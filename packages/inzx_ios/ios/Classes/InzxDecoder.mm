// Automix's decoder on iOS: a region of a local audio file to float PCM,
// through AVAssetReader. The Dart side (IosPcmDecoder) calls it over FFI from
// its analysis and render isolates; desktop does the same through libmpv.
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version.

#import <AVFoundation/AVFoundation.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <vector>

#define INZX_API extern "C" __attribute__((visibility("default"), used))

namespace {

/// One pass of an AVAssetReader over `track`, keeping the frames that fall
/// in [from, end) by each buffer's presentation time. `ranged` also sets the
/// reader's timeRange, which is quicker but unreliable on YouTube's
/// fragmented MP4 (it can start late, or yield nothing), so the caller
/// falls back to an unranged pass. Frames before the first one delivered
/// are zero-filled, so index 0 of `pcm` is always `from`.
bool ReadPass(AVURLAsset *asset, AVAssetTrack *track, NSDictionary *settings, double from, double end,
              bool ranged, int32_t rate, int32_t channels, std::vector<float> &pcm) {
  pcm.clear();
  NSError *error = nil;
  AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:&error];
  if (reader == nil) return false;
  AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track
                                                                                outputSettings:settings];
  output.alwaysCopiesSampleData = NO;
  if (![reader canAddOutput:output]) return false;
  [reader addOutput:output];
  if (ranged) {
    // Half a second early: the reader may start a little after the asked time.
    const double lead = std::max(0.0, from - 0.5);
    CMTime startTime = CMTimeMakeWithSeconds(lead, 48000);
    CMTime duration = end > from ? CMTimeMakeWithSeconds(end - lead, 48000) : kCMTimePositiveInfinity;
    reader.timeRange = CMTimeRangeMake(startTime, duration);
  }
  if (![reader startReading]) return false;

  const int64_t first = static_cast<int64_t>(std::llround(from * rate));
  const int64_t last = end > from ? static_cast<int64_t>(std::llround(end * rate)) : INT64_MAX;
  int64_t next = -1;  // where the following buffer starts, when one has no time
  std::vector<float> chunk;
  while (true) {
    CMSampleBufferRef buffer = [output copyNextSampleBuffer];
    if (buffer == nullptr) break;
    const CMTime pts = CMSampleBufferGetPresentationTimeStamp(buffer);
    CMBlockBufferRef block = CMSampleBufferGetDataBuffer(buffer);
    const int64_t frames =
        block == nullptr ? 0 : static_cast<int64_t>(CMBlockBufferGetDataLength(block) / sizeof(float) / channels);
    int64_t at;
    if (CMTIME_IS_NUMERIC(pts)) {
      at = static_cast<int64_t>(std::llround(CMTimeGetSeconds(pts) * rate));
    } else {
      at = next >= 0 ? next : 0;
    }
    next = at + frames;
    if (frames > 0 && at + frames > first && at < last) {
      chunk.resize(static_cast<size_t>(frames * channels));
      if (CMBlockBufferCopyDataBytes(block, 0, chunk.size() * sizeof(float), chunk.data()) == kCMBlockBufferNoErr) {
        const int64_t skip = std::max<int64_t>(0, first - at);
        const int64_t keep = std::min<int64_t>(frames, last - at);
        // Place by time: pad a gap before (or between) buffers with silence.
        const int64_t have = static_cast<int64_t>(pcm.size()) / channels;
        const int64_t gap = at + skip - first - have;
        if (ranged && have == 0 && gap > rate / 20) {
          // The ranged read started well after what was asked: read it all.
          CFRelease(buffer);
          [reader cancelReading];
          pcm.clear();
          return false;
        }
        if (gap > 0) pcm.insert(pcm.end(), static_cast<size_t>(gap * channels), 0.0f);
        pcm.insert(pcm.end(), chunk.begin() + skip * channels, chunk.begin() + keep * channels);
      }
    }
    CFRelease(buffer);
    if (at >= last) {
      [reader cancelReading];
      return true;
    }
  }
  return reader.status != AVAssetReaderStatusFailed;
}

}  // namespace

/// Decodes `path` from `start` to `end` seconds (`end` < 0: to the end of
/// the file) at `rate` Hz, `channels` 1 or 2 (interleaved). Writes a malloc'd
/// buffer to `*out` (freed with inzx_decode_free) and returns the frame
/// count, or -1 on failure.
INZX_API int64_t inzx_decode_region(const char *path, double start, double end, int32_t rate,
                                    int32_t channels, float **out) {
  *out = nullptr;
  if (path == nullptr || rate <= 0 || channels < 1 || channels > 2) return -1;
  @autoreleasepool {
    NSURL *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:path]];
    AVURLAsset *asset =
        [AVURLAsset URLAssetWithURL:url options:@{AVURLAssetPreferPreciseDurationAndTimingKey : @YES}];

    __block AVAssetTrack *track = nil;
    dispatch_semaphore_t loaded = dispatch_semaphore_create(0);
    [asset loadTracksWithMediaType:AVMediaTypeAudio
                 completionHandler:^(NSArray<AVAssetTrack *> *tracks, NSError *error) {
                   track = tracks.firstObject;
                   dispatch_semaphore_signal(loaded);
                 }];
    if (dispatch_semaphore_wait(loaded, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC)) != 0) return -1;
    if (track == nil) return -1;

    AudioChannelLayout layout;
    std::memset(&layout, 0, sizeof(layout));
    layout.mChannelLayoutTag = channels == 1 ? kAudioChannelLayoutTag_Mono : kAudioChannelLayoutTag_Stereo;
    NSDictionary *settings = @{
      AVFormatIDKey : @(kAudioFormatLinearPCM),
      AVLinearPCMBitDepthKey : @32,
      AVLinearPCMIsFloatKey : @YES,
      AVLinearPCMIsBigEndianKey : @NO,
      AVLinearPCMIsNonInterleaved : @NO,
      AVSampleRateKey : @(rate),
      AVNumberOfChannelsKey : @(channels),
      AVChannelLayoutKey : [NSData dataWithBytes:&layout length:sizeof(layout)],
    };

    const double from = start > 0 ? start : 0;
    std::vector<float> pcm;
    const bool region = from > 0 || end > 0;
    bool ok = region && ReadPass(asset, track, settings, from, end, true, rate, channels, pcm) && !pcm.empty();
    if (!ok) ok = ReadPass(asset, track, settings, from, end, false, rate, channels, pcm);
    if (!ok) return -1;

    const int64_t frames = static_cast<int64_t>(pcm.size() / channels);
    if (frames <= 0) return -1;
    float *copy = static_cast<float *>(std::malloc(static_cast<size_t>(frames) * channels * sizeof(float)));
    if (copy == nullptr) return -1;
    std::memcpy(copy, pcm.data(), static_cast<size_t>(frames) * channels * sizeof(float));
    *out = copy;
    return frames;
  }
}

INZX_API void inzx_decode_free(void *buffer) { std::free(buffer); }
