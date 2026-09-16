import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'liquid_glass.dart';

enum BouncyStyle {
  /// Small controls & action pills (Play/Pause, Heart, Action buttons)
  button,

  /// Large cards, miniplayer capsule & list tiles (Grounding with zero overshoot)
  card,

  /// Heart like button with spring burst pop
  heartPop,
}

/// A premium tactile touch animation wrapper.
///
/// Features:
/// - Guaranteed visibility: Fast normal taps complete full press-down phase before reversing.
/// - Tuned curves: ZERO overshoot for cards/containers, crisp spring for small controls.
/// - Layered opacity/highlight: Subtle opacity shift on press down.
/// - Scroll arena safe: Instant reset on tap cancel without locking pressed state.
/// - Distinct haptics per interaction style.
class BouncyTouch extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BouncyStyle style;
  final double? customScale;
  final bool enableHaptics;
  final HitTestBehavior hitTestBehavior;

  const BouncyTouch({
    super.key,
    required this.child,
    this.onTap,
    this.style = BouncyStyle.button,
    this.customScale,
    this.enableHaptics = true,
    this.hitTestBehavior = HitTestBehavior.opaque,
  });

  @override
  State<BouncyTouch> createState() => _BouncyTouchState();
}

class _BouncyTouchState extends State<BouncyTouch>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 85),
      reverseDuration: Duration(
        milliseconds: widget.style == BouncyStyle.card
            ? 260
            : (widget.style == BouncyStyle.heartPop ? 500 : 380),
      ),
    );

    _setupAnimations();
  }

  void _setupAnimations() {
    double targetScale;
    double targetOpacity;
    Curve curveOut;

    switch (widget.style) {
      case BouncyStyle.card:
        targetScale = widget.customScale ?? 0.98;
        targetOpacity = 0.92;
        curveOut = Curves.easeOutCubic; // Zero overshoot for grounded cards
        break;
      case BouncyStyle.heartPop:
        targetScale = widget.customScale ?? 0.85;
        targetOpacity = 1.0;
        curveOut = Curves.elasticOut;
        break;
      case BouncyStyle.button:
        targetScale = widget.customScale ?? 0.92;
        targetOpacity = 0.88;
        curveOut = Curves.easeOutBack; // Crisp responsive spring
        break;
    }

    _scaleAnimation = Tween<double>(begin: 1.0, end: targetScale).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutQuad,
        reverseCurve: curveOut,
      ),
    );

    _opacityAnimation = Tween<double>(begin: 1.0, end: targetOpacity).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutQuad,
        reverseCurve: Curves.easeOut,
      ),
    );
  }

  @override
  void didUpdateWidget(BouncyTouch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.style != widget.style ||
        oldWidget.customScale != widget.customScale) {
      _setupAnimations();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _triggerHaptic() {
    if (!widget.enableHaptics) return;
    switch (widget.style) {
      case BouncyStyle.card:
        HapticFeedback.selectionClick();
        break;
      case BouncyStyle.heartPop:
        HapticFeedback.mediumImpact();
        break;
      case BouncyStyle.button:
        HapticFeedback.lightImpact();
        break;
    }
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.onTap == null) return;
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) async {
    if (widget.onTap == null) return;
    _triggerHaptic();
    widget.onTap?.call();

    // Ensure the press down completes so it is clearly visible even on 10ms ultra-fast taps!
    if (_controller.value < 0.75) {
      await _controller.forward().orCancel.catchError((_) {});
    }

    if (mounted) {
      _controller.reverse();
    }
  }

  void _onTapCancel() {
    if (widget.onTap == null) return;
    // Rapid reset to prevent stuck state when fling/scroll starts
    _controller.animateBack(0.0, duration: const Duration(milliseconds: 100));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) {
      return widget.child;
    }

    return GestureDetector(
      behavior: widget.hitTestBehavior,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Opacity(
              opacity: _opacityAnimation.value,
              child: widget.child,
            ),
          );
        },
      ),
    );
  }
}

/// An ultra-fluid, animated Play/Pause toggle button with icon morphing and spring scale.
/// Supports both standard opaque theme and optical Liquid Glass lens styling.
class AnimatedPlayPauseButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onTap;
  final double size;
  final double iconSize;
  final Color backgroundColor;
  final Color iconColor;
  final bool isLiquidGlass;

  const AnimatedPlayPauseButton({
    super.key,
    required this.isPlaying,
    required this.onTap,
    this.size = 72.0,
    this.iconSize = 40.0,
    required this.backgroundColor,
    this.iconColor = Colors.white,
    this.isLiquidGlass = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bool isLightColor = backgroundColor.computeLuminance() > 0.60;
    
    // Always contrast white icons on light backgrounds, regardless of liquid glass
    final effectiveIconColor = (iconColor == Colors.white && isLightColor)
        ? Colors.black87
        : iconColor;

    final iconSwitcher = AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      reverseDuration: const Duration(milliseconds: 300),
      switchInCurve: Curves.elasticOut,
      switchOutCurve: Curves.easeInBack,
      transitionBuilder: (child, animation) {
        return ScaleTransition(
          scale: animation,
          child: RotationTransition(
            turns: Tween<double>(
              begin: child.key == const ValueKey('play') ? -0.15 : 0.15,
              end: 0.0,
            ).animate(animation),
            child: FadeTransition(
              opacity: animation,
              child: child,
            ),
          ),
        );
      },
      child: Icon(
        isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
        key: ValueKey(isPlaying ? 'pause' : 'play'),
        color: effectiveIconColor,
        size: iconSize,
      ),
    );

    if (isLiquidGlass) {
      return LiquidGlassContainer(
        width: size,
        height: size,
        borderRadius: size / 2,
        blurSigma: 2.0,
        refractionScale: 1.08,
        refractionDeflection: 2.8,
        isDark: isDark,
        surfaceColor: backgroundColor.withValues(
          alpha: isDark ? 0.82 : 0.88,
        ),
        accentColor: Color.lerp(backgroundColor, Colors.white, 0.45) ?? backgroundColor,
        additionalShadows: [
          BoxShadow(
            color: backgroundColor.withValues(alpha: isPlaying ? 0.55 : 0.28),
            blurRadius: isPlaying ? 24 : 12,
            spreadRadius: isPlaying ? 3 : 0,
            offset: const Offset(0, 4),
          ),
        ],
        child: SizedBox.expand(
          child: BouncyTouch(
            style: BouncyStyle.button,
            customScale: 0.88,
            onTap: onTap,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.30),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.15),
                  ],
                ),
              ),
              child: Center(
                child: iconSwitcher,
              ),
            ),
          ),
        ),
      );
    }

    return BouncyTouch(
      style: BouncyStyle.button,
      customScale: 0.88,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: backgroundColor.withValues(alpha: isPlaying ? 0.45 : 0.2),
              blurRadius: isPlaying ? 24 : 10,
              spreadRadius: isPlaying ? 4 : 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: iconSwitcher,
        ),
      ),
    );
  }
}
