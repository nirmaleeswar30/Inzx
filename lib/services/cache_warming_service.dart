import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:inzx/data/repositories/music_repository.dart';
import 'package:inzx/core/services/result.dart';

/// Service for pre-loading cache on app startup
class CacheWarmingService {
  final MusicRepository _repository;

  CacheWarmingService(this._repository);

  /// Warm cache by pre-loading trending and liked songs
  /// Runs in background without blocking UI
  Future<void> warmCache({
    bool preTrendingMusic = true,
    bool prelikedSongs = true,
  }) async {
    try {
      final futures = <Future<dynamic>>[];

      if (preTrendingMusic) {
        futures.add(
          _repository
              .getTrendingTracks()
              .then((_) {
                if (kDebugMode) {
                  print('Cache warming: Trending music pre-loaded');
                }
              })
              .catchError((e) {
                if (kDebugMode) {
                  print('Cache warming: Failed to pre-load trending: $e');
                }
              }),
        );
      }

      if (prelikedSongs && _repository.isAuthenticated) {
        futures.add(
          _repository
              .getLikedSongs()
              .then((_) {
                if (kDebugMode) {
                  print('Cache warming: Liked songs pre-loaded');
                }
              })
              .catchError((e) {
                if (kDebugMode) {
                  print('Cache warming: Failed to pre-load liked songs: $e');
                }
              }),
        );
      }

      // Run all warming tasks in parallel but don't await
      // This allows app to start while warming happens in background
      Future.wait(futures).ignore();
    } catch (e) {
      if (kDebugMode) {
        print('Cache warming error: $e');
      }
    }
  }

  /// Check if cache has enough data
  Future<bool> isCacheWarmed() async {
    try {
      final result = await _repository.getCacheStats();
      return switch (result) {
        Success(:final data) => data.cachedTracksCount > 0,
        Failure() => false,
      };
    } catch (_) {
      return false;
    }
  }
}
