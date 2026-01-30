import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:iconsax/iconsax.dart';
import '../../../../core/design_system/design_system.dart';
import '../../providers/providers.dart';
import '../../models/models.dart';

import '../jams_screen.dart';
import '../ytmusic_login_screen.dart';
import '../ytmusic_settings_screen.dart';
import '../widgets/home_shelves.dart';
import '../widgets/playlist_screen.dart';
import '../widgets/album_screen.dart';
import '../widgets/artist_screen.dart';
import '../widgets/now_playing_screen.dart';
import '../search_screen.dart';

/// Home tab with search, quick actions, mood chips, and recommendations
class MusicHomeTab extends ConsumerStatefulWidget {
  const MusicHomeTab({super.key});

  @override
  ConsumerState<MusicHomeTab> createState() => _MusicHomeTabState();
}

class _MusicHomeTabState extends ConsumerState<MusicHomeTab> {
  bool _hasPrefetched =
      false; // Track if we've already prefetched for current home data

  /// OuterTune-style prefetching: resolve stream URLs when tracks become visible
  /// This makes play taps instant (pure cache lookup, no network call)
  void _prefetchShelfTracks(List<HomeShelf> shelves) {
    if (_hasPrefetched) return; // Only prefetch once per home load
    _hasPrefetched = true;

    // Collect all tracks from all shelves
    final allTracks = <Track>[];
    for (final shelf in shelves) {
      allTracks.addAll(shelf.tracks.take(10)); // First 10 per shelf
    }

    if (allTracks.isEmpty) return;

    // Prefetch using the provider
    final prefetchManager = ref.read(trackPrefetchProvider);
    prefetchManager.prefetchVisibleTracks(allTracks);

    if (kDebugMode) {
      print(
        'HomeTab: Triggered prefetch for ${allTracks.length} visible tracks',
      );
    }
  }

  /// Navigate to search results screen with a query
  void _performSearch(String query) {
    ref.read(searchQueryProvider.notifier).state = query;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const SearchScreen()));
  }

  /// Navigate to content based on item type (playlist, album, artist)
  void _navigateToContent(HomeShelfItem item) {
    final track = item.toTrack();
    if (track != null) {
      // It's a song - play it with radio mode enabled to build queue
      // enableRadio: true ensures YouTube radio builds a queue of related tracks
      ref.read(audioPlayerServiceProvider).playTrack(track, enableRadio: true);
      ref.read(recentlyPlayedProvider.notifier).addTrack(track);
      NowPlayingScreen.show(context);
      return;
    }

    // Check for playlist
    if (item.playlistId != null ||
        item.itemType == HomeShelfItemType.playlist ||
        item.itemType == HomeShelfItemType.mix) {
      final playlistId = item.playlistId ?? item.navigationId ?? item.id;
      PlaylistScreen.open(
        context,
        playlistId: playlistId,
        title: item.title,
        thumbnailUrl: item.thumbnailUrl,
      );
      return;
    }

    // Check for album
    if (item.itemType == HomeShelfItemType.album) {
      final albumId = item.navigationId ?? item.id;
      AlbumScreen.open(
        context,
        albumId: albumId,
        title: item.title,
        thumbnailUrl: item.thumbnailUrl,
      );
      return;
    }

    // Check for artist
    if (item.itemType == HomeShelfItemType.artist) {
      final artistId = item.navigationId ?? item.id;
      ArtistScreen.open(
        context,
        artistId: artistId,
        name: item.title,
        thumbnailUrl: item.thumbnailUrl,
      );
      return;
    }

    // Fallback to search for moods/genres/charts
    if (item.navigationId != null) {
      _performSearch(item.title);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Column(
        children: [
          // Search bar
          _buildSearchBar(isDark, colorScheme),

          // Content
          Expanded(child: _buildHomeContent(isDark, colorScheme)),
        ],
      ),
    );
  }

  /// Build profile avatar - shows Google pfp first, then YT Music, then initials
  Widget _buildProfileAvatar(
    bool isDark,
    ColorScheme colorScheme, {
    double size = 44,
  }) {
    final googleAuthState = ref.watch(googleAuthStateProvider);
    final ytAuthState = ref.watch(ytMusicAuthStateProvider);

    // Priority: Google Auth > YT Music Auth > Default
    String? avatarUrl;
    String initials = 'U';

    if (googleAuthState.isSignedIn && googleAuthState.user != null) {
      avatarUrl = googleAuthState.user!.photoUrl;
      initials = googleAuthState.user!.initials;
    } else if (ytAuthState.isLoggedIn && ytAuthState.account != null) {
      avatarUrl = ytAuthState.account!.avatarUrl;
      initials = (ytAuthState.account!.name?.isNotEmpty == true)
          ? ytAuthState.account!.name!.substring(0, 1).toUpperCase()
          : 'U';
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: avatarUrl == null
            ? LinearGradient(colors: [Colors.red.shade400, Colors.red.shade700])
            : null,
      ),
      child: ClipOval(
        child: avatarUrl != null
            ? CachedNetworkImage(
                imageUrl: avatarUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: Colors.red.shade400,
                  child: Center(
                    child: Text(
                      initials,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: size * 0.4,
                      ),
                    ),
                  ),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: Colors.red.shade400,
                  child: Center(
                    child: Text(
                      initials,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: size * 0.4,
                      ),
                    ),
                  ),
                ),
              )
            : Center(
                child: Text(
                  initials,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: size * 0.4,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildSearchBar(bool isDark, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                // Navigate to dedicated search screen
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const SearchScreen()),
                );
              },
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 22,
                      color: isDark ? Colors.white60 : MineColors.textSecondary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Search songs, albums, artists',
                        style: TextStyle(
                          color: isDark
                              ? Colors.white54
                              : MineColors.textSecondary,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Profile picture / YT Music settings
          GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const YTMusicSettingsScreen(),
                ),
              );
            },
            child: _buildProfileAvatar(isDark, colorScheme, size: 44),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeContent(bool isDark, ColorScheme colorScheme) {
    final ytAuthState = ref.watch(ytMusicAuthStateProvider);
    final homeState = ref.watch(ytMusicHomePageStateProvider);

    // Eagerly trigger liked songs fetch when logged in
    // This ensures liked status shows correctly when playing songs
    if (ytAuthState.isLoggedIn) {
      ref.watch(ytMusicLikedSongsProvider);
    }

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(ytMusicHomePageStateProvider.notifier).refresh();
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          // Load more when near bottom - handles both drag and momentum scrolling
          if (notification is ScrollUpdateNotification) {
            final metrics = notification.metrics;
            // Check if near bottom (within 500px) and have more content
            if (metrics.pixels >= metrics.maxScrollExtent - 500 &&
                metrics.maxScrollExtent > 0) {
              if (homeState.hasMore && !homeState.isLoadingMore) {
                ref.read(ytMusicHomePageStateProvider.notifier).loadMore();
              }
            }
          }
          return false;
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            // YT Music login prompt if not logged in
            if (!ytAuthState.isLoggedIn && !ytAuthState.isLoading)
              _buildYTMusicLoginCard(isDark, colorScheme),

            // Mood chips removed as per request
            const SizedBox(height: 8),

            // YT Music Home Page Shelves - use Builder to ensure proper rebuilds
            Builder(
              key: ValueKey(
                'shelves_${homeState.shelves.length}_${homeState.isLoading}',
              ),
              builder: (context) {
                if (homeState.isLoading && homeState.shelves.isEmpty) {
                  return _buildShelvesLoading(isDark);
                } else if (homeState.hasError && homeState.shelves.isEmpty) {
                  return _buildFallbackShelves(isDark, colorScheme);
                } else if (homeState.shelves.isEmpty) {
                  return _buildFallbackShelves(isDark, colorScheme);
                } else {
                  // OuterTune-style: Prefetch all visible tracks immediately
                  // This makes play taps instant (pure cache lookup)
                  _prefetchShelfTracks(homeState.shelves);
                  return _buildYTMusicShelvesFromState(
                    homeState,
                    isDark,
                    colorScheme,
                  );
                }
              },
            ),

            // Loading more indicator
            if (homeState.isLoadingMore)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: isDark ? Colors.white54 : Colors.grey,
                  ),
                ),
              ),

            // const SizedBox(height: 100), // Space for mini player - Removed as MusicApp handles this
          ],
        ),
      ),
    );
  }

  /// Build YT Music shelves from state (with continuation support)
  Widget _buildYTMusicShelvesFromState(
    HomePageState homeState,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    final shelves = homeState.shelves;

    if (shelves.isEmpty) {
      return _buildFallbackShelves(isDark, colorScheme);
    }

    final widgets = <Widget>[];

    // Find a suitable shelf for the "Welcome" section
    // Priority 1: "Quick Picks" (User request: Always fetch first)
    // Priority 2: "Music to get you started"
    // Priority 3: First shelf that contains songs

    HomeShelf? welcomeShelf;

    // Priority 1: Quick Picks
    try {
      welcomeShelf = shelves.firstWhere(
        (s) =>
            s.type == HomeShelfType.quickPicks ||
            s.title.toLowerCase().contains('quick picks'),
      );
    } catch (_) {
      // Not found
    }

    // Priority 2: "Music to get you started"
    if (welcomeShelf == null) {
      try {
        welcomeShelf = shelves.firstWhere(
          (s) =>
              (s.strapline?.toLowerCase() ?? '').contains(
                'music to get you started',
              ) ||
              (s.subtitle?.toLowerCase() ?? '').contains(
                'music to get you started',
              ) ||
              s.title.startsWith('Welcome'),
        );
      } catch (_) {
        // Not found
      }
    }

    // Priority 3: First shelf with songs
    if (welcomeShelf == null) {
      try {
        welcomeShelf = shelves.firstWhere(
          (s) =>
              s.items.any((i) => i.itemType == HomeShelfItemType.song) &&
              s.items.length >= 4,
        );
      } catch (_) {}
    }

    // Render Welcome Shelf first if found
    if (welcomeShelf != null) {
      widgets.add(_buildNativeWelcomeShelf(welcomeShelf, isDark, colorScheme));
      widgets.add(const SizedBox(height: 24));
    }

    // Render other shelves
    for (final shelf in shelves) {
      // Skip the one we used for welcome
      if (shelf == welcomeShelf) continue;

      // Skip empty shelves
      if (shelf.items.isEmpty) continue;

      // Skip Quick Picks if we used it as welcome (double check to be safe)
      if (shelf.type == HomeShelfType.quickPicks &&
          welcomeShelf?.type == HomeShelfType.quickPicks)
        continue;

      Widget? shelfWidget;

      // Use the layout helper to determine which widget to use
      final layout = getShelfLayout(shelf);

      switch (layout) {
        case ShelfLayout.quickPicksStyle:
          shelfWidget = TrackListShelf(
            shelf: shelf,
            isDark: isDark,
            colorScheme: colorScheme,
          );
          break;

        case ShelfLayout.videoStyle:
          shelfWidget = VideoShelf(
            shelf: shelf,
            isDark: isDark,
            colorScheme: colorScheme,
            onItemTap: (item) => _navigateToContent(item),
          );
          break;

        case ShelfLayout.communityStyle:
          shelfWidget = CommunityShelf(
            shelf: shelf,
            isDark: isDark,
            colorScheme: colorScheme,
            onItemTap: (item) => _navigateToContent(item),
          );
          break;

        case ShelfLayout.dailyDiscoverStyle:
          shelfWidget = DailyDiscoverShelf(
            shelf: shelf,
            isDark: isDark,
            colorScheme: colorScheme,
            onItemTap: (item) => _navigateToContent(item),
          );
          break;

        case ShelfLayout.mixesStyle:
          shelfWidget = MixesShelf(
            shelf: shelf,
            isDark: isDark,
            colorScheme: colorScheme,
            onMixTap: (item) => _navigateToContent(item),
          );
          break;

        case ShelfLayout.chartsStyle:
          shelfWidget = ChartsShelf(
            shelf: shelf,
            isDark: isDark,
            colorScheme: colorScheme,
            onItemTap: (item) => _navigateToContent(item),
          );
          break;

        case ShelfLayout.moodGenreStyle:
          shelfWidget = MoodGenreShelf(
            shelf: shelf,
            isDark: isDark,
            colorScheme: colorScheme,
            onItemTap: (item) => _performSearch(item.title),
          );
          break;

        case ShelfLayout.contentCarousel:
          shelfWidget = ContentCarouselShelf(
            shelf: shelf,
            isDark: isDark,
            colorScheme: colorScheme,
            onItemTap: (item) => _navigateToContent(item),
          );
          break;
      }

      widgets.add(shelfWidget);

      // Add spacing only if not the last item
      if (shelf != shelves.last) {
        widgets.add(const SizedBox(height: 24));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  /// Fallback shelves when YT Music data is not available
  Widget _buildFallbackShelves(bool isDark, ColorScheme colorScheme) {
    return Column(
      children: [
        // Forgotten favorites (horizontal albums)
        _buildForgottenFavorites(isDark, colorScheme),

        const SizedBox(height: 24),

        // Mixed for you section (placeholder)
        _buildMixedForYou(isDark, colorScheme),
      ],
    );
  }

  /// Loading state for shelves
  Widget _buildShelvesLoading(bool isDark) {
    return Column(
      children: [
        // Skeleton for quick picks
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            height: 20,
            width: 150,
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 280,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 3,
            itemBuilder: (context, index) {
              return Container(
                width: MediaQuery.of(context).size.width - 48,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),
        // Also show fallback shelves while loading
        _buildForgottenFavorites(isDark, Theme.of(context).colorScheme),
        const SizedBox(height: 24),
        _buildMixedForYou(isDark, Theme.of(context).colorScheme),
      ],
    );
  }

  Widget _buildYTMusicLoginCard(bool isDark, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.red.shade800, Colors.red.shade900],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            final result = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (context) => const YTMusicLoginScreen(),
              ),
            );
            if (result == true) {
              // Refresh data after login
              ref.invalidate(ytMusicLikedSongsProvider);
              ref.invalidate(ytMusicRecentlyPlayedProvider);
              ref.invalidate(ytMusicSavedPlaylistsProvider);
              ref.invalidate(ytMusicSavedAlbumsProvider);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.music_note,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Connect YouTube Music',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Sync your liked songs, playlists & more',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white, size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForgottenFavorites(bool isDark, ColorScheme colorScheme) {
    final recentlyPlayed = ref.watch(recentlyPlayedProvider);

    // Only show if user has some history
    if (recentlyPlayed.length < 3) {
      return const SizedBox.shrink();
    }

    // Take older items as "forgotten favorites"
    final forgotten = recentlyPlayed.length > 6
        ? recentlyPlayed.skip(4).take(6).toList()
        : recentlyPlayed.take(4).toList();

    // Prefetch forgotten favorites tracks for instant playback
    if (forgotten.isNotEmpty) {
      final prefetchManager = ref.read(trackPrefetchProvider);
      prefetchManager.prefetchVisibleTracks(forgotten);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Forgotten favorites',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : MineColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 160,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: forgotten.length,
            itemBuilder: (context, index) {
              final track = forgotten[index];
              return _buildAlbumCard(track, isDark, colorScheme);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAlbumCard(Track track, bool isDark, ColorScheme colorScheme) {
    final playerService = ref.watch(audioPlayerServiceProvider);
    // Capture notifier BEFORE async to avoid "ref after dispose" error
    final recentlyPlayedNotifier = ref.read(recentlyPlayedProvider.notifier);

    return GestureDetector(
      onTap: () async {
        await playerService.playTrack(track);
        recentlyPlayedNotifier.addTrack(track);
      },
      child: Container(
        width: 130,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 130,
                height: 130,
                child: track.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: track.thumbnailUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => _defaultArtwork(colorScheme),
                        errorWidget: (_, __, ___) =>
                            _defaultArtwork(colorScheme),
                      )
                    : _defaultArtwork(colorScheme),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              track.title,
              maxLines: 1,
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

  /// Default artwork placeholder
  Widget _defaultArtwork(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.primaryContainer,
      child: Icon(
        Icons.music_note_rounded,
        color: colorScheme.primary,
        size: 40,
      ),
    );
  }

  Widget _buildMixedForYou(bool isDark, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Mixed for you',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : MineColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 170,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 5,
            itemBuilder: (context, index) {
              final mixes = [
                ('My Mix 1', 'Based on your listening', Colors.indigo),
                ('Discover Mix', 'New music for you', Colors.teal),
                ('Replay Mix', 'Your favorites', Colors.orange),
                ('New Release', 'Fresh tracks', Colors.pink),
                ('Chill Mix', 'Relaxing vibes', Colors.blue),
              ];
              return _buildMixCard(
                mixes[index].$1,
                mixes[index].$2,
                mixes[index].$3,
                isDark,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMixCard(
    String title,
    String subtitle,
    Color color,
    bool isDark,
  ) {
    return GestureDetector(
      onTap: () => _performSearch(title),
      child: Container(
        width: 130,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withValues(alpha: 0.8),
                    color.withValues(alpha: 0.4),
                  ],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Icon(
                      Icons.queue_music_rounded,
                      size: 40,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
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

  Widget _buildTrendingSection(bool isDark, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                'JUST UPDATED',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white38 : MineColors.textSecondary,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            "Today's biggest hits",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 170, // Reduced from 180
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 5,
            itemBuilder: (context, index) {
              final playlists = [
                ('The Hit List', 'Top 50 songs right now'),
                ('Pop Certified', 'The best pop hits'),
                ('Bollywood Hotlist', 'Latest Bollywood'),
                ('Indie Mix', 'Fresh indie tracks'),
                ('Chill Vibes', 'Relax and unwind'),
              ];
              return _buildPlaylistCard(
                playlists[index].$1,
                playlists[index].$2,
                isDark,
                colorScheme,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNativeWelcomeShelf(
    HomeShelf shelf,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    final ytAuthState = ref.watch(ytMusicAuthStateProvider);
    final googleAuthState = ref.watch(googleAuthStateProvider);

    // Try to get name from Google Auth first, then YT Music, then fallback
    String userName = 'there';
    if (googleAuthState.isSignedIn &&
        googleAuthState.user?.displayName != null) {
      userName = googleAuthState.user!.displayName!.split(' ').first;
    } else if (ytAuthState.account?.name != null) {
      userName = ytAuthState.account!.name!.split(' ').first;
    }

    // Determine title: Use shelf title if it starts with "Welcome", otherwise "Welcome [Name]"
    // This handles the fallback case where we pick "Quick Picks" but want to show "Welcome User"
    final displayTitle = shelf.title.startsWith('Welcome')
        ? shelf.title
        : 'Welcome $userName';

    // Convert items to tracks
    final songs = shelf.items
        .where((item) => item.itemType == HomeShelfItemType.song)
        .map((item) => item.toTrack())
        .whereType<Track>()
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              // Profile avatar
              _buildProfileAvatar(isDark, colorScheme, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MUSIC TO GET YOU STARTED',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Colors.white54
                            : MineColors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      displayTitle,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : MineColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              // Jams button - minimalist
              GestureDetector(
                onTap: () => JamsScreen.open(context),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? Colors.white10 : Colors.grey.shade200,
                  ),
                  child: Icon(
                    Iconsax.profile_2user,
                    color: isDark ? Colors.white70 : MineColors.textSecondary,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Song cards grid
        if (songs.isNotEmpty)
          _buildSongCardsGrid(songs, isDark, colorScheme)
        else
          // Fallback if no songs found (e.g. mixed content), show standard carousel
          TrackListShelf(
            shelf: shelf,
            isDark: isDark,
            colorScheme: colorScheme,
          ),
      ],
    );
  }

  Widget _buildSongCardsGrid(
    List<Track> songs,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    final playerService = ref.watch(audioPlayerServiceProvider);

    // Calculate number of pages (4 songs per page)
    final pageCount = (songs.length / 4).ceil();

    return SizedBox(
      height: 292,
      child: PageView.builder(
        controller: PageController(viewportFraction: 0.92),
        itemCount: pageCount,
        itemBuilder: (context, pageIndex) {
          final startIndex = pageIndex * 4;
          final pageSongs = songs.skip(startIndex).take(4).toList();

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              children: pageSongs.asMap().entries.map((entry) {
                final isLast = entry.key == pageSongs.length - 1;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 6),
                    child: OptimizedTrackItem(
                      track: entry.value,
                      playerService: playerService,
                      isDark: isDark,
                      colorScheme: colorScheme,
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlaylistCard(
    String title,
    String subtitle,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    return Container(
      width: 130, // Slightly smaller
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 130,
            height: 130, // Reduced from 140
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Icon(
                Icons.queue_music_rounded,
                size: 48,
                color: colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : MineColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
