import 'package:inzx/core/services/result.dart';
import 'package:inzx/data/entities/cache_metadata_entity.dart';
import 'package:inzx/data/entities/track_entity.dart';
import 'package:inzx/models/track.dart';
import 'package:inzx/core/services/cache/hive_service.dart';

/// Local data source for music using Hive for caching
class MusicLocalSource {
  static const String _cacheKeyPrefix = 'search:';
  static const String _trendingCacheKey = 'trending';

  /// Get a single track by ID
  Future<Result<Track?>> getTrack(String id) async {
    try {
      final entity = HiveService.tracksBox.get(id);
      return Result.success(entity?.let(_toDomain));
    } catch (e) {
      return Result.failure(CacheException('Failed to get track: $e'));
    }
  }

  /// Save a single track to cache
  Future<Result<void>> saveTrack(Track track) async {
    try {
      final entity = _toEntity(track);
      await HiveService.tracksBox.put(track.id, entity);
      await _updateMetadata(_cacheKeyPrefix + track.id, 30);
      return Result.success(null);
    } catch (e) {
      return Result.failure(CacheException('Failed to save track: $e'));
    }
  }

  /// Save multiple tracks to cache
  Future<Result<void>> saveTracks(List<Track> tracks) async {
    try {
      final entities = {for (var t in tracks) t.id: _toEntity(t)};
      await HiveService.tracksBox.putAll(entities);
      await _updateMetadata(_cacheKeyPrefix + 'batch', 30);
      return Result.success(null);
    } catch (e) {
      return Result.failure(CacheException('Failed to save tracks: $e'));
    }
  }

  /// Search cached tracks by title or artist
  Future<Result<List<Track>>> searchTracks(String query) async {
    try {
      final lowerQuery = query.toLowerCase();
      final results = HiveService.tracksBox.values
          .where(
            (t) =>
                t.title.toLowerCase().contains(lowerQuery) ||
                t.artist.toLowerCase().contains(lowerQuery),
          )
          .map(_toDomain)
          .toList();

      return Result.success(results);
    } catch (e) {
      return Result.failure(CacheException('Failed to search tracks: $e'));
    }
  }

  /// Get cached search results
  Future<Result<List<Track>>> getCachedSearchResults(String query) async {
    try {
      final key = _cacheKeyPrefix + query;
      final cached = HiveService.searchCacheBox.get(key) as List<dynamic>?;

      if (cached == null) {
        return Result.success([]);
      }

      final tracks = cached
          .cast<Map<String, dynamic>>()
          .map((json) => Track.fromJson(json))
          .toList();

      return Result.success(tracks);
    } catch (e) {
      return Result.failure(CacheException('Failed to get cached results: $e'));
    }
  }

  /// Cache search results
  Future<Result<void>> cacheSearchResults(
    String query,
    List<Track> results,
  ) async {
    try {
      final key = _cacheKeyPrefix + query;
      final jsonList = results.map((t) => t.toJson()).toList();
      await HiveService.searchCacheBox.put(key, jsonList);
      await _updateMetadata(key, 60); // Search results cached for 1 hour
      return Result.success(null);
    } catch (e) {
      return Result.failure(CacheException('Failed to cache results: $e'));
    }
  }

  /// Get all liked songs from cache
  Future<Result<List<Track>>> getLikedSongs() async {
    try {
      final likedTracks = HiveService.tracksBox.values
          .where((t) => t.isLiked)
          .map(_toDomain)
          .toList();

      return Result.success(likedTracks);
    } catch (e) {
      return Result.failure(CacheException('Failed to get liked songs: $e'));
    }
  }

  /// Get trending tracks from cache
  Future<Result<List<Track>>> getTrendingTracks() async {
    try {
      final cached =
          HiveService.searchCacheBox.get(_trendingCacheKey) as List<dynamic>?;

      if (cached == null) {
        return Result.success([]);
      }

      final tracks = cached
          .cast<Map<String, dynamic>>()
          .map((json) => Track.fromJson(json))
          .toList();

      return Result.success(tracks);
    } catch (e) {
      return Result.failure(
        CacheException('Failed to get trending tracks: $e'),
      );
    }
  }

  /// Cache trending tracks
  Future<Result<void>> cacheTrendingTracks(List<Track> tracks) async {
    try {
      final jsonList = tracks.map((t) => t.toJson()).toList();
      await HiveService.searchCacheBox.put(_trendingCacheKey, jsonList);
      await _updateMetadata(_trendingCacheKey, 120); // 2 hours
      return Result.success(null);
    } catch (e) {
      return Result.failure(
        CacheException('Failed to cache trending tracks: $e'),
      );
    }
  }

  /// Get cache metadata (check expiration)
  Future<Result<CacheMetadataEntity?>> getMetadata(String key) async {
    try {
      final metadata = HiveService.metadataBox.get(key);
      if (metadata != null && metadata.isExpired()) {
        // Delete expired entry
        await HiveService.metadataBox.delete(key);
        return Result.success(null);
      }
      return Result.success(metadata);
    } catch (e) {
      return Result.failure(CacheException('Failed to get metadata: $e'));
    }
  }

  /// Check if cache entry is valid
  Future<Result<bool>> isCacheValid(String key) async {
    try {
      final metadata = HiveService.metadataBox.get(key);
      if (metadata == null) return Result.success(false);
      if (metadata.isExpired()) {
        await HiveService.metadataBox.delete(key);
        return Result.success(false);
      }
      return Result.success(true);
    } catch (e) {
      return Result.failure(CacheException('Failed to check cache: $e'));
    }
  }

  /// Delete a specific track from cache
  Future<Result<void>> deleteTrack(String id) async {
    try {
      await HiveService.tracksBox.delete(id);
      await HiveService.metadataBox.delete(_cacheKeyPrefix + id);
      return Result.success(null);
    } catch (e) {
      return Result.failure(CacheException('Failed to delete track: $e'));
    }
  }

  /// Delete all cached data
  Future<Result<void>> clearAll() async {
    try {
      await HiveService.tracksBox.clear();
      await HiveService.searchCacheBox.clear();
      await HiveService.metadataBox.clear();
      return Result.success(null);
    } catch (e) {
      return Result.failure(CacheException('Failed to clear cache: $e'));
    }
  }

  /// Delete all expired cache entries
  Future<Result<int>> cleanupExpiredEntries() async {
    try {
      int deletedCount = 0;
      final expiredKeys = <String>[];

      for (final entry in HiveService.metadataBox.values) {
        if (entry.isExpired()) {
          expiredKeys.add(entry.key);
        }
      }

      for (final key in expiredKeys) {
        if (key.startsWith(_cacheKeyPrefix)) {
          // Don't delete individual tracks by search key
          await HiveService.searchCacheBox.delete(key);
        }
        await HiveService.metadataBox.delete(key);
        deletedCount++;
      }

      return Result.success(deletedCount);
    } catch (e) {
      return Result.failure(
        CacheException('Failed to cleanup expired entries: $e'),
      );
    }
  }

  /// Get cache statistics
  Future<Result<CacheStats>> getCacheStats() async {
    try {
      final trackCount = HiveService.tracksBox.length;
      final searchCacheCount = HiveService.searchCacheBox.length;
      final metadataCount = HiveService.metadataBox.length;
      final lyricsCount = HiveService.lyricsBox.length;
      final homePageCount = HiveService.homePageBox.length;
      final albumsCount = HiveService.albumsBox.length;
      final artistsCount = HiveService.artistsBox.length;
      final playlistsCount = HiveService.playlistsBox.length;
      final colorsCount = HiveService.colorsBox.length;
      final streamUrlsCount = HiveService.streamCacheBox.length;

      int expiredCount = 0;
      for (final entry in HiveService.metadataBox.values) {
        if (entry.isExpired()) expiredCount++;
      }

      return Result.success(
        CacheStats(
          cachedTracksCount: trackCount,
          cachedSearchesCount: searchCacheCount,
          metadataEntriesCount: metadataCount,
          expiredEntriesCount: expiredCount,
          lyricsCount: lyricsCount,
          homePageCount: homePageCount,
          albumsCount: albumsCount,
          artistsCount: artistsCount,
          playlistsCount: playlistsCount,
          colorsCount: colorsCount,
          streamUrlsCount: streamUrlsCount,
        ),
      );
    } catch (e) {
      return Result.failure(CacheException('Failed to get cache stats: $e'));
    }
  }

  // ============ Private Helper Methods ============

  Future<void> _updateMetadata(String key, int ttlMinutes) async {
    final metadata = CacheMetadataEntity(
      key: key,
      ttlMinutes: ttlMinutes,
      cachedAt: DateTime.now(),
    );
    await HiveService.metadataBox.put(key, metadata);
  }

  TrackEntity _toEntity(Track track) => TrackEntity(
    id: track.id,
    title: track.title,
    artist: track.artist,
    album: track.album,
    duration: track.duration.inMilliseconds,
    thumbnailUrl: track.thumbnailUrl,
    isExplicit: track.isExplicit,
    isLiked: track.isLiked,
    addedAt: track.addedAt,
    localFilePath: track.localFilePath,
    cachedAt: DateTime.now(),
  );

  Track _toDomain(TrackEntity entity) => Track(
    id: entity.id,
    title: entity.title,
    artist: entity.artist,
    album: entity.album,
    duration: Duration(milliseconds: entity.duration),
    thumbnailUrl: entity.thumbnailUrl,
    isExplicit: entity.isExplicit,
    isLiked: entity.isLiked,
    addedAt: entity.addedAt,
    localFilePath: entity.localFilePath,
  );
}

/// Cache statistics
class CacheStats {
  final int cachedTracksCount;
  final int cachedSearchesCount;
  final int metadataEntriesCount;
  final int expiredEntriesCount;
  final int lyricsCount;
  final int homePageCount;
  final int albumsCount;
  final int artistsCount;
  final int playlistsCount;
  final int colorsCount;
  final int streamUrlsCount;

  CacheStats({
    required this.cachedTracksCount,
    required this.cachedSearchesCount,
    required this.metadataEntriesCount,
    required this.expiredEntriesCount,
    this.lyricsCount = 0,
    this.homePageCount = 0,
    this.albumsCount = 0,
    this.artistsCount = 0,
    this.playlistsCount = 0,
    this.colorsCount = 0,
    this.streamUrlsCount = 0,
  });

  /// Total cached item count
  int get totalItemCount =>
      cachedTracksCount +
      cachedSearchesCount +
      homePageCount +
      lyricsCount +
      albumsCount +
      artistsCount +
      playlistsCount +
      colorsCount +
      streamUrlsCount;

  int get validEntriesCount => metadataEntriesCount - expiredEntriesCount;

  @override
  String toString() =>
      'CacheStats(tracks: $cachedTracksCount, searches: $cachedSearchesCount, lyrics: $lyricsCount, albums: $albumsCount, valid: $validEntriesCount, expired: $expiredEntriesCount)';
}

/// Extension for nullable objects
extension Nullable<T> on T? {
  R? let<R>(R Function(T) fn) {
    if (this == null) return null;
    return fn(this as T);
  }
}
