import 'package:hive/hive.dart';

part 'color_cache_entity.g.dart';

/// Cached dominant colors for album art
/// Stores all AlbumColors fields as int values
@HiveType(typeId: 10)
class ColorCacheEntity extends HiveObject {
  @HiveField(0)
  final String imageUrl;

  @HiveField(1)
  final int accent;

  @HiveField(2)
  final int accentLight;

  @HiveField(3)
  final int accentDark;

  @HiveField(4)
  final int backgroundPrimary;

  @HiveField(5)
  final int backgroundSecondary;

  @HiveField(6)
  final int surface;

  @HiveField(7)
  final int onBackground;

  @HiveField(8)
  final int onSurface;

  @HiveField(9)
  final DateTime cachedAt;

  ColorCacheEntity({
    required this.imageUrl,
    required this.accent,
    required this.accentLight,
    required this.accentDark,
    required this.backgroundPrimary,
    required this.backgroundSecondary,
    required this.surface,
    required this.onBackground,
    required this.onSurface,
    required this.cachedAt,
  });

  // Colors are permanent - no expiration
}
