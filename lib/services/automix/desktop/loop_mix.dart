// Desktop Automix: the loop mix.
//
// BitChord's LoopMix (com.music.bitchord.playback.smart, GPL-3.0), ported
// line for line: a clean bar-aligned loop near the end of the outgoing song
// and one near the start of the incoming song, their tempo ramped from one
// to the other bar by bar, the incoming loop then let go into its song.
// Android plays it through its sinks; desktop renders it with the same
// native renderer (loop_mix_renderer.cpp) and plays the result as a clip.

import 'dart:math' as math;

import 'track_analysis.dart';
import 'transition_policy.dart' show vocalActiveThreshold;

class LoopMix {
  static const int loopBars = 4;
  static const List<int> _loopLengths = [4, 2, 1];
  static const int enterBars = 4;
  static const int exitBars = 2;
  static const int settleBars = 2;
  static const double maxBpmPerBar = 2.5;
  static const int minRampBars = 2;
  static const int maxRampBars = 24;
  static const double maxSungShare = 0.03;
  static const double maxSungRunSec = 0.2;
  static const double minMaskCoverage = 0.8;
  static const double lyricGuardSec = 0.3;
  static const double lyricLeadSec = 0.15;
  static const double lyricTailSec = 0.35;
  static const double lyricOpenLineSec = 10.0;
  static const double openLineCertainSec = 2.0;
  static const double minLoudness = 0.6;
  static const double silentRms = 0.01;
  static const double outSearchSec = 60.0;
  static const double inSearchSec = 45.0;
  static const double handoverSec = 0.025;
  static const double bassCutDb = -18.0;
  static const double highPassFromHz = 20.0;
  static const double highPassToHz = 1500.0;

  static LoopMixPlan? plan({
    required TrackAnalysis out,
    required double outDuration,
    required TrackAnalysis inn,
    required double inDuration,
    required double earliestOutSec,
    List<SungSpan>? sungOut,
    List<SungSpan>? sungIn,
    StringBuffer? why,
  }) {
    final outGrid = _constantGrid(out);
    if (outGrid == null) {
      why?.write('no grid on the outgoing song');
      return null;
    }
    final inGrid = _constantGrid(inn);
    if (inGrid == null) {
      why?.write('no grid on the incoming song');
      return null;
    }
    final outCount = _Rejections();
    final inCount = _Rejections();
    final outEnd = outDuration - 0.5;
    final outFirst = math.max(earliestOutSec, outDuration - outSearchSec);
    final outPick = _firstClean(
      (bars) => _loopsBetween(out.tailBeats, outGrid, outFirst, outEnd, bars).reversed.toList(),
      out,
      sungOut,
      outGrid.beatSec,
      outCount,
    );
    if (outPick == null) {
      why?.write('outgoing: $outCount');
      return null;
    }
    final inEnd = math.min(inSearchSec + loopBars * inGrid.barSec, inDuration - 20);
    final inPick = _firstClean(
      (bars) => _loopsBetween(inn.headBeats, inGrid, 0.0, inEnd, bars),
      inn,
      sungIn,
      inGrid.beatSec,
      inCount,
    );
    if (inPick == null) {
      why?.write('incoming: $inCount');
      return null;
    }
    final outBeat = (outPick.end - outPick.start) / (outPick.bars * 4);
    final inBeat = (inPick.end - inPick.start) / (inPick.bars * 4);
    final outBpm = 60 / outBeat;
    final inBpm = 60 / inBeat;
    var fold = 1.0;
    for (final f in const [1.0, 2.0, 0.5]) {
      if ((math.log(inBpm / f / outBpm)).abs() < (math.log(inBpm / fold / outBpm)).abs()) fold = f;
    }
    final target = inBpm / fold;
    final rampBars = ((target - outBpm).abs() / maxBpmPerBar).ceil().clamp(minRampBars, maxRampBars);
    final inLoopOutBars = inPick.bars / fold;
    final totalBars = (((enterBars + rampBars + exitBars) / inLoopOutBars).ceil() * inLoopOutBars).round();
    LoopPick pick(_Clean clean, double beatSec, double bpm) => LoopPick(
          loopStart: clean.start,
          loopEnd: clean.end,
          bars: clean.bars,
          beatSec: beatSec,
          bpm: bpm,
          vocal: clean.vocal,
          checkedBy: clean.checkedBy,
        );
    return LoopMixPlan(
      out: pick(outPick, outBeat, outBpm),
      inn: pick(inPick, inBeat, inBpm),
      fold: fold,
      enterBars: enterBars,
      rampBars: rampBars,
      exitBars: totalBars - enterBars - rampBars,
      totalBars: totalBars,
    );
  }

  static _Grid? _constantGrid(TrackAnalysis analysis) {
    double? beat;
    if (analysis.beatInterval.isFinite && analysis.beatInterval > 0) {
      beat = analysis.beatInterval;
    } else if (analysis.bpm.isFinite && analysis.bpm > 0) {
      beat = 60 / analysis.bpm;
    }
    if (beat == null) return null;
    double anchor = analysis.firstBeat;
    for (final d in analysis.downbeats) {
      if (d.isFinite) {
        anchor = d;
        break;
      }
    }
    if (!anchor.isFinite) return null;
    return _Grid(beat, anchor);
  }

  static List<_Loop> _loopsBetween(BeatSide? side, _Grid grid, double from, double to, int bars) {
    final loops = <_Loop>[];
    if (side != null && side.bpm > 0 && side.downbeats.length >= bars + 1) {
      final beat = 60 / side.bpm;
      final downs = side.downbeats;
      for (final start in downs) {
        if (start < from) continue;
        final target = start + bars * 4 * beat;
        final end = _nearest(downs, target);
        if ((end - target).abs() > beat / 4 || end > to) continue;
        loops.add(_Loop(start, end));
      }
      if (loops.isNotEmpty) return loops;
    }
    if (to < from) return loops;
    final bar = grid.barSec;
    final length = bars * bar;
    var t = grid.anchor + ((from - grid.anchor) / bar).ceilToDouble() * bar;
    while (t + length <= to) {
      loops.add(_Loop(t, t + length));
      t += bar;
    }
    return loops;
  }

  static double _nearest(List<double> sorted, double target) {
    var low = 0;
    var high = sorted.length - 1;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (sorted[mid] < target) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    final after = sorted[low];
    if (low - 1 < 0) return after;
    final before = sorted[low - 1];
    return (before - target).abs() <= (after - target).abs() ? before : after;
  }

  static _Clean? _firstClean(
    List<_Loop> Function(int bars) candidates,
    TrackAnalysis analysis,
    List<SungSpan>? sung,
    double beatSec,
    _Rejections count,
  ) {
    for (final bars in _loopLengths) {
      final loops = candidates(bars);
      if (loops.isEmpty) continue;
      count.loops += loops.length;
      final louds = [for (final loop in loops) _quietestBar(analysis.levelWindows, loop, bars)];
      final known = louds.where((v) => !v.isNaN).toList()..sort();
      final typical = known.isEmpty ? double.nan : known[math.min(known.length - 1, (known.length * 0.6).floor())];
      for (var index = 0; index < loops.length; index++) {
        final loop = loops[index];
        final loud = louds[index];
        if (!loud.isNaN && (loud < typical * minLoudness || loud <= silentRms)) {
          count.quiet++;
          continue;
        }
        if (sung != null) {
          final from = loop.start - lyricGuardSec;
          final touching = sung.where((s) => s.start < loop.end && s.end > from).toList();
          if (touching.any((s) => s.start < loop.end && s.certainUntil > from)) {
            count.lyrics++;
            continue;
          }
          if (touching.isEmpty) return _Clean(loop.start, loop.end, bars, 0.0, LoopCheck.lyrics);
          final mask = maskStats(analysis.vocalWindows, loop.start - beatSec, loop.end);
          if (mask == null) {
            count.unmasked++;
            continue;
          }
          if (mask.share > maxSungShare || mask.longestRunSec > maxSungRunSec) {
            count.sung++;
            continue;
          }
          return _Clean(loop.start, loop.end, bars, mask.share, LoopCheck.lyricsAndMask);
        }
        final mask = maskStats(analysis.vocalWindows, loop.start - beatSec, loop.end);
        if (mask == null) {
          count.unmasked++;
          continue;
        }
        if (mask.share > maxSungShare || mask.longestRunSec > maxSungRunSec) {
          count.sung++;
          continue;
        }
        return _Clean(loop.start, loop.end, bars, mask.share, LoopCheck.mask);
      }
    }
    return null;
  }

  static double _quietestBar(List<CurveWindow> windows, _Loop loop, int bars) {
    if (windows.isEmpty) return double.nan;
    var quietest = double.infinity;
    final bar = (loop.end - loop.start) / bars;
    for (var b = 0; b < bars; b++) {
      final rms = _meanRms(windows, loop.start + b * bar, loop.start + (b + 1) * bar);
      if (rms.isNaN) return double.nan;
      quietest = math.min(quietest, rms);
    }
    return quietest;
  }

  static double _meanRms(List<CurveWindow> windows, double from, double to) {
    var sumSquares = 0.0;
    var count = 0;
    for (final window in windows) {
      final a = math.max(0, ((from - window.startTime) * window.frameRate).ceil());
      final b = math.min(window.values.length, ((to - window.startTime) * window.frameRate).floor());
      for (var i = a; i < b; i++) {
        final rms = rmsFromLevel(window.values[i].toDouble());
        sumSquares += rms * rms;
        count++;
      }
    }
    return count == 0 ? double.nan : math.sqrt(sumSquares / count);
  }

  static ({double share, double longestRunSec})? maskStats(List<CurveWindow> windows, double from, double to) {
    var sung = 0;
    var n = 0;
    var covered = 0.0;
    var run = 0;
    var longest = 0;
    var fps = 1.0;
    for (final window in windows) {
      final a = math.max(0, ((from - window.startTime) * window.frameRate).ceil());
      final b = math.min(window.values.length, ((to - window.startTime) * window.frameRate).floor());
      for (var i = a; i < b; i++) {
        n++;
        if (window.values[i] > vocalActiveThreshold) {
          sung++;
          run++;
          longest = math.max(longest, run);
        } else {
          run = 0;
        }
      }
      if (b > a) {
        covered += (b - a) / window.frameRate;
        fps = window.frameRate;
      }
    }
    return n > 0 && covered >= (to - from) * minMaskCoverage
        ? (share: sung / n, longestRunSec: longest / fps)
        : null;
  }

  /// Where a voice is, from synced lyric lines.
  static List<SungSpan> sungSpans(List<LoopLyricLine> lines) {
    final sorted = [...lines]..sort((a, b) => a.timeMs.compareTo(b.timeMs));
    final spans = <SungSpan>[];
    for (var index = 0; index < sorted.length; index++) {
      final line = sorted[index];
      if (line.blank) continue;
      final start = line.timeMs / 1000.0;
      int? next;
      for (var j = index + 1; j < sorted.length; j++) {
        if (sorted[j].timeMs > line.timeMs) {
          next = sorted[j].timeMs;
          break;
        }
      }
      final stated = line.endMs != null && line.endMs! > line.timeMs;
      final end = stated
          ? line.endMs! / 1000.0
          : math.min(start + lyricOpenLineSec, (next ?? (line.timeMs + 10000)) / 1000.0);
      final certain = stated ? end : math.min(end, start + openLineCertainSec);
      spans.add(SungSpan(start - lyricLeadSec, end + lyricTailSec, certain + lyricTailSec));
    }
    return spans;
  }
}

enum LoopCheck { lyrics, mask, lyricsAndMask }

class SungSpan {
  const SungSpan(this.start, this.end, [double? certainUntil]) : certainUntil = certainUntil ?? end;
  final double start;
  final double end;
  final double certainUntil;
}

class LoopLyricLine {
  const LoopLyricLine(this.timeMs, this.endMs, {required this.blank});
  final int timeMs;
  final int? endMs;
  final bool blank;
}

class LoopPick {
  const LoopPick({
    required this.loopStart,
    required this.loopEnd,
    required this.bars,
    required this.beatSec,
    required this.bpm,
    required this.vocal,
    required this.checkedBy,
  });
  final double loopStart;
  final double loopEnd;
  final int bars;
  final double beatSec;
  final double bpm;
  final double vocal;
  final LoopCheck checkedBy;
  int get beats => bars * 4;
}

class LoopMixPlan {
  const LoopMixPlan({
    required this.out,
    required this.inn,
    required this.fold,
    required this.enterBars,
    required this.rampBars,
    required this.exitBars,
    required this.totalBars,
  });
  final LoopPick out;
  final LoopPick inn;
  final double fold;
  final int enterBars;
  final int rampBars;
  final int exitBars;
  final int totalBars;
  double get targetBpm => inn.bpm / fold;

  /// "out 4-bar, clear by mask · in 2-bar, clear by lyrics · 111 → 85 BPM over 11 bars".
  String describe() {
    final from = out.bpm.round();
    final to = targetBpm.round();
    final tempo = from == to ? '$from BPM' : '$from → $to BPM over $rampBars bars';
    final folded = fold > 1 ? ' (next in double time)' : (fold < 1 ? ' (next in half time)' : '');
    String side(LoopPick pick) => '${pick.bars}-bar, clear by ${switch (pick.checkedBy) {
          LoopCheck.lyrics => 'lyrics',
          LoopCheck.mask => 'mask',
          LoopCheck.lyricsAndMask => 'lyrics + mask',
        }}';
    return 'out ${side(out)} · in ${side(inn)} · $tempo$folded';
  }
}

/// The mix's beat clock: mix seconds of every beat, and where each deck is.
class LoopMixClock {
  LoopMixClock(this.plan)
      : beats = plan.totalBars * 4,
        settleBeats = (LoopMix.settleBars * 4 / plan.fold).round(),
        rampFrom = plan.enterBars * 4,
        rampTo = (plan.enterBars + plan.rampBars) * 4 {
    beatTimes = List<double>.filled(beats + settleBeats + 1, 0);
    for (var k = 0; k < beats + settleBeats; k++) {
      beatTimes[k + 1] = beatTimes[k] + 60 / tempo(k);
    }
  }

  final LoopMixPlan plan;
  final int beats;
  final int settleBeats;
  final int rampFrom;
  final int rampTo;
  late final List<double> beatTimes;

  double tempo(int k) {
    if (k < rampFrom) return plan.out.bpm;
    if (k >= rampTo) return plan.targetBpm;
    return plan.out.bpm + (plan.targetBpm - plan.out.bpm) * (k - rampFrom + 0.5) / (rampTo - rampFrom);
  }

  double get enterEnd => beatTimes[rampFrom];
  double get rampEnd => beatTimes[rampTo];
  double get handoffAt => beatTimes[(rampFrom + rampTo) ~/ 2];
  double get swapBar => 4 * 60 / tempo((rampFrom + rampTo) ~/ 2);
  double get releaseAt => beatTimes[beats];
  double get elementAt => beatTimes[beats + settleBeats];
  double get elementTrackTime => plan.inn.loopEnd + (elementAt - releaseAt);

  double outPositionAt(int k) => plan.out.loopStart + k * plan.out.beatSec;
  double inPositionAt(int k) => plan.inn.loopStart + k * plan.fold * plan.inn.beatSec;
  double get inReleasePosition => inPositionAt(beats);

  (int, double) beatAt(double t) {
    if (t < 0) return (-1, 0.0);
    var low = 0;
    var high = beatTimes.length - 1;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (beatTimes[mid] <= t) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    final k = low;
    if (k + 1 >= beatTimes.length) return (k, 0.0);
    return (k, math.min(1.0, (t - beatTimes[k]) / (beatTimes[k + 1] - beatTimes[k])));
  }

  /// Where a deck is in its own song at mix second [t], or null once the
  /// outgoing deck has let go.
  double? outgoingAt(double t) {
    if (t < 0 || t >= releaseAt) return null;
    final (k, frac) = beatAt(t);
    if (k >= beats) return null;
    return plan.out.loopStart + ((k % plan.out.beats) + frac) * plan.out.beatSec;
  }

  double? incomingAt(double t) {
    if (t < 0) return null;
    if (t >= releaseAt) return plan.inn.loopEnd + (t - releaseAt);
    final (k, frac) = beatAt(t);
    if (k >= beats) return null;
    return plan.inn.loopStart + (((k * plan.fold) % plan.inn.beats) + frac * plan.fold) * plan.inn.beatSec;
  }
}

class _Grid {
  _Grid(this.beatSec, this.anchor);
  final double beatSec;
  final double anchor;
  double get barSec => beatSec * 4;
}

class _Loop {
  _Loop(this.start, this.end);
  final double start;
  final double end;
}

class _Clean extends _Loop {
  _Clean(super.start, super.end, this.bars, this.vocal, this.checkedBy);
  final int bars;
  final double vocal;
  final LoopCheck checkedBy;
}

class _Rejections {
  int loops = 0, quiet = 0, lyrics = 0, unmasked = 0, sung = 0;
  @override
  String toString() => loops == 0
      ? 'no bar lines in the search'
      : '$loops loops: $quiet quiet, $lyrics sung (lyrics), $sung sung (mask), $unmasked unmeasured';
}
