import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import 'track_options_sheet.dart';
import 'playlist_screen.dart';
import 'album_screen.dart';
import 'artist_screen.dart';
import 'now_playing_screen.dart';
import 'mini_player.dart';

/// Screen to display all items in a shelf when "More" is tapped
/// Supports infinite scroll pagination
class ShelfDetailsScreen extends ConsumerStatefulWidget {
  final HomeShelf shelf;

  const ShelfDetailsScreen({super.key, required this.shelf});

  static void open(BuildContext context, HomeShelf shelf) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ShelfDetailsScreen(shelf: shelf)),
    );
  }

  @override
  ConsumerState<ShelfDetailsScreen> createState() => _ShelfDetailsScreenState();
}

class _ShelfDetailsScreenState extends ConsumerState<ShelfDetailsScreen> {
  final ScrollController _scrollController = ScrollController();

  List<HomeShelfItem> _items = [];
  String? _continuationToken;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Start with shelf items
    _items = List.from(widget.shelf.items);

    // Fetch more items immediately if browseId is available
    if (widget.shelf.browseId != null) {
      _fetchInitialItems();
    }

    // Setup scroll listener for infinite scroll
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 500) {
      _loadMore();
    }
  }

  Future<void> _fetchInitialItems() async {
    if (_isLoading || widget.shelf.browseId == null) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final innerTube = ref.read(innerTubeServiceProvider);
      final result = await innerTube.browseShelf(
        widget.shelf.browseId!,
        params: widget.shelf.params,
      );

      if (mounted) {
        setState(() {
          // Merge new items with existing, avoiding duplicates
          final existingIds = _items.map((i) => i.id).toSet();
          final newItems = result.items.where(
            (i) => !existingIds.contains(i.id),
          );
          _items.addAll(newItems);
          _continuationToken = result.continuationToken;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || _continuationToken == null) return;

    setState(() => _isLoadingMore = true);

    try {
      final innerTube = ref.read(innerTubeServiceProvider);
      final result = await innerTube.browseShelf(
        widget.shelf.browseId!,
        continuationToken: _continuationToken,
        params: widget.shelf.params,
      );

      if (mounted) {
        setState(() {
          // Add new items avoiding duplicates
          final existingIds = _items.map((i) => i.id).toSet();
          final newItems = result.items.where(
            (i) => !existingIds.contains(i.id),
          );
          _items.addAll(newItems);
          _continuationToken = result.continuationToken;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final playerService = ref.read(audioPlayerServiceProvider);
    final currentTrack = ref.watch(currentTrackProvider);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.shelf.title,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: isDark ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Shelf description/strapline
          if (widget.shelf.strapline != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                widget.shelf.strapline!,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
            ),

          Expanded(
            child: _buildContent(
              isDark,
              colorScheme,
              playerService,
              currentTrack,
            ),
          ),

          // Mini player
          if (currentTrack != null)
            MusicMiniPlayer(onTap: () => NowPlayingScreen.show(context)),
        ],
      ),
    );
  }

  Widget _buildContent(
    bool isDark,
    ColorScheme colorScheme,
    dynamic playerService,
    Track? currentTrack,
  ) {
    // Determine content type
    final hasTracks = _items.any((i) => i.itemType == HomeShelfItemType.song);
    final hasArtists = _items.any(
      (i) => i.itemType == HomeShelfItemType.artist,
    );

    // Loading state
    if (_isLoading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // Error state
    if (_hasError && _items.isEmpty) {
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
              'Failed to load content',
              style: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _fetchInitialItems,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // Track list
    if (hasTracks) {
      return _buildTrackList(isDark, colorScheme, playerService, currentTrack);
    }

    // Grid of albums/playlists/artists
    return _buildItemGrid(isDark, colorScheme, hasArtists);
  }

  Widget _buildTrackList(
    bool isDark,
    ColorScheme colorScheme,
    dynamic playerService,
    Track? currentTrack,
  ) {
    final tracks = _items
        .where((i) => i.itemType == HomeShelfItemType.song)
        .map((i) => i.toTrack())
        .whereType<Track>()
        .toList();

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 100),
      itemCount:
          tracks.length +
          (_isLoadingMore || _continuationToken != null ? 1 : 0),
      itemBuilder: (context, index) {
        // Loading indicator at the end
        if (index >= tracks.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: _isLoadingMore
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : _continuationToken != null
                  ? TextButton(
                      onPressed: _loadMore,
                      child: const Text('Load more'),
                    )
                  : const SizedBox.shrink(),
            ),
          );
        }

        final track = tracks[index];
        final isCurrentTrack = currentTrack?.id == track.id;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          selected: isCurrentTrack,
          selectedTileColor: colorScheme.primary.withValues(alpha: 0.1),
          leading: ClipRRect(
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
                      color: colorScheme.primaryContainer,
                      child: Icon(Iconsax.music, color: colorScheme.primary),
                    ),
            ),
          ),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: isCurrentTrack ? FontWeight.bold : FontWeight.w500,
              color: isCurrentTrack
                  ? colorScheme.primary
                  : (isDark ? Colors.white : Colors.black),
            ),
          ),
          subtitle: Text(
            track.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
          ),
          trailing: IconButton(
            icon: Icon(
              Icons.more_vert,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
            onPressed: () => TrackOptionsSheet.show(context, track),
          ),
          onTap: () {
            playerService.playQueue(tracks, startIndex: index);
            NowPlayingScreen.show(context);
          },
        );
      },
    );
  }

  Widget _buildItemGrid(bool isDark, ColorScheme colorScheme, bool isArtists) {
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: isArtists ? 0.85 : 0.8,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount:
          _items.length +
          (_isLoadingMore || _continuationToken != null ? 1 : 0),
      itemBuilder: (context, index) {
        // Loading indicator at the end
        if (index >= _items.length) {
          return Center(
            child: _isLoadingMore
                ? const CircularProgressIndicator(strokeWidth: 2)
                : _continuationToken != null
                ? IconButton(
                    onPressed: _loadMore,
                    icon: const Icon(Icons.refresh),
                  )
                : const SizedBox.shrink(),
          );
        }

        final item = _items[index];
        return _buildGridItem(item, isDark, colorScheme, isArtists);
      },
    );
  }

  Widget _buildGridItem(
    HomeShelfItem item,
    bool isDark,
    ColorScheme colorScheme,
    bool isCircular,
  ) {
    return GestureDetector(
      onTap: () => _navigateToItem(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(isCircular ? 100 : 12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(isCircular ? 100 : 12),
                  child: item.thumbnailUrl != null
                      ? CachedNetworkImage(
                          imageUrl: item.thumbnailUrl!,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: colorScheme.primaryContainer,
                          child: Icon(
                            _getIconForType(item.itemType),
                            color: colorScheme.primary,
                            size: 48,
                          ),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          if (item.subtitle != null)
            Text(
              item.subtitle!,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
        ],
      ),
    );
  }

  void _navigateToItem(HomeShelfItem item) {
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
        // For songs, play them
        final track = item.toTrack();
        if (track != null) {
          final playerService = ref.read(audioPlayerServiceProvider);
          playerService.playTrack(track, enableRadio: true);
          NowPlayingScreen.show(context);
        }
        break;
    }
  }

  IconData _getIconForType(HomeShelfItemType type) {
    switch (type) {
      case HomeShelfItemType.playlist:
      case HomeShelfItemType.mix:
        return Iconsax.music_playlist;
      case HomeShelfItemType.album:
        return Iconsax.music_dashboard;
      case HomeShelfItemType.artist:
        return Iconsax.profile_2user;
      default:
        return Iconsax.music;
    }
  }
}
