import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/design_system/design_system.dart';
import '../../core/l10n/app_localizations_x.dart';
import '../../providers/providers.dart';
import '../../providers/bookmarks_and_stats_provider.dart';
import '../../models/models.dart';
import '../../services/download_service.dart';
import '../widgets/playlist_screen.dart';
import '../widgets/now_playing_screen.dart';
import '../search_screen.dart';

/// Library tab with albums, artists, and playlists
class MusicLibraryTab extends ConsumerStatefulWidget {
  const MusicLibraryTab({super.key});

  @override
  ConsumerState<MusicLibraryTab> createState() => _MusicLibraryTabState();
}

class _MusicLibraryTabState extends ConsumerState<MusicLibraryTab> {
  int _selectedCategory = 0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Column(
        children: [
          // Header
          _buildHeader(isDark, colorScheme),

          // Category tabs
          _buildCategoryTabs(isDark, colorScheme),

          // Content
          Expanded(child: _buildContent(isDark, colorScheme)),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark, ColorScheme colorScheme) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            l10n.library,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : InzxColors.textPrimary,
            ),
          ),
          Row(
            children: [
              IconButton(
                onPressed: () {
                  // Navigate to search
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const SearchScreen(),
                    ),
                  );
                },
                icon: Icon(
                  Icons.search_rounded,
                  color: isDark ? Colors.white70 : InzxColors.textPrimary,
                ),
              ),
              IconButton(
                onPressed: () {
                  _showCreatePlaylistDialog();
                },
                icon: Icon(
                  Icons.add_rounded,
                  color: isDark ? Colors.white70 : InzxColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTabs(bool isDark, ColorScheme colorScheme) {
    final l10n = context.l10n;
    final accentColor = ref.watch(effectiveAccentColorProvider);
    final categories = [
      l10n.playlists,
      l10n.albums,
      l10n.artists,
      l10n.downloads,
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: List.generate(categories.length, (index) {
          final isSelected = _selectedCategory == index;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(categories[index]),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _selectedCategory = index);
                }
              },
              // Use dynamic accent color for selected state
              selectedColor: accentColor.withValues(alpha: 0.2),
              backgroundColor: isDark ? Colors.white10 : Colors.grey.shade100,
              labelStyle: TextStyle(
                color: isSelected
                    ? accentColor
                    : (isDark ? Colors.white70 : InzxColors.textPrimary),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 13,
              ),
              side: BorderSide(
                color: isSelected ? accentColor : Colors.transparent,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildContent(bool isDark, ColorScheme colorScheme) {
    switch (_selectedCategory) {
      case 0:
        return _buildPlaylistsView(isDark, colorScheme);
      case 1:
        return _buildAlbumsView(isDark, colorScheme);
      case 2:
        return _buildArtistsView(isDark, colorScheme);
      case 3:
        return _buildDownloadsView(isDark, colorScheme);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildPlaylistsView(bool isDark, ColorScheme colorScheme) {
    final l10n = context.l10n;
    final ytAuthState = ref.watch(ytMusicAuthStateProvider);
    final ytPlaylistsAsync = ytAuthState.isLoggedIn
        ? ref.watch(ytMusicSavedPlaylistsProvider)
        : const AsyncValue<List<Playlist>>.data([]);

    // Get counts for auto playlists
    final likedSongs = ref.watch(likedSongsProvider);
    final ytLikedSongs = ref.watch(ytMusicLikedSongsProvider).valueOrNull ?? [];
    final recentlyPlayed = ref.watch(recentlyPlayedProvider);
    final mostPlayed = ref.watch(mostPlayedTracksProvider);
    final downloadedTracks =
        ref.watch(downloadedTracksProvider).valueOrNull ?? [];
    final totalLiked = likedSongs.length + ytLikedSongs.length;

    // Auto playlists with dynamic counts
    final autoPlaylists = [
      (
        l10n.likedSongsLabel,
        Icons.favorite_rounded,
        Colors.pink,
        totalLiked,
        'liked',
      ),
      (
        l10n.mostPlayed,
        Icons.bar_chart_rounded,
        Colors.blue,
        mostPlayed.length,
        'most_played',
      ),
      (
        l10n.recentlyPlayed,
        Icons.history_rounded,
        Colors.orange,
        recentlyPlayed.length,
        'recent',
      ),
      (
        l10n.downloaded,
        Icons.download_rounded,
        Colors.green,
        downloadedTracks.length,
        'downloaded',
      ),
    ];

    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        // Auto playlists section
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text(
            l10n.autoPlaylists,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white54 : InzxColors.textSecondary,
            ),
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.85,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: autoPlaylists.length,
          itemBuilder: (context, index) {
            final playlist = autoPlaylists[index];
            return _buildAutoPlaylistCard(
              playlist.$1,
              playlist.$2,
              playlist.$3,
              playlist.$4,
              playlist.$5,
              isDark,
              colorScheme,
            );
          },
        ),

        const SizedBox(height: 24),

        // YouTube Music playlists
        if (ytAuthState.isLoggedIn) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Icon(Icons.music_note, size: 16, color: Colors.red),
                const SizedBox(width: 6),
                Text(
                  context.l10n.youtubeMusicPlaylists,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white54 : InzxColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          ytPlaylistsAsync.when(
            data: (playlists) => playlists.isEmpty
                ? _buildEmptyYTPlaylistsState(isDark, colorScheme)
                : _buildYTPlaylistsList(
                    playlists,
                    isDark,
                    colorScheme,
                    ytLikedSongs.length,
                  ),
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  context.l10n.errorLoadingPlaylists,
                  style: TextStyle(color: Colors.red.shade300),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],

        // User playlists section
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text(
            context.l10n.yourPlaylists,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white54 : InzxColors.textSecondary,
            ),
          ),
        ),
        _buildEmptyPlaylistsState(isDark, colorScheme),
      ],
    );
  }

  Widget _buildYTPlaylistsList(
    List<Playlist> playlists,
    bool isDark,
    ColorScheme colorScheme,
    int ytLikedSongsCount,
  ) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        final displayCount = _resolveYtPlaylistSongCount(
          playlist,
          ytLikedSongsCount,
        );
        return ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: playlist.thumbnailUrl != null
                ? CachedNetworkImage(
                    imageUrl: playlist.thumbnailUrl!,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: 56,
                    height: 56,
                    color: Colors.red.withValues(alpha: 0.2),
                    child: const Icon(
                      Icons.queue_music_rounded,
                      color: Colors.red,
                    ),
                  ),
          ),
          title: Text(
            playlist.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : InzxColors.textPrimary,
            ),
          ),
          subtitle: Text(
            context.l10n.songsCount(displayCount),
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : InzxColors.textSecondary,
            ),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            // Open playlist screen
            PlaylistScreen.open(
              context,
              playlistId: playlist.id,
              title: playlist.title,
              thumbnailUrl: playlist.thumbnailUrl,
            );
          },
        );
      },
    );
  }

  int _resolveYtPlaylistSongCount(Playlist playlist, int ytLikedSongsCount) {
    final parsedCount = playlist.trackCount ?? 0;
    if (parsedCount > 0) return parsedCount;

    final title = playlist.title.toLowerCase();
    final isLikedPlaylist =
        playlist.id == 'LM' ||
        playlist.id == 'VLLM' ||
        title == 'liked songs' ||
        title == 'liked music';

    if (isLikedPlaylist && ytLikedSongsCount > 0) {
      return ytLikedSongsCount;
    }

    return parsedCount;
  }

  Widget _buildEmptyYTPlaylistsState(bool isDark, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        context.l10n.noYoutubeMusicPlaylistsFound,
        style: TextStyle(
          color: isDark ? Colors.white38 : InzxColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildAutoPlaylistCard(
    String title,
    IconData icon,
    Color color,
    int count,
    String type,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    return InkWell(
      onTap: () => _openAutoPlaylist(type, title),
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 130,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: Icon(icon, size: 48, color: color)),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : InzxColors.textPrimary,
            ),
          ),
          Text(
            context.l10n.songsCount(count),
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : InzxColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  void _openAutoPlaylist(String type, String title) {
    // Special case: switch to Downloads tab
    if (type == 'downloaded') {
      setState(() {
        _selectedCategory = 3; // Downloads tab
      });
      return;
    }

    // Liked songs should open the actual liked playlist page.
    if (type == 'liked') {
      final ytAuthState = ref.read(ytMusicAuthStateProvider);
      if (ytAuthState.isLoggedIn) {
        PlaylistScreen.open(context, playlistId: 'LM', title: title);
        return;
      }
    }

    List<Track> tracks = [];

    switch (type) {
      case 'liked':
        final likedSongs = ref.read(likedSongsProvider);
        final ytLikedSongs =
            ref.read(ytMusicLikedSongsProvider).valueOrNull ?? [];
        tracks = [...likedSongs, ...ytLikedSongs];
        break;
      case 'most_played':
        final mostPlayedStats = ref.read(mostPlayedTracksProvider);
        tracks = mostPlayedStats
            .map(
              (s) => Track(
                id: s.trackId,
                title: s.title,
                artist: s.artist,
                duration: Duration.zero,
                thumbnailUrl: s.thumbnailUrl,
              ),
            )
            .toList();
        break;
      case 'recent':
        tracks = ref.read(recentlyPlayedProvider);
        break;
    }

    if (tracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.noSongsInTitle(title))),
      );
      return;
    }

    // Play all tracks
    _showAutoPlaylistSheet(title, tracks);
  }

  void _showAutoPlaylistSheet(String title, List<Track> tracks) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title and play buttons
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : InzxColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.pop(context);
                      final shuffled = List<Track>.from(tracks)..shuffle();
                      ref
                          .read(audioPlayerServiceProvider)
                          .playQueue(shuffled, startIndex: 0);
                      NowPlayingScreen.show(context);
                    },
                    icon: Icon(
                      Icons.shuffle_rounded,
                      color: colorScheme.primary,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.pop(context);
                      ref
                          .read(audioPlayerServiceProvider)
                          .playQueue(tracks, startIndex: 0);
                      NowPlayingScreen.show(context);
                    },
                    icon: Icon(
                      Icons.play_circle_filled_rounded,
                      color: colorScheme.primary,
                      size: 32,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              context.l10n.songsCount(tracks.length),
              style: TextStyle(
                color: isDark ? Colors.white54 : InzxColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            // Track list
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: tracks.length,
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  return ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: track.thumbnailUrl != null
                          ? CachedNetworkImage(
                              imageUrl: track.thumbnailUrl!,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              width: 48,
                              height: 48,
                              color: colorScheme.primaryContainer,
                              child: Icon(
                                Icons.music_note_rounded,
                                color: colorScheme.primary,
                              ),
                            ),
                    ),
                    title: Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark ? Colors.white : InzxColors.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.white54
                            : InzxColors.textSecondary,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      ref
                          .read(audioPlayerServiceProvider)
                          .playQueue(tracks, startIndex: index);
                      NowPlayingScreen.show(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyPlaylistsState(bool isDark, ColorScheme colorScheme) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white10
                    : colorScheme.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.queue_music_rounded,
                size: 36,
                color: isDark
                    ? Colors.white38
                    : colorScheme.primary.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.noPlaylistsYet,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : InzxColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.createPlaylistDescription,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white54 : InzxColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _showCreatePlaylistDialog,
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.createPlaylist),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumsView(bool isDark, ColorScheme colorScheme) {
    final l10n = context.l10n;
    final ytAuthState = ref.watch(ytMusicAuthStateProvider);
    final ytAlbumsAsync = ytAuthState.isLoggedIn
        ? ref.watch(ytMusicSavedAlbumsProvider)
        : const AsyncValue<List<Album>>.data([]);

    final recentlyPlayed = ref.watch(recentlyPlayedProvider);

    // Group locally played by album
    final albumsMap = <String, List<dynamic>>{};
    for (final track in recentlyPlayed) {
      final albumKey = track.album ?? l10n.unknownAlbum;
      albumsMap.putIfAbsent(albumKey, () => []).add(track);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        // YouTube Music albums
        if (ytAuthState.isLoggedIn) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Icon(Icons.music_note, size: 16, color: Colors.red),
                const SizedBox(width: 6),
                Text(
                  l10n.savedAlbumsFromYoutubeMusic,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white54 : InzxColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          ytAlbumsAsync.when(
            data: (albums) => albums.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      l10n.noSavedAlbumsFromYoutubeMusic,
                      style: TextStyle(
                        color: isDark
                            ? Colors.white38
                            : InzxColors.textSecondary,
                      ),
                    ),
                  )
                : GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.78,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: albums.length,
                    itemBuilder: (context, index) {
                      final album = albums[index];
                      return _buildAlbumCard(
                        album.title,
                        album.artist,
                        album.thumbnailUrl,
                        album.trackCount ?? 0,
                        isDark,
                        colorScheme,
                        isYTMusic: true,
                      );
                    },
                  ),
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  l10n.errorLoadingAlbums,
                  style: TextStyle(color: Colors.red.shade300),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Recently played albums
        if (albumsMap.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              l10n.recentlyPlayed,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white54 : InzxColors.textSecondary,
              ),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.78,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: albumsMap.length,
            itemBuilder: (context, index) {
              final albumName = albumsMap.keys.elementAt(index);
              final tracks = albumsMap[albumName]!;
              final firstTrack = tracks.first;

              return _buildAlbumCard(
                albumName,
                firstTrack.artist,
                firstTrack.thumbnailUrl,
                tracks.length,
                isDark,
                colorScheme,
              );
            },
          ),
        ],

        if (albumsMap.isEmpty && !ytAuthState.isLoggedIn)
          _buildEmptyAlbumsState(isDark, colorScheme),
      ],
    );
  }

  Widget _buildAlbumCard(
    String title,
    String artist,
    String? imageUrl,
    int trackCount,
    bool isDark,
    ColorScheme colorScheme, {
    bool isYTMusic = false,
  }) {
    final subtitle = context.metadataLine([
      artist,
      trackCount > 0 ? context.l10n.songsCount(trackCount) : null,
    ]);
    return InkWell(
      onTap: () {
        // TODO: Open album
      },
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          placeholder: (_, _) => _defaultAlbumArt(colorScheme),
                          errorWidget: (_, _, _) =>
                              _defaultAlbumArt(colorScheme),
                        )
                      : _defaultAlbumArt(colorScheme),
                  if (isYTMusic)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(
                          Icons.music_note,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : InzxColors.textPrimary,
            ),
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : InzxColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyAlbumsState(bool isDark, ColorScheme colorScheme) {
    final l10n = context.l10n;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white10
                  : colorScheme.primaryContainer.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.album_rounded,
              size: 36,
              color: isDark
                  ? Colors.white38
                  : colorScheme.primary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.noAlbumsYet,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : InzxColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.playSomeMusicToSeeAlbumsHere,
            style: TextStyle(
              color: isDark ? Colors.white54 : InzxColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArtistsView(bool isDark, ColorScheme colorScheme) {
    final l10n = context.l10n;
    final ytAuthState = ref.watch(ytMusicAuthStateProvider);
    final ytArtistsAsync = ytAuthState.isLoggedIn
        ? ref.watch(ytMusicSubscribedArtistsProvider)
        : const AsyncValue<List<Artist>>.data([]);

    final recentlyPlayed = ref.watch(recentlyPlayedProvider);

    // Group by artist from local plays
    final artistsMap = <String, int>{};
    for (final track in recentlyPlayed) {
      artistsMap[track.artist] = (artistsMap[track.artist] ?? 0) + 1;
    }

    final localArtists = artistsMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        // YouTube Music subscribed artists
        if (ytAuthState.isLoggedIn) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Icon(Icons.music_note, size: 16, color: Colors.red),
                const SizedBox(width: 6),
                Text(
                  l10n.subscribedArtists,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white54 : InzxColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          ytArtistsAsync.when(
            data: (artists) => artists.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      l10n.noSubscribedArtists,
                      style: TextStyle(
                        color: isDark
                            ? Colors.white38
                            : InzxColors.textSecondary,
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: artists.length,
                    itemBuilder: (context, index) {
                      final artist = artists[index];
                      return _buildArtistTile(
                        artist.name,
                        0, // We don't have song count
                        isDark,
                        colorScheme,
                        imageUrl: artist.thumbnailUrl,
                        isYTMusic: true,
                      );
                    },
                  ),
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  l10n.errorLoadingArtists,
                  style: TextStyle(color: Colors.red.shade300),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Local artists
        if (localArtists.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              l10n.recentlyPlayedArtists,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white54 : InzxColors.textSecondary,
              ),
            ),
          ),
          ...localArtists.map(
            (artist) =>
                _buildArtistTile(artist.key, artist.value, isDark, colorScheme),
          ),
        ],

        if (localArtists.isEmpty && !ytAuthState.isLoggedIn)
          _buildEmptyArtistsState(isDark, colorScheme),
      ],
    );
  }

  Widget _buildArtistTile(
    String name,
    int songCount,
    bool isDark,
    ColorScheme colorScheme, {
    String? imageUrl,
    bool isYTMusic = false,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 28,
        backgroundColor: colorScheme.primaryContainer,
        backgroundImage: imageUrl != null
            ? CachedNetworkImageProvider(imageUrl)
            : null,
        child: imageUrl == null
            ? Icon(Icons.person_rounded, color: colorScheme.primary)
            : null,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : InzxColors.textPrimary,
              ),
            ),
          ),
          if (isYTMusic)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.music_note, size: 12, color: Colors.red),
            ),
        ],
      ),
      subtitle: songCount > 0
          ? Text(
              context.l10n.songsCount(songCount),
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white54 : InzxColors.textSecondary,
              ),
            )
          : null,
      onTap: () {
        // TODO: Open artist page
      },
    );
  }

  Widget _buildEmptyArtistsState(bool isDark, ColorScheme colorScheme) {
    final l10n = context.l10n;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white10
                  : colorScheme.primaryContainer.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person_rounded,
              size: 36,
              color: isDark
                  ? Colors.white38
                  : colorScheme.primary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.noArtistsYet,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : InzxColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.playSomeMusicToSeeArtistsHere,
            style: TextStyle(
              color: isDark ? Colors.white54 : InzxColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _defaultAlbumArt(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.primaryContainer,
      child: Icon(Icons.album_rounded, color: colorScheme.primary, size: 48),
    );
  }

  Widget _buildDownloadsView(bool isDark, ColorScheme colorScheme) {
    final l10n = context.l10n;
    final downloadsAsync = ref.watch(downloadedTracksProvider);
    final downloadedPlaylists =
        ref.watch(downloadedPlaylistsProvider).valueOrNull ??
        const <DownloadedPlaylistSnapshot>[];
    final downloadManager = ref.watch(downloadManagerProvider);
    final downloadPathAsync = ref.watch(downloadPathProvider);

    return downloadsAsync.when(
      data: (tracks) {
        // Include active downloads
        final activeDownloads = downloadManager.activeTasks;
        final queuedDownloads = downloadManager.queuedTasks;

        if (tracks.isEmpty &&
            downloadedPlaylists.isEmpty &&
            activeDownloads.isEmpty &&
            queuedDownloads.isEmpty) {
          return _buildEmptyDownloadsState(isDark, colorScheme);
        }

        final downloadPath = downloadPathAsync.valueOrNull ?? l10n.loading;

        return ListView(
          padding: const EdgeInsets.only(bottom: 100),
          children: [
            // Download location info
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_rounded,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      downloadPath,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.white54
                            : InzxColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    l10n.songsCount(tracks.length),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),

            // Active downloads
            if (activeDownloads.isNotEmpty || queuedDownloads.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  l10n.downloading,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white54 : InzxColors.textSecondary,
                  ),
                ),
              ),
              ...activeDownloads.map(
                (task) => _buildDownloadingTile(task, isDark, colorScheme),
              ),
              ...queuedDownloads.map(
                (task) => _buildDownloadingTile(task, isDark, colorScheme),
              ),
              const SizedBox(height: 16),
            ],

            // Downloaded playlist snapshots (ordered offline playback)
            if (downloadedPlaylists.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  l10n.downloadedPlaylists,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white54 : InzxColors.textSecondary,
                  ),
                ),
              ),
              ...downloadedPlaylists.map(
                (snapshot) =>
                    _buildDownloadedPlaylistTile(snapshot, isDark, colorScheme),
              ),
              const SizedBox(height: 16),
            ],

            // Completed downloads
            if (tracks.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.downloaded,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Colors.white54
                            : InzxColors.textSecondary,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _playAllDownloads(tracks),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: Text(l10n.playAll),
                      style: TextButton.styleFrom(
                        foregroundColor: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              ...tracks.asMap().entries.map((entry) {
                final index = entry.key;
                final track = entry.value;
                return _buildDownloadedTrackTile(
                  track,
                  tracks,
                  index,
                  isDark,
                  colorScheme,
                );
              }),
            ],
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(
              l10n.errorLoadingDownloads,
              style: TextStyle(
                color: isDark ? Colors.white70 : InzxColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadedPlaylistTile(
    DownloadedPlaylistSnapshot snapshot,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    final artworkUrl =
        snapshot.thumbnailUrl ??
        (snapshot.downloadedOrderedTracks.isNotEmpty
            ? snapshot.downloadedOrderedTracks.first.thumbnailUrl
            : null);

    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: artworkUrl != null
            ? CachedNetworkImage(
                imageUrl: artworkUrl,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(
                  width: 48,
                  height: 48,
                  color: isDark ? Colors.white12 : Colors.grey.shade200,
                  child: const Icon(Icons.queue_music_rounded),
                ),
                errorWidget: (_, _, _) => Container(
                  width: 48,
                  height: 48,
                  color: isDark ? Colors.white12 : Colors.grey.shade200,
                  child: const Icon(Icons.queue_music_rounded),
                ),
              )
            : Container(
                width: 48,
                height: 48,
                color: isDark ? Colors.white12 : Colors.grey.shade200,
                child: const Icon(Icons.queue_music_rounded),
              ),
      ),
      title: Text(
        snapshot.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: isDark ? Colors.white : InzxColors.textPrimary),
      ),
      subtitle: Text(
        context.l10n.downloadedFraction(
          snapshot.downloadedTracks,
          snapshot.totalTracks,
        ),
        style: TextStyle(
          fontSize: 12,
          color: isDark ? Colors.white54 : InzxColors.textSecondary,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: isDark ? Colors.white54 : Colors.grey,
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlaylistScreen.offlineDownloaded(snapshot: snapshot),
        ),
      ),
    );
  }

  Widget _buildDownloadingTile(
    DownloadTask task,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: task.track.thumbnailUrl != null
            ? CachedNetworkImage(
                imageUrl: task.track.thumbnailUrl!,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(
                  width: 48,
                  height: 48,
                  color: isDark ? Colors.white12 : Colors.grey.shade200,
                  child: const Icon(Icons.music_note),
                ),
              )
            : Container(
                width: 48,
                height: 48,
                color: isDark ? Colors.white12 : Colors.grey.shade200,
                child: const Icon(Icons.music_note),
              ),
      ),
      title: Text(
        task.track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: isDark ? Colors.white : InzxColors.textPrimary),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            task.track.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : InzxColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: task.progress,
            backgroundColor: isDark ? Colors.white12 : Colors.grey.shade300,
            color: colorScheme.primary,
          ),
        ],
      ),
      trailing: task.status == DownloadStatus.downloading
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(task.progress * 100).toInt()}%',
                  style: TextStyle(fontSize: 12, color: colorScheme.primary),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: isDark ? Colors.white54 : Colors.grey,
                  ),
                  onPressed: () {
                    ref
                        .read(downloadManagerProvider.notifier)
                        .cancelDownload(task.trackId);
                  },
                ),
              ],
            )
          : IconButton(
              icon: Icon(
                Icons.close_rounded,
                size: 18,
                color: isDark ? Colors.white54 : Colors.grey,
              ),
              onPressed: () {
                ref
                    .read(downloadManagerProvider.notifier)
                    .cancelDownload(task.trackId);
              },
            ),
    );
  }

  Widget _buildDownloadedTrackTile(
    Track track,
    List<Track> allTracks,
    int index,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    final l10n = context.l10n;
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: track.thumbnailUrl != null
            ? CachedNetworkImage(
                imageUrl: track.thumbnailUrl!,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(
                  width: 48,
                  height: 48,
                  color: isDark ? Colors.white12 : Colors.grey.shade200,
                  child: const Icon(Icons.music_note),
                ),
              )
            : Container(
                width: 48,
                height: 48,
                color: isDark ? Colors.white12 : Colors.grey.shade200,
                child: const Icon(Icons.music_note),
              ),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: isDark ? Colors.white : InzxColors.textPrimary),
      ),
      subtitle: Text(
        track.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: isDark ? Colors.white54 : InzxColors.textSecondary,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.download_done_rounded,
            size: 16,
            color: Colors.green.shade400,
          ),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert,
              color: isDark ? Colors.white54 : Colors.grey,
            ),
            onSelected: (value) {
              if (value == 'delete') {
                _showDeleteConfirmation(track, isDark, colorScheme);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline,
                      color: Colors.red.shade400,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      l10n.deleteDownload,
                      style: TextStyle(color: Colors.red.shade400),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      onTap: () {
        // Play this track and queue the rest
        final playerService = ref.read(audioPlayerServiceProvider);
        playerService.playQueue(allTracks, startIndex: index);

        // Show now playing
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => const NowPlayingScreen(),
        );
      },
    );
  }

  void _showDeleteConfirmation(
    Track track,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        title: Text(
          l10n.deleteDownloadQuestion,
          style: TextStyle(
            color: isDark ? Colors.white : InzxColors.textPrimary,
          ),
        ),
        content: Text(
          l10n.deleteDownloadWarning(track.title),
          style: TextStyle(
            color: isDark ? Colors.white70 : InzxColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              l10n.cancel,
              style: TextStyle(color: isDark ? Colors.white54 : Colors.grey),
            ),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ref
                  .read(downloadManagerProvider.notifier)
                  .removeDownload(track.id);
              ScaffoldMessenger.of(this.context).showSnackBar(
                SnackBar(
                  content: Text(l10n.deletedTrack(track.title)),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(l10n.deleteDownload),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyDownloadsState(bool isDark, ColorScheme colorScheme) {
    final l10n = context.l10n;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.download_rounded,
            size: 64,
            color: isDark ? Colors.white24 : Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.noDownloadsYet,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : InzxColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.downloadedSongsWillAppearHere,
            style: TextStyle(
              color: isDark ? Colors.white38 : InzxColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  void _playAllDownloads(List<Track> tracks) {
    if (tracks.isEmpty) return;
    final playerService = ref.read(audioPlayerServiceProvider);
    playerService.playQueue(tracks, startIndex: 0);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const NowPlayingScreen(),
    );
  }

  void _showCreatePlaylistDialog() {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        title: Text(
          l10n.createPlaylist,
          style: TextStyle(
            color: isDark ? Colors.white : InzxColors.textPrimary,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(
            color: isDark ? Colors.white : InzxColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: l10n.playlistName,
            hintStyle: TextStyle(
              color: isDark ? Colors.white38 : InzxColors.textSecondary,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              // TODO: Create playlist
              Navigator.pop(context);
            },
            child: Text(l10n.create),
          ),
        ],
      ),
    );
  }
}
