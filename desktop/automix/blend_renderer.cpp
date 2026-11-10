// Inzx desktop Automix: offline blend renderer. See blend_renderer.h.
//
// TransitionFilter is BitChord's TransitionFilterProcessor
// (com.music.bitchord.playback, GPL-3.0) moved to C++ unchanged in
// behaviour: same filter topology, glide, constants and echo.
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.

#include "blend_renderer.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>

#if defined(_WIN32)
#include <windows.h>
#endif

namespace inzx::automix {

namespace {

constexpr double kPi = 3.14159265358979323846;

// TransitionFilterProcessor's constants.
constexpr float kMinHz = 10.f;
constexpr float kGlideRate = 0.05f;
constexpr float kSettledHz = 1.f;
constexpr float kMaxCutoffFraction = 0.45f;
constexpr float kButterworthQ[2] = {0.54120f, 1.30656f};
constexpr float kEchoFeedback = 0.4f;
constexpr float kEchoWet = 0.5f;
constexpr float kEchoLowPassHz = 3500.f;
constexpr float kEchoHighPassHz = 250.f;
constexpr float kMaxEchoSeconds = 1.f;

float onePole(float hz, int sampleRate) {
  return sampleRate <= 0 ? 0.f : float(1.0 - std::exp(-2.0 * kPi * hz / sampleRate));
}

}  // namespace

// ---- Envelope ----------------------------------------------------------------

float Envelope::at(double seconds) const {
  if (values.empty()) return 0.f;
  if (values.size() == 1 || seconds <= 0) return values.front();
  const double position = seconds / step;
  const size_t index = size_t(position);
  if (index + 1 >= values.size()) return values.back();
  const float a = values[index];
  const float b = values[index + 1];
  const double fraction = position - double(index);
  if (exponential && a > 0 && b > 0) {
    return float(std::exp(std::log(a) + (std::log(b) - std::log(a)) * fraction));
  }
  return float(a + (b - a) * fraction);
}

// ---- TransitionFilter --------------------------------------------------------

void TransitionFilter::configure(int sampleRate) {
  sampleRate_ = sampleRate;
  currentLow_ = targetLow_;
  currentHigh_ = targetHigh_;
  std::memset(lowState_, 0, sizeof(lowState_));
  std::memset(highState_, 0, sizeof(highState_));
  echoLowCoefficient_ = onePole(kEchoLowPassHz, sampleRate);
  echoHighCoefficient_ = onePole(kEchoHighPassHz, sampleRate);
}

void TransitionFilter::setCutoffs(float lowPassHz, float highPassHz) {
  targetLow_ = std::clamp(lowPassHz, kMinHz, kOpenHz);
  targetHigh_ = std::clamp(highPassHz, kOffHz, kMaxHighPassHz);
}

void TransitionFilter::setEcho(float delaySeconds, float send, float dry) {
  if (!echoEngaged_ || delaySeconds != echoSeconds_) {
    echoSeconds_ = delaySeconds;
    echoDelayFrames_ = int(std::clamp(delaySeconds, 0.f, kMaxEchoSeconds) * sampleRate_);
    echoRing_.assign(size_t(std::max(0, echoDelayFrames_)) * 2, 0.f);
    echoPosition_ = 0;
    echoLow_[0] = echoLow_[1] = 0.f;
    echoHigh_[0] = echoHigh_[1] = 0.f;
    echoSend_ = 0.f;
    echoDry_ = 1.f;
  }
  echoTargetSend_ = std::clamp(send, 0.f, 1.f);
  echoTargetDry_ = std::clamp(dry, 0.f, 1.f);
  echoEngaged_ = true;
}

void TransitionFilter::process(float* left, float* right, int frames) {
  if (frames <= 0 || sampleRate_ <= 0) return;
  filter(left, right, frames);
  if (echoEngaged_) echo(left, right, frames);
}

float TransitionFilter::glide(float current, float target) const {
  const float from = std::log(std::max(current, kMinHz));
  const float to = std::log(std::max(target, kMinHz));
  return std::exp(from + (to - from) * kGlideRate);
}

float TransitionFilter::usable(float hz) const {
  return std::clamp(hz, kMinHz, sampleRate_ * kMaxCutoffFraction);
}

void TransitionFilter::updateLow() {
  const float g = float(std::tan(kPi * usable(currentLow_) / sampleRate_));
  for (int stage = 0; stage < kStages; ++stage) {
    const float k = 1.f / kButterworthQ[stage];
    const float a1 = 1.f / (1.f + g * (g + k));
    lowA1_[stage] = a1;
    lowA2_[stage] = g * a1;
    lowA3_[stage] = g * (g * a1);
  }
}

void TransitionFilter::updateHigh() {
  const float g = float(std::tan(kPi * usable(currentHigh_) / sampleRate_));
  for (int stage = 0; stage < kStages; ++stage) {
    const float k = 1.f / kButterworthQ[stage];
    const float a1 = 1.f / (1.f + g * (g + k));
    highA1_[stage] = a1;
    highA2_[stage] = g * a1;
    highA3_[stage] = g * (g * a1);
    highK_[stage] = k;
  }
}

float TransitionFilter::lowPass(int channel, float input) {
  float value = input;
  for (int stage = 0; stage < kStages; ++stage) {
    const int i = (channel * kStages + stage) * 2;
    const float ic1 = lowState_[i];
    const float ic2 = lowState_[i + 1];
    const float v3 = value - ic2;
    const float v1 = lowA1_[stage] * ic1 + lowA2_[stage] * v3;
    const float v2 = ic2 + lowA2_[stage] * ic1 + lowA3_[stage] * v3;
    lowState_[i] = 2.f * v1 - ic1;
    lowState_[i + 1] = 2.f * v2 - ic2;
    value = v2;
  }
  return value;
}

float TransitionFilter::highPass(int channel, float input) {
  float value = input;
  for (int stage = 0; stage < kStages; ++stage) {
    const int i = (channel * kStages + stage) * 2;
    const float ic1 = highState_[i];
    const float ic2 = highState_[i + 1];
    const float v3 = value - ic2;
    const float v1 = highA1_[stage] * ic1 + highA2_[stage] * v3;
    const float v2 = ic2 + highA2_[stage] * ic1 + highA3_[stage] * v3;
    highState_[i] = 2.f * v1 - ic1;
    highState_[i + 1] = 2.f * v2 - ic2;
    value -= highK_[stage] * v1 + v2;
  }
  return value;
}

void TransitionFilter::filter(float* left, float* right, int frames) {
  const bool parked = targetLow_ >= kOpenHz && targetHigh_ <= kOffHz &&
                      currentLow_ >= kOpenHz - kSettledHz && currentHigh_ <= kOffHz + kSettledHz;
  if (parked) {
    std::memset(lowState_, 0, sizeof(lowState_));
    std::memset(highState_, 0, sizeof(highState_));
    return;
  }
  int offset = 0;
  while (offset < frames) {
    const int count = std::min(kGlideFrames, frames - offset);
    currentLow_ = glide(currentLow_, targetLow_);
    currentHigh_ = glide(currentHigh_, targetHigh_);
    const bool lowOn = currentLow_ < kOpenHz - kSettledHz;
    const bool highOn = currentHigh_ > kOffHz + kSettledHz;
    if (lowOn) updateLow();
    if (highOn) updateHigh();
    for (int f = offset; f < offset + count; ++f) {
      float l = left[f];
      float r = right[f];
      if (lowOn) {
        l = lowPass(0, l);
        r = lowPass(1, r);
      }
      if (highOn) {
        l = highPass(0, l);
        r = highPass(1, r);
      }
      left[f] = l;
      right[f] = r;
    }
    offset += count;
  }
}

void TransitionFilter::echo(float* left, float* right, int frames) {
  const float sendStep = (echoTargetSend_ - echoSend_) / frames;
  const float dryStep = (echoTargetDry_ - echoDry_) / frames;
  float send = echoSend_;
  float dry = echoDry_;
  const int delay = echoDelayFrames_;
  if (delay <= 0) {
    for (int f = 0; f < frames; ++f) {
      dry += dryStep;
      left[f] *= dry;
      right[f] *= dry;
    }
  } else {
    float* channels[2] = {left, right};
    for (int f = 0; f < frames; ++f) {
      send += sendStep;
      dry += dryStep;
      const int ringBase = echoPosition_ * 2;
      for (int c = 0; c < 2; ++c) {
        const float input = channels[c][f];
        const float delayed = echoRing_[ringBase + c];
        const float darker = echoLow_[c] + echoLowCoefficient_ * (delayed - echoLow_[c]);
        echoLow_[c] = darker;
        const float rumble = echoHigh_[c] + echoHighCoefficient_ * (darker - echoHigh_[c]);
        echoHigh_[c] = rumble;
        echoRing_[ringBase + c] = input * send + (darker - rumble) * kEchoFeedback;
        channels[c][f] = input * dry + delayed * kEchoWet;
      }
      if (++echoPosition_ == delay) echoPosition_ = 0;
    }
  }
  echoSend_ = echoTargetSend_;
  echoDry_ = echoTargetDry_;
}

// ---- BlendRenderer -----------------------------------------------------------

namespace {

inline float sampleAt(const std::vector<float>& channel, int64_t index) {
  return index >= 0 && index < int64_t(channel.size()) ? channel[size_t(index)] : 0.f;
}

bool isUnity(double rate) { return std::abs(rate - 1.0) < 1e-6; }

// UTF-8 paths, which plain fopen misreads on Windows.
std::FILE* openForWrite(const std::string& path) {
#if defined(_WIN32)
  const int length = MultiByteToWideChar(CP_UTF8, 0, path.c_str(), -1, nullptr, 0);
  if (length <= 0) return nullptr;
  std::wstring wide(size_t(length), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, path.c_str(), -1, wide.data(), length);
  return _wfopen(wide.c_str(), L"wb");
#else
  return std::fopen(path.c_str(), "wb");
#endif
}

void writeU32(std::FILE* file, uint32_t value) { std::fwrite(&value, 4, 1, file); }
void writeU16(std::FILE* file, uint16_t value) { std::fwrite(&value, 2, 1, file); }

}  // namespace

std::FILE* OpenFloatWav(const std::string& path, int sampleRate, int64_t frames) {
  std::FILE* file = openForWrite(path);
  if (file == nullptr) return nullptr;
  const uint32_t dataBytes = uint32_t(frames * 2 * sizeof(float));
  std::fwrite("RIFF", 1, 4, file);
  writeU32(file, 4 + 26 + 12 + 8 + dataBytes);
  std::fwrite("WAVE", 1, 4, file);
  std::fwrite("fmt ", 1, 4, file);
  writeU32(file, 18);
  writeU16(file, 3);  // IEEE float
  writeU16(file, 2);
  writeU32(file, uint32_t(sampleRate));
  writeU32(file, uint32_t(sampleRate) * 2 * 4);
  writeU16(file, 8);
  writeU16(file, 32);
  writeU16(file, 0);
  std::fwrite("fact", 1, 4, file);
  writeU32(file, 4);
  writeU32(file, uint32_t(frames));
  std::fwrite("data", 1, 4, file);
  writeU32(file, dataBytes);
  return file;
}

void BlendRenderer::renderDeck(BlendDeck& deck, int64_t frame, int frames, float* outLeft, float* outRight) {
  const double sr = sampleRate_;
  const double blockStart = frame / sr;
  if (blockStart >= deck.stopAt || deck.left.empty()) {
    std::fill(outLeft, outLeft + frames, 0.f);
    std::fill(outRight, outRight + frames, 0.f);
    return;
  }

  if (isUnity(deck.rate)) {
    const int64_t first = int64_t(std::llround(deck.startSample)) + frame;
    for (int i = 0; i < frames; ++i) {
      outLeft[i] = sampleAt(deck.left, first + i);
      outRight[i] = sampleAt(deck.right, first + i);
    }
  } else {
    // As BitChord's loop-mix decks drive Signalsmith: seeded with its read
    // pointer the stretch's own latency ahead of what is heard, then fed
    // exactly the input that keeps the heard position on the tempo line.
    const double inLatency = deck.stretch.inputLatency();
    const double outLatency = deck.stretch.outputLatency();
    if (!deck.started) {
      const double heard = deck.startSample + frame * deck.rate;
      const int seekLength = deck.stretch.seekLength();
      if (int(inLeft_.size()) < seekLength) {
        inLeft_.resize(seekLength);
        inRight_.resize(seekLength);
      }
      const int64_t first = int64_t(std::llround(heard + inLatency + deck.rate * outLatency)) - seekLength;
      for (int i = 0; i < seekLength; ++i) {
        inLeft_[i] = sampleAt(deck.left, first + i);
        inRight_[i] = sampleAt(deck.right, first + i);
      }
      float* seekInput[2] = {inLeft_.data(), inRight_.data()};
      deck.stretch.reset();
      deck.stretch.seek(seekInput, seekLength, deck.rate);
      deck.readPos = double(first + seekLength);
      deck.started = true;
    }
    const double heardEnd = deck.startSample + (frame + frames) * deck.rate;
    const double readEnd = heardEnd + inLatency + deck.rate * outLatency;
    int inputSamples = int(std::floor(readEnd - deck.readPos));
    inputSamples = std::clamp(inputSamples, 0, frames * 8);
    if (int(inLeft_.size()) < inputSamples) {
      inLeft_.resize(inputSamples);
      inRight_.resize(inputSamples);
    }
    const int64_t readFrom = int64_t(deck.readPos);
    for (int i = 0; i < inputSamples; ++i) {
      inLeft_[i] = sampleAt(deck.left, readFrom + i);
      inRight_[i] = sampleAt(deck.right, readFrom + i);
    }
    deck.readPos += inputSamples;
    float* input[2] = {inLeft_.data(), inRight_.data()};
    float* output[2] = {outLeft, outRight};
    deck.stretch.process(input, inputSamples, output, frames);
  }

  // The filter chain and fader, in control blocks; the fader ramps per sample.
  for (int at = 0; at < frames; at += kControlFrames) {
    const int count = std::min(kControlFrames, frames - at);
    const double t0 = (frame + at) / sr;
    const double t1 = (frame + at + count) / sr;
    const double mid = (t0 + t1) / 2;
    const float low = deck.lowPassHz.empty() ? TransitionFilter::kOpenHz : deck.lowPassHz.at(mid);
    const float high = deck.highPassHz.empty() ? TransitionFilter::kOffHz : deck.highPassHz.at(mid);
    deck.filter.setCutoffs(low, high);
    if (!deck.echoSend.empty()) {
      const float send = deck.echoSend.at(t1);
      const float dry = deck.echoDry.empty() ? 1.f : deck.echoDry.at(t1);
      // Left alone until the beat that feeds it, as on Android.
      if (send > 0.f || dry < 1.f) deck.filter.setEcho(deck.echoSeconds, send, dry);
    }
    deck.filter.process(outLeft + at, outRight + at, count);
    const float g0 = (deck.gain.empty() ? 1.f : deck.gain.at(t0)) * deck.level;
    const float g1 = (deck.gain.empty() ? 1.f : deck.gain.at(t1)) * deck.level;
    for (int i = 0; i < count; ++i) {
      const float g = g0 + (g1 - g0) * (float(i) / count);
      outLeft[at + i] *= g;
      outRight[at + i] *= g;
    }
  }
}

bool BlendRenderer::renderToFile(const std::string& path, int64_t frames) {
  if (frames <= 0) return false;
  std::FILE* file = OpenFloatWav(path, sampleRate_, frames);
  if (file == nullptr) return false;

  for (BlendDeck& deck : decks_) {
    deck.stretch.presetDefault(2, float(sampleRate_));
    deck.filter.configure(sampleRate_);
    deck.started = false;
  }

  // Render from a little before the first frame so a stretched deck's
  // pre-roll has played out by the time it is heard.
  int64_t frame = -int64_t(std::ceil(0.25 * sampleRate_));
  std::vector<float> mixLeft(kBlock), mixRight(kBlock);
  outLeft_.resize(kBlock);
  outRight_.resize(kBlock);
  std::vector<float> interleaved(kBlock * 2);
  bool ok = true;
  while (frame < frames && ok) {
    const int count = int(std::min<int64_t>(kBlock, frames - frame));
    std::fill(mixLeft.begin(), mixLeft.begin() + count, 0.f);
    std::fill(mixRight.begin(), mixRight.begin() + count, 0.f);
    for (BlendDeck& deck : decks_) {
      renderDeck(deck, frame, count, outLeft_.data(), outRight_.data());
      for (int i = 0; i < count; ++i) {
        mixLeft[i] += outLeft_[i];
        mixRight[i] += outRight_[i];
      }
    }
    // Only frames at or after the clip's start are written.
    const int skip = frame < 0 ? int(std::min<int64_t>(count, -frame)) : 0;
    int written = 0;
    for (int i = skip; i < count; ++i) {
      const float trim = headroom_.empty() ? 1.f : headroom_.at((frame + i) / double(sampleRate_));
      interleaved[written * 2] = mixLeft[i] * trim;
      interleaved[written * 2 + 1] = mixRight[i] * trim;
      ++written;
    }
    if (written > 0 && std::fwrite(interleaved.data(), sizeof(float), size_t(written) * 2, file) !=
                           size_t(written) * 2) {
      ok = false;
    }
    frame += count;
  }
  ok = std::fclose(file) == 0 && ok;
  return ok;
}

}  // namespace inzx::automix
