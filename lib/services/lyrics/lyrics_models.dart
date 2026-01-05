/// Lyrics data models and provider interface

/// Represents a single line of synced lyrics
class LyricLine {
  final int timeInMs;
  final int? durationMs;
  final String text;

  const LyricLine({
    required this.timeInMs,
    this.durationMs,
    required this.text,
  });

  /// Format time as mm:ss.ms
  String get formattedTime {
    final minutes = (timeInMs ~/ 60000);
    final seconds = ((timeInMs % 60000) ~/ 1000);
    final ms = ((timeInMs % 1000) ~/ 10);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${ms.toString().padLeft(2, '0')}';
  }

  factory LyricLine.fromLrc(String line) {
    // Parse LRC format: [mm:ss.ms]text
    final match = RegExp(r'\[(\d+):(\d+)\.(\d+)\](.*)').firstMatch(line);
    if (match == null) return LyricLine(timeInMs: 0, text: line);

    final minutes = int.parse(match.group(1)!);
    final seconds = int.parse(match.group(2)!);
    final ms = int.parse(match.group(3)!) * 10;
    final text = match.group(4)!.trim();

    return LyricLine(
      timeInMs: minutes * 60000 + seconds * 1000 + ms,
      text: text,
    );
  }

  Map<String, dynamic> toJson() => {
    'timeInMs': timeInMs,
    'durationMs': durationMs,
    'text': text,
  };

  factory LyricLine.fromJson(Map<String, dynamic> json) => LyricLine(
    timeInMs: json['timeInMs'] as int,
    durationMs: json['durationMs'] as int?,
    text: json['text'] as String,
  );
}

/// Result from a lyrics provider
class LyricResult {
  final String title;
  final List<String> artists;
  final List<LyricLine>? lines; // Synced lyrics
  final String? lyrics; // Plain text lyrics
  final String source; // Provider name

  const LyricResult({
    required this.title,
    required this.artists,
    this.lines,
    this.lyrics,
    required this.source,
  });

  bool get hasSyncedLyrics => lines != null && lines!.isNotEmpty;
  bool get hasPlainLyrics => lyrics != null && lyrics!.isNotEmpty;
  bool get hasLyrics => hasSyncedLyrics || hasPlainLyrics;
}

/// Search parameters for lyrics
class LyricsSearchInfo {
  final String videoId;
  final String title;
  final String artist;
  final String? album;
  final int durationSeconds;

  const LyricsSearchInfo({
    required this.videoId,
    required this.title,
    required this.artist,
    this.album,
    required this.durationSeconds,
  });
}

/// Provider state during fetching
enum LyricsProviderState { idle, fetching, done, error }

class ProviderStatus {
  final LyricsProviderState state;
  final LyricResult? data;
  final String? error;

  const ProviderStatus({
    this.state = LyricsProviderState.idle,
    this.data,
    this.error,
  });

  ProviderStatus copyWith({
    LyricsProviderState? state,
    LyricResult? data,
    String? error,
  }) => ProviderStatus(
    state: state ?? this.state,
    data: data ?? this.data,
    error: error ?? this.error,
  );
}

/// Abstract lyrics provider interface
abstract class LyricsProvider {
  String get name;
  Future<LyricResult?> search(LyricsSearchInfo info);
}
