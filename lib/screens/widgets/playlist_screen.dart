import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marquee/marquee.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/design_system/design_system.dart';
import '../../services/deep_link_handler.dart';
import '../../core/l10n/app_localizations_x.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../services/download_service.dart';
import 'track_options_sheet.dart';
import 'playlist_edit_screen.dart';
import 'mini_player.dart';
import 'now_playing_screen.dart';
import 'podcast_screen.dart' show PodcastScreen;

import 'package:palette_generator/palette_generator.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'explicit_badge.dart';

enum PlaylistTrackSort {
  defaultOrder,
  title,
  artist,
  duration,
}

/// Dynamic theme color provider from playlist image
final playlistColorsProvider = FutureProvider.autoDispose.family<Color?, String?>(
  (ref, imageUrl) async {
    if (imageUrl == null || imageUrl.isEmpty) return null;

    try {
      String optimizedUrl = imageUrl;
      if (imageUrl.contains('googleusercontent.com') ||
          imageUrl.contains('ytimg.com')) {
        optimizedUrl = imageUrl
            .replaceAll(RegExp(r'w\d+-h\d+'), 'w60-h60')
            .replaceAll(RegExp(r's\d+'), 's60');
      }

      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(optimizedUrl),
        maximumColorCount: 4,
        size: const Size(60, 60),
      );
      return paletteGenerator.dominantColor?.color ??
          paletteGenerator.vibrantColor?.color;
    } catch (e) {
      return null;
    }
  },
);

// NOTE: We use ytMusicPlaylistProvider from ytmusic_providers.dart
// which uses the shared innerTubeServiceProvider singleton.
// This ensures authentication cookies are preserved.

/// Playlist detail screen with track listing and in-playlist search
class PlaylistScreen extends ConsumerStatefulWidget {
  final String playlistId;
  final String? playlistTitle;
  final String? thumbnailUrl;
  final DownloadedPlaylistSnapshot? downloadedSnapshot;

  const PlaylistScreen({
    super.key,
    required this.playlistId,
    this.playlistTitle,
    this.thumbnailUrl,
    this.downloadedSnapshot,
  });

  PlaylistScreen.offlineDownloaded({
    super.key,
    required DownloadedPlaylistSnapshot snapshot,
  }) : playlistId = 'offline_playlist:${snapshot.sourcePlaylistId}',
       playlistTitle = snapshot.title,
       thumbnailUrl = snapshot.thumbnailUrl,
       downloadedSnapshot = snapshot;

  bool get isOfflineDownloaded => downloadedSnapshot != null;

  Playlist buildOfflinePlaylist(BuildContext context) {
    final snapshot = downloadedSnapshot!;
    return Playlist(
      id: snapshot.sourcePlaylistId,
      title: snapshot.title,
      thumbnailUrl: snapshot.thumbnailUrl,
      tracks: snapshot.downloadedOrderedTracks,
      description: context.l10n.offlineSnapshotDownloaded(
        snapshot.downloadedTracks,
        snapshot.totalTracks,
      ),
      author: context.l10n.downloaded,
      isLocal: true,
    );
  }

  static void open(
    BuildContext context, {
    required String playlistId,
    String? title,
    String? thumbnailUrl,
  }) {
    if (playlistId.startsWith('MPSP') ||
        playlistId.startsWith('RDPN') ||
        playlistId == 'SE' ||
        playlistId == 'FEmusic_library_podcasts_new_episodes' ||
        playlistId == 'FEmusic_library_podcasts_episodes_for_later') {
      PodcastScreen.open(
        context,
        podcastId: playlistId,
        title: title,
        thumbnailUrl: thumbnailUrl,
      );
      return;
    }

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
  PlaylistTrackSort _sortOption = PlaylistTrackSort.defaultOrder;
  bool _isCompactView = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Track> _getSortedTracks(List<Track> tracks) {
    if (_sortOption == PlaylistTrackSort.defaultOrder) {
      return tracks;
    }
    final sorted = List<Track>.from(tracks);
    switch (_sortOption) {
      case PlaylistTrackSort.title:
        sorted.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
        break;
      case PlaylistTrackSort.artist:
        sorted.sort(
          (a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()),
        );
        break;
      case PlaylistTrackSort.duration:
        sorted.sort((a, b) => a.duration.compareTo(b.duration));
        break;
      case PlaylistTrackSort.defaultOrder:
        break;
    }
    return sorted;
  }

  String _getSortLabel(PlaylistTrackSort sort, AppLocalizations l10n) {
    switch (sort) {
      case PlaylistTrackSort.defaultOrder:
        return 'Default';
      case PlaylistTrackSort.title:
        return l10n.name;
      case PlaylistTrackSort.artist:
        return l10n.artistLabel;
      case PlaylistTrackSort.duration:
        return l10n.duration;
    }
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

  Widget _buildControlBar(
    bool isDark,
    Color themeColor,
    AppLocalizations l10n,
    int trackCount,
  ) {
    final sortOptions = [
      (
        PlaylistTrackSort.defaultOrder,
        'Default',
        Icons.format_list_numbered_rounded,
      ),
      (
        PlaylistTrackSort.title,
        l10n.name,
        Icons.sort_by_alpha_rounded,
      ),
      (
        PlaylistTrackSort.artist,
        l10n.artistLabel,
        Icons.person_rounded,
      ),
      (
        PlaylistTrackSort.duration,
        l10n.duration,
        Icons.timer_outlined,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Sort button on the LEFT
          InkWell(
            onTap: () {
              _showSortBottomSheet<PlaylistTrackSort>(
                currentValue: _sortOption,
                options: sortOptions,
                onSelected: (newSort) => setState(() => _sortOption = newSort),
                isDark: isDark,
                accentColor: themeColor,
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
                    _getSortLabel(_sortOption, l10n),
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

          // View switcher on the RIGHT
          IconButton(
            onPressed: () {
              setState(() => _isCompactView = !_isCompactView);
            },
            icon: Icon(
              _isCompactView
                  ? Icons.view_headline_rounded
                  : Icons.view_list_rounded,
              size: 20,
              color: isDark ? Colors.white70 : InzxColors.textSecondary,
            ),
            tooltip: _isCompactView ? 'Detailed view' : 'Compact view',
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataPill(String text, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.16),
          width: 1.0,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
          color: isDark ? Colors.white.withValues(alpha: 0.85) : Colors.black87,
        ),
      ),
    );
  }

  /// A pill showing a user-owned playlist's privacy (Public / Unlisted /
  /// Private) with a matching icon.
  Widget _buildPrivacyPill(String privacy, bool isDark) {
    final p = privacy.toUpperCase();
    final (IconData icon, String label) = switch (p) {
      'PUBLIC' => (Icons.public_rounded, 'Public'),
      'UNLISTED' => (Icons.link_rounded, 'Unlisted'),
      _ => (Icons.lock_rounded, 'Private'),
    };
    final fg =
        isDark ? Colors.white.withValues(alpha: 0.85) : Colors.black87;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.16),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSheetActionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return BouncyTouch(
      style: BouncyStyle.card,
      customScale: 0.98,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(icon, color: iconColor, size: 18),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: textColor.withValues(alpha: 0.25),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground(
    BuildContext context,
    String? imageUrl,
    Color themeColor,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

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
              color: (isDark ? Colors.black : Colors.white).withValues(
                alpha: isDark ? 0.5 : 0.5,
              ),
              colorBlendMode: isDark ? BlendMode.darken : BlendMode.lighten,
            ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? [
                        themeColor.withValues(alpha: 0.3),
                        Colors.black.withValues(alpha: 0.7),
                        Colors.black,
                      ]
                    : [
                        themeColor.withValues(alpha: 0.14),
                        colorScheme.surface.withValues(alpha: 0.75),
                        colorScheme.surface,
                      ],
                stops: const [0.0, 0.4, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final playerService = ref.read(audioPlayerServiceProvider);

    if (widget.isOfflineDownloaded) {
      final playlist = widget.buildOfflinePlaylist(context);
      return Scaffold(
        backgroundColor: isDark ? Colors.black : colorScheme.surface,
        body: _buildContent(
          context,
          ref,
          playlist,
          isDark,
          colorScheme,
          playerService,
        ),
      );
    }

    final isLikedPlaylist = widget.playlistId == 'LM' ||
        widget.playlistId == 'VLLM' ||
        widget.playlistId == 'liked' ||
        widget.playlistId == 'favorites' ||
        widget.playlistId == 'local_liked' ||
        (widget.playlistTitle?.toLowerCase().contains('liked') == true);

    if (isLikedPlaylist) {
      final localLiked = ref.watch(likedSongsProvider);
      final ytAuthState = ref.watch(ytMusicAuthStateProvider);
      final ytLikedAsync = ytAuthState.isLoggedIn
          ? ref.watch(ytMusicPlaylistProvider('LM'))
          : const AsyncValue<Playlist?>.data(null);
      final ytLikedSongsAsync = ytAuthState.isLoggedIn
          ? ref.watch(ytMusicLikedSongsProvider)
          : const AsyncValue<List<Track>>.data([]);

      final remoteTracks = ytLikedAsync.valueOrNull?.tracks ??
          ytLikedSongsAsync.valueOrNull ??
          [];

      final seenIds = <String>{};
      final combinedTracks = <Track>[];

      // Local liked tracks first (most recently added locally)
      for (final t in localLiked) {
        if (seenIds.add(t.id)) combinedTracks.add(t);
      }
      // Remote liked tracks
      for (final t in remoteTracks) {
        if (seenIds.add(t.id)) combinedTracks.add(t);
      }

      if ((ytLikedAsync.isLoading || ytLikedSongsAsync.isLoading) &&
          combinedTracks.isEmpty) {
        return Scaffold(
          backgroundColor: isDark ? Colors.black : colorScheme.surface,
          body: _buildLoadingState(
            widget.playlistTitle ?? context.l10n.likedSongsLabel,
            null,
            isDark,
            colorScheme,
          ),
        );
      }

      final displayPlaylist = Playlist(
        id: widget.playlistId,
        title: widget.playlistTitle ??
            ytLikedAsync.valueOrNull?.title ??
            context.l10n.likedSongsLabel,
        tracks: combinedTracks,
        author: ytLikedAsync.valueOrNull?.author ??
            context.l10n.autoPlaylists,
        isYTMusic: true,
      );

      return Scaffold(
        backgroundColor: isDark ? Colors.black : colorScheme.surface,
        body: _buildContent(
          context,
          ref,
          displayPlaylist,
          isDark,
          colorScheme,
          playerService,
        ),
      );
    }

    // Use ytMusicPlaylistProvider which uses the shared InnerTubeService singleton
    final playlistAsync = ref.watch(ytMusicPlaylistProvider(widget.playlistId));

    return Scaffold(
      backgroundColor: isDark ? Colors.black : colorScheme.surface,
      body: playlistAsync.when(
        loading: () => _buildLoadingState(
          widget.playlistTitle,
          widget.thumbnailUrl,
          isDark,
          colorScheme,
        ),
        error: (e, stack) {
          return _buildErrorState(
            context.l10n.errorWithMessage(e.toString()),
            isDark,
          );
        },
        data: (playlist) {
          if (playlist == null) {
            return _buildErrorState(
              context.l10n.playlistNotFoundMessage(widget.playlistId),
              isDark,
            );
          }
          
          Playlist displayPlaylist = playlist;
          if (widget.playlistId.startsWith('RD')) {
             displayPlaylist = playlist.copyWith(
                title: widget.playlistTitle ?? playlist.title,
                thumbnailUrl: widget.thumbnailUrl ?? playlist.thumbnailUrl,
             );
          }
          
          return _buildContent(
            context,
            ref,
            displayPlaylist,
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
        title: title ?? context.l10n.loading,
        thumbnailUrl: thumbnail,
        tracks: [],
        description: context.l10n.loading,
        author: context.l10n.youtubeMusicLabel,
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
    final l10n = (context ?? this.context).l10n;
    final allTracks = playlist.tracks ?? [];

    // Extract year from extraSubtitle or createdAt
    String? year;
    if (playlist.extraSubtitle != null) {
      final match =
          RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(playlist.extraSubtitle!);
      if (match != null) {
        year = match.group(0);
      }
    }
    if (year == null && playlist.createdAt != null) {
      year = playlist.createdAt!.year.toString();
    }

    // Extract a view count (e.g. "1.2M views") from the subtitle if present.
    String? views;
    if (playlist.extraSubtitle != null) {
      final m = RegExp(
        r'([\d.,]+\s*[KMB]?)\s+views?',
        caseSensitive: false,
      ).firstMatch(playlist.extraSubtitle!);
      if (m != null) views = m.group(0)!.trim();
    }

    // Track count
    final trackCount =
        allTracks.isNotEmpty ? allTracks.length : (playlist.trackCount ?? 0);

    // Total duration formatting (e.g. 1 hr 30 min, 30 min, 12 hr 12 min)
    int totalDurationSeconds = 0;
    for (final t in allTracks) {
      totalDurationSeconds += t.duration.inSeconds;
    }
    String totalTimeFormatted = '';
    if (totalDurationSeconds > 0) {
      final hours = totalDurationSeconds ~/ 3600;
      final minutes = (totalDurationSeconds % 3600) ~/ 60;
      final seconds = totalDurationSeconds % 60;
      final parts = <String>[
        if (hours > 0) '$hours hr',
        if (minutes > 0) '$minutes min',
        if (seconds > 0) '$seconds sec',
      ];
      totalTimeFormatted = parts.join(' ');
    }

    // Filter tracks based on search query
    final searchedTracks = _searchQuery.isEmpty
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

    // Sort tracks
    List<Track> displayTracks = _getSortedTracks(searchedTracks);

    // Check if this is the Liked Music auto playlist
    final isLikedPlaylist = playlist.id == 'LM' ||
        playlist.id == 'VLLM' ||
        playlist.id == 'liked' ||
        playlist.id == 'favorites' ||
        playlist.id == 'local_liked' ||
        playlist.title.toLowerCase().contains('liked');

    // For Liked Music auto playlist (or playlists with missing cover),
    // use the cover of the most recently liked song (first track)
    String? bgThumbnailUrl = playlist.thumbnailUrl;
    if (isLikedPlaylist || bgThumbnailUrl == null || bgThumbnailUrl.isEmpty) {
      if (allTracks.isNotEmpty) {
        final recentTrack = allTracks.firstWhere(
          (t) => (t.highResThumbnailUrl ?? t.thumbnailUrl) != null,
          orElse: () => allTracks.first,
        );
        bgThumbnailUrl =
            recentTrack.highResThumbnailUrl ??
            recentTrack.thumbnailUrl ??
            bgThumbnailUrl;
      }
    }

    // Extract dynamic palette color from playlist cover or first track
    final colorSource = bgThumbnailUrl ?? playlist.thumbnailUrl;
    final playlistColor = ref != null && colorSource != null
        ? ref.watch(playlistColorsProvider(colorSource)).valueOrNull
        : null;
    final liveAccent = ref?.watch(effectiveAccentColorProvider);
    final themeColor = playlistColor ?? liveAccent ?? colorScheme.primary;
    // On a light background the dynamic accent can be too pale to read as the
    // active-song highlight, so darken it enough for solid contrast.
    final activeTrackColor = isDark
        ? themeColor
        : () {
            final hsl = HSLColor.fromColor(themeColor);
            return hsl
                .withLightness((hsl.lightness * 0.6).clamp(0.0, 0.42))
                .withSaturation((hsl.saturation).clamp(0.35, 1.0))
                .toColor();
          }();

    // Use high-res thumbnail if available (for Liked playlist, keep null so Like icon is shown on cover)
    final lowResThumb = bgThumbnailUrl;
    final highResThumb = isLikedPlaylist
        ? null
        : playlist.thumbnailUrl?.replaceAll(
            'w120-h120',
            'w600-h600',
          );

    // Watch playback state for UI updates
    final playbackState = ref?.watch(playbackStateProvider);
    final currentTrack = ref?.watch(currentTrackProvider);
    final queueSourceId = ref?.watch(queueSourceIdProvider);
    final isPlaying =
        playbackState?.whenOrNull(data: (s) => s.isPlaying) ?? false;

    // Check if this playlist is currently playing
    final isPlaylistPlaying = queueSourceId == playlist.id;

    // Determine play button icon
    final playIcon = (isPlaylistPlaying && isPlaying)
        ? Icons.pause_rounded
        : Icons.play_arrow_rounded;

    return Stack(
      children: [
        // Background - Smooth 3-stop fading gradient
        _buildBackground(this.context, lowResThumb, themeColor),

        Column(
          children: [
            Expanded(
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // App Bar with Back and Translucent Dynamic Search
                  SliverAppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    pinned: true,
                    flexibleSpace: _isSearching
                        ? ClipRect(
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: (isDark
                                          ? const Color(0xFF141414)
                                          : Colors.white)
                                      .withValues(alpha: 0.85),
                                  border: Border(
                                    bottom: BorderSide(
                                      color: themeColor.withValues(alpha: 0.22),
                                      width: 1.0,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          )
                        : null,
                    leading: IconButton(
                      icon: Icon(
                        Icons.arrow_back,
                        color: isDark ? Colors.white : colorScheme.onSurface,
                      ),
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
                            cursorColor: themeColor,
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white
                                  : colorScheme.onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: InputDecoration(
                              hintText: l10n.findInPlaylist,
                              hintStyle: TextStyle(
                                color: isDark
                                    ? Colors.white54
                                    : colorScheme.onSurface.withValues(
                                        alpha: 0.54,
                                      ),
                                fontSize: 16,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              contentPadding: EdgeInsets.zero,
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
                          icon: Icon(
                            Icons.search,
                            color: isDark
                                ? Colors.white
                                : colorScheme.onSurface,
                          ),
                          onPressed: () {
                            setState(() {
                              _isSearching = true;
                            });
                          },
                        )
                      else if (_searchQuery.isNotEmpty)
                        IconButton(
                          icon: Icon(
                            Icons.close_rounded,
                            color: isDark
                                ? Colors.white70
                                : colorScheme.onSurface,
                          ),
                          onPressed: () {
                            setState(() {
                              _searchQuery = '';
                              _searchController.clear();
                            });
                          },
                        ),
                    ],
                  ),

                  // Header Section
                  if (!_isSearching)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const SizedBox(height: 10),
                            // Centered Album Art
                            Center(
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                height: 240,
                                width: 240,
                                decoration: BoxDecoration(
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.4,
                                      ),
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
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? Colors.grey[900]
                                                : Colors.grey[200],
                                            gradient: isLikedPlaylist
                                                ? LinearGradient(
                                                    colors: [
                                                      Colors.red.shade400,
                                                      Colors.red.shade700,
                                                    ],
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                  )
                                                : null,
                                          ),
                                          child: Icon(
                                            isLikedPlaylist
                                                ? Icons.favorite_rounded
                                                : Icons.music_note,
                                            color: isLikedPlaylist
                                                ? Colors.white
                                                : (isDark
                                                    ? Colors.white
                                                    : colorScheme.onSurface),
                                            size: 80,
                                          ),
                                        ),
                                ),
                                  ),
                                  if (playlist.isEditable && !isLikedPlaylist)
                                    Positioned(
                                      right: 8,
                                      bottom: 8,
                                      child: _buildCoverEditButton(
                                        context,
                                        isDark,
                                        colorScheme,
                                        playlist,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Title
                            SizedBox(
                              width: double.infinity,
                              child: Text(
                                playlist.title,
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
                            ),
                            const SizedBox(height: 8),

                            // Subtitle / Author
                            if (playlist.author != null ||
                                playlist.authorAvatarUrl != null)
                              Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (playlist.authorAvatarUrl != null) ...[
                                      ClipOval(
                                        child: CachedNetworkImage(
                                          imageUrl: playlist.authorAvatarUrl!,
                                          width: 20,
                                          height: 20,
                                          fit: BoxFit.cover,
                                          placeholder: (_, _) => Container(
                                            color: Colors.grey[800],
                                          ),
                                          errorWidget: (_, _, _) => Container(
                                            color: Colors.grey[800],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    Text(
                                      playlist.author ?? l10n.youtubeMusicLabel,
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.white.withValues(alpha: 0.9)
                                            : colorScheme.onSurface,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            const SizedBox(height: 12),

                            // Glassy outlined metadata pills: Year, Tracks, Total Time
                            Center(
                              child: Builder(
                                builder: (context) {
                                  final showPrivacy = playlist.isEditable &&
                                      playlist.privacy != null;
                                  final hasYear =
                                      year != null && year.isNotEmpty;
                                  final row1 = <Widget>[
                                    if (showPrivacy)
                                      _buildPrivacyPill(
                                          playlist.privacy!, isDark),
                                    if (hasYear)
                                      _buildMetadataPill(year, isDark),
                                  ];
                                  final row2 = <Widget>[
                                    if (views != null && views.isNotEmpty)
                                      _buildMetadataPill(views, isDark),
                                    if (trackCount > 0)
                                      _buildMetadataPill(
                                        '$trackCount ${trackCount == 1 ? "track" : "tracks"}',
                                        isDark,
                                      ),
                                    if (totalTimeFormatted.isNotEmpty)
                                      _buildMetadataPill(
                                          totalTimeFormatted, isDark),
                                  ];
                                  return Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (row1.isNotEmpty)
                                        Wrap(
                                          alignment: WrapAlignment.center,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: row1,
                                        ),
                                      if (row1.isNotEmpty && row2.isNotEmpty)
                                        const SizedBox(height: 8),
                                      if (row2.isNotEmpty)
                                        Wrap(
                                          alignment: WrapAlignment.center,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: row2,
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Description
                            if (playlist.description != null &&
                                playlist.description!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                child: Text(
                                  playlist.description!,
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
                                _buildCircleButton(Icons.download_rounded, () {
                                  if (context == null) return;
                                  _downloadPlaylist(
                                    context,
                                    ref,
                                    playlist,
                                    allTracks,
                                  );
                                }),
                                _buildCircleButton(Icons.add_box_outlined, () {
                                  if (context == null) return;
                                  _addPlaylistToQueue(
                                    context,
                                    playerService,
                                    allTracks,
                                  );
                                }),

                                // Play Button (Toggle Play/Pause)
                                Container(
                                  height: 72,
                                  width: 72,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                  child: IconButton(
                                    icon: Icon(
                                      playIcon,
                                      color: isDark
                                          ? Colors.black
                                          : Colors.white,
                                    ),
                                    iconSize: 42,
                                    onPressed: () {
                                      if (isLoading ||
                                          playerService == null ||
                                          allTracks.isEmpty) {
                                        return;
                                      }

                                      if (isPlaylistPlaying && isPlaying) {
                                        playerService.pause();
                                      } else if (isPlaylistPlaying &&
                                          !isPlaying) {
                                        playerService.togglePlayPause();
                                      } else {
                                        playerService.playQueue(
                                          allTracks,
                                          startIndex: 0,
                                          sourceId: playlist.id,
                                          sourceTitle: playlist.title.isNotEmpty
                                              ? playlist.title
                                              : (playlist.id == 'LM'
                                                  ? l10n.likedSongsLabel
                                                  : 'Playlist'),
                                        );
                                      }
                                    },
                                  ),
                                ),

                                _buildCircleButton(Icons.share_outlined, () {
                                  if (context != null) {
                                    _sharePlaylist(context, playlist);
                                  }
                                }),
                                _buildCircleButton(Icons.more_vert_rounded, () {
                                  if (context == null) return;
                                  _showPlaylistOptions(
                                    context,
                                    ref,
                                    playlist,
                                    allTracks,
                                    playerService,
                                  );
                                }),
                              ],
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),

                  // Control Bar with Sort on Left and View Switcher on Right
                  if (!_isSearching && !isLoading && allTracks.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _buildControlBar(
                        isDark,
                        themeColor,
                        l10n,
                        displayTracks.length,
                      ),
                    ),

                  // Tracks List (Filtered or Full)
                  if (isLoading)
                    SliverSkeletonizer(
                      enabled: true,
                      child: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => ListTile(
                            leading: Skeleton.replace(
                              width: 48,
                              height: 48,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.grey,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                            title: Text(BoneMock.name),
                            subtitle: Text(BoneMock.words(2)),
                            trailing: const Icon(Icons.more_vert),
                          ),
                          childCount: 8,
                        ),
                      ),
                    )
                  else if (displayTracks.isEmpty)
                    SliverFillRemaining(
                      child: Center(
                        child: Text(
                          _isSearching
                              ? l10n.noMatchingTracks
                              : l10n.noTracksFound,
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
                      itemExtent: _isCompactView ? 58 : 72,
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final track = displayTracks[index];
                        final isTrackPlaying = currentTrack?.id == track.id;

                        // Subtitle with dot separator for duration (e.g. Artist • 03:12)
                        final subtitleText = track.formattedDuration.isNotEmpty
                            ? '${track.artist} • ${track.formattedDuration}'
                            : track.artist;

                        if (_isCompactView) {
                          // Compact Tracklist View (matching reference)
                          return ListTile(
                            contentPadding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
                            selected: isTrackPlaying,
                            selectedTileColor: (isDark
                                    ? Colors.white
                                    : Colors.black)
                                .withValues(alpha: 0.08),
                            leading: SizedBox(
                              width: 32,
                              child: Center(
                                child: isTrackPlaying
                                    ? Icon(
                                        isPlaying
                                            ? Icons.graphic_eq_rounded
                                            : Icons.play_arrow_rounded,
                                        color: themeColor,
                                        size: 20,
                                      )
                                    : Text(
                                        '${index + 1}',
                                        style: TextStyle(
                                          color: isDark
                                              ? Colors.white38
                                              : InzxColors.textSecondary,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                              ),
                            ),
                            title: Row(
                              children: [
                                if (track.isExplicit)
                                  ExplicitBadge(
                                    color: isTrackPlaying
                                        ? activeTrackColor
                                        : (isDark
                                            ? Colors.white
                                            : colorScheme.onSurface),
                                  ),
                                Expanded(
                                  child: _buildScrollableTitle(
                                    track.title,
                                    TextStyle(
                                      color: isTrackPlaying
                                          ? activeTrackColor
                                          : (isDark
                                              ? Colors.white
                                              : colorScheme.onSurface),
                                      fontSize: 15,
                                      fontWeight: isTrackPlaying
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                    ),
                                    isTrackPlaying,
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isTrackPlaying
                                    ? activeTrackColor.withValues(alpha: 0.7)
                                    : (isDark
                                        ? Colors.white60
                                        : colorScheme.onSurface.withValues(
                                            alpha: 0.6,
                                          )),
                                fontSize: 12.5,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (track.formattedDuration.isNotEmpty)
                                  Text(
                                    track.formattedDuration,
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white38
                                          : InzxColors.textSecondary,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                IconButton(
                                  icon: Icon(
                                    Icons.more_vert_rounded,
                                    color: isDark
                                        ? Colors.white54
                                        : colorScheme.onSurface.withValues(
                                            alpha: 0.54,
                                          ),
                                  ),
                                  onPressed: () => TrackOptionsSheet.show(
                                    context,
                                    track,
                                    sourcePlaylistId: playlist.id,
                                    isLocalPlaylist: !playlist.isYTMusic,
                                  ),
                                ),
                              ],
                            ),
                            onTap: () {
                              if (playerService != null) {
                                playerService.playQueue(
                                  displayTracks,
                                  startIndex: index,
                                  sourceId: playlist.id,
                                  sourceTitle: playlist.title.isNotEmpty
                                      ? playlist.title
                                      : (playlist.id == 'LM'
                                          ? l10n.likedSongsLabel
                                          : 'Playlist'),
                                );
                              }
                            },
                          );
                        }

                        // Detailed View with thumbnail
                        return ListTile(
                          contentPadding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                          selected: isTrackPlaying,
                          selectedTileColor:
                              (isDark ? Colors.white : Colors.black).withValues(
                            alpha: 0.1,
                          ),
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
                                      fadeInDuration: const Duration(
                                        milliseconds: 150,
                                      ),
                                      errorWidget: (_, _, _) => Container(
                                        color: isDark
                                            ? Colors.grey[800]
                                            : Colors.grey[300],
                                      ),
                                    )
                                  : Container(
                                      color: isDark
                                          ? Colors.grey[800]
                                          : Colors.grey[300],
                                    ),
                            ),
                          ),
                          title: Row(
                            children: [
                              if (track.isExplicit)
                                ExplicitBadge(
                                  color: isTrackPlaying
                                      ? activeTrackColor
                                      : (isDark
                                          ? Colors.white
                                          : colorScheme.onSurface),
                                ),
                              Expanded(
                                child: _buildScrollableTitle(
                                  track.title,
                                  TextStyle(
                                    color: isTrackPlaying
                                        ? activeTrackColor
                                        : (isDark
                                            ? Colors.white
                                            : colorScheme.onSurface),
                                    fontSize: 16,
                                    fontWeight: isTrackPlaying
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  ),
                                  isTrackPlaying,
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            subtitleText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isTrackPlaying
                                  ? activeTrackColor.withValues(alpha: 0.7)
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
                              Icons.more_vert_rounded,
                              color: isDark
                                  ? Colors.white54
                                  : colorScheme.onSurface.withValues(
                                      alpha: 0.54,
                                    ),
                            ),
                            onPressed: () => TrackOptionsSheet.show(
                              context,
                              track,
                              sourcePlaylistId: playlist.id,
                              isLocalPlaylist: !playlist.isYTMusic,
                            ),
                          ),
                          onTap: () {
                            if (playerService != null) {
                              playerService.playQueue(
                                displayTracks,
                                startIndex: index,
                                sourceId: playlist.id,
                                sourceTitle: playlist.title.isNotEmpty
                                    ? playlist.title
                                    : (playlist.id == 'LM'
                                        ? l10n.likedSongsLabel
                                        : 'Playlist'),
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

  /// Open the full-screen playlist editor (cover, title, description, privacy
  /// and inline reorder). The editor patches the cache itself, so no extra
  /// refresh is needed on return.
  void _openEditScreen(Playlist playlist) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlaylistEditScreen(playlist: playlist),
      ),
    );
  }

  /// Small pencil overlay on the playlist cover that opens the editor.
  /// Shown only for owned, editable playlists.
  Widget _buildCoverEditButton(
    BuildContext? ctx,
    bool isDark,
    ColorScheme colorScheme,
    Playlist playlist,
  ) {
    return Material(
      color: isDark ? const Color(0xFF202020) : Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _openEditScreen(playlist),
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(
            Icons.edit_rounded,
            size: 20,
            color: isDark ? Colors.white : colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildCircleButton(IconData icon, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 48,
      width: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
      ),
      child: IconButton(
        icon: Icon(icon, color: isDark ? Colors.white : colorScheme.onSurface),
        onPressed: onTap,
      ),
    );
  }

  void _sharePlaylist(BuildContext context, Playlist playlist) {
    final url = DeepLinkHandler.createShareUrl('playlist', playlist.id);
    SharePlus.instance.share(
      ShareParams(text: context.l10n.sharePlaylistText(playlist.title, url)),
    );
  }

  void _downloadPlaylist(
    BuildContext context,
    WidgetRef? ref,
    Playlist playlist,
    List<Track> tracks,
  ) {
    if (ref == null || tracks.isEmpty) return;

    final downloadManager = ref.read(downloadManagerProvider.notifier);
    downloadManager.addPlaylistToQueue(
      sourcePlaylistId: playlist.id,
      title: playlist.title,
      thumbnailUrl: playlist.thumbnailUrl,
      tracks: tracks,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.downloadingTracksFromPlaylist(
            tracks.length,
            playlist.title,
          ),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _addPlaylistToQueue(
    BuildContext context,
    dynamic playerService,
    List<Track> tracks,
  ) {
    if (playerService == null || tracks.isEmpty) return;

    for (final track in tracks) {
      playerService.addToQueue(track);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.addedTracksToQueueCount(tracks.length)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showPlaylistOptions(
    BuildContext context,
    WidgetRef? ref,
    Playlist playlist,
    List<Track> tracks,
    dynamic playerService,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = context.l10n;
    final isLikedPlaylist = playlist.id == 'LM' ||
        playlist.id == 'VLLM' ||
        playlist.id == 'liked' ||
        playlist.id == 'favorites' ||
        playlist.id == 'local_liked' ||
        playlist.title.toLowerCase().contains('liked');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Consumer(
          builder: (context, refConsumer, child) {
            final liveAccent = refConsumer.watch(effectiveAccentColorProvider);
            final sheetBg = isDark
                ? const Color(0xFF141414).withValues(alpha: 0.92)
                : Colors.white.withValues(alpha: 0.95);
            final textColor = isDark ? Colors.white : Colors.black87;
            final secondaryColor = textColor.withValues(alpha: 0.55);

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
                      child: SingleChildScrollView(
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
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: textColor.withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),

                              // Playlist Header Card
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: textColor.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: liveAccent.withValues(alpha: 0.15),
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: SizedBox(
                                        width: 50,
                                        height: 50,
                                        child: (playlist.thumbnailUrl !=
                                                    null &&
                                                !isLikedPlaylist)
                                            ? CachedNetworkImage(
                                                imageUrl:
                                                    playlist.thumbnailUrl!,
                                                fit: BoxFit.cover,
                                              )
                                            : Container(
                                                decoration: BoxDecoration(
                                                  color: isDark
                                                      ? Colors.grey[800]
                                                      : Colors.grey[300],
                                                  gradient: isLikedPlaylist
                                                      ? LinearGradient(
                                                          colors: [
                                                            Colors.red.shade400,
                                                            Colors.red.shade700,
                                                          ],
                                                          begin:
                                                              Alignment.topLeft,
                                                          end: Alignment
                                                              .bottomRight,
                                                        )
                                                      : null,
                                                ),
                                                child: Icon(
                                                  isLikedPlaylist
                                                      ? Icons.favorite_rounded
                                                      : Icons.music_note,
                                                  color: isLikedPlaylist
                                                      ? Colors.white
                                                      : (isDark
                                                          ? Colors.white70
                                                          : Colors.black87),
                                                  size: 24,
                                                ),
                                              ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            playlist.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: textColor,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            playlist.author ??
                                                l10n.youtubeMusicLabel,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              color: secondaryColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 14),

                              // Section: PLAYLIST ACTIONS
                              Padding(
                                padding:
                                    const EdgeInsets.only(left: 6, bottom: 4),
                                child: Text(
                                  'PLAYLIST ACTIONS',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.2,
                                    color: secondaryColor,
                                  ),
                                ),
                              ),
                              Container(
                                decoration: BoxDecoration(
                                  color: textColor.withValues(alpha: 0.04),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                  horizontal: 4,
                                ),
                                child: Column(
                                  children: [
                                    _buildSheetActionTile(
                                      icon: Icons.play_arrow_rounded,
                                      iconColor: liveAccent,
                                      title: l10n.play,
                                      textColor: textColor,
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        if (playerService != null &&
                                            tracks.isNotEmpty) {
                                          playerService.playQueue(
                                            tracks,
                                            startIndex: 0,
                                            sourceId: playlist.id,
                                            sourceTitle:
                                                playlist.title.isNotEmpty
                                                    ? playlist.title
                                                    : (playlist.id == 'LM'
                                                        ? l10n.likedSongsLabel
                                                        : 'Playlist'),
                                          );
                                        }
                                      },
                                    ),
                                    _buildSheetActionTile(
                                      icon: Icons.shuffle_rounded,
                                      iconColor: liveAccent,
                                      title: l10n.shuffle,
                                      textColor: textColor,
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        if (playerService != null &&
                                            tracks.isNotEmpty) {
                                          final shuffled =
                                              List<Track>.from(tracks)
                                                ..shuffle();
                                          playerService.playQueue(
                                            shuffled,
                                            startIndex: 0,
                                            sourceId: playlist.id,
                                            sourceTitle:
                                                playlist.title.isNotEmpty
                                                    ? playlist.title
                                                    : (playlist.id == 'LM'
                                                        ? l10n.likedSongsLabel
                                                        : 'Playlist'),
                                          );
                                        }
                                      },
                                    ),
                                    if (playlist.isEditable &&
                                        !isLikedPlaylist)
                                      _buildSheetActionTile(
                                        icon: Icons.edit_rounded,
                                        iconColor: liveAccent,
                                        title: 'Edit playlist',
                                        textColor: textColor,
                                        onTap: () {
                                          Navigator.pop(ctx);
                                          _openEditScreen(playlist);
                                        },
                                      ),
                                    _buildSheetActionTile(
                                      icon: Iconsax.add_square,
                                      iconColor: liveAccent,
                                      title: l10n.addToQueue,
                                      textColor: textColor,
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        _addPlaylistToQueue(
                                          context,
                                          playerService,
                                          tracks,
                                        );
                                      },
                                    ),
                                    _buildSheetActionTile(
                                      icon: Icons.download_rounded,
                                      iconColor: liveAccent,
                                      title: l10n.downloadPlaylist,
                                      textColor: textColor,
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        _downloadPlaylist(
                                          context,
                                          ref,
                                          playlist,
                                          tracks,
                                        );
                                      },
                                    ),
                                    _buildSheetActionTile(
                                      icon: Icons.share_rounded,
                                      iconColor: liveAccent,
                                      title: l10n.share,
                                      textColor: textColor,
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        _sharePlaylist(context, playlist);
                                      },
                                    ),
                                  ],
                                ),
                              ),

                              if (playlist.id != 'LM' &&
                                  playlist.id != 'VLLM') ...[
                                const SizedBox(height: 12),
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: _buildSheetActionTile(
                                    icon: Icons.delete_outline_rounded,
                                    iconColor: Colors.redAccent,
                                    title: l10n.deletePlaylist,
                                    textColor: Colors.redAccent,
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      final container =
                                          ProviderScope.containerOf(
                                            context,
                                            listen: false,
                                          );
                                      final scaffoldMessenger =
                                          ScaffoldMessenger.of(context);
                                      final localL10n = context.l10n;
                                      showDialog(
                                        context: context,
                                        builder:
                                            (dialogCtx) => AlertDialog(
                                              title: Text(
                                                localL10n.deletePlaylist,
                                              ),
                                              content: Text(
                                                localL10n.deletePlaylistConfirm,
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed:
                                                      () => Navigator.pop(
                                                        dialogCtx,
                                                      ),
                                                  child: Text(localL10n.cancel),
                                                ),
                                                TextButton(
                                                  onPressed: () async {
                                                    Navigator.pop(dialogCtx);
                                                    bool success = true;
                                                    if (playlist.isYTMusic) {
                                                      final ytAction = container
                                                          .read(
                                                            ytMusicPlaylistActionProvider,
                                                          );
                                                      success = await ytAction
                                                          .delete(playlist.id);
                                                      if (success) {
                                                        await container
                                                            .read(
                                                              ytMusicSavedPlaylistsProvider
                                                                  .notifier,
                                                            )
                                                            .removePlaylistOptimistically(
                                                              playlist.id,
                                                            );
                                                        container.invalidate(
                                                          ytMusicSavedPlaylistsProvider,
                                                        );
                                                      }
                                                    } else {
                                                      if (ref != null) {
                                                        ref
                                                            .read(
                                                              localPlaylistsProvider
                                                                  .notifier,
                                                            )
                                                            .deletePlaylist(
                                                              playlist.id,
                                                            );
                                                      }
                                                    }

                                                    if (!context.mounted) return;
                                                    if (success) {
                                                      // Close the playlist screen
                                                      // and confirm on the screen
                                                      // beneath it (library).
                                                      Navigator.pop(
                                                        context,
                                                      );
                                                      scaffoldMessenger
                                                          .showSnackBar(
                                                            SnackBar(
                                                              content: Text(
                                                                'Deleted "${playlist.title}"',
                                                              ),
                                                              duration:
                                                                  const Duration(
                                                                seconds: 2,
                                                              ),
                                                            ),
                                                          );
                                                    } else {
                                                      scaffoldMessenger
                                                          .showSnackBar(
                                                            SnackBar(
                                                              content: Text(
                                                                localL10n
                                                                    .unknownError,
                                                              ),
                                                            ),
                                                          );
                                                    }
                                                  },
                                                  child: Text(
                                                    localL10n.delete,
                                                    style: const TextStyle(
                                                      color: Colors.red,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                              const SizedBox(height: 6),
                            ],
                          ),
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

  Widget _buildScrollableTitle(String title, TextStyle style, bool isPlaying) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(text: title, style: style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);

        if (isPlaying && (textPainter.didExceedMaxLines || textPainter.width >= constraints.maxWidth - 2)) {
          return SizedBox(
            height: style.fontSize != null ? style.fontSize! * 1.5 : 20,
            child: Marquee(
              text: title,
              style: style,
              scrollAxis: Axis.horizontal,
              blankSpace: 40.0,
              velocity: 30.0,
              pauseAfterRound: const Duration(seconds: 2),
              startPadding: 0,
              accelerationDuration: const Duration(milliseconds: 500),
              accelerationCurve: Curves.linear,
              decelerationDuration: const Duration(milliseconds: 500),
              decelerationCurve: Curves.easeOut,
            ),
          );
        }

        return Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        );
      },
    );
  }
}
