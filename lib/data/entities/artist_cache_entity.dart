import 'package:hive/hive.dart';

part 'artist_cache_entity.g.dart';

/// Cached artist details
@HiveType(typeId: 8)
class ArtistCacheEntity extends HiveObject {
  @HiveField(0)
  final String artistId;

  @HiveField(1)
  final String artistJson; // JSON encoded Artist

  @HiveField(2)
  final DateTime cachedAt;

  @HiveField(3)
  final int ttlMinutes;

  ArtistCacheEntity({
    required this.artistId,
    required this.artistJson,
    required this.cachedAt,
    this.ttlMinutes = 60, // 1 hour
  });

  bool get isExpired {
    final expiresAt = cachedAt.add(Duration(minutes: ttlMinutes));
    return DateTime.now().isAfter(expiresAt);
  }

  bool get isStale {
    final staleAt = cachedAt.add(Duration(minutes: ttlMinutes ~/ 2));
    return DateTime.now().isAfter(staleAt);
  }
}
