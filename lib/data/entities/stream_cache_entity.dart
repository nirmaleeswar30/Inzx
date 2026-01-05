import 'package:hive/hive.dart';

part 'stream_cache_entity.g.dart';

/// Cached stream URL data for playback
/// Stream URLs typically expire in 6 hours
@HiveType(typeId: 11)
class StreamCacheEntity extends HiveObject {
  @HiveField(0)
  final String videoId;

  @HiveField(1)
  final String streamUrl;

  @HiveField(2)
  final int expiresInSeconds;

  @HiveField(3)
  final DateTime fetchedAt;

  @HiveField(4)
  final String mimeType;

  @HiveField(5)
  final int bitrate;

  @HiveField(6)
  final int? contentLength;

  @HiveField(7)
  final String? codec;

  StreamCacheEntity({
    required this.videoId,
    required this.streamUrl,
    required this.expiresInSeconds,
    required this.fetchedAt,
    required this.mimeType,
    required this.bitrate,
    this.contentLength,
    this.codec,
  });

  /// Check if stream URL is still valid (with 30s buffer)
  bool get isValid {
    final expiresAt = fetchedAt.add(Duration(seconds: expiresInSeconds));
    return DateTime.now().isBefore(
      expiresAt.subtract(const Duration(seconds: 30)),
    );
  }

  /// Check if expired
  bool get isExpired => !isValid;

  /// Time until expiry
  Duration get timeUntilExpiry {
    final expiresAt = fetchedAt.add(Duration(seconds: expiresInSeconds));
    return expiresAt.difference(DateTime.now());
  }
}
