// The iOS side of Inzx's equaliser, AutoEQ and loudness normalization: one
// MTAudioProcessingTap per AVPlayerItem, running the same RBJ biquads as
// Android's ParametricEqProcessor (and desktop's lavfi chain).
//
// Settings arrive from Dart (IosAudioDsp) on the main thread and are
// published as an immutable spec through an atomic shared_ptr; each tap
// re-derives its coefficients for its own sample rate when the spec changes,
// on the render thread, without locking. The tap sits after the mix's own
// effects (post-effects): BitChord-iOS measured ~0.25 s start latency there
// against ~0.45 s before them.

#import "InzxDsp.h"

#import <MediaToolbox/MediaToolbox.h>

#include <atomic>
#include <cmath>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

namespace {

struct FilterSpec {
  int type;  // 0 peaking, 1 low shelf, 2 high shelf, 3 low pass, 4 high pass
  double f;
  double g;
  double q;
};

struct ChainSpec {
  std::vector<FilterSpec> filters;
  double preampDb = 0;
  uint64_t version = 0;
  bool isFlat() const { return filters.empty() && std::fabs(preampDb) < 0.01; }
};

struct Coeffs {
  double b0, b1, b2, a1, a2;
};

// RBJ cookbook, as ParametricEqProcessor.kt computes it.
Coeffs Design(const FilterSpec &s, double sampleRate) {
  const double nyquist = sampleRate * 0.49;
  const double f = std::min(std::max(s.f, 10.0), nyquist);
  const double w = 2.0 * M_PI * f / sampleRate;
  const double cs = std::cos(w);
  const double alpha = std::sin(w) / (2.0 * std::max(s.q, 0.05));
  const double a = std::pow(10.0, s.g / 40.0);
  double b0, b1, b2, a0, a1, a2;
  switch (s.type) {
    case 1: {  // low shelf
      const double k = 2 * std::sqrt(a) * alpha;
      b0 = a * ((a + 1) - (a - 1) * cs + k);
      b1 = 2 * a * ((a - 1) - (a + 1) * cs);
      b2 = a * ((a + 1) - (a - 1) * cs - k);
      a0 = (a + 1) + (a - 1) * cs + k;
      a1 = -2 * ((a - 1) + (a + 1) * cs);
      a2 = (a + 1) + (a - 1) * cs - k;
      break;
    }
    case 2: {  // high shelf
      const double k = 2 * std::sqrt(a) * alpha;
      b0 = a * ((a + 1) + (a - 1) * cs + k);
      b1 = -2 * a * ((a - 1) + (a + 1) * cs);
      b2 = a * ((a + 1) + (a - 1) * cs - k);
      a0 = (a + 1) - (a - 1) * cs + k;
      a1 = 2 * ((a - 1) - (a + 1) * cs);
      a2 = (a + 1) - (a - 1) * cs - k;
      break;
    }
    case 3:  // low pass
      b0 = (1 - cs) / 2; b1 = 1 - cs; b2 = (1 - cs) / 2;
      a0 = 1 + alpha; a1 = -2 * cs; a2 = 1 - alpha;
      break;
    case 4:  // high pass
      b0 = (1 + cs) / 2; b1 = -(1 + cs); b2 = (1 + cs) / 2;
      a0 = 1 + alpha; a1 = -2 * cs; a2 = 1 - alpha;
      break;
    default:  // peaking
      b0 = 1 + alpha * a; b1 = -2 * cs; b2 = 1 - alpha * a;
      a0 = 1 + alpha / a; a1 = -2 * cs; a2 = 1 - alpha / a;
      break;
  }
  return {b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0};
}

// One shared, versioned spec. Written on the main thread, read lock-free.
std::shared_ptr<const ChainSpec> gSpec = std::make_shared<ChainSpec>();
std::atomic<uint64_t> gSpecVersion{0};

std::shared_ptr<const ChainSpec> CurrentSpec() { return std::atomic_load(&gSpec); }

// Per-player gain, looked up once per tap and then read atomically.
struct PlayerGain {
  std::atomic<float> gain{1.0f};
};
std::mutex gGainsLock;
std::unordered_map<std::string, std::shared_ptr<PlayerGain>> gGains;

std::shared_ptr<PlayerGain> GainFor(const std::string &playerId) {
  std::lock_guard<std::mutex> lock(gGainsLock);
  auto &slot = gGains[playerId];
  if (!slot) slot = std::make_shared<PlayerGain>();
  return slot;
}

std::atomic<int64_t> gFrames{0};
std::atomic<double> gLastRate{0};

// Everything one tap needs. Owned by the tap (freed in finalize).
struct TapContext {
  std::shared_ptr<PlayerGain> gain;
  double sampleRate = 0;
  UInt32 channels = 0;
  bool isFloat = false;
  bool nonInterleaved = false;
  uint64_t builtVersion = UINT64_MAX;
  double preamp = 1.0;
  bool flat = true;
  std::vector<Coeffs> coeffs;
  // Direct form 1 state: per filter, per channel: x1 x2 y1 y2.
  std::vector<double> state;

  void Rebuild() {
    auto spec = CurrentSpec();
    builtVersion = spec->version;
    flat = spec->isFlat();
    preamp = std::pow(10.0, spec->preampDb / 20.0);
    coeffs.clear();
    if (sampleRate > 0) {
      for (const auto &f : spec->filters) coeffs.push_back(Design(f, sampleRate));
    }
    state.assign(coeffs.size() * std::max<UInt32>(channels, 1) * 4, 0.0);
  }

  void ProcessChannel(float *samples, UInt32 frames, UInt32 stride, UInt32 channel, float gain) {
    const size_t n = coeffs.size();
    for (UInt32 i = 0; i < frames; i++) {
      double x = samples[i * stride];
      for (size_t k = 0; k < n; k++) {
        const Coeffs &c = coeffs[k];
        double *st = &state[(k * channels + channel) * 4];
        const double y = c.b0 * x + c.b1 * st[0] + c.b2 * st[1] - c.a1 * st[2] - c.a2 * st[3];
        st[1] = st[0];
        st[0] = x;
        st[3] = st[2];
        st[2] = y;
        x = y;
      }
      samples[i * stride] = static_cast<float>(x * gain);
    }
  }
};

void TapInit(MTAudioProcessingTapRef tap, void *clientInfo, void **tapStorageOut) {
  *tapStorageOut = clientInfo;
}

void TapFinalize(MTAudioProcessingTapRef tap) {
  delete static_cast<TapContext *>(MTAudioProcessingTapGetStorage(tap));
}

void TapPrepare(MTAudioProcessingTapRef tap, CMItemCount maxFrames,
                const AudioStreamBasicDescription *format) {
  auto *ctx = static_cast<TapContext *>(MTAudioProcessingTapGetStorage(tap));
  ctx->sampleRate = format->mSampleRate;
  ctx->channels = format->mChannelsPerFrame;
  ctx->isFloat = (format->mFormatFlags & kAudioFormatFlagIsFloat) != 0 && format->mBitsPerChannel == 32;
  ctx->nonInterleaved = (format->mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
  ctx->builtVersion = UINT64_MAX;  // rebuild on the first process call
  gLastRate.store(format->mSampleRate);
}

void TapUnprepare(MTAudioProcessingTapRef tap) {}

void TapProcess(MTAudioProcessingTapRef tap, CMItemCount numberFrames,
                MTAudioProcessingTapFlags flags, AudioBufferList *bufferList,
                CMItemCount *numberFramesOut, MTAudioProcessingTapFlags *flagsOut) {
  OSStatus status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferList, flagsOut,
                                                       nullptr, numberFramesOut);
  if (status != noErr) return;
  auto *ctx = static_cast<TapContext *>(MTAudioProcessingTapGetStorage(tap));
  if (!ctx->isFloat) return;  // only Float32 PCM is processed; anything else passes through
  if (ctx->builtVersion != gSpecVersion.load(std::memory_order_acquire)) ctx->Rebuild();
  const float gain = static_cast<float>(ctx->preamp) * ctx->gain->gain.load(std::memory_order_relaxed);
  const bool unityGain = std::fabs(gain - 1.0f) < 1e-6f;
  if (ctx->flat && unityGain) return;  // bit-transparent
  const UInt32 frames = static_cast<UInt32>(*numberFramesOut);
  if (ctx->nonInterleaved) {
    for (UInt32 b = 0; b < bufferList->mNumberBuffers && b < ctx->channels; b++) {
      float *data = static_cast<float *>(bufferList->mBuffers[b].mData);
      if (data) ctx->ProcessChannel(data, frames, 1, b, gain);
    }
  } else if (bufferList->mNumberBuffers > 0) {
    float *data = static_cast<float *>(bufferList->mBuffers[0].mData);
    const UInt32 ch = std::max<UInt32>(ctx->channels, 1);
    if (data) {
      for (UInt32 c = 0; c < ch; c++) ctx->ProcessChannel(data + c, frames, ch, c, gain);
    }
  }
  gFrames.fetch_add(frames, std::memory_order_relaxed);
}

}  // namespace

@implementation InzxDsp

+ (instancetype)shared {
  static InzxDsp *instance;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    instance = [[InzxDsp alloc] init];
  });
  return instance;
}

- (void)setFilters:(NSArray<NSDictionary *> *)filters preampDb:(double)preampDb {
  auto spec = std::make_shared<ChainSpec>();
  for (NSDictionary *f in filters) {
    FilterSpec s;
    s.type = [f[@"type"] intValue];
    s.f = [f[@"f"] doubleValue];
    s.g = [f[@"g"] doubleValue];
    s.q = [f[@"q"] doubleValue];
    if (s.f <= 0) continue;
    spec->filters.push_back(s);
  }
  spec->preampDb = preampDb;
  spec->version = gSpecVersion.load() + 1;
  std::atomic_store(&gSpec, std::shared_ptr<const ChainSpec>(spec));
  gSpecVersion.store(spec->version, std::memory_order_release);
}

- (void)setGain:(double)gain forPlayer:(NSString *)playerId {
  if (!(gain > 0) || !std::isfinite(gain)) gain = 1;
  GainFor(std::string(playerId.UTF8String))->gain.store(static_cast<float>(gain));
}

- (int64_t)framesProcessed {
  return gFrames.load();
}

- (double)lastSampleRate {
  return gLastRate.load();
}

- (void)attachToItem:(AVPlayerItem *)item playerId:(NSString *)playerId {
  AVAsset *asset = item.asset;
  std::string pid(playerId.UTF8String);
  __weak AVPlayerItem *weakItem = item;
  [asset loadTracksWithMediaType:AVMediaTypeAudio
               completionHandler:^(NSArray<AVAssetTrack *> *tracks, NSError *error) {
                 AVAssetTrack *track = tracks.firstObject;
                 if (!track) return;  // HLS or a failed load: plays untapped
                 dispatch_async(dispatch_get_main_queue(), ^{
                   AVPlayerItem *strongItem = weakItem;
                   if (!strongItem || strongItem.audioMix) return;
                   AVAudioMix *mix = [InzxDsp mixForTrack:track gain:GainFor(pid)];
                   if (mix) strongItem.audioMix = mix;
                 });
               }];
}

+ (nullable AVAudioMix *)mixForTrack:(AVAssetTrack *)track gain:(std::shared_ptr<PlayerGain>)gain {
  auto *ctx = new TapContext();
  ctx->gain = gain;
  MTAudioProcessingTapCallbacks callbacks;
  callbacks.version = kMTAudioProcessingTapCallbacksVersion_0;
  callbacks.clientInfo = ctx;
  callbacks.init = TapInit;
  callbacks.finalize = TapFinalize;
  callbacks.prepare = TapPrepare;
  callbacks.unprepare = TapUnprepare;
  callbacks.process = TapProcess;
  MTAudioProcessingTapRef tap = nullptr;
  OSStatus status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
                                               kMTAudioProcessingTapCreationFlag_PostEffects, &tap);
  if (status != noErr || !tap) {
    delete ctx;
    return nil;
  }
  AVMutableAudioMixInputParameters *params =
      [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:track];
  params.audioTapProcessor = tap;
  CFRelease(tap);
  AVMutableAudioMix *mix = [AVMutableAudioMix audioMix];
  mix.inputParameters = @[ params ];
  return mix;
}

@end
