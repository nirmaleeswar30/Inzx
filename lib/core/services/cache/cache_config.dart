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
