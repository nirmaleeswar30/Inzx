import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:marquee/marquee.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/l10n/app_localizations_x.dart';
import '../../services/audio_player_service.dart' as player;
import '../../services/lyrics/lyrics_service.dart';
import '../../services/lyrics/lyrics_models.dart';
import '../../core/design_system/design_system.dart';
import 'artist_screen.dart';
import 'podcast_screen.dart' show PodcastScreen;
import 'ripple_circular_progress_scrubber.dart';
import 'ripple_flower_clipper.dart';
import 'jam_indicator_badge.dart';
import 'explicit_badge.dart';

/// The 'Ripple' minimalist Now Playing screen layout.
/// Features an 8-petal wavy album art mask, concentric waveform seek ring,
/// top-centered track info with stats and timestamp, and clean centered typography.
class RippleNowPlayingView extends ConsumerStatefulWidget {
  final Track track;
  final player.PlaybackState state;
  final player.AudioPlayerService playerService;
  final Color textColor;
  final Color secondaryTextColor;
  final Color accentColor;
  final Widget albumArt;
  final VoidCallback onDismiss;
  final VoidCallback? onOpenOptions;
  final Widget tabsWidget;
  final VoidCallback? onToggleLike;
  final VoidCallback? onDoubleTapLike;
  final Widget? heartOverlay;
  final ValueChanged<bool>? onSeekingChanged;
  final bool isLiked;
  final Widget? lyricPreview;

  const RippleNowPlayingView({
    super.key,
    required this.track,
    required this.state,
    required this.playerService,
    required this.textColor,
    required this.secondaryTextColor,
    required this.accentColor,
    required this.albumArt,
    required this.onDismiss,
    this.onOpenOptions,
    required this.tabsWidget,
    this.onToggleLike,
    this.onDoubleTapLike,
    this.heartOverlay,
    this.onSeekingChanged,
    this.isLiked = false,
    this.lyricPreview,
  });

  @override
  ConsumerState<RippleNowPlayingView> createState() =>
      _RippleNowPlayingViewState();
}

class _RippleNowPlayingViewState extends ConsumerState<RippleNowPlayingView> {
  Duration? _seekingPosition;
  bool _showStatsInsteadOfTitle = false;

  @override
  Widget build(BuildContext context) {
    final duration = widget.state.duration ?? Duration.zero;
    final isLiquidGlass = ref.watch(liquidGlassNavProvider);

    final lyricsState = ref.watch(lyricsProvider);
    final isFetchingLyrics =
        lyricsState.currentStatus.state == LyricsProviderState.fetching ||
        lyricsState.currentStatus.state == LyricsProviderState.idle;
    final hasSyncedLyrics =
        lyricsState.currentLyrics?.hasSyncedLyrics ?? false;
    final showLyricsBelowArt = ref.watch(showLyricsBelowAlbumArtProvider);
    final hasLyricsPreview =
        showLyricsBelowArt && (isFetchingLyrics || hasSyncedLyrics);

    return SafeArea(
      top: true,
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = constraints.maxHeight;

          // Responsive sizing for the centerpiece based on screen height and lyrics presence
          final double scrubberSize;
          if (hasLyricsPreview) {
            if (availableHeight < 640) {
              scrubberSize = (constraints.maxWidth * 0.68).clamp(190.0, 235.0);
            } else if (availableHeight < 750) {
              scrubberSize = (constraints.maxWidth * 0.74).clamp(225.0, 275.0);
            } else {
              scrubberSize = (constraints.maxWidth * 0.78).clamp(255.0, 310.0);
            }
          } else {
            if (availableHeight < 640) {
              scrubberSize = (constraints.maxWidth * 0.76).clamp(220.0, 270.0);
            } else if (availableHeight < 750) {
              scrubberSize = (constraints.maxWidth * 0.83).clamp(260.0, 320.0);
            } else {
              scrubberSize = (constraints.maxWidth * 0.88).clamp(290.0, 365.0);
            }
          }

          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity < -200) {
                widget.playerService.skipToNext();
              } else if (velocity > 200) {
                widget.playerService.skipToPrevious();
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  // 1. Top Bar with Back button, "NOW PLAYING" / stats in center, and 3-dot menu
                  _buildTopHeader(isLiquidGlass),

                  const Spacer(flex: 2),

                  // 2. Standalone Centered Time Readout: "01:23 | 03:40"
                  _RippleTimeReadout(
                    totalDuration: duration,
                    seekingPosition: _seekingPosition,
                    isPlaying: widget.state.isPlaying,
                    textColor: widget.textColor,
                    secondaryTextColor: widget.secondaryTextColor,
                  ),

                  const SizedBox(height: 14),

                  // 3. Centerpiece: Waveform Seek Ring enclosing 8-Petal Wavy Art
                  Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutCubic,
                      width: scrubberSize,
                      height: scrubberSize,
                      child: Consumer(
                        builder: (context, ref, _) {
                          final streamPos =
                              ref.watch(positionStreamProvider).valueOrNull ??
                              Duration.zero;
                          final displayPos = _seekingPosition ?? streamPos;

                          return RippleCircularProgressScrubber(
                            position: displayPos,
                            duration: duration,
                            isPlaying: widget.state.isPlaying,
                            activeColor: widget.accentColor,
                            inactiveColor:
                                widget.textColor.withValues(alpha: 0.14),
                            strokeWidth: 2.2,
                            thumbRadius: 5.5,
                            waveAmplitudeRatio: 0.065,
                            lobes: 8,
                            paddingAroundChild: 14.0,
                            onSeekingChanged: widget.onSeekingChanged,
                            onSeeking: (seeking) {
                              setState(() => _seekingPosition = seeking);
                            },
                            onSeek: (target) {
                              setState(() => _seekingPosition = null);
                              widget.playerService.seek(target);
                            },
                            child: Stack(
                              fit: StackFit.expand,
                              clipBehavior: Clip.none,
                              children: [
                                // Multi-tiered Ambient Glow (YT Music style matching Default player)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: RepaintBoundary(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            // Primary Ambient Glow (YT Music style)
                                            BoxShadow(
                                              color: widget.accentColor
                                                  .withValues(alpha: 0.55),
                                              blurRadius: 90,
                                              spreadRadius: 24,
                                              offset: const Offset(0, 24),
                                            ),
                                            // Deep Diffuse Ambient Atmosphere
                                            BoxShadow(
                                              color: widget.accentColor
                                                  .withValues(alpha: 0.25),
                                              blurRadius: 140,
                                              spreadRadius: 40,
                                              offset: const Offset(0, 34),
                                            ),
                                            // Depth Shadow for Contrast
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.35,
                                              ),
                                              blurRadius: 30,
                                              spreadRadius: 5,
                                              offset: const Offset(0, 10),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                                // Silky Smooth Clipped Wavy Artwork with double-tap to like
                                ClipPath(
                                  clipper: const RippleFlowerClipper(
                                    waveAmplitudeRatio: 0.065,
                                    lobes: 8,
                                  ),
                                  clipBehavior: Clip.antiAliasWithSaveLayer,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onDoubleTap: widget.onDoubleTapLike,
                                    child: widget.albumArt,
                                  ),
                                ),

                                // Thin outline border along the wavy lobes with ambient accent tint
                                IgnorePointer(
                                  child: CustomPaint(
                                    painter: RippleFlowerBorderPainter(
                                      borderColor: Color.lerp(
                                        widget.textColor.withValues(
                                          alpha: 0.18,
                                        ),
                                        widget.accentColor.withValues(
                                          alpha: 0.35,
                                        ),
                                        0.5,
                                      )!,
                                      strokeWidth: 1.5,
                                      waveAmplitudeRatio: 0.065,
                                      lobes: 8,
                                    ),
                                  ),
                                ),

                                // Popping heart animation front-and-center (unclipped!)
                                if (widget.heartOverlay != null)
                                  IgnorePointer(
                                    child: widget.heartOverlay!,
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),


                  // 4. Live Synced Lyrics Preview under album art
                  if (widget.lyricPreview != null)
                    widget.lyricPreview!,

                  SizedBox(height: hasLyricsPreview ? 4 : 14),

                  // 5. Centered Title & Artist
                  _buildTrackInfo(),

                const Spacer(flex: 2),

                // 5. Playback Controls Row
                _buildControlsRow(isLiquidGlass),

                const Spacer(flex: 2),

                // 6. Drawer Tabs Bar (UP NEXT | LYRICS | RELATED)
                widget.tabsWidget,

                SizedBox(
                  height: max(12.0, MediaQuery.of(context).padding.bottom + 2),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}


  /// Top Bar with dismiss button, centered track/stats, and 3-dot menu
  Widget _buildTopHeader(bool isLiquidGlass) {
    final playbackState = ref.watch(playbackStateProvider).valueOrNull;
    final queueTitle = playbackState?.queueTitle;
    final hasQueueTitle = queueTitle != null && queueTitle.trim().isNotEmpty;
    final showNerdStats = playbackState?.showNerdStats ?? false;
    final statsSummary = playbackState?.qualityInfo;
    final hasStats =
        showNerdStats && statsSummary != null && statsSummary.isNotEmpty;

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

    final albumColors = ref.watch(albumColorsProvider);
    final hasAlbumColors = !albumColors.isDefault;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget buildDropletButton({
      required Widget icon,
      required VoidCallback onTap,
    }) {
      if (isLiquidGlass) {
        return LiquidGlassContainer(
          width: 40,
          height: 40,
          borderRadius: 20,
          blurSigma: 2.0,
          refractionScale: 1.08,
          refractionDeflection: 2.8,
          isDark: isDark,
          surfaceColor: Colors.black.withValues(
            alpha: isDark ? 0.38 : 0.22,
          ),
          accentColor: hasAlbumColors
              ? widget.accentColor.withValues(alpha: 0.50)
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
                color: widget.accentColor.withValues(
                  alpha: isDark ? 0.20 : 0.10,
                ),
                blurRadius: 12,
                spreadRadius: 0,
              ),
          ],
          child: SizedBox.expand(
            child: BouncyTouch(
              style: BouncyStyle.button,
              customScale: 0.88,
              onTap: onTap,
              child: Center(child: icon),
            ),
          ),
        );
      }

      return BouncyTouch(
        style: BouncyStyle.button,
        customScale: 0.90,
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.textColor.withValues(alpha: 0.08),
            boxShadow: [
              if (hasAlbumColors)
                BoxShadow(
                  color: widget.accentColor.withValues(
                    alpha: isDark ? 0.18 : 0.10,
                  ),
                  blurRadius: 10,
                  spreadRadius: 0,
                ),
            ],
          ),
          child: Center(child: icon),
        ),
      );
    }

    final backButton = buildDropletButton(
      icon: Icon(
        Icons.keyboard_arrow_down_rounded,
        color: widget.textColor,
        size: isLiquidGlass ? 26 : 28,
      ),
      onTap: widget.onDismiss,
    );

    final moreButton = buildDropletButton(
      icon: Icon(
        Icons.more_vert_rounded,
        color: widget.textColor,
        size: isLiquidGlass ? 20 : 22,
      ),
      onTap: () => widget.onOpenOptions?.call(),
    );

    final isInJam = ref.watch(isInJamSessionProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
      child: Row(
        children: [
          backButton,
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // "NOW PLAYING" header
                Text(
                  context.l10n.nowPlayingHeader.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: widget.secondaryTextColor.withValues(alpha: 0.70),
                    letterSpacing: 1.3,
                  ),
                ),
                // Stats for nerds or playlist title
                if (displaySubtext != null && displaySubtext.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  SizedBox(
                    height: 16,
                    child: GestureDetector(
                      onTap: () {
                        if (hasQueueTitle && hasStats) {
                           setState(() {
                             _showStatsInsteadOfTitle = !_showStatsInsteadOfTitle;
                           });
                        }
                      },
                      child: Text(
                        displaySubtext,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isDisplayingStats ? 10.5 : 11,
                          fontWeight: FontWeight.w600,
                          color: isDisplayingStats
                              ? widget.secondaryTextColor.withValues(alpha: 0.9)
                              : widget.textColor,
                          letterSpacing: isDisplayingStats ? 0.3 : 0.0,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isInJam) ...[
            JamIndicatorBadge(
              textColor: widget.textColor,
              accentColor: widget.accentColor,
            ),
            const SizedBox(width: 8),
          ],
          moreButton,
        ],
      ),
    );
  }

  /// Clean, bold, centered track title and artist
  Widget _buildTrackInfo() {
    final isPodcast = widget.track.isPodcast ||
        (widget.track.podcastId != null && widget.track.podcastId!.isNotEmpty);
    final canOpen = isPodcast || widget.track.artistId.isNotEmpty;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null) {
          if (details.primaryVelocity! < -200) {
            widget.playerService.skipToNext();
          } else if (details.primaryVelocity! > 200) {
            widget.playerService.skipToPrevious();
          }
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Song title
            SizedBox(
              height: 28,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.track.isExplicit)
                    ExplicitBadge(color: widget.textColor),
                  Flexible(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final painter = TextPainter(
                          text: TextSpan(
                            text: widget.track.title,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                              color: widget.textColor,
                            ),
                          ),
                          maxLines: 1,
                          textDirection: TextDirection.ltr,
                        )..layout();

                        if (painter.width > constraints.maxWidth) {
                          return Marquee(
                            text: widget.track.title,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                              color: widget.textColor,
                            ),
                            scrollAxis: Axis.horizontal,
                            blankSpace: 48.0,
                            velocity: 30.0,
                            pauseAfterRound: const Duration(seconds: 2),
                          );
                        }

                        return Text(
                          widget.track.title,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                            color: widget.textColor,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),

            // Artist name (tappable to open podcast or artist profile)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: canOpen
                  ? () {
                      if (isPodcast) {
                        PodcastScreen.open(
                          context,
                          podcastId: widget.track.podcastId!,
                          title: widget.track.album ?? widget.track.artist,
                          thumbnailUrl: widget.track.thumbnailUrl,
                        );
                      } else {
                        ArtistScreen.open(
                          context,
                          artistId: widget.track.artistId,
                          name: widget.track.artist,
                        );
                      }
                    }
                  : null,
              child: Text(
                widget.track.artist,
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  color: widget.secondaryTextColor,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Minimalist controls row: Shuffle, Previous, Play/Pause, Next, Repeat
  Widget _buildControlsRow(bool isLiquidGlass) {
    final isInJam = ref.watch(isInJamSessionProvider);
    final canControl = ref.watch(canControlJamPlaybackProvider);
    final canSkip = !isInJam || canControl;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Shuffle
          BouncyTouch(
            style: BouncyStyle.button,
            customScale: 0.90,
            onTap: () => widget.playerService.toggleShuffle(),
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Icon(
                Iconsax.shuffle,
                color: widget.state.shuffleEnabled
                    ? widget.accentColor
                    : widget.textColor.withValues(alpha: 0.55),
                size: 22,
              ),
            ),
          ),

          // Previous
          BouncyTouch(
            style: BouncyStyle.button,
            customScale: 0.90,
            onTap: canSkip ? () => widget.playerService.skipToPrevious() : null,
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Icon(
                Iconsax.previous,
                color: canSkip
                    ? widget.textColor
                    : widget.textColor.withValues(alpha: 0.3),
                size: 32,
              ),
            ),
          ),

          // Play / Pause
          AnimatedPlayPauseButton(
            isPlaying: widget.state.isPlaying,
            onTap: widget.state.isPlaying
                ? widget.playerService.pause
                : widget.playerService.play,
            size: 68.0,
            iconSize: 38.0,
            backgroundColor: widget.accentColor,
            isLiquidGlass: isLiquidGlass,
          ),

          // Next
          BouncyTouch(
            style: BouncyStyle.button,
            customScale: 0.90,
            onTap: canSkip ? () => widget.playerService.skipToNext() : null,
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Icon(
                Iconsax.next,
                color: canSkip
                    ? widget.textColor
                    : widget.textColor.withValues(alpha: 0.3),
                size: 32,
              ),
            ),
          ),

          // Repeat
          BouncyTouch(
            style: BouncyStyle.button,
            customScale: 0.90,
            onTap: () => widget.playerService.cycleLoopMode(),
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Icon(
                widget.state.loopMode == LoopMode.one
                    ? Iconsax.repeate_one
                    : Iconsax.repeate_music,
                color: widget.state.loopMode != LoopMode.off
                    ? widget.accentColor
                    : widget.textColor.withValues(alpha: 0.55),
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Standalone time readout widget that updates smoothly without rebuilding the parent view
class _RippleTimeReadout extends ConsumerStatefulWidget {
  final Duration totalDuration;
  final Duration? seekingPosition;
  final bool isPlaying;
  final Color textColor;
  final Color secondaryTextColor;

  const _RippleTimeReadout({
    required this.totalDuration,
    this.seekingPosition,
    required this.isPlaying,
    required this.textColor,
    required this.secondaryTextColor,
  });

  @override
  ConsumerState<_RippleTimeReadout> createState() => _RippleTimeReadoutState();
}

class _RippleTimeReadoutState extends ConsumerState<_RippleTimeReadout>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastKnownPosition = Duration.zero;
  DateTime _lastSyncTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    if (widget.isPlaying) {
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(_RippleTimeReadout oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    if (widget.seekingPosition == null && widget.isPlaying) {
      setState(() {});
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final streamPos =
        ref.watch(positionStreamProvider).valueOrNull ?? Duration.zero;
    if (streamPos != _lastKnownPosition) {
      _lastKnownPosition = streamPos;
      _lastSyncTime = DateTime.now();
    }

    Duration current;
    if (widget.seekingPosition != null) {
      current = widget.seekingPosition!;
    } else if (widget.isPlaying) {
      final elapsed = DateTime.now().difference(_lastSyncTime);
      final estimatedMs =
          _lastKnownPosition.inMilliseconds +
          elapsed.inMilliseconds.clamp(0, 1500);
      current = Duration(milliseconds: estimatedMs);
    } else {
      current = streamPos;
    }

    return Text.rich(
      TextSpan(
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        children: [
          TextSpan(
            text: _formatDuration(current),
            style: TextStyle(color: widget.textColor),
          ),
          TextSpan(
            text: '  |  ',
            style: TextStyle(
              color: widget.secondaryTextColor.withValues(alpha: 0.45),
              fontWeight: FontWeight.w400,
            ),
          ),
          TextSpan(
            text: _formatDuration(widget.totalDuration),
            style: TextStyle(color: widget.secondaryTextColor),
          ),
        ],
      ),
    );
  }
}
