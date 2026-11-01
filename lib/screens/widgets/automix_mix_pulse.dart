import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../services/automix/automix_service.dart';

/// One beat clock for everything that pulses with an Automix blend — the
/// seek bar's fill and the "Mixing" label — so the two can never drift out
/// of step. A port of BitChord's `MixPulse` (ThinSlider.kt): the same cover
/// and pulse timings, beat shape, rest opacity and phase locking.
///
/// The engine's state (mixing, the planned window, the blend's beat) is
/// polled ten times a second; the pulse itself is computed every frame from
/// the last beat anchor, so it stays smooth between polls.
class AutomixMixPulse extends ChangeNotifier {
  AutomixMixPulse(TickerProvider vsync) {
    _ticker = vsync.createTicker(_onTick);
    _poll = Timer.periodic(const Duration(milliseconds: 100), (_) => _refresh());
    _refresh();
  }

  late final Ticker _ticker;
  Timer? _poll;

  // ---- Engine state ----------------------------------------------------
  bool _mixing = false;
  bool _blendActive = false;
  bool _blendPlaying = false;
  double? _beatMs;

  /// When a beat landed, in [_clock] microseconds.
  int? _beatAnchorUs;
  double? windowStart;
  double? windowEnd;

  // ---- Animated values (read in paint) ---------------------------------
  /// 0..1: how far the blend has claimed the bar and the label.
  double cover = 0;
  double _depth = 0;
  double _level = 0;
  double _phase = 0;
  bool _locked = false;

  /// 0..1: the planned window's fade.
  double windowAlpha = 0;

  final Stopwatch _clock = Stopwatch()..start();
  Duration _lastTick = Duration.zero;

  bool get mixing => _mixing;

  /// The fill's opacity: full, pulsed down to [restShare] between beats.
  double alpha(double fullAlpha, {double restShare = _pulseRest}) {
    final rest = fullAlpha * restShare;
    final pulsed = rest + (fullAlpha - rest) * _level;
    return fullAlpha + (pulsed - fullAlpha) * _depth;
  }

  Future<void> _refresh() async {
    final state = await AutomixService.instance.mixState();
    final nowUs = _clock.elapsedMicroseconds;
    final mixing = state?['mixing'] == true;
    final beatMs = (state?['beatMs'] as num?)?.toDouble();
    final sinceBeatMs = (state?['sinceBeatMs'] as num?)?.toDouble();
    final blendPlaying = state?['blendPlaying'];
    final ws = (state?['windowStart'] as num?)?.toDouble();
    final we = (state?['windowEnd'] as num?)?.toDouble();

    _mixing = mixing;
    _blendActive = blendPlaying != null;
    _blendPlaying = blendPlaying == true;
    _beatMs = (beatMs != null && beatMs > 0) ? beatMs : null;
    _beatAnchorUs = (sinceBeatMs != null) ? nowUs - (sinceBeatMs * 1000).round() : null;
    if (ws != null && we != null) {
      windowStart = ws;
      windowEnd = we;
    }
    _windowWanted = ws != null && we != null;
    if (_needsFrames && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
    notifyListeners();
  }

  bool _windowWanted = false;

  bool get _needsFrames =>
      _mixing ||
      cover > 0 ||
      _depth > 0 ||
      windowAlpha != (_windowWanted ? 1.0 : 0.0);

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 16000
        : (elapsed - _lastTick).inMicroseconds.clamp(0, _maxFrameUs);
    _lastTick = elapsed;
    final seconds = dt / 1e6;

    // Cover glides out to the full bar and back (BitChord: 700 ms, eased).
    cover = _approach(cover, _blendActive || _mixing ? 1 : 0, seconds / _coverS);
    // The beat pulse swells in as a blend plays and settles as it stops.
    _depth = _approach(
      _depth,
      (_blendActive || _mixing) && _blendPlaying ? 1 : 0,
      seconds / _pulseFadeS,
    );
    windowAlpha = _approach(windowAlpha, _windowWanted ? 1 : 0, seconds / _windowFadeS);

    final beatMs = _beatMs;
    final anchor = _beatAnchorUs;
    var phase = _phase;
    if (beatMs != null && anchor != null) {
      final beatUs = beatMs * 1000;
      phase += dt / beatUs;
      final nowUs = _clock.elapsedMicroseconds;
      final target = ((nowUs - anchor) % beatUs) / beatUs;
      final error = ((target - phase) % 1.0 + 1.5) % 1.0 - 0.5;
      phase += _locked ? error * _phasePull : error;
      _locked = true;
    } else {
      phase += dt / _breathUs;
      if (_blendActive) _locked = false;
    }
    phase -= phase.floorToDouble();
    _phase = phase;
    _level = _beatShape(phase);

    notifyListeners();
    if (!_needsFrames && _depth == 0) {
      _ticker.stop();
      _locked = false;
    }
  }

  /// Linear approach to [target] at [step] per call, eased on read by the
  /// smoothstep in [eased] where a curve matters.
  static double _approach(double value, double target, double step) {
    if (value < target) return math.min(target, value + step);
    if (value > target) return math.max(target, value - step);
    return value;
  }

  /// FastOutSlowIn-like easing of a linear 0..1, for the cover.
  static double eased(double t) => Curves.fastOutSlowIn.transform(t.clamp(0, 1));

  /// BitChord's beat shape: a raised cosine, squared — a sharp lift on the
  /// beat that falls away through it.
  static double _beatShape(double phase) {
    final c = 0.5 + 0.5 * math.cos(2 * math.pi * phase);
    return c * c;
  }

  @override
  void dispose() {
    _poll?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  static const double _coverS = 0.7;
  static const double _pulseFadeS = 0.9;
  static const double _windowFadeS = 0.5;
  static const double _pulseRest = 0.1;
  static const double _phasePull = 0.06;
  static const double _breathUs = 1800000;
  static const int _maxFrameUs = 100000;
}

/// The seek bar's track with the planned Automix window drawn over it: a
/// band whose ends dissolve on a smoothstep (BitChord's feathered window).
class AutomixWindowTrackShape extends RoundedRectSliderTrackShape {
  const AutomixWindowTrackShape({
    required this.windowStart,
    required this.windowEnd,
    required this.windowAlpha,
    required this.markerColor,
  });

  final double? windowStart;
  final double? windowEnd;
  final double windowAlpha;
  final Color markerColor;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    // Inactive track first, then the window band, then the played part on top.
    final canvas = context.canvas;
    final radius = Radius.circular(rect.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()..color = sliderTheme.inactiveTrackColor ?? Colors.white24,
    );
    final start = windowStart;
    final end = windowEnd;
    if (start != null && end != null && windowAlpha > 0) {
      final from = rect.left + rect.width * start.clamp(0.0, 1.0);
      final to = rect.left + rect.width * end.clamp(0.0, 1.0);
      final span = to - from;
      if (span > 0) {
        // BitChord: feather = 40% of the window, kept between 6 and 40 dp
        // and never more than half the span; six smoothstep stops per end.
        final feather = (span * 0.4).clamp(6.0, 40.0).clamp(0.0, span / 2);
        final f = feather / span;
        final full = markerColor.a * windowAlpha;
        final colors = <Color>[];
        final stops = <double>[];
        for (var s = 0; s <= 6; s++) {
          final t = s / 6;
          colors.add(markerColor.withValues(alpha: full * t * t * (3 - 2 * t)));
          stops.add(f * t);
        }
        for (var s = 6; s >= 0; s--) {
          final t = s / 6;
          colors.add(markerColor.withValues(alpha: full * t * t * (3 - 2 * t)));
          stops.add(1 - f * t);
        }
        canvas.save();
        canvas.clipRRect(RRect.fromRectAndRadius(rect, radius));
        canvas.drawRect(
          Rect.fromLTRB(from, rect.top, to, rect.bottom),
          Paint()
            ..shader = LinearGradient(colors: colors, stops: stops)
                .createShader(Rect.fromLTRB(from, rect.top, to, rect.bottom)),
        );
        canvas.restore();
      }
    }
    final played = Rect.fromLTRB(
      rect.left,
      rect.top,
      thumbCenter.dx.clamp(rect.left, rect.right),
      rect.bottom,
    );
    if (played.width > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(played, radius),
        Paint()..color = sliderTheme.activeTrackColor ?? Colors.white,
      );
    }
  }
}

/// "Mixing", in the quality badge's place while a blend runs, breathing on
/// the same beat as the bar (BitChord's MixingLabel: plain text, no icon,
/// resting at half opacity between beats).
class AutomixMixingLabel extends StatelessWidget {
  const AutomixMixingLabel({super.key, required this.pulse, required this.color});

  final AutomixMixPulse pulse;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: (AutomixMixPulse.eased(pulse.cover) * pulse.alpha(1, restShare: 0.5))
          .clamp(0.0, 1.0),
      child: Text(
        'Mixing',
        maxLines: 1,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          color: color.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}

/// The quality badge's spot for layouts without a linear seek bar (Ripple's
/// circular scrubber): the given [badge], giving way to a pulsing "Mixing"
/// while an Automix blend runs. Owns its own beat clock.
class LosslessOrMixingBadge extends StatefulWidget {
  const LosslessOrMixingBadge({
    super.key,
    required this.badge,
    required this.color,
  });

  final Widget badge;
  final Color color;

  @override
  State<LosslessOrMixingBadge> createState() => _LosslessOrMixingBadgeState();
}

class _LosslessOrMixingBadgeState extends State<LosslessOrMixingBadge>
    with SingleTickerProviderStateMixin {
  late final AutomixMixPulse _pulse = AutomixMixPulse(this);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final cover = AutomixMixPulse.eased(_pulse.cover);
        return Stack(
          alignment: Alignment.center,
          children: [
            Opacity(opacity: 1 - cover, child: widget.badge),
            if (cover > 0) AutomixMixingLabel(pulse: _pulse, color: widget.color),
          ],
        );
      },
    );
  }
}
