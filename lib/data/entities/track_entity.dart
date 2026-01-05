import 'package:hive/hive.dart';

part 'track_entity.g.dart';

@HiveType(typeId: 1)
class TrackEntity extends HiveObject {
  @HiveField(0)
  late String id;

  @HiveField(1)
  late String title;

  @HiveField(2)
  late String artist;

  @HiveField(3)
  late String? album;

  @HiveField(4)
  late int duration; // milliseconds

  @HiveField(5)
  late String? thumbnailUrl;

  @HiveField(6)
  late bool isExplicit;

  @HiveField(7)
  late bool isLiked;

  @HiveField(8)
  late DateTime? addedAt;

  @HiveField(9)
  late String? localFilePath; // For offline playback

  @HiveField(10)
  late DateTime cachedAt; // When this was cached

  TrackEntity({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    required this.duration,
    this.thumbnailUrl,
    required this.isExplicit,
    required this.isLiked,
    this.addedAt,
    this.localFilePath,
    DateTime? cachedAt,
  }) : cachedAt = cachedAt ?? DateTime.now();
}
