import 'package:equatable/equatable.dart';

/// Represents a music track
class Track extends Equatable {
  final String id;
  final String title;
  final String artist;
  final String artistId;
  final String? album;
  final String? albumId;
  final Duration duration;
  final String? thumbnailUrl;
  final String? highResThumbnailUrl;
  final bool isExplicit;
  final bool isLiked;
  final DateTime? addedAt;
  final String? setVideoId; // Used for playlist operations
  final String? localFilePath; // For offline playback

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    this.artistId = '',
    this.album,
    this.albumId,
    required this.duration,
    this.thumbnailUrl,
    this.highResThumbnailUrl,
    this.isExplicit = false,
    this.isLiked = false,
    this.addedAt,
    this.setVideoId,
    this.localFilePath,
  });

  /// Create from YouTube Music data
  factory Track.fromYouTube({
    required String videoId,
    required String title,
    required String artist,
    String? artistId,
    String? album,
    String? albumId,
    required Duration duration,
    String? thumbnailUrl,
  }) {
    // Get highest quality thumbnail
    String? highRes;
    if (thumbnailUrl != null) {
      // YouTube thumbnail URL patterns
      highRes = 'https://img.youtube.com/vi/$videoId/maxresdefault.jpg';
    }

    return Track(
      id: videoId,
      title: title,
      artist: artist,
      artistId: artistId ?? '',
      album: album,
      albumId: albumId,
      duration: duration,
      thumbnailUrl:
          thumbnailUrl ?? 'https://img.youtube.com/vi/$videoId/mqdefault.jpg',
      highResThumbnailUrl: highRes,
    );
  }

  /// Copy with modifications
  Track copyWith({
    String? id,
    String? title,
    String? artist,
    String? artistId,
    String? album,
    String? albumId,
    Duration? duration,
    String? thumbnailUrl,
    String? highResThumbnailUrl,
    bool? isExplicit,
    bool? isLiked,
    DateTime? addedAt,
    String? setVideoId,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      artistId: artistId ?? this.artistId,
      album: album ?? this.album,
      albumId: albumId ?? this.albumId,
      duration: duration ?? this.duration,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      highResThumbnailUrl: highResThumbnailUrl ?? this.highResThumbnailUrl,
      isExplicit: isExplicit ?? this.isExplicit,
      isLiked: isLiked ?? this.isLiked,
      addedAt: addedAt ?? this.addedAt,
      setVideoId: setVideoId ?? this.setVideoId,
    );
  }

  /// Get the best available thumbnail
  String? get bestThumbnail => highResThumbnailUrl ?? thumbnailUrl;

  /// Format duration as mm:ss or h:mm:ss
  String get formattedDuration {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  List<Object?> get props => [id];

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'artistId': artistId,
      'album': album,
      'albumId': albumId,
      'duration': duration.inMilliseconds,
      'thumbnailUrl': thumbnailUrl,
      'highResThumbnailUrl': highResThumbnailUrl,
      'isExplicit': isExplicit,
      'isLiked': isLiked,
      'addedAt': addedAt?.millisecondsSinceEpoch,
      'setVideoId': setVideoId,
      'localFilePath': localFilePath,
    };
  }

  /// Create from JSON
  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String,
      artistId: json['artistId'] as String? ?? '',
      album: json['album'] as String?,
      albumId: json['albumId'] as String?,
      duration: Duration(milliseconds: json['duration'] as int),
      thumbnailUrl: json['thumbnailUrl'] as String?,
      highResThumbnailUrl: json['highResThumbnailUrl'] as String?,
      isExplicit: json['isExplicit'] as bool? ?? false,
      isLiked: json['isLiked'] as bool? ?? false,
      addedAt: json['addedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['addedAt'] as int)
          : null,
      setVideoId: json['setVideoId'] as String?,
      localFilePath: json['localFilePath'] as String?,
    );
  }
}
