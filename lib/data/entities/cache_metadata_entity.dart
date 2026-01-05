import 'package:hive/hive.dart';

part 'cache_metadata_entity.g.dart';

@HiveType(typeId: 3)
class CacheMetadataEntity extends HiveObject {
  @HiveField(0)
  late String key; // Cache key (e.g., "search:hello", "trending", "liked_songs")

  @HiveField(1)
  late DateTime cachedAt;

  @HiveField(2)
  late int ttlMinutes; // Time to live in minutes (0 = never expire)

  @HiveField(3)
  late String? sourceId; // Optional identifier for invalidation (e.g., user_id)

  CacheMetadataEntity({
    required this.key,
    required this.ttlMinutes,
    this.sourceId,
    DateTime? cachedAt,
  }) : cachedAt = cachedAt ?? DateTime.now();

  /// Check if this cache entry has expired
  bool isExpired() {
    if (ttlMinutes == 0) return false; // Never expires
    final expiresAt = cachedAt.add(Duration(minutes: ttlMinutes));
    return DateTime.now().isAfter(expiresAt);
  }

  /// Get remaining time in minutes (0 if expired)
  int getRemainingMinutes() {
    if (isExpired()) return 0;
    if (ttlMinutes == 0) return 999999; // Effectively infinite
    final expiresAt = cachedAt.add(Duration(minutes: ttlMinutes));
    return expiresAt.difference(DateTime.now()).inMinutes;
  }
}
