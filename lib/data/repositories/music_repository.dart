import 'package:flutter/foundation.dart';
import 'package:inzx/core/services/result.dart';
import 'package:inzx/core/services/cache/cache_config.dart';
import 'package:inzx/models/track.dart';
import 'package:inzx/data/sources/music_local_source.dart';
import 'package:inzx/data/sources/music_remote_source.dart';

/// Global cache analytics singleton - tracks hits/misses across all caching layers
class CacheAnalytics extends ChangeNotifier {
  // Singleton instance
  static final CacheAnalytics _instance = CacheAnalytics._internal();
  static CacheAnalytics get instance => _instance;

  CacheAnalytics._internal();

  // For backwards compatibility with MusicRepository
  factory CacheAnalytics() => _instance;

  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _networkCalls = 0;

  int get cacheHits => _cacheHits;
  int get cacheMisses => _cacheMisses;
  int get networkCalls => _networkCalls;

  double get hitRate => _cacheHits + _cacheMisses == 0
      ? 0.0
      : (_cacheHits / (_cacheHits + _cacheMisses)) * 100;

  void recordCacheHit() {
    _cacheHits++;
    notifyListeners();
  }

  void recordCacheMiss() {
    _cacheMisses++;
    notifyListeners();
  }

  void recordNetworkCall() {
    _networkCalls++;
    notifyListeners();
  }

  void reset() {
    _cacheHits = 0;
    _cacheMisses = 0;
    _networkCalls = 0;
    notifyListeners();
  }

  @override
  String toString() =>
      'Cache Hits: $_cacheHits, Misses: $_cacheMisses, Hit Rate: ${hitRate.toStringAsFixed(1)}%, Network: $_networkCalls';
}

/// Business logic layer for music operations
/// Orchestrates local cache and remote services with intelligent caching strategies
class MusicRepository {
  final MusicLocalSource _localSource;
  final MusicRemoteSource _remoteSource;
  final CacheAnalytics analytics = CacheAnalytics();

  MusicRepository({
    required MusicLocalSource localSource,
    required MusicRemoteSource remoteSource,
  }) : _localSource = localSource,
       _remoteSource = remoteSource;

  // ============ Search ============

  /// Search for tracks with configurable cache strategy
  Future<Result<List<Track>>> search(
    String query, {
    CacheConfig? config,
  }) async {
    final cacheConfig = config ?? CacheConfig.networkWithFallback();

    return switch (cacheConfig.policy) {
      CachePolicy.networkFirst => _networkFirstSearch(query, cacheConfig),
      CachePolicy.cacheFirst => _cacheFirstSearch(query, cacheConfig),
      CachePolicy.networkWithFallback => _networkWithFallbackSearch(
        query,
        cacheConfig,
      ),
      CachePolicy.cacheOnly => _cacheOnlySearch(query),
    };
  }

  /// Strategy 1: Try network first, fall back to cache
  Future<Result<List<Track>>> _networkFirstSearch(
    String query,
    CacheConfig config,
  ) async {
    // Try network
    analytics.recordNetworkCall();
    final networkResult = await _remoteSource.searchTracks(query);

    if (networkResult is Success) {
      // Cache the results
      final tracks = (networkResult as Success<List<Track>>).data;
      await _localSource.cacheSearchResults(query, tracks);
      analytics.recordCacheMiss(); // Network first = cache miss
      return networkResult;
    }

    // Network failed, try cache
    final cacheResult = await _localSource.getCachedSearchResults(query);
    if (cacheResult is Success) {
      final cached = (cacheResult as Success<List<Track>>).data;
      if (cached.isNotEmpty) {
        analytics.recordCacheHit();
        return cacheResult;
      }
    }

    // Both failed
    analytics.recordCacheMiss();
    return networkResult;
  }

  /// Strategy 2: Use cache if valid, otherwise fetch from network
  Future<Result<List<Track>>> _cacheFirstSearch(
    String query,
    CacheConfig config,
  ) async {
    // Check cache validity
    final isCached = await _localSource.isCacheValid('search:$query');
    if (isCached is Success && (isCached as Success<bool>).data) {
      final cacheResult = await _localSource.getCachedSearchResults(query);
      if (cacheResult is Success) {
        final cached = (cacheResult as Success<List<Track>>).data;
        if (cached.isNotEmpty) {
          analytics.recordCacheHit();
          return cacheResult;
        }
      }
    }

    // Cache miss or invalid, fetch from network
    analytics.recordCacheMiss();
    analytics.recordNetworkCall();
    final networkResult = await _remoteSource.searchTracks(query);
    if (networkResult is Success) {
      final tracks = (networkResult as Success<List<Track>>).data;
      await _localSource.cacheSearchResults(query, tracks);
    }

    return networkResult;
  }

  /// Strategy 3: Network with cache fallback (default)
  Future<Result<List<Track>>> _networkWithFallbackSearch(
    String query,
    CacheConfig config,
  ) async {
    // Check if force refresh
    if (config.forceRefresh) {
      analytics.recordNetworkCall();
      final networkResult = await _remoteSource.searchTracks(query);
      if (networkResult is Success) {
        final tracks = (networkResult as Success<List<Track>>).data;
        await _localSource.cacheSearchResults(query, tracks);
      }
      analytics.recordCacheMiss();
      return networkResult;
    }

    // Try network first
    analytics.recordNetworkCall();
    final networkResult = await _remoteSource.searchTracks(query);
    if (networkResult is Success) {
      final tracks = (networkResult as Success<List<Track>>).data;
      await _localSource.cacheSearchResults(query, tracks);
      analytics.recordCacheMiss();
      return networkResult;
    }

    // Fall back to cache
    final cacheResult = await _localSource.getCachedSearchResults(query);
    if (cacheResult is Success) {
      final cached = (cacheResult as Success<List<Track>>).data;
      if (cached.isNotEmpty) {
        analytics.recordCacheHit();
        return cacheResult;
      }
    }
    analytics.recordCacheMiss();
    return cacheResult;
  }

  /// Strategy 4: Cache only, no network
  Future<Result<List<Track>>> _cacheOnlySearch(String query) async {
    final result = await _localSource.getCachedSearchResults(query);
    if (result is Success) {
      final cached = (result as Success<List<Track>>).data;
      if (cached.isNotEmpty) {
        analytics.recordCacheHit();
      } else {
        analytics.recordCacheMiss();
      }
    } else {
      analytics.recordCacheMiss();
    }
    return result;
  }

  // ============ Trending ============

  /// Get trending tracks with cache strategy
  Future<Result<List<Track>>> getTrendingTracks({CacheConfig? config}) async {
    final cacheConfig = config ?? CacheConfig.networkWithFallback();

    return switch (cacheConfig.policy) {
      CachePolicy.networkFirst => _networkFirstTrending(cacheConfig),
      CachePolicy.cacheFirst => _cacheFirstTrending(cacheConfig),
      CachePolicy.networkWithFallback => _networkWithFallbackTrending(
        cacheConfig,
      ),
      CachePolicy.cacheOnly => _cacheOnlyTrending(),
    };
  }

  Future<Result<List<Track>>> _networkFirstTrending(CacheConfig config) async {
    analytics.recordNetworkCall();
    final networkResult = await _remoteSource.getTrendingTracks();
    if (networkResult is Success) {
      final tracks = (networkResult as Success<List<Track>>).data;
      await _localSource.cacheTrendingTracks(tracks);
      analytics.recordCacheMiss();
      return networkResult;
    }

    final cacheResult = await _localSource.getTrendingTracks();
    if (cacheResult is Success) {
      final cached = (cacheResult as Success<List<Track>>).data;
      if (cached.isNotEmpty) {
        analytics.recordCacheHit();
        return cacheResult;
      }
    }

    analytics.recordCacheMiss();
    return networkResult;
  }

  Future<Result<List<Track>>> _cacheFirstTrending(CacheConfig config) async {
    final isCached = await _localSource.isCacheValid('trending');
    if (isCached is Success && (isCached as Success<bool>).data) {
      final cacheResult = await _localSource.getTrendingTracks();
      if (cacheResult is Success) {
        final cached = (cacheResult as Success<List<Track>>).data;
        if (cached.isNotEmpty) {
          analytics.recordCacheHit();
          return cacheResult;
        }
      }
    }

    analytics.recordCacheMiss();
    analytics.recordNetworkCall();
    final networkResult = await _remoteSource.getTrendingTracks();
    if (networkResult is Success) {
      final tracks = (networkResult as Success<List<Track>>).data;
      await _localSource.cacheTrendingTracks(tracks);
    }

    return networkResult;
  }

  Future<Result<List<Track>>> _networkWithFallbackTrending(
    CacheConfig config,
  ) async {
    if (config.forceRefresh) {
      analytics.recordNetworkCall();
      final networkResult = await _remoteSource.getTrendingTracks();
      if (networkResult is Success) {
        final tracks = (networkResult as Success<List<Track>>).data;
        await _localSource.cacheTrendingTracks(tracks);
      }
      analytics.recordCacheMiss();
      return networkResult;
    }

    analytics.recordNetworkCall();
    final networkResult = await _remoteSource.getTrendingTracks();
    if (networkResult is Success) {
      final tracks = (networkResult as Success<List<Track>>).data;
      await _localSource.cacheTrendingTracks(tracks);
      analytics.recordCacheMiss();
      return networkResult;
    }

    final cacheResult = await _localSource.getTrendingTracks();
    if (cacheResult is Success) {
      final cached = (cacheResult as Success<List<Track>>).data;
      if (cached.isNotEmpty) {
        analytics.recordCacheHit();
        return cacheResult;
      }
    }
    analytics.recordCacheMiss();
    return cacheResult;
  }

  Future<Result<List<Track>>> _cacheOnlyTrending() async {
    final result = await _localSource.getTrendingTracks();
    if (result is Success) {
      final cached = (result as Success<List<Track>>).data;
      if (cached.isNotEmpty) {
        analytics.recordCacheHit();
      } else {
        analytics.recordCacheMiss();
      }
    } else {
      analytics.recordCacheMiss();
    }
    return result;
  }

  // ============ Library (Auth Required) ============

  /// Get liked songs with cache strategy
  Future<Result<List<Track>>> getLikedSongs({CacheConfig? config}) async {
    final cacheConfig = config ?? CacheConfig.networkWithFallback();

    // Auth check
    if (!_remoteSource.isAuthenticated) {
      return Result.failure(AuthException('User not authenticated'));
    }

    switch (cacheConfig.policy) {
      case CachePolicy.networkFirst:
        return _networkFirstLikedSongs(cacheConfig);
      case CachePolicy.cacheFirst:
        return _cacheFirstLikedSongs(cacheConfig);
      case CachePolicy.networkWithFallback:
        return _networkWithFallbackLikedSongs(cacheConfig);
      case CachePolicy.cacheOnly:
        return _cacheOnlyLikedSongs();
    }
  }

  Future<Result<List<Track>>> _networkFirstLikedSongs(
    CacheConfig config,
  ) async {
    analytics.recordNetworkCall();
    final networkResult = await _remoteSource.getLikedSongs();
    if (networkResult is Success) {
      final tracks = (networkResult as Success<List<Track>>).data;
      await _localSource.saveTracks(tracks);
      analytics.recordCacheMiss();
      return networkResult;
    }

    final cacheResult = await _localSource.getLikedSongs();
    if (cacheResult is Success) {
      final cached = (cacheResult as Success<List<Track>>).data;
      if (cached.isNotEmpty) {
        analytics.recordCacheHit();
        return cacheResult;
      }
    }

    analytics.recordCacheMiss();
    return networkResult;
  }

  Future<Result<List<Track>>> _cacheFirstLikedSongs(CacheConfig config) async {
    final cacheResult = await _localSource.getLikedSongs();
    if (cacheResult is Success) {
      final cached = (cacheResult as Success<List<Track>>).data;
      if (cached.isNotEmpty) {
        analytics.recordCacheHit();
        return cacheResult;
      }
    }

    analytics.recordCacheMiss();
    analytics.recordNetworkCall();
    final networkResult = await _remoteSource.getLikedSongs();
    if (networkResult is Success) {
      final tracks = (networkResult as Success<List<Track>>).data;
      await _localSource.saveTracks(tracks);
    }

    return networkResult;
  }

  Future<Result<List<Track>>> _networkWithFallbackLikedSongs(
    CacheConfig config,
  ) async {
    if (config.forceRefresh) {
      analytics.recordNetworkCall();
      final networkResult = await _remoteSource.getLikedSongs();
      if (networkResult is Success) {
        final tracks = (networkResult as Success<List<Track>>).data;
        await _localSource.saveTracks(tracks);
      }
      analytics.recordCacheMiss();
      return networkResult;
    }

    analytics.recordNetworkCall();
    final networkResult = await _remoteSource.getLikedSongs();
    if (networkResult is Success) {
      final tracks = (networkResult as Success<List<Track>>).data;
      await _localSource.saveTracks(tracks);
      analytics.recordCacheMiss();
      return networkResult;
    }

    final cacheResult = await _localSource.getLikedSongs();
    if (cacheResult is Success) {
      final cached = (cacheResult as Success<List<Track>>).data;
      if (cached.isNotEmpty) {
        analytics.recordCacheHit();
        return cacheResult;
      }
    }
    analytics.recordCacheMiss();
    return cacheResult;
  }

  Future<Result<List<Track>>> _cacheOnlyLikedSongs() async {
    final result = await _localSource.getLikedSongs();
    if (result is Success) {
      final cached = (result as Success<List<Track>>).data;
      if (cached.isNotEmpty) {
        analytics.recordCacheHit();
      } else {
        analytics.recordCacheMiss();
      }
    } else {
      analytics.recordCacheMiss();
    }
    return result;
  }

  // ============ Cache Management ============

  /// Get detailed cache statistics
  Future<Result<CacheStats>> getCacheStats() async {
    return await _localSource.getCacheStats();
  }

  /// Clean up expired cache entries
  Future<Result<int>> cleanupExpiredCache() async {
    return await _localSource.cleanupExpiredEntries();
  }

  /// Clear all cache (use with caution)
  Future<Result<void>> clearAllCache() async {
    return await _localSource.clearAll();
  }

  // ============ Utility ============

  /// Check if user is authenticated
  bool get isAuthenticated => _remoteSource.isAuthenticated;
}
