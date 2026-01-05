import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/design_system/design_system.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import '../services/search_service.dart';
import '../services/download_service.dart';
import '../services/local_music_scanner.dart';
import 'widgets/playlist_screen.dart';
import 'widgets/album_screen.dart';
import 'widgets/artist_screen.dart';
import 'widgets/now_playing_screen.dart';
import 'widgets/track_options_sheet.dart';

// ============ PROVIDERS ============

/// Search service provider
final searchServiceProvider = Provider<SearchService>((ref) {
  final innerTube = ref.watch(innerTubeServiceProvider);
  return SearchService(innerTube);
});

/// Current search filter
final searchFilterProvider = StateProvider<SearchFilter>(
  (ref) => SearchFilter.all,
);

/// Enhanced search results provider with local + online merge
/// Uses proper debouncing and lets YouTube handle intent detection
final enhancedSearchProvider =
    FutureProvider.autoDispose<EnhancedSearchResults>((ref) async {
      final query = ref.watch(searchQueryProvider);
      final filter = ref.watch(searchFilterProvider);

      if (query.trim().isEmpty) {
        return EnhancedSearchResults.empty('');
      }

      // Debounce: 300ms delay before searching
      // This prevents excessive API calls while typing
      await Future.delayed(const Duration(milliseconds: 300));

      // Check if query changed during debounce
      if (ref.read(searchQueryProvider) != query) {
        throw Exception('Query changed');
      }

      // Get local library for merged results
      final downloadedTracks =
          ref.read(downloadedTracksProvider).valueOrNull ?? [];
      final localTracks = ref.read(localTracksProvider);
      final allLocalTracks = [...downloadedTracks, ...localTracks];

      // Delegate search to YouTube Music (they handle intent detection)
      final searchService = ref.read(searchServiceProvider);
      return searchService.search(
        query,
        filter: filter,
        localLibrary: allLocalTracks.isNotEmpty ? allLocalTracks : null,
      );
    });

/// Search suggestions provider with debouncing
final searchSuggestionsEnhancedProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
      final query = ref.watch(searchQueryProvider);

      if (query.trim().length < 2) return [];

      // Shorter debounce for suggestions
      await Future.delayed(const Duration(milliseconds: 150));

      if (ref.read(searchQueryProvider) != query) {
        throw Exception('Query changed');
      }

      final searchService = ref.read(searchServiceProvider);
      return searchService.getSuggestions(query);
    });

// ============ SEARCH SCREEN ============

/// OuterTune-style search screen
///
/// Key design principles:
/// 1. Trust YouTube Music's intent detection and ranking
/// 2. Clean, grouped display of results by type
/// 3. Show "Top Result" prominently (YouTube's best guess)
/// 4. Merge local + online results
/// 5. Filter chips for type-specific searches
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    // Cancel any pending debounce
    _debounceTimer?.cancel();

    // Immediate update for UI responsiveness
    ref.read(searchQueryProvider.notifier).state = query;
  }

  void _performSearch(String query) {
    _searchController.text = query;
    ref.read(searchQueryProvider.notifier).state = query;
    _searchFocusNode.unfocus();
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(searchQueryProvider.notifier).state = '';
    ref.read(searchFilterProvider.notifier).state = SearchFilter.all;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final query = ref.watch(searchQueryProvider);

    return Scaffold(
      backgroundColor: isDark
          ? MineColors.darkBackground
          : MineColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchBar(isDark, colorScheme),
            if (query.isNotEmpty) _buildFilterChips(isDark, colorScheme),
            Expanded(
              child: query.isEmpty
                  ? _buildSuggestionsOrHistory(isDark, colorScheme)
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
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.arrow_back_rounded,
              color: isDark ? Colors.white : MineColors.textPrimary,
            ),
          ),
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
                      cursorColor: isDark ? Colors.white : colorScheme.primary,
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
                        focusedBorder: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    GestureDetector(
                      onTap: _clearSearch,
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
    final currentFilter = ref.watch(searchFilterProvider);

    final filters = [
      (SearchFilter.all, 'All'),
      (SearchFilter.songs, 'Songs'),
      (SearchFilter.albums, 'Albums'),
      (SearchFilter.artists, 'Artists'),
      (SearchFilter.playlists, 'Playlists'),
    ];

    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final (filter, label) = filters[index];
          final isSelected = currentFilter == filter;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(label),
              selected: isSelected,
              onSelected: (_) {
                ref.read(searchFilterProvider.notifier).state = filter;
              },
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

  Widget _buildSuggestionsOrHistory(bool isDark, ColorScheme colorScheme) {
    final suggestionsAsync = ref.watch(searchSuggestionsEnhancedProvider);

    return suggestionsAsync.when(
      data: (suggestions) {
        if (suggestions.isEmpty) {
          return _buildEmptyState(
            isDark,
            'Search for music',
            Icons.search_rounded,
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: suggestions.length,
          itemBuilder: (context, index) {
            return ListTile(
              leading: Icon(
                Icons.search_rounded,
                color: isDark ? Colors.white54 : MineColors.textSecondary,
              ),
              title: Text(
                suggestions[index],
                style: TextStyle(
                  color: isDark ? Colors.white : MineColors.textPrimary,
                ),
              ),
              trailing: IconButton(
                onPressed: () {
                  _searchController.text = suggestions[index];
                  _searchController.selection = TextSelection.fromPosition(
                    TextPosition(offset: suggestions[index].length),
                  );
                  _onSearchChanged(suggestions[index]);
                },
                icon: Icon(
                  Icons.north_west_rounded,
                  size: 18,
                  color: isDark ? Colors.white38 : MineColors.textSecondary,
                ),
              ),
              onTap: () => _performSearch(suggestions[index]),
            );
          },
        );
      },
      loading: () =>
          _buildEmptyState(isDark, 'Search for music', Icons.search_rounded),
      error: (_, __) =>
          _buildEmptyState(isDark, 'Search for music', Icons.search_rounded),
    );
  }

  Widget _buildSearchResults(bool isDark, ColorScheme colorScheme) {
    final resultsAsync = ref.watch(enhancedSearchProvider);
    final filter = ref.watch(searchFilterProvider);

    return resultsAsync.when(
      data: (results) {
        if (results.isEmpty) {
          return _buildEmptyState(
            isDark,
            'No results found',
            Icons.search_off_rounded,
          );
        }

        return ListView(
          padding: const EdgeInsets.only(bottom: 100),
          children: [
            // Local results section (if any)
            if (results.localTracks.isNotEmpty && filter == SearchFilter.all)
              _buildLocalResultsSection(
                results.localTracks,
                isDark,
                colorScheme,
              ),

            // Top Result (YouTube's best guess at intent)
            if (results.topResult != null && filter == SearchFilter.all)
              _buildTopResult(results.topResult!, isDark, colorScheme),

            // Songs section
            if ((filter == SearchFilter.all || filter == SearchFilter.songs) &&
                results.onlineTracks.isNotEmpty)
              _buildSongsSection(
                results.onlineTracks,
                isDark,
                colorScheme,
                filter,
              ),

            // Artists section
            if ((filter == SearchFilter.all ||
                    filter == SearchFilter.artists) &&
                results.onlineArtists.isNotEmpty)
              _buildArtistsSection(
                results.onlineArtists,
                isDark,
                colorScheme,
                filter,
              ),

            // Albums section
            if ((filter == SearchFilter.all || filter == SearchFilter.albums) &&
                results.onlineAlbums.isNotEmpty)
              _buildAlbumsSection(
                results.onlineAlbums,
                isDark,
                colorScheme,
                filter,
              ),

            // Playlists section
            if ((filter == SearchFilter.all ||
                    filter == SearchFilter.playlists) &&
                results.onlinePlaylists.isNotEmpty)
              _buildPlaylistsSection(
                results.onlinePlaylists,
                isDark,
                colorScheme,
                filter,
              ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) {
        if (e.toString().contains('Query changed')) {
          return const Center(child: CircularProgressIndicator());
        }
        return _buildEmptyState(
          isDark,
          'No results found',
          Icons.search_off_rounded,
        );
      },
    );
  }

  Widget _buildEmptyState(bool isDark, String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: isDark ? Colors.white24 : Colors.black12),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              color: isDark ? Colors.white54 : MineColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalResultsSection(
    List<Track> tracks,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(
                Icons.download_done_rounded,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Downloaded',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : MineColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        ...tracks
            .take(3)
            .map((track) => _buildTrackTile(track, isDark, colorScheme)),
        if (tracks.length > 3)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextButton(
              onPressed: () {
                // Show all local results
              },
              child: Text('Show all ${tracks.length} local results'),
            ),
          ),
        const Divider(height: 24),
      ],
    );
  }

  Widget _buildTopResult(
    TopResult topResult,
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
          _buildTopResultCard(topResult, isDark, colorScheme),
        ],
      ),
    );
  }

  Widget _buildTopResultCard(
    TopResult topResult,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    Widget content;
    VoidCallback? onTap;

    switch (topResult.type) {
      case SearchResultType.artist:
        final artist = topResult.artist!;
        onTap = () => ArtistScreen.open(
          context,
          artistId: artist.id,
          name: artist.name,
          thumbnailUrl: artist.thumbnailUrl,
        );
        content = Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(40),
              child: _buildImage(artist.thumbnailUrl, 80, Icons.person_rounded),
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
                      color: isDark ? Colors.white : MineColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Artist${artist.formattedSubscribers != null ? ' • ${artist.formattedSubscribers}' : ''}',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white54 : MineColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
        break;
      case SearchResultType.track:
        final track = topResult.track!;
        onTap = () async {
          final playerService = ref.read(audioPlayerServiceProvider);
          await playerService.playTrack(track, enableRadio: true);
          ref.read(recentlyPlayedProvider.notifier).addTrack(track);
          if (mounted) NowPlayingScreen.show(context);
        };
        content = _buildTrackTile(track, isDark, colorScheme, isLarge: true);
        break;
      case SearchResultType.album:
        final album = topResult.album!;
        onTap = () => AlbumScreen.open(
          context,
          albumId: album.id,
          title: album.title,
          thumbnailUrl: album.thumbnailUrl,
        );
        content = Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _buildImage(album.thumbnailUrl, 80, Icons.album_rounded),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : MineColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Album • ${album.artist}',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white54 : MineColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
        break;
      case SearchResultType.playlist:
        final playlist = topResult.playlist!;
        onTap = () => PlaylistScreen.open(
          context,
          playlistId: playlist.id,
          title: playlist.title,
          thumbnailUrl: playlist.thumbnailUrl,
        );
        content = Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _buildImage(
                playlist.thumbnailUrl,
                80,
                Icons.queue_music_rounded,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : MineColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Playlist • ${playlist.author ?? 'YouTube Music'}',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white54 : MineColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
        break;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
        ),
        child: content,
      ),
    );
  }

  Widget _buildSongsSection(
    List<Track> tracks,
    bool isDark,
    ColorScheme colorScheme,
    SearchFilter filter,
  ) {
    final displayTracks = filter == SearchFilter.songs
        ? tracks
        : tracks.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (filter == SearchFilter.all)
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
        child: _buildImage(
          track.thumbnailUrl,
          isLarge ? 64.0 : 48.0,
          Icons.music_note_rounded,
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
        '${track.artist}${track.formattedDuration.isNotEmpty && track.formattedDuration != '0:00' ? ' • ${track.formattedDuration}' : ''}',
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
    SearchFilter filter,
  ) {
    final displayArtists = filter == SearchFilter.artists
        ? artists
        : artists.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (filter == SearchFilter.all)
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
        if (filter == SearchFilter.artists)
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
              itemBuilder: (context, index) =>
                  _buildArtistCard(displayArtists[index], isDark, colorScheme),
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
        child: _buildImage(artist.thumbnailUrl, 48, Icons.person_rounded),
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
              child: _buildImage(
                artist.thumbnailUrl,
                100,
                Icons.person_rounded,
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
    SearchFilter filter,
  ) {
    final displayAlbums = filter == SearchFilter.albums
        ? albums
        : albums.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (filter == SearchFilter.all)
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
        if (filter == SearchFilter.albums)
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
              itemBuilder: (context, index) =>
                  _buildAlbumCard(displayAlbums[index], isDark, colorScheme),
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
        child: _buildImage(album.thumbnailUrl, 48, Icons.album_rounded),
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
              child: _buildImage(album.thumbnailUrl, 140, Icons.album_rounded),
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
    SearchFilter filter,
  ) {
    final displayPlaylists = filter == SearchFilter.playlists
        ? playlists
        : playlists.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (filter == SearchFilter.all)
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
        child: _buildImage(
          playlist.thumbnailUrl,
          48,
          Icons.queue_music_rounded,
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

  Widget _buildImage(String? url, double size, IconData fallbackIcon) {
    if (url == null) {
      return Container(
        width: size,
        height: size,
        color: Colors.grey[800],
        child: Icon(fallbackIcon, color: Colors.white54, size: size * 0.4),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      width: size,
      height: size,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(
        width: size,
        height: size,
        color: Colors.grey[800],
        child: Icon(fallbackIcon, color: Colors.white54, size: size * 0.4),
      ),
      errorWidget: (_, __, ___) => Container(
        width: size,
        height: size,
        color: Colors.grey[800],
        child: Icon(fallbackIcon, color: Colors.white54, size: size * 0.4),
      ),
    );
  }
}
