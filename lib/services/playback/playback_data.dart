/// OuterTune-style playback data model
/// Separates metadata from playback data for resilience
library;

/// Audio quality preference
/// Note: YT Music max is typically ~256kbps AAC or ~160kbps Opus
/// There is no true lossless - 'max' means highest available
enum AudioQuality {
  auto, // Adapts to network
  low, // ~48-64 kbps (data saver)
  medium, // ~128 kbps
  high, // ~256 kbps (best available)
  max, // Highest available (same as high for YT Music)
}

/// Audio format information
class AudioFormat {
  final String mimeType;
  final int bitrate;
  final int? sampleRate;
  final int? channelCount;
  final String? codecs;
  final int? contentLength;
  final int? averageBitrate;
  final bool isAudioOnly;

  const AudioFormat({
    required this.mimeType,
    required this.bitrate,
    this.sampleRate,
    this.channelCount,
    this.codecs,
    this.contentLength,
    this.averageBitrate,
    this.isAudioOnly = true,
  });

  /// Check if this is an Opus format (preferred)
  bool get isOpus =>
      mimeType.contains('opus') ||
      mimeType.contains('webm') ||
      (codecs != null && codecs!.toLowerCase().contains('opus'));

  /// Check if this is AAC format
  bool get isAac =>
      mimeType.contains('mp4') ||
      mimeType.contains('m4a') ||
      (codecs != null &&
          (codecs!.toLowerCase().contains('mp4a') ||
              codecs!.toLowerCase().contains('aac')));

  /// Clean user-friendly codec name (e.g. "Opus", "AAC", "FLAC", "MP3")
  String get codecName {
    final lowerMime = mimeType.toLowerCase();
    final lowerCodecs = codecs?.toLowerCase() ?? '';
    if (isOpus) return 'Opus';
    if (isAac) return 'AAC';
    if (lowerMime.contains('flac') || lowerCodecs.contains('flac')) return 'FLAC';
    if (lowerMime.contains('mp3') || lowerCodecs.contains('mp3')) return 'MP3';
    if (lowerMime.contains('ogg') || lowerCodecs.contains('vorbis')) {
      return 'Vorbis';
    }
    if (codecs != null && codecs!.isNotEmpty) {
      return codecs!.toUpperCase();
    }
    return mimeType.split('/').last.toUpperCase();
  }

  /// Quality factor for sorting (higher is better)
  int get qualityFactor {
    int factor = bitrate;
    // Prefer Opus over AAC
    if (isOpus) factor += 10240;
    return factor;
  }

  factory AudioFormat.fromJson(Map<String, dynamic> json) {
    return AudioFormat(
      mimeType: json['mimeType'] as String? ?? '',
      bitrate: json['bitrate'] as int? ?? 0,
      sampleRate: json['audioSampleRate'] != null
          ? int.tryParse(json['audioSampleRate'].toString())
          : null,
      channelCount: json['audioChannels'] as int?,
      codecs: _extractCodecs(json['mimeType'] as String? ?? ''),
      contentLength: json['contentLength'] != null
          ? int.tryParse(json['contentLength'].toString())
          : null,
      averageBitrate: json['averageBitrate'] as int?,
      isAudioOnly: (json['width'] == null),
    );
  }

  static String? _extractCodecs(String mimeType) {
    final match = RegExp(r'codecs="([^"]+)"').firstMatch(mimeType);
    return match?.group(1);
  }

  @override
  String toString() => 'AudioFormat($mimeType, ${bitrate}bps, ${sampleRate}Hz)';
}

/// Audio configuration from YouTube
class AudioConfig {
  final double? loudnessDb;
  final double? perceptualLoudnessDb;

  const AudioConfig({this.loudnessDb, this.perceptualLoudnessDb});

  factory AudioConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AudioConfig();
    return AudioConfig(
      loudnessDb: (json['loudnessDb'] as num?)?.toDouble(),
      perceptualLoudnessDb: (json['perceptualLoudnessDb'] as num?)?.toDouble(),
    );
  }
}

/// Video/track details from YouTube
class VideoDetails {
  final String videoId;
  final String title;
  final String author;
  final String? channelId;
  final int lengthSeconds;
  final bool isLive;
  final bool isPrivate;
  final List<String> thumbnails;

  const VideoDetails({
    required this.videoId,
    required this.title,
    required this.author,
    this.channelId,
    required this.lengthSeconds,
    this.isLive = false,
    this.isPrivate = false,
    this.thumbnails = const [],
  });

  Duration get duration => Duration(seconds: lengthSeconds);

  factory VideoDetails.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const VideoDetails(
        videoId: '',
        title: '',
        author: '',
        lengthSeconds: 0,
      );
    }

    // Extract thumbnails
    final thumbList = <String>[];
    final thumbnailData = json['thumbnail']?['thumbnails'] as List?;
    if (thumbnailData != null) {
      for (final t in thumbnailData) {
        final url = t['url'] as String?;
        if (url != null) thumbList.add(url);
      }
    }

    return VideoDetails(
      videoId: json['videoId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      author: json['author'] as String? ?? '',
      channelId: json['channelId'] as String?,
      lengthSeconds:
          int.tryParse(json['lengthSeconds']?.toString() ?? '0') ?? 0,
      isLive: json['isLive'] as bool? ?? false,
      isPrivate: json['isPrivate'] as bool? ?? false,
      thumbnails: thumbList,
    );
  }
}

/// Playback tracking info for YouTube
class PlaybackTracking {
  final String? videostatsPlaybackUrl;
  final String? videostatsWatchtimeUrl;

  /// The ping real clients fire a few seconds in; separates a play that
  /// started from a play that happened.
  final String? atrUrl;
  final int atrAfterSeconds;

  const PlaybackTracking({
    this.videostatsPlaybackUrl,
    this.videostatsWatchtimeUrl,
    this.atrUrl,
    this.atrAfterSeconds = 5,
  });

  bool get hasStatsUrls =>
      (videostatsPlaybackUrl?.isNotEmpty ?? false) ||
      (videostatsWatchtimeUrl?.isNotEmpty ?? false);

  factory PlaybackTracking.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const PlaybackTracking();
    return PlaybackTracking(
      videostatsPlaybackUrl:
          json['videostatsPlaybackUrl']?['baseUrl'] as String?,
      videostatsWatchtimeUrl:
          json['videostatsWatchtimeUrl']?['baseUrl'] as String?,
      atrUrl: json['atrUrl']?['baseUrl'] as String?,
      atrAfterSeconds:
          int.tryParse('${json['atrUrl']?['elapsedMediaTimeSeconds'] ?? ''}') ??
          5,
    );
  }
}

/// Complete playback data - everything ExoPlayer needs
class PlaybackData {
  final AudioConfig? audioConfig;
  final VideoDetails? videoDetails;
  final PlaybackTracking? playbackTracking;
  final AudioFormat format;
  final String streamUrl;
  final int streamExpiresInSeconds;
  final DateTime fetchedAt;
  final String audioSource;

  const PlaybackData({
    this.audioConfig,
    this.videoDetails,
    this.playbackTracking,
    required this.format,
    required this.streamUrl,
    required this.streamExpiresInSeconds,
    required this.fetchedAt,
    this.audioSource = 'YouTube',
  });

  /// Whether this is a live stream (delivered as an HLS/DASH manifest, not a
  /// finite progressive file). Live streams must be handed to the player as a
  /// manifest URL and must never be file-cached (they're endless).
  bool get isLive => videoDetails?.isLive == true;

  /// Whether the stream URL points at an HLS/DASH manifest rather than a plain
  /// progressive media file.
  bool get isManifestStream {
    final mime = format.mimeType.toLowerCase();
    return mime.contains('mpegurl') ||
        mime.contains('x-mpeg') ||
        mime.contains('dash+xml');
  }

  /// Codec display name (e.g. "Opus", "AAC")
  String get codecName => format.codecName;

  /// Bitrate in kbps
  int get bitrateKbps => (format.bitrate / 1000).round();

  /// Formatted stats for nerds summary (e.g. "AAC • 320 kbps • JioSaavn")
  String get statsSummary => '$codecName • $bitrateKbps kbps • $audioSource';

  PlaybackData copyWith({
    AudioConfig? audioConfig,
    VideoDetails? videoDetails,
    PlaybackTracking? playbackTracking,
    AudioFormat? format,
    String? streamUrl,
    int? streamExpiresInSeconds,
    DateTime? fetchedAt,
    String? audioSource,
  }) {
    return PlaybackData(
      audioConfig: audioConfig ?? this.audioConfig,
      videoDetails: videoDetails ?? this.videoDetails,
      playbackTracking: playbackTracking ?? this.playbackTracking,
      format: format ?? this.format,
      streamUrl: streamUrl ?? this.streamUrl,
      streamExpiresInSeconds:
          streamExpiresInSeconds ?? this.streamExpiresInSeconds,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      audioSource: audioSource ?? this.audioSource,
    );
  }

  /// Check if stream URL is still valid
  bool get isValid {
    final expiresAt = fetchedAt.add(Duration(seconds: streamExpiresInSeconds));
    // Give 30 seconds buffer
    return DateTime.now().isBefore(
      expiresAt.subtract(const Duration(seconds: 30)),
    );
  }

  /// Time until expiry
  Duration get timeUntilExpiry {
    final expiresAt = fetchedAt.add(Duration(seconds: streamExpiresInSeconds));
    return expiresAt.difference(DateTime.now());
  }

  @override
  String toString() =>
      'PlaybackData(${format.mimeType}, ${format.bitrate}bps, expires in ${timeUntilExpiry.inMinutes}m)';
}

/// Result of playback resolution
class PlaybackResult {
  final PlaybackData? data;
  final String? error;
  final bool requiresPoToken;

  const PlaybackResult({this.data, this.error, this.requiresPoToken = false});

  bool get isSuccess => data != null && error == null;
  bool get isFailure => error != null;

  factory PlaybackResult.success(PlaybackData data) =>
      PlaybackResult(data: data);
  factory PlaybackResult.failure(String error) => PlaybackResult(error: error);
  factory PlaybackResult.needsPoToken() =>
      const PlaybackResult(requiresPoToken: true);
}
