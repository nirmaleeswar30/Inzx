import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:marquee/marquee.dart';
import 'package:skeletonizer/skeletonizer.dart';
import '../../providers/providers.dart';
import '../../services/jams/jams_models.dart';
import '../../models/models.dart';
import '../../services/audio_player_service.dart' as player;
import '../../services/lyrics/lyrics_service.dart';
import '../../services/lyrics/lyrics_models.dart';
import '../../services/lyrics/instrumental_gaps.dart';
import '../../core/design_system/design_system.dart';
import '../../core/l10n/app_localizations_x.dart';
import '../../core/providers/theme_provider.dart';
import 'artist_screen.dart';
import 'album_screen.dart' show AlbumScreen;
import 'playlist_screen.dart' show PlaylistScreen;
import 'podcast_screen.dart' show PodcastScreen;
import 'track_options_sheet.dart';
import 'lyrics_view.dart';
import 'karaoke_word.dart';
import 'ytm_drawer.dart';
import 'home_shelves.dart' show TrackListShelf;
import '../../services/local_artwork_service.dart';
import 'track_artwork_view.dart';
import 'animated_album_art_view.dart';
import 'ripple_now_playing_view.dart';
import 'edge_now_playing_view.dart';
import 'jam_indicator_badge.dart';
import 'jams_panel.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/deep_link_handler.dart';
import '../../services/download_service.dart';
import 'explicit_badge.dart';

/// Progress bar widget that only rebuilds on position changes (isolated)
class _NowPlayingProgressBar extends ConsumerStatefulWidget {
  final Duration? duration;
  final Color textColor;
  final Color secondaryColor;
  final Color accentColor;
  final bool isCompact;
  final bool isLive;
  final double? horizontalPadding;
  final double? verticalPadding;

  const _NowPlayingProgressBar({
    required this.duration,
    required this.textColor,
    required this.secondaryColor,
    required this.accentColor,
    this.isCompact = false,
    this.isLive = false,
    this.horizontalPadding,
    this.verticalPadding,
  });

  @override
  ConsumerState<_NowPlayingProgressBar> createState() =>
      _NowPlayingProgressBarState();
}

class _NowPlayingProgressBarState
    extends ConsumerState<_NowPlayingProgressBar>
    with TickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _trackHeightAnim;
  late final Animation<double> _thumbRadiusAnim;
  late final CurvedAnimation _spectrumZoomAnim;
  late final AnimationController _wavePhaseController;
  bool _isSeeking = false;
  double _dragPositionMs = 0;
  double? _lastSeekTargetMs;
  List<double>? _cachedAmplitudes;
  String? _cachedTrackId;
  final GlobalKey _progressKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _wavePhaseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    );

    final baseTrackHeight = widget.isCompact ? 3.0 : 4.0;
    final expandedTrackHeight = widget.isCompact ? 5.0 : 7.0;
    final baseThumbRadius = widget.isCompact ? 4.0 : 6.0;
    final expandedThumbRadius = widget.isCompact ? 7.0 : 9.0;

    _trackHeightAnim = Tween<double>(
      begin: baseTrackHeight,
      end: expandedTrackHeight,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeOutCubic,
    ));

    _thumbRadiusAnim = Tween<double>(
      begin: baseThumbRadius,
      end: expandedThumbRadius,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeOutCubic,
    ));

    _spectrumZoomAnim = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _spectrumZoomAnim.dispose();
    _scaleController.dispose();
    _wavePhaseController.dispose();
    super.dispose();
  }

  void _onSeekStart(double value) {
    setState(() {
      _isSeeking = true;
      _dragPositionMs = value;
      _lastSeekTargetMs = null;
    });
    _scaleController.forward();
  }

  void _onSeekChanged(double value) {
    setState(() {
      _dragPositionMs = value;
    });
  }

  void _onSeekEnd(double value) {
    final playerService = ref.read(audioPlayerServiceProvider);
    playerService.seek(Duration(milliseconds: value.toInt()));
    _lastSeekTargetMs = value;
    setState(() {
      _isSeeking = false;
    });
    _scaleController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _lastSeekTargetMs = null;
        });
      }
    });
  }

  double _getProgressBarWidth() {
    final renderBox =
        _progressKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize && renderBox.size.width > 0) {
      return renderBox.size.width;
    }
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = widget.isCompact ? 16.0 : 24.0;
    return (screenWidth - (horizontalPadding * 2)).clamp(1.0, double.infinity);
  }

  void _seekFromDx(double dx, double maxMs) {
    final width = _getProgressBarWidth();
    final frac = (dx / width).clamp(0.0, 1.0);
    final targetMs = frac * maxMs;
    _onSeekStart(targetMs);
    _onSeekEnd(targetMs);
  }

  void _seekStartFromDx(double dx, double maxMs) {
    final width = _getProgressBarWidth();
    final frac = (dx / width).clamp(0.0, 1.0);
    _onSeekStart(frac * maxMs);
  }

  void _seekUpdateFromDx(double dx, double maxMs) {
    final width = _getProgressBarWidth();
    final frac = (dx / width).clamp(0.0, 1.0);
    _onSeekChanged(frac * maxMs);
  }

  Widget _buildWaveformProgressBar({
    required double progress,
    required double displayMs,
    required double maxMs,
  }) {
    final barHeight = widget.isCompact ? 28.0 : 38.0;
    return GestureDetector(
      key: _progressKey,
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) =>
          _seekFromDx(details.localPosition.dx, maxMs),
      onHorizontalDragStart: (details) =>
          _seekStartFromDx(details.localPosition.dx, maxMs),
      onHorizontalDragUpdate: (details) =>
          _seekUpdateFromDx(details.localPosition.dx, maxMs),
      onHorizontalDragEnd: (_) => _onSeekEnd(_dragPositionMs),
      onHorizontalDragCancel: () {
        setState(() => _isSeeking = false);
        _scaleController.reverse();
      },
      child: SizedBox(
        height: barHeight,
        width: double.infinity,
        child: AnimatedBuilder(
          animation: Listenable.merge([_wavePhaseController, _scaleController]),
          builder: (context, child) {
            return CustomPaint(
              size: Size.infinite,
              painter: _WavyProgressBarPainter(
                progress: progress,
                phase: _wavePhaseController.value * 2 * math.pi,
                activeColor: widget.accentColor,
                inactiveColor: widget.textColor.withValues(alpha: 0.20),
                thumbColor: widget.textColor,
                trackHeight: _trackHeightAnim.value,
                thumbRadius: _thumbRadiusAnim.value,
                isSeeking: _isSeeking,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSpectrumProgressBar({
    required double progress,
    required double displayMs,
    required double maxMs,
    required List<double> amplitudes,
  }) {
    final barContainerHeight = widget.isCompact ? 36.0 : 48.0;

    return GestureDetector(
      key: _progressKey,
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) =>
          _seekStartFromDx(details.localPosition.dx, maxMs),
      onTapUp: (details) =>
          _onSeekEnd(_dragPositionMs),
      onTapCancel: () {
        if (_isSeeking) {
          setState(() => _isSeeking = false);
          _scaleController.reverse();
        }
      },
      onHorizontalDragStart: (details) =>
          _seekStartFromDx(details.localPosition.dx, maxMs),
      onHorizontalDragUpdate: (details) =>
          _seekUpdateFromDx(details.localPosition.dx, maxMs),
      onHorizontalDragEnd: (_) => _onSeekEnd(_dragPositionMs),
      onHorizontalDragCancel: () {
        setState(() => _isSeeking = false);
        _scaleController.reverse();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: SizedBox(
          height: barContainerHeight,
          width: double.infinity,
          child: AnimatedBuilder(
            animation: _spectrumZoomAnim,
            builder: (context, child) {
              return CustomPaint(
                size: Size.infinite,
                painter: _SpectrumBarPainter(
                  progress: progress,
                  amplitudes: amplitudes,
                  activeColor: widget.accentColor,
                  inactiveColor: widget.textColor.withValues(alpha: 0.20),
                  thumbColor: widget.textColor,
                  seekScale: _spectrumZoomAnim.value,
                  isSeeking: _isSeeking,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final position =
        ref.watch(positionStreamProvider).valueOrNull ?? Duration.zero;
    final progressBarStyle = ref.watch(progressBarStyleProvider);
    final isPlaying = ref.watch(isPlayingProvider);
    final currentTrack = ref.watch(currentTrackProvider);

    if (progressBarStyle == ProgressBarStyle.waveform) {
      if (isPlaying && !_wavePhaseController.isAnimating) {
        _wavePhaseController.repeat();
      } else if (!isPlaying && _wavePhaseController.isAnimating) {
        _wavePhaseController.stop();
      }
    } else if (_wavePhaseController.isAnimating) {
      _wavePhaseController.stop();
    }

    final trackId = currentTrack?.id ?? 'default_track';
    if (_cachedTrackId != trackId || _cachedAmplitudes == null) {
      _cachedTrackId = trackId;
      _cachedAmplitudes = _SpectrumBarPainter.generateAmplitudes(
        widget.isCompact ? 56 : 82,
        trackId.hashCode,
      );
    }

    final verticalPadding =
        widget.verticalPadding ?? (widget.isCompact ? 2.0 : 16.0);
    final horizontalPadding =
        widget.horizontalPadding ?? (widget.isCompact ? 16.0 : 24.0);

    // Live streams have no seekable length — show a LIVE indicator with a solid
    // track instead of a progress bar that would sit at a bogus 30s.
    if (widget.isLive) {
      return RepaintBoundary(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          child: Column(
            children: [
              Container(
                height: widget.isCompact ? 3 : 4,
                decoration: BoxDecoration(
                  color: widget.accentColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              SizedBox(height: widget.isCompact ? 4 : 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF3B30),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'LIVE',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: widget.secondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final maxMs = (widget.duration?.inMilliseconds ?? 0) > 0
        ? widget.duration!.inMilliseconds.toDouble()
        : 1.0;

    // Use local drag position during seek, hold position while zoom-out animation is running, stream position otherwise
    final double displayMs;
    if (_isSeeking) {
      displayMs = _dragPositionMs;
    } else if (_lastSeekTargetMs != null && _scaleController.isAnimating) {
      displayMs = _lastSeekTargetMs!;
    } else {
      displayMs = position.inMilliseconds.toDouble().clamp(0.0, maxMs);
    }
    final displayPosition = Duration(milliseconds: displayMs.toInt());
    final double progress =
        (maxMs > 0) ? (displayMs / maxMs).clamp(0.0, 1.0) : 0.0;

    return RepaintBoundary(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: verticalPadding,
        ),
        child: Column(
          children: [
            if (progressBarStyle == ProgressBarStyle.waveform)
              _buildWaveformProgressBar(
                progress: progress,
                displayMs: displayMs,
                maxMs: maxMs,
              )
            else if (progressBarStyle == ProgressBarStyle.spectrum)
              _buildSpectrumProgressBar(
                progress: progress,
                displayMs: displayMs,
                maxMs: maxMs,
                amplitudes: _cachedAmplitudes!,
              )
            else
              AnimatedBuilder(
                animation: _scaleController,
                builder: (context, child) {
                  return SliderTheme(
                    data: SliderThemeData(
                      trackHeight: _trackHeightAnim.value,
                      thumbShape: RoundSliderThumbShape(
                        enabledThumbRadius: _thumbRadiusAnim.value,
                      ),
                      overlayShape: RoundSliderOverlayShape(
                        overlayRadius: widget.isCompact ? 10 : 14,
                      ),
                      activeTrackColor: widget.accentColor,
                      inactiveTrackColor:
                          widget.textColor.withValues(alpha: 0.2),
                      thumbColor: widget.textColor,
                      overlayColor:
                          widget.accentColor.withValues(alpha: 0.2),
                    ),
                    child: Slider(
                      value: displayMs.clamp(0.0, maxMs),
                      min: 0,
                      max: maxMs,
                      onChangeStart: _onSeekStart,
                      onChanged: _onSeekChanged,
                      onChangeEnd: _onSeekEnd,
                    ),
                  );
                },
              ),
            SizedBox(
              height: progressBarStyle == ProgressBarStyle.defaultLinear
                  ? 0
                  : (widget.isCompact ? 2 : 4),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(displayPosition),
                    style: TextStyle(
                        fontSize: 12, color: widget.secondaryColor),
                  ),
                  Text(
                    _formatDuration(widget.duration ?? Duration.zero),
                    style: TextStyle(
                        fontSize: 12, color: widget.secondaryColor),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Custom painter for the animated wavy progress bar
class _WavyProgressBarPainter extends CustomPainter {
  final double progress; // 0.0 to 1.0
  final double phase; // 0.0 to 2*pi
  final Color activeColor;
  final Color inactiveColor;
  final Color thumbColor;
  final double trackHeight;
  final double thumbRadius;
  final bool isSeeking;

  _WavyProgressBarPainter({
    required this.progress,
    required this.phase,
    required this.activeColor,
    required this.inactiveColor,
    required this.thumbColor,
    required this.trackHeight,
    required this.thumbRadius,
    required this.isSeeking,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final progressWidth = (size.width * progress).clamp(0.0, size.width);
    const wavelength = 48.0;
    final baseAmplitude = (trackHeight * 1.25).clamp(3.0, 5.5);
    final effectiveAmplitude =
        baseAmplitude * (progressWidth / 32.0).clamp(0.0, 1.0);

    // 1. Draw inactive line from progress to total width
    if (progressWidth < size.width) {
      final inactivePaint = Paint()
        ..color = inactiveColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = trackHeight
        ..strokeCap = StrokeCap.round;

      final inactivePath = Path();
      inactivePath.moveTo(progressWidth, midY);
      inactivePath.lineTo(size.width, midY);
      canvas.drawPath(inactivePath, inactivePaint);
    }

    // 2. Draw active wavy path from 0 to progressWidth
    if (progressWidth > 0) {
      final activePaint = Paint()
        ..color = activeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = trackHeight
        ..strokeCap = StrokeCap.round;

      final activePath = Path();
      activePath.moveTo(0, midY);

      final steps = (progressWidth / 2.0).ceil().clamp(2, 400);
      for (int i = 1; i <= steps; i++) {
        final x = (i / steps) * progressWidth;
        final distanceFromStart = x;
        final distanceFromThumb = progressWidth - x;
        final startDamp = (distanceFromStart / 24.0).clamp(0.0, 1.0);
        final endDamp = (distanceFromThumb / 24.0).clamp(0.0, 1.0);
        final damp = startDamp * endDamp;
        final y = midY +
            math.sin((x / wavelength) * 2 * math.pi + phase) *
                effectiveAmplitude *
                damp;
        activePath.lineTo(x, y);
      }

      canvas.drawPath(activePath, activePaint);
    }

    // 3. Draw rolling soft-rounded square thumb at progressWidth
    final side = (isSeeking ? thumbRadius * 1.35 : thumbRadius) * 2.1;
    final cornerRadius = Radius.circular(side * 0.28);
    final rollAngle =
        isSeeking ? (progressWidth / (side * 3.5)) * math.pi : (phase * 0.75);

    canvas.save();
    canvas.translate(progressWidth, midY);
    canvas.rotate(rollAngle);

    // Dynamic accent glow/halo (subtle ambient aura while playing, expanded when seeking)
    final haloSide = side + (isSeeking ? 10.0 : 4.0);
    final haloRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset.zero,
        width: haloSide,
        height: haloSide,
      ),
      Radius.circular(haloSide * 0.28),
    );
    final haloPaint = Paint()
      ..color = activeColor.withValues(alpha: isSeeking ? 0.35 : 0.16)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(haloRect, haloPaint);

    // Crisp white square scrubber body
    final thumbRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset.zero,
        width: side,
        height: side,
      ),
      cornerRadius,
    );
    final thumbPaint = Paint()
      ..color = thumbColor
      ..style = PaintingStyle.fill;
    canvas.drawRRect(thumbRect, thumbPaint);

    // Dynamic accent border
    final borderPaint = Paint()
      ..color = activeColor.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawRRect(thumbRect, borderPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_WavyProgressBarPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.phase != phase ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.thumbColor != thumbColor ||
        oldDelegate.trackHeight != trackHeight ||
        oldDelegate.thumbRadius != thumbRadius ||
        oldDelegate.isSeeking != isSeeking;
  }
}

/// Custom painter for the Spectrum vertical amplitude bars scrubber with zoom seek
class _SpectrumBarPainter extends CustomPainter {
  final double progress;
  final List<double> amplitudes;
  final Color activeColor;
  final Color inactiveColor;
  final Color thumbColor;
  final double seekScale;
  final bool isSeeking;

  _SpectrumBarPainter({
    required this.progress,
    required this.amplitudes,
    required this.activeColor,
    required this.inactiveColor,
    required this.thumbColor,
    required this.seekScale,
    required this.isSeeking,
  });

  /// Generates a high-sensitivity, dynamic audio spectrum profile customized per track
  static List<double> generateAmplitudes(int count, int seed) {
    final rand = math.Random(seed);
    final list = <double>[];
    double prev = 0.25;

    for (int i = 0; i < count; i++) {
      final t = (count > 1) ? i / (count - 1) : 0.5;

      // Sectional dynamics: intro, verse, chorus/drop, bridge, climax, outro
      final double sectionCurve;
      if (t < 0.12) {
        sectionCurve = 0.05 + 0.38 * (t / 0.12);
      } else if (t < 0.35) {
        sectionCurve = 0.40 + 0.32 * math.sin((t - 0.12) / 0.23 * math.pi);
      } else if (t < 0.55) {
        sectionCurve = 0.68 + 0.32 * math.sin((t - 0.35) / 0.20 * math.pi);
      } else if (t < 0.70) {
        sectionCurve = 0.18 + 0.30 * math.sin((t - 0.55) / 0.15 * math.pi);
      } else if (t < 0.90) {
        sectionCurve = 0.72 + 0.28 * math.sin((t - 0.70) / 0.20 * math.pi);
      } else {
        sectionCurve = (1.0 - (t - 0.90) / 0.10).clamp(0.02, 0.70);
      }

      // Multi-frequency harmonic spectrum waves
      final wave1 = math.sin(i * 0.38 + seed) * 0.28;
      final wave2 = math.cos(i * 0.95 + seed * 2) * 0.20;
      final wave3 = math.sin(i * 1.85 + seed * 3) * 0.15;

      // Rhythmic beat pulses (kick transients every ~4 bars)
      final isBeat = (i % 4 == 0) ? 0.28 : ((i % 2 == 0) ? 0.12 : -0.08);

      // Micro-variation noise for fine-grained spectrum detail
      final noise = (rand.nextDouble() - 0.5) * 0.35;

      // Target amplitude with wide dynamic range
      final target = (sectionCurve + wave1 + wave2 + wave3 + isBeat + noise)
          .clamp(0.04, 1.0);

      // Low damping (0.24 prev, 0.76 target) preserves crisp sensitivity to peaks and drops
      prev = (prev * 0.24 + target * 0.76).clamp(0.04, 1.0);
      list.add(prev);
    }
    return list;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (amplitudes.isEmpty || size.width <= 0 || size.height <= 0) return;

    final totalBars = amplitudes.length;
    final step = size.width / totalBars;
    // Slender, modern thin bars matching mockup
    final baseBarWidth = (step * 0.46).clamp(1.5, 2.4);
    final midY = size.height / 2;
    final cursorX = (progress * size.width).clamp(0.0, size.width);

    // Smoothly scale maximum bar height from resting (62% of container) to seeking (92% of container)
    final restMaxHeight = size.height * 0.62;
    final seekMaxHeight = size.height * 0.92;
    final currentMaxHeight =
        restMaxHeight + (seekMaxHeight - restMaxHeight) * seekScale;

    // Zoom window parameters during seek
    final zoomRadius = size.width * 0.16;

    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;

    final inactivePaint = Paint()
      ..color = inactiveColor
      ..style = PaintingStyle.fill;

    for (int i = 0; i < totalBars; i++) {
      final x = i * step + step / 2;
      final barFraction = (i + 0.5) / totalBars;
      final isActive = barFraction <= progress;

      // Localized magnification zoom around seek cursor
      final dist = (x - cursorX).abs();
      final double zoomFactor;
      if (seekScale > 0.0 && dist < zoomRadius) {
        zoomFactor = math.cos((dist / zoomRadius) * (math.pi / 2)) * seekScale;
      } else {
        zoomFactor = 0.0;
      }

      final amp = amplitudes[i];
      final currentBarWidth =
          (baseBarWidth * (1.0 + zoomFactor * 0.45)).clamp(1.5, 3.2);
      final rawHeight = amp * (1.0 + zoomFactor * 0.30) * currentMaxHeight;
      // When rawHeight is small, barHeight equals currentBarWidth -> becomes a perfect circular dot
      final barHeight = rawHeight < currentBarWidth
          ? currentBarWidth
          : rawHeight.clamp(currentBarWidth, size.height);
      final top = midY - barHeight / 2;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x - currentBarWidth / 2, top, currentBarWidth, barHeight),
        Radius.circular(currentBarWidth / 2),
      );
      canvas.drawRRect(rect, isActive ? activePaint : inactivePaint);
    }

    // Draw animated seek playhead needle & glowing indicator when seeking
    if (seekScale > 0.0) {
      // 1. Luminous halo around cursor
      final haloWidth = 12.0 + 6.0 * seekScale;
      final haloPaint = Paint()
        ..color = activeColor.withValues(alpha: (0.35 * seekScale).clamp(0.0, 1.0))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cursorX, midY),
            width: haloWidth,
            height: currentMaxHeight + 4.0,
          ),
          Radius.circular(haloWidth / 2),
        ),
        haloPaint,
      );

      // 2. Crisp refined needle playhead line
      final needleWidth = 2.2;
      final needleHeight = currentMaxHeight + 6.0;
      final needleRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cursorX, midY),
          width: needleWidth,
          height: needleHeight,
        ),
        const Radius.circular(1.1),
      );

      final needlePaint = Paint()
        ..color = thumbColor.withValues(alpha: (0.95 * seekScale).clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;
      canvas.drawRRect(needleRect, needlePaint);

      // 3. Top and bottom accent indicator diamonds
      final diamondSize = 5.0 * seekScale;
      final diamondPaint = Paint()
        ..color = activeColor
        ..style = PaintingStyle.fill;

      void drawDiamond(Offset center) {
        final path = Path()
          ..moveTo(center.dx, center.dy - diamondSize / 2)
          ..lineTo(center.dx + diamondSize / 2, center.dy)
          ..lineTo(center.dx, center.dy + diamondSize / 2)
          ..lineTo(center.dx - diamondSize / 2, center.dy)
          ..close();
        canvas.drawPath(path, diamondPaint);
      }

      drawDiamond(Offset(cursorX, midY - needleHeight / 2));
      drawDiamond(Offset(cursorX, midY + needleHeight / 2));
    }
  }

  @override
  bool shouldRepaint(_SpectrumBarPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.amplitudes != amplitudes ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.thumbColor != thumbColor ||
        oldDelegate.seekScale != seekScale ||
        oldDelegate.isSeeking != isSeeking;
  }
}


/// Isolated lyrics container that watches [positionStreamProvider] without
/// causing the parent NowPlayingScreen widget tree to rebuild on audio ticks.
class _IsolatedLyricsView extends ConsumerWidget {
  final bool isActive;
  const _IsolatedLyricsView({this.isActive = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Live/radio streams: don't show (stale/mismatched) lyrics.
    if (ref.watch(isLiveProvider)) {
      return Center(
        child: Text(
          'Lyrics aren’t available for live streams',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      );
    }
    final position =
        ref.watch(positionStreamProvider).valueOrNull ?? Duration.zero;
    return RepaintBoundary(
      child: LyricsView(currentPosition: position, isActive: isActive),
    );
  }
}

// NOTE: albumColorsProvider is now defined in music_providers.dart for app-wide access

const double _syncedLyricPreviewHeight = 72.0;

/// Isolated synced lyric preview widget that renders word-level karaoke sync under album art
@visibleForTesting
class SyncedLyricPreview extends ConsumerStatefulWidget {
  final Color textColor;
  final Color accentColor;
  final VoidCallback onTap;
  final bool isCentered;

  const SyncedLyricPreview({
    super.key,
    required this.textColor,
    required this.accentColor,
    required this.onTap,
    this.isCentered = false,
  });

  @override
  ConsumerState<SyncedLyricPreview> createState() => _SyncedLyricPreviewState();
}

class _SyncedLyricPreviewState extends ConsumerState<SyncedLyricPreview>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<int> _smoothPositionNotifier = ValueNotifier<int>(0);
  int _lastAudioMs = 0;
  int _lastSyncEpochMs = 0;
  int _currentLineIndex = -1;
  bool _inMidSongBreak = false;
  String? _lastVideoId;
  bool _isPlaying = false;
  LyricsState? _latestLyricsState;

  @override
  void initState() {
    super.initState();
    final initialPos =
        ref.read(positionStreamProvider).valueOrNull ?? Duration.zero;
    _lastAudioMs = initialPos.inMilliseconds;
    _lastSyncEpochMs = DateTime.now().millisecondsSinceEpoch;
    _smoothPositionNotifier.value = _lastAudioMs;
    _isPlaying = ref.read(isPlayingProvider);
    _latestLyricsState = ref.read(lyricsProvider);

    _ticker = createTicker((_) {
      if (!mounted) return;
      if (_isPlaying) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final elapsed = now - _lastSyncEpochMs;
        final current = _lastAudioMs + elapsed;
        if (_smoothPositionNotifier.value != current) {
          _smoothPositionNotifier.value = current;
          _checkLineIndexChange(current);
        }
      } else if (_smoothPositionNotifier.value != _lastAudioMs) {
        _smoothPositionNotifier.value = _lastAudioMs;
        _checkLineIndexChange(_lastAudioMs);
      }
    });
    if (_isPlaying) {
      _ticker.start();
    }
  }

  void _checkLineIndexChange(int currentPositionMs) {
    if (!mounted) return;
    final lines = _latestLyricsState?.currentLyrics?.lines;
    if (lines == null || lines.isEmpty) {
      if (_currentLineIndex != -1 || _inMidSongBreak) {
        _safeSetState(() {
          _currentLineIndex = -1;
          _inMidSongBreak = false;
        });
      }
      return;
    }

    int newIdx = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].timeInMs <= currentPositionMs) {
        newIdx = i;
      } else {
        break;
      }
    }

    bool shouldBeInBreak = false;
    if (newIdx >= 0 && newIdx < lines.length) {
      final cur = lines[newIdx];
      if (!cur.isGap) {
        final nextLineStart = (newIdx + 1 < lines.length)
            ? lines[newIdx + 1].timeInMs
            : null;
        if (nextLineStart != null) {
          final int vocalEnd = cur.hasKnownEnd
              ? cur.endMs
              : (cur.timeInMs +
                  (cur.text.trim().split(RegExp(r'\s+')).length * 300)
                      .clamp(2500, 4500));
          if ((nextLineStart - vocalEnd) >= 3500 &&
              currentPositionMs >= (vocalEnd + 800) &&
              currentPositionMs < nextLineStart) {
            shouldBeInBreak = true;
          }
        }
      }
    }

    if (newIdx != _currentLineIndex || shouldBeInBreak != _inMidSongBreak) {
      _safeSetState(() {
        _currentLineIndex = newIdx;
        _inMidSongBreak = shouldBeInBreak;
      });
    }
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(fn);
        }
      });
    } else {
      setState(fn);
    }
  }

  @override
  void deactivate() {
    _ticker.stop();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    if (_isPlaying && !_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _smoothPositionNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _isPlaying = ref.watch(isPlayingProvider);
    final lyricsState = ref.watch(lyricsProvider);
    _latestLyricsState = lyricsState;

    // Synchronize play/pause state
    ref.listen<bool>(isPlayingProvider, (prev, isPlaying) {
      _isPlaying = isPlaying;
      if (!mounted) return;
      if (isPlaying) {
        _lastSyncEpochMs = DateTime.now().millisecondsSinceEpoch;
        if (!_ticker.isActive) {
          _ticker.start();
        }
      } else {
        if (_ticker.isActive) {
          _ticker.stop();
        }
      }
    });

    // Synchronize audio stream ticks / seeks without rebuilding widget tree
    ref.listen<AsyncValue<Duration>>(positionStreamProvider, (prev, next) {
      if (!mounted) return;
      final newMs = next.valueOrNull?.inMilliseconds;
      if (newMs == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final estimatedCurrent = _lastAudioMs + (now - _lastSyncEpochMs);
      final drift = (newMs - estimatedCurrent).abs();

      if (drift > 80 || newMs < _lastAudioMs || (newMs - _lastAudioMs) > 1000) {
        _lastAudioMs = newMs;
        _lastSyncEpochMs = now;
        _smoothPositionNotifier.value = newMs;
        _checkLineIndexChange(newMs);
      }
    });

    if (lyricsState.videoId != _lastVideoId) {
      _lastVideoId = lyricsState.videoId;
      _currentLineIndex = -1;
      _inMidSongBreak = false;
      _lastAudioMs = 0;
      _lastSyncEpochMs = DateTime.now().millisecondsSinceEpoch;
      _smoothPositionNotifier.value = 0;
    }

    final result = lyricsState.currentLyrics;
    final isFetching =
        lyricsState.currentStatus.state == LyricsProviderState.fetching;
    final hasSynced = result != null && result.hasSyncedLyrics;
    final lines = hasSynced ? result.lines! : const <LyricLine>[];

    // Initialize line index if not set and synced lyrics are ready
    if (hasSynced && _currentLineIndex == -1 && lines.isNotEmpty) {
      final pos = _smoothPositionNotifier.value;
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].timeInMs <= pos) {
          _currentLineIndex = i;
        } else {
          break;
        }
      }
    }

    final bool showPreview = hasSynced || isFetching;

    Widget content;
    final String switcherKey;
    bool isInstrumental = false;
    bool isIntro = false;
    int firstSungIdx = -1;
    LyricLine? activeLine;

    if (isFetching) {
      final currentTrack = ref.watch(currentTrackProvider);
      final seed = currentTrack?.id.hashCode ?? 0;
      final loadingText = LyricsLoadingTexts.getText(seed);
      switcherKey = 'loading_${lyricsState.videoId}';
      content = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: widget.isCentered
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: [
          Icon(
            Icons.music_note_rounded,
            size: 16,
            color: widget.accentColor.withValues(alpha: 0.85),
            shadows: [
              Shadow(
                color: widget.accentColor.withValues(alpha: 0.3),
                blurRadius: 8,
              ),
            ],
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              loadingText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign:
                  widget.isCentered ? TextAlign.center : TextAlign.left,
              style: TextStyle(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w500,
                color: widget.textColor.withValues(alpha: 0.65),
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      );
    } else if (hasSynced && lines.isNotEmpty) {
      final pos = _smoothPositionNotifier.value;
      final currentLine =
          (_currentLineIndex >= 0 && _currentLineIndex < lines.length)
              ? lines[_currentLineIndex]
              : null;
      activeLine = currentLine;

      firstSungIdx = lines.indexWhere((l) => !l.isGap);

      // Determine whether the player is currently in an instrumental passage:
      // 1. Before the first sung line (intro)
      // 2. An explicit gap line or musical symbol line
      // 3. A natural break between non-gap lines (>= 3.5s gap after vocal finishes)
      if (_inMidSongBreak ||
          (currentLine != null && currentLine.isGap) ||
          (_currentLineIndex == -1 && lines.isNotEmpty && pos < lines[0].timeInMs)) {
        isInstrumental = true;
        isIntro = (_currentLineIndex == -1 ||
            (_currentLineIndex >= 0 &&
                _currentLineIndex < lines.length &&
                lines[_currentLineIndex].isGap &&
                (firstSungIdx == -1 || _currentLineIndex < firstSungIdx)));

        final seed = (lyricsState.videoId.hashCode ^ _currentLineIndex);
        final String gapText;
        if (isIntro) {
          gapText = (currentLine != null &&
                  currentLine.text.trim().isNotEmpty &&
                  !LyricLine.isMusicalSymbol(currentLine.text))
              ? currentLine.text.trim()
              : InstrumentalGapTexts.getIntroText(seed);
        } else {
          gapText = (currentLine != null &&
                  currentLine.text.trim().isNotEmpty &&
                  !LyricLine.isMusicalSymbol(currentLine.text))
              ? currentLine.text.trim()
              : InstrumentalGapTexts.getBreakText(seed);
        }

        switcherKey = 'gap_${_currentLineIndex}_${isIntro ? "intro" : "break"}';
        content = Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: widget.isCentered
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          children: [
            Icon(
              Icons.music_note_rounded,
              size: 18,
              color: widget.accentColor.withValues(alpha: 0.9),
              shadows: [
                Shadow(
                  color: widget.accentColor.withValues(alpha: 0.35),
                  blurRadius: 10,
                ),
              ],
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                gapText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign:
                    widget.isCentered ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w600,
                  color: widget.accentColor.withValues(alpha: 0.9),
                  letterSpacing: 0.3,
                  shadows: [
                    Shadow(
                      color: widget.accentColor.withValues(alpha: 0.3),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      } else if (currentLine != null) {
        if (currentLine.hasWordSync) {
          switcherKey = 'words_$_currentLineIndex';
          content = Wrap(
            alignment: widget.isCentered
                ? WrapAlignment.center
                : WrapAlignment.start,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: currentLine.words!.asMap().entries.map((entry) {
              final wordIdx = entry.key;
              final word = entry.value;
              final isLastWord = wordIdx == currentLine.words!.length - 1;

              return KaraokeWord(
                word: word,
                isLastWord: isLastWord,
                isCurrentLine: true,
                positionNotifier: _smoothPositionNotifier,
                fontSize: 15.0,
                isBg: currentLine.isBackground,
                textColor: widget.textColor,
                accentColor: widget.accentColor,
                dimColor: widget.textColor.withValues(alpha: 0.5),
              );
            }).toList(),
          );
        } else {
          // Standard line sync
          switcherKey = 'line_$_currentLineIndex';
          content = Text(
            currentLine.text.trim(),
            maxLines: 3,
            overflow: TextOverflow.clip,
            softWrap: true,
            textAlign:
                widget.isCentered ? TextAlign.center : TextAlign.left,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: widget.textColor.withValues(alpha: 0.90),
              fontStyle:
                  currentLine.isBackground ? FontStyle.italic : FontStyle.normal,
            ),
          );
        }
      } else {
        switcherKey = 'empty';
        content = const SizedBox.shrink();
      }
    } else {
      switcherKey = 'empty';
      content = const SizedBox.shrink();
    }

    final int widgetLineIndex = _currentLineIndex;
    final LyricLine? widgetLine = activeLine;
    final bool widgetIsInstrumental = isInstrumental;
    final bool widgetIsIntro = isIntro;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        height: showPreview ? _syncedLyricPreviewHeight : 0.0,
        child: ClipRect(
          child: Padding(
            padding: widget.isCentered
                ? const EdgeInsets.fromLTRB(16, 4, 16, 4)
                : const EdgeInsets.fromLTRB(24, 6, 24, 6),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 360),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  alignment: widget.isCentered
                      ? Alignment.center
                      : Alignment.centerLeft,
                  children: [
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                );
              },
              transitionBuilder: (child, animation) {
                final isIncoming = child.key == ValueKey(switcherKey);
                if (isIncoming) {
                  final inCurved = CurvedAnimation(
                    parent: animation,
                    curve: const Interval(0.40, 1.0, curve: Curves.easeOutCubic),
                  );
                  return FadeTransition(
                    opacity: inCurved,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.025),
                        end: Offset.zero,
                      ).animate(inCurved),
                      child: child,
                    ),
                  );
                } else {
                  final outCurved = CurvedAnimation(
                    parent: animation,
                    curve: const Interval(0.60, 1.0, curve: Curves.easeInCubic),
                  );
                  return FadeTransition(
                    opacity: outCurved,
                    child: child,
                  );
                }
              },
              child: Align(
                key: ValueKey(switcherKey),
                alignment: widget.isCentered
                    ? Alignment.center
                    : Alignment.centerLeft,
                child: AnimatedBuilder(
                  animation: _smoothPositionNotifier,
                  builder: (context, child) {
                    final pos = _smoothPositionNotifier.value;
                    double lineAlpha = 1.0;

                    if (widgetIsInstrumental) {
                      // Instrumental gap or intro:
                      final int? nextSungIdx;
                      if (widgetIsIntro) {
                        nextSungIdx = firstSungIdx >= 0 ? firstSungIdx : null;
                      } else {
                        nextSungIdx = (widgetLineIndex + 1 < lines.length)
                            ? widgetLineIndex + 1
                            : null;
                      }

                      if (nextSungIdx != null && nextSungIdx < lines.length) {
                        final nextStart = lines[nextSungIdx].timeInMs;
                        if (pos >= nextStart) {
                          lineAlpha = 0.0;
                        } else {
                          final remaining = nextStart - pos;
                          if (remaining < 350) {
                            lineAlpha = (remaining / 350.0).clamp(0.0, 1.0);
                          }
                        }
                      }
                    } else if (widgetLine != null) {
                      // Vocal lyric line:
                      final int nextStart = (widgetLineIndex + 1 < lines.length)
                          ? lines[widgetLineIndex + 1].timeInMs
                          : (widgetLine.timeInMs + 1000000);

                      if (pos >= nextStart) {
                        // CRITICAL: Once playback has reached or passed the next line,
                        // this retiring line must stay at 0.0 opacity so it never flashes back!
                        lineAlpha = 0.0;
                      } else if (widgetLine.hasKnownEnd) {
                        final vocalEnd = widgetLine.endMs;
                        if (pos > vocalEnd) {
                          final elapsed = pos - vocalEnd;
                          lineAlpha = (1.0 - (elapsed / 350.0)).clamp(0.0, 1.0);
                        }
                        final remaining = nextStart - pos;
                        if (remaining < 350) {
                          final nextFade =
                              (remaining / 350.0).clamp(0.0, 1.0);
                          if (nextFade < lineAlpha) {
                            lineAlpha = nextFade;
                          }
                        }
                      } else if (widgetLineIndex + 1 < lines.length) {
                        final remaining = nextStart - pos;
                        if (remaining < 350) {
                          lineAlpha = (remaining / 350.0).clamp(0.0, 1.0);
                        }
                      } else {
                        final lineEnd = widgetLine.timeInMs + 4000;
                        if (pos > lineEnd) {
                          final elapsed = pos - lineEnd;
                          lineAlpha = (1.0 - (elapsed / 400.0)).clamp(0.0, 1.0);
                        }
                      }
                    }

                    return Opacity(
                      opacity: lineAlpha,
                      child: child,
                    );
                  },
                  child: content,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen now playing screen with OuterTune-style dynamic theming
/// NO TRANSLUCENCY - Solid, well-filtered colors only
class NowPlayingScreen extends ConsumerStatefulWidget {
  final VoidCallback? onClose;

  const NowPlayingScreen({super.key, this.onClose});

  /// Show the Now Playing screen with Hero animation support
  static void show(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black54,
        barrierDismissible: true,
        pageBuilder: (context, animation, secondaryAnimation) {
          return const NowPlayingScreen();
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // Slide up from bottom with fade
          final slideAnimation =
              Tween<Offset>(
                begin: const Offset(0.0, 1.0),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              );

          return SlideTransition(position: slideAnimation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 350),
        reverseTransitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen>
    with TickerProviderStateMixin {
  late AnimationController _colorAnimController;
  late TabController _tabController;
  late PageController _pageController;
  late PageController _albumArtPageController; // For swiping album art
  late PageController _stageViewPageController; // For swiping right panel in Stage View
  final GlobalKey<YTMDrawerState> _drawerKey = GlobalKey<YTMDrawerState>();
  AlbumColors _currentColors = AlbumColors.defaultColors();
  AlbumColors _targetColors = AlbumColors.defaultColors();
  String? _lastLyricsTrackId;
  int? _lastLyricsDurationSeconds;
  String? _lastLyricsArtist;
  String? _lastRelatedTrackId; // Cache key for related tracks
  Future<WatchRelatedContent>? _relatedContentFuture;
  // ignore: unused_field - reserved for future panel toggle features
  bool _showLyrics = false;
  // ignore: unused_field - reserved for future panel toggle features
  bool _showQueue = false;
  bool _isDrawerExpanded = false; // Track drawer state
  bool _initialColorLoad = true;
  bool _isAlbumSwipeNavigationInProgress = false;
  bool _isUserDraggingAlbumArt = false;
  bool _hasAnimatedCanvas = false; // Track if current song actually has canvas
  double _dismissTranslateOffset = 0.0;
  bool _isDismissSnapping = false;
  int? _lastAlbumArtSyncedIndex;
  Orientation? _lastOrientation;
  late AnimationController _heartAnimController;
  late Animation<double> _heartScaleAnimation;
  late Animation<double> _heartOpacityAnimation;
  late ScrollController _queueScrollController;
  bool _hasInitialQueueScrolled = false;
  Timer? _nerdStatsAlternateTimer;
  bool _showStatsInsteadOfTitle = false;
  bool _isScrubberSeeking = false;

  @override
  void initState() {
    super.initState();
    _nerdStatsAlternateTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) {
        setState(() {
          _showStatsInsteadOfTitle = !_showStatsInsteadOfTitle;
        });
      }
    });
    _colorAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _colorAnimController.addListener(() {
      if (mounted) setState(() {});
    });
    _colorAnimController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _currentColors = _targetColors;
      }
    });

    _queueScrollController = ScrollController();

    // Tab controller for bottom tabs
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        final newIndex = _tabController.index;
        setState(() {
          _showQueue = newIndex == 0;
          _showLyrics = newIndex == 1;
          // index 2 = Related
        });
        if (newIndex == 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToActiveTrack(animate: true);
          });
        }
        if (_pageController.hasClients &&
            _pageController.page?.round() != newIndex) {
          _pageController.animateToPage(
            newIndex,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        }
      }
    });

    // Page controller for swiping content
    _pageController = PageController(initialPage: 0);

    // Album art page controller follows actual queue index starting on active index
    final initialQueueIndex =
        ref.read(audioPlayerServiceProvider).currentIndex;
    final startPage = initialQueueIndex >= 0 ? initialQueueIndex : 0;
    _albumArtPageController = PageController(initialPage: startPage);
    _lastAlbumArtSyncedIndex = startPage;

    // Stage view page controller starts on Lyrics (index 1)
    _stageViewPageController = PageController(initialPage: 1);

    // Double tap like heart pop animation controller
    _heartAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _heartScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.2, end: 1.25)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.25, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.35)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 40,
      ),
    ]).animate(_heartAnimController);

    _heartOpacityAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.0),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0),
        weight: 40,
      ),
    ]).animate(_heartAnimController);
  }

  @override
  void dispose() {
    _colorAnimController.dispose();
    _tabController.dispose();
    _pageController.dispose();
    _albumArtPageController.dispose();
    _stageViewPageController.dispose();
    _heartAnimController.dispose();
    _queueScrollController.dispose();
    _nerdStatsAlternateTimer?.cancel();
    super.dispose();
  }

  void _scrollToActiveTrack({bool animate = true}) {
    if (!mounted || !_queueScrollController.hasClients) return;

    final queue = ref.read(queueProvider);
    final currentTrack = ref.read(currentTrackProvider);
    if (queue.isEmpty) return;

    int activeIndex = -1;
    if (currentTrack != null) {
      activeIndex = queue.indexWhere((t) => t.id == currentTrack.id);
    }
    if (activeIndex < 0) {
      activeIndex = ref.read(audioPlayerServiceProvider).currentIndex;
    }

    if (activeIndex <= 0) {
      if (_queueScrollController.offset != 0) {
        if (animate) {
          _queueScrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        } else {
          _queueScrollController.jumpTo(0);
        }
      }
      return;
    }

    const double itemExtent = 72.0;
    double targetOffset = (activeIndex * itemExtent) - 80.0;
    if (targetOffset < 0) targetOffset = 0;
    if (_queueScrollController.position.hasContentDimensions) {
      targetOffset = targetOffset.clamp(
        0.0,
        _queueScrollController.position.maxScrollExtent,
      );
    }

    if (animate) {
      _queueScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    } else {
      _queueScrollController.jumpTo(targetOffset);
    }
  }

  @override
  Widget build(BuildContext context) {
    final playbackState = ref.watch(playbackStateProvider);
    final playerService = ref.watch(audioPlayerServiceProvider);
    final albumColors = ref.watch(albumColorsProvider);
    final currentTrack = ref.watch(currentTrackProvider);
    final currentQueueIndex = playerService.currentIndex;

    ref.listen<Track?>(currentTrackProvider, (previous, next) {
      if (next != null && previous?.id != next.id) {
        _hasInitialQueueScrolled = false;
        if (_tabController.index == 0 && _isDrawerExpanded) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToActiveTrack(animate: true);
          });
        }
      }
    });

    final currentOrientation = MediaQuery.of(context).orientation;
    if (_lastOrientation != currentOrientation) {
      _lastOrientation = currentOrientation;
      _lastAlbumArtSyncedIndex = currentQueueIndex;

      // Swap out the PageController so the incoming PageView in the new orientation
      // immediately mounts at the active track index without any initialPage=0 mismatch
      final oldController = _albumArtPageController;
      _albumArtPageController = PageController(
        initialPage: currentQueueIndex >= 0 ? currentQueueIndex : 0,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          oldController.dispose();
        } catch (_) {}
      });

      if (currentOrientation == Orientation.landscape) {
        // In landscape, ensure tabs are on Lyrics (index 1) without async post-frame jumps
        if (_tabController.index != 1) {
          _tabController.index = 1;
        }
        _isDrawerExpanded = false;
      } else {
        // Returning to portrait: keep drawer collapsed so the user sees the full Now Playing view
        _isDrawerExpanded = false;
      }
    }

    if (currentQueueIndex >= 0 &&
        currentQueueIndex != _lastAlbumArtSyncedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_albumArtPageController.hasClients) return;
        _lastAlbumArtSyncedIndex = currentQueueIndex;
        final activePage = _safeAlbumArtPage(-1.0).round();
        if (activePage != currentQueueIndex) {
          _isAlbumSwipeNavigationInProgress = true;
          if ((activePage - currentQueueIndex).abs() > 1 || _isDrawerExpanded) {
            _albumArtPageController.jumpToPage(currentQueueIndex);
            _isAlbumSwipeNavigationInProgress = false;
          } else {
            _albumArtPageController
                .animateToPage(
                  currentQueueIndex,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                )
                .then((_) {
                  if (mounted) {
                    _isAlbumSwipeNavigationInProgress = false;
                  }
                })
                .catchError((_) {
                  if (mounted) {
                    _isAlbumSwipeNavigationInProgress = false;
                  }
                });
          }
        }
      });
    }

    // First time opening - trigger color extraction immediately & adopt existing colors if non-default
    if (_initialColorLoad && currentTrack != null) {
      _initialColorLoad = false;
      if (!albumColors.isDefault) {
        _currentColors = albumColors;
        _targetColors = albumColors;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(albumColorsProvider.notifier).updateForTrack(currentTrack);
        }
      });
    }

    // Track change for lyrics fetch
    final trackId = currentTrack?.id;
    final currentDurationSec = currentTrack?.duration.inSeconds ?? 0;
    final currentArtist = currentTrack?.artist ?? '';
    // Live/radio streams have no fixed track, so time-synced lyrics fetched by
    // title match are meaningless — never fetch lyrics for them.
    final isLiveStream = ref.watch(isLiveProvider);
    final isNewTrack =
        trackId != _lastLyricsTrackId && currentTrack != null && !isLiveStream;

    final lyricsState = ref.watch(lyricsProvider);
    final hasSyncedLyrics =
        lyricsState.currentLyrics?.lines?.any((l) => l.timeInMs > 0) ?? false;

    // Trigger re-fetch if duration or artist were missing/placeholder and are now enriched with no synced lyrics yet
    final isEnriched = !isNewTrack &&
        currentTrack != null &&
        !isLiveStream &&
        !hasSyncedLyrics &&
        (((_lastLyricsDurationSeconds ?? 0) == 0 && currentDurationSec > 0) ||
            ((_lastLyricsArtist == null ||
                    _lastLyricsArtist == 'Song' ||
                    _lastLyricsArtist == 'Unknown Artist' ||
                    _lastLyricsArtist!.isEmpty) &&
                currentArtist.isNotEmpty &&
                currentArtist != 'Song' &&
                currentArtist != 'Unknown Artist'));

    if (isNewTrack || isEnriched) {
      _lastLyricsTrackId = trackId;
      _lastLyricsDurationSeconds = currentDurationSec;
      _lastLyricsArtist = currentArtist;

      // Fetch lyrics for new track
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref
              .read(lyricsProvider.notifier)
              .fetchLyrics(
                LyricsSearchInfo(
                  videoId: currentTrack.id,
                  title: currentTrack.title,
                  artist: currentTrack.artist,
                  album: currentTrack.album,
                  durationSeconds: currentTrack.duration.inSeconds,
                  localFilePath: currentTrack.localFilePath,
                ),
              );
        }
      });
    }

    // Animate when new colors arrive (not default)
    if (albumColors != _targetColors && !albumColors.isDefault) {
      if (_targetColors.isDefault) {
        // Apply immediately if coming from default fallback
        _currentColors = albumColors;
        _targetColors = albumColors;
      } else {
        _currentColors = AlbumColors.lerp(
          _currentColors,
          _targetColors,
          _colorAnimController.value,
        );
        _targetColors = albumColors;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _colorAnimController.forward(from: 0);
          }
        });
      }
    }

    // Calculate animated colors - smooth lerp from current to target
    final animatedColors = AlbumColors.lerp(
      _currentColors,
      _targetColors,
      _colorAnimController.value,
    );

    // Use lighter pastel version in light mode
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = isDark ? animatedColors : animatedColors.toLightMode();

    return playbackState.when(
      data: (state) {
        if (state.currentTrack == null) {
          return const SizedBox.shrink();
        }

        final track = state.currentTrack!;

        // SOLID colors - no translucency
        final backgroundColor = colors.backgroundPrimary;
        final accentColor = colors.accent;
        final textColor = colors.onBackground;
        final secondaryTextColor = textColor.withValues(alpha: 0.7);

        final isLandscape =
            MediaQuery.of(context).orientation == Orientation.landscape;
        final nowPlayingStyle = ref.watch(nowPlayingStyleProvider);

        if (isLandscape) {
          return Scaffold(
            backgroundColor: backgroundColor,
            body: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    colors.backgroundPrimary,
                    colors.backgroundSecondary,
                  ],
                  stops: const [0.0, 1.0],
                ),
              ),
              child: _buildStageView(
                track,
                state,
                playerService,
                textColor,
                secondaryTextColor,
                accentColor,
                colors.surface,
              ),
            ),
          );
        }

        return AnimatedContainer(
          duration: _isDismissSnapping ? const Duration(milliseconds: 300) : Duration.zero,
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, _dismissTranslateOffset, 0),
          onEnd: () {
            if (mounted && _isDismissSnapping && _dismissTranslateOffset == 0) {
              setState(() => _isDismissSnapping = false);
            }
          },
          child: Scaffold(
            backgroundColor: backgroundColor,
            body: Container(
              // Solid gradient background - NO ALPHA/TRANSLUCENCY
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [colors.backgroundPrimary, colors.backgroundSecondary],
                  stops: const [0.0, 1.0],
                ),
              ),
              child: YTMDrawer(
                key: _drawerKey,
                backgroundColor: Colors.transparent,
                surfaceColor: colors.surface,
                surfaceDecoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      colors.backgroundPrimary,
                      colors.backgroundSecondary,
                    ],
                    stops: const [0.0, 1.0],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
                initiallyExpanded: _isDrawerExpanded,
                enableDrag: !_isScrubberSeeking,
                onDismissDragUpdate: (offset) {
                  if (mounted) {
                    setState(() {
                      _dismissTranslateOffset = offset;
                      _isDismissSnapping = false;
                    });
                  }
                },
                onDismissDragEnd: (dismissed) {
                  if (mounted && !dismissed) {
                    setState(() {
                      _dismissTranslateOffset = 0.0;
                      _isDismissSnapping = true;
                    });
                  }
                },
                onDismiss: () {
                  Navigator.of(context).pop();
                  widget.onClose?.call();
                },
              onStateChanged: (expanded) {
                setState(() {
                  _isDrawerExpanded = expanded;
                  _showQueue = expanded && _tabController.index == 0;
                  _showLyrics = expanded && _tabController.index == 1;
                });
                if (expanded && _tabController.index == 0) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _scrollToActiveTrack(animate: true);
                  });
                } else if (!expanded) {
                  // Sheet collapsed: guarantee album art PageView is centered on the active track
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted || !_albumArtPageController.hasClients) return;
                    final currentQueueIndex =
                        ref.read(audioPlayerServiceProvider).currentIndex;
                    if (currentQueueIndex >= 0) {
                      final activePage = _safeAlbumArtPage(-1.0).round();
                      if (activePage != currentQueueIndex) {
                        _albumArtPageController.jumpToPage(currentQueueIndex);
                      }
                    }
                  });
                }
              },
              // Position-based tab selection (left=UP NEXT, center=LYRICS, right=RELATED)
              onTabFromPosition: (tabIndex) {
                setState(() {
                  _tabController.animateTo(tabIndex);
                  _showQueue = tabIndex == 0;
                  _showLyrics = tabIndex == 1;
                });
                if (tabIndex == 0) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _scrollToActiveTrack(animate: true);
                  });
                }
                if (_pageController.hasClients) {
                  _pageController.jumpToPage(tabIndex);
                }
              },
              // Now Playing content (shown when collapsed)
              nowPlayingContent: nowPlayingStyle == NowPlayingStyle.edge
                  ? RepaintBoundary(
                      child: EdgeNowPlayingView(
                        track: track,
                        state: state,
                        playerService: playerService,
                        textColor: textColor,
                        secondaryTextColor: secondaryTextColor,
                        accentColor: accentColor,
                        backgroundColor: colors.backgroundPrimary,
                        isLiked: ref.watch(isTrackLikedProvider(track.id)),
                        onToggleLike: () => _toggleLikeTrack(track),
                        onDoubleTapLike: () => _triggerDoubleTapLike(track),
                        heartOverlay: _buildHeartOverlay(),
                        onDismiss: () {
                          Navigator.of(context).pop();
                          widget.onClose?.call();
                        },
                        onOpenOptions: () {
                          TrackOptionsSheet.show(context, track);
                        },
                        tabsWidget: _buildBottomTabs(textColor, accentColor),
                        albumArt: _buildEdgeSwipeableAlbumArt(
                          track,
                          accentColor,
                        ),
                        ambientArt: AnimatedAlbumArtView(
                          key: ValueKey('ambient_art_${track.id}'),
                          track: track,
                          staticArt: _buildStaticAlbumArtContent(track, accentColor),
                          borderRadius: BorderRadius.zero,
                          onCanvasLoaded: (hasCanvas) {
                            if (mounted && _hasAnimatedCanvas != hasCanvas) {
                              setState(() => _hasAnimatedCanvas = hasCanvas);
                            }
                          },
                        ),
                        forceFallbackGradient: ref.watch(cinematicAmbientOnlyForAnimatedArtProvider) && !_hasAnimatedCanvas,
                        lyricPreview: _buildSyncedLyricPreview(
                          textColor,
                          accentColor,
                          isCentered: true,
                        ),
                        progressBar: _NowPlayingProgressBar(
                          duration: state.duration,
                          textColor: textColor,
                          secondaryColor: secondaryTextColor,
                          accentColor: accentColor,
                          isLive: state.isLive,
                          horizontalPadding: 24.0,
                          verticalPadding: 0.0,
                        ),
                        controlsWidget: _buildControls(
                          state,
                          playerService,
                          textColor,
                          accentColor,
                          horizontalPadding: 24.0,
                        ),
                      ),
                    )
                  : SafeArea(
                      top: true,
                      bottom: false,
                      child: RepaintBoundary(
                        child: nowPlayingStyle == NowPlayingStyle.ripple
                            ? RippleNowPlayingView(
                                track: track,
                                state: state,
                                playerService: playerService,
                                textColor: textColor,
                                secondaryTextColor: secondaryTextColor,
                                accentColor: accentColor,
                                isLiked: ref.watch(isTrackLikedProvider(track.id)),
                                onToggleLike: () => _toggleLikeTrack(track),
                                onDoubleTapLike: () => _triggerDoubleTapLike(track),
                                heartOverlay: _buildHeartOverlay(),
                                onSeekingChanged: (seeking) {
                                  if (_isScrubberSeeking != seeking) {
                                    setState(() => _isScrubberSeeking = seeking);
                                  }
                                },
                                onDismiss: () {
                                  Navigator.of(context).pop();
                                  widget.onClose?.call();
                                },
                                onOpenOptions: () {
                                  TrackOptionsSheet.show(context, track);
                                },
                                tabsWidget: _buildBottomTabs(textColor, accentColor),
                                albumArt: _buildRippleSwipeableAlbumArt(
                                  track,
                                  accentColor,
                                ),
                                lyricPreview: _buildSyncedLyricPreview(
                                  textColor,
                                  accentColor,
                                  isCentered: true,
                                ),
                              )
                            : _buildFullAlbumView(
                                track,
                                state,
                                playerService,
                                textColor,
                                secondaryTextColor,
                                accentColor,
                                isOg: nowPlayingStyle == NowPlayingStyle.og,
                              ),
                      ),
                    ),
              // Up Next header (mini player style)
              expandedHeader: _buildMiniPlayerHeader(
                track,
                state,
                playerService,
                textColor,
                accentColor,
              ),
              // Tabs bar - persists between header and content
              tabsWidget: _buildBottomTabs(textColor, accentColor),
              // Tab content - switches based on selected tab
              upNextContent: RepaintBoundary(
                child: _buildTabContent(
                  textColor,
                  secondaryTextColor,
                  colors.surface,
                ),
              ),
            ),
          ),
        ),
        );
      },
      loading: () => Scaffold(
        backgroundColor: isDark ? Colors.black : Theme.of(context).colorScheme.surface,
        body: SafeArea(
          child: Skeletonizer(
            enabled: true,
            enableSwitchAnimation: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  const Spacer(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(BoneMock.name),
                    subtitle: Text(BoneMock.words(2)),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: const [
                      Icon(Icons.skip_previous, size: 36),
                      Icon(Icons.play_circle_fill, size: 64),
                      Icon(Icons.skip_next, size: 36),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  /// Full album art view - default when no tab is selected
  Widget _buildFullAlbumView(
    Track track,
    player.PlaybackState state,
    player.AudioPlayerService playerService,
    Color textColor,
    Color secondaryTextColor,
    Color accentColor, {
    bool isOg = false,
  }) {
    return Column(
      children: [
        // Top bar
        _buildTopBar(
          textColor,
          secondaryTextColor,
          showJamIndicator: !isOg,
        ),

        // Album art
        _buildAlbumArt(track, accentColor),

        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        // Current synced lyric line (shown only when synced lyrics are available)
                        _buildSyncedLyricPreview(
                          textColor,
                          accentColor,
                          isCentered: !isOg,
                        ),

                        // Track info
                        _buildTrackInfo(
                          track,
                          textColor,
                          secondaryTextColor,
                          accentColor,
                          isOg: isOg,
                        ),

                        // Progress bar
                        _NowPlayingProgressBar(
                          duration: state.duration,
                          textColor: textColor,
                          secondaryColor: secondaryTextColor,
                          accentColor: accentColor,
                          isLive: state.isLive,
                        ),

                        // Controls
                        _buildControls(state, playerService, textColor, accentColor),

                        const Spacer(),

                        // Bottom tabs
                        _buildBottomTabs(textColor, accentColor),

                        SizedBox(height: MediaQuery.of(context).padding.bottom),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Stage View (Landscape Mode): Album Art & Controls on left, Live Lyrics / Queue on right
  Widget _buildStageView(
    Track track,
    player.PlaybackState state,
    player.AudioPlayerService playerService,
    Color textColor,
    Color secondaryTextColor,
    Color accentColor,
    Color surfaceColor,
  ) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Left Panel: Album Art, Track Info, Progress & Controls (30% width)
            RepaintBoundary(
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.30,
                child: Column(
                  children: [
                    // Prominent Large Swipeable Album Art
                    Expanded(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(2.0),
                          child: AspectRatio(
                            aspectRatio: 1.0,
                            child: _buildSwipeableAlbumArt(track, accentColor),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 4),

                    // Minimal Track Title & Artist
                    _buildMinimalTrackInfo(track, textColor, secondaryTextColor),

                    // Compact Progress Bar & Duration
                    _NowPlayingProgressBar(
                      duration: state.duration,
                      textColor: textColor,
                      secondaryColor: secondaryTextColor,
                      accentColor: accentColor,
                      isCompact: true,
                      isLive: state.isLive,
                    ),

                    // Minimal Controls (Previous, Play/Pause, Next)
                    _buildMinimalControls(
                      state,
                      playerService,
                      textColor,
                      accentColor,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 16),

            // Right Panel: Borderless Swipeable PageView (Up Next / Lyrics [default] / Related)
            Expanded(
              child: RepaintBoundary(
                child: Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    PageView(
                      controller: _stageViewPageController,
                      physics: const BouncingScrollPhysics(),
                      onPageChanged: (index) {
                        if (_tabController.index != index) {
                          _tabController.animateTo(index);
                        }
                        setState(() {
                          _showQueue = index == 0;
                          _showLyrics = index == 1;
                        });
                        if (_pageController.hasClients &&
                            _pageController.page?.round() != index) {
                          _pageController.jumpToPage(index);
                        }
                      },
                      children: [
                        _buildQueueContent(
                          textColor,
                          secondaryTextColor,
                          surfaceColor,
                        ),
                        _buildLyricsView(),
                        _buildRelatedContent(textColor, secondaryTextColor),
                      ],
                    ),

                  // Ultra-minimal floating page indicator dots (Up Next • Lyrics • Related)
                  Positioned(
                    top: 4,
                    child: AnimatedBuilder(
                      animation: _stageViewPageController,
                      builder: (context, child) {
                        final page = _stageViewPageController.hasClients
                            ? (_stageViewPageController.page ?? 1.0)
                            : 1.0;

                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(3, (index) {
                            final delta = (index - page).abs().clamp(0.0, 1.0);
                            final opacity =
                                (1.0 - (delta * 0.65)).clamp(0.25, 1.0);
                            final width = 18.0 - (delta * 12.0);

                            return Container(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 3,
                              ),
                              width: width,
                              height: 4,
                              decoration: BoxDecoration(
                                color: (index == page.round()
                                        ? accentColor
                                        : textColor)
                                    .withValues(alpha: opacity),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            );
                          }),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildMinimalTrackInfo(
    Track track,
    Color textColor,
    Color secondaryColor,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Title with Marquee auto-scrolling on overflow
        SizedBox(
          height: 20,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final textPainter = TextPainter(
                text: TextSpan(
                  text: track.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                maxLines: 1,
                textDirection: TextDirection.ltr,
              )..layout();

              if (textPainter.width > (constraints.maxWidth - 2)) {
                return Marquee(
                  text: track.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                  scrollAxis: Axis.horizontal,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  blankSpace: 48.0,
                  velocity: 30.0,
                  pauseAfterRound: const Duration(seconds: 2),
                  startPadding: 0.0,
                  accelerationDuration: const Duration(seconds: 1),
                  accelerationCurve: Curves.linear,
                  decelerationDuration: const Duration(milliseconds: 500),
                  decelerationCurve: Curves.easeOut,
                );
              }

              return Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 2),

        // Artist with Marquee auto-scrolling on overflow
        SizedBox(
          height: 18,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final textPainter = TextPainter(
                text: TextSpan(
                  text: track.artist,
                  style: TextStyle(
                    fontSize: 12,
                    color: secondaryColor,
                  ),
                ),
                maxLines: 1,
                textDirection: TextDirection.ltr,
              )..layout();

              if (textPainter.width > (constraints.maxWidth - 2)) {
                return Marquee(
                  text: track.artist,
                  style: TextStyle(
                    fontSize: 12,
                    color: secondaryColor,
                  ),
                  scrollAxis: Axis.horizontal,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  blankSpace: 48.0,
                  velocity: 30.0,
                  pauseAfterRound: const Duration(seconds: 2),
                  startPadding: 0.0,
                  accelerationDuration: const Duration(seconds: 1),
                  accelerationCurve: Curves.linear,
                  decelerationDuration: const Duration(milliseconds: 500),
                  decelerationCurve: Curves.easeOut,
                );
              }

              return InkWell(
                onTap: () {
                  if (track.isPodcast || (track.podcastId != null && track.podcastId!.isNotEmpty)) {
                    PodcastScreen.open(
                      context,
                      podcastId: track.podcastId!,
                      title: track.album ?? track.artist,
                      thumbnailUrl: track.thumbnailUrl,
                    );
                  } else if (track.artistId.isNotEmpty) {
                    ArtistScreen.open(
                      context,
                      artistId: track.artistId,
                      name: track.artist,
                    );
                  }
                },
                child: Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: secondaryColor,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMinimalControls(
    player.PlaybackState state,
    player.AudioPlayerService playerService,
    Color textColor,
    Color accentColor,
  ) {
    final isInJam = ref.watch(isInJamSessionProvider);
    final canControl = ref.watch(canControlJamPlaybackProvider);
    final canSkip = !isInJam || canControl;

    final isLiquidGlass = ref.watch(liquidGlassNavProvider);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Previous
        BouncyTouch(
          style: BouncyStyle.button,
          customScale: 0.90,
          onTap: canSkip ? playerService.skipToPrevious : null,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(
              Iconsax.previous,
              color: canSkip ? textColor : textColor.withValues(alpha: 0.3),
              size: 28,
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Play/Pause
        AnimatedPlayPauseButton(
          isPlaying: state.isPlaying,
          onTap: state.isPlaying ? playerService.pause : playerService.play,
          size: 48,
          iconSize: 28,
          backgroundColor: accentColor,
          isLiquidGlass: isLiquidGlass,
        ),
        const SizedBox(width: 16),
        // Next
        BouncyTouch(
          style: BouncyStyle.button,
          customScale: 0.90,
          onTap: canSkip ? playerService.skipToNext : null,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(
              Iconsax.next,
              color: canSkip ? textColor : textColor.withValues(alpha: 0.3),
              size: 28,
            ),
          ),
        ),
      ],
    );
  }

  /// Mini player header for compact view
  Widget _buildMiniPlayerHeader(
    Track track,
    player.PlaybackState state,
    player.AudioPlayerService playerService,
    Color textColor,
    Color accentColor,
  ) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // Album art thumbnail
          TrackArtworkView(
            track: track,
            width: 56,
            height: 56,
            borderRadius: BorderRadius.circular(8),
            fallbackColor: accentColor.withValues(alpha: 0.3),
            fallbackIcon: Iconsax.music,
          ),
          const SizedBox(width: 12),
          // Title and artist
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 22,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final textPainter = TextPainter(
                        text: TextSpan(
                          text: track.title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        maxLines: 1,
                        textDirection: TextDirection.ltr,
                      )..layout();

                      if (textPainter.width > (constraints.maxWidth - 2)) {
                        return Marquee(
                          text: track.title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                          scrollAxis: Axis.horizontal,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          blankSpace: 48.0,
                          velocity: 30.0,
                          pauseAfterRound: const Duration(seconds: 2),
                          startPadding: 0.0,
                          accelerationDuration: const Duration(seconds: 1),
                          accelerationCurve: Curves.linear,
                          decelerationDuration:
                              const Duration(milliseconds: 500),
                          decelerationCurve: Curves.easeOut,
                        );
                      }

                      return Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  height: 18,
                  child: _buildArtistLink(
                    track,
                    style: TextStyle(
                      fontSize: 13,
                      color: textColor.withValues(alpha: 0.7),
                    ),
                    maxLines: 1,
                    enableMarquee: true,
                  ),
                ),
              ],
            ),
          ),
          // Play/pause button
          AnimatedPlayPauseButton(
            isPlaying: state.isPlaying,
            onTap: state.isPlaying ? playerService.pause : playerService.play,
            size: 40,
            iconSize: 24,
            backgroundColor: accentColor,
            isLiquidGlass: ref.watch(liquidGlassNavProvider),
          ),
        ],
      ),
    );
  }

  /// Queue content for UP NEXT tab
  Widget _buildQueueContent(
    Color textColor,
    Color secondaryColor,
    Color surfaceColor,
  ) {
    final l10n = context.l10n;
    final queue = ref.watch(queueProvider);
    final currentTrack = ref.watch(currentTrackProvider);
    final isRadioMode = ref.watch(isRadioModeProvider);
    final isFetchingRadio = ref.watch(isFetchingRadioProvider);
    final isInJam = ref.watch(isInJamSessionProvider);
    final jamQueue = ref.watch(jamQueueProvider);
    final isHost = ref.watch(isJamHostProvider);
    final canControlPlayback = ref.watch(canControlJamPlaybackProvider);
    final session = ref.watch(currentJamSessionProvider).valueOrNull;

    // Determine queue label
    String queueLabel;
    IconData? queueIcon;
    if (isInJam) {
      queueLabel = l10n.jamQueue;
      queueIcon = Iconsax.profile_2user;
    } else if (isRadioMode) {
      queueLabel = l10n.radioQueue;
      queueIcon = Icons.all_inclusive;
    } else {
      queueLabel = l10n.queueLabel;
      queueIcon = null;
    }

    // When in jam, show jam queue instead of personal queue
    if (isInJam) {
      return _buildJamQueueContent(
        textColor,
        secondaryColor,
        surfaceColor,
        queueLabel,
        queueIcon,
        jamQueue,
        session,
        isHost,
        canControlPlayback,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with "Playing from" info
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.playingFrom,
                    style: TextStyle(fontSize: 12, color: secondaryColor),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        queueLabel,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      if (queueIcon != null) ...[
                        const SizedBox(width: 6),
                        Icon(queueIcon, size: 16, color: secondaryColor),
                      ],
                    ],
                  ),
                ],
              ),
              // Save button (hide when in jam - jam queue is managed separately)
              if (!isInJam)
                TextButton.icon(
                  onPressed: () =>
                      _showSaveQueueDialog(context, queue, textColor),
                  icon: Icon(
                    Iconsax.music_playlist,
                    size: 18,
                    color: textColor,
                  ),
                  label: Text(l10n.save, style: TextStyle(color: textColor)),
                ),
            ],
          ),
        ),

        // Queue list - ReorderableListView with optimizations
        // Wrap with NotificationListener to detect scroll for infinite radio
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              // Read current state at notification time, not captured build time values
              final currentIsRadioMode = ref.read(isRadioModeProvider);
              final currentIsFetching = ref.read(isFetchingRadioProvider);

              // Check if near bottom and radio mode is on
              if (currentIsRadioMode && !currentIsFetching) {
                final metrics = notification.metrics;
                final remaining = metrics.maxScrollExtent - metrics.pixels;
                // Fetch more when within 500 pixels of bottom
                if (remaining < 500 && metrics.maxScrollExtent > 0) {
                  // Trigger radio fetch
                  ref.read(audioPlayerServiceProvider).fetchMoreRadioTracks();
                }
              }
              return false; // Don't consume the notification
            },
            child: Builder(
              builder: (context) {
                if (!_hasInitialQueueScrolled) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _queueScrollController.hasClients) {
                      _scrollToActiveTrack(animate: false);
                      _hasInitialQueueScrolled = true;
                    }
                  });
                }
                return ReorderableListView.builder(
                  scrollController: _queueScrollController,
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              // Add extra item at end for loading indicator when in radio mode
              itemCount: queue.length + (isRadioMode ? 1 : 0),
              // Add prototypeItem for consistent sizing (improves scroll performance)
              proxyDecorator: (child, index, animation) {
                return Material(
                  elevation: 4,
                  color: Colors.transparent,
                  child: child,
                );
              },
              onReorderItem: (oldIndex, newIndex) {
                // Don't allow reordering the loading indicator
                if (oldIndex >= queue.length || newIndex >= queue.length) return;
                ref
                    .read(audioPlayerServiceProvider)
                    .reorderQueue(oldIndex, newIndex);
              },
              itemBuilder: (context, index) {
                // Loading indicator at the end for radio mode
                if (index >= queue.length) {
                  return Container(
                    key: const ValueKey('radio_loading'),
                    height: 72,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: isFetchingRadio
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: secondaryColor,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  l10n.loadingMoreTracks,
                                  style: TextStyle(
                                    color: secondaryColor,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.all_inclusive,
                                  size: 18,
                                  color: secondaryColor,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  l10n.scrollForMore,
                                  style: TextStyle(
                                    color: secondaryColor,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  );
                }

                final track = queue[index];
                final isCurrent = currentTrack?.id == track.id;

                return _buildQueueItemTile(
                  key: ValueKey(track.id + index.toString()),
                  track: track,
                  isCurrent: isCurrent,
                  index: index,
                  textColor: textColor,
                  secondaryColor: secondaryColor,
                  accentColor: ref.watch(albumColorsProvider).accent,
                  onTap: () {
                    ref
                        .read(audioPlayerServiceProvider)
                        .playQueue(queue, startIndex: index);
                  },
                  trailingWidget: ReorderableDragStartListener(
                    index: index,
                    child: Icon(Icons.drag_handle, color: secondaryColor),
                  ),
                );
              },
            );
          },
        ),
      ),
    ),
      ],
    );
  }

  /// Jam queue content - shows jam queue with who added each track
  Widget _buildJamQueueContent(
    Color textColor,
    Color secondaryColor,
    Color surfaceColor,
    String queueLabel,
    IconData? queueIcon,
    List<JamQueueItem> jamQueue,
    JamSession? session,
    bool isHost,
    bool canControlPlayback,
  ) {
    final l10n = context.l10n;
    final currentTrack = ref.watch(currentTrackProvider);
    // Find participant names from session
    String getAddedByName(String oderId) {
      final participant = session?.participants
          .where((p) => p.id == oderId)
          .firstOrNull;
      return participant?.name ?? l10n.someone;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with "Playing from" info
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.playingFrom,
                    style: TextStyle(fontSize: 12, color: secondaryColor),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        queueLabel,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      if (queueIcon != null) ...[
                        const SizedBox(width: 6),
                        Icon(queueIcon, size: 16, color: secondaryColor),
                      ],
                    ],
                  ),
                ],
              ),
              // Show track count
              Text(
                l10n.tracksCount(jamQueue.length),
                style: TextStyle(color: secondaryColor, fontSize: 12),
              ),
            ],
          ),
        ),

        // Jam queue list
        Expanded(
          child: jamQueue.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Iconsax.music, size: 48, color: secondaryColor),
                      const SizedBox(height: 16),
                      Text(
                        l10n.noTracksInQueue,
                        style: TextStyle(color: secondaryColor),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.addSongsToJamQueue,
                        style: TextStyle(color: secondaryColor, fontSize: 12),
                      ),
                    ],
                  ),
                )
              : ReorderableListView.builder(
                  scrollController: _queueScrollController,
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: jamQueue.length,
                  onReorderItem: canControlPlayback
                      ? (oldIndex, newIndex) =>
                            _reorderJamQueue(oldIndex, newIndex)
                      : (_, _) {},
                  buildDefaultDragHandles: false,
                  itemBuilder: (context, index) {
                    final queueItem = jamQueue[index];
                    final jamTrack = queueItem.track;
                    final isCurrent = currentTrack?.id == jamTrack.videoId;
                    final track = Track(
                      id: jamTrack.videoId,
                      title: jamTrack.title,
                      artist: jamTrack.artist,
                      thumbnailUrl: jamTrack.thumbnailUrl,
                      duration: Duration(milliseconds: jamTrack.durationMs),
                    );
                    final addedByName = getAddedByName(queueItem.addedBy);

                    return _buildQueueItemTile(
                      key: ValueKey('jam_${track.id}_$index'),
                      track: track,
                      isCurrent: isCurrent,
                      index: index,
                      textColor: textColor,
                      secondaryColor: secondaryColor,
                      accentColor: ref.watch(albumColorsProvider).accent,
                      onTap: canControlPlayback
                          ? () => _playFromJamQueue(index)
                          : null,
                      subtitleWidget: Text(
                        context.metadataLine([
                          track.artist,
                          l10n.addedByUser(addedByName),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCurrent
                              ? ref
                                  .watch(albumColorsProvider)
                                  .accent
                                  .withValues(alpha: 0.85)
                              : secondaryColor,
                          fontSize: 12,
                        ),
                      ),
                      trailingWidget: canControlPlayback
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    Iconsax.trash,
                                    size: 20,
                                    color: secondaryColor,
                                  ),
                                  onPressed: () =>
                                      _removeFromJamQueue(index),
                                ),
                                ReorderableDragStartListener(
                                  index: index,
                                  child: Icon(
                                    Icons.drag_handle,
                                    color: secondaryColor,
                                  ),
                                ),
                              ],
                            )
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Remove a track from the jam queue by index
  void _removeFromJamQueue(int index) async {
    final jamsService = ref.read(jamsServiceProvider);
    if (jamsService != null) {
      await jamsService.removeFromQueue(index);
    }
  }

  /// Play from a specific position in the jam queue
  void _playFromJamQueue(int index) async {
    final jamsService = ref.read(jamsServiceProvider);
    if (jamsService == null) return;

    final jamQueue = ref.read(jamQueueProvider);
    if (index >= jamQueue.length) return;

    // Get the track at this index and remove all items up to and including it
    final queueItem = await jamsService.playFromQueueAt(index);
    if (queueItem == null) return;

    // Convert to Track and play
    final track = Track(
      id: queueItem.track.videoId,
      title: queueItem.track.title,
      artist: queueItem.track.artist,
      thumbnailUrl: queueItem.track.thumbnailUrl,
      duration: Duration(milliseconds: queueItem.track.durationMs),
    );

    // Play the track (host's sync will update participants)
    ref.read(audioPlayerServiceProvider).playTrack(track);
  }

  /// Reorder tracks in the jam queue
  void _reorderJamQueue(int oldIndex, int newIndex) async {
    final jamsService = ref.read(jamsServiceProvider);
    if (jamsService != null) {
      await jamsService.reorderQueue(oldIndex, newIndex);
    }
  }

  Widget _buildQueueItemTile({
    required Key key,
    required Track track,
    required bool isCurrent,
    required int index,
    required Color textColor,
    required Color secondaryColor,
    required Color accentColor,
    required VoidCallback? onTap,
    Widget? subtitleWidget,
    Widget? trailingWidget,
  }) {
    final playbackState = ref.watch(playbackStateProvider).valueOrNull;
    final isPlaying = isCurrent && (playbackState?.isPlaying ?? false);

    return RepaintBoundary(
      key: key,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.transparent,
            border: isCurrent
                ? Border.all(
                    color: accentColor.withValues(alpha: 0.50),
                    width: 1.0,
                  )
                : null,
          ),
          child: BouncyTouch(
            style: BouncyStyle.card,
            customScale: 0.98,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  // Thumbnail with optional Playing Equalizer overlay
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      TrackArtworkView(
                        track: track,
                        width: 48,
                        height: 48,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      if (isCurrent)
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.black.withValues(alpha: 0.45),
                          ),
                          child: Center(
                            child: isPlaying
                                ? _QueuePlayingEqualizerBars(color: accentColor)
                                : Icon(
                                    Icons.play_arrow_rounded,
                                    color: accentColor,
                                    size: 24,
                                  ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),

                  // Track Info (Title & Subtitle)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            if (track.isExplicit)
                              ExplicitBadge(
                                color: isCurrent ? accentColor : textColor,
                              ),
                            Expanded(
                              child: Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isCurrent ? accentColor : textColor,
                                  fontWeight: isCurrent
                                      ? FontWeight.bold
                                      : FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        subtitleWidget ??
                            Builder(
                              builder: (context) {
                                final state =
                                    ref.watch(playbackStateProvider).valueOrNull;
                                final playerDuration =
                                    isCurrent ? state?.duration : null;
                                final formattedDur = (track.duration.inSeconds > 0)
                                    ? track.formattedDuration
                                    : (playerDuration != null &&
                                            playerDuration.inSeconds > 0
                                        ? _formatDuration(playerDuration)
                                        : null);

                                return Text(
                                  context.trackSubtitle(
                                    track.artist,
                                    formattedDur,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isCurrent
                                        ? accentColor.withValues(alpha: 0.85)
                                        : secondaryColor,
                                    fontSize: 12,
                                  ),
                                );
                              },
                            ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Trailing widget (e.g. drag handle or trash button)
                  if (trailingWidget != null) trailingWidget,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Tab content with horizontal swipeable PageView (Up Next / Lyrics / Related)
  Widget _buildTabContent(
    Color textColor,
    Color secondaryColor,
    Color surfaceColor,
  ) {
    return PageView(
      controller: _pageController,
      physics: const BouncingScrollPhysics(),
      onPageChanged: (index) {
        if (_tabController.index != index) {
          _tabController.animateTo(index);
          setState(() {
            _showQueue = index == 0;
            _showLyrics = index == 1;
          });
        }
      },
      children: [
        _buildQueueContent(textColor, secondaryColor, surfaceColor),
        _buildLyricsView(),
        _buildRelatedContent(textColor, secondaryColor),
      ],
    );
  }

  /// Related content placeholder
  Widget _buildRelatedContent(Color textColor, Color secondaryColor) {
    final l10n = context.l10n;
    final currentTrack = ref.watch(currentTrackProvider);
    if (currentTrack == null) {
      return Center(
        child: Text(
          l10n.noTrackPlaying,
          style: TextStyle(color: secondaryColor),
        ),
      );
    }

    // Cache the future to prevent re-fetching on every rebuild
    if (_lastRelatedTrackId != currentTrack.id) {
      _lastRelatedTrackId = currentTrack.id;
      _relatedContentFuture = _loadRelatedContent(currentTrack);
    }

    return FutureBuilder<WatchRelatedContent>(
      future: _relatedContentFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Skeletonizer(
            enabled: true,
            enableSwitchAnimation: true,
            child: ListView(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  child: Text(
                    BoneMock.words(2),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                ),
                ...List.generate(
                  4,
                  (index) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: Skeleton.replace(
                      width: 48,
                      height: 48,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                    title: Text(BoneMock.name),
                    subtitle: Text(BoneMock.words(2)),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  child: Text(
                    BoneMock.words(3),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                ),
                SizedBox(
                  height: 236,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 3,
                    separatorBuilder: (_, _) => const SizedBox(width: 14),
                    itemBuilder:
                        (context, index) => SizedBox(
                          width: 140,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Skeleton.replace(
                                width: 140,
                                height: 140,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.grey,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(BoneMock.name),
                              Text(BoneMock.words(2)),
                            ],
                          ),
                        ),
                  ),
                ),
              ],
            ),
          );
        }

        if (snapshot.hasError ||
            !snapshot.hasData ||
            snapshot.data == null ||
            snapshot.data!.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Iconsax.music_filter, size: 48, color: secondaryColor),
                const SizedBox(height: 12),
                Text(
                  l10n.noRelatedTracksFound,
                  style: TextStyle(color: secondaryColor),
                ),
              ],
            ),
          );
        }

        final relatedContent = snapshot.data!;

        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
          children: [
            for (final shelf in relatedContent.shelves)
              _buildRelatedShelfSection(shelf, textColor, secondaryColor),
            if (relatedContent.hasAboutSection)
              _buildAboutArtistSection(
                relatedContent,
                textColor,
                secondaryColor,
              ),
          ],
        );
      },
    );
  }

  Future<WatchRelatedContent> _loadRelatedContent(Track currentTrack) async {
    final innerTube = ref.read(innerTubeServiceProvider);
    final relatedTabTitle = context.l10n.relatedTab;

    final relatedContent = await innerTube.getWatchRelatedContent(
      currentTrack.id,
      limitPerShelf: 12,
    );
    if (!relatedContent.isEmpty) {
      return relatedContent;
    }

    final fallbackTracks = await innerTube.getWatchPlaylist(
      currentTrack.id,
      limit: 20,
    );
    final filteredFallback = fallbackTracks
        .where((track) => track.id != currentTrack.id)
        .take(20)
        .toList();
    if (filteredFallback.isNotEmpty) {
      return WatchRelatedContent(
        shelves: [
          HomeShelf(
            id: 'related_fallback_${currentTrack.id}',
            title: relatedTabTitle,
            type: HomeShelfType.unknown,
            items: filteredFallback.map(_trackToShelfItem).toList(),
          ),
        ],
      );
    }

    // Final fallback: search for similar tracks via InnerTube
    try {
      final searchQuery = '${currentTrack.artist} ${currentTrack.title}';
      final searchResults = await innerTube.search(searchQuery);
      final genericTracks = searchResults.tracks
          .where((track) => track.id != currentTrack.id)
          .take(20)
          .toList();

      if (genericTracks.isNotEmpty) {
        return WatchRelatedContent(
          shelves: [
            HomeShelf(
              id: 'related_generic_${currentTrack.id}',
              title: relatedTabTitle,
              type: HomeShelfType.unknown,
              items: genericTracks.map(_trackToShelfItem).toList(),
            ),
          ],
        );
      }
    } catch (_) {
      // Search fallback failed, return empty
    }

    return WatchRelatedContent.empty;
  }

  HomeShelfItem _trackToShelfItem(Track track) {
    return HomeShelfItem(
      id: track.id,
      title: track.title,
      subtitle: track.artist,
      thumbnailUrl: track.thumbnailUrl,
      navigationId: track.id,
      itemType: HomeShelfItemType.song,
      videoId: track.id,
      artistId: track.artistId.isNotEmpty ? track.artistId : null,
    );
  }

  Widget _buildRelatedShelfSection(
    HomeShelf shelf,
    Color textColor,
    Color secondaryColor,
  ) {
    if (_usesHomeQuickPicksLayout(shelf)) {
      final theme = Theme.of(context);
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: TrackListShelf(
          shelf: shelf,
          isDark: theme.brightness == Brightness.dark,
          colorScheme: theme.colorScheme,
          showPlayButton: false,
          headerHorizontalPadding: 8,
          listHorizontalPadding: 4,
          enableDynamicColors: false,
          showCurrentTrackHighlight: false,
        ),
      );
    }

    final primaryType = _primaryRelatedItemType(shelf);
    final title = _relatedShelfTitle(shelf);
    final titlePrefix = _relatedShelfTitlePrefix(shelf);
    final titleMain = _relatedShelfTitleMain(shelf);
    final showTitle = !_isRedundantRelatedTitle(title);

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showTitle)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: titlePrefix == null
                  ? Text(
                      title,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if ((shelf.headerThumbnailUrl ?? '').isNotEmpty) ...[
                          ClipOval(
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: CachedNetworkImage(
                                imageUrl: shelf.headerThumbnailUrl!,
                                fit: BoxFit.cover,
                                memCacheWidth: 88,
                                memCacheHeight: 88,
                                fadeInDuration: Duration.zero,
                                fadeOutDuration: Duration.zero,
                                errorWidget: (_, _, _) =>
                                    Container(color: Colors.grey.shade800),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                titlePrefix,
                                style: TextStyle(
                                  color: secondaryColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                titleMain,
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          if (primaryType == HomeShelfItemType.song)
            ..._buildRelatedTrackTiles(shelf, textColor, secondaryColor)
          else
            SizedBox(
              height: primaryType == HomeShelfItemType.artist ? 200 : 236,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: shelf.items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final item = shelf.items[index];
                  if (primaryType == HomeShelfItemType.artist) {
                    return _buildRelatedArtistCard(
                      shelf,
                      item,
                      textColor,
                      secondaryColor,
                    );
                  }
                  return _buildRelatedMediaCard(
                    shelf,
                    item,
                    textColor,
                    secondaryColor,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildRelatedTrackTiles(
    HomeShelf shelf,
    Color textColor,
    Color secondaryColor,
  ) {
    final tracks = shelf.items
        .map((item) => item.toTrack())
        .whereType<Track>()
        .toList();

    return List<Widget>.generate(shelf.items.length, (index) {
      final item = shelf.items[index];
      final track = index < tracks.length ? tracks[index] : item.toTrack();
      return RepaintBoundary(
        child: Material(
          color: Colors.transparent,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 2,
            ),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 52,
                height: 52,
                child: item.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: item.thumbnailUrl!,
                        fit: BoxFit.cover,
                        memCacheWidth: 104,
                        memCacheHeight: 104,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                      )
                    : Container(color: Colors.grey.shade800),
              ),
            ),
            title: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              item.subtitle ?? track?.artist ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: secondaryColor, fontSize: 12),
            ),
            onTap: () {
              if (track != null) {
                ref
                    .read(audioPlayerServiceProvider)
                    .playTrack(track, enableRadio: false);
              }
            },
          ),
        ),
      );
    });
  }

  Widget _buildRelatedArtistCard(
    HomeShelf shelf,
    HomeShelfItem item,
    Color textColor,
    Color secondaryColor,
  ) {
    return GestureDetector(
      onTap: () => _handleRelatedItemTap(shelf, item),
      child: SizedBox(
        width: 112,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipOval(
              child: SizedBox(
                width: 112,
                height: 112,
                child: item.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: item.thumbnailUrl!,
                        fit: BoxFit.cover,
                      )
                    : Container(color: Colors.grey.shade800),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            if ((item.subtitle ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  item.subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: secondaryColor, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRelatedMediaCard(
    HomeShelf shelf,
    HomeShelfItem item,
    Color textColor,
    Color secondaryColor,
  ) {
    return GestureDetector(
      onTap: () => _handleRelatedItemTap(shelf, item),
      child: SizedBox(
        width: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 140,
                height: 140,
                child: item.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: item.thumbnailUrl!,
                        fit: BoxFit.cover,
                      )
                    : Container(color: Colors.grey.shade800),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            if ((item.subtitle ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  item.subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: secondaryColor, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _cleanArtistDescription(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return text;

    // 1. Remove URLs enclosed in parentheses e.g. (https://...) or (http://...)
    text = text.replaceAll(
      RegExp(r'\s*\(\s*https?:\/\/[^\)]+\)', caseSensitive: false),
      '',
    );

    // 2. Remove standalone URLs
    text = text.replaceAll(
      RegExp(r'https?:\/\/\S+', caseSensitive: false),
      '',
    );

    // 3. Remove Wikipedia & Creative Commons / CCA license boilerplate trailers
    text = text.replaceAll(
      RegExp(
        r'[-–—|•]?\s*(?:From\s+)?Wikipedia(?:\s*\(.*?\))?\s*(?:Under\s+.*)?$',
        caseSensitive: false,
        multiLine: true,
      ),
      '',
    );
    text = text.replaceAll(
      RegExp(
        r'[-–—|•]?\s*Under\s+(?:CCA|CC|Creative\s+Commons|the\s+Creative\s+Commons).*$',
        caseSensitive: false,
        multiLine: true,
      ),
      '',
    );
    text = text.replaceAll(
      RegExp(
        r'[-–—|•]?\s*(?:CC-BY-SA|CC\s+BY-SA|Creative\s+Commons\s+Attribution).*$',
        caseSensitive: false,
        multiLine: true,
      ),
      '',
    );

    // 4. Remove empty brackets/parentheses that might remain
    text = text.replaceAll(RegExp(r'\(\s*\)'), '');
    text = text.replaceAll(RegExp(r'\[\s*\]'), '');

    // 5. Clean up redundant spaces and trailing punctuation
    text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    text = text.trim();

    // Clean any dangling trailing dashes, pipes, or commas
    text = text.replaceAll(RegExp(r'[\s\-–—|•,]+$'), '');

    return text.trim();
  }

  Widget _buildAboutArtistSection(
    WatchRelatedContent relatedContent,
    Color textColor,
    Color secondaryColor,
  ) {
    final rawDesc = relatedContent.aboutDescription ?? '';
    final cleanedDesc = _cleanArtistDescription(rawDesc);
    if (cleanedDesc.isEmpty) return const SizedBox.shrink();

    final bool hadWikipediaSource =
        rawDesc.toLowerCase().contains('wikipedia') ||
        rawDesc.toLowerCase().contains('cc-by-sa') ||
        rawDesc.toLowerCase().contains('creative commons');

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              relatedContent.aboutTitle ?? context.l10n.aboutArtist,
              style: TextStyle(
                color: textColor,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cleanedDesc,
                  style: TextStyle(
                    color: secondaryColor.withValues(alpha: 0.9),
                    fontSize: 14,
                    height: 1.5,
                    letterSpacing: 0.1,
                  ),
                ),
                if (hadWikipediaSource) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Source: Wikipedia',
                    style: TextStyle(
                      color: secondaryColor.withValues(alpha: 0.5),
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  HomeShelfItemType _primaryRelatedItemType(HomeShelf shelf) {
    final counts = <HomeShelfItemType, int>{};
    for (final item in shelf.items) {
      counts.update(item.itemType, (value) => value + 1, ifAbsent: () => 1);
    }

    return counts.entries.isEmpty
        ? HomeShelfItemType.unknown
        : counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  bool _isRedundantRelatedTitle(String title) {
    final normalizedTitle = title.trim().toLowerCase();
    final normalizedRelated = context.l10n.relatedTab.trim().toLowerCase();
    return normalizedTitle.isEmpty || normalizedTitle == normalizedRelated;
  }

  String _relatedShelfTitle(HomeShelf shelf) {
    final baseTitle = shelf.title.trim().isEmpty
        ? context.l10n.relatedTab
        : shelf.title.trim();
    if (_usesArtistHeaderLayout(shelf)) {
      return '${context.l10n.moreFrom} $baseTitle';
    }

    return baseTitle;
  }

  String? _relatedShelfTitlePrefix(HomeShelf shelf) {
    return _usesArtistHeaderLayout(shelf) ? context.l10n.moreFrom : null;
  }

  String _relatedShelfTitleMain(HomeShelf shelf) {
    return shelf.title.trim().isEmpty
        ? context.l10n.relatedTab
        : shelf.title.trim();
  }

  bool _usesHomeQuickPicksLayout(HomeShelf shelf) {
    final primaryType = _primaryRelatedItemType(shelf);
    return primaryType == HomeShelfItemType.song &&
        !_isRedundantRelatedTitle(shelf.title) &&
        !_usesArtistHeaderLayout(shelf);
  }

  bool _usesArtistHeaderLayout(HomeShelf shelf) {
    final strapline = shelf.strapline?.trim();
    return strapline != null &&
        strapline.isNotEmpty &&
        (shelf.headerThumbnailUrl?.trim().isNotEmpty ?? false) &&
        _primaryRelatedItemType(shelf) != HomeShelfItemType.artist;
  }

  void _handleRelatedItemTap(HomeShelf shelf, HomeShelfItem item) {
    switch (item.itemType) {
      case HomeShelfItemType.podcast:
        final podcastId = item.playlistId ?? item.navigationId ?? item.id;
        PodcastScreen.open(
          context,
          podcastId: podcastId,
          title: item.title,
          thumbnailUrl: item.thumbnailUrl,
        );
        break;
      case HomeShelfItemType.playlist:
      case HomeShelfItemType.mix:
        final playlistId = item.playlistId ?? item.navigationId ?? item.id;
        if (playlistId.startsWith('MPSP')) {
          PodcastScreen.open(
            context,
            podcastId: playlistId,
            title: item.title,
            thumbnailUrl: item.thumbnailUrl,
          );
        } else {
          PlaylistScreen.open(
            context,
            playlistId: playlistId,
            title: item.title,
            thumbnailUrl: item.thumbnailUrl,
          );
        }
        break;
      case HomeShelfItemType.album:
        final albumId = item.navigationId ?? item.id;
        AlbumScreen.open(
          context,
          albumId: albumId,
          title: item.title,
          thumbnailUrl: item.thumbnailUrl,
        );
        break;
      case HomeShelfItemType.artist:
        final artistId = item.navigationId ?? item.id;
        ArtistScreen.open(
          context,
          artistId: artistId,
          name: item.title,
          thumbnailUrl: item.thumbnailUrl,
        );
        break;
      default:
        final tracks = shelf.items
            .map((entry) => entry.toTrack())
            .whereType<Track>()
            .toList();
        final index = tracks.indexWhere(
          (track) => track.id == (item.videoId ?? item.id),
        );
        if (tracks.isNotEmpty) {
          ref
              .read(audioPlayerServiceProvider)
              .playQueue(tracks, startIndex: index >= 0 ? index : 0);
        }
    }
  }

  String _formatDuration(Duration? d) {
    if (d == null) return '--:--';
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _showSaveQueueDialog(
    BuildContext context,
    List<Track> queue,
    Color textColor,
  ) {
    final l10n = context.l10n;
    if (queue.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.queueIsEmpty)));
      return;
    }

    final controller = TextEditingController(text: l10n.defaultQueueName);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: backgroundColor,
        title: Text(
          l10n.saveQueueAsPlaylist,
          style: TextStyle(color: textColor),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: textColor),
          decoration: InputDecoration(
            hintText: l10n.playlistName,
            hintStyle: TextStyle(color: textColor.withValues(alpha: 0.5)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              l10n.cancel,
              style: TextStyle(color: textColor.withValues(alpha: 0.7)),
            ),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                // Create local playlist with all queue tracks
                ref.read(localPlaylistsProvider.notifier).createPlaylist(name);
                final playlists = ref.read(localPlaylistsProvider);
                if (playlists.isNotEmpty) {
                  final newPlaylist = playlists.first;
                  // Add all tracks from queue to playlist
                  for (final track in queue) {
                    ref
                        .read(localPlaylistsProvider.notifier)
                        .addTrackToPlaylist(newPlaylist.id, track);
                  }
                }
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      l10n.savedTracksToPlaylist(queue.length, name),
                    ),
                  ),
                );
              }
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(
    Color textColor,
    Color secondaryColor, {
    bool showJamIndicator = true,
  }) {
    final playbackState = ref.watch(playbackStateProvider).valueOrNull;
    final queueTitle = playbackState?.queueTitle;
    final hasQueueTitle = queueTitle != null && queueTitle.trim().isNotEmpty;
    final showNerdStats = playbackState?.showNerdStats ?? false;
    final statsSummary = playbackState?.qualityInfo;
    final hasStats =
        showNerdStats && statsSummary != null && statsSummary.isNotEmpty;

    // Subtext logic:
    // If playing from album/playlist and stats are enabled: alternate between title and stats.
    // If playing from album/playlist and stats are disabled: show album/playlist title.
    // If normal playback and stats are enabled: show stats.
    // Otherwise: no subtext.
    final String? displaySubtext;
    final bool isDisplayingStats;

    if (hasQueueTitle && hasStats) {
      isDisplayingStats = _showStatsInsteadOfTitle;
      displaySubtext =
          _showStatsInsteadOfTitle ? statsSummary : queueTitle.trim();
    } else if (hasQueueTitle) {
      isDisplayingStats = false;
      displaySubtext = queueTitle.trim();
    } else if (hasStats) {
      isDisplayingStats = true;
      displaySubtext = statsSummary;
    } else {
      isDisplayingStats = false;
      displaySubtext = null;
    }

    final hasSubtext = displaySubtext != null && displaySubtext.isNotEmpty;

    final isLiquidGlass = ref.watch(liquidGlassNavProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final albumColors = ref.watch(albumColorsProvider);
    final hasAlbumColors = !albumColors.isDefault;
    final accentColor = hasAlbumColors
        ? albumColors.accent
        : Theme.of(context).colorScheme.primary;

    Widget buildDropletButton({
      required Widget icon,
      required VoidCallback onTap,
    }) {
      if (isLiquidGlass) {
        return LiquidGlassContainer(
          width: 42,
          height: 42,
          borderRadius: 21,
          blurSigma: 2.0,
          refractionScale: 1.08,
          refractionDeflection: 2.8,
          isDark: isDark,
          surfaceColor: Colors.black.withValues(
            alpha: isDark ? 0.38 : 0.22,
          ),
          accentColor: hasAlbumColors
              ? accentColor.withValues(alpha: 0.50)
              : (isDark ? Colors.white24 : Colors.black12),
          padding: EdgeInsets.zero,
          additionalShadows: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.10),
              blurRadius: 10,
              spreadRadius: -1,
              offset: const Offset(0, 3),
            ),
            if (hasAlbumColors)
              BoxShadow(
                color: accentColor.withValues(alpha: isDark ? 0.20 : 0.10),
                blurRadius: 12,
                spreadRadius: -1,
                offset: const Offset(0, 2),
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
                      Colors.white.withValues(alpha: isDark ? 0.18 : 0.25),
                      Colors.transparent,
                      Colors.black.withValues(alpha: isDark ? 0.15 : 0.08),
                    ],
                  ),
                ),
                child: Center(
                  child: icon,
                ),
              ),
            ),
          ),
        );
      }

      return BouncyTouch(
        style: BouncyStyle.button,
        customScale: 0.90,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: icon,
        ),
      );
    }

    final backButton = buildDropletButton(
      icon: Icon(
        Icons.keyboard_arrow_down,
        color: textColor,
        size: isLiquidGlass ? 28 : 32,
      ),
      onTap: () {
        // Use Navigator.pop for Hero animation on close
        Navigator.of(context).pop();
        widget.onClose?.call();
      },
    );

    final moreButton = buildDropletButton(
      icon: Icon(
        Icons.more_vert,
        color: textColor,
        size: isLiquidGlass ? 22 : 24,
      ),
      onTap: () {
        final track = ref.read(currentTrackProvider);
        if (track != null) {
          TrackOptionsSheet.show(context, track);
        }
      },
    );

    final isInJam = ref.watch(isInJamSessionProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          backButton,
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.l10n.nowPlayingHeader,
                  style: TextStyle(
                    fontSize: hasSubtext ? 9.5 : 11,
                    fontWeight: FontWeight.w600,
                    color: secondaryColor.withValues(alpha: 0.65),
                    letterSpacing: 1.4,
                  ),
                ),
                if (hasSubtext) ...[
                  const SizedBox(height: 2),
                  SizedBox(
                    height: 18,
                    width: (isInJam && showJamIndicator) ? 150 : 220,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      transitionBuilder: (child, animation) =>
                          FadeTransition(opacity: animation, child: child),
                      child: KeyedSubtree(
                        key: ValueKey<String>(displaySubtext),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final text = displaySubtext!;
                            final textStyle = TextStyle(
                              fontSize: isDisplayingStats ? 11.5 : 12,
                              fontWeight: FontWeight.w600,
                              color: isDisplayingStats
                                  ? secondaryColor.withValues(alpha: 0.9)
                                  : textColor,
                              letterSpacing: isDisplayingStats ? 0.3 : 0.0,
                            );

                            final textPainter = TextPainter(
                              text: TextSpan(text: text, style: textStyle),
                              maxLines: 1,
                              textDirection: TextDirection.ltr,
                            )..layout();

                            // Subtext marquee animation
                            if (textPainter.width > constraints.maxWidth) {
                              return Marquee(
                                text: text,
                                style: textStyle,
                                scrollAxis: Axis.horizontal,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                blankSpace: 40.0,
                                velocity: 25.0,
                                pauseAfterRound: const Duration(seconds: 2),
                                startPadding: 0.0,
                                accelerationDuration:
                                    const Duration(seconds: 1),
                                accelerationCurve: Curves.linear,
                                decelerationDuration:
                                    const Duration(milliseconds: 500),
                                decelerationCurve: Curves.easeOut,
                              );
                            }

                            return Center(
                              child: Text(
                                text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: textStyle,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isInJam && showJamIndicator) ...[
            JamIndicatorBadge(
              textColor: textColor,
              accentColor: accentColor,
            ),
            const SizedBox(width: 8),
          ],
          moreButton,
        ],
      ),
    );
  }

  void _handleAlbumArtPageChanged(
    int pageIndex,
    player.AudioPlayerService playerService, {
    required int currentIndex,
    required int queueLength,
  }) {
    if (_isAlbumSwipeNavigationInProgress) return;
    // Strictly require physical user drag so layout resizes or orientation changes never skip tracks
    if (!_isUserDraggingAlbumArt) return;
    if (pageIndex < 0 || pageIndex >= queueLength) return;
    if (pageIndex == currentIndex) return;
    playerService.skipToIndex(pageIndex);
  }

  Widget _buildAlbumArt(Track track, Color accentColor) {

    final lyricsState = ref.watch(lyricsProvider);
    final isFetchingLyrics =
        lyricsState.currentStatus.state == LyricsProviderState.fetching ||
        lyricsState.currentStatus.state == LyricsProviderState.idle;
    final hasSyncedLyrics =
        lyricsState.currentLyrics?.hasSyncedLyrics ?? false;

    final showLyricsBelowArt = ref.watch(showLyricsBelowAlbumArtProvider);
    final shouldExpand =
        !showLyricsBelowArt || (!isFetchingLyrics && !hasSyncedLyrics);
    final progressBarStyle = ref.watch(progressBarStyleProvider);
    final isSpectrum = progressBarStyle == ProgressBarStyle.spectrum;

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;

        // Reduce album art size slightly for Spectrum style so the spectrum bar and bottom controls have generous breathing room
        final double maxHeightRatio;
        final double widthMargin;
        if (isSpectrum) {
          maxHeightRatio = shouldExpand ? 0.41 : 0.35;
          widthMargin = shouldExpand ? 64 : 76;
        } else {
          maxHeightRatio = shouldExpand ? 0.47 : 0.40;
          widthMargin = shouldExpand ? 36 : 52;
        }
        final maxHeight = screenHeight * maxHeightRatio;

        // When lyrics are off (shouldExpand), provide generous vertical separation (24px in spectrum)
        // between the bottom of the album art and the track title.
        final double topPadding = shouldExpand ? (isSpectrum ? 8.0 : 6.0) : 12.0;
        final double bottomSpacing = shouldExpand
            ? (isSpectrum ? 24.0 : 18.0)
            : 6.0;

        final double maxArtHeight = maxHeight - topPadding - bottomSpacing;

        // Constrain to max height while staying square
        final artSize = math.min(
          screenWidth - widthMargin,
          maxArtHeight,
        );

        final double containerHeight = topPadding + artSize + bottomSpacing;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          height: containerHeight,
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.only(top: topPadding),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                width: artSize,
                height: artSize,
                child: _buildSwipeableAlbumArt(track, accentColor),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLyricsView({bool? isActive}) {
    return _IsolatedLyricsView(isActive: isActive ?? _showLyrics);
  }

  Widget _buildAlbumArtContent(
    Track? displayTrack,
    Color accentColor, {
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(16)),
  }) {
    final staticArt = _buildStaticAlbumArtContent(displayTrack, accentColor);
    if (displayTrack == null) return staticArt;

    return AnimatedAlbumArtView(
      key: ValueKey('animated_art_${displayTrack.id}'),
      track: displayTrack,
      staticArt: staticArt,
      borderRadius: borderRadius,
    );
  }

  Widget _buildStaticAlbumArtContent(Track? displayTrack, Color accentColor) {
    final localAudioPath = displayTrack?.localFilePath?.trim();
    if (localAudioPath != null && localAudioPath.isNotEmpty) {
      // 1. Fast synchronous check for memory-cached bytes
      final cachedBytes = LocalArtworkService.getCachedBytes(localAudioPath);
      if (cachedBytes != null && cachedBytes.isNotEmpty) {
        return Image.memory(
          cachedBytes,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) {
            return _defaultArt(accentColor);
          },
        );
      }

      // 2. Legacy companion .cover.jpg if present
      final localCoverFile = File('$localAudioPath.cover.jpg');
      if (localCoverFile.existsSync()) {
        return Image.file(
          localCoverFile,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          errorBuilder: (context, error, stackTrace) {
            return _defaultArt(accentColor);
          },
        );
      }

      // 3. Asynchronously load embedded artwork with fallback to network
      return FutureBuilder<Uint8List?>(
        future: LocalArtworkService.getArtworkBytes(
          localAudioPath,
          track: displayTrack,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done &&
              snapshot.hasData &&
              snapshot.data != null &&
              snapshot.data!.isNotEmpty) {
            return Image.memory(
              snapshot.data!,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) {
                return _defaultArt(accentColor);
              },
            );
          }
          if (displayTrack?.thumbnailUrl != null &&
              displayTrack!.thumbnailUrl!.trim().isNotEmpty) {
            return _buildNetworkArtwork(displayTrack, accentColor);
          }
          return _defaultArt(accentColor);
        },
      );
    }

    return _buildNetworkArtwork(displayTrack, accentColor);
  }

  Widget _buildNetworkArtwork(Track? displayTrack, Color accentColor) {
    final rawThumbnail = displayTrack?.thumbnailUrl?.trim();
    if (rawThumbnail == null || rawThumbnail.isEmpty) {
      return _defaultArt(accentColor);
    }

    final candidates = <String>[];
    final highResFromTrack = displayTrack?.highResThumbnailUrl?.trim();
    if (highResFromTrack != null && highResFromTrack.isNotEmpty) {
      candidates.add(highResFromTrack);
    }

    // Try an upgraded thumbnail first for now playing, then fallback to original.
    final upgradedThumbnail = rawThumbnail.replaceAll('w120-h120', 'w600-h600');
    if (upgradedThumbnail.isNotEmpty) {
      candidates.add(upgradedThumbnail);
    }
    candidates.add(rawThumbnail);

    final uniqueCandidates = <String>[];
    for (final url in candidates) {
      if (url.isEmpty) continue;
      if (!uniqueCandidates.contains(url)) {
        uniqueCandidates.add(url);
      }
    }

    return _buildAlbumArtWithFallback(uniqueCandidates, accentColor);
  }

  Widget _buildAlbumArtWithFallback(List<String> urls, Color accentColor) {
    if (urls.isEmpty) return _defaultArt(accentColor);

    Widget buildAt(int index) {
      if (index >= urls.length) return _defaultArt(accentColor);
      return CachedNetworkImage(
        imageUrl: urls[index],
        fit: BoxFit.cover,
        alignment: Alignment.center,
        placeholder: (context, url) => _defaultArt(accentColor),
        errorWidget: (context, url, error) => buildAt(index + 1),
      );
    }

    return buildAt(0);
  }

  double _safeAlbumArtPage(double fallback) {
    if (!_albumArtPageController.hasClients) return fallback;
    try {
      if (_albumArtPageController.positions.length == 1) {
        return _albumArtPageController.page ?? fallback;
      }
      for (final pos in _albumArtPageController.positions) {
        if (pos.viewportDimension > 0) {
          return pos.pixels / pos.viewportDimension;
        }
      }
    } catch (_) {}
    return fallback;
  }

  bool _lastDoubleTapWasLike = true;

  void _triggerDoubleTapLike(Track track) {
    final isLiked = ref.read(isTrackLikedProvider(track.id));
    _lastDoubleTapWasLike = !isLiked;
    _toggleLikeTrack(track);
    _heartAnimController.forward(from: 0.0);
  }

  Widget _buildHeartOverlay() {
    return AnimatedBuilder(
      animation: _heartAnimController,
      builder: (context, child) {
        if (_heartAnimController.isDismissed) return const SizedBox.shrink();
        return IgnorePointer(
          child: Center(
            child: Opacity(
              opacity: _heartOpacityAnimation.value.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: _heartScaleAnimation.value,
                child: _lastDoubleTapWasLike
                    ? Icon(
                        Icons.favorite_rounded,
                        color: Colors.redAccent,
                        size: 96,
                        shadows: [
                          BoxShadow(
                            color: Colors.redAccent.withValues(alpha: 0.7),
                            blurRadius: 36,
                            spreadRadius: 12,
                          ),
                        ],
                      )
                    : Icon(
                        Icons.heart_broken_rounded,
                        color: Colors.redAccent,
                        size: 96,
                        shadows: [
                          BoxShadow(
                            color: Colors.redAccent.withValues(alpha: 0.7),
                            blurRadius: 36,
                            spreadRadius: 12,
                          ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _toggleLikeTrack(Track track) async {
    await toggleTrackLike(ref: ref, track: track);
  }

  /// Swipeable album art widget for landscape Stage View
  Widget _buildSwipeableAlbumArt(Track track, Color accentColor) {
    final playerService = ref.watch(audioPlayerServiceProvider);
    final queue = playerService.queue;
    final currentIndex = playerService.currentIndex;

    if (queue.length <= 1) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () => _triggerDoubleTapLike(track),
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity != null) {
            if (details.primaryVelocity! < -200) {
              playerService.skipToNext();
            } else if (details.primaryVelocity! > 200) {
              playerService.skipToPrevious();
            }
          }
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            RepaintBoundary(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    // Ambient glow (YT Music style)
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.55),
                      blurRadius: 90,
                      spreadRadius: 24,
                      offset: const Offset(0, 26),
                    ),
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.25),
                      blurRadius: 140,
                      spreadRadius: 40,
                      offset: const Offset(0, 36),
                    ),
                    // Depth shadow for contrast
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 30,
                      spreadRadius: 5,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _buildAlbumArtContent(track, accentColor),
                ),
              ),
            ),
            _buildHeartOverlay(),
          ],
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is UserScrollNotification) {
          _isUserDraggingAlbumArt =
              notification.direction != ScrollDirection.idle;
        }
        if (notification is ScrollStartNotification) {
          if (notification.dragDetails != null) {
            _isUserDraggingAlbumArt = true;
          }
        } else if (notification is ScrollEndNotification) {
          _isUserDraggingAlbumArt = false;
        }
        return false;
      },
      child: PageView.builder(
        controller: _albumArtPageController,
        clipBehavior: Clip.none,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        itemCount: queue.length,
        onPageChanged: (pageIndex) {
          _handleAlbumArtPageChanged(
            pageIndex,
            playerService,
            currentIndex: currentIndex,
            queueLength: queue.length,
          );
        },
      itemBuilder: (context, pageIndex) {
        final displayTrack =
            (pageIndex >= 0 && pageIndex < queue.length)
            ? queue[pageIndex]
            : track;

        return AnimatedBuilder(
          animation: _albumArtPageController,
          builder: (context, child) {
            final fallbackPage = currentIndex >= 0
                ? currentIndex.toDouble()
                : 0.0;
            final page = _safeAlbumArtPage(fallbackPage);
            final delta = (pageIndex - page).abs().clamp(0.0, 1.0);
            final scale = (1.0 - (delta * 0.10)).clamp(0.90, 1.0);
            final opacity = (1.0 - (delta * 0.35)).clamp(0.65, 1.0);

            return Transform.scale(
              scale: scale,
              child: Opacity(
                opacity: opacity,
                child: GestureDetector(
                  onDoubleTap: () => _triggerDoubleTapLike(displayTrack),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      RepaintBoundary(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              // Ambient glow (YT Music style)
                              BoxShadow(
                                color: accentColor.withValues(alpha: 0.55),
                                blurRadius: 90,
                                spreadRadius: 24,
                                offset: const Offset(0, 26),
                              ),
                              BoxShadow(
                                color: accentColor.withValues(alpha: 0.25),
                                blurRadius: 140,
                                spreadRadius: 40,
                                offset: const Offset(0, 36),
                              ),
                              // Depth shadow for contrast
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 30,
                                spreadRadius: 5,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: pageIndex == currentIndex
                                ? _buildAlbumArtContent(
                                    displayTrack,
                                    accentColor,
                                  )
                                : _buildStaticAlbumArtContent(
                                    displayTrack,
                                    accentColor,
                                  ),
                          ),
                        ),
                      ),
                      _buildHeartOverlay(),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ),
  );
}

  /// Swipeable album art widget for Ripple style (clean unclipped stack for RippleFlowerClipper)
  Widget _buildRippleSwipeableAlbumArt(Track track, Color accentColor) {
    final playerService = ref.watch(audioPlayerServiceProvider);
    final queue = playerService.queue;
    final currentIndex = playerService.currentIndex;

    if (queue.length <= 1) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () => _triggerDoubleTapLike(track),
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity != null) {
            if (details.primaryVelocity! < -200) {
              playerService.skipToNext();
            } else if (details.primaryVelocity! > 200) {
              playerService.skipToPrevious();
            }
          }
        },
        child: _buildAlbumArtContent(track, accentColor),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is UserScrollNotification) {
          _isUserDraggingAlbumArt =
              notification.direction != ScrollDirection.idle;
        }
        if (notification is ScrollStartNotification) {
          if (notification.dragDetails != null) {
            _isUserDraggingAlbumArt = true;
          }
        } else if (notification is ScrollEndNotification) {
          _isUserDraggingAlbumArt = false;
        }
        return false;
      },
      child: PageView.builder(
        controller: _albumArtPageController,
        clipBehavior: Clip.none,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        itemCount: queue.length,
        onPageChanged: (pageIndex) {
          _handleAlbumArtPageChanged(
            pageIndex,
            playerService,
            currentIndex: currentIndex,
            queueLength: queue.length,
          );
        },
      itemBuilder: (context, pageIndex) {
        final displayTrack = queue[pageIndex];
        return AnimatedBuilder(
          animation: _albumArtPageController,
          builder: (context, child) {
            final fallbackPage = currentIndex >= 0
                ? currentIndex.toDouble()
                : 0.0;
            final page = _safeAlbumArtPage(fallbackPage);
            final delta = (pageIndex - page).abs().clamp(0.0, 1.0);
            final scale = (1.0 - (delta * 0.10)).clamp(0.90, 1.0);
            final opacity = (1.0 - (delta * 0.35)).clamp(0.65, 1.0);

            return Transform.scale(
              scale: scale,
              child: Opacity(
                opacity: opacity,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: () => _triggerDoubleTapLike(displayTrack),
                  child: pageIndex == currentIndex
                      ? _buildAlbumArtContent(
                          displayTrack,
                          accentColor,
                        )
                      : _buildStaticAlbumArtContent(
                          displayTrack,
                          accentColor,
                        ),
                ),
              ),
            );
          },
        );
      },
    ),
  );
  }

  /// Swipeable full-width album art widget for Edge-to-Edge style
  Widget _buildEdgeSwipeableAlbumArt(Track track, Color accentColor) {
    final playerService = ref.watch(audioPlayerServiceProvider);
    final queue = playerService.queue;
    final currentIndex = playerService.currentIndex;

    if (queue.length <= 1) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () => _triggerDoubleTapLike(track),
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity != null) {
            if (details.primaryVelocity! < -200) {
              playerService.skipToNext();
            } else if (details.primaryVelocity! > 200) {
              playerService.skipToPrevious();
            }
          }
        },
        child: _buildAlbumArtContent(
          track,
          accentColor,
          borderRadius: BorderRadius.zero,
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is UserScrollNotification) {
          _isUserDraggingAlbumArt =
              notification.direction != ScrollDirection.idle;
        }
        if (notification is ScrollStartNotification) {
          if (notification.dragDetails != null) {
            _isUserDraggingAlbumArt = true;
          }
        } else if (notification is ScrollEndNotification) {
          _isUserDraggingAlbumArt = false;
        }
        return false;
      },
      child: PageView.builder(
        controller: _albumArtPageController,
        clipBehavior: Clip.none,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        itemCount: queue.length,
        onPageChanged: (pageIndex) {
          _handleAlbumArtPageChanged(
            pageIndex,
            playerService,
            currentIndex: currentIndex,
            queueLength: queue.length,
          );
        },
        itemBuilder: (context, pageIndex) {
          final displayTrack = queue[pageIndex];
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: () => _triggerDoubleTapLike(displayTrack),
            child: pageIndex == currentIndex
                ? _buildAlbumArtContent(
                    displayTrack,
                    accentColor,
                    borderRadius: BorderRadius.zero,
                  )
                : _buildStaticAlbumArtContent(
                    displayTrack,
                    accentColor,
                  ),
          );
        },
      ),
    );
  }

  Widget _buildSyncedLyricPreview(
    Color textColor,
    Color accentColor, {
    bool isCentered = false,
  }) {
    final showLyricsBelowArt = ref.watch(showLyricsBelowAlbumArtProvider);
    if (!showLyricsBelowArt) return const SizedBox.shrink();
    // No lyrics for live/radio streams — they'd be stale/wrong.
    if (ref.watch(isLiveProvider)) return const SizedBox.shrink();

    return SyncedLyricPreview(
      textColor: textColor,
      accentColor: accentColor,
      isCentered: isCentered,
      onTap: () {
        _tabController.animateTo(1);
        if (_pageController.hasClients) {
          _pageController.jumpToPage(1);
        }
        _drawerKey.currentState?.expand();
      },
    );
  }

  Widget _buildTrackInfo(
    Track track,
    Color textColor,
    Color secondaryColor,
    Color accentColor, {
    bool isCompact = false,
    bool isOg = false,
  }) {
    final titleFontSize = isOg
        ? (isCompact ? 16.0 : 20.0)
        : (isCompact ? 15.0 : 17.0);
    final titleHeight = isOg
        ? (isCompact ? 24.0 : 28.0)
        : (isCompact ? 22.0 : 26.0);
    final artistFontSize = isOg
        ? (isCompact ? 13.0 : 15.0)
        : (isCompact ? 12.0 : 14.0);
    final artistHeight = isCompact ? 18.0 : 22.0;
    final horizontalPadding = isCompact ? 16.0 : 24.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: isOg
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                // Marquee for long titles
                SizedBox(
                  height: titleHeight,
                  child: Row(
                    mainAxisAlignment: isOg ? MainAxisAlignment.start : MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (track.isExplicit)
                        ExplicitBadge(color: textColor),
                      Flexible(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final textPainter = TextPainter(
                              text: TextSpan(
                                text: track.title,
                                style: TextStyle(
                                  fontSize: titleFontSize,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                              maxLines: 1,
                              textDirection: TextDirection.ltr,
                            )..layout();

                            // Only use marquee if text overflows
                            if (textPainter.width > (constraints.maxWidth - 2)) {
                              return Marquee(
                                text: track.title,
                                style: TextStyle(
                                  fontSize: titleFontSize,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                                scrollAxis: Axis.horizontal,
                                crossAxisAlignment: isOg
                                    ? CrossAxisAlignment.start
                                    : CrossAxisAlignment.center,
                                blankSpace: 60.0,
                                velocity: 30.0,
                                pauseAfterRound: const Duration(seconds: 2),
                                startPadding: 0.0,
                                accelerationDuration: const Duration(seconds: 1),
                                accelerationCurve: Curves.linear,
                                decelerationDuration: const Duration(
                                  milliseconds: 500,
                                ),
                                decelerationCurve: Curves.easeOut,
                              );
                            }
                            return Text(
                              track.title,
                              maxLines: 1,
                              textAlign: isOg ? TextAlign.start : TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: titleFontSize,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                // Marquee for long artist names
                SizedBox(
                  height: artistHeight,
                  child: _buildArtistLink(
                    track,
                    style: TextStyle(
                      fontSize: artistFontSize,
                      color: secondaryColor,
                    ),
                    maxLines: 1,
                    enableMarquee: true,
                    textAlign: isOg ? TextAlign.start : TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          if (isOg) ...[
            const SizedBox(width: 8),
            // Download indicator
            Builder(
              builder: (context) {
                final isDownloaded = ref.watch(
                  isTrackDownloadedProvider(track.id),
                );
                final progress = ref.watch(
                  trackDownloadProgressProvider(track.id),
                );

                if (isDownloaded) {
                  return const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(
                      Iconsax.tick_circle5,
                      size: 20,
                      color: Colors.green,
                    ),
                  );
                }

                if (progress != null) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 2,
                        color: secondaryColor,
                      ),
                    ),
                  );
                }

                return const SizedBox.shrink();
              },
            ),
            // Action Buttons Capsule (Like, Share, Jam)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: textColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.38),
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Like button
                  Builder(
                    builder: (context) {
                      final isLiked = ref.watch(isTrackLikedProvider(track.id));
                      return BouncyTouch(
                        style: BouncyStyle.heartPop,
                        customScale: 0.85,
                        onTap: () => _toggleLikeTrack(track),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9.0,
                            vertical: 7.0,
                          ),
                          child: Icon(
                            isLiked ? Iconsax.heart5 : Iconsax.heart,
                            color: isLiked
                                ? Colors.red
                                : textColor.withValues(alpha: 0.9),
                            size: 21,
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(width: 5),
                  Container(
                    width: 1,
                    height: 22,
                    color: textColor.withValues(alpha: 0.15),
                  ),
                  const SizedBox(width: 5),

                  // Share button
                  BouncyTouch(
                    style: BouncyStyle.button,
                    customScale: 0.92,
                    onTap: () {
                      final url = DeepLinkHandler.createShareUrl('song', track.id);
                      SharePlus.instance.share(
                        ShareParams(
                          text: context.l10n.shareTrackText(
                            track.title,
                            track.artist,
                            url,
                          ),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9.0,
                        vertical: 7.0,
                      ),
                      child: Icon(
                        Icons.share_rounded,
                        color: textColor.withValues(alpha: 0.9),
                        size: 20,
                      ),
                    ),
                  ),

                  const SizedBox(width: 5),
                  Container(
                    width: 1,
                    height: 22,
                    color: textColor.withValues(alpha: 0.15),
                  ),
                  const SizedBox(width: 5),

                  // Jams button - listen together
                  _buildJamsCompactButton(textColor, accentColor),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildJamsCompactButton(Color textColor, Color accentColor) {
    final isInSession = ref.watch(isInJamSessionProvider);
    final session = ref.watch(currentJamSessionProvider).valueOrNull;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        BouncyTouch(
          style: BouncyStyle.button,
          customScale: 0.92,
          onTap: () {
            final albumColors = ref.read(albumColorsProvider);
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final bgColor = (!albumColors.isDefault
                ? albumColors.backgroundPrimary
                : (isDark ? const Color(0xFF141414) : Colors.white)).withValues(alpha: 1.0);
            final txtColor = !albumColors.isDefault
                ? albumColors.onBackground
                : (isDark ? Colors.white : InzxColors.textPrimary);
            JamsPanel.show(
              context,
              backgroundColor: bgColor,
              textColor: txtColor,
              accentColor: accentColor,
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 9.0,
              vertical: 7.0,
            ),
            child: Icon(
              Iconsax.profile_2user,
              color: isInSession ? accentColor : textColor.withValues(alpha: 0.9),
              size: 20,
            ),
          ),
        ),
        if (isInSession && session != null)
          Positioned(
            right: 2,
            top: 2,
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildArtistLink(
    Track track, {
    required TextStyle style,
    required int maxLines,
    required bool enableMarquee,
    TextAlign textAlign = TextAlign.start,
  }) {
    final canOpen = track.isPodcast ||
        (track.podcastId != null && track.podcastId!.isNotEmpty) ||
        track.artistId.isNotEmpty;

    final artistLabel = enableMarquee
        ? LayoutBuilder(
            builder: (context, constraints) {
              final textPainter = TextPainter(
                text: TextSpan(text: track.artist, style: style),
                maxLines: maxLines,
                textDirection: TextDirection.ltr,
              )..layout();

              if (textPainter.width > constraints.maxWidth) {
                return Marquee(
                  text: track.artist,
                  style: style,
                  scrollAxis: Axis.horizontal,
                  crossAxisAlignment: textAlign == TextAlign.center
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.start,
                  blankSpace: 60.0,
                  velocity: 30.0,
                  pauseAfterRound: const Duration(seconds: 2),
                  startPadding: 0.0,
                );
              }

              return Text(
                track.artist,
                maxLines: maxLines,
                textAlign: textAlign,
                overflow: TextOverflow.ellipsis,
                style: style,
              );
            },
          )
        : Text(
            track.artist,
            maxLines: maxLines,
            textAlign: textAlign,
            overflow: TextOverflow.ellipsis,
            style: style,
          );

    if (!canOpen) {
      return artistLabel;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openArtist(track),
      child: artistLabel,
    );
  }

  void _openArtist(Track track) {
    if (track.isPodcast || (track.podcastId != null && track.podcastId!.isNotEmpty)) {
      PodcastScreen.open(
        context,
        podcastId: track.podcastId!,
        title: track.album ?? track.artist,
        thumbnailUrl: track.thumbnailUrl,
      );
      return;
    }
    if (track.artistId.isEmpty) return;
    ArtistScreen.open(context, artistId: track.artistId, name: track.artist);
  }

  Widget _buildControls(
    player.PlaybackState state,
    player.AudioPlayerService playerService,
    Color textColor,
    Color accentColor, {
    bool isCompact = false,
    double? horizontalPadding,
  }) {
    // Check if in Jam and has control permission
    final isInJam = ref.watch(isInJamSessionProvider);
    final canControl = ref.watch(canControlJamPlaybackProvider);
    final canSkip =
        !isInJam || canControl; // Can skip if not in Jam or has permission

    final playPauseSize = isCompact ? 52.0 : 72.0;
    final playPauseIconSize = isCompact ? 32.0 : 42.0;
    final skipIconSize = isCompact ? 28.0 : 36.0;
    final modeIconSize = isCompact ? 20.0 : 24.0;
    final effectiveHorizontalPadding =
        horizontalPadding ?? (isCompact ? 12.0 : 24.0);

    final isLiquidGlass = ref.watch(liquidGlassNavProvider);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: effectiveHorizontalPadding,
        vertical: isCompact ? 0 : 0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Shuffle
          BouncyTouch(
            style: BouncyStyle.button,
            customScale: 0.90,
            onTap: () => playerService.toggleShuffle(),
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Icon(
                Iconsax.shuffle,
                color: state.shuffleEnabled
                    ? accentColor
                    : textColor.withValues(alpha: 0.6),
                size: modeIconSize,
              ),
            ),
          ),
          // Previous
          BouncyTouch(
            style: BouncyStyle.button,
            customScale: 0.90,
            onTap: canSkip ? playerService.skipToPrevious : null,
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Icon(
                Iconsax.previous,
                color: canSkip ? textColor : textColor.withValues(alpha: 0.3),
                size: skipIconSize,
              ),
            ),
          ),
          // Play/Pause - always allowed (sync controller handles it)
          AnimatedPlayPauseButton(
            isPlaying: state.isPlaying,
            onTap: state.isPlaying ? playerService.pause : playerService.play,
            size: playPauseSize,
            iconSize: playPauseIconSize,
            backgroundColor: accentColor,
            isLiquidGlass: isLiquidGlass,
          ),
          // Next
          BouncyTouch(
            style: BouncyStyle.button,
            customScale: 0.90,
            onTap: canSkip ? playerService.skipToNext : null,
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Icon(
                Iconsax.next,
                color: canSkip ? textColor : textColor.withValues(alpha: 0.3),
                size: skipIconSize,
              ),
            ),
          ),
          // Repeat
          BouncyTouch(
            style: BouncyStyle.button,
            customScale: 0.90,
            onTap: () => playerService.cycleLoopMode(),
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Icon(
                state.loopMode == LoopMode.one
                    ? Iconsax.repeate_one
                    : Iconsax.repeate_music,
                color: state.loopMode != LoopMode.off
                    ? accentColor
                    : textColor.withValues(alpha: 0.6),
                size: modeIconSize,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// YTM-style bottom tabs with TabBar for animated transitions
  Widget _buildBottomTabs(Color textColor, Color accentColor) {
    // Only show active tab styling when drawer is expanded
    final showActiveState = _isDrawerExpanded;

    return TabBar(
      controller: _tabController,
      // Label color - all same when collapsed, accent when expanded
      labelColor: showActiveState
          ? accentColor
          : textColor.withValues(alpha: 0.6),
      unselectedLabelColor: textColor.withValues(alpha: 0.6),
      // Indicator - transparent when collapsed
      indicatorColor: showActiveState ? accentColor : Colors.transparent,
      indicatorWeight: 2,
      indicatorSize: TabBarIndicatorSize.label,
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: showActiveState ? FontWeight.bold : FontWeight.w500,
        letterSpacing: 0.5,
      ),
      unselectedLabelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
      tabs: [
        Tab(text: context.l10n.upNext),
        Tab(text: context.l10n.lyricsTab),
        Tab(text: context.l10n.relatedTab),
      ],
      onTap: (index) {
        setState(() {
          _showQueue = index == 0;
          _showLyrics = index == 1;
          // index 2 = Related
        });
        if (_pageController.hasClients) {
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        }
        // Also expand the drawer when tapping a tab
        _drawerKey.currentState?.expand();
      },
    );
  }

  Widget _defaultArt(Color accentColor) {
    return Container(
      color: accentColor.withValues(alpha: 0.2),
      child: Icon(Iconsax.music, color: accentColor, size: 64),
    );
  }
}

/// Animated 3-bar soundwave equalizer for active playing track in Up Next queue
class _QueuePlayingEqualizerBars extends StatefulWidget {
  final Color color;

  const _QueuePlayingEqualizerBars({required this.color});

  @override
  State<_QueuePlayingEqualizerBars> createState() =>
      __QueuePlayingEqualizerBarsState();
}

class __QueuePlayingEqualizerBarsState extends State<_QueuePlayingEqualizerBars>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        final val = _animController.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _bar(8 + (val * 10)),
            const SizedBox(width: 2.5),
            _bar(18 - (val * 10)),
            const SizedBox(width: 2.5),
            _bar(6 + (val * 12)),
          ],
        );
      },
    );
  }

  Widget _bar(double height) {
    return Container(
      width: 3,
      height: height.clamp(4.0, 20.0),
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
