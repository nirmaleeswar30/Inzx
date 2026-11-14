// Desktop Automix: how a planned transition sounds, as curves over the blend.
//
// BitChord's CrossfadeController (com.music.bitchord.playback, GPL-3.0)
// rides two players' faders and filters live, every tick, as functions of
// the blend's progress. Desktop renders the blend instead, so the same
// functions are evaluated ahead of time and handed to the renderer as
// envelopes. Everything here is that code moved to Dart: Render's beat
// snapping, mixRise/mixFall, and every rideStyle branch with its constants.
//
// Since a render is sample-accurate, the controller's sink-lead offsets
// (filters aimed seconds ahead of the speaker) have no counterpart: each
// curve is simply evaluated at the progress being heard.

import 'dart:math' as math;
import 'dart:typed_data';

import 'transition_planner.dart';

// TransitionFilterProcessor's.
const double openHz = 20000.0;
const double offHz = 20.0;

// CrossfadeController's.
const double _filterEntryHz = 7000.0;
const double _filterFloorHz = 300.0;
const double _bassSwapHz = 200.0;
const double _bassSwapWidth = 0.10;
const double _swapBeats = 0.5;
const double _filterBassSwapAt = 0.5;
const double _filterFallShape = 1.6;
const double _filterRiseShape = 0.8;
const double _fallbackHandoffEntryHz = 900.0;
const double _fallbackHandoffFloorHz = 1600.0;
const double _fallbackHandoffShape = 0.8;
const double _vocalSafeEntryHighPassHz = 2400.0;
const double _vocalSafeEntryOpenBy = 0.78;
const double _vocalSafeExitShape = 0.55;
const double _vocalSafeRiseShape = 1.65;
const double _vocalSafeFallShape = 0.65;
const double _echoKillBeats = 4.0;
const double _filterSweepShape = 0.75;
const double _entryHighPassHz = 1200.0;
const double _entryOpenBy = 0.6;
const double _entryShape = 0.35;
const double _vocalSeparationFloorHz = 1600.0;
const double _vocalSeparationHighPassHz = 700.0;
const double _blendEntryHighPassHz = 520.0;
const double _blendEntryOpenBy = 0.45;
const double _blendEntryClashHighPassHz = 950.0;
const double _blendEntryClashOpenBy = 0.7;
const double _blendExitClashFrom = 0.12;
const double _blendExitClashLowPassHz = 1100.0;
const double _blendExitFrom = 0.3;
const double _blendExitLowPassHz = 2200.0;
const double handoffAtDefault = 0.5;

/// Tempo ease-back after a stretched blend: one step a beat.
const double tempoStepPerBeat = 0.0075;
const double easeDone = 1e-4;

int rampStepsFor(double rate) {
  final stretch = (rate - 1.0).abs();
  return stretch < easeDone ? 0 : (stretch / tempoStepPerBeat).ceil();
}

double _kotlinRound(double x) {
  final floor = x.floorToDouble();
  final diff = x - floor;
  if (diff > 0.5) return floor + 1;
  if (diff < 0.5) return floor;
  return floor % 2 == 0 ? floor : floor + 1;
}

double _coerce(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

/// BitChord's Render: the plan resolved onto the blend's own beat grid.
class Render {
  Render({
    this.style = TransitionStyle.equalPower,
    this.bassSwap = false,
    double bassSwapFraction = 0.7,
    this.filterSweep = 0.0,
    this.filterVariant = FilterTransitionVariant.sweep,
    this.vocalOverlap = 0.0,
    this.advanced = false,
    double beats = 0.0,
    double echoSeconds = 0.0,
  }) {
    _grid = advanced && beats >= 2.0 ? beats : 0.0;
    clash = _coerce(vocalOverlap, 0.0, 1.0);
    echo = _grid > 0 && echoSeconds > 0.0;
    this.echoSeconds = echoSeconds;
    swapAt = _onBeat(_coerce(bassSwapFraction, 0.05, 0.95));
    swapWidth = _grid > 0 ? _swapBeats / _grid : 2 * _bassSwapWidth;
    swapFrom = _grid > 0 ? swapAt - swapWidth : swapAt - _bassSwapWidth;
    final entryOpenBy = _onBar(switch (filterVariant) {
      FilterTransitionVariant.sweep => _entryOpenBy,
      FilterTransitionVariant.bassHandoff => 0.38,
      FilterTransitionVariant.echoRide => 0.52,
    });
    vocalEntryOpenBy = _onBar(entryOpenBy + (_vocalSafeEntryOpenBy - entryOpenBy) * clash);
    blendEntryOpenBy = _onBar(_blendEntryOpenBy + (_blendEntryClashOpenBy - _blendEntryOpenBy) * clash);
    blendExitFrom = _onBar(_blendExitFrom + (_blendExitClashFrom - _blendExitFrom) * clash);
    filterSwapAt = _onBar(switch (filterVariant) {
      FilterTransitionVariant.sweep => _filterBassSwapAt,
      FilterTransitionVariant.bassHandoff => 0.43,
      FilterTransitionVariant.echoRide => 0.58,
    });
    echoAt = _onBar(filterEchoAt);
    echoFrom = _grid > 0 ? echoAt - 1.0 / _grid : echoAt;
    echoKill = _grid > 0 ? _echoKillBeats / _grid : 0.0;
    holdFaders = 1.0 - clash;
    fallFrom = math.max(
        0.0, [swapAt, 0.5, _grid > 0 ? 1.0 - 4.0 / _grid : 0.5].reduce(math.min));
    if (!advanced) {
      handoffAt = handoffAtDefault;
    } else if (style == TransitionStyle.djBlend && bassSwap) {
      handoffAt = swapAt;
    } else if (style == TransitionStyle.djFilter && filterVariant == FilterTransitionVariant.bassHandoff) {
      handoffAt = filterSwapAt;
    } else {
      handoffAt = handoffAtDefault;
    }
  }

  final TransitionStyle style;
  final bool bassSwap;
  final double filterSweep;
  final FilterTransitionVariant filterVariant;
  final double vocalOverlap;
  final bool advanced;
  late final double _grid;
  late final double clash;
  late final bool echo;
  late final double echoSeconds;
  late final double swapAt;
  late final double swapWidth;
  late final double swapFrom;
  late final double vocalEntryOpenBy;
  late final double blendEntryOpenBy;
  late final double blendExitFrom;
  late final double filterSwapAt;
  late final double echoAt;
  late final double echoFrom;
  late final double echoKill;
  late final double holdFaders;
  late final double fallFrom;
  late final double handoffAt;

  double _onBeat(double fraction) => _grid > 0
      ? _coerce(_kotlinRound(fraction * _grid) / _grid, 1.0 / _grid, 1.0 - 1.0 / _grid)
      : fraction;

  double _onBar(double fraction) => _grid >= 8.0
      ? _coerce(_kotlinRound(fraction * _grid / 4.0) * 4.0 / _grid, 4.0 / _grid, 1.0 - 4.0 / _grid)
      : _onBeat(fraction);

  /// Built from a plan the way considerSmartTransition builds one.
  factory Render.forPlan(TransitionPlan plan, {bool advanced = true}) => Render(
        style: plan.transitionStyle,
        bassSwap: plan.bassSwap,
        bassSwapFraction: plan.bassSwapFraction,
        filterSweep: plan.filterSweep,
        filterVariant: plan.filterVariant,
        vocalOverlap: plan.vocalOverlap,
        advanced: advanced,
        beats: plan.beatSeconds > 0 ? plan.fadeSeconds / plan.beatSeconds : 0.0,
        echoSeconds: plan.echoSeconds,
      );

  /// Whether this is something a plain crossfade couldn't be (isRealMix).
  bool isRealMix(TransitionPlan plan) =>
      style == TransitionStyle.djBlend ||
      style == TransitionStyle.djFilter ||
      plan.incomingCueTime > 0 ||
      plan.incomingPlaybackRate != 1.0 ||
      plan.outgoingPlaybackRate != 1.0;
}

/// One instant of the blend: both faders, both filters, the echo.
class BlendFrame {
  double inGain = 0, outGain = 1;
  double inLow = openHz, inHigh = offHz;
  double outLow = openHz, outHigh = offHz;
  double echoSend = 0, echoDry = 1;
  bool echoEngaged = false;
}

/// The controller's per-tick automation as pure functions of [progress].
class BlendAutomation {
  BlendAutomation(this.render);
  final Render render;

  static double _glide(double from, double to, double amount) =>
      from * math.pow(to / from, _coerce(amount, 0.0, 1.0));

  static double riseGain(double progress) => math.sin(_coerce(progress, 0, 1) * math.pi / 2);
  static double fallGain(double progress) => math.cos(_coerce(progress, 0, 1) * math.pi / 2);

  double _held(double plain, double dj) => plain + (dj - plain) * render.holdFaders;

  double mixRise(double progress) {
    if (!render.advanced) return riseGain(progress);
    final double styled;
    switch (render.style) {
      case TransitionStyle.djBlend:
        styled = render.bassSwap
            ? _held(riseGain(progress), riseGain(progress / render.swapAt))
            : riseGain(progress);
      case TransitionStyle.djFilter:
        styled = riseGain(math.pow(progress, _filterRiseShape).toDouble());
      default:
        styled = riseGain(progress);
    }
    final vocalSafe = riseGain(math.pow(progress, _vocalSafeRiseShape).toDouble());
    return styled + (vocalSafe - styled) * render.clash;
  }

  double mixFall(double progress) {
    if (!render.advanced) return fallGain(progress);
    if (render.echo) return 1.0;
    final double styled;
    switch (render.style) {
      case TransitionStyle.djBlend:
        if (!render.bassSwap) {
          styled = fallGain(progress);
        } else {
          final from = render.fallFrom;
          styled = _held(fallGain(progress), progress <= from ? 1.0 : fallGain((progress - from) / (1.0 - from)));
        }
      case TransitionStyle.djFilter:
        styled = fallGain(math.pow(progress, _filterFallShape).toDouble());
      default:
        styled = fallGain(progress);
    }
    final vocalSafe = fallGain(math.pow(progress, _vocalSafeFallShape).toDouble());
    return styled + (vocalSafe - styled) * render.clash;
  }

  double _echoDry(double progress) =>
      1.0 - _coerce((progress - render.echoAt) / render.echoKill, 0.0, 1.0);

  /// The outgoing track's real level, for the headroom trim.
  double outgoingLevel(double progress, double wallSpanMs) {
    if (!render.echo) return mixFall(progress);
    final sinceEcho = (progress - render.echoAt) * wallSpanMs;
    final repeats = sinceEcho > 0 ? sinceEcho / (render.echoSeconds * 1000) : 0.0;
    final wet = sinceEcho > 0 ? 0.5 * math.pow(0.4, repeats) : 0.0;
    return math.max(_echoDry(progress), wet.toDouble());
  }

  static double headroomFor(double incomingGain, double outgoingGain) {
    final sum = incomingGain + outgoingGain;
    return sum <= 1 ? 1.0 : 1 / math.sqrt(sum);
  }

  double _bassCutoff(double amount) => _glide(offHz, _bassSwapHz, amount);

  double _entryHighPass(double progress, double amount, double topHz, double openBy) {
    final remaining = _coerce(1.0 - progress / openBy, 0.0, 1.0);
    return _glide(offHz, topHz, amount * math.pow(remaining, _entryShape));
  }

  /// Every filter and fader at [progress].
  BlendFrame at(double progress, double wallSpanMs) {
    final f = BlendFrame()
      ..inGain = mixRise(progress)
      ..outGain = mixFall(progress);
    _rideStyle(progress, f);
    return f;
  }

  void _rideStyle(double p, BlendFrame f) {
    switch (render.style) {
      case TransitionStyle.djFilter:
        if (render.filterVariant == FilterTransitionVariant.bassHandoff) {
          _rideFallbackBassHandoff(p, f);
        } else {
          _rideFilterSweep(p, f);
        }
      case TransitionStyle.djBlend:
        if (render.bassSwap) {
          _rideBassSwap(p, f);
        } else {
          _rideVocalSeparation(p, f);
        }
      case TransitionStyle.gapless:
        break; // open
      case TransitionStyle.equalPower:
        _rideVocalSeparation(p, f);
    }
    if (render.echo) _rideEchoOut(p, f);
  }

  void _rideEchoOut(double p, BlendFrame f) {
    final handover = _coerce((p - (render.echoAt - render.swapWidth)) / render.swapWidth, 0.0, 1.0);
    f.outLow = openHz;
    f.outHigh = _bassCutoff(handover);
    if (p < render.echoFrom) return;
    final send = p >= render.echoAt ? 0.0 : (p - render.echoFrom) / (render.echoAt - render.echoFrom);
    f.echoEngaged = true;
    f.echoSend = send;
    f.echoDry = _echoDry(p);
  }

  void _rideVocalSeparation(double p, BlendFrame f) {
    final amount = _coerce(render.vocalOverlap, 0.0, 1.0);
    if (amount <= 0.0) return; // open
    final floor = _glide(openHz, _vocalSeparationFloorHz, amount);
    f.outLow = _glide(openHz, floor, math.pow(p, _filterSweepShape).toDouble());
    f.outHigh = offHz;
    f.inLow = openHz;
    f.inHigh = _entryHighPass(p, amount, _vocalSeparationHighPassHz, _entryOpenBy);
  }

  void _rideFilterSweep(double p, BlendFrame f) {
    final sweep = _coerce(render.filterSweep, 0.0, 1.0);
    if (sweep <= 0.0) return;
    final entry = _glide(openHz, _filterEntryHz, sweep);
    final floor = _glide(openHz, _filterFloorHz, sweep);
    final cutoff = _glide(entry, floor, math.pow(p, _filterSweepShape).toDouble());
    final entryCorner = _entryHighPass(
      p,
      sweep,
      _glide(_entryHighPassHz, _vocalSafeEntryHighPassHz, render.clash),
      render.vocalEntryOpenBy,
    );
    final handover =
        _coerce((p - (render.filterSwapAt - render.swapWidth)) / render.swapWidth, 0.0, 1.0);
    f.outLow = cutoff;
    f.outHigh = _bassCutoff(handover);
    f.inLow = openHz;
    f.inHigh = math.max(entryCorner, _bassCutoff(1.0 - handover));
  }

  void _rideFallbackBassHandoff(double p, BlendFrame f) {
    final handover =
        _coerce((p - (render.filterSwapAt - render.swapWidth)) / render.swapWidth, 0.0, 1.0);
    final exitAmount = _coerce((p - render.filterSwapAt) / (1.0 - render.filterSwapAt), 0.0, 1.0);
    final handoffTone =
        _glide(openHz, _fallbackHandoffFloorHz, math.pow(exitAmount, _fallbackHandoffShape).toDouble());
    final vocalTone =
        _glide(openHz, _vocalSeparationFloorHz, render.clash * math.pow(p, _vocalSafeExitShape));
    final incomingEntry = _entryHighPass(
      p,
      1.0,
      _glide(_fallbackHandoffEntryHz, _vocalSafeEntryHighPassHz, render.clash),
      render.vocalEntryOpenBy,
    );
    f.outLow = math.min(handoffTone, vocalTone);
    f.outHigh = _bassCutoff(handover);
    f.inLow = openHz;
    f.inHigh = math.max(incomingEntry, _bassCutoff(1.0 - handover));
  }

  void _rideBassSwap(double p, BlendFrame f) {
    final handover = _coerce((p - render.swapFrom) / render.swapWidth, 0.0, 1.0);
    final clash = _coerce(render.vocalOverlap, 0.0, 1.0);
    final entry = math.max(
      _bassCutoff(1.0 - handover),
      _entryHighPass(
        p,
        1.0,
        _glide(_blendEntryHighPassHz, _blendEntryClashHighPassHz, clash),
        render.blendEntryOpenBy,
      ),
    );
    f.inLow = openHz;
    f.inHigh = entry;
    f.outLow = _blendExitLowPass(p, clash);
    f.outHigh = _bassCutoff(handover);
  }

  double _blendExitLowPass(double p, double clash) {
    final from = render.blendExitFrom;
    final amount = _coerce((p - from) / (1.0 - from), 0.0, 1.0);
    final floor = _glide(_blendExitLowPassHz, _blendExitClashLowPassHz, clash);
    return _glide(openHz, floor, amount);
  }
}

/// The blend's envelopes, sampled every [step] seconds of clip time.
class BlendEnvelopes {
  BlendEnvelopes(this.step, int count)
      : inGain = Float32List(count),
        outGain = Float32List(count),
        inLow = Float32List(count),
        inHigh = Float32List(count),
        outLow = Float32List(count),
        outHigh = Float32List(count),
        echoSend = Float32List(count),
        echoDry = Float32List(count),
        headroom = Float32List(count);

  final double step;
  final Float32List inGain, outGain, inLow, inHigh, outLow, outHigh, echoSend, echoDry, headroom;
  bool echo = false;
}
