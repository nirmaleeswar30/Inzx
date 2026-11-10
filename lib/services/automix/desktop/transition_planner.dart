// Desktop Automix: turns stored analysis into a transition plan.
//
// Ported from BitChord's TransitionPlanner.kt (itself built on Orchard,
// https://github.com/SFG5453/Orchard; AGPL-3.0 as combined into BitChord's
// GPL-3.0 work). Line for line, including Kotlin's rounding (`round` is
// half-to-even) and tie-breaking (first of equals wins), so the same pair
// gets the same plan on desktop as on Android.
//
// Copyright (C) 2026 SFG545 (original Orchard implementation)
// Copyright (C) 2026 Kushagra Singh (BitChord adaptation)

import 'dart:math' as math;

import 'track_analysis.dart';
import 'transition_policy.dart';

enum CrossfadeMode { standard, smart }

class TransitionTrackInfo {
  const TransitionTrackInfo({
    required this.id,
    required this.durationMs,
    this.title = '',
    this.artist = '',
    this.album = '',
    this.albumId = '',
  });
  final String id;
  final int durationMs;
  final String title;
  final String artist;
  final String album;
  final String albumId;
}

const double _autoTransitionMaxBeats = 16.0;
const double _autoMinSeconds = 4.0;
const double _autoFastTrackMinSeconds = 6.0;
const double _autoTransitionMaxSeconds = 12.0;
const double _autoFallbackSeconds = 8.0;
const double _mixWindowSeconds = 30.0;
const double _minSmartDurationSeconds = 45.0;
const double _minIncomingClearanceSeconds = 5.0;

const Map<String, int> _keyIndex = {
  'C': 0, 'C♯': 1, 'D♭': 1, 'D': 2, 'D♯': 3, 'E♭': 3, //
  'E': 4, 'F': 5, 'F♯': 6, 'G♭': 6, 'G': 7, 'G♯': 8,
  'A♭': 8, 'A': 9, 'A♯': 10, 'B♭': 10, 'B': 11,
};

final RegExp _spokenText = RegExp(r'\b(podcast|episode|audiobook|concert)\b', caseSensitive: false);

final RegExp _liveText = RegExp(
  r'[(\[]\s*(?:[^)\]]*\s)?live(?:\s+(?:at|from|in|on|version|session|recording|performance|edit)\b[^)\]]*)?\s*[)\]]'
  r'|[-–—]\s*live(?:\s+(?:at|from|in|on|version|session|recording|performance|edit)\b.*)?\s*$'
  r'|^\s*live\s*(?::|\s(?:at|from|in|on)\b)',
  caseSensitive: false,
);

bool _isSpokenOrLive(TransitionTrackInfo? track) {
  if (track == null) return false;
  if (_spokenText.hasMatch(_itemText(track))) return true;
  return _liveText.hasMatch(track.title) || _liveText.hasMatch(track.album);
}

enum TransitionStyle { equalPower, gapless, djBlend, djFilter }

enum FilterTransitionVariant { sweep, bassHandoff, echoRide }

const double handoffFraction = 0.5;
const double bedPosition = 0.5;

class TransitionPlan {
  const TransitionPlan({
    this.shouldStart = false,
    this.markerVisible = false,
    this.blocked = false,
    this.reason = '',
    this.transitionStart = 0.0,
    this.transitionEnd = 0.0,
    this.fadeSeconds = 0.0,
    this.transitionStyle = TransitionStyle.equalPower,
    this.incomingCueTime = 0.0,
    this.incomingHandoffTime = 0.0,
    this.incomingPlaybackRate = 1.0,
    this.outgoingPlaybackRate = 1.0,
    this.handoffStartSeconds = 0.0,
    this.handoffDuration = 0.0,
    this.pickupSeconds = 0.0,
    this.transitionBeats = 0,
    this.bassSwap = false,
    this.handoffFraction = 0.5,
    this.bedPosition = 0.5,
    this.bassSwapFraction = 0.7,
    this.filterSweep = 0.0,
    this.filterVariant = FilterTransitionVariant.sweep,
    this.vocalOverlap = 0.0,
    this.outgoingBpm = 0.0,
    this.incomingBpm = 0.0,
    this.beatSeconds = 0.0,
    this.phaseLock = false,
    this.echoSeconds = 0.0,
    this.policyReasons = const [],
  });

  final bool shouldStart;
  final bool markerVisible;
  final bool blocked;
  final String reason;
  final double transitionStart;
  final double transitionEnd;
  final double fadeSeconds;
  final TransitionStyle transitionStyle;
  final double incomingCueTime;
  final double incomingHandoffTime;
  final double incomingPlaybackRate;
  final double outgoingPlaybackRate;
  final double handoffStartSeconds;
  final double handoffDuration;
  final double pickupSeconds;
  final int transitionBeats;
  final bool bassSwap;
  final double handoffFraction;
  final double bedPosition;
  final double bassSwapFraction;
  final double filterSweep;
  final FilterTransitionVariant filterVariant;
  final double vocalOverlap;
  final double outgoingBpm;
  final double incomingBpm;
  final double beatSeconds;
  final bool phaseLock;
  final double echoSeconds;
  final List<String> policyReasons;

  int get fadeMs => (fadeSeconds * 1000).round();

  TransitionPlan copyWith({
    bool? shouldStart,
    String? reason,
    double? transitionStart,
    double? transitionEnd,
    double? fadeSeconds,
    double? incomingCueTime,
    double? incomingHandoffTime,
    List<String>? policyReasons,
  }) =>
      TransitionPlan(
        shouldStart: shouldStart ?? this.shouldStart,
        markerVisible: markerVisible,
        blocked: blocked,
        reason: reason ?? this.reason,
        transitionStart: transitionStart ?? this.transitionStart,
        transitionEnd: transitionEnd ?? this.transitionEnd,
        fadeSeconds: fadeSeconds ?? this.fadeSeconds,
        transitionStyle: transitionStyle,
        incomingCueTime: incomingCueTime ?? this.incomingCueTime,
        incomingHandoffTime: incomingHandoffTime ?? this.incomingHandoffTime,
        incomingPlaybackRate: incomingPlaybackRate,
        outgoingPlaybackRate: outgoingPlaybackRate,
        handoffStartSeconds: handoffStartSeconds,
        handoffDuration: handoffDuration,
        pickupSeconds: pickupSeconds,
        transitionBeats: transitionBeats,
        bassSwap: bassSwap,
        handoffFraction: handoffFraction,
        bedPosition: bedPosition,
        bassSwapFraction: bassSwapFraction,
        filterSweep: filterSweep,
        filterVariant: filterVariant,
        vocalOverlap: vocalOverlap,
        outgoingBpm: outgoingBpm,
        incomingBpm: incomingBpm,
        beatSeconds: beatSeconds,
        phaseLock: phaseLock,
        echoSeconds: echoSeconds,
        policyReasons: policyReasons ?? this.policyReasons,
      );
}

TransitionPlan _blocked(String reason, {double transitionStart = 0.0, double transitionEnd = 0.0}) =>
    TransitionPlan(blocked: true, reason: reason, transitionStart: transitionStart, transitionEnd: transitionEnd);

double _trackDurationSeconds(TransitionTrackInfo? track) =>
    track == null || track.durationMs <= 0 ? 0.0 : track.durationMs / 1000.0;

String _itemText(TransitionTrackInfo? track) => track == null
    ? ''
    : [track.title, track.artist, track.album].where((s) => s.trim().isNotEmpty).join(' ');

// ---- Kotlin helpers --------------------------------------------------------------

/// kotlin.math.round: half to even.
double _roundHalfEven(double x) {
  final floor = x.floorToDouble();
  final diff = x - floor;
  if (diff > 0.5) return floor + 1;
  if (diff < 0.5) return floor;
  return floor % 2 == 0 ? floor : floor + 1;
}

/// Kotlin's Double.roundToInt (Math.round: half up).
int _roundToInt(double x) => (x + 0.5).floor();

double _nonZeroOr(double value, double Function() otherwise) => value != 0.0 ? value : otherwise();

double? _minByAbs(Iterable<double> values, double target) {
  double? best;
  for (final v in values) {
    if (best == null || (v - target).abs() < (best - target).abs()) best = v;
  }
  return best;
}

double? _maxOrNull(Iterable<double> values) {
  double? best;
  for (final v in values) {
    if (best == null || v > best) best = v;
  }
  return best;
}

double _beatIntervalOf(TrackAnalysis analysis) {
  final interval = analysis.beatInterval.orZero();
  if (interval > 0) return interval;
  return analysis.bpm.orZero() > 0 ? 60 / analysis.bpm : 0.0;
}

// ---- Pair judgements ------------------------------------------------------------

const double _kickPresent = 0.5;
const double _vocalConflictProbability = 0.62;

bool _isUnmixablePair(TrackAnalysis analysis, TrackAnalysis nextAnalysis) {
  final currentBpm = analysis.bpm.orZero();
  final nextBpm = nextAnalysis.bpm.orZero();
  if (currentBpm <= 0 || nextBpm <= 0) return false;
  if (stretchReachable(currentBpm, nextBpm)) return false;
  final left = _trustedKey(analysis);
  final right = _trustedKey(nextAnalysis);
  final keyClash = left.isNotEmpty && right.isNotEmpty && !_harmonicallyCompatible(left, right);
  final vocalConflict = analysis.vocalProbability >= _vocalConflictProbability &&
      nextAnalysis.vocalProbability >= _vocalConflictProbability;
  return keyClash || vocalConflict;
}

FilterTransitionVariant _fallbackVariantFor(
    TrackAnalysis analysis, TrackAnalysis nextAnalysis, double exitAt, double beatSeconds) {
  final window = _energyWindowBeats * (beatSeconds > 0 ? beatSeconds : 0.5);
  final entry = _incomingStartPoint(nextAnalysis);
  final outReference = _lowEnergyReference(analysis.lowEnergyCurve);
  if (outReference == null) return FilterTransitionVariant.sweep;
  final inReference = _lowEnergyReference(nextAnalysis.lowEnergyCurve);
  if (inReference == null) return FilterTransitionVariant.sweep;
  final out = _averageEnergy(analysis.lowEnergyCurve, exitAt - window, exitAt);
  if (out == null) return FilterTransitionVariant.sweep;
  final into = _averageEnergy(nextAnalysis.lowEnergyCurve, entry, entry + window);
  if (into == null) return FilterTransitionVariant.sweep;
  return out / outReference >= _kickPresent && into / inReference >= _kickPresent
      ? FilterTransitionVariant.bassHandoff
      : FilterTransitionVariant.sweep;
}

bool _sameAlbum(TransitionTrackInfo? left, TransitionTrackInfo? right) {
  if (left == null || right == null) return false;
  if (left.albumId.trim().isNotEmpty && left.albumId == right.albumId) return true;
  return left.album.trim().isNotEmpty && left.album == right.album && left.artist == right.artist;
}

double _normalizedTempoRatio(double currentBpm, double nextBpm) {
  if (currentBpm <= 0 || nextBpm <= 0) return 1.0;
  var ratio = nextBpm / currentBpm;
  while (ratio > 1.5) {
    ratio /= 2;
  }
  while (ratio < 0.67) {
    ratio *= 2;
  }
  return ratio;
}

(int?, String?) _splitKey(String key) {
  final parts = key.trim().split(' ');
  return (_keyIndex[parts.isEmpty ? null : parts.first], parts.length > 1 ? parts[1] : null);
}

int? _keyDistance(String left, String right) {
  final (leftIndex, leftMode) = _splitKey(left);
  final (rightIndex, rightMode) = _splitKey(right);
  if (leftIndex == null || rightIndex == null) return null;
  final pitchDistance = math.min((leftIndex - rightIndex + 12) % 12, (rightIndex - leftIndex + 12) % 12);
  return pitchDistance + (leftMode != null && rightMode != null && leftMode != rightMode ? 1 : 0);
}

bool _harmonicallyCompatible(String left, String right) {
  final (leftIndex, leftMode) = _splitKey(left);
  final (rightIndex, rightMode) = _splitKey(right);
  if (leftIndex == null || rightIndex == null) return false;
  final distance = math.min((leftIndex - rightIndex + 12) % 12, (rightIndex - leftIndex + 12) % 12);
  if (leftMode != null && rightMode != null && leftMode != rightMode) return distance <= 1;
  return distance <= 2 || distance == 5;
}

String _trustedKey(TrackAnalysis analysis) =>
    analysis.key.trim().isEmpty || analysis.keyConfidence < 0.25 ? '' : analysis.key;

double? _nearestTimedValue(List<double> values, double target,
        {double tolerance = double.infinity, double minimum = 0.0}) =>
    _minByAbs(values.where((v) => v.isFinite && v >= minimum && (v - target).abs() <= tolerance), target);

double? _timedValueNearOrBefore(List<double> values, double target,
        {double tolerance = double.infinity, double minimum = 0.0}) =>
    _maxOrNull(values.where((v) => v.isFinite && v >= minimum && v <= target && target - v <= tolerance));

double _alignedTransitionStart(TrackAnalysis analysis, double target, double end,
    {required bool preferEarlier, required double minimum}) {
  final interval = _beatIntervalOf(analysis);
  final phraseTolerance = math.max(1.0, interval * 4);
  final downbeatTolerance = math.max(0.75, interval * 2);
  final phrase = preferEarlier
      ? _timedValueNearOrBefore(analysis.phraseBoundaries, target, tolerance: phraseTolerance, minimum: minimum)
      : _nearestTimedValue(analysis.phraseBoundaries, target, tolerance: phraseTolerance, minimum: minimum);
  final downbeat = preferEarlier
      ? _timedValueNearOrBefore(analysis.downbeats, target, tolerance: downbeatTolerance, minimum: minimum)
      : _nearestTimedValue(analysis.downbeats, target, tolerance: downbeatTolerance, minimum: minimum);
  return clampFinite(phrase ?? downbeat ?? target, minimum, end);
}

const double maxIncomingSkipFraction = 0.25;

double latestIncomingCue(double length) =>
    length.isFinite && length > 0 ? length * maxIncomingSkipFraction : double.infinity;

double incomingCuePoint(TrackAnalysis analysis, {double latest = double.infinity}) {
  for (final c in rankMixInCandidates(analysis)) {
    if (c.time <= latest) return c.time;
  }
  final interval = _beatIntervalOf(analysis);
  final downbeats = analysis.downbeats;
  double within(double time) => time <= latest ? time : (_nearestAtOrBefore(downbeats, latest) ?? latest);

  final analyzedMixIn = analysis.mixInTime;
  if (analyzedMixIn.isFinite && analyzedMixIn > 0) {
    return within(
        _nearestTimedValue(downbeats, analyzedMixIn, tolerance: math.max(0.5, interval * 2)) ?? analyzedMixIn);
  }
  final pickup = math.max(
    0.0,
    _nonZeroOr(
      analysis.introEndTime.orZero(),
      () => _nonZeroOr(orZeroN(analysis.audibleStartTime ?? analysis.pickupTime), () => analysis.firstBeat.orZero()),
    ),
  );
  final duration = _nonZeroOr(analysis.duration.orZero(), () => 300.0);
  if (pickup > 0 && pickup < duration - 10) {
    for (final d in downbeats) {
      if (d >= pickup) return within(d);
    }
  }
  final phrases = analysis.phraseBoundaries;
  if (phrases.length > 1 && phrases[1] > 4) return within(phrases[1]);
  if (downbeats.length >= 8) return within(downbeats[math.min(8, downbeats.length - 1)].orZero());
  return within(pickup);
}

TransitionPlan _capIncomingSkip(TransitionPlan plan, TrackAnalysis nextAnalysis, double nextLength) {
  final latest = latestIncomingCue(nextLength);
  if (plan.incomingCueTime <= latest) return plan;
  final beat = _beatIntervalOf(nextAnalysis);
  final over = plan.incomingCueTime - latest;
  final shift = beat > 0 ? (over / (4 * beat)).ceilToDouble() * 4 * beat : over;
  final cue = math.max(0.0, plan.incomingCueTime - shift);
  final moved = plan.incomingCueTime - cue;
  return plan.copyWith(
    incomingCueTime: cue,
    incomingHandoffTime: math.max(cue, plan.incomingHandoffTime - moved),
  );
}

double _incomingStartPoint(TrackAnalysis analysis) {
  for (final v in [analysis.audibleStartTime, analysis.pickupTime, analysis.firstBeat]) {
    if (v != null && v.isFinite && v >= 0) return v;
  }
  return 0.0;
}

// ---- Apple-style phrase mixes ---------------------------------------------------

const int phraseBarsShort = 8;
const int phraseBarsLong = 16;
const int _beatsPerBar = 4;
const double _maxPhraseOverlapSeconds = 64.0;

TransitionPlan? _phraseBarPlan(TrackAnalysis analysis, TrackAnalysis nextAnalysis, double length, double nextLength,
    int phraseBars, double mixAnchor, bool advanced) {
  final outgoingBpm = analysis.bpm.orZero();
  if (outgoingBpm < minBpm || outgoingBpm > maxBpm) return null;
  final interval = analysis.beatInterval.orZero();
  final beatSeconds = interval > 0 ? interval : 60.0 / outgoingBpm;
  if (beatSeconds <= 0) return null;

  final overlapBeats = phraseBars * _beatsPerBar;
  final requestedOverlap = overlapBeats * beatSeconds;
  if (requestedOverlap <= 0 || requestedOverlap > _maxPhraseOverlapSeconds) return null;

  final contentEnd = _nonZeroOr(analysis.contentEndTime.orZero(), () => length);
  final anchor = math.min(math.min(mixAnchor, contentEnd), length);
  final gridTrusted = analysis.beatConfidence.orZero() >= minDjConfidence;
  final mixEnd = gridTrusted ? _onDownbeatBefore(analysis, anchor, _beatsPerBar * beatSeconds) : anchor;
  if (mixEnd <= 0) return null;

  final latestStart = mixEnd - requestedOverlap;
  if (latestStart < _minClearanceSeconds) return null;
  final transitionStart = gridTrusted
      ? _alignedTransitionStart(analysis, latestStart, mixEnd - 0.05,
          preferEarlier: true, minimum: _minClearanceSeconds)
      : latestStart;
  final transitionEnd = transitionStart + requestedOverlap;
  if (transitionEnd > length + 0.05) return null;
  final overlapSeconds = transitionEnd - transitionStart;
  if (overlapSeconds <= 0) return null;

  final policy = assessTransitionTier(analysis, nextAnalysis, advanced: advanced);
  final beatmatched = policy.tier == TransitionTier.beatmatched;
  final nextBpm = nextAnalysis.bpm.orZero();
  final alignedIncomingBpm = alignTempoOctave(outgoingBpm, nextBpm);
  final tempoFar = nextBpm > 0 && !stretchReachable(outgoingBpm, nextBpm);
  final mediaRatio =
      nextBpm > 0 && !tempoFar ? _roundRate(1.0 / _normalizedTempoRatio(outgoingBpm, nextBpm)) : 1.0;
  final incomingPlaybackRate = _incomingRateFor(mediaRatio, advanced);
  final outgoingPlaybackRate = _outgoingRateFor(mediaRatio, advanced);
  final incomingBeatSeconds = alignedIncomingBpm > 0 ? 60.0 / alignedIncomingBpm : beatSeconds;

  final audibleStart = _incomingStartPoint(nextAnalysis);
  final incomingDropTime = incomingCuePoint(nextAnalysis, latest: latestIncomingCue(nextLength));
  final finalIncomingCueTime = audibleStart;
  final incomingHandoffTime = nextLength > 0
      ? math.max(math.min(incomingDropTime, nextLength - _minIncomingClearanceSeconds), finalIncomingCueTime)
      : incomingDropTime;
  final incomingResume = finalIncomingCueTime + overlapSeconds * incomingPlaybackRate;
  if (nextLength > 0 && incomingResume + _minIncomingClearanceSeconds > nextLength) return null;

  final vocalOverlap = _plannedVocalOverlap(
      analysis, nextAnalysis, transitionStart, transitionEnd, finalIncomingCueTime, incomingPlaybackRate);
  final bassSwapFraction = _bassSwapFractionFor(analysis, nextAnalysis, transitionStart, finalIncomingCueTime,
      beatSeconds, incomingBeatSeconds, overlapSeconds, overlapBeats);
  final hasBassContent = analysis.lowEnergyCurve.isNotEmpty || nextAnalysis.lowEnergyCurve.isNotEmpty;

  return TransitionPlan(
    markerVisible: true,
    transitionStart: transitionStart,
    transitionEnd: transitionEnd,
    fadeSeconds: overlapSeconds,
    handoffStartSeconds: 0.0,
    handoffDuration: overlapSeconds,
    incomingCueTime: finalIncomingCueTime,
    incomingHandoffTime: incomingHandoffTime,
    incomingPlaybackRate: incomingPlaybackRate,
    outgoingPlaybackRate: outgoingPlaybackRate,
    pickupSeconds: audibleStart,
    transitionBeats: overlapBeats,
    bassSwap: beatmatched || hasBassContent,
    handoffFraction: handoffFraction,
    bedPosition: bedPosition,
    bassSwapFraction: bassSwapFraction,
    filterSweep: beatmatched ? 0.0 : filterSweepFull,
    filterVariant: FilterTransitionVariant.sweep,
    vocalOverlap: vocalOverlap,
    outgoingBpm: outgoingBpm,
    incomingBpm: alignedIncomingBpm,
    beatSeconds: gridTrusted ? beatSeconds : 0.0,
    phaseLock: false,
    echoSeconds: 0.0,
    transitionStyle: beatmatched ? TransitionStyle.djBlend : TransitionStyle.djFilter,
    reason: 'smart-phrase-bars',
  );
}

// ---- Beat-matched phrase switch ---------------------------------------------------

const int _minFadeBeats = 4;
const int _maxFadeBeats = 16;
const double _maxOverlapSeconds = 16.0;
const int arrangementOverlapBeats = 8;
const double _defaultBassSwapFraction = 0.7;
const double _maxBassSwapFraction = 0.85;
const double _minBassStructureScore = 0.25;
const double _bassSwapMaxSeconds = 6.0;
const double filterSweepFull = 1.0;
const double _minClearanceSeconds = 5.0;

int _lowerBound(List<EnergySample> curve, double time) {
  var low = 0;
  var high = curve.length;
  while (low < high) {
    final mid = (low + high) >> 1;
    if (curve[mid].time < time) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low;
}

double? _averageEnergy(List<EnergySample> curve, double from, double until) {
  if (until <= from) return null;
  var index = _lowerBound(curve, from);
  var sum = 0.0;
  var count = 0;
  while (index < curve.length && curve[index].time < until) {
    final point = curve[index++];
    if (point.time.isFinite && point.energy.isFinite && point.energy >= 0) {
      sum += point.energy;
      count++;
    }
  }
  return count > 0 ? sum / count : null;
}

double? _lowEnergyReference(List<EnergySample> curve) {
  final energies = [for (final p in curve) if (p.energy.isFinite && p.energy >= 0) p.energy]..sort();
  if (energies.isEmpty) return null;
  final upperDecile = energies[((energies.length - 1) * 0.9).toInt()];
  final reference = math.max(upperDecile, energies.last * 0.25);
  return reference > 1e-9 ? reference : null;
}

double _lowEnergyResolution(List<EnergySample> curve) {
  final gaps = [
    for (var i = 0; i + 1 < curve.length; i++) curve[i + 1].time - curve[i].time,
  ].where((g) => g.isFinite && g > 0).toList()
    ..sort();
  final index = gaps.length ~/ 2;
  return index < gaps.length ? gaps[index] : 0.0;
}

double? _lowEnergyChange(List<EnergySample> curve, double? reference, double at, double windowSeconds) {
  if (curve.isEmpty || reference == null || windowSeconds <= 0) return null;
  final before = _averageEnergy(curve, at - windowSeconds, at);
  if (before == null) return null;
  final after = _averageEnergy(curve, at, at + windowSeconds);
  if (after == null) return null;
  return coerceIn(after / reference, 0.0, 1.5) - coerceIn(before / reference, 0.0, 1.5);
}

double _bassSwapFractionFor(
  TrackAnalysis analysis,
  TrackAnalysis nextAnalysis,
  double transitionStart,
  double incomingCueTime,
  double outgoingBeatSeconds,
  double incomingBeatSeconds,
  double overlapSeconds,
  int overlapBeats,
) {
  if (overlapSeconds <= 0) return _defaultBassSwapFraction;
  final latestFraction = coerceIn(math.min(_maxBassSwapFraction, _bassSwapMaxSeconds / overlapSeconds), 0.0, 1.0);
  final prior = math.min(_defaultBassSwapFraction, latestFraction);
  if (overlapBeats < 2) return prior;

  final earliestFraction = math.min(handoffFraction, latestFraction);
  final earliestBeat = (earliestFraction * overlapBeats - 1e-9).ceil().clamp(1, overlapBeats - 1);
  final latestBeat = (latestFraction * overlapBeats + 1e-9).floor().clamp(earliestBeat, overlapBeats - 1);
  final candidates = [for (var b = earliestBeat; b <= latestBeat; b++) b];
  int? fallbackBeat;
  for (final beat in candidates) {
    if (fallbackBeat == null) {
      fallbackBeat = beat;
      continue;
    }
    final a = (beat / overlapBeats - prior).abs();
    final b = (fallbackBeat / overlapBeats - prior).abs();
    final aBar = beat % 4 == 0 ? 0 : 1;
    final bBar = fallbackBeat % 4 == 0 ? 0 : 1;
    if (a < b || (a == b && aBar < bBar)) fallbackBeat = beat;
  }
  if (fallbackBeat == null) return prior;

  final outgoingReference = _lowEnergyReference(analysis.lowEnergyCurve);
  final incomingReference = _lowEnergyReference(nextAnalysis.lowEnergyCurve);
  final outgoingWindow = math.max(outgoingBeatSeconds, _lowEnergyResolution(analysis.lowEnergyCurve) * 1.1);
  final incomingWindow = math.max(incomingBeatSeconds, _lowEnergyResolution(nextAnalysis.lowEnergyCurve) * 1.1);
  (int, double)? strongest;
  int compare((int, double) x, (int, double) y) {
    final byScore = x.$2.compareTo(y.$2);
    if (byScore != 0) return byScore;
    final byBar = (x.$1 % 4 == 0 ? 1 : 0).compareTo(y.$1 % 4 == 0 ? 1 : 0);
    if (byBar != 0) return byBar;
    return (-(x.$1 / overlapBeats - prior).abs()).compareTo(-(y.$1 / overlapBeats - prior).abs());
  }

  for (final beat in candidates) {
    final outgoingAt = transitionStart + beat * outgoingBeatSeconds;
    final incomingAt = incomingCueTime + beat * incomingBeatSeconds;
    final incomingChange =
        _lowEnergyChange(nextAnalysis.lowEnergyCurve, incomingReference, incomingAt, incomingWindow);
    final outgoingChange = _lowEnergyChange(analysis.lowEnergyCurve, outgoingReference, outgoingAt, outgoingWindow);
    if (incomingChange == null && outgoingChange == null) continue;
    final candidate = (beat, (incomingChange ?? 0.0) - (outgoingChange ?? 0.0));
    if (strongest == null || compare(strongest, candidate) < 0) strongest = candidate;
  }
  final chosenBeat = strongest != null && strongest.$2 >= _minBassStructureScore ? strongest.$1 : fallbackBeat;
  return chosenBeat / overlapBeats;
}

double _plannedVocalOverlap(TrackAnalysis analysis, TrackAnalysis nextAnalysis, double transitionStart,
    double transitionEnd, double incomingCueTime, double incomingPlaybackRate) {
  final outgoingSpan = transitionEnd - transitionStart;
  if (outgoingSpan <= 0.0 || !outgoingSpan.isFinite) return 0.0;
  final rate = incomingPlaybackRate.isFinite && incomingPlaybackRate > 0 ? incomingPlaybackRate : 1.0;
  return simultaneousVocalFraction(analysis, nextAnalysis, transitionStart, transitionEnd, incomingCueTime, rate) ??
      0.0;
}

double? _nearestAtOrBefore(List<double> values, double target) =>
    _maxOrNull(values.where((v) => v.isFinite && v >= 0 && v <= target));

class WsolaPlanned {
  const WsolaPlanned({
    required this.tier,
    required this.beatConfidence,
    required this.mixOutType,
    required this.vocalClash,
    required this.transitionStart,
    required this.transitionEnd,
    required this.overlapSeconds,
    required this.beats,
    required this.bassSwapFraction,
    required this.outgoingBpm,
    required this.incomingBpm,
    required this.stretchRatio,
    required this.incomingCueTime,
    required this.incomingDropTime,
    required this.incomingHandoffTime,
    required this.incomingResumeTime,
  });
  final TransitionTier tier;
  final double beatConfidence;
  final String mixOutType;
  final bool vocalClash;
  final double transitionStart;
  final double transitionEnd;
  final double overlapSeconds;
  final int beats;
  final double bassSwapFraction;
  final double outgoingBpm;
  final double incomingBpm;
  final double stretchRatio;
  final double incomingCueTime;
  final double incomingDropTime;
  final double incomingHandoffTime;
  final double incomingResumeTime;
}

double? incomingMixInPoint(TrackAnalysis analysis, {double latest = double.infinity}) {
  final beatSeconds = _beatIntervalOf(analysis);
  final tolerance = math.max(0.5, beatSeconds * 2);
  double? ranked;
  for (final c in rankMixInCandidates(analysis)) {
    if (c.time <= latest) {
      ranked = c.time;
      break;
    }
  }
  double? target;
  for (final v in [ranked, analysis.mixInTime]) {
    if (v != null && v.isFinite && v > 0 && v <= latest) {
      target = v;
      break;
    }
  }
  if (target == null) return null;
  final snapped = nearestValue(analysis.downbeats, target, tolerance);
  return snapped != null && snapped <= latest ? snapped : target;
}

/// planWsolaTransition: a [WsolaPlanned], or the refusal reason.
Object _planWsolaTransition(TrackAnalysis analysis, TrackAnalysis nextAnalysis,
    {double duration = 0.0, double nextDuration = 0.0, bool advanced = false}) {
  final policy = assessTransitionTier(analysis, nextAnalysis, advanced: advanced);
  if (policy.tier != TransitionTier.beatmatched) {
    return policy.reasons.isEmpty ? 'policy' : policy.reasons.first;
  }
  final outgoingBpm = analysis.bpm.orZero();
  final incomingBpm = alignTempoOctave(outgoingBpm, nextAnalysis.bpm.orZero());
  final stretchRatio = outgoingBpm / incomingBpm;
  final outgoingLength = math.max(duration.orZero(), analysis.duration.orZero());
  final incomingLength = math.max(nextDuration.orZero(), nextAnalysis.duration.orZero());
  if (outgoingLength <= 0 || incomingLength <= 0) return 'missing-duration';
  final incomingBeatSeconds = 60 / incomingBpm;
  final outgoingBeatSeconds = 60 / outgoingBpm;

  final incomingDropTime = incomingMixInPoint(nextAnalysis, latest: latestIncomingCue(incomingLength));
  if (incomingDropTime == null || !incomingDropTime.isFinite || incomingDropTime < 0) return 'incoming-mix-in';

  final contentEnd = _nonZeroOr(analysis.contentEndTime.orZero(), () => outgoingLength);
  final mixOutAnchor = resolveMixOutAnchor(analysis, contentEnd: contentEnd, duration: outgoingLength);
  final unshiftedOverlapEnd = math.min(outgoingLength, mixOutAnchor.time);
  final outgoingArrangementOverlap = mixOutAnchor.type == 'content_end'
      ? math.min(arrangementOverlapBeats * outgoingBeatSeconds, maxDiscardedMusicSeconds)
      : 0.0;
  final overlapEndTarget = math.max(_minClearanceSeconds, unshiftedOverlapEnd - outgoingArrangementOverlap);

  final audibleStart = audibleStartOf(nextAnalysis);
  final availableFadeBeats = math.max(0.0, incomingDropTime - audibleStart) / incomingBeatSeconds;
  final cappedByOverlap = ((_maxOverlapSeconds / incomingBeatSeconds).floorToDouble() / 4).floor() * 4;
  if (cappedByOverlap < _minFadeBeats) return 'overlap-too-long';
  var fadeBeats = [_maxFadeBeats, cappedByOverlap, (availableFadeBeats / 4).floor() * 4].reduce(math.min);
  if (fadeBeats < _minFadeBeats) fadeBeats = _minFadeBeats;

  bool clashOver(int beats) {
    final outStart = overlapEndTarget - beats * outgoingBeatSeconds;
    final inStart = math.max(audibleStart, incomingDropTime - beats * incomingBeatSeconds);
    final outVocal = vocalActivityBetween(analysis, outStart, overlapEndTarget);
    final inVocal = vocalActivityBetween(nextAnalysis, inStart, incomingDropTime);
    final simultaneous = simultaneousVocalFraction(analysis, nextAnalysis, outStart, overlapEndTarget, inStart,
        outgoingBeatSeconds > 0 ? incomingBeatSeconds / outgoingBeatSeconds : 1.0);
    if (simultaneous != null && simultaneous > vocalClashTolerance) return true;
    if (isVocalClash(outVocal, inVocal)) return true;
    if (beats > 8 && outVocal != null && outVocal >= vocalActiveThreshold) {
      final deepVocal =
          vocalActivityBetween(analysis, outStart, overlapEndTarget - 8 * outgoingBeatSeconds);
      if (deepVocal != null && deepVocal >= vocalActiveThreshold) return true;
    }
    return false;
  }

  var fadeVocalClash = clashOver(fadeBeats);
  while (fadeVocalClash && fadeBeats > _minFadeBeats) {
    fadeBeats -= 4;
    fadeVocalClash = clashOver(fadeBeats);
  }

  final coverableBeats = (math.max(0.0, incomingDropTime - audibleStart) / incomingBeatSeconds).floor();
  final overlapBeats = math.min(fadeBeats, coverableBeats);
  if (overlapBeats < 1) return 'incoming-no-intro';
  final outgoingOverlapSeconds = overlapBeats * outgoingBeatSeconds;
  final overlapSeconds = overlapBeats * incomingBeatSeconds;

  final requestedIncomingHandoff = incomingDropTime + arrangementOverlapBeats * incomingBeatSeconds;
  final maxIncomingHandoff = incomingLength - _minClearanceSeconds;
  if (maxIncomingHandoff < incomingDropTime) return 'incoming-too-short';
  final incomingHandoffTime = math.min(requestedIncomingHandoff, maxIncomingHandoff);
  final incomingCueTime = incomingHandoffTime - overlapSeconds;
  if (incomingCueTime < audibleStart - 0.05) return 'incoming-no-runway';

  final startTarget = overlapEndTarget - outgoingOverlapSeconds;
  final transitionStart = _nearestAtOrBefore(analysis.downbeats, startTarget) ?? startTarget;
  if (transitionStart < _minClearanceSeconds) return 'outgoing-too-short';
  final transitionEnd = transitionStart + outgoingOverlapSeconds;
  if (transitionEnd > outgoingLength + 0.05) return 'outgoing-overlap-overruns';
  final incomingResumeTime = incomingCueTime + overlapSeconds;
  if (incomingResumeTime + _minClearanceSeconds > incomingLength) return 'incoming-too-short';

  return WsolaPlanned(
    tier: policy.tier,
    beatConfidence: policy.beatConfidence,
    mixOutType: mixOutAnchor.type,
    vocalClash: fadeVocalClash,
    transitionStart: transitionStart,
    transitionEnd: transitionEnd,
    overlapSeconds: overlapSeconds,
    beats: overlapBeats,
    bassSwapFraction: _bassSwapFractionFor(analysis, nextAnalysis, transitionStart, incomingCueTime,
        outgoingBeatSeconds, incomingBeatSeconds, overlapSeconds, overlapBeats),
    outgoingBpm: outgoingBpm,
    incomingBpm: incomingBpm,
    stretchRatio: stretchRatio,
    incomingCueTime: incomingCueTime,
    incomingDropTime: incomingDropTime,
    incomingHandoffTime: incomingHandoffTime,
    incomingResumeTime: incomingResumeTime,
  );
}

TransitionPlan? _phraseSwitch(
    TrackAnalysis analysis, TrackAnalysis nextAnalysis, double length, double nextLength, bool advanced) {
  if (!_harmonicallyCompatible(_trustedKey(analysis), _trustedKey(nextAnalysis))) return null;
  final result = _planWsolaTransition(analysis, nextAnalysis,
      duration: length, nextDuration: nextLength, advanced: advanced);
  if (result is! WsolaPlanned) return null;
  final planned = result;
  if (planned.stretchRatio < minIncomingRate || planned.stretchRatio > maxIncomingRate) return null;
  final overlap = planned.transitionEnd - planned.transitionStart;
  final renderedIncomingRate = _incomingRateFor(planned.stretchRatio, advanced);
  return TransitionPlan(
    markerVisible: true,
    transitionStart: planned.transitionStart,
    transitionEnd: planned.transitionEnd,
    fadeSeconds: overlap,
    handoffStartSeconds: 0.0,
    handoffDuration: overlap,
    incomingCueTime: planned.incomingCueTime,
    incomingHandoffTime: planned.incomingHandoffTime,
    incomingPlaybackRate: renderedIncomingRate,
    outgoingPlaybackRate: _outgoingRateFor(planned.stretchRatio, advanced),
    pickupSeconds: audibleStartOf(nextAnalysis),
    transitionBeats: planned.beats,
    bassSwap: true,
    handoffFraction: handoffFraction,
    bedPosition: bedPosition,
    bassSwapFraction: planned.bassSwapFraction,
    filterSweep: 0.0,
    vocalOverlap: _plannedVocalOverlap(analysis, nextAnalysis, planned.transitionStart, planned.transitionEnd,
        planned.incomingCueTime, renderedIncomingRate),
    outgoingBpm: planned.outgoingBpm,
    incomingBpm: planned.incomingBpm,
    beatSeconds: 60 / planned.outgoingBpm,
    phaseLock: false,
    transitionStyle: TransitionStyle.djBlend,
  );
}

double _incomingRateFor(double mediaRatio, bool advanced) =>
    _roundRate(clampFinite(mediaRatio, minIncomingRate, maxIncomingRate));

double _outgoingRateFor(double mediaRatio, bool advanced) => 1.0;

double _roundRate(double rate) => _roundToInt(rate * 10000) / 10000.0;

// ---- Advanced Automix --------------------------------------------------------------

const int _maxAdvancedBeats = 32;
const double _calmMaxSeconds = 16.0;
const int _energyWindowBeats = 8;
const double _calmEnergy = 0.7;
const double _vocalRerouteOverlap = 0.3;
const double _vocalSafeFallbackThreshold = 0.18;
const double _vocalMaskMissingProtection = 0.55;
const double _vocalRerouteGain = 0.5;
const int _maxRerouteCandidates = 3;

class _PairTraits {
  _PairTraits(TrackAnalysis analysis, TrackAnalysis nextAnalysis)
      : _currentBpm = analysis.bpm.orZero(),
        _nextBpm = nextAnalysis.bpm.orZero(),
        outgoingMeanEnergy = _meanEnergy(analysis.energyCurve),
        incomingMeanEnergy = _meanEnergy(nextAnalysis.energyCurve) {
    tempoFar = _currentBpm > 0 && _nextBpm > 0 && !stretchReachable(_currentBpm, _nextBpm);
    final left = _trustedKey(analysis);
    final right = _trustedKey(nextAnalysis);
    keyClash = left.isNotEmpty && right.isNotEmpty && !_harmonicallyCompatible(left, right);
    vocalConflict = analysis.vocalProbability >= _vocalConflictProbability &&
        nextAnalysis.vocalProbability >= _vocalConflictProbability;
    phaseLockable = _currentBpm > 0 &&
        _nextBpm > 0 &&
        !tempoFar &&
        analysis.beatConfidence.orZero() >= minBeatmatchConfidence &&
        nextAnalysis.beatConfidence.orZero() >= minBeatmatchConfidence;
    outgoingGrid = _currentBpm > 0 && analysis.beatConfidence.orZero() >= minDjConfidence;
  }

  final double _currentBpm;
  final double _nextBpm;
  late final bool tempoFar;
  late final bool keyClash;
  late final bool vocalConflict;
  late final bool phaseLockable;
  late final bool outgoingGrid;
  final double outgoingMeanEnergy;
  final double incomingMeanEnergy;
}

double _meanEnergy(List<EnergySample> curve) {
  var sum = 0.0;
  var count = 0;
  for (final point in curve) {
    if (point.energy.isFinite && point.energy >= 0) {
      sum += point.energy;
      count++;
    }
  }
  return count > 0 ? sum / count : 0.0;
}

double _energyScale(
    TrackAnalysis analysis, TrackAnalysis nextAnalysis, _PairTraits traits, double exitAt, double beatSeconds) {
  if (beatSeconds <= 0 || traits.outgoingMeanEnergy <= 0 || traits.incomingMeanEnergy <= 0) return 1.0;
  final window = _energyWindowBeats * beatSeconds;
  final entry = _incomingStartPoint(nextAnalysis);
  final out = _averageEnergy(analysis.energyCurve, exitAt - window, exitAt);
  if (out == null) return 1.0;
  final into = _averageEnergy(nextAnalysis.energyCurve, entry, entry + window);
  if (into == null) return 1.0;
  final outLevel = out / traits.outgoingMeanEnergy;
  final inLevel = into / traits.incomingMeanEnergy;
  return outLevel < _calmEnergy && inLevel < _calmEnergy ? 2.0 : 1.0;
}

double _wholeBars(double seconds, double beatSeconds, double maximum) {
  if (beatSeconds <= 0) return seconds;
  final bar = 4 * beatSeconds;
  var bars = _roundHalfEven(seconds / bar);
  if (bars * bar > maximum + 1e-6) bars = (maximum / bar + 1e-6).floorToDouble();
  return bars >= 1 ? bars * bar : seconds;
}

double _onDownbeatBefore(TrackAnalysis analysis, double time, double tolerance) =>
    _timedValueNearOrBefore(analysis.downbeats, time, tolerance: tolerance) ?? time;

({double overlap, int transitionBeats, double incomingPlaybackRate}) _adaptiveOverlap(
  TrackAnalysis analysis,
  TrackAnalysis nextAnalysis, {
  _PairTraits? traits,
  double energy = 1.0,
  FilterTransitionVariant filterVariant = FilterTransitionVariant.sweep,
}) {
  final currentBpm = analysis.bpm.orZero();
  final nextBpm = nextAnalysis.bpm.orZero();
  if (currentBpm <= 0 || nextBpm <= 0) {
    return (overlap: _autoFallbackSeconds, transitionBeats: 0, incomingPlaybackRate: 1.0);
  }
  final ratio = _normalizedTempoRatio(currentBpm, nextBpm);
  final int transitionBeats;
  if (traits == null) {
    final distance = _keyDistance(_trustedKey(analysis), _trustedKey(nextAnalysis));
    final vocalConflict = analysis.vocalProbability >= _vocalConflictProbability &&
        nextAnalysis.vocalProbability >= _vocalConflictProbability;
    transitionBeats =
        !vocalConflict && ((1 - ratio).abs() > 0.07 || (distance != null && distance > 4)) ? 16 : 8;
  } else {
    final base = traits.tempoFar
        ? (filterVariant == FilterTransitionVariant.sweep ? 12 : 8)
        : (traits.keyClash || traits.vocalConflict ? 8 : 16);
    transitionBeats = _roundToInt(base * energy).clamp(_minFadeBeats, _maxAdvancedBeats);
  }
  final beatSeconds = 60 / currentBpm;
  final minimumOverlap = currentBpm >= 140 ? _autoFastTrackMinSeconds : _autoMinSeconds;
  final maximumOverlap = traits != null && energy > 1 ? _calmMaxSeconds : _autoTransitionMaxSeconds;
  final overlap = clampFinite(transitionBeats * beatSeconds, minimumOverlap, maximumOverlap);
  final double incomingRate;
  if (traits != null) {
    incomingRate = traits.tempoFar ? 1.0 : _roundRate(1 / ratio);
  } else if (1 / ratio >= minIncomingRate && 1 / ratio <= maxIncomingRate) {
    incomingRate = _roundRate(1 / ratio);
  } else {
    incomingRate = 1.0;
  }
  return (
    overlap: traits != null ? _wholeBars(overlap, beatSeconds, maximumOverlap) : overlap,
    transitionBeats: transitionBeats,
    incomingPlaybackRate: incomingRate,
  );
}

const int echoRepeats = 5;
const double filterEchoAt = 0.5;
const double maxEchoSeconds = 1.0;

double echoTailSeconds(double echoSeconds) => echoSeconds * echoRepeats;

TransitionPlan _standardTransition(double length, double playbackTime, double fadeSeconds, double minFadeSeconds,
    [String reason = 'standard']) {
  final fade = clampFinite(fadeSeconds, minFadeSeconds, 12.0);
  final transitionStart = math.max(0.0, length - fade);
  final started = playbackTime >= transitionStart;
  return TransitionPlan(
    shouldStart: started,
    markerVisible: true,
    transitionStart: transitionStart,
    transitionEnd: length,
    fadeSeconds: fade,
    transitionStyle: TransitionStyle.equalPower,
    reason: started ? reason : 'before-$reason-window',
  );
}

bool _analysisReadyForTrack(TrackAnalysis analysis, TransitionTrackInfo? track) {
  if (analysis.status.trim().isEmpty) return true;
  if (analysis.status != TrackAnalysis.statusReady) return false;
  return analysis.trackId.trim().isEmpty ||
      track == null ||
      track.id.trim().isEmpty ||
      analysis.trackId == track.id;
}

TransitionPlan planTransition({
  TrackAnalysis analysis = const TrackAnalysis(),
  TrackAnalysis nextAnalysis = const TrackAnalysis(),
  TransitionTrackInfo? currentTrack,
  TransitionTrackInfo? nextTrack,
  double currentTime = 0.0,
  double duration = 0.0,
  double fadeSeconds = 6.0,
  double minFadeSeconds = 1.0,
  CrossfadeMode mode = CrossfadeMode.standard,
  bool albumSequential = false,
  bool advanced = false,
  int phraseBars = 0,
  bool mixWindow = false,
}) {
  final plan = _planTransitionInner(
    analysis: analysis,
    nextAnalysis: nextAnalysis,
    currentTrack: currentTrack,
    nextTrack: nextTrack,
    currentTime: currentTime,
    duration: duration,
    fadeSeconds: fadeSeconds,
    minFadeSeconds: minFadeSeconds,
    mode: mode,
    albumSequential: albumSequential,
    advanced: advanced,
    phraseBars: phraseBars,
  );
  if (!mixWindow) return plan;
  return _clampToMixWindow(plan,
      length: math.max(duration.orZero(), _trackDurationSeconds(currentTrack)),
      playbackTime: math.max(0.0, currentTime.orZero()));
}

TransitionPlan _clampToMixWindow(TransitionPlan plan, {required double length, required double playbackTime}) {
  if (plan.blocked || length <= 0.0) return plan;
  var result = plan;
  final earliestStart = math.max(0.0, length - _mixWindowSeconds);
  if (result.transitionStart < earliestStart) {
    final end = math.max(result.transitionEnd, earliestStart);
    result = result.copyWith(
      shouldStart: playbackTime >= earliestStart,
      transitionStart: earliestStart,
      transitionEnd: end,
      fadeSeconds: math.max(0.0, end - earliestStart),
    );
  }
  if (result.incomingCueTime > _mixWindowSeconds) result = result.copyWith(incomingCueTime: _mixWindowSeconds);
  return result;
}

TransitionPlan _planTransitionInner({
  required TrackAnalysis analysis,
  required TrackAnalysis nextAnalysis,
  TransitionTrackInfo? currentTrack,
  TransitionTrackInfo? nextTrack,
  required double currentTime,
  required double duration,
  required double fadeSeconds,
  required double minFadeSeconds,
  required CrossfadeMode mode,
  required bool albumSequential,
  required bool advanced,
  required int phraseBars,
}) {
  final length = math.max(duration.orZero(), _trackDurationSeconds(currentTrack));
  final playbackTime = math.max(0.0, currentTime.orZero());
  if (length <= 0) return _blocked('no-duration');

  final standardFade = clampFinite(fadeSeconds, minFadeSeconds, 12.0);
  if (mode != CrossfadeMode.smart) return _standardTransition(length, playbackTime, standardFade, minFadeSeconds);
  if (length < _minSmartDurationSeconds) {
    return _blocked('short-duration-guard', transitionStart: length, transitionEnd: length);
  }

  final analyzedContentEnd = _nonZeroOr(analysis.contentEndTime.orZero(), () => length);
  final finalMixAnchor = analyzedContentEnd > 0 && analyzedContentEnd <= length ? analyzedContentEnd : length;
  final rankedMixOuts = rankMixOutCandidates(analysis, contentEnd: finalMixAnchor, duration: length);
  final mixOutAnchor = rankedMixOuts.isNotEmpty
      ? MixOutAnchor(
          time: rankedMixOuts.first.time,
          type: rankedMixOuts.first.type,
          discardedMusicSeconds: rankedMixOuts.first.discardedMusicSeconds)
      : MixOutAnchor(time: finalMixAnchor, type: 'content_end', discardedMusicSeconds: 0.0);
  final hasInteriorMixOut = mixOutAnchor.time < finalMixAnchor - 1;

  if (albumSequential && _sameAlbum(currentTrack, nextTrack) && !hasInteriorMixOut) {
    final transitionStart = math.max(0.0, length - 0.45);
    final started = playbackTime >= transitionStart;
    return TransitionPlan(
      shouldStart: started,
      markerVisible: true,
      transitionStart: transitionStart,
      transitionEnd: length,
      fadeSeconds: 0.12,
      transitionStyle: TransitionStyle.gapless,
      reason: started ? 'same-album-gapless' : 'before-gapless-window',
    );
  }

  if (_isSpokenOrLive(currentTrack) || _isSpokenOrLive(nextTrack)) return _blocked('blocked-speech-or-live');

  if (!_analysisReadyForTrack(analysis, currentTrack) || !_analysisReadyForTrack(nextAnalysis, nextTrack)) {
    return _standardTransition(length, playbackTime, standardFade, minFadeSeconds, 'smart-analysis-fallback');
  }

  final preferredMixAnchor = math.min(length, mixOutAnchor.time);
  final mixAnchor = playbackTime >= preferredMixAnchor - 0.05 && preferredMixAnchor < finalMixAnchor - 1
      ? finalMixAnchor
      : preferredMixAnchor;

  final policy = assessTransitionTier(analysis, nextAnalysis, advanced: advanced);
  if (policy.tier == TransitionTier.plainCrossfade) {
    final transitionStart = math.max(0.0, mixAnchor - standardFade);
    final started = playbackTime >= transitionStart;
    return TransitionPlan(
      shouldStart: started,
      markerVisible: true,
      transitionStart: transitionStart,
      transitionEnd: mixAnchor,
      fadeSeconds: mixAnchor - transitionStart,
      transitionStyle: TransitionStyle.equalPower,
      incomingCueTime: _incomingStartPoint(nextAnalysis),
      policyReasons: policy.reasons,
      reason: started ? 'smart-plain-crossfade' : 'before-plain-crossfade-window',
    );
  }

  final nextLength = math.max(nextAnalysis.duration.orZero(), _trackDurationSeconds(nextTrack));

  if (_isUnmixablePair(analysis, nextAnalysis)) {
    final transitionStart = math.max(0.0, finalMixAnchor - standardFade);
    final incomingCueTime = _incomingStartPoint(nextAnalysis);
    final started = playbackTime >= transitionStart;
    return TransitionPlan(
      shouldStart: started,
      markerVisible: true,
      transitionStart: transitionStart,
      transitionEnd: finalMixAnchor,
      fadeSeconds: finalMixAnchor - transitionStart,
      transitionStyle: TransitionStyle.equalPower,
      incomingCueTime: incomingCueTime,
      incomingHandoffTime: incomingCueTime,
      vocalOverlap:
          _plannedVocalOverlap(analysis, nextAnalysis, transitionStart, finalMixAnchor, incomingCueTime, 1.0),
      policyReasons: [...policy.reasons, 'unmixable-pair'],
      reason: started ? 'smart-unmixable-crossfade' : 'before-unmixable-crossfade',
    );
  }

  if (phraseBars == phraseBarsShort || phraseBars == phraseBarsLong) {
    final plan = _phraseBarPlan(analysis, nextAnalysis, length, nextLength, phraseBars, mixAnchor, advanced);
    if (plan != null && playbackTime < plan.transitionEnd) {
      final started = playbackTime >= plan.transitionStart;
      return _capIncomingSkip(
        plan.copyWith(
          shouldStart: started,
          policyReasons: policy.reasons,
          reason: started ? 'smart-phrase-$phraseBars-bar' : 'before-phrase-$phraseBars-bar',
        ),
        nextAnalysis,
        nextLength,
      );
    }
  }

  final switched = _phraseSwitch(analysis, nextAnalysis, length, nextLength, advanced);
  if (switched != null && playbackTime < switched.transitionEnd) {
    final started = playbackTime >= switched.transitionStart;
    return _capIncomingSkip(
      switched.copyWith(
        shouldStart: started,
        policyReasons: policy.reasons,
        reason: started ? 'smart-phrase-switch' : 'before-phrase-switch',
      ),
      nextAnalysis,
      nextLength,
    );
  }

  final traits = advanced ? _PairTraits(analysis, nextAnalysis) : null;
  final primary = _mixPlan(analysis, nextAnalysis, mixAnchor, mixOutAnchor.type, nextLength, traits);
  var plan = primary;
  if (traits != null && primary.vocalOverlap > _vocalRerouteOverlap && playbackTime < primary.transitionStart) {
    TransitionPlan? best;
    for (final candidate in rankedMixOuts
        .where((c) => (c.time - mixAnchor).abs() > 1.0 && c.time <= length)
        .take(_maxRerouteCandidates)) {
      final alternative = _mixPlan(analysis, nextAnalysis, candidate.time, candidate.type, nextLength, traits);
      if (playbackTime >= alternative.transitionStart) continue;
      if (best == null || alternative.vocalOverlap < best.vocalOverlap) best = alternative;
    }
    if (best != null && best.vocalOverlap <= primary.vocalOverlap * _vocalRerouteGain) plan = best;
  }
  final started = playbackTime >= plan.transitionStart;
  return _capIncomingSkip(
    plan.copyWith(
      shouldStart: started,
      policyReasons: policy.reasons,
      reason: started ? plan.reason : 'before-${plan.reason}',
    ),
    nextAnalysis,
    nextLength,
  );
}

TransitionPlan _mixPlan(TrackAnalysis analysis, TrackAnalysis nextAnalysis, double mixAnchor, String mixOutType,
    double nextLength, _PairTraits? traits) {
  final currentBpm = analysis.bpm.orZero();
  final nextBpm = nextAnalysis.bpm.orZero();
  final gridBeatSeconds = traits?.outgoingGrid == true ? 60 / currentBpm : 0.0;
  final filterVariant = traits != null
      ? _fallbackVariantFor(analysis, nextAnalysis, mixAnchor, currentBpm > 0 ? 60 / currentBpm : 0.0)
      : FilterTransitionVariant.sweep;
  final energy = traits != null ? _energyScale(analysis, nextAnalysis, traits, mixAnchor, gridBeatSeconds) : 1.0;
  final adaptive =
      _adaptiveOverlap(analysis, nextAnalysis, traits: traits, energy: energy, filterVariant: filterVariant);
  final overlap = adaptive.overlap;
  final transitionBeats = adaptive.transitionBeats;
  final incomingPlaybackRate = adaptive.incomingPlaybackRate;
  final handoffBpm = currentBpm > 0 ? currentBpm : nextBpm;
  final sameBeatBlend = (traits == null || incomingPlaybackRate >= 1.0) &&
      (currentBpm > 0 &&
              nextBpm > 0 &&
              (1 - _normalizedTempoRatio(currentBpm, nextBpm)).abs() <= 0.05 &&
              (analysis.beatConfidence.orZero() >= 0.2 || nextAnalysis.beatConfidence.orZero() >= 0.2) ||
          traits?.phaseLockable == true);
  final outgoingArrangementOverlap = sameBeatBlend && mixOutType == 'content_end'
      ? math.min(arrangementOverlapBeats * 60 / currentBpm, maxDiscardedMusicSeconds)
      : 0.0;
  final arrangementEnd = math.max(0.0, mixAnchor - outgoingArrangementOverlap);
  final mixEnd =
      gridBeatSeconds > 0 ? _onDownbeatBefore(analysis, arrangementEnd, 4 * gridBeatSeconds) : arrangementEnd;
  final maxBeats = traits != null ? _maxAdvancedBeats.toDouble() : _autoTransitionMaxBeats;
  final fallbackMaxSeconds = filterVariant == FilterTransitionVariant.sweep ? 8.0 : 7.0;
  final double maxSeconds;
  if (traits != null && !sameBeatBlend) {
    maxSeconds = fallbackMaxSeconds;
  } else if (traits != null && energy > 1) {
    maxSeconds = _calmMaxSeconds;
  } else {
    maxSeconds = _autoTransitionMaxSeconds;
  }
  final maximumOverlap = [
    handoffBpm > 0 ? (maxBeats * 60) / handoffBpm : maxSeconds,
    maxSeconds,
    mixEnd * 0.4,
    nextLength > 0 ? nextLength * 0.4 : maxSeconds,
  ].reduce(math.min);
  final handoffBeats = sameBeatBlend ? 8 : 4;
  final beatSeconds = handoffBpm > 0 ? 60 / handoffBpm : 0.5;
  final handoffSeconds =
      handoffBpm > 0 ? clampFinite((handoffBeats * 60) / handoffBpm, 2.0, sameBeatBlend ? 6.0 : 5.0) : 4.0;
  final analyzedPickup = nextAnalysis.audibleStartTime ?? nextAnalysis.pickupTime;
  final pickupSeconds =
      analyzedPickup != null && analyzedPickup.isFinite && analyzedPickup >= 0 ? analyzedPickup : 0.0;
  final incomingDropTime = incomingCuePoint(nextAnalysis, latest: latestIncomingCue(nextLength));
  final alignedIncomingBpm = alignTempoOctave(currentBpm, nextBpm);
  final requestedIncomingHandoff = sameBeatBlend && alignedIncomingBpm > 0
      ? incomingDropTime + arrangementOverlapBeats * 60 / alignedIncomingBpm
      : incomingDropTime;
  final maxIncomingHandoff = nextLength - _minIncomingClearanceSeconds;
  final incomingHandoffTime = maxIncomingHandoff >= incomingDropTime
      ? math.min(requestedIncomingHandoff, maxIncomingHandoff)
      : incomingDropTime;
  final rawIncomingCueTime = _incomingStartPoint(nextAnalysis);

  final double finalIncomingCueTime;
  final double transitionStart;
  if (sameBeatBlend && beatSeconds > 0) {
    final introDropTime = incomingHandoffTime / math.max(0.8, incomingPlaybackRate);
    final clamped = clampFinite(introDropTime, math.min(12.0, maximumOverlap), maximumOverlap);
    final totalOverlap = traits != null ? _wholeBars(clamped, beatSeconds, maximumOverlap) : clamped;
    final targetStart = math.max(0.0, mixEnd - totalOverlap);
    final earliestTransitionStart = math.max(0.0, mixEnd - maximumOverlap);
    transitionStart = _alignedTransitionStart(analysis, targetStart, mixEnd - 0.05,
        preferEarlier: true, minimum: earliestTransitionStart);
    finalIncomingCueTime = math.max(0.0, incomingHandoffTime - (mixEnd - transitionStart) * incomingPlaybackRate);
  } else {
    final clamped = clampFinite(overlap, math.min(handoffSeconds, maximumOverlap), maximumOverlap);
    final actualOverlap = traits != null ? _wholeBars(clamped, beatSeconds, maximumOverlap) : clamped;
    final targetStart = math.max(0.0, mixEnd - actualOverlap);
    final earliestTransitionStart = math.max(0.0, mixEnd - maximumOverlap);
    transitionStart = _alignedTransitionStart(analysis, targetStart, mixEnd - 0.05,
        preferEarlier: false, minimum: earliestTransitionStart);
    finalIncomingCueTime = rawIncomingCueTime;
  }

  final alignedOverlap = mixEnd - transitionStart;
  final hasBassContent = analysis.lowEnergyCurve.isNotEmpty || nextAnalysis.lowEnergyCurve.isNotEmpty;
  final measuredVocalOverlap = _plannedVocalOverlap(
      analysis, nextAnalysis, transitionStart, mixEnd, finalIncomingCueTime, incomingPlaybackRate);
  final vocalOverlap = math.max(
    measuredVocalOverlap,
    traits?.vocalConflict == true &&
            (analysis.vocalActivityMask.isEmpty || nextAnalysis.vocalActivityMask.isEmpty)
        ? _vocalMaskMissingProtection
        : 0.0,
  );
  final vocalSafeFallback = !sameBeatBlend && vocalOverlap >= _vocalSafeFallbackThreshold;
  final resolvedFilterVariant = vocalSafeFallback ? FilterTransitionVariant.sweep : filterVariant;
  return TransitionPlan(
    markerVisible: true,
    transitionStart: transitionStart,
    transitionEnd: mixEnd,
    fadeSeconds: alignedOverlap,
    handoffStartSeconds: 0.0,
    handoffDuration: alignedOverlap,
    incomingCueTime: finalIncomingCueTime,
    incomingHandoffTime: incomingHandoffTime,
    incomingPlaybackRate: _incomingRateFor(incomingPlaybackRate, traits != null),
    outgoingPlaybackRate: _outgoingRateFor(incomingPlaybackRate, traits != null),
    pickupSeconds: pickupSeconds,
    transitionBeats: transitionBeats,
    bassSwap: sameBeatBlend || hasBassContent,
    transitionStyle: sameBeatBlend ? TransitionStyle.djBlend : TransitionStyle.djFilter,
    filterSweep: sameBeatBlend ? 0.0 : filterSweepFull,
    filterVariant: sameBeatBlend ? FilterTransitionVariant.sweep : resolvedFilterVariant,
    vocalOverlap: vocalOverlap,
    beatSeconds: gridBeatSeconds,
    phaseLock: false,
    echoSeconds: 0.0,
    reason: 'smart-duration',
  );
}
