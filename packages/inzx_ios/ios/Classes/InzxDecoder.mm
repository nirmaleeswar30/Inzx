// Automix's decoder on iOS: a region of a local audio file to float PCM,
// through AVAssetReader. The Dart side (IosPcmDecoder) calls it over FFI from
// its analysis and render isolates; desktop does the same through libmpv.
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version.

#import <AVFoundation/AVFoundation.h>

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <vector>

#define INZX_API extern "C" __attribute__((visibility("default"), used))

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

    NSError *error = nil;
    AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:&error];
    if (reader == nil) return -1;

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
    AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track
                                                                                  outputSettings:settings];
    output.alwaysCopiesSampleData = NO;
    if (![reader canAddOutput:output]) return -1;
    [reader addOutput:output];

    const double from = start > 0 ? start : 0;
    CMTime startTime = CMTimeMakeWithSeconds(from, 48000);
    CMTime duration = end > from ? CMTimeMakeWithSeconds(end - from, 48000) : kCMTimePositiveInfinity;
    reader.timeRange = CMTimeRangeMake(startTime, duration);
    if (![reader startReading]) return -1;

    std::vector<float> pcm;
    while (true) {
      CMSampleBufferRef buffer = [output copyNextSampleBuffer];
      if (buffer == nullptr) break;
      CMBlockBufferRef block = CMSampleBufferGetDataBuffer(buffer);
      if (block != nullptr) {
        const size_t bytes = CMBlockBufferGetDataLength(block);
        const size_t floats = bytes / sizeof(float);
        const size_t at = pcm.size();
        pcm.resize(at + floats);
        if (CMBlockBufferCopyDataBytes(block, 0, floats * sizeof(float), pcm.data() + at) != kCMBlockBufferNoErr) {
          pcm.resize(at);
        }
      }
      CFRelease(buffer);
    }
    if (reader.status == AVAssetReaderStatusFailed) return -1;

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
