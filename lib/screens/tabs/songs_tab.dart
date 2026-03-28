import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/design_system/design_system.dart';
import '../../core/l10n/app_localizations_x.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../providers/providers.dart';
import '../../models/models.dart';
import '../../services/local_music_scanner.dart';
import '../../services/download_service.dart';
import '../widgets/track_options_sheet.dart';
import '../widgets/now_playing_screen.dart';

enum SongFilter { all, liked, local, downloaded }

enum SongSort { recentlyAdded, name, artist, duration }

/// Provider that combines all songs from multiple sources
final allSongsProvider = Provider<List<Track>>((ref) {
  final recentlyPlayed = ref.watch(recentlyPlayedProvider);
  final likedSongs = ref.watch(likedSongsProvider);
  final localTracks = ref.watch(localTracksProvider);

  // Downloaded tracks from Hive
  final downloadedTracks =
      ref.watch(downloadedTracksProvider).valueOrNull ?? [];

  // YT Music liked songs if logged in
  final ytLikedSongs = ref.watch(ytMusicLikedSongsProvider).valueOrNull ?? [];

  // Combine all sources, removing duplicates by ID
  final allTracks = <String, Track>{};

  // Priority: downloaded > local > yt liked > local liked > recently played
  for (final track in recentlyPlayed) {
    allTracks[track.id] = track;
  }
  for (final track in likedSongs) {
    allTracks[track.id] = track;
  }
  for (final track in ytLikedSongs) {
    allTracks[track.id] = track;
  }
  for (final track in localTracks) {
    allTracks[track.id] = track;
  }
  // Downloaded tracks have highest priority (they have local files)
  for (final track in downloadedTracks) {
    allTracks[track.id] = track;
  }

  return allTracks.values.toList();
});

/// Songs tab with filter chips and song list
class MusicSongsTab extends ConsumerStatefulWidget {
  const MusicSongsTab({super.key});

  @override
  ConsumerState<MusicSongsTab> createState() => _MusicSongsTabState();
}

class _MusicSongsTabState extends ConsumerState<MusicSongsTab> {
  SongFilter _selectedFilter = SongFilter.all;
  SongSort _sortBy = SongSort.recentlyAdded;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Track> _getFilteredTracks(List<Track> allTracks) {
    var tracks = List<Track>.from(allTracks);

    // Apply filter
    switch (_selectedFilter) {
      case SongFilter.liked:
        final likedIds = ref.read(likedSongsProvider).map((t) => t.id).toSet();
        final ytLikedIds =
            (ref.read(ytMusicLikedSongsProvider).valueOrNull ?? [])
                .map((t) => t.id)
                .toSet();
        tracks = tracks
            .where((t) => likedIds.contains(t.id) || ytLikedIds.contains(t.id))
            .toList();
        break;
      case SongFilter.local:
        final localIds = ref.read(localTracksProvider).map((t) => t.id).toSet();
        tracks = tracks.where((t) => localIds.contains(t.id)).toList();
        break;
      case SongFilter.downloaded:
        // Only show tracks that have a local file path (downloaded)
        tracks = tracks.where((t) => t.localFilePath != null).toList();
        break;
      case SongFilter.all:
        break;
    }

    // Apply search
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      tracks = tracks
          .where(
            (t) =>
                t.title.toLowerCase().contains(query) ||
                t.artist.toLowerCase().contains(query) ||
                (t.album?.toLowerCase().contains(query) ?? false),
          )
          .toList();
    }

    // Apply sort
    switch (_sortBy) {
      case SongSort.name:
        tracks.sort((a, b) => a.title.compareTo(b.title));
        break;
      case SongSort.artist:
        tracks.sort((a, b) => a.artist.compareTo(b.artist));
        break;
      case SongSort.duration:
        tracks.sort(
          (a, b) =>
              a.duration.inMilliseconds.compareTo(b.duration.inMilliseconds),
        );
        break;
      case SongSort.recentlyAdded:
        // Keep original order (most recent first)
        break;
    }

    return tracks;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final allTracks = ref.watch(allSongsProvider);
    final filteredTracks = _getFilteredTracks(allTracks);
    final sortOptions = SongSort.values;

    // Get dynamic colors from album art
    final albumColors = ref.watch(albumColorsProvider);
    final hasAlbumColors = !albumColors.isDefault;
    final accentColor = hasAlbumColors
        ? albumColors.accent
        : colorScheme.primary;

    return SafeArea(
      child: Column(
        children: [
          // Header
          _buildHeader(isDark, colorScheme),

          // Filter chips
          _buildFilterChips(isDark, colorScheme, accentColor),

          // Sort row and count
          _buildSortRow(
            isDark,
            colorScheme,
            l10n,
            filteredTracks.length,
            accentColor,
            sortOptions,
          ),

          // Song list
          Expanded(
            child: filteredTracks.isEmpty
                ? _buildEmptyState(isDark, colorScheme, accentColor, l10n)
                : _buildSongList(
                    filteredTracks,
                    isDark,
                    colorScheme,
                    accentColor,
                  ),
          ),
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
          if (_isSearching)
            Expanded(
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: isDark ? Colors.white54 : InzxColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: l10n.searchSongsHint,
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          hintStyle: TextStyle(
                            color: isDark
                                ? Colors.white54
                                : InzxColors.textSecondary,
                          ),
                        ),
                        style: TextStyle(
                          color: isDark ? Colors.white : InzxColors.textPrimary,
                          fontSize: 15,
                        ),
                        onChanged: (value) =>
                            setState(() => _searchQuery = value),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Text(
              l10n.songs,
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
                  setState(() {
                    _isSearching = !_isSearching;
                    if (!_isSearching) {
                      _searchQuery = '';
                      _searchController.clear();
                    }
                  });
                },
                icon: Icon(
                  _isSearching ? Icons.close_rounded : Icons.search_rounded,
                  color: isDark ? Colors.white70 : InzxColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(
    bool isDark,
    ColorScheme colorScheme,
    Color accentColor,
  ) {
    final l10n = context.l10n;
    final filters = SongFilter.values;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: filters.map((filter) {
          final isSelected = _selectedFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(_filterLabel(l10n, filter)),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _selectedFilter = filter);
                }
              },
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
        }).toList(),
      ),
    );
  }

  Widget _buildSortRow(
    bool isDark,
    ColorScheme colorScheme,
    AppLocalizations l10n,
    int count,
    Color accentColor,
    List<SongSort> sortOptions,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                l10n.songsCount(count),
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white54 : InzxColors.textSecondary,
                ),
              ),
            ],
          ),
          PopupMenuButton<String>(
            onSelected: (value) =>
                setState(() => _sortBy = SongSort.values.byName(value)),
            offset: const Offset(0, 40),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            itemBuilder: (context) => sortOptions.map((option) {
              return PopupMenuItem(
                value: option.name,
                child: Row(
                  children: [
                    if (_sortBy == option)
                      Icon(Icons.check_rounded, size: 18, color: accentColor)
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: 8),
                    Text(_sortLabel(l10n, option)),
                  ],
                ),
              );
            }).toList(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.sort_rounded,
                  size: 18,
                  color: isDark ? Colors.white54 : InzxColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  _sortLabel(l10n, _sortBy),
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : InzxColors.textPrimary,
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 20,
                  color: isDark ? Colors.white54 : InzxColors.textSecondary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    bool isDark,
    ColorScheme colorScheme,
    Color accentColor,
    AppLocalizations l10n,
  ) {
    final emptyState = _emptyStateCopy(l10n);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white10
                  : accentColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _searchQuery.isNotEmpty
                  ? Icons.search_off_rounded
                  : Icons.music_note_rounded,
              size: 48,
              color: isDark
                  ? Colors.white38
                  : accentColor.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            emptyState.$1,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : InzxColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            emptyState.$2,
            style: TextStyle(
              color: isDark ? Colors.white54 : InzxColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSongList(
    List<Track> tracks,
    bool isDark,
    ColorScheme colorScheme,
    Color accentColor,
  ) {
    return Stack(
      children: [
        ListView.builder(
          padding: const EdgeInsets.only(bottom: 100),
          itemCount: tracks.length + 1, // +1 for play all header
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildPlayAllHeader(
                tracks,
                isDark,
                colorScheme,
                accentColor,
              );
            }
            return _buildSongTile(
              tracks[index - 1],
              index - 1,
              tracks,
              isDark,
              colorScheme,
              accentColor,
            );
          },
        ),
      ],
    );
  }

  Widget _buildPlayAllHeader(
    List<Track> tracks,
    bool isDark,
    ColorScheme colorScheme,
    Color accentColor,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          // Play all button
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _playAll(tracks),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(context.l10n.playAll),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: InzxColors.contrastTextOn(accentColor),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Shuffle button
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _shuffleAll(tracks),
              icon: const Icon(Icons.shuffle_rounded),
              label: Text(context.l10n.shuffle),
              style: OutlinedButton.styleFrom(
                foregroundColor: accentColor,
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: BorderSide(color: accentColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSongTile(
    Track track,
    int index,
    List<Track> allTracks,
    bool isDark,
    ColorScheme colorScheme,
    Color accentColor,
  ) {
    final playbackState = ref.watch(playbackStateProvider);
    final isCurrentTrack =
        playbackState.whenOrNull(data: (s) => s.currentTrack?.id == track.id) ??
        false;
    final isPlaying =
        playbackState.whenOrNull(data: (s) => s.isPlaying) ?? false;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 52,
          height: 52,
          child: Stack(
            children: [
              track.thumbnailUrl != null
                  ? CachedNetworkImage(
                      imageUrl: track.thumbnailUrl!,
                      fit: BoxFit.cover,
                      width: 52,
                      height: 52,
                      placeholder: (_, _) =>
                          _defaultArtwork(colorScheme, accentColor),
                      errorWidget: (_, _, _) =>
                          _defaultArtwork(colorScheme, accentColor),
                    )
                  : _defaultArtwork(colorScheme, accentColor),
              if (isCurrentTrack)
                Container(
                  color: Colors.black45,
                  child: Center(
                    child: Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isCurrentTrack ? FontWeight.w600 : FontWeight.w500,
          fontSize: 15,
          color: isCurrentTrack
              ? accentColor
              : (isDark ? Colors.white : InzxColors.textPrimary),
        ),
      ),
      subtitle: Text(
        context.trackSubtitle(track.artist, track.formattedDuration),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          color: isDark ? Colors.white54 : InzxColors.textSecondary,
        ),
      ),
      trailing: IconButton(
        onPressed: () => TrackOptionsSheet.show(context, track),
        icon: Icon(
          Icons.more_vert_rounded,
          color: isDark ? Colors.white54 : InzxColors.textSecondary,
        ),
      ),
      onTap: () async {
        final playerService = ref.read(audioPlayerServiceProvider);
        // Play from this position in the list
        await playerService.playQueue(allTracks, startIndex: index);
        if (mounted) NowPlayingScreen.show(context);
      },
    );
  }

  Widget _defaultArtwork(ColorScheme colorScheme, Color accentColor) {
    return Container(
      width: 52,
      height: 52,
      color: accentColor.withValues(alpha: 0.2),
      child: Icon(Icons.music_note_rounded, color: accentColor, size: 24),
    );
  }

  void _playAll(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    final playerService = ref.read(audioPlayerServiceProvider);
    await playerService.playQueue(tracks, startIndex: 0);
    if (mounted) NowPlayingScreen.show(context);
  }

  void _shuffleAll(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    final shuffled = List<Track>.from(tracks)..shuffle();
    final playerService = ref.read(audioPlayerServiceProvider);
    await playerService.playQueue(shuffled, startIndex: 0);
    if (mounted) NowPlayingScreen.show(context);
  }

  String _filterLabel(AppLocalizations l10n, SongFilter filter) {
    switch (filter) {
      case SongFilter.all:
        return l10n.all;
      case SongFilter.liked:
        return l10n.liked;
      case SongFilter.local:
        return l10n.local;
      case SongFilter.downloaded:
        return l10n.downloaded;
    }
  }

  String _sortLabel(AppLocalizations l10n, SongSort sort) {
    switch (sort) {
      case SongSort.recentlyAdded:
        return l10n.recentlyAdded;
      case SongSort.name:
        return l10n.name;
      case SongSort.artist:
        return l10n.artistLabel;
      case SongSort.duration:
        return l10n.duration;
    }
  }

  (String, String) _emptyStateCopy(AppLocalizations l10n) {
    switch (_selectedFilter) {
      case SongFilter.liked:
        return (l10n.noLikedSongs, l10n.likeSomeSongsToSeeThemHere);
      case SongFilter.local:
        return (l10n.noLocalSongs, l10n.scanFoldersToFindLocalMusic);
      case SongFilter.downloaded:
        return (l10n.noDownloadsYet, l10n.downloadSongsToListenOffline);
      case SongFilter.all:
        if (_searchQuery.isNotEmpty) {
          return (l10n.noResults, l10n.tryDifferentKeywords);
        }
        return (l10n.noSongsYet, l10n.playSomeMusicToBuildYourLibrary);
    }
  }
}
