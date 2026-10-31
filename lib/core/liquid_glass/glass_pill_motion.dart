import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// The selection pill's physics: a line-for-line port of BitChord's
/// `GlassPillMotion` (itself after liquid_glass_easy's lens motion).
///
/// A tap lifts the pill at once — it inflates past the bar on two
/// under-damped springs, one per axis, so it overshoots its raised size and
/// rebounds — and it stays up for the whole journey. The travel is its own
/// spring. Only once the pill has landed ([_handoverStart] of the way
/// there) is the lift released, so it deflates where it stands, dipping a
/// little under its resting size and coming back. A drag is the same lift
/// held open by a finger.
///
/// Along the way the pill's drawn position is sampled every frame and
/// differentiated twice: it stretches wide and flat as it launches,
/// squashes narrow and tall as it brakes, and is undeformed at constant
/// speed.
///
/// The glass is a third, much faster spring, so the pill reads as glass
/// almost as soon as it is touched, and sheds it ([glassPresence]) from the
/// landing while the size is still settling. Once nothing is left to see,
/// [isFlat] flips and the plain pill takes over.
///
/// One [Ticker] drives everything and it only runs while something is
/// moving, exactly like the Kotlin frame loop.
///
/// Positions are in tab steps: `0` is the first tab, `1` the second.
class GlassPillMotion extends ChangeNotifier {
  GlassPillMotion({required TickerProvider vsync, int initialIndex = 0})
      : _index = initialIndex,
        _position = initialIndex.toDouble(),
        _travelPos = initialIndex.toDouble(),
        _travelTarget = initialIndex.toDouble(),
        _travelFrom = initialIndex.toDouble() {
    _ticker = vsync.createTicker(_onTick);
  }

  late final Ticker _ticker;

  double _position;
  double _liftX = 0;
  double _liftY = 0;
  double _material = 0;
  double _deviation = 0;
  double _glassPresence = 0;
  bool _isFlat = true;
  int _index;

  /// Where the pill is drawn, in tab steps.
  double get position => _position;

  /// The width lift, `0` at rest and `1` at the raised size; overshoots both.
  double get liftX => _liftX;

  /// The height lift; see [liftX].
  double get liftY => _liftY;

  /// How much of the material is on, `0`..`1`.
  double get material => _material;

  /// Acceleration squash: width scales by `1 + this`, height by `1 - this`.
  double get deviation => _deviation;

  /// How much of the pill still reads as glass, `1` lifted to `0` flat.
  double get glassPresence => _glassPresence;

  /// True when only a flat fill at rest size is left.
  bool get isFlat => _isFlat;

  /// The tab the pill is headed for.
  int get index => _index;

  /// One tab step in logical pixels; the squash model samples travel in it.
  double stepDp = 0;

  /// "Reduce animation": every move lands at once, with no lift.
  bool reduceMotion = false;

  double _travelPos;
  double _travelVel = 0;
  double _travelTarget;
  double _travelFrom;
  bool _travelActive = false;

  bool _lifted = false;
  double _liftXPos = 0, _liftXVel = 0;
  double _liftYPos = 0, _liftYVel = 0;
  double _liftPos = 0, _liftVel = 0;

  bool _dragging = false;
  double _dragTarget = 0;
  double _dragFollow = 0;

  double _travelSign = 0;
  double _travelSignEased = 0;
  double _handover = 1;
  double _squash = 0;
  final _PillSquashModel _squashModel = _PillSquashModel();

  Duration? _lastElapsed;

  /// A tab was chosen: travel there, lifted.
  void animateTo(int next) {
    if (next == _index) return;
    if (reduceMotion) {
      snapTo(next);
      return;
    }
    _index = next;
    _travelActive = true;
    _lifted = true;
    // Retarget from wherever the pill is; the spring keeps its velocity.
    _travelFrom = _travelPos;
    _travelTarget = next.toDouble();
    _travelSign = _signOfTravel(_travelTarget - _travelFrom);
    _isFlat = false;
    _start();
  }

  /// Place the pill on [target] at rest, with no travel and no lift.
  void snapTo(int target) {
    _index = target;
    _travelPos = target.toDouble();
    _travelTarget = _travelPos;
    _travelFrom = _travelPos;
    _travelVel = 0;
    _travelActive = false;
    _dragging = false;
    _lifted = false;
    _liftXPos = 0;
    _liftXVel = 0;
    _liftYPos = 0;
    _liftYVel = 0;
    _liftPos = 0;
    _liftVel = 0;
    _handover = 1;
    _squash = 0;
    _squashModel.stop();
    _travelSign = 0;
    _travelSignEased = 0;
    _publish();
    _isFlat = true;
    _ticker.stop();
    _lastElapsed = null;
    notifyListeners();
  }

  /// A finger has picked the pill up where it stands.
  void startDrag() {
    _dragging = true;
    _travelActive = false;
    _lifted = !reduceMotion;
    _travelSign = 0;
    _dragFollow = _travelPos;
    _dragTarget = _travelPos;
    _travelVel = 0;
    _isFlat = false;
    _start();
  }

  /// The finger is over [position] tab steps.
  void dragTo(double position) {
    if (_dragging) _dragTarget = position;
  }

  /// The finger let go and the pill is to settle on [next].
  void release(int next) {
    if (!_dragging) return;
    final from = _dragFollow;
    _dragging = false;
    _index = next;
    if (reduceMotion) {
      snapTo(next);
      return;
    }
    _travelActive = true;
    _travelPos = from;
    _travelVel = 0;
    _travelFrom = from;
    _travelTarget = next.toDouble();
    _travelSign = _signOfTravel(_travelTarget - _travelFrom);
    _start();
  }

  void _start() {
    if (_ticker.isActive) return;
    _lastElapsed = null;
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final last = _lastElapsed;
    final dt = last == null ? 0.0 : (elapsed - last).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    final now = elapsed.inMicroseconds / 1e6;
    if (!_tick(dt, now)) {
      _ticker.stop();
      _lastElapsed = null;
    }
    notifyListeners();
  }

  /// One frame of everything. False once all of it has settled.
  bool _tick(double dt, double now) {
    // 1) Travel.
    var travelSettled = true;
    if (_travelActive) {
      final r = _springStep(_travelPos, _travelVel, _travelTarget, dt,
          _travelStiffness, _travelDamping);
      _travelPos = r.$1;
      _travelVel = r.$2;
      travelSettled =
          (_travelPos - _travelTarget).abs() < 0.003 && _travelVel.abs() < 0.05;
      if (travelSettled) {
        _travelPos = _travelTarget;
        _travelVel = 0;
      }
    }

    // 2) Under a finger, chase it smoothly.
    if (_dragging) {
      _dragFollow += reduceMotion
          ? _dragTarget - _dragFollow
          : (_dragTarget - _dragFollow) * (1 - math.exp(-dt / _followTau));
    }

    // 3) The lift, held for the journey and released on landing.
    if (!_dragging && (travelSettled || _travelProgress() >= _handoverStart)) {
      _lifted = false;
    }
    final liftTarget = _lifted ? 1.0 : 0.0;
    var r = _stepLift(
        _liftXPos, _liftXVel, liftTarget, dt, _liftStiffness, _liftDampingX);
    _liftXPos = r.$1;
    _liftXVel = r.$2;
    r = _stepLift(
        _liftYPos, _liftYVel, liftTarget, dt, _liftStiffness, _liftDampingY);
    _liftYPos = r.$1;
    _liftYVel = r.$2;
    r = _stepLift(
        _liftPos, _liftVel, liftTarget, dt, _materialStiffness, _materialDamping);
    _liftPos = r.$1;
    _liftVel = r.$2;
    final liftSettled =
        !_lifted && _liftXPos == 0 && _liftYPos == 0 && _liftPos == 0;

    // 4) The deflation outlives the spring that carried the pill there.
    if (_travelActive && travelSettled && liftSettled && !_dragging) {
      _travelActive = false;
    }

    // 5) Sample the pill where it is drawn this frame.
    final frac = _dragging ? _dragFollow : _travelPos;
    if (stepDp > 0) {
      if (!_squashModel.isTracking) _squashModel.start();
      _squash = _squashModel.track(frac * stepDp, now, dt);
      if (_travelSignEased == 0) {
        _travelSignEased = _travelSign;
      } else if (_travelSignEased != _travelSign) {
        _travelSignEased +=
            (_travelSign - _travelSignEased) * (1 - math.exp(-dt / _signTau));
        if ((_travelSign - _travelSignEased).abs() < 0.01) {
          _travelSignEased = _travelSign;
        }
      }
      // Keep the force's magnitude and take its sign from the direction of
      // travel, so a trip deforms one way the whole way.
      final key = _travelSignEased;
      if (key != 0) _squash = _squash * (1 - key.abs()) - key * _squash.abs();
    }

    // 6) The hand-off rides the same landing as the deflation.
    final handoverTarget = _lifted ? 0.0 : 1.0;
    final tau = handoverTarget > _handover ? _handoverTau : _glassReturnTau;
    _handover += (handoverTarget - _handover) * (1 - math.exp(-dt / tau));
    if ((handoverTarget - _handover).abs() < 0.002) _handover = handoverTarget;

    final settled = !_travelActive &&
        !_dragging &&
        liftSettled &&
        _squash.abs() < 0.0005 &&
        _handover >= 1.0;
    if (settled) {
      _squashModel.stop();
      _squash = 0;
      _travelSign = 0;
      _travelSignEased = 0;
    }
    _publish();
    _isFlat = settled;
    return !settled;
  }

  void _publish() {
    _position = _dragging ? _dragFollow : _travelPos;
    _liftX = _liftXPos;
    _liftY = _liftYPos;
    _material = _liftPos.clamp(0.0, 1.0);
    _deviation = _squash;
    _glassPresence = (1 - _handover).clamp(0.0, 1.0);
  }

  double _travelProgress() {
    final span = (_travelTarget - _travelFrom).abs();
    if (span < 1e-6) return 1;
    return (1 - (_travelTarget - _travelPos).abs() / span).clamp(0.0, 1.0);
  }

  static double _signOfTravel(double span) =>
      span.abs() < 1e-6 ? 0 : span.sign;

  /// The size the pill is drawn at this frame, between [rest] and [lifted].
  Size liveSize(Size rest, Size lifted) {
    final w = rest.width + (lifted.width - rest.width) * _liftX;
    final h = rest.height + (lifted.height - rest.height) * _liftY;
    return Size(w * (1 + _deviation), h * (1 - _deviation));
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  static const double _travelStiffness = 280;
  static const double _travelDamping = 31.4;

  /// Damping ratio 0.6 across, 0.7 down, so width overshoots a shade further.
  static const double _liftStiffness = 250;
  static const double _liftDampingX = 19;
  static const double _liftDampingY = 22.1;

  /// Critically damped and four times as stiff: the glass is on long before
  /// the size settles.
  static const double _materialStiffness = 1000;
  static const double _materialDamping = 63.3;

  static const double _handoverStart = 0.92;
  static const double _handoverTau = 0.09;
  static const double _glassReturnTau = 0.05;
  static const double _followTau = 0.05;
  static const double _signTau = 0.25;

  /// Semi-implicit Euler in 1/240 s substeps, so a long frame cannot blow
  /// it up.
  static (double, double) _springStep(
    double x,
    double vel,
    double target,
    double dt,
    double stiffness,
    double damping,
  ) {
    var t = dt;
    var px = x;
    var pv = vel;
    while (t > 0) {
      final step = t > 1 / 240 ? 1 / 240 : t;
      final accel = -stiffness * (px - target) - damping * pv;
      pv += accel * step;
      px += pv * step;
      t -= step;
    }
    return (px, pv);
  }

  /// A spring step snapped to its target once it has nothing left to say.
  static (double, double) _stepLift(
    double x,
    double vel,
    double target,
    double dt,
    double stiffness,
    double damping,
  ) {
    final r = _springStep(x, vel, target, dt, stiffness, damping);
    return (r.$1 - target).abs() < 0.0008 && r.$2.abs() < 0.01
        ? (target, 0)
        : r;
  }
}

/// Acceleration to deformation: the pill's position over a short window,
/// differentiated twice and averaged, scaled and clamped, then eased so a
/// single noisy frame cannot flick it. Tuned in dp/s².
class _PillSquashModel {
  final List<(double, double)> _history = [];
  bool isTracking = false;
  double _value = 0;

  void start() {
    _history.clear();
    _value = 0;
    isTracking = true;
  }

  void stop() {
    isTracking = false;
    _history.clear();
    _value = 0;
  }

  double track(double x, double now, double dt) {
    if (!isTracking) return _value;
    _history.add((x, now));
    final cutoff = now - _sampleWindow;
    _history.removeWhere((e) => e.$2 < cutoff);
    final raw = (_averageAcceleration() * _sensitivity)
        .clamp(-_maxDeformation, _maxDeformation);
    final ease = (dt / _responseTime).clamp(0.0, 1.0);
    _value += (raw - _value) * ease;
    return _value;
  }

  double _averageAcceleration() {
    if (_history.length < 3) return 0;
    final velocities = <(double, double)>[];
    for (var i = 1; i < _history.length; i++) {
      final dt = _history[i].$2 - _history[i - 1].$2;
      if (dt <= 0) continue;
      velocities.add((
        (_history[i].$1 - _history[i - 1].$1) / dt,
        (_history[i].$2 + _history[i - 1].$2) / 2,
      ));
    }
    if (velocities.length < 2) return 0;
    var total = 0.0;
    var count = 0;
    for (var i = 1; i < velocities.length; i++) {
      final dt = velocities[i].$2 - velocities[i - 1].$2;
      if (dt <= 0) continue;
      total += (velocities[i].$1 - velocities[i - 1].$1) / dt;
      count++;
    }
    return count == 0 ? 0 : total / count;
  }

  static const double _sampleWindow = 0.3;
  static const double _sensitivity = 0.00007;

  /// ±12 %: the pill travels inside the bar, and more would climb out of it.
  static const double _maxDeformation = 0.12;
  static const double _responseTime = 0.18;
}
