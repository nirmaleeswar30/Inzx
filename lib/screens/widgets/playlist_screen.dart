import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/l10n/app_localizations_x.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../services/download_service.dart';
import 'track_options_sheet.dart';
import 'mini_player.dart';
import 'now_playing_screen.dart';

// NOTE: We use ytMusicPlaylistProvider from ytmusic_providers.dart
// which uses the shared innerTubeServiceProvider singleton.
// This ensures authentication cookies are preserved.

/// Playlist detail screen with track listing and in-playlist search
class PlaylistScreen extends ConsumerStatefulWidget {
  final String playlistId;
  final String? playlistTitle;
  final String? thumbnailUrl;
  final DownloadedPlaylistSnapshot? downloadedSnapshot;

  const PlaylistScreen({
    super.key,
    required this.playlistId,
    this.playlistTitle,
    this.thumbnailUrl,
    this.downloadedSnapshot,
  });

  PlaylistScreen.offlineDownloaded({
    super.key,
    required DownloadedPlaylistSnapshot snapshot,
  }) : playlistId = 'offline_playlist:${snapshot.sourcePlaylistId}',
       playlistTitle = snapshot.title,
       thumbnailUrl = snapshot.thumbnailUrl,
       downloadedSnapshot = snapshot;

  bool get isOfflineDownloaded => downloadedSnapshot != null;

  Playlist buildOfflinePlaylist(BuildContext context) {
    final snapshot = downloadedSnapshot!;
    return Playlist(
      id: snapshot.sourcePlaylistId,
      title: snapshot.title,
      thumbnailUrl: snapshot.thumbnailUrl,
      tracks: snapshot.downloadedOrderedTracks,
      description: context.l10n.offlineSnapshotDownloaded(
        snapshot.downloadedTracks,
        snapshot.totalTracks,
      ),
      author: context.l10n.downloaded,
      isLocal: true,
    );
  }

  static void open(
    BuildContext context, {
    required String playlistId,
    String? title,
    String? thumbnailUrl,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlaylistScreen(
          playlistId: playlistId,
          playlistTitle: title,
          thumbnailUrl: thumbnailUrl,
        ),
      ),
    );
  }

  @override
  ConsumerState<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends ConsumerState<PlaylistScreen> {
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final playerService = ref.read(audioPlayerServiceProvider);

    if (widget.isOfflineDownloaded) {
      final playlist = widget.buildOfflinePlaylist(context);
      return Scaffold(
        backgroundColor: isDark ? Colors.black : colorScheme.surface,
        body: _buildContent(
          context,
          ref,
          playlist,
          isDark,
          colorScheme,
          playerService,
        ),
      );
    }

    // Use ytMusicPlaylistProvider which uses the shared InnerTubeService singleton
    final playlistAsync = ref.watch(ytMusicPlaylistProvider(widget.playlistId));

    return Scaffold(
      backgroundColor: isDark ? Colors.black : colorScheme.surface,
      body: playlistAsync.when(
        loading: () => _buildLoadingState(
          widget.playlistTitle,
          widget.thumbnailUrl,
          isDark,
          colorScheme,
        ),
        error: (e, stack) {
          return _buildErrorState(
            context.l10n.errorWithMessage(e.toString()),
            isDark,
          );
        },
        data: (playlist) {
          if (playlist == null) {
            return _buildErrorState(
              context.l10n.playlistNotFoundMessage(widget.playlistId),
              isDark,
            );
          }
          return _buildContent(
            context,
            ref,
            playlist,
            isDark,
            colorScheme,
            playerService,
          );
        },
      ),
    );
  }

  Widget _buildLoadingState(
    String? title,
    String? thumbnail,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    return _buildContent(
      null,
      null,
      Playlist(
        id: widget.playlistId,
        title: title ?? context.l10n.loading,
        thumbnailUrl: thumbnail,
        tracks: [],
        description: context.l10n.loading,
        author: context.l10n.youtubeMusicLabel,
      ),
      isDark,
      colorScheme,
      null,
      isLoading: true,
    );
  }

  Widget _buildErrorState(String error, bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Iconsax.warning_2,
            size: 48,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
          const SizedBox(height: 16),
          Text(
            error,
            textAlign: TextAlign.center,
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext? context,
    WidgetRef? ref,
    Playlist playlist,
    bool isDark,
    ColorScheme colorScheme,
    dynamic playerService, {
    bool isLoading = false,
  }) {
    final l10n = (context ?? this.context).l10n;
    final allTracks = playlist.tracks ?? [];

    // Filter tracks based on search query
    final displayTracks = _searchQuery.isEmpty
        ? allTracks
        : allTracks
              .where(
                (t) =>
                    t.title.toLowerCase().contains(
                      _searchQuery.toLowerCase(),
                    ) ||
                    t.artist.toLowerCase().contains(_searchQuery.toLowerCase()),
              )
              .toList();

    // Use high-res thumbnail if available
    // Low res for background (performance), High res for foreground
    final lowResThumb = playlist.thumbnailUrl;
    final highResThumb = playlist.thumbnailUrl?.replaceAll(
      'w120-h120',
      'w600-h600',
    );

    // Watch playback state for UI updates
    final playbackState = ref?.watch(playbackStateProvider);
    final currentTrack = ref?.watch(currentTrackProvider);
    final queueSourceId = ref?.watch(queueSourceIdProvider);
    final isPlaying =
        playbackState?.whenOrNull(data: (s) => s.isPlaying) ?? false;

    // Check if this playlist is currently playing (by source ID, not by track membership)
    final isPlaylistPlaying = queueSourceId == playlist.id;

    // Determine play button icon
    final playIcon = (isPlaylistPlaying && isPlaying)
        ? Icons.pause_rounded
        : Icons.play_arrow_rounded;

    return Stack(
      children: [
        // Background - Use simple gradient instead of expensive BackdropFilter
        if (lowResThumb != null)
          Positioned.fill(
            child: RepaintBoundary(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Low-res blurred image (pre-scaled for performance)
                  CachedNetworkImage(
                    imageUrl: lowResThumb,
                    fit: BoxFit.cover,
                    memCacheWidth: 100, // Very small for blur effect
                    memCacheHeight: 100,
                    color: (isDark ? Colors.black : Colors.white).withValues(
                      alpha: 0.5,
                    ),
                    colorBlendMode: isDark
                        ? BlendMode.darken
                        : BlendMode.lighten,
                  ),
                  // Gradient overlay instead of expensive BackdropFilter
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          (isDark ? Colors.black : Colors.white).withValues(
                            alpha: 0.2,
                          ),
                          (isDark ? Colors.black : Colors.white).withValues(
                            alpha: 0.6,
                          ),
                          (isDark ? Colors.black : Colors.white).withValues(
                            alpha: 0.9,
                          ),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        Column(
          children: [
            Expanded(
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // App Bar with Back and Search
                  SliverAppBar(
                    backgroundColor: _isSearching
                        ? (isDark ? Colors.black : Colors.white).withValues(
                            alpha: 0.8,
                          )
                        : Colors.transparent,
                    elevation: 0,
                    pinned:
                        true, // Pin when searching? Or always? Let's pin when searching for better UX
                    leading: IconButton(
                      icon: Icon(
                        Icons.arrow_back,
                        color: isDark ? Colors.white : colorScheme.onSurface,
                      ),
                      onPressed: () {
                        if (_isSearching) {
                          setState(() {
                            _isSearching = false;
                            _searchQuery = '';
                            _searchController.clear();
                          });
                        } else {
                          if (context != null) Navigator.pop(context);
                        }
                      },
                    ),
                    title: _isSearching
                        ? TextField(
                            controller: _searchController,
                            autofocus: true,
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white
                                  : colorScheme.onSurface,
                            ),
                            decoration: InputDecoration(
                              hintText: l10n.findInPlaylist,
                              hintStyle: TextStyle(
                                color: isDark
                                    ? Colors.white54
                                    : colorScheme.onSurface.withValues(
                                        alpha: 0.54,
                                      ),
                              ),
                              border: InputBorder.none,
                            ),
                            onChanged: (value) {
                              setState(() {
                                _searchQuery = value;
                              });
                            },
                          )
                        : null,
                    actions: [
                      if (!_isSearching)
                        IconButton(
                          icon: Icon(
                            Icons.search,
                            color: isDark
                                ? Colors.white
                                : colorScheme.onSurface,
                          ),
                          onPressed: () {
                            setState(() {
                              _isSearching = true;
                            });
                          },
                        )
                      else
                        IconButton(
                          icon: Icon(
                            Icons.close,
                            color: isDark
                                ? Colors.white
                                : colorScheme.onSurface,
                          ),
                          onPressed: () {
                            setState(() {
                              _isSearching = false;
                              _searchQuery = '';
                              _searchController.clear();
                            });
                          },
                        ),
                    ],
                  ),

                  // Header Section (Only show if not searching or if we want to keep it? Usually filters hide header)
                  // Let's keep header but maybe collapse it if filtered?
                  // Providing User asked to "search that playlist and show results", usually means list view.
                  // I will hide header if searching to focus on results.
                  if (!_isSearching)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          children: [
                            const SizedBox(height: 10),
                            // Centered Album Art
                            Container(
                              height: 240,
                              width: 240,
                              decoration: BoxDecoration(
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: highResThumb != null
                                    ? CachedNetworkImage(
                                        imageUrl: highResThumb,
                                        fit: BoxFit.cover,
                                        placeholder: (_, _) => Container(
                                          color: isDark
                                              ? Colors.grey[900]
                                              : Colors.grey[200],
                                        ),
                                        errorWidget: (_, _, _) => Container(
                                          color: isDark
                                              ? Colors.grey[900]
                                              : Colors.grey[200],
                                        ),
                                      )
                                    : Container(
                                        color: isDark
                                            ? Colors.grey[900]
                                            : Colors.grey[200],
                                        child: Icon(
                                          Icons.music_note,
                                          color: isDark
                                              ? Colors.white
                                              : colorScheme.onSurface,
                                          size: 80,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Title
                            Text(
                              playlist.title,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isDark
                                    ? Colors.white
                                    : colorScheme.onSurface,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Subtitle / Author
                            Text(
                              playlist.author ?? l10n.youtubeMusicLabel,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isDark
                                    ? Colors.white70
                                    : colorScheme.onSurface.withValues(
                                        alpha: 0.7,
                                      ),
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Description
                            if (playlist.description != null &&
                                playlist.description!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Text(
                                  playlist.description!,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white54
                                        : colorScheme.onSurface.withValues(
                                            alpha: 0.54,
                                          ),
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 32),

                            // Action Buttons Row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildCircleButton(Icons.download_rounded, () {
                                  if (context == null) return;
                                  _downloadPlaylist(
                                    context,
                                    ref,
                                    playlist,
                                    allTracks,
                                  );
                                }),
                                _buildCircleButton(Icons.add_box_outlined, () {
                                  if (context == null) return;
                                  _addPlaylistToQueue(
                                    context,
                                    playerService,
                                    allTracks,
                                  );
                                }),

                                // Play Button (Toggle Play/Pause)
                                Container(
                                  height: 72,
                                  width: 72,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                  child: IconButton(
                                    icon: Icon(
                                      playIcon,
                                      color: isDark
                                          ? Colors.black
                                          : Colors.white,
                                    ),
                                    iconSize: 42,
                                    onPressed: () {
                                      if (isLoading ||
                                          playerService == null ||
                                          allTracks.isEmpty) {
                                        return;
                                      }

                                      if (isPlaylistPlaying && isPlaying) {
                                        // Only pause if this playlist is currently playing
                                        playerService.pause();
                                      } else if (isPlaylistPlaying &&
                                          !isPlaying) {
                                        // Resume current playlist playback
                                        playerService.togglePlayPause();
                                      } else {
                                        // Start playing this playlist from beginning
                                        // This handles both: resuming paused playlist AND starting fresh
                                        playerService.playQueue(
                                          allTracks,
                                          startIndex: 0,
                                          sourceId: playlist.id,
                                        );
                                      }
                                    },
                                  ),
                                ),

                                _buildCircleButton(Icons.share_outlined, () {
                                  if (context != null) {
                                    _sharePlaylist(context, playlist);
                                  }
                                }),
                                _buildCircleButton(Icons.more_vert_rounded, () {
                                  if (context == null) return;
                                  _showPlaylistOptions(
                                    context,
                                    ref,
                                    playlist,
                                    allTracks,
                                    playerService,
                                  );
                                }),
                              ],
                            ),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ),

                  // Tracks List (Filtered or Full)
                  if (isLoading)
                    SliverFillRemaining(
                      child: Center(
                        child: CircularProgressIndicator(
                          color: isDark ? Colors.white : colorScheme.primary,
                        ),
                      ),
                    )
                  else if (displayTracks.isEmpty)
                    SliverFillRemaining(
                      child: Center(
                        child: Text(
                          _isSearching
                              ? l10n.noMatchingTracks
                              : l10n.noTracksFound,
                          style: TextStyle(
                            color: isDark
                                ? Colors.white54
                                : colorScheme.onSurface.withValues(alpha: 0.54),
                          ),
                        ),
                      ),
                    )
                  else
                    SliverFixedExtentList(
                      itemExtent: 72, // Fixed height for faster scrolling
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final track = displayTracks[index];
                        final isTrackPlaying = currentTrack?.id == track.id;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          // Selected color if playing
                          selected: isTrackPlaying,
                          selectedTileColor:
                              (isDark ? Colors.white : Colors.black).withValues(
                                alpha: 0.1,
                              ),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: SizedBox(
                              width: 48,
                              height: 48,
                              child: track.thumbnailUrl != null
                                  ? CachedNetworkImage(
                                      imageUrl: track.thumbnailUrl!,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 96, // 2x for retina
                                      memCacheHeight: 96,
                                      fadeInDuration: const Duration(
                                        milliseconds: 150,
                                      ),
                                      errorWidget: (_, _, _) => Container(
                                        color: isDark
                                            ? Colors.grey[800]
                                            : Colors.grey[300],
                                      ),
                                    )
                                  : Container(
                                      color: isDark
                                          ? Colors.grey[800]
                                          : Colors.grey[300],
                                    ),
                            ),
                          ),
                          title: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isTrackPlaying
                                  ? colorScheme.primary
                                  : (isDark
                                        ? Colors.white
                                        : colorScheme.onSurface),
                              fontSize: 16,
                              fontWeight: isTrackPlaying
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isTrackPlaying
                                  ? colorScheme.primary.withValues(alpha: 0.7)
                                  : (isDark
                                        ? Colors.white60
                                        : colorScheme.onSurface.withValues(
                                            alpha: 0.6,
                                          )),
                              fontSize: 14,
                            ),
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              Icons.more_vert,
                              color: isDark
                                  ? Colors.white54
                                  : colorScheme.onSurface.withValues(
                                      alpha: 0.54,
                                    ),
                            ),
                            onPressed: () =>
                                TrackOptionsSheet.show(context, track),
                          ),
                          onTap: () {
                            // If searching, we might want to play the selected track contextually?
                            // Or just play it from the original list?
                            // For simplicty, play queue starting from this track in the filtered list?
                            // Or find the index in MAIN list?
                            // Standard behavior: Play this track.
                            // If we play filtered list, we construct a new queue of filtered items? Yes.
                            if (playerService != null) {
                              playerService.playQueue(
                                displayTracks,
                                startIndex: index,
                                sourceId: playlist.id,
                              );
                            }
                          },
                        );
                      }, childCount: displayTracks.length),
                    ),

                  // Bottom Padding for Mini Player
                  const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
                ],
              ),
            ),

            // Mini Player at the bottom of the content column (above nav/safe area)
            if (currentTrack != null && context != null)
              MusicMiniPlayer(onTap: () => NowPlayingScreen.show(context)),
          ],
        ),
      ],
    );
  }

  Widget _buildCircleButton(IconData icon, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 48,
      width: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
      ),
      child: IconButton(
        icon: Icon(icon, color: isDark ? Colors.white : colorScheme.onSurface),
        onPressed: onTap,
      ),
    );
  }

  void _sharePlaylist(BuildContext context, Playlist playlist) {
    final url = 'https://music.youtube.com/playlist?list=${playlist.id}';
    SharePlus.instance.share(
      ShareParams(text: context.l10n.sharePlaylistText(playlist.title, url)),
    );
  }

  void _downloadPlaylist(
    BuildContext context,
    WidgetRef? ref,
    Playlist playlist,
    List<Track> tracks,
  ) {
    if (ref == null || tracks.isEmpty) return;

    final downloadManager = ref.read(downloadManagerProvider.notifier);
    downloadManager.addPlaylistToQueue(
      sourcePlaylistId: playlist.id,
      title: playlist.title,
      thumbnailUrl: playlist.thumbnailUrl,
      tracks: tracks,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.downloadingTracksFromPlaylist(
            tracks.length,
            playlist.title,
          ),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _addPlaylistToQueue(
    BuildContext context,
    dynamic playerService,
    List<Track> tracks,
  ) {
    if (playerService == null || tracks.isEmpty) return;

    for (final track in tracks) {
      playerService.addToQueue(track);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.addedTracksToQueueCount(tracks.length)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showPlaylistOptions(
    BuildContext context,
    WidgetRef? ref,
    Playlist playlist,
    List<Track> tracks,
    dynamic playerService,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? Colors.grey[900] : Colors.grey[200],
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[700] : Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Icon(
                  Icons.play_arrow,
                  color: isDark ? Colors.white : colorScheme.onSurface,
                ),
                title: Text(
                  context.l10n.play,
                  style: TextStyle(
                    color: isDark ? Colors.white : colorScheme.onSurface,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  if (playerService != null && tracks.isNotEmpty) {
                    playerService.playQueue(
                      tracks,
                      startIndex: 0,
                      sourceId: playlist.id,
                    );
                  }
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.shuffle,
                  color: isDark ? Colors.white : colorScheme.onSurface,
                ),
                title: Text(
                  context.l10n.shuffle,
                  style: TextStyle(
                    color: isDark ? Colors.white : colorScheme.onSurface,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  if (playerService != null && tracks.isNotEmpty) {
                    final shuffled = List<Track>.from(tracks)..shuffle();
                    playerService.playQueue(
                      shuffled,
                      startIndex: 0,
                      sourceId: playlist.id,
                    );
                  }
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.playlist_add,
                  color: isDark ? Colors.white : colorScheme.onSurface,
                ),
                title: Text(
                  context.l10n.addToQueue,
                  style: TextStyle(
                    color: isDark ? Colors.white : colorScheme.onSurface,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _addPlaylistToQueue(context, playerService, tracks);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.download,
                  color: isDark ? Colors.white : colorScheme.onSurface,
                ),
                title: Text(
                  context.l10n.downloadPlaylist,
                  style: TextStyle(
                    color: isDark ? Colors.white : colorScheme.onSurface,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _downloadPlaylist(context, ref, playlist, tracks);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.share,
                  color: isDark ? Colors.white : colorScheme.onSurface,
                ),
                title: Text(
                  context.l10n.share,
                  style: TextStyle(
                    color: isDark ? Colors.white : colorScheme.onSurface,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _sharePlaylist(context, playlist);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
