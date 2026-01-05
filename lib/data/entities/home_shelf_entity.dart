import 'package:hive/hive.dart';

part 'home_shelf_entity.g.dart';

/// Cached home page content
@HiveType(typeId: 6)
class HomePageCacheEntity extends HiveObject {
  @HiveField(0)
  final String shelvesJson; // JSON encoded list of shelves

  @HiveField(1)
  final String? continuationToken;

  @HiveField(2)
  final DateTime cachedAt;

  @HiveField(3)
  final int ttlMinutes;

  HomePageCacheEntity({
    required this.shelvesJson,
    this.continuationToken,
    required this.cachedAt,
    this.ttlMinutes = 30,
  });

  bool get isExpired {
    final expiresAt = cachedAt.add(Duration(minutes: ttlMinutes));
    return DateTime.now().isAfter(expiresAt);
  }

  /// Check if cache is stale but still usable (for stale-while-revalidate)
  bool get isStale {
    // Consider stale after half the TTL
    final staleAt = cachedAt.add(Duration(minutes: ttlMinutes ~/ 2));
    return DateTime.now().isAfter(staleAt);
  }
}
