import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import '../../../../core/design_system/design_system.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import 'package:marquee/marquee.dart';
import 'track_artwork_view.dart';



/// Custom painter for circular track progress ring around album art
class _CircularTrackProgressPainter extends CustomPainter {
  final double progress; // 0.0 to 1.0
  final Color trackColor;
  final Color progressColor;
  final double strokeWidth;

  _CircularTrackProgressPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    this.strokeWidth = 2.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Track background circle
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, trackPaint);

    // Active progress arc
    if (progress > 0) {
      final progressPaint = Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      final startAngle = -math.pi / 2; // 12 o'clock top start
      final sweepAngle = 2 * math.pi * progress.clamp(0.0, 1.0);

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CircularTrackProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

/// Circular album art with progress ring and vinyl rotation during playback
class _CircularAlbumArtWithProgress extends ConsumerStatefulWidget {
  final Track track;
  final Duration? duration;
  final Color accentColor;
  final Color textColor;
  final bool isPlaying;

  const _CircularAlbumArtWithProgress({
    required this.track,
    required this.duration,
    required this.accentColor,
    required this.textColor,
    required this.isPlaying,
  });

  @override
  ConsumerState<_CircularAlbumArtWithProgress> createState() =>
      _CircularAlbumArtWithProgressState();
}

class _CircularAlbumArtWithProgressState
    extends ConsumerState<_CircularAlbumArtWithProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncRotation();
      }
    });
  }

  @override
  void didUpdateWidget(_CircularAlbumArtWithProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) {
      _syncRotation();
    }
    // If track changed while paused, reset to upright orientation
    if (oldWidget.track.id != widget.track.id && !widget.isPlaying) {
      if (_rotationController.value != 0.0) {
        _rotationController.reset();
      }
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  void _syncRotation() {
    if (!mounted) return;
    final isEnabled = ref.read(rotatingMiniPlayerArtProvider);
    final shouldRotate = widget.isPlaying && isEnabled;

    if (shouldRotate) {
      if (!_rotationController.isAnimating) {
        _rotationController.repeat();
      }
    } else {
      if (_rotationController.isAnimating) {
        _rotationController.stop(canceled: false);
      }
      if (!isEnabled && _rotationController.value != 0.0) {
        _rotationController.reset();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // React to settings toggle changes in real time
    ref.listen<bool>(rotatingMiniPlayerArtProvider, (prev, next) {
      _syncRotation();
    });

    final position =
        ref.watch(positionStreamProvider).valueOrNull ?? Duration.zero;

    final progress = (widget.duration?.inMilliseconds ?? 0) > 0
        ? (position.inMilliseconds / widget.duration!.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return SizedBox(
      width: 50,
      height: 50,
      child: CustomPaint(
        painter: _CircularTrackProgressPainter(
          progress: progress,
          trackColor: widget.textColor.withValues(alpha: 0.15),
          progressColor: widget.accentColor,
          strokeWidth: 2.5,
        ),
        child: Center(
          child: Hero(
            tag: 'album-art-${widget.track.id}',
            child: ClipOval(
              child: RotationTransition(
                turns: _rotationController,
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: TrackArtworkView(
                    track: widget.track,
                    width: 42,
                    height: 42,
                    fallbackColor: widget.accentColor.withValues(alpha: 0.2),
                    fallbackIcon: Iconsax.music,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Floating glassmorphic capsule MiniPlayer widget
class MusicMiniPlayer extends ConsumerStatefulWidget {
  final VoidCallback onTap;

  const MusicMiniPlayer({
    super.key,
    required this.onTap,
  });

  @override
  ConsumerState<MusicMiniPlayer> createState() => _MusicMiniPlayerState();
}

class _MusicMiniPlayerState extends ConsumerState<MusicMiniPlayer> {
  String? _dismissedTrackId;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final playbackState = ref.watch(playbackStateProvider);
    final playerService = ref.watch(audioPlayerServiceProvider);
    final albumColors = ref.watch(albumColorsProvider);

    return playbackState.when(
      data: (state) {
        if (state.currentTrack == null) {
          _dismissedTrackId = null;
          return const SizedBox.shrink();
        }

        final track = state.currentTrack!;
        if (_dismissedTrackId == track.id) {
          return const SizedBox.shrink();
        } else if (_dismissedTrackId != null && _dismissedTrackId != track.id) {
          _dismissedTrackId = null;
        }

        final hasAlbumColors = !albumColors.isDefault;

        // Accent for progress ring & primary play button
        final accentColor = hasAlbumColors
            ? albumColors.accent
            : colorScheme.primary;

        final isLiquidGlass = ref.watch(liquidGlassNavProvider);

        final Color borderColor = accentColor.withValues(
          alpha: isDark ? 0.38 : 0.30,
        );

        final List<Color> gradientColors;
        final Color backgroundForText =
            isDark ? const Color(0xFF101010) : const Color(0xFF1A1A1A);

        if (isDark) {
          gradientColors = [
            Colors.black.withValues(alpha: 0.62),
            const Color(0xFF101010).withValues(alpha: 0.56),
          ];
        } else {
          // Over a light page the translucent glass washes out to grey and the
          // white text/icons lose contrast — keep it a solid dark tint so they
          // stay clearly readable.
          gradientColors = [
            const Color(0xFF1F1F1F).withValues(alpha: 0.94),
            const Color(0xFF121212).withValues(alpha: 0.92),
          ];
        }

        final textColors = InzxColors.adaptiveTextColors(backgroundForText);
        final foregroundColor = textColors.primary;
        final secondaryColor = textColors.secondary;

        final miniPlayerContent = Row(
                      children: [
                        // Album Art with Circular Progress Ring & Vinyl Rotation
                        _CircularAlbumArtWithProgress(
                          track: track,
                          duration: state.duration,
                          accentColor: accentColor,
                          textColor: foregroundColor,
                          isPlaying: state.isPlaying,
                        ),
                        const SizedBox(width: 10),

                        // Track Title & Artist
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: SizedBox(
                                      height: 18,
                                      child: LayoutBuilder(
                                        builder: (context, constraints) {
                                          final textPainter = TextPainter(
                                            text: TextSpan(
                                              text: track.title,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13.5,
                                                color: foregroundColor,
                                              ),
                                            ),
                                            maxLines: 1,
                                            textDirection: TextDirection.ltr,
                                          )..layout();

                                          if (textPainter.width >
                                              (constraints.maxWidth - 2)) {
                                            return Marquee(
                                              text: track.title,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13.5,
                                                color: foregroundColor,
                                              ),
                                              scrollAxis: Axis.horizontal,
                                              blankSpace: 40.0,
                                              velocity: 28.0,
                                              pauseAfterRound:
                                                  const Duration(seconds: 2),
                                              startPadding: 0.0,
                                              accelerationDuration:
                                                  const Duration(seconds: 1),
                                              accelerationCurve: Curves.linear,
                                              decelerationDuration:
                                                  const Duration(
                                                milliseconds: 500,
                                              ),
                                              decelerationCurve: Curves.easeOut,
                                            );
                                          }

                                          return Text(
                                            track.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13.5,
                                              color: foregroundColor,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              SizedBox(
                                height: 16,
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final textPainter = TextPainter(
                                      text: TextSpan(
                                        text: track.artist,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w500,
                                          color: secondaryColor,
                                        ),
                                      ),
                                      maxLines: 1,
                                      textDirection: TextDirection.ltr,
                                    )..layout();

                                    if (textPainter.width >
                                        (constraints.maxWidth - 2)) {
                                      return Marquee(
                                        text: track.artist,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w500,
                                          color: secondaryColor,
                                        ),
                                        scrollAxis: Axis.horizontal,
                                        blankSpace: 40.0,
                                        velocity: 28.0,
                                        pauseAfterRound:
                                            const Duration(seconds: 2),
                                        startPadding: 0.0,
                                        accelerationDuration:
                                            const Duration(seconds: 1),
                                        accelerationCurve: Curves.linear,
                                        decelerationDuration: const Duration(
                                          milliseconds: 500,
                                        ),
                                        decelerationCurve: Curves.easeOut,
                                      );
                                    }

                                    return Text(
                                      track.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w500,
                                        color: secondaryColor,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),

                        // 3 Circular Action Controls (Previous, Play/Pause, Next)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildCircularButton(
                              icon: Iconsax.previous,
                              iconSize: 17,
                              onPressed: playerService.skipToPrevious,
                              iconColor: foregroundColor,
                              bgColor: foregroundColor.withValues(alpha: 0.08),
                            ),
                            const SizedBox(width: 6),
                            AnimatedPlayPauseButton(
                              isPlaying: state.isPlaying,
                              onTap: state.isPlaying
                                  ? playerService.pause
                                  : playerService.play,
                              size: 36,
                              iconSize: 20,
                              backgroundColor: accentColor,
                            ),
                            const SizedBox(width: 6),
                            _buildCircularButton(
                              icon: Iconsax.next,
                              iconSize: 17,
                              onPressed: playerService.skipToNext,
                              iconColor: foregroundColor,
                              bgColor: foregroundColor.withValues(alpha: 0.08),
                            ),
                            const SizedBox(width: 4),
                          ],
                        ),
                      ],
                    );

        final Widget capsule;
        if (isLiquidGlass) {
          capsule = LiquidGlassContainer(
            pressable: false,
            borderRadius: 32,
            blurSigma: 2.0,
            refractionScale: 1.05,
            refractionDeflection: 2.8,
            isDark: isDark,
            surfaceColor: Colors.black.withValues(
              alpha: isDark ? 0.45 : 0.35,
            ),
            accentColor: accentColor,
            height: 64.0,
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 6,
            ),
            additionalShadows: [
              if (hasAlbumColors)
                BoxShadow(
                  color: accentColor.withValues(
                    alpha: isDark ? 0.20 : 0.10,
                  ),
                  blurRadius: 24,
                  spreadRadius: -2,
                  offset: const Offset(0, 4),
                ),
            ],
            child: miniPlayerContent,
          );
        } else {
          capsule = Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: isDark ? 0.30 : 0.08,
                  ),
                  blurRadius: 16,
                  spreadRadius: 1,
                  offset: const Offset(0, 4),
                ),
                if (hasAlbumColors)
                  BoxShadow(
                    color: accentColor.withValues(
                      alpha: isDark ? 0.20 : 0.10,
                    ),
                    blurRadius: 24,
                    spreadRadius: -2,
                    offset: const Offset(0, 4),
                  ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  height: 64.0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradientColors,
                    ),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(
                      color: borderColor,
                      width: 1.0,
                    ),
                  ),
                  child: miniPlayerContent,
                ),
              ),
            ),
          );
        }

        // When liquid glass is enabled, the LiquidGlassContainer must NOT be
        // inside BouncyTouch's Transform.scale — the scale transform creates
        // a compositing layer that breaks BackdropFilter's matrix refraction.
        // This matches the bottom nav pattern where LiquidGlassContainer sits
        // directly in the tree with no Transform parent.
        if (isLiquidGlass) {
          return Dismissible(
            key: ValueKey('mini_player_${track.id}'),
            direction: DismissDirection.down,
            onDismissed: (_) {
              setState(() {
                _dismissedTrackId = track.id;
              });
              HapticFeedback.mediumImpact();
              ref.read(audioPlayerServiceProvider).clearQueue();
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTap,
                child: capsule,
              ),
            ),
          );
        }

        return Dismissible(
          key: ValueKey('mini_player_${track.id}'),
          direction: DismissDirection.down,
          onDismissed: (_) {
            setState(() {
              _dismissedTrackId = track.id;
            });
            HapticFeedback.mediumImpact();
            ref.read(audioPlayerServiceProvider).clearQueue();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
            child: BouncyTouch(
              style: BouncyStyle.card,
              customScale: 0.985,
              onTap: widget.onTap,
              child: capsule,
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  Widget _buildCircularButton({
    required IconData icon,
    required double iconSize,
    required VoidCallback onPressed,
    required Color iconColor,
    required Color bgColor,
    double scale = 0.92,
  }) {
    return BouncyTouch(
      style: BouncyStyle.button,
      customScale: scale,
      onTap: onPressed,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Icon(
            icon,
            color: iconColor,
            size: iconSize,
          ),
        ),
      ),
    );
  }
}
