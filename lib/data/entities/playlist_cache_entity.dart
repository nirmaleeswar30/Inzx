import 'package:hive/hive.dart';

part 'playlist_cache_entity.g.dart';

/// Cached playlist details
@HiveType(typeId: 9)
class PlaylistCacheEntity extends HiveObject {
  @HiveField(0)
  final String playlistId;

  @HiveField(1)
  final String playlistJson; // JSON encoded Playlist

  @HiveField(2)
  final DateTime cachedAt;

  @HiveField(3)
  final int ttlMinutes;

  PlaylistCacheEntity({
    required this.playlistId,
    required this.playlistJson,
    required this.cachedAt,
    this.ttlMinutes = 30, // 30 minutes
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
