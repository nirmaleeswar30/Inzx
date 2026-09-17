/// Lyrics data models and provider interface
library;

/// Represents a single word with precise start/end timing for karaoke sync
class LyricWord {
  final String text;
  final int startTimeMs;
  final int endTimeMs;

  const LyricWord({
    required this.text,
    required this.startTimeMs,
    required this.endTimeMs,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'startTimeMs': startTimeMs,
    'endTimeMs': endTimeMs,
  };

  factory LyricWord.fromJson(Map<String, dynamic> json) => LyricWord(
    text: json['text'] as String,
    startTimeMs: json['startTimeMs'] as int,
    endTimeMs: json['endTimeMs'] as int,
  );
}

/// Represents a single line of synced lyrics
class LyricLine {
  final int timeInMs;
  final int? durationMs;
  final int? sungUntilMs;
  final String text;
  final String? translatedText; // AI Translated text (Metrolist style)
  final List<LyricWord>? words; // Word-level timing for karaoke sync
  final bool isBackground; // Background vocal line
  final List<LyricLine> backgroundLines; // Background vocals for this line
  final bool? _isGap;

  const LyricLine({
    required this.timeInMs,
    this.durationMs,
    this.sungUntilMs,
    required this.text,
    this.translatedText,
    this.words,
    this.isBackground = false,
    this.backgroundLines = const [],
    bool? isGap,
  }) : _isGap = isGap;

  static final RegExp _instrumentalPattern = RegExp(
    r'^[\s♪♫♩♬\-–—~•*./\\]+$'
    r'|^\s*[\(\[\{<].*?(?:instrumental|music|solo|interlude|break|drop|intro|outro).*?[\)\]\}>]\s*$'
    r'|^\s*(?:instrumental(?:\s+break|\s+solo|\s+interlude)?|solo(?:\s+section)?|(?:guitar|piano|drum|sax|saxophone|violin|trumpet|bass)\s+solo|interlude|music(?:\s+break)?|beat\s+drop|breakdown|intro|outro)\s*$',
    caseSensitive: false,
  );

  static const Set<String> _knownGapPhrases = {
    'let it breathe',
    'the beat is landing',
    'the song is starting',
    'warming up',
    'setting the mood',
    'bass first, words later',
    'wait for it',
    'feel that build',
    'just the groove for now',
    'the hook is on the way',
    'cue the vocals',
    'first notes in',
    'breathing room',
    'enjoy the groove',
    'instrumental break',
    'solo section',
    'bass & rhythm',
    'feel the beat',
    'just the music',
  };

  /// Whether given text represents an instrumental marker, symbol, or playful gap phrase
  static bool isInstrumentalText(String t) {
    final trimmed = t.trim().toLowerCase();
    if (trimmed.isEmpty) return true;
    if (_knownGapPhrases.contains(trimmed)) return true;
    return _instrumentalPattern.hasMatch(trimmed);
  }

  /// Whether given text is a placeholder musical symbol or bracketed instrumental marker
  /// (which should be replaced by witty gap copy if displayed)
  static bool isMusicalSymbol(String t) {
    final trimmed = t.trim();
    if (trimmed.isEmpty) return true;
    if (_knownGapPhrases.contains(trimmed.toLowerCase())) return false;
    return _instrumentalPattern.hasMatch(trimmed);
  }

  /// Whether this line is an instrumental gap
  bool get isGap =>
      _isGap ?? (text.trim().isEmpty || isInstrumentalText(text));

  /// Whether this line has word-level sync data
  bool get hasWordSync => words != null && words!.isNotEmpty;

  /// Known end time of the vocal/line in milliseconds
  int get endMs =>
      sungUntilMs ??
      (words != null && words!.isNotEmpty
          ? words!.last.endTimeMs
          : (durationMs != null && durationMs! > 0
              ? timeInMs + durationMs!
              : timeInMs));

  /// Whether the line has a known end time
  bool get hasKnownEnd =>
      sungUntilMs != null ||
      (words != null && words!.isNotEmpty) ||
      (durationMs != null && durationMs! > 0);

  LyricLine copyWith({
    int? timeInMs,
    int? durationMs,
    int? sungUntilMs,
    String? text,
    String? translatedText,
    List<LyricWord>? words,
    bool? isBackground,
    List<LyricLine>? backgroundLines,
    bool? isGap,
  }) => LyricLine(
    timeInMs: timeInMs ?? this.timeInMs,
    durationMs: durationMs ?? this.durationMs,
    sungUntilMs: sungUntilMs ?? this.sungUntilMs,
    text: text ?? this.text,
    translatedText: translatedText ?? this.translatedText,
    words: words ?? this.words,
    isBackground: isBackground ?? this.isBackground,
    backgroundLines: backgroundLines ?? this.backgroundLines,
    isGap: isGap ?? _isGap,
  );

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
    if (sungUntilMs != null) 'sungUntilMs': sungUntilMs,
    'text': text,
    if (translatedText != null) 'translatedText': translatedText,
    if (words != null) 'words': words!.map((w) => w.toJson()).toList(),
    'isBackground': isBackground,
    if (backgroundLines.isNotEmpty)
      'backgroundLines': backgroundLines.map((l) => l.toJson()).toList(),
    if (_isGap != null) 'isGap': _isGap,
  };

  factory LyricLine.fromJson(Map<String, dynamic> json) => LyricLine(
    timeInMs: json['timeInMs'] as int,
    durationMs: json['durationMs'] as int?,
    sungUntilMs: json['sungUntilMs'] as int?,
    text: json['text'] as String,
    translatedText: json['translatedText'] as String?,
    words: (json['words'] as List<dynamic>?)
        ?.map((e) => LyricWord.fromJson(e as Map<String, dynamic>))
        .toList(),
    isBackground: json['isBackground'] as bool? ?? false,
    backgroundLines: (json['backgroundLines'] as List<dynamic>?)
        ?.map((e) => LyricLine.fromJson(e as Map<String, dynamic>))
        .toList() ?? const [],
    isGap: json['isGap'] as bool?,
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

  /// Whether any line has word-level sync data (from BetterLyrics)
  bool get hasWordSync => lines?.any((l) => l.hasWordSync) ?? false;
}

/// Search parameters for lyrics
class LyricsSearchInfo {
  final String videoId;
  final String title;
  final String artist;
  final String? album;
  final int durationSeconds;
  final String? localFilePath;

  const LyricsSearchInfo({
    required this.videoId,
    required this.title,
    required this.artist,
    this.album,
    required this.durationSeconds,
    this.localFilePath,
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
