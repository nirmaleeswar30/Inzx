import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marquee/marquee.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../core/providers/theme_provider.dart';
import '../../services/audio_player_service.dart' as player;
import '../../services/lyrics/lyrics_service.dart';
import '../../services/lyrics/lyrics_models.dart';
import '../../core/design_system/design_system.dart';
import 'artist_screen.dart';
import 'podcast_screen.dart' show PodcastScreen;
import 'jam_indicator_badge.dart';
import 'explicit_badge.dart';

/// The 'Cinematic' Now Playing screen layout.
/// Features a full-width uncropped album artwork spanning the top half of the screen
/// from the very top pixel (no gap), an ultra-smooth fade into the background,
/// and song metadata & playback controls strictly UNDER the album cover.
class EdgeNowPlayingView extends ConsumerStatefulWidget {
  final Track track;
  final player.PlaybackState state;
  final player.AudioPlayerService playerService;
  final Color textColor;
  final Color secondaryTextColor;
  final Color accentColor;
  final Color backgroundColor;
  final Widget albumArt;
  final Widget? ambientArt;
  final VoidCallback onDismiss;
  final VoidCallback? onOpenOptions;
  final Widget tabsWidget;
  final VoidCallback? onToggleLike;
  final VoidCallback? onDoubleTapLike;
  final Widget? heartOverlay;
  final bool isLiked;
  final Widget? lyricPreview;
  final Widget? progressBar;
  final Widget? controlsWidget;
  final bool forceFallbackGradient;

  const EdgeNowPlayingView({
    super.key,
    required this.track,
    required this.state,
    required this.playerService,
    required this.textColor,
    required this.secondaryTextColor,
    required this.accentColor,
    required this.backgroundColor,
    required this.albumArt,
    this.ambientArt,
    required this.onDismiss,
    this.onOpenOptions,
    required this.tabsWidget,
    this.onToggleLike,
    this.onDoubleTapLike,
    this.heartOverlay,
    this.isLiked = false,
    this.lyricPreview,
    this.progressBar,
    this.controlsWidget,
    this.forceFallbackGradient = false,
  });

  @override
  ConsumerState<EdgeNowPlayingView> createState() => _EdgeNowPlayingViewState();
}

class _EdgeNowPlayingViewState extends ConsumerState<EdgeNowPlayingView> {
  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    final lyricsState = ref.watch(lyricsProvider);
    final isFetchingLyrics =
        lyricsState.currentStatus.state == LyricsProviderState.fetching ||
        lyricsState.currentStatus.state == LyricsProviderState.idle;
    final hasSyncedLyrics =
        lyricsState.currentLyrics?.hasSyncedLyrics ?? false;
    final showLyricsBelowArt = ref.watch(showLyricsBelowAlbumArtProvider);
    final hasLyricsPreview =
        showLyricsBelowArt && (isFetchingLyrics || hasSyncedLyrics);

    final playbackState =
        ref.watch(playbackStateProvider).valueOrNull ?? widget.state;
    final showNerdStats = playbackState.showNerdStats;
    final statsSummary = playbackState.qualityInfo;
    final hasStats = showNerdStats && statsSummary.isNotEmpty;
    final isInJam = ref.watch(isInJamSessionProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final availableHeight = constraints.maxHeight;

        // Dynamic top half height: calibrated so the album cover dominates the upper screen,
        // while leaving ample vertical room below for title, scrubber, controls, and tabs.
        final double artHeight;
        if (availableHeight < 680) {
          artHeight = (availableHeight * 0.42).clamp(240.0, 290.0);
        } else if (availableHeight < 800) {
          artHeight = (availableHeight * 0.46).clamp(290.0, 370.0);
        } else {
          artHeight = (availableHeight * 0.48).clamp(340.0, availableHeight * 0.50);
        }

        return Container(
          width: availableWidth,
          height: availableHeight,
          color: widget.backgroundColor,
          child: Stack(
            children: [
              // --- AMBIENT REFLECTION BACKGROUND ---
              if (widget.ambientArt != null && !widget.forceFallbackGradient)
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.85, // Stronger opacity for more vivid reflection
                    child: Transform.scale(
                      scale: 1.5, // Scale it up normally to fill and bleed
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80), // Massive blur
                        child: widget.ambientArt!,
                      ),
                    ),
                  ),
                ),

              // --- FOREGROUND CONTENT ---
              Column(
                children: [
                  // 1. TOP HALF: Edge-to-Edge Artwork starting from absolute top (NO GAP)
              // with seamless ShaderMask bottom fade into background
              SizedBox(
                width: availableWidth,
                height: artHeight,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragEnd: (details) {
                    // Swipe down on artwork to dismiss
                    if (details.primaryVelocity != null &&
                        details.primaryVelocity! > 250) {
                      widget.onDismiss();
                    }
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Full-bleed artwork with smooth alpha roll-off only at the bottom rim
                      ShaderMask(
                        shaderCallback: (rect) {
                          return const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white,
                              Colors.white,
                              Color(0xD9FFFFFF), // 85%
                              Color(0x80FFFFFF), // 50%
                              Color(0x26FFFFFF), // 15%
                              Colors.transparent,
                            ],
                            stops: [0.0, 0.70, 0.85, 0.92, 0.97, 1.0], // Smoother transition
                          ).createShader(rect);
                        },
                        blendMode: BlendMode.dstIn,
                        child: SizedBox(
                          width: availableWidth,
                          height: artHeight,
                          child: widget.albumArt,
                        ),
                      ),

                      // Ambient color bleed softly dissolving only at the very bottom rim
                      // (Only apply if we don't have ambientArt filling the background)
                      if (widget.ambientArt == null || widget.forceFallbackGradient)
                        Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: artHeight * 0.10,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  widget.backgroundColor.withValues(alpha: 0.0),
                                  widget.backgroundColor.withValues(alpha: 0.35),
                                  widget.backgroundColor.withValues(alpha: 0.75),
                                  widget.backgroundColor,
                                ],
                                stops: const [0.0, 0.40, 0.75, 1.0],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Subtle Stats for Nerds plain text at bottom center of album art
                      if (hasStats)
                        Positioned(
                          left: 24,
                          right: 24,
                          bottom: 10,
                          child: IgnorePointer(
                            child: Center(
                              child: _buildNerdStatsText(statsSummary),
                            ),
                          ),
                        ),

                      // Popping heart animation (for double-tap to like)
                      if (widget.heartOverlay != null)
                        IgnorePointer(
                          child: Center(child: widget.heartOverlay!),
                        ),

                      // Floating Jam Indicator Badge when in active Jam
                      if (isInJam)
                        Positioned(
                          top: MediaQuery.paddingOf(context).top + 12,
                          right: 16,
                          child: JamIndicatorBadge(
                            textColor: Colors.white,
                            accentColor: widget.accentColor,
                            backgroundColor: Colors.black.withValues(alpha: 0.6),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // 2. BOTTOM HALF: Content positioned strictly UNDER the album cover
              Expanded(
                child: Column(
                  children: [
                    const Spacer(flex: 1),

                    // Song title & artist with horizontal frosted glass three-dot options menu
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: _buildTrackInfoRow(),
                    ),

                    // Optional live synced lyrics preview
                    if (hasLyricsPreview && widget.lyricPreview != null) ...[
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: widget.lyricPreview!,
                      ),
                      const SizedBox(height: 4),
                    ] else ...[
                      const Spacer(flex: 1),
                    ],

                    // Progress bar / linear scrubber (same horizontal width as default now playing screen)
                    if (widget.progressBar != null)
                      widget.progressBar!,

                    const SizedBox(height: 20),

                    // Main playback controls row (same horizontal width as default now playing screen)
                    if (widget.controlsWidget != null)
                      widget.controlsWidget!,

                    const Spacer(flex: 2),

                    // Drawer tabs (UP NEXT | LYRICS | RELATED)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: widget.tabsWidget,
                    ),

                    SizedBox(height: max(10.0, bottomPadding + 2)),
                  ],
                ),
              ),
            ],
          ), // Close Column
            ],
          ), // Close Stack
        );
      },
    );
  }

  /// Track title and artist with horizontal frosted glass three-dot options menu
  Widget _buildTrackInfoRow() {
    final canOpen = widget.track.isPodcast ||
        (widget.track.podcastId != null &&
            widget.track.podcastId!.isNotEmpty) ||
        widget.track.artistId.isNotEmpty;
    final isPodcast = widget.track.isPodcast ||
        (widget.track.podcastId != null &&
            widget.track.podcastId!.isNotEmpty);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Title & Artist
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title with Marquee on overflow
              SizedBox(
                height: 28,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (widget.track.isExplicit)
                      ExplicitBadge(color: widget.textColor),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final painter = TextPainter(
                      text: TextSpan(
                        text: widget.track.title,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
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
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
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
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: widget.textColor,
                      ),
                    );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              // Artist with Marquee on overflow
              SizedBox(
                height: 22,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final artistStyle = TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: widget.secondaryTextColor,
                      letterSpacing: 0.1,
                    );

                    final painter = TextPainter(
                      text: TextSpan(
                        text: widget.track.artist,
                        style: artistStyle,
                      ),
                      maxLines: 1,
                      textDirection: TextDirection.ltr,
                    )..layout();

                    final isOverflowing = painter.width > constraints.maxWidth;

                    final textWidget = isOverflowing
                        ? Marquee(
                            text: widget.track.artist,
                            style: artistStyle,
                            scrollAxis: Axis.horizontal,
                            blankSpace: 40.0,
                            velocity: 25.0,
                            pauseAfterRound: const Duration(seconds: 2),
                          )
                        : Text(
                            widget.track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: artistStyle,
                          );

                    return GestureDetector(
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
                      child: textWidget,
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 12),

        // Three-dot Options Button (horizontal with frosted glass background)
        BouncyTouch(
          style: BouncyStyle.button,
          customScale: 0.88,
          onTap: widget.onOpenOptions,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.textColor.withValues(alpha: 0.10),
                  border: Border.all(
                    color: widget.textColor.withValues(alpha: 0.15),
                    width: 1.0,
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.more_horiz_rounded,
                    color: widget.textColor.withValues(alpha: 0.85),
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Subtle plain text displaying audio stream quality & source at the bottom center of the album cover
  Widget _buildNerdStatsText(String statsSummary) {
    return Text(
      statsSummary,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w500,
        color: widget.textColor.withValues(alpha: 0.55),
        letterSpacing: 0.5,
        shadows: [
          Shadow(
            color: Colors.black.withValues(alpha: 0.50),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }
}
