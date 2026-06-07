import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart' show compute, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:inzx/core/services/cache/hive_service.dart';
import 'package:inzx/data/entities/home_shelf_entity.dart';
import 'package:inzx/data/entities/album_cache_entity.dart';
import 'package:inzx/data/entities/artist_cache_entity.dart';
import 'package:inzx/data/entities/playlist_cache_entity.dart';
import 'package:inzx/data/repositories/music_repository.dart'
    show CacheAnalytics;
import '../core/providers/locale_provider.dart';
import '../services/ytmusic_api_service.dart';
import '../services/ytmusic_auth_service.dart';
import '../models/models.dart';

// ============ CORE SERVICES ============

/// InnerTube API service provider - SINGLETON (use same instance everywhere)
final innerTubeServiceProvider = Provider<InnerTubeService>((ref) {
  // This provider is evaluated once and reused
  // The InnerTubeService instance persists across the app lifetime
  return InnerTubeService();
}).select((service) => service); // Prevent unnecessary rebuilds

/// YT Music Auth service provider
final ytMusicAuthServiceProvider = Provider<YTMusicAuthService>((ref) {
  final innerTube = ref.watch(innerTubeServiceProvider);
  return YTMusicAuthService(innerTube);
});

/// YT Music auth state
final ytMusicAuthStateProvider =
    StateNotifierProvider<YTMusicAuthNotifier, YTMusicAuthState>((ref) {
      final authService = ref.watch(ytMusicAuthServiceProvider);
      return YTMusicAuthNotifier(authService);
    });

class YTMusicAuthState {
  final bool isLoggedIn;
  final bool isLoading;
  final YTMusicAccount? account;
  final String? error;

  const YTMusicAuthState({
    this.isLoggedIn = false,
    this.isLoading = true,
    this.account,
    this.error,
  });

  YTMusicAuthState copyWith({
    bool? isLoggedIn,
    bool? isLoading,
    YTMusicAccount? account,
    String? error,
  }) {
    return YTMusicAuthState(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      isLoading: isLoading ?? this.isLoading,
      account: account ?? this.account,
      error: error,
    );
  }
}

class YTMusicAuthNotifier extends StateNotifier<YTMusicAuthState> {
  final YTMusicAuthService _authService;

  YTMusicAuthNotifier(this._authService) : super(const YTMusicAuthState()) {
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // First try to restore from cache
      final cached = await _authService.restoreCachedAuth();
      if (cached) {
        state = YTMusicAuthState(
          isLoggedIn: true,
          isLoading: false,
          account: _authService.account,
        );
        if (kDebugMode) {
          print('✅ Auth restored from cache');
        }
        return;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to restore cached auth: $e');
      }
    }

    // Then try to initialize from storage
    final success = await _authService.initialize();
    state = YTMusicAuthState(
      isLoggedIn: success && _authService.isLoggedIn,
      isLoading: false,
      account: _authService.account,
    );
  }

  Future<bool> login(
    Map<String, String> cookies, {
    YTMusicAccount? account,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    final success = await _authService.loginWithCookies(
      cookies,
      account: account,
    );

    state = YTMusicAuthState(
      isLoggedIn: success,
      isLoading: false,
      account: success ? (account ?? _authService.account) : null,
      error: success ? null : 'Login failed. Please try again.',
    );

    if (success) {
      if (kDebugMode) {
        print('✅ Login successful, auth cached');
      }
    }

    return success;
  }

  Future<void> logout() async {
    state = state.copyWith(isLoading: true);
    await _authService.logout();
    state = const YTMusicAuthState(isLoggedIn: false, isLoading: false);
  }
}

// ============ LIBRARY PROVIDERS ============

/// Liked songs from YT Music (keepAlive to avoid refetching)
final ytMusicLikedSongsProvider = FutureProvider.autoDispose<List<Track>>((
  ref,
) async {
  // Keep alive so it doesn't refetch every time
  ref.keepAlive();

  final authState = ref.watch(ytMusicAuthStateProvider);
  if (!authState.isLoggedIn) {
    if (kDebugMode) {
      print('ytMusicLikedSongsProvider: Not logged in, returning empty');
    }
    return [];
  }

  if (kDebugMode) {
    print('ytMusicLikedSongsProvider: Fetching liked songs...');
  }
  final innerTube = ref.watch(innerTubeServiceProvider);
  final songs = await innerTube.getLikedSongs();
  if (kDebugMode) {
    print('ytMusicLikedSongsProvider: Loaded ${songs.length} liked songs');
  }
  if (songs.isNotEmpty) {
    if (kDebugMode) {
      print(
        'ytMusicLikedSongsProvider: First few IDs: ${songs.take(5).map((t) => t.id).join(", ")}',
      );
    }
  }
  return songs;
});

/// Recently played from YT Music
final ytMusicRecentlyPlayedProvider = FutureProvider<List<Track>>((ref) async {
  final authState = ref.watch(ytMusicAuthStateProvider);
  if (!authState.isLoggedIn) return [];

  final innerTube = ref.watch(innerTubeServiceProvider);
  return innerTube.getRecentlyPlayed();
});

/// History sections from YT Music (Today, Yesterday, etc.)
final ytMusicHistorySectionsProvider = FutureProvider<List<HistorySection>>((ref) async {
  final authState = ref.watch(ytMusicAuthStateProvider);
  if (!authState.isLoggedIn) return [];

  final innerTube = ref.watch(innerTubeServiceProvider);
  return innerTube.getHistorySections();
});

/// Saved albums from YT Music
final ytMusicSavedAlbumsProvider = FutureProvider<List<Album>>((ref) async {
  final authState = ref.watch(ytMusicAuthStateProvider);
  if (!authState.isLoggedIn) return [];

  final innerTube = ref.watch(innerTubeServiceProvider);
  return innerTube.getSavedAlbums();
});

class YtMusicSavedPlaylistsNotifier extends AsyncNotifier<List<Playlist>> {
  @override
  FutureOr<List<Playlist>> build() async {
    final authState = ref.watch(ytMusicAuthStateProvider);
    if (!authState.isLoggedIn) return [];

    final innerTube = ref.watch(innerTubeServiceProvider);
    final playlists = (await innerTube.getSavedPlaylists()).toList();

    // Handle CDN caching delays for created/deleted playlists
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Filter out deleted ones
      final deletedIds = prefs.getStringList('ytm_deleted_playlists') ?? [];
      if (deletedIds.isNotEmpty) {
        playlists.removeWhere((p) => deletedIds.contains(p.id));
      }
      
      // Inject optimistically created ones
      final addedData = prefs.getStringList('ytm_added_playlists') ?? [];
      if (addedData.isNotEmpty) {
        final remainingAdded = <String>[];
        bool changed = false;
        
        for (final data in addedData) {
          try {
            final p = Playlist.fromJson(jsonDecode(data));
            if (!playlists.any((existing) => existing.id == p.id)) {
              playlists.insert(0, p);
              remainingAdded.add(data);
            } else {
              // The CDN caught up, we no longer need to manually inject it
              changed = true;
            }
          } catch (_) {}
        }
        
        if (changed) {
          await prefs.setStringList('ytm_added_playlists', remainingAdded);
        }
      }
    } catch (_) {}

    return playlists;
  }

  Future<void> addPlaylistOptimistically(String id, String title) async {
    final currentPlaylists = state.valueOrNull ?? [];
    
    final newPlaylist = Playlist(
      id: id,
      title: title,
      isLocal: false,
      isYTMusic: true,
      trackCount: 0,
      tracks: const [],
    );

    // Update state immediately
    state = AsyncData([newPlaylist, ...currentPlaylists]);

    // Save to SharedPreferences to survive restarts before CDN catches up
    try {
      final prefs = await SharedPreferences.getInstance();
      final addedData = prefs.getStringList('ytm_added_playlists') ?? [];
      final encoded = jsonEncode(newPlaylist.toJson());
      if (!addedData.contains(encoded)) {
        addedData.add(encoded);
        await prefs.setStringList('ytm_added_playlists', addedData);
      }
    } catch (_) {}
  }

  Future<void> incrementPlaylistTrackCount(String playlistId) async {
    if (state.hasValue) {
      final currentPlaylists = state.value!;
      final index = currentPlaylists.indexWhere((p) => p.id == playlistId);
      if (index != -1) {
        final p = currentPlaylists[index];
        final updated = List<Playlist>.from(currentPlaylists);
        updated[index] = p.copyWith(trackCount: (p.trackCount ?? 0) + 1);
        state = AsyncData(updated);
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final addedData = prefs.getStringList('ytm_added_playlists') ?? [];
      final newAddedData = <String>[];
      bool changed = false;
      
      for (final data in addedData) {
        try {
          final p = Playlist.fromJson(jsonDecode(data));
          if (p.id == playlistId) {
            final updatedP = p.copyWith(trackCount: (p.trackCount ?? 0) + 1);
            newAddedData.add(jsonEncode(updatedP.toJson()));
            changed = true;
          } else {
            newAddedData.add(data);
          }
        } catch (_) {
          newAddedData.add(data);
        }
      }
      
      if (changed) {
        await prefs.setStringList('ytm_added_playlists', newAddedData);
      }
    } catch (_) {}
  }

  Future<void> removePlaylistOptimistically(String playlistId) async {
    // Save to SharedPreferences so it survives restarts
    try {
      final prefs = await SharedPreferences.getInstance();
      final deletedIds = prefs.getStringList('ytm_deleted_playlists') ?? [];
      if (!deletedIds.contains(playlistId)) {
        deletedIds.add(playlistId);
        // Keep list small, e.g., last 50 deletions
        if (deletedIds.length > 50) deletedIds.removeAt(0);
        await prefs.setStringList('ytm_deleted_playlists', deletedIds);
      }
      // Also clear any cached tracks for this playlist
      HiveService.playlistsBox.delete(playlistId);
    } catch (_) {}

    if (state.hasValue) {
      final updated = state.value!.where((p) => p.id != playlistId).toList();
      state = AsyncData(updated);
    }
  }
}

final ytMusicSavedPlaylistsProvider = AsyncNotifierProvider<YtMusicSavedPlaylistsNotifier, List<Playlist>>(
  YtMusicSavedPlaylistsNotifier.new,
);

/// Current sort order for library artists
final ytMusicLibraryArtistSortProvider = StateProvider<LibraryArtistSort>((ref) => LibraryArtistSort.recentlyAdded);

/// Current filter for library artists (0 = Artists, 1 = Subscriptions)
final ytMusicLibraryArtistFilterProvider = StateProvider<int>((ref) => 0);

/// Library artists from YT Music (based on saved songs)
final ytMusicLibraryArtistsProvider = FutureProvider<List<Artist>>((ref) async {
  final authState = ref.watch(ytMusicAuthStateProvider);
  if (!authState.isLoggedIn) return [];

  final sort = ref.watch(ytMusicLibraryArtistSortProvider);
  final innerTube = ref.watch(innerTubeServiceProvider);
  return innerTube.getLibraryArtists(sort: sort);
});

/// Subscribed artists from YT Music
final ytMusicLibrarySubscriptionsProvider = FutureProvider<List<Artist>>((ref) async {
  final authState = ref.watch(ytMusicAuthStateProvider);
  if (!authState.isLoggedIn) return [];

  final sort = ref.watch(ytMusicLibraryArtistSortProvider);
  final innerTube = ref.watch(innerTubeServiceProvider);
  return innerTube.getLibrarySubscriptions(sort: sort);
});

// ============ HOME PAGE ============

/// Home page content from YT Music
final ytMusicHomePageProvider = FutureProvider<HomePageContent>((ref) async {
  final innerTube = ref.watch(innerTubeServiceProvider);
  return innerTube.getHomePageContent();
});

/// Refresh home page content
final ytMusicHomeRefreshProvider = StateProvider<int>((ref) => 0);

/// Home page with manual refresh support (basic provider - use StateNotifier for continuation)
final ytMusicHomeContentProvider = FutureProvider<HomePageContent>((ref) async {
  // Watch refresh trigger
  ref.watch(ytMusicHomeRefreshProvider);

  final innerTube = ref.watch(innerTubeServiceProvider);
  return innerTube.getHomePageContent();
});

/// Home page state with continuation support
class HomePageState {
  final List<HomeShelf> shelves;
  final String? continuationToken;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasError;
  final DateTime? fetchedAt;

  const HomePageState({
    this.shelves = const [],
    this.continuationToken,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasError = false,
    this.fetchedAt,
  });

  bool get hasMore => continuationToken != null;
  bool get isEmpty => shelves.isEmpty && !isLoading;

  HomePageState copyWith({
    List<HomeShelf>? shelves,
    String? continuationToken,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasError,
    DateTime? fetchedAt,
    bool clearContinuation = false,
  }) {
    return HomePageState(
      shelves: shelves ?? this.shelves,
      continuationToken: clearContinuation
          ? null
          : (continuationToken ?? this.continuationToken),
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasError: hasError ?? this.hasError,
      fetchedAt: fetchedAt ?? this.fetchedAt,
    );
  }
}

/// Home page notifier with continuation support and caching
class HomePageNotifier extends StateNotifier<HomePageState> {
  final InnerTubeService _innerTube;
  static const String _cacheKeyPrefix = 'home_page_v2';
  bool _didAutoLoadMore = false;

  HomePageNotifier(this._innerTube) : super(const HomePageState()) {
    loadInitial();
  }

  Future<void> loadInitial() async {
    if (state.isLoading) return;
    _didAutoLoadMore = false;

    // Try to load from cache first (stale-while-revalidate)
    final cacheResult = await _loadFromCache();
    if (cacheResult != null &&
        cacheResult.$1 != null &&
        cacheResult.$1!.isNotEmpty) {
      final cachedShelves = cacheResult.$1!;
      final cachedContinuationToken = cacheResult.$2;

      CacheAnalytics.instance.recordCacheHit();
      if (kDebugMode) {
        print(
          'HomePageNotifier: Loaded ${cachedShelves.length} shelves from cache, hasMore=${cachedContinuationToken != null}',
        );
      }
      state = HomePageState(
        shelves: cachedShelves,
        continuationToken: cachedContinuationToken,
        isLoading: false,
        fetchedAt: DateTime.now(),
      );

      // Check if cache is stale - if so, refresh in background
      final cacheKey = await _homeCacheKey();
      final cached = HiveService.homePageBox.get(cacheKey);
      if (cached != null && cached.isStale) {
        if (kDebugMode) {
          print(
            'HomePageNotifier: Cache is stale, refreshing in background...',
          );
        }
        _fetchFromNetwork(updateState: true);
      } else {
        // Warm up first continuation page so top shelves are fully populated
        // without waiting for user-initiated scrolling.
        unawaited(_autoLoadMoreIfNeeded());
      }
      return;
    }

    CacheAnalytics.instance.recordCacheMiss();
    state = state.copyWith(isLoading: true, hasError: false);
    if (kDebugMode) {
      print('HomePageNotifier: Starting loadInitial (double fetch)...');
    }

    await _fetchFromNetwork(updateState: true);
    await _autoLoadMoreIfNeeded();
  }

  /// Load shelves from Hive cache - returns (shelves, continuationToken)
  Future<(List<HomeShelf>?, String?)?> _loadFromCache() async {
    try {
      final cacheKey = await _homeCacheKey();
      final cached = HiveService.homePageBox.get(cacheKey);
      if (cached != null && !cached.isExpired) {
        final shelves = await compute(
          _parseHomeShelvesIsolate,
          cached.shelvesJson,
        );
        return (shelves, cached.continuationToken);
      }
    } catch (e) {
      if (kDebugMode) {
        print('HomePageNotifier: Cache load error: $e');
      }
    }
    return null;
  }

  /// Save shelves to Hive cache
  Future<void> _saveToCache(
    List<HomeShelf> shelves,
    String? continuationToken,
  ) async {
    try {
      final cacheKey = await _homeCacheKey();
      final jsonList = shelves.map((s) => s.toJson()).toList();
      final shelvesJson = await compute(_encodeHomeShelvesIsolate, jsonList);
      final entity = HomePageCacheEntity(
        shelvesJson: shelvesJson,
        continuationToken: continuationToken,
        cachedAt: DateTime.now(),
        ttlMinutes: 30,
      );
      HiveService.homePageBox.put(cacheKey, entity);
      if (kDebugMode) {
        print('HomePageNotifier: Saved ${shelves.length} shelves to cache');
      }
    } catch (e) {
      if (kDebugMode) {
        print('HomePageNotifier: Cache save error: $e');
      }
    }
  }

  Future<String> _homeCacheKey() async {
    String? storedLanguageCode;
    String? storedCountryCode;
    try {
      final prefs = await SharedPreferences.getInstance();
      storedLanguageCode = prefs.getString(AppLocaleNotifier.localePrefKey);
      storedCountryCode = prefs.getString(
        AppContentLocationNotifier.contentLocationPrefKey,
      );
    } catch (_) {
      // Fall through to system locale/location.
    }

    final effectiveLocale = resolveEffectiveAppLocale(
      storedCode: storedLanguageCode,
    );
    final languageCode = appLocaleStorageKey(effectiveLocale);
    final countryCode = resolveAppContentCountryCode(
      storedCountryCode: storedCountryCode,
    );
    return '${_cacheKeyPrefix}_${languageCode}_$countryCode';
  }

  /// Fetch shelves from network
  Future<void> _fetchFromNetwork({required bool updateState}) async {
    CacheAnalytics.instance.recordNetworkCall();
    try {
      // First fetch
      final content1 = await _innerTube.getHomePageContent();

      // Small delay before second fetch (simulates page refresh)
      await Future.delayed(const Duration(milliseconds: 300));

      // Second fetch - some shelves only appear on refresh
      final content2 = await _innerTube.getHomePageContent();

      // Merge shelves from both fetches, avoiding duplicates
      final allShelves = <HomeShelf>[];
      final seenTitles = <String>{};

      // Add shelves from first fetch
      for (final shelf in content1.shelves) {
        if (!seenTitles.contains(shelf.title)) {
          seenTitles.add(shelf.title);
          allShelves.add(shelf);
        }
      }

      // Add unique shelves from second fetch
      for (final shelf in content2.shelves) {
        if (!seenTitles.contains(shelf.title)) {
          seenTitles.add(shelf.title);
          allShelves.add(shelf);
        }
      }

      // Save to cache
      _saveToCache(allShelves, content2.continuationToken);

      if (!mounted) return;

      if (updateState) {
        state = HomePageState(
          shelves: allShelves,
          continuationToken: content2.continuationToken,
          isLoading: false,
          fetchedAt: DateTime.now(),
        );
      }
      if (updateState) {
        unawaited(_autoLoadMoreIfNeeded());
      }
      if (kDebugMode) {
        print(
          'Network load complete: ${allShelves.length} shelves, hasMore=${content2.continuationToken != null}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading home page: $e');
      }
      if (!mounted) return;
      if (updateState) {
        state = state.copyWith(isLoading: false, hasError: true);
      }
    }
  }

  // Debounce loadMore calls
  DateTime? _lastLoadMoreTime;
  static const _loadMoreDebounce = Duration(milliseconds: 500);

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;

    // Debounce - prevent rapid-fire calls
    final now = DateTime.now();
    if (_lastLoadMoreTime != null &&
        now.difference(_lastLoadMoreTime!) < _loadMoreDebounce) {
      return;
    }
    _lastLoadMoreTime = now;

    state = state.copyWith(isLoadingMore: true);

    try {
      final content = await _innerTube.getHomePageContinuation(
        state.continuationToken!,
      );

      // Filter out duplicates based on shelf title
      final existingTitles = state.shelves.map((s) => s.title).toSet();
      final newShelves = content.shelves
          .where((s) => !existingTitles.contains(s.title))
          .toList();

      state = state.copyWith(
        shelves: [...state.shelves, ...newShelves],
        continuationToken: content.continuationToken,
        isLoadingMore: false,
        clearContinuation: content.continuationToken == null,
      );
      if (kDebugMode) {
        print(
          'Loaded more: ${newShelves.length} new shelves, total=${state.shelves.length}, hasMore=${state.hasMore}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading more: $e');
      }
      state = state.copyWith(isLoadingMore: false);
    }
  }

  Future<void> refresh() async {
    if (!mounted) return; // Guard: check if notifier is still alive
    if (kDebugMode) {
      print('HomePageNotifier: refresh() called (force network fetch)');
    }
    _didAutoLoadMore = false;
    // Reset state completely and reload
    state = const HomePageState();
    state = state.copyWith(isLoading: true, hasError: false);

    await _fetchFromNetwork(updateState: true);
  }

  Future<void> _autoLoadMoreIfNeeded() async {
    if (!mounted || _didAutoLoadMore) return;
    if (!state.hasMore || state.isLoading || state.isLoadingMore) return;

    _didAutoLoadMore = true;
    await loadMore();
  }
}

/// Provider for home page with continuation support
final ytMusicHomePageStateProvider =
    StateNotifierProvider<HomePageNotifier, HomePageState>((ref) {
      // Watch auth state - provider will recreate when it changes
      ref.watch(ytMusicAuthStateProvider);
      ref.watch(appLocaleProvider);
      final innerTube = ref.watch(innerTubeServiceProvider);

      // Create fresh notifier - old one will be disposed
      // This ensures we always fetch with correct auth state
      return HomePageNotifier(innerTube);
    });

// ============ SEARCH ============

final ytMusicSearchQueryProvider = StateProvider<String>((ref) => '');

final ytMusicSearchResultsProvider = FutureProvider<SearchResults?>((
  ref,
) async {
  final query = ref.watch(ytMusicSearchQueryProvider);
  if (query.isEmpty) return null;

  final innerTube = ref.watch(innerTubeServiceProvider);
  return innerTube.search(query);
});

final ytMusicSearchSuggestionsProvider =
    FutureProvider.family<List<String>, String>((ref, query) async {
      if (query.length < 2) return [];

      final innerTube = ref.watch(innerTubeServiceProvider);
      return innerTube.getSearchSuggestions(query);
    });

// ============ CONTENT DETAILS ============

class YtMusicPlaylistNotifier extends FamilyAsyncNotifier<Playlist?, String> {
  @override
  FutureOr<Playlist?> build(String arg) async {
    // Check cache first
    try {
      final cached = HiveService.playlistsBox.get(arg);
      if (cached != null && !cached.isExpired) {
        CacheAnalytics.instance.recordCacheHit();
        if (kDebugMode) {
          print('ytMusicPlaylistProvider: Loaded $arg from cache');
        }
        Playlist cachedPlaylist = await compute(
          _parsePlaylistIsolate,
          cached.playlistJson,
        );

        // Filter out locally deleted tracks that might still be cached
        try {
          final prefs = await SharedPreferences.getInstance();
          final removedIds = prefs.getStringList('ytm_removed_tracks_$arg') ?? [];
          if (removedIds.isNotEmpty && cachedPlaylist.tracks != null) {
            final filteredTracks = cachedPlaylist.tracks!.where((t) => !removedIds.contains(t.id)).toList();
            cachedPlaylist = cachedPlaylist.copyWith(tracks: filteredTracks);
          }
        } catch (_) {}

        // Older builds could cache only the first page (~100 tracks).
        // Force one network refresh for this suspicious payload shape.
        // Also force a network refresh if it's missing the new rich header metadata.
        final needsMetadataRefresh = cachedPlaylist.isYTMusic && (
            cachedPlaylist.extraSubtitle == null ||
            cachedPlaylist.author == null ||
            cachedPlaylist.authorAvatarUrl == null ||
            cachedPlaylist.author == 'Playlist' ||
            cachedPlaylist.author == 'Album' ||
            cachedPlaylist.author == 'Single' ||
            cachedPlaylist.author == 'Public' ||
            cachedPlaylist.author == 'Private'
        );
        if (((cachedPlaylist.tracks?.length ?? 0) == 100) || needsMetadataRefresh) {
          if (kDebugMode) {
            print(
              'ytMusicPlaylistProvider: Cached playlist $arg has stale metadata or exactly 100 tracks, refetching',
            );
          }
        } else {
          return cachedPlaylist;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('ytMusicPlaylistProvider: Cache load error: $e');
      }
    }

    // Fetch from network
    CacheAnalytics.instance.recordCacheMiss();
    CacheAnalytics.instance.recordNetworkCall();
    final innerTube = ref.watch(innerTubeServiceProvider);
    final playlist = await innerTube.getPlaylist(arg);

    // Save to cache
    if (playlist != null) {
      try {
        HiveService.playlistsBox.put(
          arg,
          PlaylistCacheEntity(
            playlistId: arg,
            playlistJson: jsonEncode(playlist.toJson()),
            cachedAt: DateTime.now(),
            ttlMinutes: 30,
          ),
        );
        if (kDebugMode) {
          print('ytMusicPlaylistProvider: Cached $arg');
        }
      } catch (e) {
        if (kDebugMode) {
          print('ytMusicPlaylistProvider: Cache save error: $e');
        }
      }
    }
    
    // Filter out locally deleted tracks that might still be cached on YouTube's servers
    if (playlist != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final removedIds = prefs.getStringList('ytm_removed_tracks_$arg') ?? [];
        if (removedIds.isNotEmpty && playlist.tracks != null) {
          final filteredTracks = playlist.tracks!.where((t) => !removedIds.contains(t.id)).toList();
          return playlist.copyWith(tracks: filteredTracks);
        }
      } catch (_) {}
    }

    return playlist;
  }

  Future<void> removeTrackOptimistically(String trackId) async {
    // Save to SharedPreferences so it survives restarts
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'ytm_removed_tracks_$arg';
      final removedIds = prefs.getStringList(key) ?? [];
      if (!removedIds.contains(trackId)) {
        removedIds.add(trackId);
        // Keep list small
        if (removedIds.length > 50) removedIds.removeAt(0);
        await prefs.setStringList(key, removedIds);
      }
    } catch (_) {}

    if (state.hasValue && state.value != null) {
      final updatedTracks = state.value!.tracks?.where((t) => t.id != trackId).toList();
      final updatedPlaylist = state.value!.copyWith(tracks: updatedTracks);
      // update cache
      try {
        HiveService.playlistsBox.delete(arg);
      } catch (_) {}
      state = AsyncData(updatedPlaylist);
    }
  }
}

final ytMusicPlaylistProvider = AsyncNotifierProviderFamily<YtMusicPlaylistNotifier, Playlist?, String>(
  YtMusicPlaylistNotifier.new,
);

final ytMusicAlbumProvider = FutureProvider.family<Album?, String>((
  ref,
  albumId,
) async {
  // Check cache first
  try {
    final cached = HiveService.albumsBox.get(albumId);
    if (cached != null && !cached.isExpired) {
      CacheAnalytics.instance.recordCacheHit();
      final cachedAlbum = await compute(_parseAlbumIsolate, cached.albumJson);
      final hasTrackList =
          cachedAlbum.tracks != null && cachedAlbum.tracks!.isNotEmpty;
      final isKnownEmptyAlbum = cachedAlbum.trackCount == 0;

      if (hasTrackList || isKnownEmptyAlbum) {
        if (kDebugMode) {
          print('ytMusicAlbumProvider: Loaded $albumId from cache');
        }
        return cachedAlbum;
      }

      if (kDebugMode) {
        print(
          'ytMusicAlbumProvider: Cache missing track list for $albumId, refetching from network',
        );
      }
    }
  } catch (e) {
    if (kDebugMode) {
      print('ytMusicAlbumProvider: Cache load error: $e');
    }
  }

  // Fetch from network
  CacheAnalytics.instance.recordCacheMiss();
  CacheAnalytics.instance.recordNetworkCall();
  final innerTube = ref.watch(innerTubeServiceProvider);
  final album = await innerTube.getAlbum(albumId);

  // Save to cache
  if (album != null) {
    try {
      HiveService.albumsBox.put(
        albumId,
        AlbumCacheEntity(
          albumId: albumId,
          albumJson: jsonEncode(album.toJson()),
          cachedAt: DateTime.now(),
          ttlMinutes: 60,
        ),
      );
      if (kDebugMode) {
        print('ytMusicAlbumProvider: Cached $albumId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('ytMusicAlbumProvider: Cache save error: $e');
      }
    }
  }

  return album;
});

final ytMusicArtistProvider = FutureProvider.family<Artist?, String>((
  ref,
  artistId,
) async {
  // Check cache first
  try {
    final cached = HiveService.artistsBox.get(artistId);
    if (cached != null && !cached.isExpired) {
      CacheAnalytics.instance.recordCacheHit();
      if (kDebugMode) {
        print('ytMusicArtistProvider: Loaded $artistId from cache');
      }
      return await compute(_parseArtistIsolate, cached.artistJson);
    }
  } catch (e) {
    if (kDebugMode) {
      print('ytMusicArtistProvider: Cache load error: $e');
    }
  }

  // Fetch from network
  CacheAnalytics.instance.recordCacheMiss();
  CacheAnalytics.instance.recordNetworkCall();
  final innerTube = ref.watch(innerTubeServiceProvider);
  final artist = await innerTube.getArtist(artistId);

  // Save to cache
  if (artist != null) {
    try {
      HiveService.artistsBox.put(
        artistId,
        ArtistCacheEntity(
          artistId: artistId,
          artistJson: jsonEncode(artist.toJson()),
          cachedAt: DateTime.now(),
          ttlMinutes: 60,
        ),
      );
      if (kDebugMode) {
        print('ytMusicArtistProvider: Cached $artistId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('ytMusicArtistProvider: Cache save error: $e');
      }
    }
  }

  return artist;
});

// ============ ACTIONS ============

/// Provider to like/unlike a song
final ytMusicLikeActionProvider = Provider<YTMusicLikeAction>((ref) {
  final innerTube = ref.watch(innerTubeServiceProvider);
  final authState = ref.watch(ytMusicAuthStateProvider);
  return YTMusicLikeAction(innerTube, authState.isLoggedIn);
});

class YTMusicLikeAction {
  final InnerTubeService _innerTube;
  final bool _isLoggedIn;

  YTMusicLikeAction(this._innerTube, this._isLoggedIn);

  Future<bool> like(String videoId) async {
    if (!_isLoggedIn) return false;
    return _innerTube.likeVideo(videoId, true);
  }

  Future<bool> unlike(String videoId) async {
    if (!_isLoggedIn) return false;
    return _innerTube.likeVideo(videoId, false);
  }
}

/// Provider to manage playlists
final ytMusicPlaylistActionProvider = Provider<YTMusicPlaylistAction>((ref) {
  final innerTube = ref.watch(innerTubeServiceProvider);
  final authState = ref.watch(ytMusicAuthStateProvider);
  return YTMusicPlaylistAction(innerTube, authState.isLoggedIn);
});

class YTMusicPlaylistAction {
  final InnerTubeService _innerTube;
  final bool _isLoggedIn;

  YTMusicPlaylistAction(this._innerTube, this._isLoggedIn);

  Future<String?> create(
    String title, {
    String? description,
    bool isPrivate = true,
  }) async {
    if (!_isLoggedIn) return null;
    return _innerTube.createPlaylist(
      title,
      description: description,
      isPrivate: isPrivate,
    );
  }

  Future<bool> delete(String playlistId) async {
    if (!_isLoggedIn) return false;
    return _innerTube.deletePlaylist(playlistId);
  }

  Future<bool> addSong(String playlistId, String videoId) async {
    if (!_isLoggedIn) return false;
    return _innerTube.addToPlaylist(playlistId, videoId);
  }

  Future<bool> removeSong(
    String playlistId,
    String videoId,
    String setVideoId,
  ) async {
    if (!_isLoggedIn) return false;
    return _innerTube.removeFromPlaylist(playlistId, videoId, setVideoId);
  }
}

/// Provider to subscribe/unsubscribe from artists
final ytMusicSubscribeActionProvider = Provider<YTMusicSubscribeAction>((ref) {
  final innerTube = ref.watch(innerTubeServiceProvider);
  final authState = ref.watch(ytMusicAuthStateProvider);
  return YTMusicSubscribeAction(innerTube, authState.isLoggedIn);
});

class YTMusicSubscribeAction {
  final InnerTubeService _innerTube;
  final bool _isLoggedIn;

  YTMusicSubscribeAction(this._innerTube, this._isLoggedIn);

  Future<bool> subscribe(String channelId) async {
    if (!_isLoggedIn) return false;
    return _innerTube.subscribeArtist(channelId, true);
  }

  Future<bool> unsubscribe(String channelId) async {
    if (!_isLoggedIn) return false;
    return _innerTube.subscribeArtist(channelId, false);
  }
}

// ============ ISOLATE FUNCTIONS ============

/// Top-level function for isolate - parses home shelves JSON
List<HomeShelf> _parseHomeShelvesIsolate(String json) {
  final List<dynamic> jsonList = jsonDecode(json);
  return jsonList
      .map((e) => HomeShelf.fromJson(e as Map<String, dynamic>))
      .toList();
}

/// Top-level function for isolate - encodes home shelves to JSON
String _encodeHomeShelvesIsolate(List<Map<String, dynamic>> jsonList) {
  return jsonEncode(jsonList);
}

/// Top-level function for isolate - parses playlist JSON
Playlist _parsePlaylistIsolate(String json) {
  return Playlist.fromJson(jsonDecode(json));
}

/// Top-level function for isolate - parses album JSON
Album _parseAlbumIsolate(String json) {
  return Album.fromJson(jsonDecode(json));
}

/// Top-level function for isolate - parses artist JSON
Artist _parseArtistIsolate(String json) {
  return Artist.fromJson(jsonDecode(json));
}
