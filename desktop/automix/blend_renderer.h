// Inzx desktop Automix: renders one transition offline, the way Android's
// two players and their filter chains play it live.
//
// Android blends by running both songs on their own players and riding each
// player's volume, tempo and transition filter (BitChord's
// TransitionFilterProcessor) as the blend goes. The desktop player (libmpv
// from media_kit) has no such filters, so desktop renders the blend instead:
// both songs' overlap is decoded, each deck stretched to its tempo, run
// through the same filter chain and echo, faded on the same curves, summed,
// and written out as one clip the spare player plays.
//
// The automation itself (fader curves, cutoffs, echo send and dry) is
// computed in Dart from BitChord's controller and handed over as envelopes;
// this file is only the DSP.
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.

#pragma once

#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

#include "signalsmith-stretch/signalsmith-stretch.h"

namespace inzx::automix {

/// Creates [path] (UTF-8) as a stereo 32-bit float WAV of [frames] frames,
/// header written, ready for the samples. Null if it can't be created.
std::FILE* OpenFloatWav(const std::string& path, int sampleRate, int64_t frames);

/// Values every [step] seconds from t = 0; linear (or log, for cutoffs)
/// between them, held past either end.
struct Envelope {
  std::vector<float> values;
  double step = 0.01;
  bool exponential = false;

  bool empty() const { return values.empty(); }
  float at(double seconds) const;
};

/// BitChord's TransitionFilterProcessor: a 24 dB/octave Butterworth low-pass
/// and high-pass (two SVF stages each) whose cutoffs glide in the log domain,
/// then the feedback echo for an echo out.
class TransitionFilter {
 public:
  static constexpr float kOpenHz = 20000.f;
  static constexpr float kOffHz = 20.f;
  static constexpr float kMaxHighPassHz = 2000.f;

  void configure(int sampleRate);
  void setCutoffs(float lowPassHz, float highPassHz);
  void setEcho(float delaySeconds, float send, float dry);
  /// Stereo, in place.
  void process(float* left, float* right, int frames);

 private:
  static constexpr int kStages = 2;
  static constexpr int kGlideFrames = 64;

  void filter(float* left, float* right, int frames);
  void echo(float* left, float* right, int frames);
  float glide(float current, float target) const;
  float usable(float hz) const;
  void updateLow();
  void updateHigh();
  float lowPass(int channel, float x);
  float highPass(int channel, float x);

  int sampleRate_ = 0;
  float targetLow_ = kOpenHz, targetHigh_ = kOffHz;
  float currentLow_ = kOpenHz, currentHigh_ = kOffHz;
  float lowState_[2 * kStages * 2] = {};
  float highState_[2 * kStages * 2] = {};
  float lowA1_[kStages] = {}, lowA2_[kStages] = {}, lowA3_[kStages] = {};
  float highA1_[kStages] = {}, highA2_[kStages] = {}, highA3_[kStages] = {}, highK_[kStages] = {};

  bool echoEngaged_ = false;
  float echoSeconds_ = 0.f;
  float echoTargetSend_ = 0.f, echoTargetDry_ = 1.f;
  float echoSend_ = 0.f, echoDry_ = 1.f;
  std::vector<float> echoRing_;
  int echoDelayFrames_ = 0;
  int echoPosition_ = 0;
  float echoLow_[2] = {}, echoHigh_[2] = {};
  float echoLowCoefficient_ = 0.f, echoHighCoefficient_ = 0.f;
};

struct BlendDeck {
  /// Decoded stereo audio of this song around the blend, and which of its
  /// samples is heard at the blend's first output frame.
  std::vector<float> left;
  std::vector<float> right;
  double startSample = 0;
  /// Input samples per output sample: the beatmatch stretch, constant
  /// through the blend.
  double rate = 1.0;
  /// Output seconds after which this deck renders nothing.
  double stopAt = 1e18;
  /// Loudness matching between the two songs.
  float level = 1.f;
  float echoSeconds = 0.f;

  Envelope gain;
  Envelope lowPassHz;
  Envelope highPassHz;
  Envelope echoSend;
  Envelope echoDry;

  // Render state.
  signalsmith::stretch::SignalsmithStretch<float> stretch;
  TransitionFilter filter;
  double readPos = 0;
  bool started = false;
};

class BlendRenderer {
 public:
  explicit BlendRenderer(int sampleRate) : sampleRate_(sampleRate) {}

  BlendDeck& deck(int index) { return decks_[index]; }
  /// Applied to the sum: keeps two faders at full from clipping.
  Envelope& headroom() { return headroom_; }

  /// Renders [frames] stereo frames to a 32-bit float WAV at [path].
  /// Returns false if the file couldn't be written.
  bool renderToFile(const std::string& path, int64_t frames);

 private:
  static constexpr int kBlock = 1024;
  static constexpr int kControlFrames = 64;

  void renderDeck(BlendDeck& deck, int64_t frame, int frames, float* outLeft, float* outRight);

  int sampleRate_;
  BlendDeck decks_[2];
  Envelope headroom_;
  std::vector<float> inLeft_, inRight_, outLeft_, outRight_;
};

}  // namespace inzx::automix
