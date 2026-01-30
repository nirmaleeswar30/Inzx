/// Global cache limits to prevent unbounded growth
class CacheLimits {
  CacheLimits._();

  /// Maximum total cache size in bytes (2GB)
  static const int maxCacheSizeBytes = 2 * 1024 * 1024 * 1024;

  /// Maximum age for cache entries in days
  static const int maxAgeDays = 90;

  /// Per-box entry limits (LRU eviction when exceeded)
  static const int maxTracksEntries = 5000;
  static const int maxAlbumsEntries = 500;
  static const int maxArtistsEntries = 500;
  static const int maxPlaylistsEntries = 200;
  static const int maxLyricsEntries = 1000;
  static const int maxStreamCacheEntries =
      100; // Stream URLs expire quickly anyway
  static const int maxColorsEntries = 500;
  static const int maxSearchCacheEntries = 100;
  static const int maxHomePageEntries = 10;
}

/// Eviction policy for cache management
enum EvictionPolicy {
  /// Least Recently Used - evicts oldest entries first
  lru,

  /// Time-based - evicts expired entries only
  ttl,
}

/// Cache policy options for different data fetching strategies
enum CachePolicy {
  /// Always try network first, fall back to cache if network fails
  networkFirst,

  /// Always use cache if available, never hit network
  cacheOnly,

  /// Use cache if valid, otherwise fetch from network
  cacheFirst,

  /// Network request with cache fallback (default)
  networkWithFallback,
}

/// Configuration for cache behavior
class CacheConfig {
  final CachePolicy policy;
  final int ttlMinutes;
  final bool forceRefresh;

  CacheConfig({
    this.policy = CachePolicy.networkWithFallback,
    this.ttlMinutes = 30,
    this.forceRefresh = false,
  });

  /// Create a network-first config
  factory CacheConfig.networkFirst({int ttlMinutes = 30}) =>
      CacheConfig(policy: CachePolicy.networkFirst, ttlMinutes: ttlMinutes);

  /// Create a cache-first config
  factory CacheConfig.cacheFirst({int ttlMinutes = 60}) =>
      CacheConfig(policy: CachePolicy.cacheFirst, ttlMinutes: ttlMinutes);

  /// Create a cache-only config
  factory CacheConfig.cacheOnly() =>
      CacheConfig(policy: CachePolicy.cacheOnly, ttlMinutes: 999999);

  /// Create a fresh config (force network)
  factory CacheConfig.fresh({int ttlMinutes = 30}) => CacheConfig(
    policy: CachePolicy.networkWithFallback,
    ttlMinutes: ttlMinutes,
    forceRefresh: true,
  );

  /// Create default network with fallback config
  factory CacheConfig.networkWithFallback({int ttlMinutes = 30}) => CacheConfig(
    policy: CachePolicy.networkWithFallback,
    ttlMinutes: ttlMinutes,
  );
}
