import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../providers/ytmusic_providers.dart';
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

  const PlaylistScreen({
    super.key,
    required this.playlistId,
    this.playlistTitle,
    this.thumbnailUrl,
  });

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
    // Use ytMusicPlaylistProvider which uses the shared InnerTubeService singleton
    final playlistAsync = ref.watch(ytMusicPlaylistProvider(widget.playlistId));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final playerService = ref.read(audioPlayerServiceProvider);

    return Scaffold(
      backgroundColor: Colors.black, // Dark background as per mockup
      body: playlistAsync.when(
        loading: () => _buildLoadingState(
          widget.playlistTitle,
          widget.thumbnailUrl,
          isDark,
          colorScheme,
        ),
        error: (e, stack) {
          return _buildErrorState('Error: ${e.toString()}', isDark);
        },
        data: (playlist) {
          if (playlist == null) {
            return _buildErrorState(
              'Playlist not found\n\nPlaylist ID: ${widget.playlistId}\n\nThis playlist may be private or unavailable.',
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
        title: title ?? 'Loading...',
        thumbnailUrl: thumbnail,
        tracks: [],
        description: 'Loading...',
        author: 'YouTube Music',
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
                    color: Colors.black.withValues(alpha: 0.5),
                    colorBlendMode: BlendMode.darken,
                  ),
                  // Gradient overlay instead of expensive BackdropFilter
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.2),
                          Colors.black.withValues(alpha: 0.6),
                          Colors.black.withValues(alpha: 0.9),
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
                        ? Colors.black.withValues(alpha: 0.8)
                        : Colors.transparent,
                    elevation: 0,
                    pinned:
                        true, // Pin when searching? Or always? Let's pin when searching for better UX
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
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
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              hintText: 'Find in playlist...',
                              hintStyle: TextStyle(color: Colors.white54),
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
                          icon: const Icon(Icons.search, color: Colors.white),
                          onPressed: () {
                            setState(() {
                              _isSearching = true;
                            });
                          },
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
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
                                        placeholder: (_, __) =>
                                            Container(color: Colors.grey[900]),
                                        errorWidget: (_, __, ___) =>
                                            Container(color: Colors.grey[900]),
                                      )
                                    : Container(
                                        color: Colors.grey[900],
                                        child: const Icon(
                                          Icons.music_note,
                                          color: Colors.white,
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
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Subtitle / Author
                            Text(
                              playlist.author ?? 'YouTube Music',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white70,
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
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 32),

                            // Action Buttons Row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildCircleButton(
                                  Icons.download_rounded,
                                  () {},
                                ),
                                _buildCircleButton(
                                  Icons.add_box_outlined,
                                  () {},
                                ),

                                // Play Button (Toggle Play/Pause)
                                Container(
                                  height: 72,
                                  width: 72,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                  ),
                                  child: IconButton(
                                    icon: Icon(playIcon, color: Colors.black),
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

                                _buildCircleButton(Icons.share_outlined, () {}),
                                _buildCircleButton(
                                  Icons.more_vert_rounded,
                                  () {},
                                ),
                              ],
                            ),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ),

                  // Tracks List (Filtered or Full)
                  if (isLoading)
                    const SliverFillRemaining(
                      child: Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    )
                  else if (displayTracks.isEmpty)
                    SliverFillRemaining(
                      child: Center(
                        child: Text(
                          _isSearching
                              ? 'No matching tracks'
                              : 'No tracks found',
                          style: const TextStyle(color: Colors.white54),
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
                          selectedTileColor: Colors.white.withValues(alpha: 0.1),
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
                                      errorWidget: (_, __, ___) =>
                                          Container(color: Colors.grey[800]),
                                    )
                                  : Container(color: Colors.grey[800]),
                            ),
                          ),
                          title: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isTrackPlaying
                                  ? colorScheme.primary
                                  : Colors.white,
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
                                  : Colors.white60,
                              fontSize: 14,
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.more_vert,
                              color: Colors.white54,
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
    return Container(
      height: 48,
      width: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.1),
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        onPressed: onTap,
      ),
    );
  }
}
