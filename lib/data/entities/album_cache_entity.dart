import 'package:hive/hive.dart';

part 'album_cache_entity.g.dart';

/// Cached album details
@HiveType(typeId: 7)
class AlbumCacheEntity extends HiveObject {
  @HiveField(0)
  final String albumId;

  @HiveField(1)
  final String albumJson; // JSON encoded Album

  @HiveField(2)
  final DateTime cachedAt;

  @HiveField(3)
  final int ttlMinutes;

  AlbumCacheEntity({
    required this.albumId,
    required this.albumJson,
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
