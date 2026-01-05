import 'package:hive/hive.dart';

part 'lyrics_entity.g.dart';

/// Cached lyrics entry
@HiveType(typeId: 5)
class LyricsEntity extends HiveObject {
  @HiveField(0)
  final String trackId;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String artist;

  @HiveField(3)
  final String? syncedLyrics; // LRC format

  @HiveField(4)
  final String? plainLyrics;

  @HiveField(5)
  final String provider; // lrclib, genius, etc.

  @HiveField(6)
  final DateTime cachedAt;

  @HiveField(7)
  final int ttlDays;

  LyricsEntity({
    required this.trackId,
    required this.title,
    required this.artist,
    this.syncedLyrics,
    this.plainLyrics,
    required this.provider,
    required this.cachedAt,
    this.ttlDays = 7,
  });

  bool get isExpired {
    final expiresAt = cachedAt.add(Duration(days: ttlDays));
    return DateTime.now().isAfter(expiresAt);
  }

  bool get hasLyrics => syncedLyrics != null || plainLyrics != null;
  bool get hasSyncedLyrics => syncedLyrics != null && syncedLyrics!.isNotEmpty;
  bool get hasPlainLyrics => plainLyrics != null && plainLyrics!.isNotEmpty;
}
