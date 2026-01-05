import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../services/artist_service.dart';
import '../../services/download_service.dart';
import '../../services/local_music_scanner.dart';
import 'track_options_sheet.dart';
import 'album_screen.dart';
import 'playlist_screen.dart';
import 'mini_player.dart';
import 'now_playing_screen.dart';
import 'shelf_details_screen.dart';

// ============ PROVIDERS ============

/// Artist service provider
final artistServiceProvider = Provider<ArtistService>((ref) {
  final innerTube = ref.watch(innerTubeServiceProvider);
  return ArtistService(innerTube);
});

/// Enhanced artist page data provider
final artistPageProvider = FutureProvider.autoDispose
    .family<ArtistPageData, String>((ref, artistId) async {
      // Get local library for merged results
      final downloadedTracks =
          ref.read(downloadedTracksProvider).valueOrNull ?? [];
      final localTracks = ref.read(localTracksProvider);
      final allLocalTracks = [...downloadedTracks, ...localTracks];

      final artistService = ref.read(artistServiceProvider);
      return artistService.getArtist(
        artistId,
        localLibrary: allLocalTracks.isNotEmpty ? allLocalTracks : null,
      );
    });

/// Dynamic theme colors from artist image
/// Uses a smaller image size to reduce CPU load on main thread
final artistColorsProvider = FutureProvider.autoDispose.family<Color?, String?>(
  (ref, imageUrl) async {
    if (imageUrl == null || imageUrl.isEmpty) return null;

    try {
      // Use a small image size for color extraction (reduces CPU load)
      // YouTube thumbnail URLs can be modified to request smaller sizes
      String optimizedUrl = imageUrl;
      if (imageUrl.contains('googleusercontent.com') ||
          imageUrl.contains('ytimg.com')) {
        // Request a tiny thumbnail for color extraction only
        optimizedUrl = imageUrl
            .replaceAll(RegExp(r'w\d+-h\d+'), 'w60-h60')
            .replaceAll(RegExp(r's\d+'), 's60');
      }

      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(optimizedUrl),
        maximumColorCount: 4, // Fewer colors = faster
        size: const Size(60, 60), // Resize target for faster processing
      );
      return paletteGenerator.dominantColor?.color ??
          paletteGenerator.vibrantColor?.color;
    } catch (e) {
      return null;
    }
  },
);

// ============ ARTIST SCREEN ============

/// OuterTune-style Artist/Channel screen
///
/// Key design principles:
/// 1. Uses browseId, not artist names
/// 2. Renders YTM shelves faithfully (songs, albums, singles, etc.)
/// 3. Dynamic theming from artist image
/// 4. Local tracks shown separately (additive, not merged)
/// 5. Supports pagination for large catalogs
/// 6. Distinguishes music artists from generic channels
class ArtistPageScreen extends ConsumerStatefulWidget {
  final String artistId;
  final String? artistName;
  final String? thumbnailUrl;

  const ArtistPageScreen({
    super.key,
    required this.artistId,
    this.artistName,
    this.thumbnailUrl,
  });

  static void open(
    BuildContext context, {
    required String artistId,
    String? name,
    String? thumbnailUrl,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ArtistPageScreen(
          artistId: artistId,
          artistName: name,
          thumbnailUrl: thumbnailUrl,
        ),
      ),
    );
  }

  @override
  ConsumerState<ArtistPageScreen> createState() => _ArtistPageScreenState();
}

class _ArtistPageScreenState extends ConsumerState<ArtistPageScreen> {
  @override
  Widget build(BuildContext context) {
    final artistAsync = ref.watch(artistPageProvider(widget.artistId));
    final playerService = ref.read(audioPlayerServiceProvider);
    final playbackState = ref.watch(playbackStateProvider);
    final currentTrack = ref.watch(currentTrackProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: artistAsync.when(
        loading: () => _buildLoadingState(),
        error: (e, _) => _buildErrorState('Error loading artist'),
        data: (artistData) => _ArtistContent(
          artistData: artistData,
          playerService: playerService,
          playbackState: playbackState,
          currentTrack: currentTrack,
          initialThumbnail: widget.thumbnailUrl,
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          backgroundColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        SliverToBoxAdapter(
          child: Column(
            children: [
              const SizedBox(height: 40),
              // Placeholder image
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey[900],
                ),
                child: widget.thumbnailUrl != null
                    ? ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: widget.thumbnailUrl!,
                          fit: BoxFit.cover,
                        ),
                      )
                    : const Icon(Icons.person, size: 80, color: Colors.white24),
              ),
              const SizedBox(height: 24),
              Text(
                widget.artistName ?? 'Loading...',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 40),
              const CircularProgressIndicator(color: Colors.white),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.white38),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () =>
                ref.invalidate(artistPageProvider(widget.artistId)),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

/// Artist content widget with dynamic theming
class _ArtistContent extends ConsumerWidget {
  final ArtistPageData artistData;
  final dynamic playerService;
  final AsyncValue playbackState;
  final Track? currentTrack;
  final String? initialThumbnail;

  const _ArtistContent({
    required this.artistData,
    required this.playerService,
    required this.playbackState,
    required this.currentTrack,
    this.initialThumbnail,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasCurrentTrack = currentTrack != null;

    // Get dynamic theme color from artist image
    final themeColorAsync = ref.watch(
      artistColorsProvider(artistData.thumbnailUrl ?? initialThumbnail),
    );
    final themeColor = themeColorAsync.valueOrNull ?? colorScheme.primary;

    // Check if this artist's tracks are currently playing
    final queueSourceId = ref.watch(queueSourceIdProvider);
    final isArtistPlaying = queueSourceId == artistData.id;
    final playingState = playbackState.whenOrNull(data: (s) => s.isPlaying);
    final isPlaying = (playingState is bool) ? playingState : false;

    return Stack(
      children: [
        // Dynamic background gradient
        _buildBackground(artistData.thumbnailUrl, themeColor),

        Column(
          children: [
            Expanded(
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // App bar
                  SliverAppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    pinned: false,
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.more_vert, color: Colors.white),
                        onPressed: () => _showOptionsSheet(context, ref),
                      ),
                    ],
                  ),

                  // Header section
                  SliverToBoxAdapter(
                    child: _buildHeader(
                      context,
                      themeColor,
                      isArtistPlaying,
                      isPlaying,
                    ),
                  ),

                  // Local tracks section (if any)
                  if (artistData.localTracks.isNotEmpty)
                    ..._buildLocalTracksSection(context, ref),

                  // Render each shelf from YouTube Music
                  for (final shelf in artistData.shelves)
                    ..._buildShelfSection(context, ref, shelf, themeColor),

                  // Bottom padding
                  const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
                ],
              ),
            ),

            // Mini player
            if (hasCurrentTrack)
              MusicMiniPlayer(onTap: () => NowPlayingScreen.show(context)),
          ],
        ),
      ],
    );
  }

  Widget _buildBackground(String? imageUrl, Color themeColor) {
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl != null)
            CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              memCacheWidth: 100,
              color: Colors.black.withValues(alpha: 0.5),
              colorBlendMode: BlendMode.darken,
            ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  themeColor.withValues(alpha: 0.3),
                  Colors.black.withValues(alpha: 0.7),
                  Colors.black,
                ],
                stops: const [0.0, 0.4, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    Color themeColor,
    bool isArtistPlaying,
    bool isPlaying,
  ) {
    final topTracks = artistData.topTracks;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 10),

          // Artist image (circular)
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: themeColor.withValues(alpha: 0.4),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipOval(
              child: artistData.thumbnailUrl != null
                  ? CachedNetworkImage(
                      imageUrl: artistData.thumbnailUrl!.replaceAll(
                        'w120-h120',
                        'w400-h400',
                      ),
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(color: Colors.grey[900]),
                      errorWidget: (_, __, ___) =>
                          Container(color: Colors.grey[900]),
                    )
                  : Container(
                      color: Colors.grey[900],
                      child: const Icon(
                        Icons.person,
                        color: Colors.white38,
                        size: 80,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 24),

          // Artist name
          Text(
            artistData.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),

          // Subscriber count
          if (artistData.subscriberCount != null)
            Text(
              '${_formatNumber(artistData.subscriberCount!)} subscribers',
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),

          // Description
          if (artistData.description != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                artistData.description!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ),

          // Entity type badge (for channels)
          if (!artistData.isMusicArtist)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Channel',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),

          const SizedBox(height: 32),

          // Action buttons (from YTM navigation endpoints)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildActionButton(Icons.shuffle, 'Shuffle', () {
                if (topTracks.isNotEmpty) {
                  final shuffled = List<Track>.from(topTracks)..shuffle();
                  playerService.playQueue(
                    shuffled,
                    startIndex: 0,
                    sourceId: artistData.id,
                  );
                }
              }),

              // Main play button
              Container(
                height: 64,
                width: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: themeColor,
                ),
                child: IconButton(
                  icon: Icon(
                    isArtistPlaying && isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                  ),
                  iconSize: 36,
                  onPressed: () {
                    if (topTracks.isNotEmpty) {
                      if (isArtistPlaying && isPlaying) {
                        playerService.pause();
                      } else {
                        playerService.playQueue(
                          topTracks,
                          startIndex: 0,
                          sourceId: artistData.id,
                        );
                      }
                    }
                  },
                ),
              ),

              _buildActionButton(Icons.radio, 'Radio', () {
                if (topTracks.isNotEmpty) {
                  playerService.playTrack(topTracks.first, enableRadio: true);
                }
              }),
            ],
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.1),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildLocalTracksSection(BuildContext context, WidgetRef ref) {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Icon(Icons.download_done, size: 18, color: Colors.green[400]),
              const SizedBox(width: 8),
              const Text(
                'Downloaded',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final track = artistData.localTracks[index];
          return _buildTrackTile(
            context,
            ref,
            track,
            artistData.localTracks,
            index,
          );
        }, childCount: artistData.localTracks.take(3).length),
      ),
      if (artistData.localTracks.length > 3)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextButton(
              onPressed: () {
                // Show all local tracks
              },
              child: Text(
                'Show all ${artistData.localTracks.length} downloaded',
              ),
            ),
          ),
        ),
      const SliverToBoxAdapter(
        child: Divider(color: Colors.white24, height: 32),
      ),
    ];
  }

  List<Widget> _buildShelfSection(
    BuildContext context,
    WidgetRef ref,
    ArtistShelf shelf,
    Color themeColor,
  ) {
    if (shelf.isEmpty) return [];

    switch (shelf.type) {
      case ArtistShelfType.songs:
        return _buildSongsShelf(context, ref, shelf);
      case ArtistShelfType.albums:
      case ArtistShelfType.singles:
      case ArtistShelfType.eps:
      case ArtistShelfType.appearsOn:
        return _buildAlbumsShelf(context, shelf);
      case ArtistShelfType.playlists:
        return _buildPlaylistsShelf(context, shelf);
      case ArtistShelfType.similar:
        return _buildSimilarArtistsShelf(context, shelf);
      default:
        return [];
    }
  }

  List<Widget> _buildSongsShelf(
    BuildContext context,
    WidgetRef ref,
    ArtistShelf shelf,
  ) {
    final tracks = shelf.tracks;

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                shelf.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (shelf.hasMore)
                TextButton(
                  onPressed: () {
                    // Navigate to full songs list
                    final songsShelf = HomeShelf(
                      id: shelf.browseId ?? artistData.id,
                      title: '${artistData.name} - ${shelf.title}',
                      type: HomeShelfType.unknown,
                      items: tracks
                          .map(
                            (t) => HomeShelfItem(
                              id: t.id,
                              title: t.title,
                              subtitle: t.artist,
                              thumbnailUrl: t.thumbnailUrl,
                              itemType: HomeShelfItemType.song,
                              videoId: t.id,
                            ),
                          )
                          .toList(),
                      browseId: shelf.browseId,
                      params: shelf.params,
                    );
                    ShelfDetailsScreen.open(context, songsShelf);
                  },
                  child: const Text(
                    'See all',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
            ],
          ),
        ),
      ),
      SliverFixedExtentList(
        itemExtent: 72,
        delegate: SliverChildBuilderDelegate((context, index) {
          final track = tracks[index];
          return _buildTrackTile(context, ref, track, tracks, index);
        }, childCount: tracks.take(5).length),
      ),
    ];
  }

  Widget _buildTrackTile(
    BuildContext context,
    WidgetRef ref,
    Track track,
    List<Track> queue,
    int index,
  ) {
    final isTrackPlaying = currentTrack?.id == track.id;
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                  memCacheWidth: 96,
                  memCacheHeight: 96,
                )
              : Container(color: Colors.grey[800]),
        ),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isTrackPlaying ? colorScheme.primary : Colors.white,
          fontWeight: isTrackPlaying ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      subtitle: Text(
        '${track.artist}${track.formattedDuration.isNotEmpty && track.formattedDuration != '0:00' ? ' • ${track.formattedDuration}' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isTrackPlaying
              ? colorScheme.primary.withValues(alpha: 0.7)
              : Colors.white60,
        ),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.more_vert, color: Colors.white54),
        onPressed: () => TrackOptionsSheet.show(context, track),
      ),
      onTap: () {
        playerService.playQueue(
          queue,
          startIndex: index,
          sourceId: artistData.id,
        );
      },
    );
  }

  List<Widget> _buildAlbumsShelf(BuildContext context, ArtistShelf shelf) {
    final albums = shelf.albums;

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            shelf.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: SizedBox(
          height: 200,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: albums.length,
            itemBuilder: (context, index) {
              final album = albums[index];
              return _buildAlbumCard(context, album);
            },
          ),
        ),
      ),
    ];
  }

  Widget _buildAlbumCard(BuildContext context, Album album) {
    return GestureDetector(
      onTap: () => AlbumScreen.open(
        context,
        albumId: album.id,
        title: album.title,
        thumbnailUrl: album.thumbnailUrl,
      ),
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 140,
                height: 140,
                child: album.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: album.thumbnailUrl!,
                        fit: BoxFit.cover,
                      )
                    : Container(color: Colors.grey[800]),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              album.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              album.year ?? 'Album',
              maxLines: 1,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPlaylistsShelf(BuildContext context, ArtistShelf shelf) {
    final playlists = shelf.playlists;

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            shelf.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final playlist = playlists[index];
          return ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 48,
                height: 48,
                child: playlist.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: playlist.thumbnailUrl!,
                        fit: BoxFit.cover,
                      )
                    : Container(color: Colors.grey[800]),
              ),
            ),
            title: Text(
              playlist.title,
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              playlist.author ?? 'Playlist',
              style: const TextStyle(color: Colors.white60),
            ),
            onTap: () => PlaylistScreen.open(
              context,
              playlistId: playlist.id,
              title: playlist.title,
              thumbnailUrl: playlist.thumbnailUrl,
            ),
          );
        }, childCount: playlists.length),
      ),
    ];
  }

  List<Widget> _buildSimilarArtistsShelf(
    BuildContext context,
    ArtistShelf shelf,
  ) {
    final artists = shelf.artists;

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            shelf.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: SizedBox(
          height: 160,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: artists.length,
            itemBuilder: (context, index) {
              final artist = artists[index];
              return GestureDetector(
                onTap: () => ArtistPageScreen.open(
                  context,
                  artistId: artist.id,
                  name: artist.name,
                  thumbnailUrl: artist.thumbnailUrl,
                ),
                child: Container(
                  width: 120,
                  margin: const EdgeInsets.only(right: 16),
                  child: Column(
                    children: [
                      ClipOval(
                        child: SizedBox(
                          width: 100,
                          height: 100,
                          child: artist.thumbnailUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: artist.thumbnailUrl!,
                                  fit: BoxFit.cover,
                                )
                              : Container(color: Colors.grey[800]),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        artist.name,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ];
  }

  void _showOptionsSheet(BuildContext context, WidgetRef ref) {
    final topTracks = artistData.topTracks;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[700],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: ClipOval(
                  child: SizedBox(
                    width: 50,
                    height: 50,
                    child: artistData.thumbnailUrl != null
                        ? CachedNetworkImage(
                            imageUrl: artistData.thumbnailUrl!,
                            fit: BoxFit.cover,
                          )
                        : Container(color: Colors.grey[800]),
                  ),
                ),
                title: Text(
                  artistData.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: artistData.subscriberCount != null
                    ? Text(
                        '${_formatNumber(artistData.subscriberCount!)} subscribers',
                        style: const TextStyle(color: Colors.white54),
                      )
                    : null,
              ),
              const Divider(color: Colors.grey),
              ListTile(
                leading: const Icon(Icons.play_arrow, color: Colors.white),
                title: const Text(
                  'Play all',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  if (topTracks.isNotEmpty) {
                    playerService.playQueue(
                      topTracks,
                      startIndex: 0,
                      sourceId: artistData.id,
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.shuffle, color: Colors.white),
                title: const Text(
                  'Shuffle all',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  if (topTracks.isNotEmpty) {
                    final shuffled = List<Track>.from(topTracks)..shuffle();
                    playerService.playQueue(
                      shuffled,
                      startIndex: 0,
                      sourceId: artistData.id,
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.radio, color: Colors.white),
                title: const Text(
                  'Start radio',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  if (topTracks.isNotEmpty) {
                    playerService.playTrack(topTracks.first, enableRadio: true);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.share, color: Colors.white),
                title: const Text(
                  'Share',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  final url =
                      'https://music.youtube.com/channel/${artistData.id}';
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Link: $url')));
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    }
    if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }
}
