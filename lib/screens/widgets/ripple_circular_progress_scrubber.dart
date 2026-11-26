import 'dart:math';
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'ripple_flower_clipper.dart';

/// Interactive waveform progress scrubber that encloses the Ripple wavy artwork.
/// The track follows an 8-petal harmonic wavy contour concentric with the album art,
/// with smooth 60/120fps ticker interpolation and cached path metrics for zero jank.
class RippleCircularProgressScrubber extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<Duration>? onSeeking;
  final ValueChanged<bool>? onSeekingChanged;
  final Color activeColor;
  final Color inactiveColor;
  final double strokeWidth;
  final double thumbRadius;
  final double waveAmplitudeRatio;
  final int lobes;
  final double paddingAroundChild;
  final Widget child;

  const RippleCircularProgressScrubber({
    super.key,
    required this.position,
    required this.duration,
    this.isPlaying = false,
    required this.onSeek,
    this.onSeeking,
    this.onSeekingChanged,
    required this.activeColor,
    required this.inactiveColor,
    this.strokeWidth = 2.0,
    this.thumbRadius = 5.5,
    this.waveAmplitudeRatio = 0.065,
    this.lobes = 8,
    this.paddingAroundChild = 14.0,
    required this.child,
  });

  @override
  State<RippleCircularProgressScrubber> createState() =>
      _RippleCircularProgressScrubberState();
}

class _RippleCircularProgressScrubberState
    extends State<RippleCircularProgressScrubber>
    with TickerProviderStateMixin {
  late final Ticker _ticker;
  late final AnimationController _seekAnimController;
  late final Animation<double> _strokeWidthAnim;
  late final Animation<double> _thumbRadiusAnim;
  late final Animation<double> _haloRadiusAnim;

  Duration _lastKnownPosition = Duration.zero;
  DateTime _lastSyncTime = DateTime.now();

  bool _isDragging = false;
  double _dragProgress = 0.0;

  // Cached path geometry
  Path? _cachedPath;
  PathMetric? _cachedMetric;
  Size? _cachedSize;
  double? _cachedOuterInset;
  double? _cachedWaveRatio;

  @override
  void initState() {
    super.initState();
    _lastKnownPosition = widget.position;
    _lastSyncTime = DateTime.now();
    _ticker = createTicker(_onTick);
    if (widget.isPlaying) {
      _ticker.start();
    }

    _seekAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _strokeWidthAnim = Tween<double>(
      begin: widget.strokeWidth,
      end: widget.strokeWidth * 2.4,
    ).animate(CurvedAnimation(
      parent: _seekAnimController,
      curve: Curves.easeOutCubic,
    ));

    _thumbRadiusAnim = Tween<double>(
      begin: widget.thumbRadius,
      end: widget.thumbRadius * 2.0,
    ).animate(CurvedAnimation(
      parent: _seekAnimController,
      curve: Curves.easeOutCubic,
    ));

    _haloRadiusAnim = Tween<double>(
      begin: 0.0,
      end: 24.0,
    ).animate(CurvedAnimation(
      parent: _seekAnimController,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void didUpdateWidget(RippleCircularProgressScrubber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.position != oldWidget.position) {
      _lastKnownPosition = widget.position;
      _lastSyncTime = DateTime.now();
    }
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying && !_ticker.isActive) {
        _lastSyncTime = DateTime.now();
        _ticker.start();
      } else if (!widget.isPlaying && _ticker.isActive) {
        _ticker.stop();
      }
    }
  }

  @override
  void dispose() {
    _seekAnimController.dispose();
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    if (!_isDragging && widget.isPlaying) {
      setState(() {});
    }
  }

  double get _currentProgress {
    if (_isDragging) return _dragProgress;
    final totalMs = widget.duration.inMilliseconds;
    if (totalMs <= 0) return 0.0;

    if (widget.isPlaying) {
      final timeSinceSync = DateTime.now().difference(_lastSyncTime);
      final clampedOffsetMs = timeSinceSync.inMilliseconds.clamp(0, 1500);
      final currentMs = _lastKnownPosition.inMilliseconds + clampedOffsetMs;
      return (currentMs / totalMs).clamp(0.0, 1.0);
    }
    return (widget.position.inMilliseconds / totalMs).clamp(0.0, 1.0);
  }

  void _handleTouch(Offset localPos, Size size, {bool isEnd = false}) {
    final center = Offset(size.width / 2, size.height / 2);
    final dx = localPos.dx - center.dx;
    final dy = localPos.dy - center.dy;

    if (!_isDragging && !isEnd) {
      _isDragging = true;
      widget.onSeekingChanged?.call(true);
      _seekAnimController.forward();
    }

    if (_isDragging) {
      // Angle starting at top (12 o'clock, -pi/2) going clockwise
      final angle = atan2(dy, dx);
      var normalized = (angle + (pi / 2)) % (2 * pi);
      if (normalized < 0) normalized += 2 * pi;

      final progress = (normalized / (2 * pi)).clamp(0.0, 1.0);
      setState(() {
        _dragProgress = progress;
      });

      final totalMs = widget.duration.inMilliseconds;
      final targetDuration =
          Duration(milliseconds: (totalMs * progress).round());
      widget.onSeeking?.call(targetDuration);

      if (isEnd) {
        _isDragging = false;
        widget.onSeekingChanged?.call(false);
        _seekAnimController.reverse();
        widget.onSeek(targetDuration);
      }
    }
  }

  void _handleEnd(Size size) {
    if (_isDragging) {
      final totalMs = widget.duration.inMilliseconds;
      final targetDuration =
          Duration(milliseconds: (totalMs * _dragProgress).round());
      setState(() => _isDragging = false);
      widget.onSeekingChanged?.call(false);
      _seekAnimController.reverse();
      widget.onSeek(targetDuration);
    }
  }

  void _handleCancel() {
    if (_isDragging) {
      setState(() => _isDragging = false);
      widget.onSeekingChanged?.call(false);
      _seekAnimController.reverse();
    }
  }

  void _updateCachedGeometry(Size size, double outerInset) {
    if (_cachedPath != null &&
        _cachedSize == size &&
        _cachedOuterInset == outerInset &&
        _cachedWaveRatio == widget.waveAmplitudeRatio) {
      return;
    }
    _cachedPath = RippleFlowerClipper.buildPath(
      size,
      waveAmplitudeRatio: widget.waveAmplitudeRatio,
      lobes: widget.lobes,
      inset: outerInset,
    );
    final metrics = _cachedPath!.computeMetrics().toList();
    _cachedMetric = metrics.isNotEmpty ? metrics.first : null;
    _cachedSize = size;
    _cachedOuterInset = outerInset;
    _cachedWaveRatio = widget.waveAmplitudeRatio;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxSize = min(constraints.maxWidth, constraints.maxHeight);
        final size = Size(boxSize, boxSize);
        // Position the waveform track with comfortable breathing room inside the box
        final outerInset = widget.thumbRadius + 4.5;
        final maxRadius = (boxSize / 2) - outerInset;
        final waveBaseRadius = maxRadius / (1 + widget.waveAmplitudeRatio);
        final waveValleyRadius =
            waveBaseRadius * (1 - widget.waveAmplitudeRatio);

        _updateCachedGeometry(size, outerInset);

        return SizedBox(
          width: boxSize,
          height: boxSize,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // 1. Inset inner content (album art PageView, completely free to handle swipes)
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.all(
                    widget.thumbRadius + widget.paddingAroundChild,
                  ),
                  child: RepaintBoundary(child: widget.child),
                ),
              ),

              // 2. Waveform progress scrubber painter with seek animation (visual only, ignored for pointer events)
              if (_cachedPath != null && _cachedMetric != null)
                IgnorePointer(
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _seekAnimController,
                      builder: (context, _) {
                        return CustomPaint(
                          size: size,
                          painter: _WaveformProgressPainter(
                            progress: _currentProgress,
                            path: _cachedPath!,
                            metric: _cachedMetric!,
                            activeColor: widget.activeColor,
                            inactiveColor: widget.inactiveColor,
                            strokeWidth: _strokeWidthAnim.value,
                            thumbRadius: _thumbRadiusAnim.value,
                            haloRadius: _haloRadiusAnim.value,
                            seekProgress: _seekAnimController.value,
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // 3. Annular ring hit-test target that routes touches:
              // - Generous listening area (~50px band) around the waveform track and thumb dot!
              // - Touches inside the album art core (distance < innerRadius) fall through to double-tap & swipe!
              // - Touches on and around the waveform ring capture seek and drag smoothly, claiming the arena!
              Positioned.fill(
                child: _RingHitTest(
                  innerRadius:
                      (waveValleyRadius - 16.0).clamp(0.0, double.infinity),
                  outerRadius: (boxSize / 2) + 24.0,
                  child: RawGestureDetector(
                    gestures: <Type, GestureRecognizerFactory>{
                      _ScrubberGestureRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                              _ScrubberGestureRecognizer>(
                        () => _ScrubberGestureRecognizer(),
                        (_ScrubberGestureRecognizer instance) {
                          instance
                            ..onStart = (pos) {
                              _handleTouch(pos, size);
                            }
                            ..onUpdate = (pos) {
                              _handleTouch(pos, size);
                            }
                            ..onEnd = () {
                              _handleEnd(size);
                            }
                            ..onCancel = () {
                              _handleCancel();
                            };
                        },
                      ),
                    },
                    behavior: HitTestBehavior.opaque,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Dedicated gesture recognizer that immediately claims Flutter's gesture arena
/// on pointer down within the scrubber ring.
/// This prevents ancestor vertical drag recognizers (such as YTMDrawer's sheet minimize)
/// from interrupting seek gestures when dragging downwards/circularly.
class _ScrubberGestureRecognizer extends OneSequenceGestureRecognizer {
  ValueChanged<Offset>? onStart;
  ValueChanged<Offset>? onUpdate;
  VoidCallback? onEnd;
  VoidCallback? onCancel;

  _ScrubberGestureRecognizer();

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    resolve(GestureDisposition.accepted); // Instantly claim the arena!
    onStart?.call(event.localPosition);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      onUpdate?.call(event.localPosition);
    } else if (event is PointerUpEvent) {
      stopTrackingPointer(event.pointer);
      onEnd?.call();
    } else if (event is PointerCancelEvent) {
      stopTrackingPointer(event.pointer);
      onCancel?.call();
    }
  }

  @override
  String get debugDescription => 'scrubberGesture';

  @override
  void didStopTrackingLastPointer(int pointer) {}
}

/// Hit-test filter that only accepts touches within an annular ring.
class _RingHitTest extends SingleChildRenderObjectWidget {
  final double innerRadius;
  final double outerRadius;

  const _RingHitTest({
    required this.innerRadius,
    required this.outerRadius,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderRingHitTest(
      innerRadius: innerRadius,
      outerRadius: outerRadius,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRingHitTest renderObject,
  ) {
    renderObject
      ..innerRadius = innerRadius
      ..outerRadius = outerRadius;
  }
}

class _RenderRingHitTest extends RenderProxyBox {
  double innerRadius;
  double outerRadius;

  _RenderRingHitTest({
    required this.innerRadius,
    required this.outerRadius,
  });

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final center = Offset(size.width / 2, size.height / 2);
    final dx = position.dx - center.dx;
    final dy = position.dy - center.dy;
    final distance = sqrt(dx * dx + dy * dy);

    if (distance >= innerRadius && distance <= outerRadius) {
      return super.hitTest(result, position: position);
    }
    return false;
  }
}

class _WaveformProgressPainter extends CustomPainter {
  final double progress;
  final Path path;
  final PathMetric metric;
  final Color activeColor;
  final Color inactiveColor;
  final double strokeWidth;
  final double thumbRadius;
  final double haloRadius;
  final double seekProgress;

  _WaveformProgressPainter({
    required this.progress,
    required this.path,
    required this.metric,
    required this.activeColor,
    required this.inactiveColor,
    required this.strokeWidth,
    required this.thumbRadius,
    this.haloRadius = 0.0,
    this.seekProgress = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Inactive full waveform track
    final inactivePaint =
        Paint()
          ..color = inactiveColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;

    canvas.drawPath(path, inactivePaint);

    // 2. Active arc and thumb dot along the waveform from 12 o'clock clockwise
    final totalLength = metric.length;
    if (totalLength <= 0) return;

    final clampedProgress = progress.clamp(0.0, 1.0);
    final activeLength = totalLength * clampedProgress;

    if (activeLength > 0.0) {
      final activePath = metric.extractPath(0.0, activeLength);

      // Soft ambient glow along active track
      final activeGlowPaint =
          Paint()
            ..color = activeColor.withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth + 3.0
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0)
            ..isAntiAlias = true;
      canvas.drawPath(activePath, activeGlowPaint);

      final activePaint =
          Paint()
            ..color = activeColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth + 0.6
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..isAntiAlias = true;

      canvas.drawPath(activePath, activePaint);
    }

    // 3. Thumb dot (●) with ambient accent glow and seek halo
    final sampleOffset = activeLength > 0.0 ? activeLength : 0.0;
    final tangent = metric.getTangentForOffset(sampleOffset);
    if (tangent != null) {
      final thumbCenter = tangent.position;

      // Seeking expand overlay halo (native Slider overlay / bloom effect)
      if (haloRadius > 0.5 && seekProgress > 0.01) {
        final haloPaint =
            Paint()
              ..color = activeColor.withValues(alpha: 0.26 * seekProgress)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8.0 * seekProgress)
              ..style = PaintingStyle.fill
              ..isAntiAlias = true;
        canvas.drawCircle(thumbCenter, thumbRadius + haloRadius, haloPaint);
      }

      // Soft ambient glow matching dynamic artwork color
      final glowPaint =
          Paint()
            ..color = activeColor.withValues(alpha: 0.45 + 0.25 * seekProgress)
            ..maskFilter = MaskFilter.blur(
              BlurStyle.normal,
              5.0 + 4.0 * seekProgress,
            );
      canvas.drawCircle(thumbCenter, thumbRadius + 1.8, glowPaint);

      // Solid thumb dot
      final thumbPaint =
          Paint()
            ..color = activeColor
            ..style = PaintingStyle.fill
            ..isAntiAlias = true;
      canvas.drawCircle(thumbCenter, thumbRadius, thumbPaint);

      // Bright inner core during seeking for crisp visual feedback
      if (seekProgress > 0.05) {
        final innerCorePaint =
            Paint()
              ..color = Colors.white.withValues(alpha: 0.95 * seekProgress)
              ..style = PaintingStyle.fill
              ..isAntiAlias = true;
        canvas.drawCircle(thumbCenter, thumbRadius * 0.45, innerCorePaint);
      }
    }
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_WaveformProgressPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.inactiveColor != inactiveColor ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.thumbRadius != thumbRadius ||
      oldDelegate.haloRadius != haloRadius ||
      oldDelegate.seekProgress != seekProgress;
}
