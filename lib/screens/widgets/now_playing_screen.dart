import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:just_audio/just_audio.dart';
import 'package:marquee/marquee.dart';
import '../../providers/providers.dart';
import '../../providers/jams_provider.dart';
import '../../services/jams/jams_models.dart';
import '../../services/download_service.dart';
import '../../models/models.dart';
import '../../services/audio_player_service.dart' as player;
import '../../services/album_color_extractor.dart';
import '../../services/lyrics/lyrics_service.dart';
import '../../services/lyrics/lyrics_models.dart';
import 'track_options_sheet.dart';
import 'lyrics_view.dart';
import 'ytm_drawer.dart';
import 'jams_panel.dart';

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
  late AnimationController _colorAnimController;
  late TabController _tabController;
  late PageController _pageController;
  final GlobalKey<YTMDrawerState> _drawerKey = GlobalKey<YTMDrawerState>();
  AlbumColors _currentColors = AlbumColors.defaultColors();
  AlbumColors _targetColors = AlbumColors.defaultColors();
  String? _lastUrl;
  String? _lastRelatedTrackId; // Cache key for related tracks
  Future<List<Track>>? _relatedTracksFuture; // Cached future for related tracks
  // ignore: unused_field - reserved for future panel toggle features
  bool _showLyrics = false;
  // ignore: unused_field - reserved for future panel toggle features
  bool _showQueue = false;
  bool _isDrawerExpanded = false; // Track drawer state
  bool _initialColorLoad = true;

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
  }

  @override
  void dispose() {
    _colorAnimController.dispose();
    _tabController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playbackState = ref.watch(playbackStateProvider);
    final playerService = ref.watch(audioPlayerServiceProvider);
    final albumColors = ref.watch(albumColorsProvider);
    final currentTrack = ref.watch(currentTrackProvider);

    // First time opening - trigger color extraction immediately
    if (_initialColorLoad && currentTrack != null) {
      _initialColorLoad = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(albumColorsProvider.notifier).updateForTrack(currentTrack);
        }
      });
    }

    // Track URL change for lyrics fetch
    final trackUrl = currentTrack?.thumbnailUrl;
    final isNewTrack = trackUrl != _lastUrl && currentTrack != null;
    if (isNewTrack) {
      _lastUrl = trackUrl;

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
    final colors = AlbumColors.lerp(
      _currentColors,
      _targetColors,
      _colorAnimController.value,
    );

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
      error: (_, __) => const SizedBox.shrink(),
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

        // Album art (tap to show lyrics)
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                _showLyrics = true;
                _tabController.animateTo(1); // Switch to LYRICS tab
              });
            },
            child: _buildAlbumArt(track, accentColor),
          ),
        ),

        // Track info
        _buildTrackInfo(track, textColor, secondaryTextColor, accentColor),

        // Progress bar
        _NowPlayingProgressBar(
          duration: state.duration,
          textColor: textColor,
          secondaryColor: secondaryTextColor,
          accentColor: accentColor,
        ),

        // Controls
        _buildControls(state, playerService, textColor, accentColor),

        // Gap between controls and tabs
        const SizedBox(height: 34),

        // Bottom tabs
        _buildBottomTabs(textColor, accentColor),

        const SizedBox(height: 16),
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
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: textColor.withValues(alpha: 0.7),
                  ),
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
      queueLabel = 'Jam Queue';
      queueIcon = Iconsax.profile_2user;
    } else if (isRadioMode) {
      queueLabel = 'Radio Queue';
      queueIcon = Icons.all_inclusive;
    } else {
      queueLabel = 'Queue';
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
                    'Playing from',
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
                  label: Text('Save', style: TextStyle(color: textColor)),
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
                                  'Loading more tracks...',
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
                                  'Scroll for more',
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
                        '${track.artist} • ${_formatDuration(track.duration)}',
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
    // Find participant names from session
    String getAddedByName(String oderId) {
      final participant = session?.participants
          .where((p) => p.id == oderId)
          .firstOrNull;
      return participant?.name ?? 'Someone';
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
                    'Playing from',
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
                '${jamQueue.length} tracks',
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
                        'No tracks in queue',
                        style: TextStyle(color: secondaryColor),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add songs to the jam queue',
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
                      : (_, __) {},
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
                            '${track.artist} • Added by $addedByName',
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
      thumbnailUrl: queueItem.track.thumbnailUrl ?? '',
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
    final currentTrack = ref.watch(currentTrackProvider);
    if (currentTrack == null) {
      return Center(
        child: Text(
          'No track playing',
          style: TextStyle(color: secondaryColor),
        ),
      );
    }

    final ytService = ref.watch(youtubeServiceProvider);

    // Cache the future to prevent re-fetching on every rebuild
    if (_lastRelatedTrackId != currentTrack.id) {
      _lastRelatedTrackId = currentTrack.id;
      _relatedTracksFuture = ytService.getRelatedTracks(
        currentTrack.id,
        limit: 20,
      );
    }

    return FutureBuilder<List<Track>>(
      future: _relatedTracksFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Iconsax.music_filter, size: 48, color: secondaryColor),
                const SizedBox(height: 12),
                Text(
                  'No related tracks found',
                  style: TextStyle(color: secondaryColor),
                ),
              ],
            ),
          );
        }

        final relatedTracks = snapshot.data!;

        return ListView.builder(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: relatedTracks.length,
          itemExtent: 72, // Fixed height for faster scrolling
          itemBuilder: (context, index) {
            final track = relatedTracks[index];
            return RepaintBoundary(
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
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: secondaryColor, fontSize: 12),
                ),
                onTap: () {
                  // Play this track and add related as queue
                  ref
                      .read(audioPlayerServiceProvider)
                      .playQueue(relatedTracks, startIndex: index);
                },
              ),
            );
          },
        );
      },
    );
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
    if (queue.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Queue is empty')));
      return;
    }

    final controller = TextEditingController(text: 'My Queue');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: backgroundColor,
        title: Text(
          'Save Queue as Playlist',
          style: TextStyle(color: textColor),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: textColor),
          decoration: InputDecoration(
            hintText: 'Playlist name',
            hintStyle: TextStyle(color: textColor.withValues(alpha: 0.5)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
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
                    content: Text('Saved ${queue.length} tracks to "$name"'),
                  ),
                );
              }
            },
            child: const Text('Save'),
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
                'NOW PLAYING',
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

  Widget _buildAlbumArt(Track track, Color accentColor) {
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
            alignment: Alignment.topCenter, // Push album art to top
            child: Padding(
              padding: const EdgeInsets.only(top: 16), // Tiny bit down
              child: Hero(
                tag: 'album-art-${track.id}',
                child: Container(
                  width: artSize,
                  height: artSize,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 30,
                        spreadRadius: 5,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: track.thumbnailUrl != null
                        ? CachedNetworkImage(
                            imageUrl: track.thumbnailUrl!.replaceAll(
                              'w120-h120',
                              'w600-h600',
                            ),
                            fit: BoxFit.cover,
                            placeholder: (_, __) => _defaultArt(accentColor),
                            errorWidget: (_, __, ___) =>
                                _defaultArt(accentColor),
                          )
                        : _defaultArt(accentColor),
                  ),
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
                  height: 28,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final textPainter = TextPainter(
                        text: TextSpan(
                          text: track.title,
                          style: TextStyle(
                            fontSize: 22,
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
                            fontSize: 22,
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
                          fontSize: 22,
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
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final textPainter = TextPainter(
                        text: TextSpan(
                          text: track.artist,
                          style: TextStyle(fontSize: 16, color: secondaryColor),
                        ),
                        maxLines: 1,
                        textDirection: TextDirection.ltr,
                      )..layout();

                      // Only use marquee if text overflows
                      if (textPainter.width > constraints.maxWidth) {
                        return Marquee(
                          text: track.artist,
                          style: TextStyle(fontSize: 16, color: secondaryColor),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16, color: secondaryColor),
                      );
                    },
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

  /// Jams icon button with active session indicator
  Widget _buildJamsButton(Color textColor, Color accentColor) {
    final isInSession = ref.watch(isInJamSessionProvider);
    final session = ref.watch(currentJamSessionProvider).valueOrNull;

    return Stack(
      children: [
        IconButton(
          onPressed: () {
            final albumColors = ref.read(albumColorsProvider);
            JamsPanel.show(
              context,
              backgroundColor: albumColors.backgroundPrimary,
              textColor: albumColors.onBackground,
              accentColor: albumColors.accent,
            );
          },
          icon: Icon(
            Iconsax.profile_2user,
            color: isInSession ? accentColor : textColor,
            size: 24,
          ),
          tooltip: 'Jams',
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
      labelColor: showActiveState ? accentColor : textColor.withValues(alpha: 0.6),
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
      tabs: const [
        Tab(text: 'UP NEXT'),
        Tab(text: 'LYRICS'),
        Tab(text: 'RELATED'),
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
