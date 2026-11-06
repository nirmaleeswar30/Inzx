import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:skeletonizer/skeletonizer.dart';
import '../../../../core/design_system/design_system.dart';
import '../../core/l10n/app_localizations_x.dart';
import '../../providers/providers.dart';
import '../../providers/bookmarks_and_stats_provider.dart';
import '../../models/models.dart';
import '../../services/ytmusic_api_service.dart';
import '../../services/download_service.dart';
import '../widgets/playlist_screen.dart';
import '../widgets/podcast_screen.dart';
import '../widgets/now_playing_screen.dart';
import '../widgets/history_screen.dart';
import '../widgets/artist_page_screen.dart';
import '../widgets/album_screen.dart';
import '../widgets/track_options_sheet.dart';
import '../widgets/track_artwork_view.dart';
import '../search_screen.dart';

/// Library tab with albums, artists, and playlists
class MusicLibraryTab extends ConsumerStatefulWidget {
  const MusicLibraryTab({super.key});

  @override
  ConsumerState<MusicLibraryTab> createState() => _MusicLibraryTabState();
}

enum PlaylistSortOption {
  recents,
  recentlyAdded,
  title,
}

class _MusicLibraryTabState extends ConsumerState<MusicLibraryTab> {
  int _selectedCategory = 0;
  bool _isGridView = false;
  bool _isAlbumsGridView = false;
  bool _isArtistsGridView = false;
  PlaylistSortOption _sortOption = PlaylistSortOption.recents;
  PlaylistSortOption _albumSortOption = PlaylistSortOption.recents;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          // Header
          _buildHeader(isDark, colorScheme),

          // Category tabs
          _buildCategoryTabs(isDark, colorScheme),
          const SizedBox(height: 6),

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
    final downloadManager = ref.watch(downloadManagerProvider);
    final activeDownloads = downloadManager.activeTasks;
    final isDownloading = activeDownloads.isNotEmpty;
    final activeDownloadProgress =
        isDownloading ? activeDownloads.first.progress : 0.0;
    final activeDownloadPercent = (activeDownloadProgress * 100).toInt();

    final categories = [
      l10n.playlists,
      l10n.albums,
      l10n.artists,
      l10n.downloads,
      l10n.history,
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
      child: Row(
        children: List.generate(categories.length, (index) {
          final isSelected = _selectedCategory == index;
          final isDownloadsTab = index == 3;
          final showDownloadingPill = isDownloadsTab && isDownloading;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (_selectedCategory != index) {
                  setState(() => _selectedCategory = index);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? accentColor
                      : (showDownloadingPill
                          ? accentColor.withValues(alpha: isDark ? 0.22 : 0.14)
                          : (isDark
                              ? const Color(0xFF262626)
                              : Colors.grey.shade200)),
                  borderRadius: BorderRadius.circular(24),
                  border: showDownloadingPill && !isSelected
                      ? Border.all(
                          color: accentColor.withValues(alpha: 0.45),
                          width: 1,
                        )
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      categories[index],
                      style: TextStyle(
                        color: isSelected
                            ? (isDark ? Colors.black : Colors.white)
                            : (showDownloadingPill
                                ? accentColor
                                : (isDark
                                    ? Colors.white70
                                    : InzxColors.textPrimary)),
                        fontWeight:
                            isSelected || showDownloadingPill
                                ? FontWeight.w700
                                : FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                    if (showDownloadingPill) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (isDark ? Colors.black26 : Colors.white24)
                              : accentColor.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$activeDownloadPercent%',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? (isDark ? Colors.black : Colors.white)
                                : accentColor,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
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
      case 4:
        return const HistoryView();
      default:
        return const SizedBox.shrink();
    }
  }

  String _getSortOptionLabel(PlaylistSortOption option) {
    switch (option) {
      case PlaylistSortOption.recents:
        return 'Recents';
      case PlaylistSortOption.recentlyAdded:
        return 'Recently added';
      case PlaylistSortOption.title:
        return 'Alphabetical';
    }
  }

  List<Playlist> _sortPlaylists(
    List<Playlist> playlists,
    PlaylistSortOption option,
  ) {
    final list = List<Playlist>.from(playlists);
    switch (option) {
      case PlaylistSortOption.recents:
        return list;
      case PlaylistSortOption.recentlyAdded:
        return list.reversed.toList();
      case PlaylistSortOption.title:
        list.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
        return list;
    }
  }

  Widget _buildSortButton<T>({
    required T currentValue,
    required String currentLabel,
    required List<(T value, String label, IconData icon)> options,
    required ValueChanged<T> onSelected,
    required bool isDark,
    required Color accentColor,
  }) {
    return InkWell(
      onTap: () => _showSortBottomSheet<T>(
        currentValue: currentValue,
        options: options,
        onSelected: onSelected,
        isDark: isDark,
        accentColor: accentColor,
      ),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.swap_vert_rounded,
              size: 20,
              color: isDark ? Colors.white70 : InzxColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              currentLabel,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : InzxColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSortBottomSheet<T>({
    required T currentValue,
    required List<(T value, String label, IconData icon)> options,
    required ValueChanged<T> onSelected,
    required bool isDark,
    required Color accentColor,
  }) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final secondaryColor = textColor.withValues(alpha: 0.55);
    final sheetBg = isDark
        ? const Color(0xFF141414).withValues(alpha: 0.92)
        : Colors.white.withValues(alpha: 0.95);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Consumer(
          builder: (context, ref, child) {
            final liveAccent = ref.watch(effectiveAccentColorProvider);

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: Container(
                      decoration: BoxDecoration(
                        color: sheetBg,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: liveAccent.withValues(alpha: 0.22),
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 32,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Drag handle
                            Center(
                              child: Container(
                                width: 36,
                                height: 4,
                                margin: const EdgeInsets.only(bottom: 14),
                                decoration: BoxDecoration(
                                  color: textColor.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),

                            // Section Title
                            Padding(
                              padding: const EdgeInsets.only(left: 8, bottom: 8),
                              child: Text(
                                'SORT BY',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                  color: secondaryColor,
                                ),
                              ),
                            ),

                            // Options list (no container outline)
                            Column(
                              children: options.map((opt) {
                                final isSelected = opt.$1 == currentValue;

                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: InkWell(
                                    onTap: () {
                                      Navigator.pop(context);
                                      onSelected(opt.$1);
                                    },
                                    borderRadius: BorderRadius.circular(16),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        children: [
                                          // Dynamic icon container with background and outline
                                          Container(
                                            width: 42,
                                            height: 42,
                                            decoration: BoxDecoration(
                                              color: (isSelected
                                                      ? liveAccent
                                                      : (isDark
                                                          ? Colors.white
                                                          : Colors.black))
                                                  .withValues(
                                                    alpha: isDark ? 0.12 : 0.07,
                                                  ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: (isSelected
                                                        ? liveAccent
                                                        : (isDark
                                                            ? Colors.white
                                                            : Colors.black))
                                                    .withValues(
                                                      alpha: isDark
                                                          ? 0.18
                                                          : 0.10,
                                                    ),
                                                width: 0.8,
                                              ),
                                            ),
                                            child: Icon(
                                              opt.$3,
                                              size: 20,
                                              color: isSelected
                                                  ? liveAccent
                                                  : (isDark
                                                      ? Colors.white70
                                                      : Colors.black87),
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Text(
                                              opt.$2,
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: isSelected
                                                    ? FontWeight.w600
                                                    : FontWeight.w500,
                                                color: isSelected
                                                    ? liveAccent
                                                    : textColor,
                                              ),
                                            ),
                                          ),
                                          if (isSelected)
                                            Icon(
                                              Icons.check_rounded,
                                              size: 20,
                                              color: liveAccent,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 6),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPlaylistControlBar(bool isDark, Color accentColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildSortButton<PlaylistSortOption>(
            currentValue: _sortOption,
            currentLabel: _getSortOptionLabel(_sortOption),
            onSelected: (option) => setState(() => _sortOption = option),
            isDark: isDark,
            accentColor: accentColor,
            options: const [
              (
                PlaylistSortOption.recents,
                'Recents',
                Icons.history_rounded,
              ),
              (
                PlaylistSortOption.recentlyAdded,
                'Recently added',
                Icons.more_time_rounded,
              ),
              (
                PlaylistSortOption.title,
                'Alphabetical',
                Icons.sort_by_alpha_rounded,
              ),
            ],
          ),
          IconButton(
            onPressed: () {
              setState(() => _isGridView = !_isGridView);
            },
            icon: Icon(
              _isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
              size: 20,
              color: isDark ? Colors.white70 : InzxColors.textSecondary,
            ),
            tooltip: _isGridView ? 'List view' : 'Grid view',
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistsView(bool isDark, ColorScheme colorScheme) {
    final l10n = context.l10n;
    final accentColor = ref.watch(effectiveAccentColorProvider);
    final ytAuthState = ref.watch(ytMusicAuthStateProvider);
    final ytPlaylistsAsync = ytAuthState.isLoggedIn
        ? ref.watch(ytMusicSavedPlaylistsProvider)
        : const AsyncValue<List<Playlist>>.data([]);
    // Saved podcasts live in a separate library feed; merge them in.
    final ytPodcasts = ytAuthState.isLoggedIn
        ? (ref.watch(ytMusicSavedPodcastsProvider).valueOrNull ?? const [])
        : const <Playlist>[];
    // The saved-playlists feed also lists podcasts / auto-episode-lists in a
    // playlist style — drop those so they don't duplicate the podcast cards.
    final podcastKeys =
        ytPodcasts.map((p) => SavedPodcastsNotifier.normalize(p.id)).toSet();
    final podcastTitles =
        ytPodcasts.map((p) => p.title.trim().toLowerCase()).toSet();
    bool isPodcastDuplicate(Playlist p) =>
        p.isPodcast ||
        podcastKeys.contains(SavedPodcastsNotifier.normalize(p.id)) ||
        podcastTitles.contains(p.title.trim().toLowerCase());

    // Get counts for auto playlists
    final likedSongs = ref.watch(likedSongsProvider);
    final ytLikedSongs =
        ref.watch(ytMusicLikedSongsProvider).valueOrNull ?? [];
    final downloadedTracks =
        ref.watch(downloadedTracksProvider).valueOrNull ?? [];
    final totalLiked = () {
      final seen = <String>{};
      int count = 0;
      for (final t in likedSongs) {
        if (seen.add(t.id)) count++;
      }
      for (final t in ytLikedSongs) {
        if (seen.add(t.id)) count++;
      }
      return count;
    }();

    // Auto playlists with modern colored container gradients (Artists removed)
    final autoPlaylists = [
      (
        l10n.likedSongsLabel,
        Icons.favorite_rounded,
        const Color(0xFF6366F1),
        totalLiked,
        'liked',
      ),
      (
        l10n.downloaded,
        Icons.download_rounded,
        const Color(0xFF10B981),
        downloadedTracks.length,
        'downloaded',
      ),
      (
        l10n.history,
        Icons.history_rounded,
        const Color(0xFFF59E0B),
        -1,
        'recent',
      ),
    ];

    return ListView(
      padding: const EdgeInsets.only(bottom: 160),
      children: [
        // Control Bar (Sort + View Switcher)
        _buildPlaylistControlBar(isDark, accentColor),

        if (!_isGridView) ...[
          // List View: Unified auto playlists followed directly by cloud & local playlists
          ...autoPlaylists.map(
            (p) => _buildAutoPlaylistItem(
              p.$1,
              p.$2,
              p.$3,
              p.$4,
              p.$5,
              isDark,
              colorScheme,
            ),
          ),
          if (ytAuthState.isLoggedIn)
            ytPlaylistsAsync.when(
              data: (playlists) {
                // Filter out duplicate liked playlists
                final filtered = playlists.where((p) {
                  final title = p.title.trim().toLowerCase();
                  return p.id != 'LM' &&
                      p.id != 'VLLM' &&
                      title != 'liked songs' &&
                      title != 'liked music' &&
                      title != 'your likes' &&
                      !isPodcastDuplicate(p);
                }).toList();

                final sorted =
                    _sortPlaylists([...filtered, ...ytPodcasts], _sortOption);
                return _buildYTPlaylistsList(
                  sorted,
                  isDark,
                  colorScheme,
                  ytLikedSongs.length,
                );
              },
              loading: () => Skeletonizer(
                enabled: true,
                enableSwitchAnimation: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: List.generate(
                      4,
                      (index) => ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: Skeleton.replace(
                          width: 52,
                          height: 52,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.grey,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        title: Text(BoneMock.name),
                        subtitle: Text(BoneMock.words(2)),
                      ),
                    ),
                  ),
                ),
              ),
              error: (e, _) => const SizedBox.shrink(),
            ),
        ] else ...[
          // Grid View: 2-column grid layout
          ytPlaylistsAsync.when(
            data: (playlists) {
              // Filter out duplicate liked playlists
              final filtered = playlists.where((p) {
                final title = p.title.trim().toLowerCase();
                return p.id != 'LM' &&
                    p.id != 'VLLM' &&
                    title != 'liked songs' &&
                    title != 'liked music' &&
                    title != 'your likes' &&
                    !isPodcastDuplicate(p);
              }).toList();

              final sorted =
                  _sortPlaylists([...filtered, ...ytPodcasts], _sortOption);
              return _buildPlaylistsGrid(
                autoPlaylists,
                sorted,
                isDark,
                colorScheme,
                ytLikedSongs.length,
              );
            },
            loading: () => Skeletonizer(
              enabled: true,
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.78,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: 4,
                itemBuilder: (context, index) => Container(
                  decoration: BoxDecoration(
                    color: Colors.grey,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            error: (e, _) => const SizedBox.shrink(),
          ),
        ],
      ],
    );
  }

  Widget _buildAutoPlaylistItem(
    String title,
    IconData icon,
    Color color,
    int count,
    String type,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          gradient: type == 'liked'
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF6366F1),
                    Color(0xFF8B5CF6),
                    Color(0xFFA855F7),
                  ],
                )
              : null,
          color: type != 'liked'
              ? color.withValues(alpha: isDark ? 0.22 : 0.14)
              : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Icon(
            icon,
            size: 24,
            color: type == 'liked' ? Colors.white : color,
          ),
        ),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: isDark ? Colors.white : InzxColors.textPrimary,
        ),
      ),
      subtitle: Text(
        count >= 0
            ? context.l10n.songsCount(count)
            : context.l10n.autoPlaylists,
        style: TextStyle(
          fontSize: 12,
          color: isDark ? Colors.white54 : InzxColors.textSecondary,
        ),
      ),
      onTap: () => _openAutoPlaylist(type, title),
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
      padding: EdgeInsets.zero,
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        final displayCount = _resolveYtPlaylistSongCount(
          playlist,
          ytLikedSongsCount,
        );
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 2,
          ),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: playlist.thumbnailUrl != null
                ? CachedNetworkImage(
                    imageUrl: playlist.thumbnailUrl!,
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: 52,
                    height: 52,
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
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: isDark ? Colors.white : InzxColors.textPrimary,
            ),
          ),
          subtitle: Text(
            (playlist.isPodcast || playlist.id.startsWith('MPSP') || playlist.id.startsWith('FEmusic_library_podcasts'))
                ? (displayCount > 0 ? '$displayCount episodes' : 'Podcasts')
                : context.l10n.songsCount(displayCount),
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : InzxColors.textSecondary,
            ),
          ),
          onTap: () {
            if (playlist.isPodcast || playlist.id.startsWith('MPSP') || playlist.id.startsWith('FEmusic_library_podcasts')) {
              PodcastScreen.open(
                context,
                podcastId: playlist.id,
                title: playlist.title,
                thumbnailUrl: playlist.thumbnailUrl,
              );
            } else {
              // Open playlist screen
              PlaylistScreen.open(
                context,
                playlistId: playlist.id,
                title: playlist.title,
                thumbnailUrl: playlist.thumbnailUrl,
              );
            }
          },
        );
      },
    );
  }

  Widget _buildPlaylistsGrid(
    List<(String, IconData, Color, int, String)> autoPlaylists,
    List<Playlist> ytPlaylists,
    bool isDark,
    ColorScheme colorScheme,
    int ytLikedSongsCount,
  ) {
    final totalItems = autoPlaylists.length + ytPlaylists.length;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.78,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: totalItems,
      itemBuilder: (context, index) {
        if (index < autoPlaylists.length) {
          final auto = autoPlaylists[index];
          return _buildAutoPlaylistCard(
            auto.$1,
            auto.$2,
            auto.$3,
            auto.$4,
            auto.$5,
            isDark,
            colorScheme,
          );
        }
        final playlist = ytPlaylists[index - autoPlaylists.length];
        final displayCount = _resolveYtPlaylistSongCount(
          playlist,
          ytLikedSongsCount,
        );
        return _buildYTPlaylistCard(
          playlist,
          displayCount,
          isDark,
          colorScheme,
        );
      },
    );
  }

  Widget _buildYTPlaylistCard(
    Playlist playlist,
    int displayCount,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    return InkWell(
      onTap: () {
        if (playlist.isPodcast || playlist.id.startsWith('MPSP') || playlist.id.startsWith('FEmusic_library_podcasts')) {
          PodcastScreen.open(
            context,
            podcastId: playlist.id,
            title: playlist.title,
            thumbnailUrl: playlist.thumbnailUrl,
          );
        } else {
          PlaylistScreen.open(
            context,
            playlistId: playlist.id,
            title: playlist.title,
            thumbnailUrl: playlist.thumbnailUrl,
          );
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: playlist.thumbnailUrl != null
                  ? CachedNetworkImage(
                      imageUrl: playlist.thumbnailUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(
                        color: isDark ? Colors.white10 : Colors.grey.shade200,
                        child: Icon(
                          (playlist.isPodcast || playlist.id.startsWith('MPSP') || playlist.id.startsWith('FEmusic_library_podcasts'))
                              ? Icons.podcasts_rounded
                              : Icons.music_note,
                          color: isDark ? Colors.white24 : Colors.black26,
                        ),
                      ),
                      errorWidget: (_, _, _) => Container(
                        color: isDark ? Colors.white10 : Colors.grey.shade200,
                        child: Icon(
                          (playlist.isPodcast || playlist.id.startsWith('MPSP') || playlist.id.startsWith('FEmusic_library_podcasts'))
                              ? Icons.podcasts_rounded
                              : Icons.music_note,
                          color: isDark ? Colors.white24 : Colors.black26,
                        ),
                      ),
                    )
                  : Container(
                      color: isDark ? Colors.white10 : Colors.grey.shade200,
                      child: Icon(
                        (playlist.isPodcast || playlist.id.startsWith('MPSP') || playlist.id.startsWith('FEmusic_library_podcasts'))
                            ? Icons.podcasts_rounded
                            : Icons.music_note,
                        color: isDark ? Colors.white24 : Colors.black26,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            playlist.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: isDark ? Colors.white : InzxColors.textPrimary,
            ),
          ),
          Text(
            (playlist.isPodcast || playlist.id.startsWith('MPSP') || playlist.id.startsWith('FEmusic_library_podcasts'))
                ? (displayCount > 0 ? '$displayCount episodes' : 'Podcasts')
                : context.l10n.songsCount(displayCount),
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : InzxColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  int _resolveYtPlaylistSongCount(
    Playlist playlist,
    int ytLikedSongsCount,
  ) {
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
          AspectRatio(
            aspectRatio: 1.0,
            child: Container(
              decoration: BoxDecoration(
                gradient: type == 'liked'
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF6366F1),
                          Color(0xFF8B5CF6),
                          Color(0xFFA855F7),
                        ],
                      )
                    : null,
                color: type != 'liked'
                    ? color.withValues(alpha: isDark ? 0.25 : 0.15)
                    : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Icon(
                  icon,
                  size: 44,
                  color: type == 'liked' ? Colors.white : color,
                ),
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
              fontSize: 14,
              color: isDark ? Colors.white : InzxColors.textPrimary,
            ),
          ),
          if (count >= 0)
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

    // Special case: History screen
    if (type == 'recent') {
      setState(() => _selectedCategory = 4);
      return;
    }

    // Special case: Artists tab
    if (type == 'artists') {
      setState(() => _selectedCategory = 2);
      return;
    }

    // Liked songs should open the actual liked playlist page.
    if (type == 'liked') {
      PlaylistScreen.open(context, playlistId: 'LM', title: title);
      return;
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
                          .playQueue(shuffled, startIndex: 0, sourceTitle: title);
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
                          .playQueue(tracks, startIndex: 0, sourceTitle: title);
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
                          .playQueue(tracks, startIndex: index, sourceTitle: title);
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

  List<Album> _sortAlbums(List<Album> albums, PlaylistSortOption option) {
    final list = List<Album>.from(albums);
    switch (option) {
      case PlaylistSortOption.recents:
        return list;
      case PlaylistSortOption.recentlyAdded:
        return list.reversed.toList();
      case PlaylistSortOption.title:
        list.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
        return list;
    }
  }

  Widget _buildAlbumsView(bool isDark, ColorScheme colorScheme) {
    final l10n = context.l10n;
    final accentColor = ref.watch(effectiveAccentColorProvider);
    final ytAuthState = ref.watch(ytMusicAuthStateProvider);
    final ytAlbumsAsync = ytAuthState.isLoggedIn
        ? ref.watch(ytMusicSavedAlbumsProvider)
        : const AsyncValue<List<Album>>.data([]);

    return ListView(
      padding: const EdgeInsets.only(bottom: 160),
      children: [
        // Control Bar (Sort + Grid Switcher)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSortButton<PlaylistSortOption>(
                currentValue: _albumSortOption,
                currentLabel: _getSortOptionLabel(_albumSortOption),
                onSelected: (option) =>
                    setState(() => _albumSortOption = option),
                isDark: isDark,
                accentColor: accentColor,
                options: const [
                  (
                    PlaylistSortOption.recents,
                    'Recents',
                    Icons.history_rounded,
                  ),
                  (
                    PlaylistSortOption.recentlyAdded,
                    'Recently added',
                    Icons.more_time_rounded,
                  ),
                  (
                    PlaylistSortOption.title,
                    'Alphabetical',
                    Icons.sort_by_alpha_rounded,
                  ),
                ],
              ),
              IconButton(
                onPressed: () =>
                    setState(() => _isAlbumsGridView = !_isAlbumsGridView),
                icon: Icon(
                  _isAlbumsGridView
                      ? Icons.view_list_rounded
                      : Icons.grid_view_rounded,
                  size: 20,
                  color: isDark ? Colors.white70 : InzxColors.textSecondary,
                ),
                tooltip: _isAlbumsGridView ? 'List view' : 'Grid view',
              ),
            ],
          ),
        ),

        ytAlbumsAsync.when(
          data: (albums) {
            if (albums.isEmpty) {
              return _buildEmptyAlbumsState(isDark, colorScheme);
            }
            final sorted = _sortAlbums(albums, _albumSortOption);
            if (!_isAlbumsGridView) {
              return _buildAlbumsList(sorted, isDark, colorScheme);
            } else {
              return _buildAlbumsGrid(sorted, isDark, colorScheme);
            }
          },
          loading: () => Skeletonizer(
            enabled: true,
            child: _isAlbumsGridView
                ? GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.78,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: 4,
                    itemBuilder: (context, index) => Container(
                      decoration: BoxDecoration(
                        color: Colors.grey,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  )
                : Column(
                    children: List.generate(
                      4,
                      (index) => ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: Skeleton.replace(
                          width: 52,
                          height: 52,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.grey,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        title: Text(BoneMock.name),
                        subtitle: Text(BoneMock.words(2)),
                      ),
                    ),
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
      ],
    );
  }

  Widget _buildAlbumsList(
    List<Album> albums,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        final subtitle = context.metadataLine([
          album.artist,
          (album.trackCount ?? 0) > 0
              ? context.l10n.songsCount(album.trackCount!)
              : null,
        ]);
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 2,
          ),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: album.thumbnailUrl != null
                ? CachedNetworkImage(
                    imageUrl: album.thumbnailUrl!,
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: 52,
                    height: 52,
                    color: isDark ? Colors.white10 : Colors.grey.shade200,
                    child: const Icon(Icons.album_rounded),
                  ),
          ),
          title: Text(
            album.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: isDark ? Colors.white : InzxColors.textPrimary,
            ),
          ),
          subtitle: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : InzxColors.textSecondary,
            ),
          ),
          onTap: () {
            AlbumScreen.open(
              context,
              albumId: album.id,
              title: album.title,
              thumbnailUrl: album.thumbnailUrl,
            );
          },
        );
      },
    );
  }

  Widget _buildAlbumsGrid(
    List<Album> albums,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.78,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
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
          albumId: album.id,
        );
      },
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
    String? albumId,
  }) {
    final subtitle = context.metadataLine([
      artist,
      trackCount > 0 ? context.l10n.songsCount(trackCount) : null,
    ]);
    return InkWell(
      onTap: () {
        if (albumId != null && albumId.isNotEmpty) {
          AlbumScreen.open(
            context,
            albumId: albumId,
            title: title,
            thumbnailUrl: imageUrl,
          );
        }
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
              fontSize: 14,
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
    final accentColor = ref.watch(effectiveAccentColorProvider);
    final ytAuthState = ref.watch(ytMusicAuthStateProvider);
    final sort = ref.watch(ytMusicLibraryArtistSortProvider);

    final ytArtistsAsync = ytAuthState.isLoggedIn
        ? ref.watch(ytMusicLibrarySubscriptionsProvider)
        : const AsyncValue<List<Artist>>.data([]);

    return ListView(
      padding: const EdgeInsets.only(bottom: 160),
      children: [
        // Control Bar (Sort + Grid Switcher)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSortButton<LibraryArtistSort>(
                currentValue: sort,
                currentLabel: sort == LibraryArtistSort.recentlyAdded
                    ? l10n.recentlyAdded
                    : (sort == LibraryArtistSort.aToZ ? 'Alphabetical' : 'Z to A'),
                onSelected: (result) {
                  ref.read(ytMusicLibraryArtistSortProvider.notifier).state =
                      result;
                },
                isDark: isDark,
                accentColor: accentColor,
                options: const [
                  (
                    LibraryArtistSort.recentlyAdded,
                    'Recently added',
                    Icons.history_rounded,
                  ),
                  (
                    LibraryArtistSort.aToZ,
                    'Alphabetical',
                    Icons.sort_by_alpha_rounded,
                  ),
                  (
                    LibraryArtistSort.zToA,
                    'Z to A',
                    Icons.sort_by_alpha_rounded,
                  ),
                ],
              ),
              IconButton(
                onPressed: () =>
                    setState(() => _isArtistsGridView = !_isArtistsGridView),
                icon: Icon(
                  _isArtistsGridView
                      ? Icons.view_list_rounded
                      : Icons.grid_view_rounded,
                  size: 20,
                  color: isDark ? Colors.white70 : InzxColors.textSecondary,
                ),
                tooltip: _isArtistsGridView ? 'List view' : 'Grid view',
              ),
            ],
          ),
        ),

        ytArtistsAsync.when(
          data: (artists) {
            if (artists.isEmpty) {
              return _buildEmptyArtistsState(isDark, colorScheme);
            }
            if (!_isArtistsGridView) {
              return _buildArtistsList(artists, isDark, colorScheme);
            } else {
              return _buildArtistsGrid(artists, isDark, colorScheme);
            }
          },
          loading: () => Skeletonizer(
            enabled: true,
            child: _isArtistsGridView
                ? GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.85,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 16,
                        ),
                    itemCount: 4,
                    itemBuilder: (context, index) => Container(
                      decoration: const BoxDecoration(
                        color: Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                  )
                : Column(
                    children: List.generate(
                      4,
                      (index) => ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: Skeleton.replace(
                          width: 52,
                          height: 52,
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.grey,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        title: Text(BoneMock.name),
                        subtitle: Text(BoneMock.words(2)),
                      ),
                    ),
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
      ],
    );
  }

  Widget _buildArtistsList(
    List<Artist> artists,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final artist = artists[index];
        return _buildArtistTile(
          artist.name,
          artist.songsCount ?? 0,
          isDark,
          colorScheme,
          artistId: artist.id,
          imageUrl: artist.thumbnailUrl,
          isYTMusic: true,
        );
      },
    );
  }

  Widget _buildArtistsGrid(
    List<Artist> artists,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final artist = artists[index];
        return InkWell(
          onTap: () {
            ArtistPageScreen.open(
              context,
              artistId: artist.id,
              name: artist.name,
              thumbnailUrl: artist.thumbnailUrl,
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 46,
                backgroundColor:
                    isDark ? Colors.white10 : Colors.grey.shade200,
                backgroundImage: artist.thumbnailUrl != null
                    ? CachedNetworkImageProvider(artist.thumbnailUrl!)
                    : null,
                child: artist.thumbnailUrl == null
                    ? Icon(
                        Icons.person_rounded,
                        size: 40,
                        color:
                            isDark ? Colors.white54 : InzxColors.textSecondary,
                      )
                    : null,
              ),
              const SizedBox(height: 8),
              Text(
                artist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: isDark ? Colors.white : InzxColors.textPrimary,
                ),
              ),
              if ((artist.songsCount ?? 0) > 0)
                Text(
                  context.l10n.songsCount(artist.songsCount!),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : InzxColors.textSecondary,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildArtistTile(
    String name,
    int songCount,
    bool isDark,
    ColorScheme colorScheme, {
    String? artistId,
    String? imageUrl,
    bool isYTMusic = false,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 2,
      ),
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: colorScheme.primaryContainer,
        backgroundImage: imageUrl != null
            ? CachedNetworkImageProvider(imageUrl)
            : null,
        child: imageUrl == null
            ? Icon(Icons.person_rounded, color: colorScheme.primary, size: 26)
            : null,
      ),
      title: Text(
        name,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : InzxColors.textPrimary,
        ),
      ),
      subtitle: songCount > 0
          ? Text(
              context.l10n.songsCount(songCount),
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white54 : InzxColors.textSecondary,
              ),
            )
          : null,
      onTap: () {
        if (artistId != null && artistId.isNotEmpty) {
          ArtistPageScreen.open(
            context,
            artistId: artistId,
            name: name,
            thumbnailUrl: imageUrl,
          );
        }
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
    final accentColor = ref.watch(effectiveAccentColorProvider);
    final downloadsAsync = ref.watch(downloadedTracksProvider);
    final downloadedPlaylists =
        ref.watch(downloadedPlaylistsProvider).valueOrNull ??
        const <DownloadedPlaylistSnapshot>[];
    final downloadManager = ref.watch(downloadManagerProvider);

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

        return ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 160),
          children: [
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
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
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
                        foregroundColor: accentColor,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
      loading: () => Skeletonizer(
        enabled: true,
        enableSwitchAnimation: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: List.generate(5, (index) => ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              leading: Skeleton.replace(
                width: 48,
                height: 48,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              title: Text(BoneMock.name),
              subtitle: Text(BoneMock.words(2)),
              trailing: const Icon(Icons.more_vert),
            )),
          ),
        ),
      ),
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
    final accentColor = ref.watch(effectiveAccentColorProvider);
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 48,
          height: 48,
          child: TrackArtworkView(
            track: task.track,
            width: 48,
            height: 48,
            borderRadius: BorderRadius.circular(4),
            fallback: Container(
              width: 48,
              height: 48,
              color: isDark ? Colors.white12 : Colors.grey.shade200,
              child: const Icon(Icons.music_note),
            ),
          ),
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
            color: accentColor,
          ),
        ],
      ),
      trailing: task.status == DownloadStatus.downloading
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(task.progress * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: accentColor,
                  ),
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
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 2, 4, 2),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 48,
          height: 48,
          child: TrackArtworkView(
            track: track,
            width: 48,
            height: 48,
            borderRadius: BorderRadius.circular(4),
            fallback: Container(
              width: 48,
              height: 48,
              color: isDark ? Colors.white12 : Colors.grey.shade200,
              child: const Icon(Icons.music_note),
            ),
          ),
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
      trailing: IconButton(
        icon: Icon(
          Icons.more_vert_rounded,
          color: isDark ? Colors.white54 : InzxColors.textSecondary,
        ),
        onPressed: () => TrackOptionsSheet.show(context, track),
      ),
      onTap: () {
        // Play this track and queue the rest
        final playerService = ref.read(audioPlayerServiceProvider);
        playerService.playQueue(
          allTracks,
          startIndex: index,
          sourceTitle: context.l10n.downloads,
        );

        // Show now playing
        NowPlayingScreen.show(context);
      },
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
    playerService.playQueue(
      tracks,
      startIndex: 0,
      sourceTitle: context.l10n.downloads,
    );

    NowPlayingScreen.show(context);
  }

  void _showCreatePlaylistDialog() {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController();
    final isLoggedIn = ref.read(ytMusicAuthStateProvider).isLoggedIn;
    bool createInYtMusic = isLoggedIn;

    showDialog(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (context, ref, child) {
          final accentColor = ref.watch(effectiveAccentColorProvider);
          final hsl = HSLColor.fromColor(accentColor);
          final darkerAccent = hsl
              .withLightness((hsl.lightness * 0.75).clamp(0.15, 0.85))
              .toColor();

          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                backgroundColor:
                    isDark ? const Color(0xFF1E1E1E) : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: accentColor.withValues(alpha: 0.25),
                  ),
                ),
                title: Text(
                  l10n.createPlaylist,
                  style: TextStyle(
                    color: isDark ? Colors.white : InzxColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controller,
                      autofocus: false,
                      cursorColor: accentColor,
                      style: TextStyle(
                        color: isDark ? Colors.white : InzxColors.textPrimary,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: l10n.playlistName,
                        hintStyle: TextStyle(
                          color: isDark
                              ? Colors.white38
                              : InzxColors.textSecondary,
                          fontSize: 14,
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide:
                              BorderSide(color: accentColor, width: 2),
                        ),
                      ),
                    ),
                    if (isLoggedIn) ...[
                      const SizedBox(height: 14),
                      SwitchListTile(
                        title: Text(
                          'YouTube Music',
                          style: TextStyle(
                            color:
                                isDark ? Colors.white : InzxColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        activeThumbColor: accentColor,
                        activeTrackColor: darkerAccent.withValues(alpha: 0.5),
                        value: createInYtMusic,
                        onChanged: (val) =>
                            setState(() => createInYtMusic = val),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ],
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    style: TextButton.styleFrom(
                      foregroundColor: isDark
                          ? Colors.white60
                          : InzxColors.textSecondary,
                    ),
                    child: Text(
                      l10n.cancel,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: darkerAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 9,
                      ),
                    ),
                    onPressed: () async {
                      final name = controller.text.trim();
                      if (name.isNotEmpty) {
                        Navigator.pop(dialogContext); // Close dialog immediately

                        if (createInYtMusic) {
                          final scaffoldMessenger =
                              ScaffoldMessenger.of(this.context);
                          final ytAction =
                              ref.read(ytMusicPlaylistActionProvider);
                          final notifier = ref.read(
                            ytMusicSavedPlaylistsProvider.notifier,
                          );
                          final id = await ytAction.create(name);

                          if (id != null) {
                            await notifier.addPlaylistOptimistically(
                              id,
                              name,
                            );
                            ref.invalidate(
                              ytMusicSavedPlaylistsProvider,
                            );
                          } else {
                            scaffoldMessenger.showSnackBar(
                              SnackBar(
                                content: Text(l10n.unknownError),
                              ),
                            );
                          }
                        } else {
                          ref
                              .read(localPlaylistsProvider.notifier)
                              .createPlaylist(name);
                        }
                      }
                    },
                    child: Text(
                      l10n.create,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
