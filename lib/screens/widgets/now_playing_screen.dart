import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:marquee/marquee.dart';
import '../../providers/providers.dart';
import '../../services/jams/jams_models.dart';
import '../../services/download_service.dart';
import '../../models/models.dart';
import '../../services/audio_player_service.dart' as player;
import '../../services/lyrics/lyrics_service.dart';
import '../../services/lyrics/lyrics_models.dart';
import '../../core/design_system/colors.dart';
import '../../core/l10n/app_localizations_x.dart';
import 'artist_screen.dart';
import 'album_screen.dart' show AlbumScreen;
import 'playlist_screen.dart' show PlaylistScreen;
import 'track_options_sheet.dart';
import 'lyrics_view.dart';
import 'ytm_drawer.dart';
import 'jams_panel.dart';
import 'home_shelves.dart' show TrackListShelf;

/// Progress bar widget that only rebuilds on position changes (isolated)
class _NowPlayingProgressBar extends ConsumerWidget {
  final Duration? duration;
  final Color textColor;
  final Color secondaryColor;
  final Color accentColor;

  const _NowPlayingProgressBar({
    required this.duration,
    required this.textColor,
    required this.secondaryColor,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position =
        ref.watch(positionStreamProvider).valueOrNull ?? Duration.zero;
    final playerService = ref.watch(audioPlayerServiceProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: accentColor,
              inactiveTrackColor: textColor.withValues(alpha: 0.2),
              thumbColor: textColor,
              overlayColor: accentColor.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: position.inMilliseconds.toDouble().clamp(
                0,
                (duration?.inMilliseconds ?? 1).toDouble(),
              ),
              min: 0,
              max: (duration?.inMilliseconds ?? 0) > 0
                  ? duration!.inMilliseconds.toDouble()
                  : 1,
              onChanged: (value) {
                playerService.seek(Duration(milliseconds: value.toInt()));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(position),
                  style: TextStyle(fontSize: 12, color: secondaryColor),
                ),
                Text(
                  _formatDuration(duration ?? Duration.zero),
                  style: TextStyle(fontSize: 12, color: secondaryColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

// NOTE: albumColorsProvider is now defined in music_providers.dart for app-wide access

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
  static const double _syncedLyricPreviewHeight = 72;
  late AnimationController _colorAnimController;
  late TabController _tabController;
  late PageController _pageController;
  late PageController _albumArtPageController; // For swiping album art
  final GlobalKey<YTMDrawerState> _drawerKey = GlobalKey<YTMDrawerState>();
  AlbumColors _currentColors = AlbumColors.defaultColors();
  AlbumColors _targetColors = AlbumColors.defaultColors();
  String? _lastLyricsTrackId;
  String? _lastRelatedTrackId; // Cache key for related tracks
  Future<WatchRelatedContent>? _relatedContentFuture;
  // ignore: unused_field - reserved for future panel toggle features
  bool _showLyrics = false;
  // ignore: unused_field - reserved for future panel toggle features
  bool _showQueue = false;
  bool _isDrawerExpanded = false; // Track drawer state
  bool _initialColorLoad = true;
  bool _isAlbumSwipeNavigationInProgress = false;
  int? _lastAlbumArtSyncedIndex;

  @override
  void initState() {
    super.initState();
    _colorAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _colorAnimController.addListener(() {
      if (mounted) setState(() {});
    });
    _colorAnimController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _currentColors = _targetColors;
      }
    });

    // Tab controller for bottom tabs
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _showQueue = _tabController.index == 0;
          _showLyrics = _tabController.index == 1;
          // index 2 = Related
        });
      }
    });

    // Page controller for swiping content
    _pageController = PageController(initialPage: 0);

    // Album art page controller follows actual queue index
    _albumArtPageController = PageController(initialPage: 0);
  }

  @override
  void dispose() {
    _colorAnimController.dispose();
    _tabController.dispose();
    _pageController.dispose();
    _albumArtPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playbackState = ref.watch(playbackStateProvider);
    final playerService = ref.watch(audioPlayerServiceProvider);
    final albumColors = ref.watch(albumColorsProvider);
    final currentTrack = ref.watch(currentTrackProvider);
    final currentQueueIndex = playerService.currentIndex;

    if (currentQueueIndex >= 0 &&
        currentQueueIndex != _lastAlbumArtSyncedIndex) {
      _lastAlbumArtSyncedIndex = currentQueueIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_albumArtPageController.hasClients) return;
        final activePage =
            (_albumArtPageController.page ?? currentQueueIndex.toDouble())
                .round();
        if (activePage == currentQueueIndex) return;

        _isAlbumSwipeNavigationInProgress = true;
        unawaited(
          _albumArtPageController
              .animateToPage(
                currentQueueIndex,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
              )
              .whenComplete(() {
                if (mounted) {
                  _isAlbumSwipeNavigationInProgress = false;
                }
              }),
        );
      });
    }

    // First time opening - trigger color extraction immediately
    if (_initialColorLoad && currentTrack != null) {
      _initialColorLoad = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(albumColorsProvider.notifier).updateForTrack(currentTrack);
        }
      });
    }

    // Track change for lyrics fetch
    final trackId = currentTrack?.id;
    final isNewTrack = trackId != _lastLyricsTrackId && currentTrack != null;
    if (isNewTrack) {
      _lastLyricsTrackId = trackId;

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
                ),
              );
        }
      });
    }

    // Animate when new colors arrive (not default)
    if (albumColors != _targetColors && !albumColors.isDefault) {
      _targetColors = albumColors;

      // Start animation from current to target
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _colorAnimController.forward(from: 0);
        }
      });
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

        return Scaffold(
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
              surfaceColor: colors.surface, // Solid background for drawer
              initiallyExpanded: _isDrawerExpanded,
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
              },
              // Position-based tab selection (left=UP NEXT, center=LYRICS, right=RELATED)
              onTabFromPosition: (tabIndex) {
                setState(() {
                  _tabController.animateTo(tabIndex);
                  _showQueue = tabIndex == 0;
                  _showLyrics = tabIndex == 1;
                });
              },
              // Now Playing content (shown when collapsed)
              nowPlayingContent: SafeArea(
                top: true,
                bottom: false,
                child: _buildFullAlbumView(
                  track,
                  state,
                  playerService,
                  textColor,
                  secondaryTextColor,
                  accentColor,
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
              upNextContent: _buildTabContent(
                textColor,
                secondaryTextColor,
                colors.surface,
              ),
            ),
          ),
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
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
    Color accentColor,
  ) {
    return Column(
      children: [
        // Top bar
        _buildTopBar(textColor, secondaryTextColor),

        // Album art
        _buildAlbumArt(track, accentColor),

        Expanded(
          child: Column(
            children: [
              // Current synced lyric line (shown only when synced lyrics are available)
              _buildSyncedLyricPreview(textColor),

              // Track info
              _buildTrackInfo(
                track,
                textColor,
                secondaryTextColor,
                accentColor,
              ),

              // Progress bar
              _NowPlayingProgressBar(
                duration: state.duration,
                textColor: textColor,
                secondaryColor: secondaryTextColor,
                accentColor: accentColor,
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
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 56,
              height: 56,
              child: track.thumbnailUrl != null
                  ? CachedNetworkImage(
                      imageUrl: track.thumbnailUrl!,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      color: accentColor.withValues(alpha: 0.3),
                      child: Icon(Iconsax.music, color: textColor),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          // Title and artist
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 2),
                _buildArtistLink(
                  track,
                  style: TextStyle(
                    fontSize: 13,
                    color: textColor.withValues(alpha: 0.7),
                  ),
                  maxLines: 1,
                  enableMarquee: false,
                ),
              ],
            ),
          ),
          // Play/pause button
          IconButton(
            onPressed: state.isPlaying
                ? playerService.pause
                : playerService.play,
            icon: Icon(
              state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: textColor,
              size: 32,
            ),
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
            child: ReorderableListView.builder(
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
              onReorder: (oldIndex, newIndex) {
                // Don't allow reordering the loading indicator
                if (oldIndex >= queue.length || newIndex > queue.length) return;
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

                return RepaintBoundary(
                  key: ValueKey(track.id + index.toString()),
                  child: SizedBox(
                    height: 72, // Fixed height for performance
                    child: ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: track.thumbnailUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: track.thumbnailUrl!,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 96,
                                  memCacheHeight: 96,
                                  fadeInDuration: Duration.zero,
                                  fadeOutDuration: Duration.zero,
                                )
                              : Container(color: Colors.grey),
                        ),
                      ),
                      title: Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCurrent ? textColor : secondaryColor,
                          fontWeight: isCurrent
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        context.trackSubtitle(
                          track.artist,
                          _formatDuration(track.duration),
                        ),
                        maxLines: 1,
                        style: TextStyle(color: secondaryColor, fontSize: 12),
                      ),
                      trailing: ReorderableDragStartListener(
                        index: index,
                        child: Icon(Icons.drag_handle, color: secondaryColor),
                      ),
                      onTap: () {
                        // Play from queue at this index
                        ref
                            .read(audioPlayerServiceProvider)
                            .playQueue(queue, startIndex: index);
                      },
                    ),
                  ),
                ); // Close RepaintBoundary
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
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: jamQueue.length,
                  onReorder: canControlPlayback
                      ? (oldIndex, newIndex) =>
                            _reorderJamQueue(oldIndex, newIndex)
                      : (_, _) {},
                  buildDefaultDragHandles: false,
                  itemBuilder: (context, index) {
                    final queueItem = jamQueue[index];
                    final track = queueItem.track;
                    final addedByName = getAddedByName(queueItem.addedBy);

                    return RepaintBoundary(
                      key: ValueKey('jam_${track.videoId}_$index'),
                      child: SizedBox(
                        height: 72,
                        child: ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: SizedBox(
                              width: 48,
                              height: 48,
                              child: track.thumbnailUrl != null
                                  ? CachedNetworkImage(
                                      imageUrl: track.thumbnailUrl!,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 96,
                                      memCacheHeight: 96,
                                      fadeInDuration: Duration.zero,
                                      fadeOutDuration: Duration.zero,
                                    )
                                  : Container(color: Colors.grey),
                            ),
                          ),
                          title: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: textColor),
                          ),
                          subtitle: Text(
                            context.metadataLine([
                              track.artist,
                              l10n.addedByUser(addedByName),
                            ]),
                            maxLines: 1,
                            style: TextStyle(
                              color: secondaryColor,
                              fontSize: 12,
                            ),
                          ),
                          trailing: canControlPlayback
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
                          onTap: canControlPlayback
                              ? () => _playFromJamQueue(index)
                              : null,
                        ),
                      ),
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
      // When dragging down, the newIndex needs adjustment
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      await jamsService.reorderQueue(oldIndex, newIndex);
    }
  }

  /// Tab content switcher - shows Queue, Lyrics, or Related based on selected tab
  Widget _buildTabContent(
    Color textColor,
    Color secondaryColor,
    Color surfaceColor,
  ) {
    switch (_tabController.index) {
      case 0: // UP NEXT
        return _buildQueueContent(textColor, secondaryColor, surfaceColor);
      case 1: // LYRICS
        return _buildLyricsView(ref);
      case 2: // RELATED
        return _buildRelatedContent(textColor, secondaryColor);
      default:
        return _buildQueueContent(textColor, secondaryColor, surfaceColor);
    }
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
          return const Center(child: CircularProgressIndicator());
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
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
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
    final ytService = ref.read(youtubeServiceProvider);
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

    final genericTracks = await ytService.getRelatedTracks(
      currentTrack.id,
      limit: 20,
    );
    final filteredGeneric = genericTracks
        .where((track) => track.id != currentTrack.id)
        .take(20)
        .toList();

    if (filteredGeneric.isNotEmpty) {
      return WatchRelatedContent(
        shelves: [
          HomeShelf(
            id: 'related_generic_${currentTrack.id}',
            title: relatedTabTitle,
            type: HomeShelfType.unknown,
            items: filteredGeneric.map(_trackToShelfItem).toList(),
          ),
        ],
      );
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
              height: primaryType == HomeShelfItemType.artist ? 200 : 220,
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
          onTap: track == null
              ? null
              : () {
                  ref
                      .read(audioPlayerServiceProvider)
                      .playQueue(
                        tracks,
                        startIndex: math.min(index, tracks.length - 1),
                      );
                },
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

  Widget _buildAboutArtistSection(
    WatchRelatedContent relatedContent,
    Color textColor,
    Color secondaryColor,
  ) {
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: textColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              relatedContent.aboutDescription!,
              style: TextStyle(
                color: secondaryColor,
                fontSize: 14,
                height: 1.45,
              ),
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
      case HomeShelfItemType.playlist:
      case HomeShelfItemType.mix:
        final playlistId = item.playlistId ?? item.navigationId ?? item.id;
        PlaylistScreen.open(
          context,
          playlistId: playlistId,
          title: item.title,
          thumbnailUrl: item.thumbnailUrl,
        );
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

  Widget _buildTopBar(Color textColor, Color secondaryColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () {
              // Use Navigator.pop for Hero animation on close
              Navigator.of(context).pop();
              widget.onClose?.call();
            },
            icon: Icon(Icons.keyboard_arrow_down, color: textColor, size: 32),
          ),
          Column(
            children: [
              Text(
                context.l10n.nowPlayingHeader,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: secondaryColor,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          IconButton(
            onPressed: () {
              final track = ref.read(currentTrackProvider);
              if (track != null) {
                TrackOptionsSheet.show(context, track);
              }
            },
            icon: Icon(Icons.more_vert, color: textColor),
          ),
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
    if (pageIndex < 0 || pageIndex >= queueLength) return;
    if (pageIndex == currentIndex) return;
    playerService.skipToIndex(pageIndex);
  }

  Widget _buildAlbumArt(Track track, Color accentColor) {
    final playerService = ref.watch(audioPlayerServiceProvider);
    final queue = playerService.queue;
    final currentIndex = playerService.currentIndex;

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.of(context).size.width;
        final maxHeight = MediaQuery.of(context).size.height * 0.42;

        // Constrain to max height while staying square
        final artSize = math.min(
          screenWidth - 54, // horizontal padding * 2
          maxHeight,
        );

        return SizedBox(
          height: maxHeight,
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: SizedBox(
                width: artSize,
                height: artSize,
                child: Stack(
                  children: [
                    // Swipeable album art using PageView
                    PageView.builder(
                      controller: _albumArtPageController,
                      clipBehavior: Clip.none,
                      physics: const BouncingScrollPhysics(),
                      itemCount: queue.isEmpty ? 1 : queue.length,
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
                            (queue.isNotEmpty &&
                                pageIndex >= 0 &&
                                pageIndex < queue.length)
                            ? queue[pageIndex]
                            : track;

                        return AnimatedBuilder(
                          animation: _albumArtPageController,
                          builder: (context, child) {
                            final fallbackPage = currentIndex >= 0
                                ? currentIndex.toDouble()
                                : 0.0;
                            final page = _albumArtPageController.hasClients
                                ? (_albumArtPageController.page ?? fallbackPage)
                                : fallbackPage;
                            final delta = (pageIndex - page).abs().clamp(
                              0.0,
                              1.0,
                            );
                            final scale = (1.0 - (delta * 0.08)).clamp(
                              0.92,
                              1.0,
                            );
                            final opacity = (1.0 - (delta * 0.28)).clamp(
                              0.72,
                              1.0,
                            );

                            return Transform.scale(
                              scale: scale.toDouble(),
                              child: Opacity(
                                opacity: opacity.toDouble(),
                                child: child,
                              ),
                            );
                          },
                          child: Hero(
                            tag: pageIndex == currentIndex
                                ? 'album-art-${track.id}'
                                : 'album-art-side-${displayTrack.id}-$pageIndex',
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
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
                                borderRadius: BorderRadius.circular(12),
                                child: _buildAlbumArtContent(
                                  displayTrack,
                                  accentColor,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
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

  Widget _buildLyricsView(WidgetRef ref) {
    // Get current position for synced lyrics
    final position =
        ref.watch(positionStreamProvider).valueOrNull ?? Duration.zero;
    return LyricsView(currentPosition: position);
  }

  Widget _buildAlbumArtContent(Track? displayTrack, Color accentColor) {
    final localAudioPath = displayTrack?.localFilePath?.trim();
    if (localAudioPath != null && localAudioPath.isNotEmpty) {
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
    }

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

  Widget _buildSyncedLyricPreview(Color textColor) {
    final lyricsState = ref.watch(lyricsProvider);
    final result = lyricsState.currentLyrics;

    if (result == null || !result.hasSyncedLyrics) {
      return const SizedBox(height: _syncedLyricPreviewHeight);
    }

    final position =
        ref.watch(positionStreamProvider).valueOrNull ?? Duration.zero;
    final positionMs = position.inMilliseconds;
    final lines = result.lines!;

    int currentIdx = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].timeInMs <= positionMs) {
        currentIdx = i;
      } else {
        break;
      }
    }

    if (currentIdx < 0) {
      return const SizedBox(height: _syncedLyricPreviewHeight);
    }

    final text = lines[currentIdx].text.trim();
    if (text.isEmpty) {
      return const SizedBox(height: _syncedLyricPreviewHeight);
    }

    return SizedBox(
      height: _syncedLyricPreviewHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 6, 24, 6),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 380),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOutCubic,
          transitionBuilder: (child, animation) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.06),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            );
          },
          layoutBuilder: (currentChild, previousChildren) {
            return currentChild ?? const SizedBox.shrink();
          },
          child: Align(
            key: ValueKey('lyric_$currentIdx'),
            alignment: Alignment.centerLeft,
            child: Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.clip,
              softWrap: true,
              textAlign: TextAlign.left,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: textColor.withValues(alpha: 0.95),
                height: 1.15,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrackInfo(
    Track track,
    Color textColor,
    Color secondaryColor,
    Color accentColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Marquee for long titles
                SizedBox(
                  height: 26,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final textPainter = TextPainter(
                        text: TextSpan(
                          text: track.title,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        maxLines: 1,
                        textDirection: TextDirection.ltr,
                      )..layout();

                      // Only use marquee if text overflows
                      if (textPainter.width > constraints.maxWidth) {
                        return Marquee(
                          text: track.title,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                          scrollAxis: Axis.horizontal,
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 4),
                // Marquee for long artist names
                SizedBox(
                  height: 22,
                  child: _buildArtistLink(
                    track,
                    style: TextStyle(fontSize: 16, color: secondaryColor),
                    maxLines: 1,
                    enableMarquee: true,
                  ),
                ),
              ],
            ),
          ),
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
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    Iconsax.tick_circle5,
                    size: 20,
                    color: Colors.green,
                  ),
                );
              }

              if (progress != null) {
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
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
          // Like button
          Builder(
            builder: (context) {
              final isLiked = ref.watch(isTrackLikedProvider(track.id));
              return IconButton(
                onPressed: () async {
                  // Use explicit like/unlike based on current state
                  if (isLiked) {
                    // Unlike: remove from local state and mark as explicitly unliked
                    ref.read(likedSongsProvider.notifier).unlike(track.id);
                    ref
                        .read(explicitlyUnlikedIdsProvider.notifier)
                        .update((state) => {...state, track.id});
                  } else {
                    // Like: add to local state and remove from explicitly unliked
                    ref.read(likedSongsProvider.notifier).like(track);
                    ref
                        .read(explicitlyUnlikedIdsProvider.notifier)
                        .update(
                          (state) =>
                              state.where((id) => id != track.id).toSet(),
                        );
                  }

                  // Also sync to YT Music if logged in
                  final authState = ref.read(ytMusicAuthStateProvider);
                  if (authState.isLoggedIn) {
                    final likeAction = ref.read(ytMusicLikeActionProvider);
                    if (isLiked) {
                      await likeAction.unlike(track.id);
                    } else {
                      await likeAction.like(track.id);
                    }
                    // Refresh liked songs from YT Music
                    ref.invalidate(ytMusicLikedSongsProvider);
                  }
                },
                icon: Icon(
                  isLiked ? Iconsax.heart5 : Iconsax.heart,
                  color: isLiked ? Colors.red : textColor,
                  size: 26,
                ),
              );
            },
          ),
          // Add to Playlist button - opens track options sheet
          IconButton(
            onPressed: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (_) => TrackOptionsSheet(track: track),
              );
            },
            icon: Icon(Iconsax.add_square, color: textColor, size: 24),
          ),
          // Jams button - listen together
          _buildJamsButton(textColor, accentColor),
        ],
      ),
    );
  }

  Widget _buildArtistLink(
    Track track, {
    required TextStyle style,
    required int maxLines,
    required bool enableMarquee,
  }) {
    final canOpenArtist = track.artistId.isNotEmpty;

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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  blankSpace: 60.0,
                  velocity: 30.0,
                  pauseAfterRound: const Duration(seconds: 2),
                  startPadding: 0.0,
                );
              }

              return Text(
                track.artist,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: style,
              );
            },
          )
        : Text(
            track.artist,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: style,
          );

    if (!canOpenArtist) {
      return artistLabel;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openArtist(track),
      child: artistLabel,
    );
  }

  void _openArtist(Track track) {
    if (track.artistId.isEmpty) return;
    ArtistScreen.open(context, artistId: track.artistId, name: track.artist);
  }

  /// Jams icon button with active session indicator
  Widget _buildJamsButton(Color textColor, Color accentColor) {
    final isInSession = ref.watch(isInJamSessionProvider);
    final session = ref.watch(currentJamSessionProvider).valueOrNull;

    return Stack(
      children: [
        IconButton(
          onPressed: () {
            final albumColors = ref.read(albumColorsProvider);
            final isDark = Theme.of(context).brightness == Brightness.dark;
            // Use album colors in dark mode, plain white in light mode
            final bgColor = isDark
                ? albumColors.backgroundPrimary
                : InzxColors.background;
            final txtColor = isDark
                ? albumColors.onBackground
                : InzxColors.textPrimary;
            JamsPanel.show(
              context,
              backgroundColor: bgColor,
              textColor: txtColor,
              accentColor: albumColors.accent,
            );
          },
          icon: Icon(
            Iconsax.profile_2user,
            color: isInSession ? accentColor : textColor,
            size: 24,
          ),
          tooltip: context.l10n.jams,
        ),
        // Active session indicator
        if (isInSession && session != null)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black, width: 1),
              ),
            ),
          ),
        // Participant count badge
        if (isInSession && session != null && session.participantCount > 1)
          Positioned(
            right: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${session.participantCount}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildControls(
    player.PlaybackState state,
    player.AudioPlayerService playerService,
    Color textColor,
    Color accentColor,
  ) {
    // Check if in Jam and has control permission
    final isInJam = ref.watch(isInJamSessionProvider);
    final canControl = ref.watch(canControlJamPlaybackProvider);
    final canSkip =
        !isInJam || canControl; // Can skip if not in Jam or has permission

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Shuffle
          IconButton(
            onPressed: () => playerService.toggleShuffle(),
            icon: Icon(
              Iconsax.shuffle,
              color: state.shuffleEnabled
                  ? accentColor
                  : textColor.withValues(alpha: 0.6),
              size: 24,
            ),
          ),
          // Previous
          IconButton(
            onPressed: canSkip ? playerService.skipToPrevious : null,
            icon: Icon(
              Iconsax.previous,
              color: canSkip ? textColor : textColor.withValues(alpha: 0.3),
              size: 36,
            ),
          ),
          // Play/Pause - always allowed (sync controller handles it)
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: accentColor,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: state.isPlaying
                  ? playerService.pause
                  : playerService.play,
              icon: Icon(
                state.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 42,
              ),
            ),
          ),
          // Next
          IconButton(
            onPressed: canSkip ? playerService.skipToNext : null,
            icon: Icon(
              Iconsax.next,
              color: canSkip ? textColor : textColor.withValues(alpha: 0.3),
              size: 36,
            ),
          ),
          // Repeat
          IconButton(
            onPressed: () => playerService.cycleLoopMode(),
            icon: Icon(
              state.loopMode == LoopMode.one
                  ? Iconsax.repeate_one
                  : Iconsax.repeate_music,
              color: state.loopMode != LoopMode.off
                  ? accentColor
                  : textColor.withValues(alpha: 0.6),
              size: 24,
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
