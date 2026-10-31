import 'package:flutter/material.dart';

import '../liquid_glass/liquid_glass_kit.dart';

/// A liquid glass surface for Inzx's controls (play/pause, top buttons, mini
/// player capsule): BitChord's glass — a refracting, chromatic lens with a
/// directional rim highlight, rendered by fragment shaders over the live
/// backdrop (see `lib/core/liquid_glass`).
///
/// It keeps the old container's constructor so existing call sites carry
/// over; the old painter's tuning knobs ([blurSigma], [refractionScale],
/// [refractionDeflection], [accentColor], [additionalShadows]) are accepted
/// and ignored — the BitChord style defines the look.
///
/// Pressing it squashes the surface on BitChord's glass spring (damping
/// 0.72, stiffness 320) and lets it spring back, which is the liquid feel the
/// tab bar's items have.
class LiquidGlassContainer extends StatefulWidget {
  final Widget child;
  final double borderRadius;
  final double blurSigma;
  final double refractionScale;
  final double refractionDeflection;

  /// Glass tint. Defaults to BitChord's 40% theme tint.
  final Color? surfaceColor;
  final Color? accentColor;
  final bool isDark;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final List<BoxShadow>? additionalShadows;
  final Offset? globalOffset;

  /// Squash on press (off for large passive surfaces).
  final bool pressable;

  const LiquidGlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 32.0,
    this.blurSigma = 2.0,
    this.refractionScale = 1.05,
    this.refractionDeflection = 2.8,
    this.surfaceColor,
    this.accentColor,
    this.isDark = true,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.additionalShadows,
    this.globalOffset,
    this.pressable = true,
  });

  @override
  State<LiquidGlassContainer> createState() => _LiquidGlassContainerState();
}

class _LiquidGlassContainerState extends State<LiquidGlassContainer>
    with SingleTickerProviderStateMixin {
  /// 0 at rest, 1 fully pressed (may overshoot on the spring).
  late final AnimationController _press = AnimationController.unbounded(
    vsync: this,
  );

  static const double _pressedScale = 0.94;

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _springTo(double target) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _press.value = target;
      return;
    }
    _press.animateWith(
      composeSpring(
        _press.value,
        target,
        _press.velocity,
        dampingRatio: kGlassSpringDamping,
        stiffness: kGlassSpringStiffness,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final glass = LiquidGlass(
      style: GlassStyle.bitChord(
        dark: widget.isDark,
        surfaceTint: widget.surfaceColor,
      ),
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Padding(
        padding: widget.padding ?? EdgeInsets.zero,
        child: widget.child,
      ),
    );

    Widget surface = SizedBox(
      width: widget.width,
      height: widget.height,
      child: glass,
    );

    if (widget.pressable) {
      surface = Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _springTo(1),
        onPointerUp: (_) => _springTo(0),
        onPointerCancel: (_) => _springTo(0),
        child: AnimatedBuilder(
          animation: _press,
          builder: (context, child) {
            final p = _press.value;
            // A squash, not a plain shrink: a touch wider than tall, the way
            // a drop of liquid flattens under a finger.
            final scale = 1 - (1 - _pressedScale) * p;
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(
                scale + 0.02 * p,
                scale - 0.02 * p,
                1,
              ),
              child: child,
            );
          },
          child: surface,
        ),
      );
    }

    if (widget.margin != null) {
      surface = Padding(padding: widget.margin!, child: surface);
    }
    return surface;
  }
}
