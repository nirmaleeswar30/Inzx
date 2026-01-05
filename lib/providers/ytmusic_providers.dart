import 'dart:convert';
import 'package:flutter/foundation.dart' show compute, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inzx/core/services/cache/hive_service.dart';
import 'package:inzx/data/entities/home_shelf_entity.dart';
import 'package:inzx/data/entities/album_cache_entity.dart';
import 'package:inzx/data/entities/artist_cache_entity.dart';
import 'package:inzx/data/entities/playlist_cache_entity.dart';
import 'package:inzx/data/repositories/music_repository.dart'
    show CacheAnalytics;
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
        if (kDebugMode) {print('✅ Auth restored from cache');}
        return;
      }
    } catch (e) {
      if (kDebugMode) {print('Failed to restore cached auth: $e');}
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
      if (kDebugMode) {print('✅ Login successful, auth cached');}
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
    if (kDebugMode) {print('ytMusicLikedSongsProvider: Not logged in, returning empty');}
    return [];
  }

  if (kDebugMode) {print('ytMusicLikedSongsProvider: Fetching liked songs...');}
  final innerTube = ref.watch(innerTubeServiceProvider);
  final songs = await innerTube.getLikedSongs();
  if (kDebugMode) {print('ytMusicLikedSongsProvider: Loaded ${songs.length} liked songs');}
  if (songs.isNotEmpty) {
    if (kDebugMode) {print(
      'ytMusicLikedSongsProvider: First few IDs: ${songs.take(5).map((t) => t.id).join(", ")}',
    );}
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

/// Saved albums from YT Music
final ytMusicSavedAlbumsProvider = FutureProvider<List<Album>>((ref) async {
  final authState = ref.watch(ytMusicAuthStateProvider);
  if (!authState.isLoggedIn) return [];

  final innerTube = ref.watch(innerTubeServiceProvider);
  return innerTube.getSavedAlbums();
});

/// Saved playlists from YT Music
final ytMusicSavedPlaylistsProvider = FutureProvider<List<Playlist>>((
  ref,
) async {
  final authState = ref.watch(ytMusicAuthStateProvider);
  if (!authState.isLoggedIn) return [];

  final innerTube = ref.watch(innerTubeServiceProvider);
  return innerTube.getSavedPlaylists();
});

/// Subscribed artists from YT Music
final ytMusicSubscribedArtistsProvider = FutureProvider<List<Artist>>((
  ref,
) async {
  final authState = ref.watch(ytMusicAuthStateProvider);
  if (!authState.isLoggedIn) return [];

  final innerTube = ref.watch(innerTubeServiceProvider);
  return innerTube.getSubscribedArtists();
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
  static const String _cacheKey = 'home_page';

  HomePageNotifier(this._innerTube) : super(const HomePageState()) {
    loadInitial();
  }

  Future<void> loadInitial() async {
    if (state.isLoading) return;

    // Try to load from cache first (stale-while-revalidate)
    final cacheResult = await _loadFromCache();
    if (cacheResult != null &&
        cacheResult.$1 != null &&
        cacheResult.$1!.isNotEmpty) {
      final cachedShelves = cacheResult.$1!;
      final cachedContinuationToken = cacheResult.$2;

      CacheAnalytics.instance.recordCacheHit();
      if (kDebugMode) {print(
        'HomePageNotifier: Loaded ${cachedShelves.length} shelves from cache, hasMore=${cachedContinuationToken != null}',
      );}
      state = HomePageState(
        shelves: cachedShelves,
        continuationToken: cachedContinuationToken,
        isLoading: false,
        fetchedAt: DateTime.now(),
      );

      // Check if cache is stale - if so, refresh in background
      final cached = HiveService.homePageBox.get(_cacheKey);
      if (cached != null && cached.isStale) {
        if (kDebugMode) {print('HomePageNotifier: Cache is stale, refreshing in background...');}
        _fetchFromNetwork(updateState: true);
      }
      return;
    }

    CacheAnalytics.instance.recordCacheMiss();
    state = state.copyWith(isLoading: true, hasError: false);
    if (kDebugMode) {print('HomePageNotifier: Starting loadInitial (double fetch)...');}

    await _fetchFromNetwork(updateState: true);
  }

  /// Load shelves from Hive cache - returns (shelves, continuationToken)
  Future<(List<HomeShelf>?, String?)?> _loadFromCache() async {
    try {
      final cached = HiveService.homePageBox.get(_cacheKey);
      if (cached != null && !cached.isExpired) {
        final shelves = await compute(
          _parseHomeShelvesIsolate,
          cached.shelvesJson,
        );
        return (shelves, cached.continuationToken);
      }
    } catch (e) {
      if (kDebugMode) {print('HomePageNotifier: Cache load error: $e');}
    }
    return null;
  }

  /// Save shelves to Hive cache
  Future<void> _saveToCache(
    List<HomeShelf> shelves,
    String? continuationToken,
  ) async {
    try {
      final jsonList = shelves.map((s) => s.toJson()).toList();
      final shelvesJson = await compute(_encodeHomeShelvesIsolate, jsonList);
      final entity = HomePageCacheEntity(
        shelvesJson: shelvesJson,
        continuationToken: continuationToken,
        cachedAt: DateTime.now(),
        ttlMinutes: 30,
      );
      HiveService.homePageBox.put(_cacheKey, entity);
      if (kDebugMode) {print('HomePageNotifier: Saved ${shelves.length} shelves to cache');}
    } catch (e) {
      if (kDebugMode) {print('HomePageNotifier: Cache save error: $e');}
    }
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
      if (kDebugMode) {print(
        'Network load complete: ${allShelves.length} shelves, hasMore=${content2.continuationToken != null}',
      );}
    } catch (e) {
      if (kDebugMode) {print('Error loading home page: $e');}
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
      if (kDebugMode) {print(
        'Loaded more: ${newShelves.length} new shelves, total=${state.shelves.length}, hasMore=${state.hasMore}',
      );}
    } catch (e) {
      if (kDebugMode) {print('Error loading more: $e');}
      state = state.copyWith(isLoadingMore: false);
    }
  }

  Future<void> refresh() async {
    if (!mounted) return; // Guard: check if notifier is still alive
    if (kDebugMode) {print('HomePageNotifier: refresh() called (force network fetch)');}
    // Reset state completely and reload
    state = const HomePageState();
    state = state.copyWith(isLoading: true, hasError: false);

    await _fetchFromNetwork(updateState: true);
  }
}

/// Provider for home page with continuation support
final ytMusicHomePageStateProvider =
    StateNotifierProvider<HomePageNotifier, HomePageState>((ref) {
      // Watch auth state - provider will recreate when it changes
      ref.watch(ytMusicAuthStateProvider);
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

final ytMusicPlaylistProvider = FutureProvider.family<Playlist?, String>((
  ref,
  playlistId,
) async {
  // Check cache first
  try {
    final cached = HiveService.playlistsBox.get(playlistId);
    if (cached != null && !cached.isExpired) {
      CacheAnalytics.instance.recordCacheHit();
      if (kDebugMode) {print('ytMusicPlaylistProvider: Loaded $playlistId from cache');}
      return await compute(_parsePlaylistIsolate, cached.playlistJson);
    }
  } catch (e) {
    if (kDebugMode) {print('ytMusicPlaylistProvider: Cache load error: $e');}
  }

  // Fetch from network
  CacheAnalytics.instance.recordCacheMiss();
  CacheAnalytics.instance.recordNetworkCall();
  final innerTube = ref.watch(innerTubeServiceProvider);
  final playlist = await innerTube.getPlaylist(playlistId);

  // Save to cache
  if (playlist != null) {
    try {
      HiveService.playlistsBox.put(
        playlistId,
        PlaylistCacheEntity(
          playlistId: playlistId,
          playlistJson: jsonEncode(playlist.toJson()),
          cachedAt: DateTime.now(),
          ttlMinutes: 30,
        ),
      );
      if (kDebugMode) {print('ytMusicPlaylistProvider: Cached $playlistId');}
    } catch (e) {
      if (kDebugMode) {print('ytMusicPlaylistProvider: Cache save error: $e');}
    }
  }

  return playlist;
});

final ytMusicAlbumProvider = FutureProvider.family<Album?, String>((
  ref,
  albumId,
) async {
  // Check cache first
  try {
    final cached = HiveService.albumsBox.get(albumId);
    if (cached != null && !cached.isExpired) {
      CacheAnalytics.instance.recordCacheHit();
      if (kDebugMode) {print('ytMusicAlbumProvider: Loaded $albumId from cache');}
      return await compute(_parseAlbumIsolate, cached.albumJson);
    }
  } catch (e) {
    if (kDebugMode) {print('ytMusicAlbumProvider: Cache load error: $e');}
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
      if (kDebugMode) {print('ytMusicAlbumProvider: Cached $albumId');}
    } catch (e) {
      if (kDebugMode) {print('ytMusicAlbumProvider: Cache save error: $e');}
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
      if (kDebugMode) {print('ytMusicArtistProvider: Loaded $artistId from cache');}
      return await compute(_parseArtistIsolate, cached.artistJson);
    }
  } catch (e) {
    if (kDebugMode) {print('ytMusicArtistProvider: Cache load error: $e');}
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
      if (kDebugMode) {print('ytMusicArtistProvider: Cached $artistId');}
    } catch (e) {
      if (kDebugMode) {print('ytMusicArtistProvider: Cache save error: $e');}
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
