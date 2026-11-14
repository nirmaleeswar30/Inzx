// Desktop Automix: what analysis knows about a track.
//
// BitChord's TrackAnalysis and its companions (com.music.bitchord.playback.
// smart, GPL-3.0), ported to Dart field for field so the planner reads the
// same numbers Android's does.
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

class EnergySample {
  const EnergySample(this.time, this.energy);
  final double time;
  final double energy;
}

class MixCandidate {
  const MixCandidate(this.time, this.score, this.type);
  final double time;
  final double score;
  final String type;
}

class RankedMixCandidate {
  const RankedMixCandidate({
    required this.time,
    required this.score,
    required this.type,
    required this.rankScore,
    this.discardedMusicSeconds = 0.0,
    this.measured = true,
  });
  final double time;
  final double score;
  final String type;
  final double rankScore;
  final double discardedMusicSeconds;
  final bool measured;
}

class MixOutAnchor {
  const MixOutAnchor({required this.time, required this.type, required this.discardedMusicSeconds});
  final double time;
  final String type;
  final double discardedMusicSeconds;
}

enum TransitionTier { beatmatched, djAssisted, plainCrossfade }

class TransitionPolicyVerdict {
  const TransitionPolicyVerdict({required this.tier, required this.reasons, required this.beatConfidence});
  final TransitionTier tier;
  final List<String> reasons;
  final double beatConfidence;
}

class BeatSide {
  const BeatSide({required this.beats, required this.downbeats, required this.bpm, required this.confidence});
  final List<double> beats;
  final List<double> downbeats;
  final double bpm;
  final double confidence;

  Map<String, Object?> toJson() => {'b': beats, 'd': downbeats, 'bpm': bpm, 'c': confidence};

  static BeatSide? fromJson(Object? json) {
    if (json is! Map) return null;
    return BeatSide(
      beats: _doubles(json['b']),
      downbeats: _doubles(json['d']),
      bpm: _num(json['bpm']),
      confidence: _num(json['c']),
    );
  }
}

const double levelFrameRate = 10.0;

class CurveWindow {
  CurveWindow(this.startTime, this.frameRate, this.values);
  final double startTime;
  final double frameRate;
  final Float32List values;

  double get endTime => startTime + values.length / frameRate;

  Map<String, Object?> toJson() => {
        's': startTime,
        'r': frameRate,
        'v': [for (final v in values) (v * 100).round()],
      };

  static CurveWindow? fromJson(Object? json) {
    if (json is! Map) return null;
    final raw = json['v'];
    if (raw is! List) return null;
    return CurveWindow(
      _num(json['s']),
      _num(json['r']),
      Float32List.fromList([for (final v in raw) (v as num).toDouble() / 100]),
    );
  }
}

double levelFromRms(double rms) =>
    rms <= 1e-3 ? 0.0 : ((20 * math.log(rms) / math.ln10 + 60) / 60).clamp(0.0, 1.0);

double rmsFromLevel(double level) => level <= 0 ? 0.0 : math.pow(10.0, (level * 60 - 60) / 20).toDouble();

class TrackAnalysis {
  const TrackAnalysis({
    this.status = '',
    this.trackId = '',
    this.duration = 0.0,
    this.bpm = 0.0,
    this.beatInterval = 0.0,
    this.beatConfidence = 0.0,
    this.downbeats = const [],
    this.phraseBoundaries = const [],
    this.firstBeat = 0.0,
    this.key = '',
    this.keyConfidence = 0.0,
    this.audibleStartTime,
    this.pickupTime,
    this.introEndTime = 0.0,
    this.contentEndTime = 0.0,
    this.outroStartTime = 0.0,
    this.mixInTime = 0.0,
    this.mixOutTime = 0.0,
    this.mixInCandidates = const [],
    this.mixOutCandidates = const [],
    this.energyCurve = const [],
    this.lowEnergyCurve = const [],
    this.vocalActivityMask = const [],
    this.vocalProbability = 0.0,
    this.headBeats,
    this.tailBeats,
    this.vocalWindows = const [],
    this.levelWindows = const [],
  });

  static const statusReady = 'ready';

  final String status;
  final String trackId;
  final double duration;
  final double bpm;
  final double beatInterval;
  final double beatConfidence;
  final List<double> downbeats;
  final List<double> phraseBoundaries;
  final double firstBeat;
  final String key;
  final double keyConfidence;
  final double? audibleStartTime;
  final double? pickupTime;
  final double introEndTime;
  final double contentEndTime;
  final double outroStartTime;
  final double mixInTime;
  final double mixOutTime;
  final List<MixCandidate> mixInCandidates;
  final List<MixCandidate> mixOutCandidates;
  final List<EnergySample> energyCurve;
  final List<EnergySample> lowEnergyCurve;
  final List<double> vocalActivityMask;
  final double vocalProbability;
  final BeatSide? headBeats;
  final BeatSide? tailBeats;
  final List<CurveWindow> vocalWindows;
  final List<CurveWindow> levelWindows;

  bool get isUsable => status == statusReady && bpm > 0;

  Map<String, Object?> toJson() => {
        'status': status,
        'trackId': trackId,
        'duration': duration,
        'bpm': bpm,
        'beatInterval': beatInterval,
        'beatConfidence': beatConfidence,
        'downbeats': downbeats,
        'phraseBoundaries': phraseBoundaries,
        'firstBeat': firstBeat,
        'key': key,
        'keyConfidence': keyConfidence,
        'audibleStartTime': audibleStartTime,
        'pickupTime': pickupTime,
        'introEndTime': introEndTime,
        'contentEndTime': contentEndTime,
        'outroStartTime': outroStartTime,
        'mixInTime': mixInTime,
        'mixOutTime': mixOutTime,
        'mixInCandidates': [for (final c in mixInCandidates) [c.time, c.score, c.type]],
        'mixOutCandidates': [for (final c in mixOutCandidates) [c.time, c.score, c.type]],
        'energyCurve': [for (final e in energyCurve) [e.time, e.energy]],
        'lowEnergyCurve': [for (final e in lowEnergyCurve) [e.time, e.energy]],
        'vocalActivityMask': vocalActivityMask,
        'vocalProbability': vocalProbability,
        'headBeats': headBeats?.toJson(),
        'tailBeats': tailBeats?.toJson(),
        'vocalWindows': [for (final w in vocalWindows) w.toJson()],
        'levelWindows': [for (final w in levelWindows) w.toJson()],
      };

  static TrackAnalysis fromJson(Map<String, Object?> json) {
    List<MixCandidate> candidates(Object? raw) => raw is List
        ? [
            for (final c in raw)
              if (c is List && c.length >= 3) MixCandidate(_num(c[0]), _num(c[1]), '${c[2]}'),
          ]
        : const [];
    List<EnergySample> curve(Object? raw) => raw is List
        ? [
            for (final e in raw)
              if (e is List && e.length >= 2) EnergySample(_num(e[0]), _num(e[1])),
          ]
        : const [];
    List<CurveWindow> windows(Object? raw) =>
        raw is List ? [for (final w in raw) ?CurveWindow.fromJson(w)] : const [];
    return TrackAnalysis(
      status: json['status'] as String? ?? '',
      trackId: json['trackId'] as String? ?? '',
      duration: _num(json['duration']),
      bpm: _num(json['bpm']),
      beatInterval: _num(json['beatInterval']),
      beatConfidence: _num(json['beatConfidence']),
      downbeats: _doubles(json['downbeats']),
      phraseBoundaries: _doubles(json['phraseBoundaries']),
      firstBeat: _num(json['firstBeat']),
      key: json['key'] as String? ?? '',
      keyConfidence: _num(json['keyConfidence']),
      audibleStartTime: (json['audibleStartTime'] as num?)?.toDouble(),
      pickupTime: (json['pickupTime'] as num?)?.toDouble(),
      introEndTime: _num(json['introEndTime']),
      contentEndTime: _num(json['contentEndTime']),
      outroStartTime: _num(json['outroStartTime']),
      mixInTime: _num(json['mixInTime']),
      mixOutTime: _num(json['mixOutTime']),
      mixInCandidates: candidates(json['mixInCandidates']),
      mixOutCandidates: candidates(json['mixOutCandidates']),
      energyCurve: curve(json['energyCurve']),
      lowEnergyCurve: curve(json['lowEnergyCurve']),
      vocalActivityMask: _doubles(json['vocalActivityMask']),
      vocalProbability: _num(json['vocalProbability']),
      headBeats: BeatSide.fromJson(json['headBeats']),
      tailBeats: BeatSide.fromJson(json['tailBeats']),
      vocalWindows: windows(json['vocalWindows']),
      levelWindows: windows(json['levelWindows']),
    );
  }
}

/// BitChord's TrackFeatures.Features: the whole-track DSP pass's output.
class TrackFeatures {
  const TrackFeatures({
    required this.duration,
    required this.bpm,
    required this.beatInterval,
    required this.firstBeat,
    required this.beatConfidence,
    required this.key,
    required this.keyConfidence,
    required this.audibleStartTime,
    required this.pickupTime,
    required this.introEndTime,
    required this.outroStartTime,
    required this.contentEndTime,
    required this.mixInTime,
    required this.mixOutTime,
    required this.vocalProbability,
    required this.downbeats,
    required this.phraseBoundaries,
    required this.vocalActivityMask,
    required this.energyCurve,
    required this.lowEnergyCurve,
    required this.mixInCandidates,
    required this.mixOutCandidates,
  });

  final double duration;
  final double bpm;
  final double beatInterval;
  final double firstBeat;
  final double beatConfidence;
  final String key;
  final double keyConfidence;
  final double audibleStartTime;
  final double pickupTime;
  final double introEndTime;
  final double outroStartTime;
  final double contentEndTime;
  final double mixInTime;
  final double mixOutTime;
  final double vocalProbability;
  final List<double> downbeats;
  final List<double> phraseBoundaries;
  final List<double> vocalActivityMask;
  final List<EnergySample> energyCurve;
  final List<EnergySample> lowEnergyCurve;
  final List<MixCandidate> mixInCandidates;
  final List<MixCandidate> mixOutCandidates;

  static TrackFeatures? parse(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final root = decoded;
    double number(String name) {
      final v = root[name];
      return v is num && v.isFinite ? v.toDouble() : 0.0;
    }

    List<EnergySample> curve(String name) {
      final raw = root[name];
      if (raw is! List) return const [];
      return [
        for (final point in raw)
          if (point is Map && point['t'] is num && point['e'] is num &&
              (point['t'] as num).isFinite && (point['e'] as num).isFinite)
            EnergySample((point['t'] as num).toDouble(), (point['e'] as num).toDouble()),
      ];
    }

    List<MixCandidate> cues(String name) {
      final raw = root[name];
      if (raw is! List) return const [];
      return [
        for (final point in raw)
          if (point is Map && point['t'] is num && (point['t'] as num).isFinite)
            MixCandidate(
              (point['t'] as num).toDouble(),
              point['s'] is num && (point['s'] as num).isFinite ? (point['s'] as num).toDouble() : 0.0,
              point['y'] as String? ?? '',
            ),
      ];
    }

    return TrackFeatures(
      duration: number('duration'),
      bpm: number('bpm'),
      beatInterval: number('beatInterval'),
      firstBeat: number('firstBeat'),
      beatConfidence: number('beatConfidence'),
      key: root['key'] as String? ?? '',
      keyConfidence: number('keyConfidence'),
      audibleStartTime: number('audibleStartTime'),
      pickupTime: number('pickupTime'),
      introEndTime: number('introEndTime'),
      outroStartTime: number('outroStartTime'),
      contentEndTime: number('contentEndTime'),
      mixInTime: number('mixInTime'),
      mixOutTime: number('mixOutTime'),
      vocalProbability: number('vocalProbability'),
      downbeats: _finiteDoubles(root['downbeats']),
      phraseBoundaries: _finiteDoubles(root['phraseBoundaries']),
      vocalActivityMask: _finiteDoubles(root['vocalActivityMask']),
      energyCurve: curve('energyCurve'),
      lowEnergyCurve: curve('lowEnergyCurve'),
      mixInCandidates: cues('mixInCandidates'),
      mixOutCandidates: cues('mixOutCandidates'),
    );
  }
}

double _num(Object? v) => v is num ? v.toDouble() : 0.0;

List<double> _doubles(Object? raw) =>
    raw is List ? [for (final v in raw) if (v is num) v.toDouble()] : const [];

List<double> _finiteDoubles(Object? raw) =>
    raw is List ? [for (final v in raw) if (v is num && v.isFinite) v.toDouble()] : const [];
