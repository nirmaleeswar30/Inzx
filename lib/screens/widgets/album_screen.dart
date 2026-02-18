import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../services/download_service.dart';
import 'track_options_sheet.dart';
import 'mini_player.dart';
import 'now_playing_screen.dart';
import '../../services/album_color_extractor.dart';

// Provider for extracting album colors
final albumColorsProvider = FutureProvider.family<AlbumColors, String>((
  ref,
  url,
) {
  return AlbumColorExtractor.extractFromUrl(url);
});

// NOTE: We use ytMusicAlbumProvider from ytmusic_providers.dart
// which uses the shared innerTubeServiceProvider singleton.

/// Album detail screen with track listing
class AlbumScreen extends ConsumerWidget {
  final String albumId;
  final String? albumTitle;
  final String? thumbnailUrl;

  const AlbumScreen({
    super.key,
    required this.albumId,
    this.albumTitle,
    this.thumbnailUrl,
  });

  static void open(
    BuildContext context, {
    required String albumId,
    String? title,
    String? thumbnailUrl,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AlbumScreen(
          albumId: albumId,
          albumTitle: title,
          thumbnailUrl: thumbnailUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use ytMusicAlbumProvider which uses the shared InnerTubeService singleton
    final albumAsync = ref.watch(ytMusicAlbumProvider(albumId));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final playerService = ref.read(audioPlayerServiceProvider);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : colorScheme.surface,
      body: albumAsync.when(
        loading: () =>
            _buildLoadingState(albumTitle, thumbnailUrl, isDark, colorScheme),
        error: (e, stack) => _buildErrorState('Error: ${e.toString()}', isDark),
        data: (album) {
          if (album == null) {
            return _buildErrorState('Album not found', isDark);
          }
          return _buildContent(
            context,
            ref,
            album,
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
      Album(
        id: albumId,
        title: title ?? 'Loading...',
        thumbnailUrl: thumbnail,
        artist: 'Loading...',
        tracks: [],
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
    Album album,
    bool isDark,
    ColorScheme colorScheme,
    dynamic playerService, {
    bool isLoading = false,
  }) {
    final tracks = album.tracks ?? [];

    // Low res for background (performance), High res for foreground
    final lowResThumb = album.thumbnailUrl;
    final highResThumb =
        album.highResThumbnailUrl?.replaceAll('w120-h120', 'w600-h600') ??
        album.thumbnailUrl?.replaceAll('w120-h120', 'w600-h600');

    // Extract colors from the high res thumbnail (or low res if high not available)
    // We use high res for extraction as it might be cleaner, but purely for logic
    // Using low res for extraction is faster.
    final colorSource = lowResThumb ?? highResThumb;
    final albumColors = ref != null && colorSource != null
        ? ref.watch(albumColorsProvider(colorSource)).valueOrNull
        : null;

    final primaryColor = albumColors?.accent ?? colorScheme.primary;

    // Watch playback state for UI updates
    final playbackState = ref?.watch(playbackStateProvider);
    final currentTrack = ref?.watch(currentTrackProvider);
    final queueSourceId = ref?.watch(queueSourceIdProvider);
    final isPlaying =
        playbackState?.whenOrNull(data: (s) => s.isPlaying) ?? false;
    final hasCurrentTrack = currentTrack != null;

    // Check if this album is currently playing (by source ID, not by track membership)
    final isAlbumPlaying = queueSourceId == album.id;

    // Determine play button icon
    final playIcon = (isAlbumPlaying && isPlaying)
        ? Icons.pause_rounded
        : Icons.play_arrow_rounded;
    final playButtonColor = colorScheme.primary;
    final playIconColor = colorScheme.onPrimary;

    return Stack(
      children: [
        // Background - Use simple gradient instead of expensive BackdropFilter
        if (lowResThumb != null)
          Positioned.fill(
            child: RepaintBoundary(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Low-res image (pre-scaled for performance)
                  CachedNetworkImage(
                    imageUrl: lowResThumb,
                    fit: BoxFit.cover,
                    memCacheWidth: 100,
                    memCacheHeight: 100,
                    color: (isDark ? Colors.black : Colors.white).withValues(
                      alpha: isDark ? 0.7 : 0.55,
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
                        colors: isDark
                            ? [
                                Colors.black.withValues(alpha: 0.4),
                                Colors.black.withValues(alpha: 0.8),
                                Colors.black,
                              ]
                            : [
                                primaryColor.withValues(alpha: 0.14),
                                colorScheme.surface.withValues(alpha: 0.75),
                                colorScheme.surface,
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
                  // App Bar
                  SliverAppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    pinned: false,
                    leading: IconButton(
                      icon: Icon(
                        Icons.arrow_back,
                        color: isDark ? Colors.white : colorScheme.onSurface,
                      ),
                      onPressed: () {
                        if (context != null) Navigator.pop(context);
                      },
                    ),
                    actions: [
                      IconButton(
                        icon: Icon(
                          Icons.search,
                          color: isDark ? Colors.white : colorScheme.onSurface,
                        ),
                        onPressed: () {
                          // TODO: Navigate to Search Screen
                          // For now, we pop to root as a fallback if no dedicated search screen
                          if (context != null) {
                            Navigator.popUntil(
                              context,
                              (route) => route.isFirst,
                            );
                          }
                        },
                      ),
                    ],
                  ),

                  // Header Section
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
                                  color: (isDark ? Colors.black : primaryColor)
                                      .withValues(alpha: isDark ? 0.4 : 0.22),
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
                                        Icons.album,
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
                            album.title,
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

                          // Artist & Year
                          Text(
                            '${album.artist}${album.year != null ? ' • ${album.year}' : ''}',
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

                          // Description/Info
                          if (album.description != null &&
                              album.description!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Text(
                                album.description!,
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
                              _buildCircleButton(
                                Icons.download_rounded,
                                () {
                                  if (context != null && tracks.isNotEmpty) {
                                    _downloadAlbum(context, ref, album, tracks);
                                  }
                                },
                                isDark: isDark,
                                colorScheme: colorScheme,
                              ),
                              _buildCircleButton(
                                Icons.shuffle_rounded,
                                () {
                                  if (playerService != null &&
                                      tracks.isNotEmpty) {
                                    final shuffled = List<Track>.from(tracks)
                                      ..shuffle();
                                    playerService.playQueue(
                                      shuffled,
                                      startIndex: 0,
                                      sourceId: album.id,
                                    );
                                  }
                                },
                                isDark: isDark,
                                colorScheme: colorScheme,
                              ),

                              // Play Button
                              Container(
                                height: 72,
                                width: 72,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: playButtonColor,
                                ),
                                child: IconButton(
                                  icon: Icon(playIcon, color: playIconColor),
                                  iconSize: 42,
                                  onPressed: () {
                                    if (!isLoading &&
                                        playerService != null &&
                                        tracks.isNotEmpty) {
                                      if (isAlbumPlaying && isPlaying) {
                                        // Only pause if this album is currently playing
                                        playerService.pause();
                                      } else {
                                        // Start playing this album
                                        playerService.playQueue(
                                          tracks,
                                          startIndex: 0,
                                          sourceId: album.id,
                                        );
                                      }
                                    }
                                  },
                                ),
                              ),

                              _buildCircleButton(
                                Icons.share_outlined,
                                () {
                                  _shareAlbum(album);
                                },
                                isDark: isDark,
                                colorScheme: colorScheme,
                              ),
                              _buildCircleButton(
                                Icons.more_vert_rounded,
                                () {
                                  if (context != null) {
                                    _showAlbumOptions(
                                      context,
                                      ref,
                                      album,
                                      tracks,
                                      playerService,
                                    );
                                  }
                                },
                                isDark: isDark,
                                colorScheme: colorScheme,
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),

                  // Tracks List
                  if (isLoading)
                    SliverFillRemaining(
                      child: Center(
                        child: CircularProgressIndicator(
                          color: isDark ? Colors.white : colorScheme.onSurface,
                        ),
                      ),
                    )
                  else if (tracks.isEmpty)
                    SliverFillRemaining(
                      child: Center(
                        child: Text(
                          'No tracks found',
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
                      itemExtent: 64, // Fixed height for album tracks
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final track = tracks[index];
                        final isTrackPlaying = currentTrack?.id == track.id;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          selected: isTrackPlaying,
                          selectedTileColor:
                              (isDark ? Colors.white : colorScheme.onSurface)
                                  .withValues(alpha: 0.1),
                          leading: Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white54
                                  : colorScheme.onSurface.withValues(
                                      alpha: 0.54,
                                    ),
                              fontSize: 14,
                            ),
                          ),
                          title: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isTrackPlaying
                                  ? primaryColor
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
                                  ? primaryColor.withValues(alpha: 0.7)
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
                            if (playerService != null) {
                              playerService.playQueue(
                                tracks,
                                startIndex: index,
                                sourceId: album.id,
                              );
                            }
                          },
                        );
                      }, childCount: tracks.length),
                    ),

                  // Bottom Padding for Mini Player
                  const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
                ],
              ),
            ),

            if (hasCurrentTrack && context != null)
              MusicMiniPlayer(onTap: () => NowPlayingScreen.show(context)),
          ],
        ),
      ],
    );
  }

  Widget _buildCircleButton(
    IconData icon,
    VoidCallback onTap, {
    required bool isDark,
    required ColorScheme colorScheme,
  }) {
    return Container(
      height: 48,
      width: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: (isDark ? Colors.white : colorScheme.onSurface).withValues(
          alpha: 0.1,
        ),
      ),
      child: IconButton(
        icon: Icon(icon, color: isDark ? Colors.white : colorScheme.onSurface),
        iconSize: 24,
        onPressed: onTap,
      ),
    );
  }

  /// Share album link
  void _shareAlbum(Album album) {
    final url = 'https://music.youtube.com/playlist?list=${album.id}';
    SharePlus.instance.share(
      ShareParams(text: '${album.title} by ${album.artist}\n$url'),
    );
  }

  /// Download all tracks in the album
  void _downloadAlbum(
    BuildContext context,
    WidgetRef? ref,
    Album album,
    List<Track> tracks,
  ) {
    if (ref == null || tracks.isEmpty) return;

    // Use the download manager notifier to queue all tracks
    final downloadManager = ref.read(downloadManagerProvider.notifier);
    downloadManager.addMultipleToQueue(tracks);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Downloading ${tracks.length} tracks from ${album.title}',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Show album options bottom sheet
  void _showAlbumOptions(
    BuildContext context,
    WidgetRef? ref,
    Album album,
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
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 50,
                    height: 50,
                    child: album.thumbnailUrl != null
                        ? CachedNetworkImage(
                            imageUrl: album.thumbnailUrl!,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            color: isDark ? Colors.grey[800] : Colors.grey[300],
                          ),
                  ),
                ),
                title: Text(
                  album.title,
                  style: TextStyle(
                    color: isDark ? Colors.white : colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  album.artist,
                  style: TextStyle(
                    color: isDark
                        ? Colors.white54
                        : colorScheme.onSurface.withValues(alpha: 0.54),
                  ),
                ),
              ),
              Divider(color: isDark ? Colors.grey : Colors.grey[300]),
              ListTile(
                leading: Icon(
                  Icons.play_arrow,
                  color: isDark ? Colors.white : colorScheme.onSurface,
                ),
                title: Text(
                  'Play',
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
                      sourceId: album.id,
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
                  'Shuffle',
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
                      sourceId: album.id,
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
                  'Add to queue',
                  style: TextStyle(
                    color: isDark ? Colors.white : colorScheme.onSurface,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  if (playerService != null && tracks.isNotEmpty) {
                    for (final track in tracks) {
                      playerService.addToQueue(track);
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Added ${tracks.length} tracks to queue'),
                      ),
                    );
                  }
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.download,
                  color: isDark ? Colors.white : colorScheme.onSurface,
                ),
                title: Text(
                  'Download album',
                  style: TextStyle(
                    color: isDark ? Colors.white : colorScheme.onSurface,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _downloadAlbum(context, ref, album, tracks);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.share,
                  color: isDark ? Colors.white : colorScheme.onSurface,
                ),
                title: Text(
                  'Share',
                  style: TextStyle(
                    color: isDark ? Colors.white : colorScheme.onSurface,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _shareAlbum(album);
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
