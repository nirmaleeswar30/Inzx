import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:http/http.dart' as http;
import 'lyrics_cleaner.dart';
import 'lyrics_models.dart';
import 'background_vocals.dart';
import 'instrumental_gaps.dart';

/// LyricsPlus provider - YouLy+ backend with 6 redundant mirrors & syllable-level timing
class LyricsPlusProvider implements LyricsProvider {
  @override
  String get name => 'LyricsPlus';

  static const List<String> _mirrors = [
    'https://lyricsplus.prjktla.my.id',
    'https://lyricsplus.atomix.one',
    'https://lyricsplus.binimum.org',
    'https://lyricsplus.prjktla.workers.dev',
    'https://lyricsplus-seven.vercel.app',
    'https://lyrics-plus-backend.vercel.app',
  ];

  static String? _lastGoodHost;
  static const _timeout = Duration(seconds: 8);
  static final http.Client _client = http.Client();

  @override
  Future<LyricResult?> search(LyricsSearchInfo info) async {
    final cleanTitle = LyricsCleaner.cleanTitle(info.title);
    final cleanArtist = LyricsCleaner.cleanArtist(info.artist);

    // Prioritize last known working host, followed by rest of mirrors
    final hosts = [
      ?_lastGoodHost,
      ..._mirrors.where((m) => m != _lastGoodHost),
    ];

    final completer = Completer<LyricResult?>();
    int pendingCount = hosts.length;

    for (final host in hosts) {
      _fetchFromHost(host, cleanTitle, cleanArtist, info).then((result) {
        if (!completer.isCompleted) {
          if (result != null && result.hasLyrics) {
            _lastGoodHost = host;
            completer.complete(result);
          } else {
            pendingCount--;
            if (pendingCount <= 0 && !completer.isCompleted) {
              completer.complete(null);
            }
          }
        }
      }).catchError((_) {
        pendingCount--;
        if (pendingCount <= 0 && !completer.isCompleted) {
          completer.complete(null);
        }
      });
    }

    return completer.future;
  }

  Future<LyricResult?> _fetchFromHost(
    String host,
    String title,
    String artist,
    LyricsSearchInfo info,
  ) async {
    final queryParams = {
      'title': title,
      if (artist.isNotEmpty) 'artist': artist,
      if (info.durationSeconds > 0) 'duration': info.durationSeconds.toString(),
      if (info.album != null && info.album!.isNotEmpty) 'album': info.album!,
    };

    final uri = Uri.parse('$host/v2/lyrics/get').replace(queryParameters: queryParams);

    try {
      final res = await _client.get(
        uri,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Accept': 'application/json',
        },
      ).timeout(_timeout);

      if (res.statusCode != 200) return null;

      final json = jsonDecode(res.body);
      if (json is! Map) return null;

      final lyricsList = json['lyrics'] as List?;
      if (lyricsList == null || lyricsList.isEmpty) return null;

      final lines = <LyricLine>[];

      for (final item in lyricsList) {
        if (item is! Map) continue;
        final start = (item['time'] as num?)?.toInt();
        if (start == null) continue;

        final syllabusRaw = item['syllabus'] as List?;
        final words = _mergeSyllables(syllabusRaw);

        if (words.isNotEmpty) {
          lines.add(LyricLine(
            timeInMs: start < words.first.startTimeMs ? start : words.first.startTimeMs,
            text: words.map((w) => w.text).join(' '),
            words: words,
          ));
        } else {
          final text = (item['text'] as String?)?.trim();
          if (text != null && text.isNotEmpty) {
            final dur = (item['duration'] as num?)?.toInt();
            lines.add(LyricLine(
              timeInMs: start,
              text: text,
              sungUntilMs: dur != null && dur > 0 ? start + dur : null,
            ));
          }
        }
      }

      if (lines.isEmpty) return null;

      lines.sort((a, b) => a.timeInMs.compareTo(b.timeInMs));
      final processed = lines.withBackgroundVocals().withInstrumentalGaps();

      if (kDebugMode) {
        print('LyricsPlus: Found ${processed.length} lines from $host for "$title"');
      }

      return LyricResult(
        title: info.title,
        artists: [info.artist],
        lines: processed,
        source: name,
      );
    } catch (_) {
      return null;
    }
  }

  /// Glues syllables back into words using whitespace cues from the API
  static List<LyricWord> _mergeSyllables(List? syllabusList) {
    if (syllabusList == null || syllabusList.isEmpty) return const [];

    final words = <LyricWord>[];
    final currentText = StringBuffer();
    int start = 0;
    int end = 0;

    for (final s in syllabusList) {
      if (s is! Map) continue;
      final text = s['text'] as String?;
      if (text == null || text.trim().isEmpty) continue;
      final time = (s['time'] as num?)?.toInt();
      if (time == null) continue;

      if (currentText.isEmpty) {
        start = time;
      }
      currentText.write(text.trim());
      final dur = (s['duration'] as num?)?.toInt() ?? 0;
      end = time + dur;

      // Trailing whitespace indicates end of a word
      if (text.endsWith(' ') || text.endsWith('\t')) {
        words.add(LyricWord(
          text: currentText.toString(),
          startTimeMs: start,
          endTimeMs: end,
        ));
        currentText.clear();
      }
    }

    if (currentText.isNotEmpty) {
      words.add(LyricWord(
        text: currentText.toString(),
        startTimeMs: start,
        endTimeMs: end,
      ));
    }

    return words;
  }
}
