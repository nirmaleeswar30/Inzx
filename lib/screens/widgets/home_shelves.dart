import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:iconsax/iconsax.dart';
import '../../../../core/design_system/design_system.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../services/audio_player_service.dart' as player;
import 'now_playing_screen.dart';
import 'track_options_sheet.dart';
import 'shelf_details_screen.dart';

// ============================================================================
// HELPER: Determine which widget to use based on shelf title
// ============================================================================

enum ShelfLayout {
  quickPicksStyle, // Track list - Trending, Heard in Shorts, Covers, Long listens
  videoStyle, // Full width tall cards - Music videos, Live performances
  communityStyle, // Playlist header + songs - From the community
  dailyDiscoverStyle, // Large horizontal cards - Daily discover
  mixesStyle, // Mix cards
  chartsStyle, // Chart cards
  moodGenreStyle, // Chips
  contentCarousel, // Default carousel
}

ShelfLayout getShelfLayout(HomeShelf shelf) {
  final title = shelf.title.toLowerCase();

  // Music videos, Live performances -> Full width tall cards
  if (title.contains('music video') ||
      title.contains('live performance') ||
      title.contains('official video')) {
    return ShelfLayout.videoStyle;
  }

  // From the community -> Playlist with songs
  if (title.contains('from the community') ||
      title.contains('community playlist')) {
    return ShelfLayout.communityStyle;
  }

  // Daily discover -> Large cards
  if (title.contains('daily discover') || title.contains('your daily')) {
    return ShelfLayout.dailyDiscoverStyle;
  }

  // Trending, Heard in Shorts, Covers, Long listens -> Quick picks style
  if (title.contains('trending') ||
      title.contains('heard in shorts') ||
      title.contains('shorts') ||
      title.contains('cover') ||
      title.contains('remix') ||
      title.contains('long listen')) {
    return ShelfLayout.quickPicksStyle;
  }

  // Fallback to type-based layout
  switch (shelf.type) {
    case HomeShelfType.quickPicks:
      return ShelfLayout.quickPicksStyle;
    case HomeShelfType.mixedForYou:
    case HomeShelfType.discoverMix:
    case HomeShelfType.newReleaseMix:
      return ShelfLayout.mixesStyle;
    case HomeShelfType.charts:
    case HomeShelfType.trending:
      return ShelfLayout.chartsStyle;
    case HomeShelfType.moods:
    case HomeShelfType.genres:
      return ShelfLayout.moodGenreStyle;
    default:
      return ShelfLayout.contentCarousel;
  }
}

/// Widget for displaying Quick Picks shelf (radio-based song selection)
class QuickPicksShelf extends ConsumerWidget {
  final HomeShelf shelf;
  final bool isDark;
  final ColorScheme colorScheme;

  const QuickPicksShelf({
    super.key,
    required this.shelf,
    required this.isDark,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerService = ref.watch(audioPlayerServiceProvider);
    final tracks = shelf.tracks;

    if (tracks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (shelf.strapline != null)
                      Text(
                        shelf.strapline!,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.white54
                              : MineColors.textSecondary,
                        ),
                      ),
                    Text(
                      shelf.title,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : MineColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              // Play all button
              if (shelf.isPlayable)
                IconButton(
                  onPressed: () async {
                    if (tracks.isNotEmpty) {
                      await playerService.playTrack(tracks.first);
                      // Queue remaining tracks
                      if (tracks.length > 1) {
                        playerService.addToQueue(tracks.sublist(1));
                      }
                    }
                  },
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Track list (vertical list, 4 items visible at a time)
        SizedBox(
          height: 360, // Fixed height with smaller text to prevent overflow
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            cacheExtent: MediaQuery.of(
              context,
            ).size.width, // Preload 1 page ahead
            itemCount: (tracks.length / 4).ceil(),
            itemBuilder: (context, pageIndex) {
              final startIndex = pageIndex * 4;
              final pageTracks = tracks.skip(startIndex).take(4).toList();

              return Container(
                width: MediaQuery.of(context).size.width - 48,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  children: pageTracks.asMap().entries.map((entry) {
                    final isLast = entry.key == pageTracks.length - 1;
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: isLast ? 0 : 4),
                        child: OptimizedTrackItem(
                          track: entry.value,
                          playerService: playerService,
                          isDark: isDark,
                          colorScheme: colorScheme,
                          shelfTracks: tracks, // Pass all tracks for queue
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Optimized track item widget - only rebuilds when current track changes
/// Used by QuickPicksShelf, TrackListShelf, and home_tab song cards
class OptimizedTrackItem extends ConsumerWidget {
  final Track track;
  final player.AudioPlayerService playerService;
  final bool isDark;
  final ColorScheme colorScheme;
  final List<Track>? shelfTracks; // All tracks in the shelf for queue

  const OptimizedTrackItem({
    super.key,
    required this.track,
    required this.playerService,
    required this.isDark,
    required this.colorScheme,
    this.shelfTracks,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only watch the current track ID, not the entire playback state
    final currentTrackId = ref.watch(currentTrackIdProvider);
    final isCurrentTrack = currentTrackId == track.id;

    // Watch colors for this track (with auto-dispose for memory efficiency)
    final trackColors = ref.watch(trackColorsProvider(track.thumbnailUrl));

    // Capture notifier BEFORE async operation to avoid "ref after dispose" error
    final recentlyPlayedNotifier = ref.read(recentlyPlayedProvider.notifier);

    // Get accent color from track colors (defaults to theme primary)
    final accentColor = trackColors.whenOrNull(
      data: (colors) => colors.isDefault ? null : colors.accent,
    );

    return GestureDetector(
      onTap: () {
        // Open Now Playing screen with Hero animation
        NowPlayingScreen.show(context);

        // Start playback in background (don't await)
        if (shelfTracks != null && shelfTracks!.length > 1) {
          final idx = shelfTracks!.indexWhere((t) => t.id == track.id);
          if (idx >= 0) {
            playerService.playQueue(shelfTracks!, startIndex: idx);
          } else {
            playerService.playTrack(track);
          }
        } else {
          playerService.playTrack(track, enableRadio: true);
        }
        recentlyPlayedNotifier.addTrack(track);
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          // Subtle gradient based on album colors
          gradient: accentColor != null
              ? LinearGradient(
                  colors: [
                    accentColor.withValues(alpha: isDark ? 0.15 : 0.1),
                    accentColor.withValues(alpha: 0.0),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          children: [
            // Album art
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 56,
                height: 56,
                child: track.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: track.thumbnailUrl!,
                        fit: BoxFit.cover,
                        memCacheWidth: 112, // 2x for high DPI
                        placeholder: (_, __) => _defaultArtwork(),
                        errorWidget: (_, __, ___) => _defaultArtwork(),
                      )
                    : _defaultArtwork(),
              ),
            ),
            const SizedBox(width: 12),
            // Track info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    track.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isCurrentTrack
                          ? (accentColor ?? colorScheme.primary)
                          : (isDark ? Colors.white : MineColors.textPrimary),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white54 : MineColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            // More button
            IconButton(
              onPressed: () => TrackOptionsSheet.show(context, track),
              icon: Icon(
                Icons.more_vert,
                size: 18,
                color: isDark ? Colors.white38 : MineColors.textSecondary,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32),
            ),
          ],
        ),
      ),
    );
  }

  Widget _defaultArtwork() {
    return Container(
      color: isDark ? Colors.white12 : Colors.grey.shade200,
      child: Icon(
        Iconsax.music,
        color: isDark ? Colors.white38 : MineColors.textSecondary,
        size: 24,
      ),
    );
  }
}

/// Widget for displaying personalized mixes (Supermix, My Mix 1-7, etc.)
class MixesShelf extends ConsumerWidget {
  final HomeShelf shelf;
  final bool isDark;
  final ColorScheme colorScheme;
  final Function(HomeShelfItem item)? onMixTap;

  const MixesShelf({
    super.key,
    required this.shelf,
    required this.isDark,
    required this.colorScheme,
    this.onMixTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (shelf.items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (shelf.strapline != null)
                Text(
                  shelf.strapline!,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : MineColors.textSecondary,
                  ),
                ),
              Text(
                shelf.title,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : MineColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Horizontal carousel of mixes
        SizedBox(
          height: 210,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: shelf.items.length,
            itemBuilder: (context, index) {
              final item = shelf.items[index];
              return _buildMixCard(context, item, ref);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMixCard(
    BuildContext context,
    HomeShelfItem item,
    WidgetRef ref,
  ) {
    return GestureDetector(
      onTap: () {
        onMixTap?.call(item);
      },
      child: Container(
        width: 160,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 160,
                height: 160,
                child: item.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: item.thumbnailUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => _defaultMixArt(item),
                        errorWidget: (_, __, ___) => _defaultMixArt(item),
                      )
                    : _defaultMixArt(item),
              ),
            ),
            const SizedBox(height: 8),
            // Title
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : MineColors.textPrimary,
              ),
            ),
            if (item.subtitle != null)
              Text(
                item.subtitle!,
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

  Widget _defaultMixArt(HomeShelfItem item) {
    // Generate gradient based on title hash
    final hash = item.title.hashCode;
    final colors = [
      Colors.purple,
      Colors.blue,
      Colors.teal,
      Colors.green,
      Colors.orange,
      Colors.pink,
      Colors.indigo,
    ];
    final color1 = colors[hash.abs() % colors.length];
    final color2 = colors[(hash.abs() + 3) % colors.length];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color1, color2],
        ),
      ),
      child: Center(
        child: Icon(
          Iconsax.music_play,
          color: Colors.white.withValues(alpha: 0.8),
          size: 48,
        ),
      ),
    );
  }
}

/// Widget for displaying album/playlist carousel (New Releases, etc.)
class ContentCarouselShelf extends ConsumerWidget {
  final HomeShelf shelf;
  final bool isDark;
  final ColorScheme colorScheme;
  final void Function(HomeShelfItem item)? onItemTap;

  const ContentCarouselShelf({
    super.key,
    required this.shelf,
    required this.isDark,
    required this.colorScheme,
    this.onItemTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (shelf.items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (shelf.strapline != null)
                      Text(
                        shelf.strapline!,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.white54
                              : MineColors.textSecondary,
                        ),
                      ),
                    Text(
                      shelf.title,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : MineColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              if (shelf.browseId != null)
                TextButton(
                  onPressed: () {
                    ShelfDetailsScreen.open(context, shelf);
                  },
                  child: Text(
                    'More',
                    style: TextStyle(color: colorScheme.primary),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Horizontal carousel
        SizedBox(
          height: _getShelfHeight(),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: shelf.items.length,
            itemBuilder: (context, index) {
              final item = shelf.items[index];
              return _buildContentCard(context, item, ref);
            },
          ),
        ),
      ],
    );
  }

  double _getShelfHeight() {
    // Artists have circular thumbnails, others square
    final hasArtists = shelf.items.any(
      (i) => i.itemType == HomeShelfItemType.artist,
    );
    return hasArtists ? 195 : 220;
  }

  Widget _buildContentCard(
    BuildContext context,
    HomeShelfItem item,
    WidgetRef ref,
  ) {
    final isArtist = item.itemType == HomeShelfItemType.artist;
    final size = isArtist ? 140.0 : 150.0;

    return GestureDetector(
      onTap: () => onItemTap?.call(item),
      child: Container(
        width: size,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(isArtist ? size / 2 : 8),
              child: SizedBox(
                width: size,
                height: size,
                child: item.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: item.thumbnailUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => _defaultArt(item, isArtist),
                        errorWidget: (_, __, ___) =>
                            _defaultArt(item, isArtist),
                      )
                    : _defaultArt(item, isArtist),
              ),
            ),
            const SizedBox(height: 8),
            // Title
            Text(
              item.title,
              maxLines: isArtist ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              textAlign: isArtist ? TextAlign.center : TextAlign.start,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : MineColors.textPrimary,
              ),
            ),
            if (item.subtitle != null && !isArtist)
              Text(
                item.subtitle!,
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

  Widget _defaultArt(HomeShelfItem item, bool isArtist) {
    return Container(
      color: isDark ? Colors.white12 : Colors.grey.shade200,
      child: Icon(
        isArtist ? Iconsax.profile_2user : Iconsax.music_square,
        color: isDark ? Colors.white38 : MineColors.textSecondary,
        size: 40,
      ),
    );
  }
}

/// Widget for displaying mood/genre chips shelf
class MoodGenreShelf extends StatelessWidget {
  final HomeShelf shelf;
  final bool isDark;
  final ColorScheme colorScheme;
  final void Function(HomeShelfItem item)? onItemTap;

  const MoodGenreShelf({
    super.key,
    required this.shelf,
    required this.isDark,
    required this.colorScheme,
    this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    if (shelf.items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            shelf.title,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : MineColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Mood chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: shelf.items.map((item) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _buildMoodChip(item),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildMoodChip(HomeShelfItem item) {
    // Generate color from title hash
    final hash = item.title.hashCode;
    final colors = [
      Colors.purple.shade300,
      Colors.blue.shade300,
      Colors.teal.shade300,
      Colors.green.shade300,
      Colors.orange.shade300,
      Colors.pink.shade300,
      Colors.indigo.shade300,
    ];
    final chipColor = colors[hash.abs() % colors.length];

    return ActionChip(
      label: Text(item.title),
      onPressed: () => onItemTap?.call(item),
      backgroundColor: chipColor.withValues(alpha: isDark ? 0.3 : 0.2),
      labelStyle: TextStyle(
        color: isDark ? Colors.white : chipColor.withValues(alpha: 1),
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }
}

/// Widget for displaying charts shelf
class ChartsShelf extends ConsumerWidget {
  final HomeShelf shelf;
  final bool isDark;
  final ColorScheme colorScheme;
  final void Function(HomeShelfItem item)? onItemTap;

  const ChartsShelf({
    super.key,
    required this.shelf,
    required this.isDark,
    required this.colorScheme,
    this.onItemTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (shelf.items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                shelf.title,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : MineColors.textPrimary,
                ),
              ),
              if (shelf.browseId != null)
                TextButton(
                  onPressed: () {
                    // TODO: Navigate to chart details
                  },
                  child: Text(
                    'See all',
                    style: TextStyle(color: colorScheme.primary),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Chart cards
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: shelf.items.length,
            itemBuilder: (context, index) {
              final item = shelf.items[index];
              return _buildChartCard(context, item, index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildChartCard(BuildContext context, HomeShelfItem item, int index) {
    return GestureDetector(
      onTap: () => onItemTap?.call(item),
      child: Container(
        width: 150,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 150,
                height: 150,
                child: item.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: item.thumbnailUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => _defaultChartArt(),
                        errorWidget: (_, __, ___) => _defaultChartArt(),
                      )
                    : _defaultChartArt(),
              ),
            ),
            const SizedBox(height: 8),
            // Title
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : MineColors.textPrimary,
              ),
            ),
            if (item.subtitle != null)
              Text(
                item.subtitle!,
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

  Widget _defaultChartArt() {
    return Container(
      color: isDark ? Colors.white12 : Colors.grey.shade200,
      child: Icon(
        Iconsax.chart,
        color: isDark ? Colors.white38 : MineColors.textSecondary,
        size: 40,
      ),
    );
  }
}

// ============================================================================
// VIDEO SHELF - Full width, taller cards (Music Videos, Live Performances)
// ============================================================================

class VideoShelf extends ConsumerWidget {
  final HomeShelf shelf;
  final bool isDark;
  final ColorScheme colorScheme;
  final void Function(HomeShelfItem item)? onItemTap;

  const VideoShelf({
    super.key,
    required this.shelf,
    required this.isDark,
    required this.colorScheme,
    this.onItemTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (shelf.items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (shelf.strapline != null)
                      Text(
                        shelf.strapline!,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.white54
                              : MineColors.textSecondary,
                        ),
                      ),
                    Text(
                      shelf.title,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : MineColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              if (shelf.browseId != null)
                TextButton(
                  onPressed: () {
                    ShelfDetailsScreen.open(context, shelf);
                  },
                  child: Text(
                    'More',
                    style: TextStyle(color: colorScheme.primary),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Full width video cards - taller than normal
        SizedBox(
          height: 240, // Taller height for video cards
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: shelf.items.length,
            itemBuilder: (context, index) {
              final item = shelf.items[index];
              return _buildVideoCard(context, item, ref);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildVideoCard(
    BuildContext context,
    HomeShelfItem item,
    WidgetRef ref,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = screenWidth - 48; // Full width with padding

    return GestureDetector(
      onTap: () => onItemTap?.call(item),
      child: Container(
        width: cardWidth,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Video thumbnail with 16:9 aspect ratio
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  SizedBox(
                    width: cardWidth,
                    height: 180, // 16:9 ratio for video
                    child: item.thumbnailUrl != null
                        ? CachedNetworkImage(
                            imageUrl: item.thumbnailUrl!,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => _defaultVideoArt(),
                            errorWidget: (_, __, ___) => _defaultVideoArt(),
                          )
                        : _defaultVideoArt(),
                  ),
                  // Play icon overlay
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                  // Duration badge (if available)
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'VIDEO',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Title
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : MineColors.textPrimary,
              ),
            ),
            if (item.subtitle != null)
              Text(
                item.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white54 : MineColors.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _defaultVideoArt() {
    return Container(
      color: isDark ? Colors.white12 : Colors.grey.shade200,
      child: Icon(
        Iconsax.video_play,
        color: isDark ? Colors.white38 : MineColors.textSecondary,
        size: 48,
      ),
    );
  }
}

// ============================================================================
// COMMUNITY SHELF - Horizontal carousel (From the community)
// ============================================================================

class CommunityShelf extends ConsumerWidget {
  final HomeShelf shelf;
  final bool isDark;
  final ColorScheme colorScheme;
  final void Function(HomeShelfItem item)? onItemTap;

  const CommunityShelf({
    super.key,
    required this.shelf,
    required this.isDark,
    required this.colorScheme,
    this.onItemTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = shelf.items;

    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (shelf.strapline != null)
                      Text(
                        shelf.strapline!,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.white54
                              : MineColors.textSecondary,
                        ),
                      ),
                    Text(
                      shelf.title,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : MineColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              if (shelf.browseId != null)
                TextButton(
                  onPressed: () {
                    ShelfDetailsScreen.open(context, shelf);
                  },
                  child: Text(
                    'More',
                    style: TextStyle(color: colorScheme.primary),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Horizontal carousel of playlists/items
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return _buildCommunityCard(context, item, ref);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCommunityCard(
    BuildContext context,
    HomeShelfItem item,
    WidgetRef ref,
  ) {
    return GestureDetector(
      onTap: () => onItemTap?.call(item),
      child: Container(
        width: 150,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 150,
                height: 150,
                child: item.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: item.thumbnailUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => _defaultCommunityArt(),
                        errorWidget: (_, __, ___) => _defaultCommunityArt(),
                      )
                    : _defaultCommunityArt(),
              ),
            ),
            const SizedBox(height: 8),
            // Title
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : MineColors.textPrimary,
              ),
            ),
            if (item.subtitle != null)
              Text(
                item.subtitle!,
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

  Widget _defaultCommunityArt() {
    return Container(
      color: isDark ? Colors.white12 : Colors.grey.shade200,
      child: Icon(
        Iconsax.music_playlist,
        color: isDark ? Colors.white38 : MineColors.textSecondary,
        size: 40,
      ),
    );
  }
}

// ============================================================================
// DAILY DISCOVER SHELF - Large horizontal cards (Your daily discover)
// ============================================================================

class DailyDiscoverShelf extends ConsumerWidget {
  final HomeShelf shelf;
  final bool isDark;
  final ColorScheme colorScheme;
  final void Function(HomeShelfItem item)? onItemTap;

  const DailyDiscoverShelf({
    super.key,
    required this.shelf,
    required this.isDark,
    required this.colorScheme,
    this.onItemTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (shelf.items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (shelf.strapline != null)
                      Text(
                        shelf.strapline!,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.white54
                              : MineColors.textSecondary,
                        ),
                      ),
                    Text(
                      shelf.title,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : MineColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              // Play all button
              TextButton(
                onPressed: () {
                  final tracks = shelf.items
                      .map((i) => i.toTrack())
                      .whereType<Track>()
                      .toList();
                  if (tracks.isNotEmpty) {
                    ref
                        .read(audioPlayerServiceProvider)
                        .playTrack(tracks.first);
                    if (tracks.length > 1) {
                      ref
                          .read(audioPlayerServiceProvider)
                          .addToQueue(tracks.sublist(1));
                    }
                  }
                },
                child: Text(
                  'Play all',
                  style: TextStyle(color: colorScheme.primary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Large horizontal cards
        SizedBox(
          height: 300, // Large cards
          child: PageView.builder(
            controller: PageController(viewportFraction: 0.85),
            itemCount: shelf.items.length,
            itemBuilder: (context, index) {
              final item = shelf.items[index];
              return _buildDailyCard(context, item, ref, index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDailyCard(
    BuildContext context,
    HomeShelfItem item,
    WidgetRef ref,
    int index,
  ) {
    return GestureDetector(
      onTap: () => onItemTap?.call(item),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail - large card
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: double.infinity,
                height: 240,
                child: item.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: item.thumbnailUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => _defaultDailyArt(),
                        errorWidget: (_, __, ___) => _defaultDailyArt(),
                      )
                    : _defaultDailyArt(),
              ),
            ),
            const SizedBox(height: 10),
            // Title
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : MineColors.textPrimary,
              ),
            ),
            if (item.subtitle != null)
              Text(
                item.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white54 : MineColors.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _defaultDailyArt() {
    return Container(
      color: isDark ? Colors.white12 : Colors.grey.shade200,
      child: Icon(
        Iconsax.music_play,
        color: isDark ? Colors.white38 : MineColors.textSecondary,
        size: 48,
      ),
    );
  }
}

// ============================================================================
// QUICK PICKS STYLE SHELF - Track list (Trending, Heard in Shorts, Covers)
// ============================================================================

class TrackListShelf extends ConsumerWidget {
  final HomeShelf shelf;
  final bool isDark;
  final ColorScheme colorScheme;

  const TrackListShelf({
    super.key,
    required this.shelf,
    required this.isDark,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerService = ref.watch(audioPlayerServiceProvider);
    final tracks = shelf.tracks;
    final items = shelf.items;

    // Use tracks if available, otherwise convert items to tracks
    final displayTracks = tracks.isNotEmpty
        ? tracks
        : items.map((i) => i.toTrack()).whereType<Track>().toList();

    if (displayTracks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (shelf.strapline != null)
                      Text(
                        shelf.strapline!,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.white54
                              : MineColors.textSecondary,
                        ),
                      ),
                    Text(
                      shelf.title,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : MineColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              // Play all button
              if (displayTracks.isNotEmpty)
                IconButton(
                  onPressed: () async {
                    await playerService.playTrack(displayTracks.first);
                    if (displayTracks.length > 1) {
                      playerService.addToQueue(displayTracks.sublist(1));
                    }
                  },
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Track list (horizontal pages, 4 tracks per page) - using PageView for snapping
        SizedBox(
          height: 280,
          child: PageView.builder(
            controller: PageController(viewportFraction: 0.92),
            itemCount: (displayTracks.length / 4).ceil(),
            itemBuilder: (context, pageIndex) {
              final startIndex = pageIndex * 4;
              final pageTracks = displayTracks
                  .skip(startIndex)
                  .take(4)
                  .toList();

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  children: pageTracks.asMap().entries.map((entry) {
                    final isLast = entry.key == pageTracks.length - 1;
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: isLast ? 0 : 6),
                        // Use optimized track item widget
                        child: OptimizedTrackItem(
                          track: entry.value,
                          playerService: playerService,
                          isDark: isDark,
                          colorScheme: colorScheme,
                          shelfTracks:
                              displayTracks, // Pass all tracks for queue
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
