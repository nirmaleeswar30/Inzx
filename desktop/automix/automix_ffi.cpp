// Inzx desktop Automix: the C API Dart reaches over FFI.
//
// The same calls Android's JNI bridges make into BitChord's native code
// (android/app/src/main/cpp/jni), plus ONNX Runtime for the two models and
// the blend renderer. Arrays the library returns are malloc'd; Dart frees
// them with ax_free.
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include <onnxruntime_cxx_api.h>

#include "analyzer/audio_analysis.h"
#include "analyzer/mel_spectrogram.h"
#include "analyzer/resampler.h"
#include "analyzer/vocal_spectrogram.h"
#include "blend_renderer.h"
#include "loopmix/loop_mix_renderer.h"

#if defined(_WIN32)
#include <windows.h>
#define AX_API extern "C" __declspec(dllexport)
#elif defined(__APPLE__)
// iOS links this statically into the app; `used` keeps the linker from
// dropping functions only Dart's FFI lookup (by name) calls.
#define AX_API extern "C" __attribute__((visibility("default"), used))
#else
#define AX_API extern "C" __attribute__((visibility("default")))
#endif

namespace {

thread_local std::string lastError;

template <typename T>
T* copyOut(const T* data, size_t count) {
  T* out = static_cast<T*>(std::malloc(std::max<size_t>(count, 1) * sizeof(T)));
  if (out != nullptr && count > 0) std::memcpy(out, data, count * sizeof(T));
  return out;
}

char* copyString(const std::string& value) {
  char* out = static_cast<char*>(std::malloc(value.size() + 1));
  if (out != nullptr) std::memcpy(out, value.c_str(), value.size() + 1);
  return out;
}

// ---- JSON, exactly as analysis_jni.cpp writes it ---------------------------

void AppendString(std::string& out, const std::string& value) {
  out += '"';
  for (const char character : value) {
    if (character >= 32 && character < 127 && character != '"' && character != '\\') out += character;
  }
  out += '"';
}

void AppendNumber(std::string& out, double value) {
  if (!(value == value) || value > 1e308 || value < -1e308) {
    out += "null";
    return;
  }
  char buffer[32];
  std::snprintf(buffer, sizeof(buffer), "%.6g", value);
  out += buffer;
}

void AppendDoubles(std::string& out, const std::vector<double>& values) {
  out += '[';
  for (size_t index = 0; index < values.size(); ++index) {
    if (index > 0) out += ',';
    AppendNumber(out, values[index]);
  }
  out += ']';
}

void AppendEnergyCurve(std::string& out, const std::vector<bitchord::smart::EnergyPoint>& points) {
  out += '[';
  for (size_t index = 0; index < points.size(); ++index) {
    if (index > 0) out += ',';
    out += "{\"t\":";
    AppendNumber(out, points[index].time);
    out += ",\"e\":";
    AppendNumber(out, points[index].energy);
    out += '}';
  }
  out += ']';
}

void AppendCuePoints(std::string& out, const std::vector<bitchord::smart::MixCuePoint>& points) {
  out += '[';
  for (size_t index = 0; index < points.size(); ++index) {
    if (index > 0) out += ',';
    out += "{\"t\":";
    AppendNumber(out, points[index].time);
    out += ",\"s\":";
    AppendNumber(out, points[index].score);
    out += ",\"y\":";
    AppendString(out, points[index].type);
    out += '}';
  }
  out += ']';
}

void AppendField(std::string& out, const char* name, double value, bool first = false) {
  if (!first) out += ',';
  out += '"';
  out += name;
  out += "\":";
  AppendNumber(out, value);
}

// ---- ONNX Runtime -----------------------------------------------------------

Ort::Env& ortEnv() {
  static Ort::Env env(ORT_LOGGING_LEVEL_WARNING, "inzx-automix");
  return env;
}

#if defined(_WIN32)
std::wstring widen(const char* utf8) {
  const int length = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, nullptr, 0);
  std::wstring wide(size_t(std::max(length, 1)), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8, -1, wide.data(), length);
  if (!wide.empty() && wide.back() == L'\0') wide.pop_back();
  return wide;
}
#endif

struct AxModel {
  std::unique_ptr<Ort::Session> session;
  std::string inputName;
  std::vector<std::string> outputNames;
};

}  // namespace

// ---- Memory -------------------------------------------------------------------

AX_API void ax_free(void* pointer) { std::free(pointer); }

AX_API const char* ax_last_error() { return lastError.c_str(); }

// ---- Analysis (analysis_jni.cpp) -----------------------------------------------

AX_API char* ax_analyze(const float* samples, int64_t count, double sampleRate, double duration) {
  std::vector<float> input(samples, samples + std::max<int64_t>(count, 0));
  const bitchord::smart::AnalysisResult result =
      bitchord::smart::AnalyzeAudio(input, sampleRate, duration);
  std::string json;
  json.reserve(8192 + result.energy_curve.size() * 24);
  json += '{';
  AppendField(json, "duration", result.duration, true);
  AppendField(json, "bpm", result.bpm);
  AppendField(json, "beatInterval", result.beat_interval);
  AppendField(json, "firstBeat", result.first_beat);
  AppendField(json, "beatConfidence", result.beat_confidence);
  AppendField(json, "keyConfidence", result.key_confidence);
  AppendField(json, "audibleStartTime", result.audible_start_time);
  AppendField(json, "pickupTime", result.pickup_time);
  AppendField(json, "introEndTime", result.intro_end_time);
  AppendField(json, "outroStartTime", result.outro_start_time);
  AppendField(json, "contentEndTime", result.content_end_time);
  AppendField(json, "mixInTime", result.mix_in_time);
  AppendField(json, "mixOutTime", result.mix_out_time);
  AppendField(json, "vocalProbability", result.vocal_probability);
  json += ",\"key\":";
  AppendString(json, result.key);
  json += ",\"downbeats\":";
  AppendDoubles(json, result.downbeats);
  json += ",\"phraseBoundaries\":";
  AppendDoubles(json, result.phrase_boundaries);
  json += ",\"vocalActivityMask\":";
  AppendDoubles(json, result.vocal_activity_mask);
  json += ",\"energyCurve\":";
  AppendEnergyCurve(json, result.energy_curve);
  json += ",\"lowEnergyCurve\":";
  AppendEnergyCurve(json, result.low_energy_curve);
  json += ",\"mixInCandidates\":";
  AppendCuePoints(json, result.mix_in_candidates);
  json += ",\"mixOutCandidates\":";
  AppendCuePoints(json, result.mix_out_candidates);
  json += '}';
  return copyString(json);
}

AX_API double ax_analysis_sample_rate() { return 11025.0; }

AX_API int64_t ax_resample(const float* samples, int64_t count, double inputRate, double outputRate, float** out) {
  std::vector<float> input(samples, samples + std::max<int64_t>(count, 0));
  const std::vector<float> resampled = bitchord::smart::Resample(input, inputRate, outputRate);
  *out = copyOut(resampled.data(), resampled.size());
  return int64_t(resampled.size());
}

// ---- Model front ends (mel_jni.cpp, vocal_jni.cpp) ---------------------------

AX_API int64_t ax_beat_spectrogram(const float* samples, int64_t count, double sampleRate, float** out) {
  std::vector<float> input(samples, samples + std::max<int64_t>(count, 0));
  const auto spectrogram = bitchord::smart::ComputeBeatSpectrogram(input, sampleRate);
  *out = copyOut(spectrogram.values.data(), spectrogram.values.size());
  return int64_t(spectrogram.values.size());
}

AX_API int ax_beat_mels() { return int(bitchord::smart::kBeatSpectrogramMels); }
AX_API double ax_beat_sample_rate() { return bitchord::smart::kBeatSpectrogramSampleRate; }
AX_API int ax_beat_hop() { return int(bitchord::smart::kBeatSpectrogramHop); }

AX_API int64_t ax_vocal_spectrogram(const float* left, const float* right, int64_t count, double sampleRate,
                                    float** out) {
  std::vector<std::vector<float>> channels(2);
  channels[0].assign(left, left + std::max<int64_t>(count, 0));
  channels[1].assign(right, right + std::max<int64_t>(count, 0));
  const auto spectrogram = bitchord::smart::ComputeVocalSpectrogram(channels, sampleRate);
  *out = copyOut(spectrogram.values.data(), spectrogram.values.size());
  return int64_t(spectrogram.values.size());
}

AX_API int ax_vocal_bins() { return int(bitchord::smart::kVocalSpectrogramBins); }
AX_API double ax_vocal_sample_rate() { return bitchord::smart::kVocalSpectrogramSampleRate; }
AX_API int ax_vocal_hop() { return int(bitchord::smart::kVocalSpectrogramHop); }
AX_API int ax_vocal_fft() { return int(bitchord::smart::kVocalSpectrogramFft); }

// ---- ONNX Runtime -----------------------------------------------------------

/// Opens [path] (UTF-8) with BitChord's session options. Null on failure;
/// ax_last_error says why.
AX_API void* ax_model_open(const char* path, int threads) {
  try {
    Ort::SessionOptions options;
    options.SetIntraOpNumThreads(threads > 0 ? threads : 1);
    options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
    // As BitChord: no arena or memory patterns, since analysis runs a few
    // times per track and holding tens of megabytes between runs isn't worth it.
    options.DisableCpuMemArena();
    options.DisableMemPattern();
#if defined(_WIN32)
    const std::wstring widePath = widen(path);
    auto session = std::make_unique<Ort::Session>(ortEnv(), widePath.c_str(), options);
#else
    auto session = std::make_unique<Ort::Session>(ortEnv(), path, options);
#endif
    auto model = std::make_unique<AxModel>();
    Ort::AllocatorWithDefaultOptions allocator;
    model->inputName = session->GetInputNameAllocated(0, allocator).get();
    const size_t outputs = session->GetOutputCount();
    for (size_t i = 0; i < outputs; ++i) {
      model->outputNames.emplace_back(session->GetOutputNameAllocated(i, allocator).get());
    }
    model->session = std::move(session);
    return model.release();
  } catch (const std::exception& e) {
    lastError = e.what();
    return nullptr;
  }
}

AX_API void ax_model_close(void* handle) { delete static_cast<AxModel*>(handle); }

/// Runs the model on one float tensor. Writes up to [maxOutputs] float
/// outputs (malloc'd) and their element counts; returns how many, or -1.
AX_API int ax_model_run(void* handle, const float* data, const int64_t* shape, int rank, int maxOutputs,
                        float** outputs, int64_t* counts) {
  auto* model = static_cast<AxModel*>(handle);
  if (model == nullptr || !model->session) return -1;
  try {
    size_t elements = 1;
    for (int i = 0; i < rank; ++i) elements *= size_t(shape[i]);
    Ort::MemoryInfo memory = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    Ort::Value input = Ort::Value::CreateTensor<float>(memory, const_cast<float*>(data), elements, shape,
                                                       size_t(rank));
    const char* inputName = model->inputName.c_str();
    std::vector<const char*> outputNames;
    for (const auto& name : model->outputNames) outputNames.push_back(name.c_str());
    auto results = model->session->Run(Ort::RunOptions{nullptr}, &inputName, &input, 1, outputNames.data(),
                                       outputNames.size());
    const int produced = int(std::min<size_t>(results.size(), size_t(std::max(maxOutputs, 0))));
    for (int i = 0; i < produced; ++i) {
      const size_t count = results[i].GetTensorTypeAndShapeInfo().GetElementCount();
      outputs[i] = copyOut(results[i].GetTensorData<float>(), count);
      counts[i] = int64_t(count);
    }
    return produced;
  } catch (const std::exception& e) {
    lastError = e.what();
    return -1;
  }
}

// ---- Loop mix (loopmix_jni.cpp) ------------------------------------------------

using bitchord::loopmix::Deck;
using bitchord::loopmix::Envelope;
using bitchord::loopmix::Renderer;

namespace {
Deck* loopDeck(void* handle, int index) {
  if (handle == nullptr || index < 0 || index > 1) return nullptr;
  return &static_cast<Renderer*>(handle)->deck(index);
}
}  // namespace

AX_API void* ax_loop_create(int sampleRate) { return new (std::nothrow) Renderer(sampleRate); }
AX_API void ax_loop_destroy(void* handle) { delete static_cast<Renderer*>(handle); }

AX_API void ax_loop_set_deck(void* handle, int index, const float* left, const float* right, int64_t frames,
                             double regionStart, int64_t loopStart, int64_t loopEnd, double releaseAt,
                             const double* knotFrames, const double* knotPositions, int knots, int runOn,
                             double stopAt, double preroll, float level) {
  Deck* deck = loopDeck(handle, index);
  if (deck == nullptr) return;
  deck->left.assign(left, left + frames);
  deck->right.assign(right, right + frames);
  deck->regionStart = regionStart;
  deck->loopStart = loopStart;
  deck->loopEnd = loopEnd;
  deck->releaseAt = releaseAt;
  deck->knotTimes.assign(knotFrames, knotFrames + knots);
  deck->knotPositions.assign(knotPositions, knotPositions + knots);
  deck->runOn = runOn != 0;
  deck->stopAt = stopAt;
  deck->preroll = preroll;
  deck->level = level;
}

AX_API void ax_loop_set_envelope(void* handle, int index, int kind, const double* times, const float* values,
                                 int points, int exponential) {
  Deck* deck = loopDeck(handle, index);
  if (deck == nullptr) return;
  Envelope* envelope = kind == 0 ? &deck->gain : kind == 1 ? &deck->lowDb : kind == 2 ? &deck->highPassHz : nullptr;
  if (envelope == nullptr) return;
  envelope->times.assign(times, times + points);
  envelope->values.assign(values, values + points);
  envelope->exponential = exponential != 0;
}

AX_API void ax_loop_prepare(void* handle) {
  if (handle != nullptr) static_cast<Renderer*>(handle)->prepare();
}

AX_API int64_t ax_loop_first_frame(void* handle) {
  return handle != nullptr ? static_cast<Renderer*>(handle)->firstFrame() : 0;
}

AX_API void ax_loop_render(void* handle, int64_t frame, float* interleaved, int frames) {
  if (handle != nullptr && frames > 0) static_cast<Renderer*>(handle)->render(frame, interleaved, frames);
}

/// Renders the prepared loop mix's first [frames] mix frames (from mix frame
/// 0, its pre-roll discarded) to a float WAV at [path]. 1 on success.
AX_API int ax_loop_render_file(void* handle, const char* path, int64_t frames) {
  auto* renderer = static_cast<Renderer*>(handle);
  if (renderer == nullptr || path == nullptr || frames <= 0) return 0;
  std::FILE* file = inzx::automix::OpenFloatWav(path, renderer->sampleRate(), frames);
  if (file == nullptr) return 0;
  constexpr int kBlock = 1024;
  std::vector<float> block(kBlock * 2);
  bool ok = true;
  for (int64_t frame = std::min<int64_t>(0, renderer->firstFrame()); frame < frames && ok;) {
    const int count = int(std::min<int64_t>(kBlock, frames - frame));
    renderer->render(frame, block.data(), count);
    const int skip = frame < 0 ? int(std::min<int64_t>(count, -frame)) : 0;
    const size_t samples = size_t(count - skip) * 2;
    if (samples > 0 && std::fwrite(block.data() + skip * 2, sizeof(float), samples, file) != samples) ok = false;
    frame += count;
  }
  ok = std::fclose(file) == 0 && ok;
  return ok ? 1 : 0;
}

AX_API double ax_loop_heard(void* handle, int index) {
  Deck* deck = loopDeck(handle, index);
  return deck != nullptr ? deck->heard.load() : 0.0;
}

// ---- Blend renderer --------------------------------------------------------------

using inzx::automix::BlendDeck;
using inzx::automix::BlendRenderer;

namespace {
BlendDeck* blendDeck(void* handle, int index) {
  if (handle == nullptr || index < 0 || index > 1) return nullptr;
  return &static_cast<BlendRenderer*>(handle)->deck(index);
}
}  // namespace

AX_API void* ax_blend_create(int sampleRate) { return new (std::nothrow) BlendRenderer(sampleRate); }
AX_API void ax_blend_destroy(void* handle) { delete static_cast<BlendRenderer*>(handle); }

AX_API void ax_blend_set_deck(void* handle, int index, const float* left, const float* right, int64_t frames,
                              double startSample, double rate, double stopAt, float level, float echoSeconds) {
  BlendDeck* deck = blendDeck(handle, index);
  if (deck == nullptr) return;
  deck->left.assign(left, left + frames);
  deck->right.assign(right, right + frames);
  deck->startSample = startSample;
  deck->rate = rate > 0 ? rate : 1.0;
  deck->stopAt = stopAt;
  deck->level = level;
  deck->echoSeconds = echoSeconds;
}

/// kind: 0 gain, 1 low-pass Hz, 2 high-pass Hz, 3 echo send, 4 echo dry;
/// deck -1 sets the mix's headroom trim.
AX_API void ax_blend_set_envelope(void* handle, int index, int kind, const float* values, int points,
                                  double step) {
  if (handle == nullptr) return;
  inzx::automix::Envelope* envelope = nullptr;
  if (index == -1) {
    envelope = &static_cast<BlendRenderer*>(handle)->headroom();
  } else if (BlendDeck* deck = blendDeck(handle, index)) {
    envelope = kind == 0   ? &deck->gain
               : kind == 1 ? &deck->lowPassHz
               : kind == 2 ? &deck->highPassHz
               : kind == 3 ? &deck->echoSend
               : kind == 4 ? &deck->echoDry
                           : nullptr;
  }
  if (envelope == nullptr) return;
  envelope->values.assign(values, values + std::max(points, 0));
  envelope->step = step > 0 ? step : 0.01;
  envelope->exponential = kind == 1 || kind == 2;
}

/// Renders [frames] to a float WAV at [path] (UTF-8). 1 on success.
AX_API int ax_blend_render(void* handle, const char* path, int64_t frames) {
  if (handle == nullptr || path == nullptr) return 0;
  return static_cast<BlendRenderer*>(handle)->renderToFile(path, frames) ? 1 : 0;
}
