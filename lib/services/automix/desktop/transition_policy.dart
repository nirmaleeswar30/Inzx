// Desktop Automix: the confidence-aware transition policy.
//
// Ported from BitChord's TransitionPolicy.kt (itself ported from Orchard,
// https://github.com/SFG5453/Orchard; AGPL-3.0 as combined into BitChord's
// GPL-3.0 work). Line for line, so desktop decides exactly what Android does.
//
// Copyright (C) 2026 SFG545 (original Orchard implementation)
// Copyright (C) 2026 Kushagra Singh (BitChord adaptation)
//
// This program is distributed in the hope that it will be useful, but
// WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero
// General Public License for more details.

import 'dart:math' as math;

import 'track_analysis.dart';

const double minBeatmatchConfidence = 0.55;
const double minDjConfidence = 0.2;
const double minBpm = 40.0;
const double maxBpm = 220.0;
const double minIncomingRate = 0.9;
const double maxIncomingRate = 1.25;
const double vocalActiveThreshold = 0.25;
const double _heuristicVocalThreshold = 0.6;
const double maxDiscardedMusicSeconds = 12.0;
const double _audibleEnergyFraction = 0.1;
const double vocalClashTolerance = 0.05;

const Map<String, double> _mixInTypeWeight = {
  'main_drop': 0.5,
  'intro_drop': 0.4,
  'pickup': 0.15,
  'phrase': 0.1,
};

const Map<String, double> _mixOutTypeScore = {
  'energy_cliff': 0.95,
  'interior_mix_out': 0.95,
  'outro_start': 0.9,
  'content_end': 0.75,
};

/// Kotlin's `sortedBy…`, which is stable; Dart's `List.sort` is not.
List<T> stableSorted<T>(Iterable<T> items, int Function(T a, T b) compare) {
  final indexed = [for (final (i, item) in items.indexed) (i, item)];
  indexed.sort((a, b) {
    final c = compare(a.$2, b.$2);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

extension DoubleOrZero on double {
  double orZero() => isFinite ? this : 0.0;
}

double orZeroN(double? v) => v != null && v.isFinite ? v : 0.0;

double clampFinite(double value, double min, double max) =>
    value.isFinite ? math.max(min, math.min(max, value)) : min;

double coerceIn(double value, double min, double max) => value < min ? min : (value > max ? max : value);

double incomingRateBetween(double outgoingBpm, double incomingBpm) {
  if (outgoingBpm <= 0 || incomingBpm <= 0) return double.nan;
  return outgoingBpm / alignTempoOctave(outgoingBpm, incomingBpm);
}

bool stretchReachable(double outgoingBpm, double incomingBpm) {
  final rate = incomingRateBetween(outgoingBpm, incomingBpm);
  return rate.isFinite && rate >= minIncomingRate - 1e-9 && rate <= maxIncomingRate + 1e-9;
}

double heuristicVocalOnModelScale(double value) {
  if (!value.isFinite) return value;
  final v = coerceIn(value, 0.0, 1.0);
  return v < _heuristicVocalThreshold
      ? v / _heuristicVocalThreshold * vocalActiveThreshold
      : vocalActiveThreshold +
          (v - _heuristicVocalThreshold) / (1 - _heuristicVocalThreshold) * (1 - vocalActiveThreshold);
}

double alignTempoOctave(double outgoingBpm, double incomingBpm) {
  if (outgoingBpm <= 0 || incomingBpm <= 0) return incomingBpm;
  var aligned = incomingBpm;
  while (aligned / outgoingBpm > 1.5) {
    aligned /= 2;
  }
  while (aligned / outgoingBpm < 0.67) {
    aligned *= 2;
  }
  return aligned;
}

double? vocalActivityBetween(TrackAnalysis analysis, double start, double end) {
  final mask = analysis.vocalActivityMask;
  final curve = analysis.energyCurve;
  if (mask.isEmpty || mask.length != curve.length || end <= start) return null;
  var sum = 0.0;
  var count = 0;
  for (var index = 0; index < mask.length; index++) {
    final time = curve[index].time;
    if (!time.isFinite || time < start || time > end) continue;
    final value = mask[index];
    if (!value.isFinite) continue;
    sum += value;
    count += 1;
  }
  return count > 0 ? sum / count : null;
}

bool isVocalClash(double? outgoingActivity, double? incomingActivity) =>
    outgoingActivity != null &&
    incomingActivity != null &&
    outgoingActivity >= vocalActiveThreshold &&
    incomingActivity >= vocalActiveThreshold;

double vocalOverlapAmount(double? outgoingActivity, double? incomingActivity) {
  if (outgoingActivity == null || incomingActivity == null) return 0.0;
  final both = math.min(outgoingActivity, incomingActivity);
  if (both <= vocalActiveThreshold) return 0.0;
  return coerceIn((both - vocalActiveThreshold) / (1.0 - vocalActiveThreshold), 0.0, 1.0);
}

double? simultaneousVocalFraction(
  TrackAnalysis outgoing,
  TrackAnalysis incoming,
  double outStart,
  double outEnd,
  double inStart,
  double rate,
) {
  final outMask = outgoing.vocalActivityMask;
  final outCurve = outgoing.energyCurve;
  final inMask = incoming.vocalActivityMask;
  final inCurve = incoming.energyCurve;
  if (outMask.isEmpty || outMask.length != outCurve.length) return null;
  if (inMask.isEmpty || inMask.length != inCurve.length) return null;
  if (outEnd <= outStart) return null;
  final step = rate.isFinite && rate > 0 ? rate : 1.0;
  var inIndex = 0;
  var both = 0;
  var total = 0;
  for (var index = 0; index < outMask.length; index++) {
    final time = outCurve[index].time;
    if (!time.isFinite || time < outStart) continue;
    if (time > outEnd) break;
    total += 1;
    if (outMask[index] < vocalActiveThreshold) continue;
    final target = inStart + (time - outStart) * step;
    while (inIndex + 1 < inCurve.length && inCurve[inIndex + 1].time <= target) {
      inIndex += 1;
    }
    if (inMask[inIndex] >= vocalActiveThreshold) both += 1;
  }
  return total > 0 ? both / total : null;
}

double? audibleSecondsBetween(TrackAnalysis analysis, double start, double end) {
  final curve = analysis.energyCurve;
  if (curve.length < 2 || end <= start) return null;
  final energies = [for (final p in curve) if (p.energy.isFinite && p.energy >= 0) p.energy]..sort();
  if (energies.isEmpty) return null;
  final reference = energies[((energies.length - 1) * 0.85).floor()].orZero();
  if (reference <= 0) return 0.0;
  final threshold = reference * _audibleEnergyFraction;
  final first = curve.first.time;
  final last = curve.last.time;
  if (!first.isFinite || !last.isFinite || last <= first) return null;
  final sampleSeconds = (last - first) / (curve.length - 1);
  var audible = 0.0;
  for (final point in curve) {
    if (!point.time.isFinite || point.time < start || point.time > end) continue;
    if (point.energy >= threshold) audible += sampleSeconds;
  }
  return audible;
}

double audibleStartOf(TrackAnalysis analysis) {
  final firstBeat = analysis.firstBeat.isFinite && analysis.firstBeat > 0 ? analysis.firstBeat : null;
  final candidates = [analysis.audibleStartTime, analysis.pickupTime, firstBeat]
      .whereType<double>()
      .where((v) => v.isFinite && v >= 0)
      .toList();
  if (candidates.isEmpty) return 0.0;
  return candidates.reduce(math.min);
}

double? nearestValue(List<double> values, double target, double tolerance) {
  double? best;
  for (final v in values) {
    if (!v.isFinite || (v - target).abs() > tolerance) continue;
    if (best == null || (v - target).abs() < (best - target).abs()) best = v;
  }
  return best;
}

List<RankedMixCandidate> rankMixInCandidates(TrackAnalysis analysis) {
  final candidates = analysis.mixInCandidates.where((c) => c.time.isFinite && c.time >= 0).toList();
  if (candidates.isEmpty) return const [];
  final interval = analysis.beatInterval.orZero();
  final beatSeconds = interval > 0 ? interval : (analysis.bpm.orZero() > 0 ? 60 / analysis.bpm : 0.5);
  final audibleStart = audibleStartOf(analysis);
  final ranked = [
    for (final candidate in candidates)
      () {
        var rankScore = candidate.score.orZero() + (_mixInTypeWeight[candidate.type] ?? 0.0);
        if (nearestValue(analysis.downbeats, candidate.time, beatSeconds / 2) != null) rankScore += 0.1;
        if (candidate.time - audibleStart < beatSeconds * 4) rankScore -= 0.2;
        final vocal = vocalActivityBetween(
          analysis,
          math.max(audibleStart, candidate.time - beatSeconds * 16),
          candidate.time,
        );
        if (vocal != null) rankScore += (0.5 - vocal) * 0.4;
        return RankedMixCandidate(
          time: candidate.time,
          score: candidate.score.orZero(),
          type: candidate.type,
          rankScore: rankScore,
        );
      }(),
  ];
  return stableSorted(ranked, (a, b) => b.rankScore.compareTo(a.rankScore));
}

List<MixCandidate> _mixOutCandidatesOf(TrackAnalysis analysis, double contentEnd) {
  final supplied = analysis.mixOutCandidates.where((c) => c.time.isFinite && c.time > 0).toList();
  final candidates = [for (final c in supplied) MixCandidate(c.time, c.score.orZero(), c.type)];
  if (supplied.isEmpty) {
    final mixOut = analysis.mixOutTime.orZero();
    final outroStart = analysis.outroStartTime.orZero();
    if (mixOut > 0 && mixOut < contentEnd - 1) candidates.add(MixCandidate(mixOut, 0.95, 'energy_cliff'));
    if (outroStart > 0 && outroStart < contentEnd - 1) {
      candidates.add(MixCandidate(outroStart, 0.9, 'outro_start'));
    }
  }
  if (!candidates.any((c) => (c.time - contentEnd).abs() < 0.05)) {
    candidates.add(MixCandidate(contentEnd, 0.75, 'content_end'));
  }
  return candidates;
}

double _resolveContentEnd(TrackAnalysis analysis, double contentEnd, double duration) {
  for (final v in [contentEnd.orZero(), analysis.contentEndTime.orZero(), duration.orZero()]) {
    if (v != 0.0) return v;
  }
  return analysis.duration.orZero();
}

List<RankedMixCandidate> rankMixOutCandidates(TrackAnalysis analysis,
    {double contentEnd = 0.0, double duration = 0.0}) {
  final end = _resolveContentEnd(analysis, contentEnd, duration);
  if (end <= 0) return const [];
  final ranked = [
    for (final candidate in _mixOutCandidatesOf(analysis, end))
      () {
        final measured = audibleSecondsBetween(analysis, candidate.time, end);
        return RankedMixCandidate(
          time: candidate.time,
          score: candidate.score,
          type: candidate.type,
          rankScore: candidate.score + (_mixOutTypeScore[candidate.type] ?? 0.0),
          discardedMusicSeconds: measured ?? math.max(0.0, end - candidate.time),
          measured: measured != null,
        );
      }(),
  ].where((c) => c.discardedMusicSeconds <= maxDiscardedMusicSeconds);
  return stableSorted(ranked, (a, b) {
    final byRank = b.rankScore.compareTo(a.rankScore);
    return byRank != 0 ? byRank : b.time.compareTo(a.time);
  });
}

MixOutAnchor resolveMixOutAnchor(TrackAnalysis analysis, {double contentEnd = 0.0, double duration = 0.0}) {
  final end = _resolveContentEnd(analysis, contentEnd, duration);
  final ranked = rankMixOutCandidates(analysis, contentEnd: end, duration: duration);
  final best = ranked.isEmpty ? null : ranked.first;
  return MixOutAnchor(
    time: best?.time ?? end,
    type: best?.type ?? 'content_end',
    discardedMusicSeconds: best?.discardedMusicSeconds ?? 0.0,
  );
}

TransitionPolicyVerdict assessTransitionTier(TrackAnalysis analysis, TrackAnalysis nextAnalysis,
    {bool advanced = false}) {
  final outgoingBpm = analysis.bpm.orZero();
  final incomingBpm = nextAnalysis.bpm.orZero();
  final outgoingConfidence = analysis.beatConfidence.orZero();
  final incomingConfidence = nextAnalysis.beatConfidence.orZero();
  final floorConfidence = math.min(outgoingConfidence, incomingConfidence);
  final reasons = <String>[];
  if (outgoingBpm < minBpm || outgoingBpm > maxBpm) reasons.add('outgoing-tempo');
  if (incomingBpm < minBpm || incomingBpm > maxBpm) reasons.add('incoming-tempo');
  if (reasons.isNotEmpty) {
    return TransitionPolicyVerdict(
        tier: TransitionTier.plainCrossfade, reasons: reasons, beatConfidence: floorConfidence);
  }
  if (outgoingConfidence < minDjConfidence && incomingConfidence < minDjConfidence) {
    return TransitionPolicyVerdict(
        tier: TransitionTier.plainCrossfade, reasons: const ['beat-confidence'], beatConfidence: floorConfidence);
  }
  if (!stretchReachable(outgoingBpm, incomingBpm)) reasons.add('tempo-distance');
  if (outgoingConfidence < minBeatmatchConfidence || incomingConfidence < minBeatmatchConfidence) {
    reasons.add('beat-confidence');
  }
  return TransitionPolicyVerdict(
    tier: reasons.isEmpty ? TransitionTier.beatmatched : TransitionTier.djAssisted,
    reasons: reasons,
    beatConfidence: floorConfidence,
  );
}
