// Desktop Automix: measures tracks the way BitChord's TrackAnalyzer does.
//
// Ported from com.music.bitchord.playback.smart (TrackAnalyzer's whole-track
// pass, BeatTracker and VocalTracker; GPL-3.0). Android decodes with
// MediaCodec; desktop decodes with the libmpv the player already ships.
// The DSP and both models are BitChord's own, run natively (automix_native).
//
// Desktop only ever analyses a complete file — the player downloads the
// whole YouTube copy for analysis — so Android's provisional head pass, which
// exists to get ahead of a download in progress, has no counterpart here.
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'automix_native.dart';
import 'track_analysis.dart';
import 'transition_policy.dart' show heuristicVocalOnModelScale;

/// TrackAnalyzer's constants.
const double _neutralVocal = 0.2;
const int _headModelWindows = 2;
const int _tailModelWindows = 3;
const double _windowOverlapSeconds = 1.0;
const double _minDecodedFraction = 0.95;

/// BeatTracker's.
const int _chunkFrames = 1500;
const int _borderFrames = 6;
const int _peakWindow = 7;
const int _minBeats = 8;
const double _minTempo = 40.0;
const double _maxTempo = 220.0;

/// VocalTracker's.
const int _vocalFixedFrames = 960;
const double _vocalLowHz = 200.0;
const double _vocalHighHz = 4000.0;
const int _vocalChannels = 2;

/// Decode rate for everything: YouTube's Opus is 48 kHz already.
const int _decodeRate = 48000;

class DesktopTrackAnalyzer {
  DesktopTrackAnalyzer({required this.storeDir, required this.scratchDir, required this.threads});

  /// Where finished analyses are kept, so a track is measured once.
  final String storeDir;
  /// Where decodes write their PCM.
  final String scratchDir;
  /// Inference threads, from Automix's performance mode.
  int Function() threads;

  final Map<String, TrackAnalysis> _results = {};
  final Set<String> _running = {};
  final Set<String> _restoreAttempted = {};
  final Map<String, String> _audio = {};
  final List<_Job> _queue = [];
  bool _working = false;
  bool stopped = false;

  /// Fires when an analysis lands.
  final StreamController<String> _landed = StreamController.broadcast();
  Stream<String> get landed => _landed.stream;

  TrackAnalysis analysisFor(String trackId) => _results[trackId] ?? TrackAnalysis(trackId: trackId);
  bool isAnalysed(String trackId) => _results.containsKey(trackId);
  bool isAnalysing(String trackId) => _running.contains(trackId);
  bool hasAudio(String trackId) => _audio.containsKey(trackId);
  String? audioFor(String trackId) => _audio[trackId];

  /// A complete audio file for [trackId] that analysis may read.
  void registerAudio(String trackId, String path) => _audio[trackId] = path;

  /// Queues [trackId] if it isn't measured or being measured. Cheap to
  /// repeat. Returns false when there's no audio to read yet.
  bool request(String trackId, double durationSeconds) {
    if (trackId.isEmpty || stopped) return true;
    _restoreOnce(trackId);
    if (_results[trackId]?.isUsable == true || _running.contains(trackId)) return true;
    final path = _audio[trackId];
    if (path == null) return false;
    if (_results.containsKey(trackId)) return true; // measured, unusable: once is enough
    _running.add(trackId);
    _queue.add(_Job(trackId, path, durationSeconds));
    _pump();
    return true;
  }

  Future<void> _pump() async {
    if (_working) return;
    _working = true;
    try {
      while (_queue.isNotEmpty) {
        final job = _queue.removeAt(0);
        if (stopped) {
          _running.remove(job.trackId);
          continue;
        }
        final stored = _results[job.trackId];
        if (stored != null && stored.isUsable) {
          _running.remove(job.trackId);
          continue;
        }
        TrackAnalysis? result;
        try {
          final args = _AnalyzeArgs(
            trackId: job.trackId,
            path: job.path,
            duration: job.duration,
            scratch: scratchDir,
            threads: threads(),
          );
          final reply = jsonDecode(await Isolate.run(() => _analyzeInIsolate(args))) as Map<String, Object?>;
          final json = reply['a'];
          if (json is Map<String, Object?>) result = TrackAnalysis.fromJson(json);
          final why = reply['why'];
          if (why != null) debugPrint('Automix: ${job.trackId}: $why');
        } catch (e) {
          debugPrint('Automix: analysis of ${job.trackId} failed: $e');
        }
        _running.remove(job.trackId);
        // Recorded ready-but-empty on failure so it isn't retried every tick.
        final landed = result ??
            TrackAnalysis(status: TrackAnalysis.statusReady, trackId: job.trackId, duration: job.duration);
        _results[job.trackId] = landed;
        if (landed.isUsable) unawaited(_save(job.trackId, landed));
        _landed.add(job.trackId);
        debugPrint('Automix: analysed ${job.trackId} bpm=${landed.bpm.toStringAsFixed(1)} '
            'conf=${landed.beatConfidence.toStringAsFixed(2)} key=${landed.key} '
            'grid=${landed.headBeats != null || landed.tailBeats != null ? 'model' : 'dsp'}');
      }
    } finally {
      _working = false;
    }
  }

  // ---- The store ----------------------------------------------------------

  String _fileFor(String trackId) =>
      p.join(storeDir, '${trackId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.json');

  void _restoreOnce(String trackId) {
    if (_results.containsKey(trackId) || !_restoreAttempted.add(trackId)) return;
    final file = File(_fileFor(trackId));
    if (!file.existsSync()) return;
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      if (json['v'] != _storeVersion) return;
      _results.putIfAbsent(trackId, () => TrackAnalysis.fromJson(json['a'] as Map<String, Object?>));
    } catch (_) {}
  }

  static const _storeVersion = 1;

  Future<void> _save(String trackId, TrackAnalysis analysis) async {
    try {
      await Directory(storeDir).create(recursive: true);
      final file = File(_fileFor(trackId));
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(jsonEncode({'v': _storeVersion, 'a': analysis.toJson()}));
      await temporary.rename(file.path);
    } catch (_) {}
  }
}

class _Job {
  _Job(this.trackId, this.path, this.duration);
  final String trackId;
  final String path;
  final double duration;
}

class _AnalyzeArgs {
  const _AnalyzeArgs({
    required this.trackId,
    required this.path,
    required this.duration,
    required this.scratch,
    required this.threads,
  });
  final String trackId;
  final String path;
  final double duration;
  final String scratch;
  final int threads;
}

// ---- The pass itself, in its own isolate -------------------------------------

/// The analysis as JSON under `a`, and under `why` what stopped it short.
String _analyzeInIsolate(_AnalyzeArgs args) {
  final native = AutomixNative.instance;
  final decoder = MpvDecoder.instance;
  if (native == null || decoder == null) {
    return jsonEncode({'why': 'native library ${native == null ? 'missing' : 'ok'}, '
        'libmpv ${decoder == null ? 'missing' : 'ok'}'});
  }
  final pass = _WholeTrack(native, decoder, args);
  final analysis = pass.run();
  return jsonEncode({'a': analysis?.toJson(), 'why': pass.why});
}

class _Region {
  _Region({
    required this.grid,
    required this.vocalMask,
    required this.seconds,
    required this.start,
    this.vocalWindow,
    this.levelWindow,
  });
  final _Grid? grid;
  final List<double>? vocalMask;
  final double seconds;
  final double start;
  final CurveWindow? vocalWindow;
  final CurveWindow? levelWindow;
}

class _Grid {
  _Grid({
    required this.beats,
    required this.downbeats,
    required this.bpm,
    required this.beatInterval,
    required this.firstBeat,
    required this.beatConfidence,
  });
  final List<double> beats;
  final List<double> downbeats;
  final double bpm;
  final double beatInterval;
  final double firstBeat;
  final double beatConfidence;
}

class _WholeTrack {
  _WholeTrack(this.native, this.decoder, this.args);

  final AutomixNative native;
  final MpvDecoder decoder;
  final _AnalyzeArgs args;
  AutomixModel? _beatModel;
  AutomixModel? _vocalModel;
  bool _beatTried = false;
  bool _vocalTried = false;
  /// What cut the pass short, for the log.
  String? why;

  double get _vocalFrameRate => native.vocalSampleRate / native.vocalHop;
  double get _melFrameRate => native.beatSampleRate / native.beatHop;

  TrackAnalysis? run() {
    try {
      return _analyze();
    } finally {
      _beatModel?.close();
      _vocalModel?.close();
    }
  }

  TrackAnalysis? _analyze() {
    // Pass 1: the whole track at the DSP's own rate.
    final whole = decoder.decode(args.path, scratch: args.scratch, sampleRate: _decodeRate, channels: 1);
    if (whole == null) {
      why = 'could not decode ${args.path}';
      return null;
    }
    // Callers often don't know the duration yet (a queue row before it
    // plays). Android then reads the container's; the full decode's length
    // is the same thing here. Nothing readable: skip, store nothing.
    var duration = args.duration;
    if (!duration.isFinite || duration <= 0) {
      duration = whole.seconds;
      if (duration <= 1) {
        why = 'no readable duration';
        return null;
      }
    }
    if (whole.seconds < duration * _minDecodedFraction) {
      why = 'decoded ${whole.seconds.toStringAsFixed(1)}s of ${duration.toStringAsFixed(1)}s; refused';
      return null;
    }
    final structural = native.resample(whole.samples, _decodeRate.toDouble(), native.analysisSampleRate);
    if (structural.isEmpty) {
      why = 'resample produced nothing';
      return null;
    }
    final features = TrackFeatures.parse(native.analyze(structural, native.analysisSampleRate, duration));
    if (features == null) {
      why = 'DSP analysis unreadable';
      return TrackAnalysis(status: TrackAnalysis.statusReady, trackId: args.trackId, duration: duration);
    }
    if (features.bpm <= 0) why = 'DSP found no tempo';

    // Pass 2: both models over the opening and the ending.
    final span = (_vocalFixedFrames - 2) * native.vocalHop / native.vocalSampleRate;
    final headEnd = math.min(duration, _headModelWindows * span - (_headModelWindows - 1) * _windowOverlapSeconds);
    final tailStart =
        math.max(0.0, duration - (_tailModelWindows * span - (_tailModelWindows - 1) * _windowOverlapSeconds));
    final regions = <_Region>[];
    for (final (from, to) in _modelWindows(headEnd, tailStart, duration, span)) {
      final region = _region(from, to, features);
      if (region != null) regions.add(region);
    }

    final beats = _seamBeats(regions);
    final headSide = _beatSide(beats, 0.0, headEnd);
    final tailSide = _beatSide(beats, tailStart, duration);
    final headGrid = headSide == null ? null : _toGrid(headSide);
    final tailGrid = tailSide == null ? null : _toGrid(tailSide);
    final leading = tailGrid ?? headGrid;

    final modelDownbeats = [...?headGrid?.downbeats, ...?tailGrid?.downbeats];
    final masks = [for (final r in regions) ?r.vocalMask];
    return TrackAnalysis(
      status: TrackAnalysis.statusReady,
      trackId: args.trackId,
      duration: duration,
      contentEndTime: features.contentEndTime > 0 ? features.contentEndTime : duration,
      bpm: leading?.bpm ?? features.bpm,
      beatInterval: leading?.beatInterval ?? features.beatInterval,
      beatConfidence: leading?.beatConfidence ?? features.beatConfidence,
      downbeats: (modelDownbeats.isEmpty ? [...features.downbeats] : modelDownbeats)..sort(),
      firstBeat: headGrid?.firstBeat ?? features.firstBeat,
      phraseBoundaries: features.phraseBoundaries,
      key: features.key,
      keyConfidence: features.keyConfidence,
      audibleStartTime: features.audibleStartTime,
      pickupTime: features.pickupTime,
      introEndTime: features.introEndTime,
      outroStartTime: features.outroStartTime,
      mixInTime: features.mixInTime,
      mixOutTime: features.mixOutTime,
      mixInCandidates: features.mixInCandidates,
      mixOutCandidates: features.mixOutCandidates,
      energyCurve: features.energyCurve,
      lowEnergyCurve: features.lowEnergyCurve,
      vocalActivityMask: _mergeMasks(features.energyCurve.length, masks) ??
          [for (final v in features.vocalActivityMask) heuristicVocalOnModelScale(v)],
      vocalProbability: features.vocalProbability,
      headBeats: headSide,
      tailBeats: tailSide,
      vocalWindows: [for (final r in regions) ?r.vocalWindow],
      levelWindows: [for (final r in regions) ?r.levelWindow],
    );
  }

  List<(double, double)> _modelWindows(double headEnd, double tailStart, double duration, double span) {
    final spans = tailStart <= headEnd ? [(0.0, duration)] : [(0.0, headEnd), (tailStart, duration)];
    final windows = <(double, double)>[];
    for (final (from, to) in spans) {
      final length = to - from;
      if (length < 1.0) continue;
      if (length <= span) {
        windows.add((from, to));
        continue;
      }
      final count = ((length - _windowOverlapSeconds) / (span - _windowOverlapSeconds) - 1e-6).ceil();
      final stride = (length - span) / (count - 1);
      for (var index = 0; index < count; index++) {
        final start = from + index * stride;
        windows.add((start, math.min(to, start + span)));
      }
    }
    return windows;
  }

  _Region? _region(double start, double end, TrackFeatures features) {
    final stereo = decoder.decode(args.path,
        scratch: args.scratch, start: start, end: end, sampleRate: _decodeRate, channels: 2);
    if (stereo == null || stereo.frames < _decodeRate) return null;
    final seconds = stereo.seconds;
    final left = stereo.channel(0);
    final right = stereo.channel(1);
    final mono = stereo.mono();
    final forModel = native.resample(mono, _decodeRate.toDouble(), native.beatSampleRate);
    final vocalValues = _vocalValues(left, right);
    return _Region(
      grid: forModel.isEmpty ? null : _trackBeats(forModel, start),
      vocalMask: vocalValues == null ? null : _vocalMask(vocalValues, features, start),
      seconds: seconds,
      start: start,
      vocalWindow: vocalValues == null ? null : CurveWindow(start, _vocalFrameRate, vocalValues),
      levelWindow: _levelCurve(left, right, start),
    );
  }

  CurveWindow? _levelCurve(Float32List left, Float32List right, double start) {
    final frame = (_decodeRate / levelFrameRate).floor();
    final count = left.length ~/ frame;
    if (count <= 0) return null;
    final values = Float32List(count);
    for (var index = 0; index < count; index++) {
      var sum = 0.0;
      var n = 0;
      for (var sample = index * frame; sample < index * frame + frame; sample += 4) {
        final mixed = (left[sample] + right[sample]) * 0.5;
        sum += mixed * mixed;
        n++;
      }
      values[index] = levelFromRms(math.sqrt(sum / n));
    }
    return CurveWindow(start, levelFrameRate, values);
  }

  // ---- Beat This! (BeatTracker) ------------------------------------------

  _Grid? _trackBeats(Float32List pcm, double offsetSeconds) {
    final values = native.beatSpectrogram(pcm, native.beatSampleRate);
    final mels = native.beatMels;
    final frames = values.length ~/ mels;
    if (frames == 0) return null;
    if (!_beatTried) {
      _beatTried = true;
      _beatModel = native.openModel(AutomixPaths.beatModel, args.threads);
      if (_beatModel == null) debugPrint('Automix: beat model unavailable: ${native.lastError}');
    }
    final model = _beatModel;
    if (model == null) return null;

    final beatLogits = Float32List(frames);
    final downbeatLogits = Float32List(frames);
    const stride = _chunkFrames - 2 * _borderFrames;
    var start = 0;
    while (start < frames) {
      final length = math.min(_chunkFrames, frames - start);
      if (length <= 2 * _borderFrames && start > 0) break;
      final chunk = Float32List.sublistView(values, start * mels, (start + length) * mels);
      final outputs = model.run(Float32List.fromList(chunk), [1, length, mels]);
      if (outputs == null || outputs.length < 2) return null;
      final beat = outputs[0];
      final downbeat = outputs[1];
      final keepFrom = start == 0 ? 0 : _borderFrames;
      final keepTo = start + length >= frames ? length : length - _borderFrames;
      for (var index = keepFrom; index < keepTo; index++) {
        final target = start + index;
        if (target >= beatLogits.length) break;
        beatLogits[target] = beat[index];
        downbeatLogits[target] = downbeat[index];
      }
      if (start + length >= frames) break;
      start += stride;
    }

    final fps = _melFrameRate;
    final beatFrames = pickPeaks(beatLogits);
    final beats = [for (final f in beatFrames) f / fps + offsetSeconds];
    if (beats.length < _minBeats) return null;
    final bpm = tempoFromBeats(beats);
    if (bpm <= 0) return null;
    final downbeats = {
      for (final f in pickPeaks(downbeatLogits))
        () {
          final time = f / fps + offsetSeconds;
          var best = beats.first;
          for (final b in beats) {
            if ((b - time).abs() < (best - time).abs()) best = b;
          }
          return best;
        }(),
    }.toList()
      ..sort();
    return _Grid(
      beats: beats,
      downbeats: downbeats,
      bpm: bpm,
      beatInterval: 60 / bpm,
      firstBeat: beats.first,
      beatConfidence: gridConfidence(beats, [
        for (final f in beatFrames)
          () {
            final i = f.round();
            return i >= 0 && i < beatLogits.length ? beatLogits[i].toDouble() : 0.0;
          }(),
      ]),
    );
  }

  // ---- open-unmix (VocalTracker) -----------------------------------------

  Float32List? _vocalValues(Float32List left, Float32List right) {
    final maxSeconds = (_vocalFixedFrames - 2) * native.vocalHop / native.vocalSampleRate;
    final maxSamples = math.min((maxSeconds * _decodeRate).floor(), left.length);
    if (maxSamples <= 0) return null;
    final l = maxSamples < left.length ? Float32List.sublistView(left, 0, maxSamples) : left;
    final r = maxSamples < right.length ? Float32List.sublistView(right, 0, maxSamples) : right;
    final rl = native.resample(Float32List.fromList(l), _decodeRate.toDouble(), native.vocalSampleRate);
    final rr = native.resample(Float32List.fromList(r), _decodeRate.toDouble(), native.vocalSampleRate);
    if (rl.isEmpty || rl.length != rr.length) return null;
    final spectrogram = native.vocalSpectrogram(rl, rr, native.vocalSampleRate);
    final bins = native.vocalBins;
    final frames = spectrogram.length ~/ (_vocalChannels * bins);
    if (frames <= 0 || frames > _vocalFixedFrames) return null;
    if (!_vocalTried) {
      _vocalTried = true;
      _vocalModel = native.openModel(AutomixPaths.vocalModel, args.threads);
      if (_vocalModel == null) debugPrint('Automix: vocal model unavailable: ${native.lastError}');
    }
    final model = _vocalModel;
    if (model == null) return null;

    // [channel][bin][frame], padded out to the graph's fixed frame count.
    final input = Float32List(_vocalChannels * bins * _vocalFixedFrames);
    for (var channel = 0; channel < _vocalChannels; channel++) {
      for (var bin = 0; bin < bins; bin++) {
        final from = (channel * bins + bin) * frames;
        final to = (channel * bins + bin) * _vocalFixedFrames;
        input.setRange(to, to + frames, spectrogram, from);
      }
    }
    final outputs = model.run(input, [1, _vocalChannels, bins, _vocalFixedFrames], outputs: 1);
    if (outputs == null || outputs.isEmpty) return null;
    final target = outputs[0];

    final lowBin = math.max(0, (_vocalLowHz * native.vocalFft / native.vocalSampleRate).floor());
    final highBin = math.min(bins - 1, (_vocalHighHz * native.vocalFft / native.vocalSampleRate).ceil());
    if (highBin <= lowBin) return null;
    final curve = Float32List(frames);
    for (var frame = 0; frame < frames; frame++) {
      var sum = 0.0;
      var count = 0;
      for (var channel = 0; channel < _vocalChannels; channel++) {
        for (var bin = lowBin; bin <= highBin; bin++) {
          final index = (channel * bins + bin) * _vocalFixedFrames + frame;
          final mix = input[index];
          if (mix <= 1e-6) continue;
          sum += (target[index] / mix).clamp(0.0, 1.0);
          count++;
        }
      }
      curve[frame] = count > 0 ? sum / count : 0.0;
    }
    return curve;
  }

  List<double>? _vocalMask(Float32List values, TrackFeatures features, double start) {
    final curve = features.energyCurve;
    if (curve.isEmpty) return null;
    final mask = List<double>.filled(curve.length, _neutralVocal);
    for (var index = 0; index < curve.length; index++) {
      final frame = ((curve[index].time - start) * _vocalFrameRate).toInt();
      if (frame >= 0 && frame < values.length) mask[index] = values[frame].toDouble();
    }
    return mask;
  }

  List<double>? _mergeMasks(int size, List<List<double>> masks) {
    if (size <= 0 || masks.isEmpty) return null;
    final merged = List<double>.filled(size, _neutralVocal);
    for (final source in masks) {
      for (var index = 0; index < merged.length; index++) {
        if (index < source.length && source[index] != _neutralVocal) merged[index] = source[index];
      }
    }
    return merged;
  }

  // ---- Stitching the windows -------------------------------------------------

  ({List<double> beats, List<double> downbeats, double confidence}) _seamBeats(List<_Region> regions) {
    final graded = regions.where((r) => r.grid != null).toList()..sort((a, b) => a.start.compareTo(b.start));
    if (graded.isEmpty) return (beats: <double>[], downbeats: <double>[], confidence: 0.0);
    final beats = <double>[];
    final downbeats = <double>[];
    var weighted = 0.0;
    var count = 0;
    for (var index = 0; index < graded.length; index++) {
      final region = graded[index];
      final grid = region.grid!;
      final previous = index > 0 ? graded[index - 1] : null;
      final next = index + 1 < graded.length ? graded[index + 1] : null;
      var from = double.negativeInfinity;
      if (previous != null) {
        final seam = (previous.start + previous.seconds + region.start) / 2;
        if (seam > region.start) from = seam;
      }
      var until = double.infinity;
      if (next != null) {
        final seam = (region.start + region.seconds + next.start) / 2;
        if (seam < region.start + region.seconds) until = seam;
      }
      final kept = grid.beats.where((b) => b >= from && b < until).toList();
      beats.addAll(kept);
      downbeats.addAll(grid.downbeats.where((b) => b >= from && b < until));
      weighted += grid.beatConfidence * kept.length;
      count += kept.length;
    }
    beats.sort();
    downbeats.sort();
    return (beats: beats, downbeats: downbeats, confidence: count > 0 ? weighted / count : 0.0);
  }

  BeatSide? _beatSide(({List<double> beats, List<double> downbeats, double confidence}) all, double from, double to) {
    final beats = all.beats.where((b) => b >= from && b <= to).toList();
    final bpm = tempoFromBeats(beats);
    if (bpm <= 0) return null;
    return BeatSide(
      beats: beats,
      downbeats: all.downbeats.where((b) => b >= from && b <= to).toList(),
      bpm: bpm,
      confidence: all.confidence,
    );
  }

  _Grid _toGrid(BeatSide side) => _Grid(
        beats: side.beats,
        downbeats: side.downbeats,
        bpm: side.bpm,
        beatInterval: 60 / side.bpm,
        firstBeat: side.beats.first,
        beatConfidence: side.confidence,
      );
}

// ---- BeatTracker's grid maths -------------------------------------------------

double _median(List<double> values) {
  if (values.isEmpty) return 0.0;
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

/// Frames (fractional) where the logits peak: local maxima over a 7-frame
/// window, ties collapsed onto their mean, refined by a parabola.
List<double> pickPeaks(Float32List logits) {
  const half = _peakWindow ~/ 2;
  final peaks = <int>[];
  for (var index = 0; index < logits.length; index++) {
    if (logits[index] <= 0) continue;
    var isMaximum = true;
    for (var offset = -half; offset <= half; offset++) {
      final neighbour = index + offset;
      if (neighbour < 0 || neighbour >= logits.length) continue;
      if (logits[neighbour] > logits[index]) {
        isMaximum = false;
        break;
      }
    }
    if (isMaximum) peaks.add(index);
  }
  final deduped = <int>[];
  var index = 0;
  while (index < peaks.length) {
    var mean = peaks[index].toDouble();
    var count = 1;
    while (index + 1 < peaks.length && peaks[index + 1] - mean <= 1) {
      index += 1;
      count += 1;
      mean += (peaks[index] - mean) / count;
    }
    deduped.add(mean.round());
    index += 1;
  }
  return [
    for (final frame in deduped)
      () {
        if (frame <= 0 || frame + 1 >= logits.length) return frame.toDouble();
        final left = logits[frame - 1].toDouble();
        final centre = logits[frame].toDouble();
        final right = logits[frame + 1].toDouble();
        final denominator = left - 2 * centre + right;
        if (denominator.abs() <= 1e-9) return frame.toDouble();
        return frame + (0.5 * (left - right) / denominator).clamp(-0.5, 0.5);
      }(),
  ];
}

double tempoFromBeats(List<double> beats) {
  if (beats.length < _minBeats) return 0.0;
  final gaps = [for (var i = 0; i + 1 < beats.length; i++) beats[i + 1] - beats[i]];
  final rough = _median(gaps);
  if (rough <= 0) return 0.0;
  final kept = gaps.where((g) => (g - rough).abs() <= rough * 0.2).toList();
  final interval = _median(kept.length >= 4 ? kept : gaps);
  if (interval <= 0) return 0.0;
  final bpm = 60 / interval;
  return bpm >= _minTempo && bpm <= _maxTempo ? bpm : 0.0;
}

double gridConfidence(List<double> beats, List<double> peakLogits) {
  if (beats.length < _minBeats) return 0.0;
  final gaps = [for (var i = 0; i + 1 < beats.length; i++) beats[i + 1] - beats[i]];
  final interval = _median(gaps);
  if (interval <= 0) return 0.0;
  final regular = gaps.where((g) => (g - interval).abs() <= interval * 0.1).length / gaps.length;
  final strength = 1 / (1 + math.exp(-(_median(peakLogits) - 0.5)));
  return math.max(0.0, math.min(0.95, 0.35 + 0.4 * regular + 0.25 * strength));
}
