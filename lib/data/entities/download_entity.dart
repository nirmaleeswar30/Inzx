import 'package:hive/hive.dart';

part 'download_entity.g.dart';

@HiveType(typeId: 4)
class DownloadEntity extends HiveObject {
  @HiveField(0)
  late String trackId;

  @HiveField(1)
  late String title;

  @HiveField(2)
  late String artist;

  @HiveField(3)
  late String? album;

  @HiveField(4)
  late int durationMs; // milliseconds

  @HiveField(5)
  late String? thumbnailUrl;

  @HiveField(6)
  late String localPath;

  @HiveField(7)
  late int totalBytes;

  @HiveField(8)
  late DateTime downloadedAt;

  @HiveField(9)
  late String? quality; // e.g., "high", "medium", "low"

  DownloadEntity({
    required this.trackId,
    required this.title,
    required this.artist,
    this.album,
    required this.durationMs,
    this.thumbnailUrl,
    required this.localPath,
    required this.totalBytes,
    DateTime? downloadedAt,
    this.quality,
  }) : downloadedAt = downloadedAt ?? DateTime.now();
}
