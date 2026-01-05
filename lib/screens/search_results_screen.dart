import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/design_system/design_system.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import 'widgets/playlist_screen.dart';
import 'widgets/album_screen.dart';
import 'widgets/artist_screen.dart';
import 'widgets/now_playing_screen.dart';
import 'widgets/track_options_sheet.dart';

/// Provider for full search results (tracks, albums, artists, playlists)
final fullSearchResultsProvider = FutureProvider.autoDispose<SearchResults>((
  ref,
) async {
  final query = ref.watch(searchQueryProvider);
  if (query.trim().isEmpty) {
    return SearchResults.empty('');
  }

  // Debounce search
  await Future.delayed(const Duration(milliseconds: 300));

  // Check if query changed during debounce
  if (ref.read(searchQueryProvider) != query) {
    throw Exception('Query changed');
  }

  // Use InnerTube for full search results
  final innerTube = ref.watch(innerTubeServiceProvider);
  return innerTube.search(query);
});

/// Full-featured search results screen like YTM/Outertune
class SearchResultsScreen extends ConsumerStatefulWidget {
  const SearchResultsScreen({super.key});

  @override
  ConsumerState<SearchResultsScreen> createState() =>
      _SearchResultsScreenState();
}

class _SearchResultsScreenState extends ConsumerState<SearchResultsScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  List<String> _suggestions = [];
  String _selectedFilter = 'All';

  final _filters = ['All', 'Songs', 'Albums', 'Artists', 'Playlists'];

  @override
  void initState() {
    super.initState();
    // Auto-focus search field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    ref.read(searchQueryProvider.notifier).state = query;
    if (query.isNotEmpty) {
      // Load suggestions
      final innerTube = ref.read(innerTubeServiceProvider);
      innerTube
          .getSearchSuggestions(query)
          .then((suggestions) {
            if (mounted && suggestions.isNotEmpty) {
              setState(() => _suggestions = suggestions);
            }
          })
          .catchError((_) {});
    } else {
      setState(() => _suggestions = []);
    }
  }

  void _performSearch(String query) {
    _searchController.text = query;
    ref.read(searchQueryProvider.notifier).state = query;
    _searchFocusNode.unfocus();
    setState(() => _suggestions = []);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final searchQuery = ref.watch(searchQueryProvider);

    return Scaffold(
      backgroundColor: isDark
          ? MineColors.darkBackground
          : MineColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Search bar
            _buildSearchBar(isDark, colorScheme),

            // Filter chips
            if (searchQuery.isNotEmpty) _buildFilterChips(isDark, colorScheme),

            // Content
            Expanded(
              child: searchQuery.isEmpty
                  ? _buildSuggestions(isDark, colorScheme)
                  : _buildSearchResults(isDark, colorScheme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(bool isDark, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          // Back button
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.arrow_back_rounded,
              color: isDark ? Colors.white : MineColors.textPrimary,
            ),
          ),
          // Search field
          Expanded(
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: isDark ? Colors.white54 : MineColors.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      onChanged: _onSearchChanged,
                      onSubmitted: _performSearch,
                      style: TextStyle(
                        color: isDark ? Colors.white : MineColors.textPrimary,
                        fontSize: 15,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search songs, albums, artists',
                        hintStyle: TextStyle(
                          color: isDark
                              ? Colors.white54
                              : MineColors.textSecondary,
                          fontSize: 15,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                      child: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: isDark
                            ? Colors.white54
                            : MineColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(bool isDark, ColorScheme colorScheme) {
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _filters.length,
        itemBuilder: (context, index) {
          final filter = _filters[index];
          final isSelected = _selectedFilter == filter;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(filter),
              selected: isSelected,
              onSelected: (_) => setState(() => _selectedFilter = filter),
              backgroundColor: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.grey.shade100,
              selectedColor: colorScheme.primary.withValues(alpha: 0.2),
              labelStyle: TextStyle(
                color: isSelected
                    ? colorScheme.primary
                    : (isDark ? Colors.white70 : MineColors.textPrimary),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 13,
              ),
              side: BorderSide.none,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSuggestions(bool isDark, ColorScheme colorScheme) {
    if (_suggestions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_rounded,
              size: 64,
              color: isDark ? Colors.white24 : Colors.black12,
            ),
            const SizedBox(height: 16),
            Text(
              'Search for music',
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white54 : MineColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _suggestions.length,
      itemBuilder: (context, index) {
        return ListTile(
          leading: Icon(
            Icons.search_rounded,
            color: isDark ? Colors.white54 : MineColors.textSecondary,
          ),
          title: Text(
            _suggestions[index],
            style: TextStyle(
              color: isDark ? Colors.white : MineColors.textPrimary,
            ),
          ),
          trailing: IconButton(
            onPressed: () {
              _searchController.text = _suggestions[index];
              _searchController.selection = TextSelection.fromPosition(
                TextPosition(offset: _suggestions[index].length),
              );
              _onSearchChanged(_suggestions[index]);
            },
            icon: Icon(
              Icons.north_west_rounded,
              size: 18,
              color: isDark ? Colors.white38 : MineColors.textSecondary,
            ),
          ),
          onTap: () => _performSearch(_suggestions[index]),
        );
      },
    );
  }

  Widget _buildSearchResults(bool isDark, ColorScheme colorScheme) {
    final searchResults = ref.watch(fullSearchResultsProvider);

    return searchResults.when(
      data: (results) {
        // Filter results based on selected filter
        final hasResults =
            results.tracks.isNotEmpty ||
            results.albums.isNotEmpty ||
            results.artists.isNotEmpty ||
            results.playlists.isNotEmpty;

        if (!hasResults) {
          return _buildEmptyResults(isDark);
        }

        return ListView(
          padding: const EdgeInsets.only(bottom: 100),
          children: [
            // Top result (first artist or first track)
            if (_selectedFilter == 'All') ...[
              if (results.artists.isNotEmpty)
                _buildTopResult(results.artists.first, isDark, colorScheme)
              else if (results.tracks.isNotEmpty)
                _buildTopResultTrack(results.tracks.first, isDark, colorScheme),
            ],

            // Songs section
            if ((_selectedFilter == 'All' || _selectedFilter == 'Songs') &&
                results.tracks.isNotEmpty)
              _buildSongsSection(results.tracks, isDark, colorScheme),

            // Artists section
            if ((_selectedFilter == 'All' || _selectedFilter == 'Artists') &&
                results.artists.isNotEmpty)
              _buildArtistsSection(results.artists, isDark, colorScheme),

            // Albums section
            if ((_selectedFilter == 'All' || _selectedFilter == 'Albums') &&
                results.albums.isNotEmpty)
              _buildAlbumsSection(results.albums, isDark, colorScheme),

            // Playlists section
            if ((_selectedFilter == 'All' || _selectedFilter == 'Playlists') &&
                results.playlists.isNotEmpty)
              _buildPlaylistsSection(results.playlists, isDark, colorScheme),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) {
        if (e.toString().contains('Query changed')) {
          return const Center(child: CircularProgressIndicator());
        }
        return _buildEmptyResults(isDark);
      },
    );
  }

  Widget _buildEmptyResults(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 64,
            color: isDark ? Colors.white24 : Colors.black12,
          ),
          const SizedBox(height: 16),
          Text(
            'No results found',
            style: TextStyle(
              fontSize: 16,
              color: isDark ? Colors.white54 : MineColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopResult(Artist artist, bool isDark, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Top result',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : MineColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => ArtistScreen.open(
              context,
              artistId: artist.id,
              name: artist.name,
              thumbnailUrl: artist.thumbnailUrl,
            ),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(40),
                    child: SizedBox(
                      width: 80,
                      height: 80,
                      child: artist.thumbnailUrl != null
                          ? CachedNetworkImage(
                              imageUrl: artist.thumbnailUrl!,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => _defaultArtwork(
                                colorScheme,
                                Icons.person_rounded,
                              ),
                              errorWidget: (_, __, ___) => _defaultArtwork(
                                colorScheme,
                                Icons.person_rounded,
                              ),
                            )
                          : _defaultArtwork(colorScheme, Icons.person_rounded),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          artist.name,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.white
                                : MineColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Artist${artist.formattedSubscribers != null ? ' • ${artist.formattedSubscribers}' : ''}',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? Colors.white54
                                : MineColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopResultTrack(
    Track track,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Top result',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : MineColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          _buildTrackTile(track, isDark, colorScheme, isLarge: true),
        ],
      ),
    );
  }

  Widget _buildSongsSection(
    List<Track> tracks,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    final displayTracks = _selectedFilter == 'Songs'
        ? tracks
        : tracks.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_selectedFilter == 'All')
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Songs',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : MineColors.textPrimary,
              ),
            ),
          ),
        ...displayTracks.map(
          (track) => _buildTrackTile(track, isDark, colorScheme),
        ),
      ],
    );
  }

  Widget _buildTrackTile(
    Track track,
    bool isDark,
    ColorScheme colorScheme, {
    bool isLarge = false,
  }) {
    final playerService = ref.watch(audioPlayerServiceProvider);
    final playbackState = ref.watch(playbackStateProvider);
    final isCurrentTrack =
        playbackState.whenOrNull(data: (s) => s.currentTrack?.id == track.id) ??
        false;

    return ListTile(
      contentPadding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: isLarge ? 8 : 2,
      ),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(isLarge ? 8 : 6),
        child: SizedBox(
          width: isLarge ? 64 : 48,
          height: isLarge ? 64 : 48,
          child: track.thumbnailUrl != null
              ? CachedNetworkImage(
                  imageUrl: track.thumbnailUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      _defaultArtwork(colorScheme, Icons.music_note_rounded),
                  errorWidget: (_, __, ___) =>
                      _defaultArtwork(colorScheme, Icons.music_note_rounded),
                )
              : _defaultArtwork(colorScheme, Icons.music_note_rounded),
        ),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: isLarge ? 16 : 14,
          fontWeight: isCurrentTrack ? FontWeight.w600 : FontWeight.w500,
          color: isCurrentTrack
              ? colorScheme.primary
              : (isDark ? Colors.white : MineColors.textPrimary),
        ),
      ),
      subtitle: Text(
        '${track.artist}${track.formattedDuration.isNotEmpty ? ' • ${track.formattedDuration}' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: isDark ? Colors.white54 : MineColors.textSecondary,
        ),
      ),
      trailing: IconButton(
        onPressed: () => TrackOptionsSheet.show(context, track),
        icon: Icon(
          Icons.more_vert_rounded,
          color: isDark ? Colors.white54 : MineColors.textSecondary,
        ),
      ),
      onTap: () async {
        await playerService.playTrack(track, enableRadio: true);
        ref.read(recentlyPlayedProvider.notifier).addTrack(track);
        if (mounted) NowPlayingScreen.show(context);
      },
    );
  }

  Widget _buildArtistsSection(
    List<Artist> artists,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    final displayArtists = _selectedFilter == 'Artists'
        ? artists
        : artists.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_selectedFilter == 'All')
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
              'Artists',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : MineColors.textPrimary,
              ),
            ),
          ),
        if (_selectedFilter == 'Artists')
          ...displayArtists.map(
            (artist) => _buildArtistTile(artist, isDark, colorScheme),
          )
        else
          SizedBox(
            height: 160,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: displayArtists.length,
              itemBuilder: (context, index) {
                return _buildArtistCard(
                  displayArtists[index],
                  isDark,
                  colorScheme,
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildArtistTile(Artist artist, bool isDark, ColorScheme colorScheme) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          width: 48,
          height: 48,
          child: artist.thumbnailUrl != null
              ? CachedNetworkImage(
                  imageUrl: artist.thumbnailUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      _defaultArtwork(colorScheme, Icons.person_rounded),
                  errorWidget: (_, __, ___) =>
                      _defaultArtwork(colorScheme, Icons.person_rounded),
                )
              : _defaultArtwork(colorScheme, Icons.person_rounded),
        ),
      ),
      title: Text(
        artist.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: isDark ? Colors.white : MineColors.textPrimary,
        ),
      ),
      subtitle: Text(
        'Artist${artist.formattedSubscribers != null ? ' • ${artist.formattedSubscribers}' : ''}',
        style: TextStyle(
          fontSize: 12,
          color: isDark ? Colors.white54 : MineColors.textSecondary,
        ),
      ),
      onTap: () => ArtistScreen.open(
        context,
        artistId: artist.id,
        name: artist.name,
        thumbnailUrl: artist.thumbnailUrl,
      ),
    );
  }

  Widget _buildArtistCard(Artist artist, bool isDark, ColorScheme colorScheme) {
    return GestureDetector(
      onTap: () => ArtistScreen.open(
        context,
        artistId: artist.id,
        name: artist.name,
        thumbnailUrl: artist.thumbnailUrl,
      ),
      child: Container(
        width: 120,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(60),
              child: SizedBox(
                width: 100,
                height: 100,
                child: artist.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: artist.thumbnailUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            _defaultArtwork(colorScheme, Icons.person_rounded),
                        errorWidget: (_, __, ___) =>
                            _defaultArtwork(colorScheme, Icons.person_rounded),
                      )
                    : _defaultArtwork(colorScheme, Icons.person_rounded),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              artist.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : MineColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumsSection(
    List<Album> albums,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    final displayAlbums = _selectedFilter == 'Albums'
        ? albums
        : albums.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_selectedFilter == 'All')
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
              'Albums',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : MineColors.textPrimary,
              ),
            ),
          ),
        if (_selectedFilter == 'Albums')
          ...displayAlbums.map(
            (album) => _buildAlbumTile(album, isDark, colorScheme),
          )
        else
          SizedBox(
            height: 200,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: displayAlbums.length,
              itemBuilder: (context, index) {
                return _buildAlbumCard(
                  displayAlbums[index],
                  isDark,
                  colorScheme,
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildAlbumTile(Album album, bool isDark, ColorScheme colorScheme) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 48,
          height: 48,
          child: album.thumbnailUrl != null
              ? CachedNetworkImage(
                  imageUrl: album.thumbnailUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      _defaultArtwork(colorScheme, Icons.album_rounded),
                  errorWidget: (_, __, ___) =>
                      _defaultArtwork(colorScheme, Icons.album_rounded),
                )
              : _defaultArtwork(colorScheme, Icons.album_rounded),
        ),
      ),
      title: Text(
        album.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: isDark ? Colors.white : MineColors.textPrimary,
        ),
      ),
      subtitle: Text(
        '${album.artist}${album.year != null ? ' • ${album.year}' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: isDark ? Colors.white54 : MineColors.textSecondary,
        ),
      ),
      onTap: () => AlbumScreen.open(
        context,
        albumId: album.id,
        title: album.title,
        thumbnailUrl: album.thumbnailUrl,
      ),
    );
  }

  Widget _buildAlbumCard(Album album, bool isDark, ColorScheme colorScheme) {
    return GestureDetector(
      onTap: () => AlbumScreen.open(
        context,
        albumId: album.id,
        title: album.title,
        thumbnailUrl: album.thumbnailUrl,
      ),
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 12),
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
                        placeholder: (_, __) =>
                            _defaultArtwork(colorScheme, Icons.album_rounded),
                        errorWidget: (_, __, ___) =>
                            _defaultArtwork(colorScheme, Icons.album_rounded),
                      )
                    : _defaultArtwork(colorScheme, Icons.album_rounded),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              album.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : MineColors.textPrimary,
              ),
            ),
            Text(
              album.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white54 : MineColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistsSection(
    List<Playlist> playlists,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    final displayPlaylists = _selectedFilter == 'Playlists'
        ? playlists
        : playlists.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_selectedFilter == 'All')
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
              'Playlists',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : MineColors.textPrimary,
              ),
            ),
          ),
        ...displayPlaylists.map(
          (playlist) => _buildPlaylistTile(playlist, isDark, colorScheme),
        ),
      ],
    );
  }

  Widget _buildPlaylistTile(
    Playlist playlist,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 48,
          height: 48,
          child: playlist.thumbnailUrl != null
              ? CachedNetworkImage(
                  imageUrl: playlist.thumbnailUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      _defaultArtwork(colorScheme, Icons.queue_music_rounded),
                  errorWidget: (_, __, ___) =>
                      _defaultArtwork(colorScheme, Icons.queue_music_rounded),
                )
              : _defaultArtwork(colorScheme, Icons.queue_music_rounded),
        ),
      ),
      title: Text(
        playlist.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: isDark ? Colors.white : MineColors.textPrimary,
        ),
      ),
      subtitle: Text(
        '${playlist.author ?? 'Playlist'}${playlist.trackCount != null ? ' • ${playlist.trackCount} songs' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: isDark ? Colors.white54 : MineColors.textSecondary,
        ),
      ),
      onTap: () => PlaylistScreen.open(
        context,
        playlistId: playlist.id,
        title: playlist.title,
        thumbnailUrl: playlist.thumbnailUrl,
      ),
    );
  }

  Widget _defaultArtwork(ColorScheme colorScheme, IconData icon) {
    return Container(
      color: colorScheme.primaryContainer,
      child: Icon(icon, color: colorScheme.primary, size: 24),
    );
  }
}
