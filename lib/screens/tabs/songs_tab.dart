import 'dart:ui';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/design_system/design_system.dart';
import '../../core/l10n/app_localizations_x.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../core/utils/platform_utils.dart';
import '../../providers/providers.dart';
import '../../models/models.dart';
import '../../services/local_music_scanner.dart';
import '../../services/download_service.dart';
import '../widgets/track_options_sheet.dart';
import '../widgets/now_playing_screen.dart';
import '../widgets/track_artwork_view.dart';

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
        final downloadedIds =
            (ref.read(downloadedTracksProvider).valueOrNull ?? [])
                .map((t) => t.id)
                .toSet();
        tracks = tracks.where((t) => downloadedIds.contains(t.id)).toList();
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

    // Get dynamic colors from effectiveAccentColorProvider
    final accentColor = ref.watch(effectiveAccentColorProvider);

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          // Header
          _buildHeader(isDark, colorScheme),

          // Filter chips
          _buildFilterChips(isDark, colorScheme, accentColor),
          const SizedBox(height: 6),

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
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.16)
                        : Colors.black.withValues(alpha: 0.12),
                    width: 1,
                  ),
                ),
                child: Center(
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    textAlignVertical: TextAlignVertical.center,
                    style: TextStyle(
                      color: isDark ? Colors.white : InzxColors.textPrimary,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: l10n.searchSongsHint,
                      hintStyle: TextStyle(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.62)
                            : Colors.black.withValues(alpha: 0.48),
                        fontSize: 14,
                      ),
                      filled: false,
                      fillColor: Colors.transparent,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.70)
                              : InzxColors.textSecondary,
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 20,
                        minHeight: 20,
                      ),
                    ),
                    onChanged: (val) {
                      setState(() => _searchQuery = val);
                    },
                  ),
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
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
      child: Row(
        children: filters.map((filter) {
          final isSelected = _selectedFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (_selectedFilter != filter) {
                  setState(() => _selectedFilter = filter);
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
                      : (isDark
                          ? const Color(0xFF262626)
                          : Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  _filterLabel(l10n, filter),
                  style: TextStyle(
                    color: isSelected
                        ? (isDark ? Colors.black : Colors.white)
                        : (isDark ? Colors.white70 : InzxColors.textPrimary),
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showSortBottomSheet<T>({
    required T currentValue,
    required List<(T value, String label, IconData icon)> options,
    required ValueChanged<T> onSelected,
    required bool isDark,
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
                    enabled: !isDesktop,
                    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: Container(
                      decoration: BoxDecoration(
                        color: modalSheetBackground(context, sheetBg),
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

                            // Options list
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

  Widget _buildSortRow(
    bool isDark,
    ColorScheme colorScheme,
    AppLocalizations l10n,
    int count,
    Color accentColor,
    List<SongSort> sortOptions,
  ) {
    final options = [
      (
        SongSort.recentlyAdded,
        l10n.recentlyAdded,
        Icons.more_time_rounded,
      ),
      (
        SongSort.name,
        l10n.name,
        Icons.sort_by_alpha_rounded,
      ),
      (
        SongSort.artist,
        l10n.artistLabel,
        Icons.person_rounded,
      ),
      (
        SongSort.duration,
        l10n.duration,
        Icons.timer_outlined,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Sort button on LEFT
          InkWell(
            onTap: () {
              _showSortBottomSheet<SongSort>(
                currentValue: _sortBy,
                options: options,
                onSelected: (newSort) => setState(() => _sortBy = newSort),
                isDark: isDark,
              );
            },
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
                    _sortLabel(l10n, _sortBy),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : InzxColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Songs count on RIGHT
          Text(
            l10n.songsCount(count),
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white54 : InzxColors.textSecondary,
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
          padding: const EdgeInsets.only(bottom: 160),
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
      contentPadding: const EdgeInsets.fromLTRB(16, 2, 4, 2),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 52,
          height: 52,
          child: Stack(
            children: [
              TrackArtworkView(
                track: track,
                width: 52,
                height: 52,
                borderRadius: BorderRadius.circular(8),
                fallback: _defaultArtwork(colorScheme, accentColor),
              ),
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
