import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

/// Leans [child] towards the mouse in 3D while it's over it, with a soft
/// glare where the pointer is, and eases back flat when it leaves. Desktop
/// only in practice: it follows hover, which touch screens don't have.
class TiltOnHover extends StatefulWidget {
  const TiltOnHover({
    super.key,
    required this.child,
    this.maxTilt = 14,
    this.lift = 1.03,
    this.borderRadius = BorderRadius.zero,
    this.enabled = true,
  });

  final Widget child;

  /// Furthest the child turns about either axis, in degrees.
  final double maxTilt;

  /// How much larger the child grows while hovered.
  final double lift;

  /// The child's corners, so the glare stays inside them.
  final BorderRadius borderRadius;

  /// Off, the child stays flat (the same widgets stay in the tree, so an
  /// animated child isn't rebuilt when this flips).
  final bool enabled;

  @override
  State<TiltOnHover> createState() => _TiltOnHoverState();
}

class _TiltOnHoverState extends State<TiltOnHover>
    with SingleTickerProviderStateMixin {
  // Where the pointer is, -1..1 across each axis, and how hovered (0..1):
  // the targets and the values drawn, which chase them.
  Offset _target = Offset.zero;
  double _targetHover = 0;
  Offset _tilt = Offset.zero;
  double _hover = 0;

  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TiltOnHover old) {
    super.didUpdateWidget(old);
    if (old.enabled && !widget.enabled) _leave();
  }

  void _aim(Offset local, Size size, double hover) {
    if (size.isEmpty || !widget.enabled) return;
    _target = Offset(
      (local.dx / size.width * 2 - 1).clamp(-1.0, 1.0),
      (local.dy / size.height * 2 - 1).clamp(-1.0, 1.0),
    );
    _targetHover = hover;
    _start();
  }

  void _leave() {
    _target = Offset.zero;
    _targetHover = 0;
    _start();
  }

  void _start() {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      setState(() {
        _tilt = _target;
        _hover = _targetHover;
      });
      return;
    }
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = _last == Duration.zero
        ? 1 / 60
        : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    // Exponential approach: quick to follow, no overshoot, frame-rate free.
    final k = 1 - math.exp(-dt * 10);
    setState(() {
      _tilt += (_target - _tilt) * k;
      _hover += (_targetHover - _hover) * k;
    });
    if ((_target - _tilt).distance < 0.001 &&
        (_targetHover - _hover).abs() < 0.001) {
      _tilt = _target;
      _hover = _targetHover;
      _ticker.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final radians = widget.maxTilt * math.pi / 180;
        final scale = 1 + (widget.lift - 1) * _hover;
        final transform = Matrix4.identity()
          // Perspective scaled to the child, so a large cover leans like a
          // small one instead of looking more stretched.
          ..setEntry(3, 2, 0.6 / math.max(size.shortestSide, 100))
          ..rotateX(-_tilt.dy * radians)
          ..rotateY(_tilt.dx * radians)
          ..scaleByDouble(scale, scale, 1, 1);
        return MouseRegion(
          onEnter: (e) => _aim(e.localPosition, size, 1),
          onHover: (e) => _aim(e.localPosition, size, 1),
          onExit: (_) => _leave(),
          child: Transform(
            alignment: Alignment.center,
            transform: transform,
            child: Stack(
              fit: StackFit.expand,
              children: [
                widget.child,
                if (_hover > 0.01)
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: widget.borderRadius,
                        gradient: RadialGradient(
                          center: Alignment(_tilt.dx, _tilt.dy),
                          radius: 0.9,
                          colors: [
                            Colors.white.withValues(alpha: 0.22 * _hover),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
