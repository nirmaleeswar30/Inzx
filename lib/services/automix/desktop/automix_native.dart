// Desktop Automix: Dart's way into the native side.
//
//  - inzx_automix (desktop/automix): BitChord's analysis DSP, the model front
//    ends, ONNX Runtime and the blend renderer, behind a C API.
//  - libmpv (bundled by media_kit): decoding any file or stream the player
//    can play to float PCM, faster than real time, through its PCM writer.
//
// Everything here blocks, so callers run it off the UI isolate. Each isolate
// opens the libraries for itself.

import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

/// Where the bundled native files live: next to the executable on Windows,
/// in lib/ and data/ beside it on Linux.
class AutomixPaths {
  static String get _exeDir => p.dirname(Platform.resolvedExecutable);

  static String get library => Platform.isWindows
      ? p.join(_exeDir, 'inzx_automix.dll')
      : p.join(_exeDir, 'lib', 'libinzx_automix.so');

  static String get modelsDir => p.join(_exeDir, 'data', 'automix');

  static String get beatModel => p.join(modelsDir, 'beat_this_final0_q8.onnx');
  static String get vocalModel => p.join(modelsDir, 'vocals_umxhq_int8.onnx');

  static bool get available => File(library).existsSync();
}

// ---- inzx_automix ------------------------------------------------------------

typedef _FreeC = Void Function(Pointer<Void>);
typedef _FreeD = void Function(Pointer<Void>);
typedef _AnalyzeC = Pointer<Utf8> Function(Pointer<Float>, Int64, Double, Double);
typedef _AnalyzeD = Pointer<Utf8> Function(Pointer<Float>, int, double, double);
typedef _ResampleC = Int64 Function(Pointer<Float>, Int64, Double, Double, Pointer<Pointer<Float>>);
typedef _ResampleD = int Function(Pointer<Float>, int, double, double, Pointer<Pointer<Float>>);
typedef _BeatSpecC = Int64 Function(Pointer<Float>, Int64, Double, Pointer<Pointer<Float>>);
typedef _BeatSpecD = int Function(Pointer<Float>, int, double, Pointer<Pointer<Float>>);
typedef _VocalSpecC = Int64 Function(Pointer<Float>, Pointer<Float>, Int64, Double, Pointer<Pointer<Float>>);
typedef _VocalSpecD = int Function(Pointer<Float>, Pointer<Float>, int, double, Pointer<Pointer<Float>>);
typedef _IntC = Int32 Function();
typedef _IntD = int Function();
typedef _DoubleC = Double Function();
typedef _DoubleD = double Function();
typedef _ModelOpenC = Pointer<Void> Function(Pointer<Utf8>, Int32);
typedef _ModelOpenD = Pointer<Void> Function(Pointer<Utf8>, int);
typedef _ModelRunC = Int32 Function(
    Pointer<Void>, Pointer<Float>, Pointer<Int64>, Int32, Int32, Pointer<Pointer<Float>>, Pointer<Int64>);
typedef _ModelRunD = int Function(
    Pointer<Void>, Pointer<Float>, Pointer<Int64>, int, int, Pointer<Pointer<Float>>, Pointer<Int64>);
typedef _ErrorC = Pointer<Utf8> Function();
typedef _CreateC = Pointer<Void> Function(Int32);
typedef _CreateD = Pointer<Void> Function(int);
typedef _BlendDeckC = Void Function(
    Pointer<Void>, Int32, Pointer<Float>, Pointer<Float>, Int64, Double, Double, Double, Float, Float);
typedef _BlendDeckD = void Function(
    Pointer<Void>, int, Pointer<Float>, Pointer<Float>, int, double, double, double, double, double);
typedef _BlendEnvC = Void Function(Pointer<Void>, Int32, Int32, Pointer<Float>, Int32, Double);
typedef _BlendEnvD = void Function(Pointer<Void>, int, int, Pointer<Float>, int, double);
typedef _BlendRenderC = Int32 Function(Pointer<Void>, Pointer<Utf8>, Int64);
typedef _BlendRenderD = int Function(Pointer<Void>, Pointer<Utf8>, int);
typedef _LoopDeckC = Void Function(Pointer<Void>, Int32, Pointer<Float>, Pointer<Float>, Int64, Double, Int64, Int64,
    Double, Pointer<Double>, Pointer<Double>, Int32, Int32, Double, Double, Float);
typedef _LoopDeckD = void Function(Pointer<Void>, int, Pointer<Float>, Pointer<Float>, int, double, int, int, double,
    Pointer<Double>, Pointer<Double>, int, int, double, double, double);
typedef _LoopEnvC = Void Function(Pointer<Void>, Int32, Int32, Pointer<Double>, Pointer<Float>, Int32, Int32);
typedef _LoopEnvD = void Function(Pointer<Void>, int, int, Pointer<Double>, Pointer<Float>, int, int);
typedef _HandleC = Void Function(Pointer<Void>);
typedef _HandleD = void Function(Pointer<Void>);

/// The C API of desktop/automix/automix_ffi.cpp.
class AutomixNative {
  AutomixNative._(DynamicLibrary lib)
      : _free = lib.lookupFunction<_FreeC, _FreeD>('ax_free'),
        _analyze = lib.lookupFunction<_AnalyzeC, _AnalyzeD>('ax_analyze'),
        _resample = lib.lookupFunction<_ResampleC, _ResampleD>('ax_resample'),
        _beatSpectrogram = lib.lookupFunction<_BeatSpecC, _BeatSpecD>('ax_beat_spectrogram'),
        _vocalSpectrogram = lib.lookupFunction<_VocalSpecC, _VocalSpecD>('ax_vocal_spectrogram'),
        _modelOpen = lib.lookupFunction<_ModelOpenC, _ModelOpenD>('ax_model_open'),
        _modelClose = lib.lookupFunction<_FreeC, _FreeD>('ax_model_close'),
        _modelRun = lib.lookupFunction<_ModelRunC, _ModelRunD>('ax_model_run'),
        _lastError = lib.lookupFunction<_ErrorC, _ErrorC>('ax_last_error'),
        _blendCreate = lib.lookupFunction<_CreateC, _CreateD>('ax_blend_create'),
        _blendDestroy = lib.lookupFunction<_FreeC, _FreeD>('ax_blend_destroy'),
        _blendSetDeck = lib.lookupFunction<_BlendDeckC, _BlendDeckD>('ax_blend_set_deck'),
        _blendSetEnvelope = lib.lookupFunction<_BlendEnvC, _BlendEnvD>('ax_blend_set_envelope'),
        _blendRender = lib.lookupFunction<_BlendRenderC, _BlendRenderD>('ax_blend_render'),
        _loopCreate = lib.lookupFunction<_CreateC, _CreateD>('ax_loop_create'),
        _loopDestroy = lib.lookupFunction<_FreeC, _FreeD>('ax_loop_destroy'),
        _loopSetDeck = lib.lookupFunction<_LoopDeckC, _LoopDeckD>('ax_loop_set_deck'),
        _loopSetEnvelope = lib.lookupFunction<_LoopEnvC, _LoopEnvD>('ax_loop_set_envelope'),
        _loopPrepare = lib.lookupFunction<_HandleC, _HandleD>('ax_loop_prepare'),
        _loopRenderFile = lib.lookupFunction<_BlendRenderC, _BlendRenderD>('ax_loop_render_file'),
        analysisSampleRate = lib.lookupFunction<_DoubleC, _DoubleD>('ax_analysis_sample_rate')(),
        beatMels = lib.lookupFunction<_IntC, _IntD>('ax_beat_mels')(),
        beatSampleRate = lib.lookupFunction<_DoubleC, _DoubleD>('ax_beat_sample_rate')(),
        beatHop = lib.lookupFunction<_IntC, _IntD>('ax_beat_hop')(),
        vocalBins = lib.lookupFunction<_IntC, _IntD>('ax_vocal_bins')(),
        vocalSampleRate = lib.lookupFunction<_DoubleC, _DoubleD>('ax_vocal_sample_rate')(),
        vocalHop = lib.lookupFunction<_IntC, _IntD>('ax_vocal_hop')(),
        vocalFft = lib.lookupFunction<_IntC, _IntD>('ax_vocal_fft')();

  static AutomixNative? _instance;

  /// The library for this isolate, or null where it isn't bundled.
  static AutomixNative? get instance {
    if (_instance != null) return _instance;
    if (!AutomixPaths.available) return null;
    try {
      return _instance = AutomixNative._(DynamicLibrary.open(AutomixPaths.library));
    } catch (_) {
      return null;
    }
  }

  final _FreeD _free;
  final _AnalyzeD _analyze;
  final _ResampleD _resample;
  final _BeatSpecD _beatSpectrogram;
  final _VocalSpecD _vocalSpectrogram;
  final _ModelOpenD _modelOpen;
  final _FreeD _modelClose;
  final _ModelRunD _modelRun;
  final _ErrorC _lastError;
  final _CreateD _blendCreate;
  final _FreeD _blendDestroy;
  final _BlendDeckD _blendSetDeck;
  final _BlendEnvD _blendSetEnvelope;
  final _BlendRenderD _blendRender;
  final _CreateD _loopCreate;
  final _FreeD _loopDestroy;
  final _LoopDeckD _loopSetDeck;
  final _LoopEnvD _loopSetEnvelope;
  final _HandleD _loopPrepare;
  final _BlendRenderD _loopRenderFile;

  /// TrackFeatures.sampleRate: what the whole-track DSP reads.
  final double analysisSampleRate;
  final int beatMels;
  final double beatSampleRate;
  final int beatHop;
  final int vocalBins;
  final double vocalSampleRate;
  final int vocalHop;
  final int vocalFft;

  String get lastError => _lastError().toDartString();

  /// The whole-track DSP analysis, as the JSON analysis_jni.cpp writes.
  String analyze(Float32List samples, double sampleRate, double duration) {
    return _withFloats(samples, (data) {
      final json = _analyze(data, samples.length, sampleRate, duration);
      try {
        return json.toDartString();
      } finally {
        _free(json.cast());
      }
    });
  }

  Float32List resample(Float32List samples, double inputRate, double outputRate) {
    return _withFloats(samples, (data) {
      return _takeFloats((out) => _resample(data, samples.length, inputRate, outputRate, out));
    });
  }

  /// Log-mel frames for the beat model, [beatMels] values each.
  Float32List beatSpectrogram(Float32List samples, double sampleRate) {
    return _withFloats(samples, (data) {
      return _takeFloats((out) => _beatSpectrogram(data, samples.length, sampleRate, out));
    });
  }

  /// Magnitude STFT for the vocal model: [channel][bin][frame].
  Float32List vocalSpectrogram(Float32List left, Float32List right, double sampleRate) {
    return _withFloats(left, (l) {
      return _withFloats(right, (r) {
        return _takeFloats((out) => _vocalSpectrogram(l, r, math.min(left.length, right.length), sampleRate, out));
      });
    });
  }

  /// Opens an ONNX model, or null (see [lastError]).
  AutomixModel? openModel(String path, int threads) {
    final utf8Path = path.toNativeUtf8();
    try {
      final handle = _modelOpen(utf8Path, threads);
      return handle == nullptr ? null : AutomixModel._(this, handle);
    } finally {
      malloc.free(utf8Path);
    }
  }

  Float32List _takeFloats(int Function(Pointer<Pointer<Float>> out) call) {
    final out = malloc<Pointer<Float>>();
    try {
      final count = call(out);
      final data = out.value;
      if (data == nullptr) return Float32List(0);
      final copy = Float32List.fromList(data.asTypedList(count));
      _free(data.cast());
      return copy;
    } finally {
      malloc.free(out);
    }
  }

  static T _withFloats<T>(Float32List values, T Function(Pointer<Float> data) use) {
    final data = malloc<Float>(math.max(values.length, 1));
    try {
      data.asTypedList(values.length).setAll(0, values);
      return use(data);
    } finally {
      malloc.free(data);
    }
  }
}

/// An open ONNX Runtime session over one model.
class AutomixModel {
  AutomixModel._(this._native, this._handle);

  final AutomixNative _native;
  Pointer<Void> _handle;

  /// Runs the model on one float tensor of [shape]; its float outputs, in
  /// order, or null if inference failed.
  List<Float32List>? run(Float32List input, List<int> shape, {int outputs = 2}) {
    if (_handle == nullptr) return null;
    final shapePtr = malloc<Int64>(shape.length);
    final outPtrs = malloc<Pointer<Float>>(outputs);
    final counts = malloc<Int64>(outputs);
    try {
      for (var i = 0; i < shape.length; i++) {
        shapePtr[i] = shape[i];
      }
      final produced = AutomixNative._withFloats(input, (data) {
        return _native._modelRun(_handle, data, shapePtr, shape.length, outputs, outPtrs, counts);
      });
      if (produced < 0) return null;
      return [
        for (var i = 0; i < produced; i++)
          () {
            final copy = Float32List.fromList(outPtrs[i].asTypedList(counts[i]));
            _native._free(outPtrs[i].cast());
            return copy;
          }(),
      ];
    } finally {
      malloc.free(shapePtr);
      malloc.free(outPtrs);
      malloc.free(counts);
    }
  }

  void close() {
    if (_handle == nullptr) return;
    _native._modelClose(_handle);
    _handle = nullptr;
  }
}

/// One deck of [BlendRender]: its audio, where it's heard from, its tempo.
class BlendDeckInput {
  BlendDeckInput({
    required this.left,
    required this.right,
    required this.startSample,
    this.rate = 1.0,
    this.stopAt = 1e18,
    this.level = 1.0,
    this.echoSeconds = 0.0,
    this.gain,
    this.lowPassHz,
    this.highPassHz,
    this.echoSend,
    this.echoDry,
  });

  final Float32List left;
  final Float32List right;
  final double startSample;
  final double rate;
  final double stopAt;
  final double level;
  final double echoSeconds;
  final Float32List? gain;
  final Float32List? lowPassHz;
  final Float32List? highPassHz;
  final Float32List? echoSend;
  final Float32List? echoDry;
}

/// Renders a blend to a float WAV at [path]; true on success. Blocking.
bool renderBlend({
  required String path,
  required int sampleRate,
  required int frames,
  required double envelopeStep,
  required BlendDeckInput outgoing,
  required BlendDeckInput incoming,
  Float32List? headroom,
}) {
  final native = AutomixNative.instance;
  if (native == null) return false;
  final handle = native._blendCreate(sampleRate);
  if (handle == nullptr) return false;
  try {
    void envelope(int deck, int kind, Float32List? values) {
      if (values == null || values.isEmpty) return;
      AutomixNative._withFloats(values, (data) {
        native._blendSetEnvelope(handle, deck, kind, data, values.length, envelopeStep);
      });
    }

    for (final (index, deck) in [(0, outgoing), (1, incoming)]) {
      AutomixNative._withFloats(deck.left, (l) {
        AutomixNative._withFloats(deck.right, (r) {
          native._blendSetDeck(handle, index, l, r, math.min(deck.left.length, deck.right.length),
              deck.startSample, deck.rate, deck.stopAt, deck.level, deck.echoSeconds);
        });
      });
      envelope(index, 0, deck.gain);
      envelope(index, 1, deck.lowPassHz);
      envelope(index, 2, deck.highPassHz);
      envelope(index, 3, deck.echoSend);
      envelope(index, 4, deck.echoDry);
    }
    envelope(-1, 5, headroom);
    final utf8Path = path.toNativeUtf8();
    try {
      return native._blendRender(handle, utf8Path, frames) == 1;
    } finally {
      malloc.free(utf8Path);
    }
  } finally {
    native._blendDestroy(handle);
  }
}

// ---- libmpv decoding --------------------------------------------------------------

typedef _MpvCreateC = Pointer<Void> Function();
typedef _MpvSetOptC = Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _MpvSetOptD = int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _MpvInitC = Int32 Function(Pointer<Void>);
typedef _MpvInitD = int Function(Pointer<Void>);
typedef _MpvCommandC = Int32 Function(Pointer<Void>, Pointer<Pointer<Utf8>>);
typedef _MpvCommandD = int Function(Pointer<Void>, Pointer<Pointer<Utf8>>);
typedef _MpvWaitC = Pointer<_MpvEvent> Function(Pointer<Void>, Double);
typedef _MpvWaitD = Pointer<_MpvEvent> Function(Pointer<Void>, double);
typedef _MpvDestroyC = Void Function(Pointer<Void>);
typedef _MpvDestroyD = void Function(Pointer<Void>);

final class _MpvEvent extends Struct {
  @Int32()
  external int eventId;
  @Int32()
  external int error;
  @Uint64()
  external int replyUserdata;
  external Pointer<Void> data;
}

final class _MpvEndFile extends Struct {
  @Int32()
  external int reason;
  @Int32()
  external int error;
}

/// Decoded audio: interleaved when [channels] is 2.
class DecodedAudio {
  DecodedAudio(this.samples, this.sampleRate, this.channels);
  final Float32List samples;
  final int sampleRate;
  final int channels;

  int get frames => samples.length ~/ channels;
  double get seconds => frames / sampleRate;

  Float32List channel(int index) {
    if (channels == 1) return samples;
    final out = Float32List(frames);
    for (var i = 0; i < out.length; i++) {
      out[i] = samples[i * channels + index];
    }
    return out;
  }

  Float32List mono() {
    if (channels == 1) return samples;
    final out = Float32List(frames);
    for (var i = 0; i < out.length; i++) {
      out[i] = (samples[i * 2] + samples[i * 2 + 1]) * 0.5;
    }
    return out;
  }
}

class MpvDecoder {
  MpvDecoder._(DynamicLibrary lib)
      : _create = lib.lookupFunction<_MpvCreateC, _MpvCreateC>('mpv_create'),
        _setOption = lib.lookupFunction<_MpvSetOptC, _MpvSetOptD>('mpv_set_option_string'),
        _initialize = lib.lookupFunction<_MpvInitC, _MpvInitD>('mpv_initialize'),
        _command = lib.lookupFunction<_MpvCommandC, _MpvCommandD>('mpv_command'),
        _wait = lib.lookupFunction<_MpvWaitC, _MpvWaitD>('mpv_wait_event'),
        _destroy = lib.lookupFunction<_MpvDestroyC, _MpvDestroyD>('mpv_terminate_destroy');

  static MpvDecoder? _instance;

  static MpvDecoder? get instance {
    if (_instance != null) return _instance;
    final names = Platform.isWindows
        ? [p.join(p.dirname(Platform.resolvedExecutable), 'libmpv-2.dll'), 'libmpv-2.dll']
        : ['libmpv.so.2', 'libmpv.so', 'libmpv.so.1'];
    for (final name in names) {
      try {
        return _instance = MpvDecoder._(DynamicLibrary.open(name));
      } catch (_) {}
    }
    return null;
  }

  final _MpvCreateC _create;
  final _MpvSetOptD _setOption;
  final _MpvInitD _initialize;
  final _MpvCommandD _command;
  final _MpvWaitD _wait;
  final _MpvDestroyD _destroy;

  static const _eventShutdown = 1;
  static const _eventEndFile = 7;
  static const _endReasonError = 4;

  /// Decodes [source] (a file path or URL) from [start] seconds to [end]
  /// (or the end of the file) at [sampleRate], mono or stereo. Null if mpv
  /// couldn't open or decode it. [scratch] is a writable directory.
  DecodedAudio? decode(
    String source, {
    required String scratch,
    double start = 0,
    double? end,
    int sampleRate = 48000,
    int channels = 2,
    Map<String, String> headers = const {},
  }) {
    try {
      Directory(scratch).createSync(recursive: true);
    } catch (_) {}
    final out = p.join(scratch,
        'decode_${pid}_${DateTime.now().microsecondsSinceEpoch}_${math.Random().nextInt(1 << 30)}.pcm');
    final handle = _create();
    if (handle == nullptr) return null;
    var ok = false;
    try {
      final options = <String, String>{
        'config': 'no',
        'terminal': 'no',
        'msg-level': 'all=no',
        'load-scripts': 'no',
        'ytdl': 'no',
        'vid': 'no',
        'vo': 'null',
        'audio-display': 'no',
        'ao': 'pcm',
        'ao-pcm-file': out,
        'ao-pcm-waveheader': 'no',
        'audio-format': 'float',
        'audio-channels': channels == 1 ? 'mono' : 'stereo',
        'audio-samplerate': '$sampleRate',
        'untimed': 'yes',
        'hr-seek': 'yes',
        'replaygain': 'no',
        'volume': '100',
        if (start > 0) 'start': start.toStringAsFixed(4),
        if (end != null) 'end': end.toStringAsFixed(4),
        if (headers.isNotEmpty)
          'http-header-fields': headers.entries
              .map((e) => '${e.key}: ${e.value.replaceAll(',', r'\,')}')
              .join(','),
      };
      for (final entry in options.entries) {
        final k = entry.key.toNativeUtf8();
        final v = entry.value.toNativeUtf8();
        _setOption(handle, k, v);
        malloc.free(k);
        malloc.free(v);
      }
      if (_initialize(handle) < 0) return null;
      final args = malloc<Pointer<Utf8>>(3);
      final load = 'loadfile'.toNativeUtf8();
      final target = source.toNativeUtf8();
      args[0] = load;
      args[1] = target;
      args[2] = nullptr;
      final queued = _command(handle, args);
      malloc.free(load);
      malloc.free(target);
      malloc.free(args);
      if (queued < 0) return null;
      // Decoding runs as fast as the codec goes; a minute of network for a
      // stream is the ceiling.
      final deadline = DateTime.now().add(const Duration(minutes: 2));
      while (DateTime.now().isBefore(deadline)) {
        final event = _wait(handle, 1.0);
        final id = event.ref.eventId;
        if (id == _eventShutdown) break;
        if (id == _eventEndFile) {
          final reason = event.ref.data.cast<_MpvEndFile>().ref.reason;
          ok = reason != _endReasonError;
          break;
        }
      }
    } finally {
      _destroy(handle);
    }
    final file = File(out);
    try {
      if (!ok || !file.existsSync()) return null;
      final bytes = file.readAsBytesSync();
      final usable = bytes.length - bytes.length % (4 * channels);
      if (usable <= 0) return null;
      final samples = Float32List.view(bytes.buffer, bytes.offsetInBytes, usable ~/ 4);
      return DecodedAudio(Float32List.fromList(samples), sampleRate, channels);
    } finally {
      try {
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
  }
}

// ---- The loop mix -------------------------------------------------------------

/// One deck of [renderLoopMix] (loop_mix_renderer.h's Deck).
class LoopDeckInput {
  LoopDeckInput({
    required this.left,
    required this.right,
    required this.regionStart,
    required this.loopStart,
    required this.loopEnd,
    required this.releaseAt,
    required this.knotFrames,
    required this.knotPositions,
    required this.runOn,
    required this.stopAt,
    this.preroll = 0.4,
    this.level = 1.0,
  });
  final Float32List left;
  final Float32List right;
  final double regionStart;
  final int loopStart;
  final int loopEnd;
  final double releaseAt;
  final Float64List knotFrames;
  final Float64List knotPositions;
  final bool runOn;
  final double stopAt;
  final double preroll;
  final double level;
}

/// A loop-mix envelope: values at mix-second times.
class LoopEnvelope {
  const LoopEnvelope(this.deck, this.kind, this.times, this.values, {this.exponential = false});
  static const gain = 0, lowDb = 1, highPassHz = 2;
  final int deck;
  final int kind;
  final List<double> times;
  final List<double> values;
  final bool exponential;
}

/// Renders a loop mix's first [frames] mix frames to a float WAV. Blocking.
bool renderLoopMix({
  required String path,
  required int sampleRate,
  required int frames,
  required LoopDeckInput outgoing,
  required LoopDeckInput incoming,
  required List<LoopEnvelope> envelopes,
}) {
  final native = AutomixNative.instance;
  if (native == null) return false;
  final handle = native._loopCreate(sampleRate);
  if (handle == nullptr) return false;
  final allocations = <Pointer>[];
  Pointer<Double> doubles(List<double> values) {
    final p = malloc<Double>(math.max(values.length, 1));
    p.asTypedList(values.length).setAll(0, values);
    allocations.add(p);
    return p;
  }

  Pointer<Float> floats(List<double> values) {
    final p = malloc<Float>(math.max(values.length, 1));
    final list = p.asTypedList(values.length);
    for (var i = 0; i < values.length; i++) {
      list[i] = values[i];
    }
    allocations.add(p);
    return p;
  }

  try {
    for (final (index, deck) in [(0, outgoing), (1, incoming)]) {
      final knots = math.min(deck.knotFrames.length, deck.knotPositions.length);
      native._loopSetDeck(
        handle,
        index,
        floats(deck.left),
        floats(deck.right),
        math.min(deck.left.length, deck.right.length),
        deck.regionStart,
        deck.loopStart,
        deck.loopEnd,
        deck.releaseAt,
        doubles(deck.knotFrames),
        doubles(deck.knotPositions),
        knots,
        deck.runOn ? 1 : 0,
        deck.stopAt,
        deck.preroll,
        deck.level,
      );
    }
    for (final e in envelopes) {
      final points = math.min(e.times.length, e.values.length);
      native._loopSetEnvelope(
          handle, e.deck, e.kind, doubles(e.times), floats(e.values), points, e.exponential ? 1 : 0);
    }
    native._loopPrepare(handle);
    final utf8Path = path.toNativeUtf8();
    try {
      return native._loopRenderFile(handle, utf8Path, frames) == 1;
    } finally {
      malloc.free(utf8Path);
    }
  } finally {
    for (final p in allocations) {
      malloc.free(p);
    }
    native._loopDestroy(handle);
  }
}
