import 'dart:convert';
import 'package:http/http.dart' as http;
import 'lyrics_models.dart';
import 'lyrics_cleaner.dart';
import 'ttml_parser.dart';

class UnisonProvider implements LyricsProvider {
  @override
  String get name => 'Unison';

  static const _base = 'https://unison.boidu.dev/lyrics';
  static final http.Client _client = http.Client();

  @override
  Future<LyricResult?> search(LyricsSearchInfo info) async {
    try {
      final uri = Uri.parse(_base).replace(queryParameters: {
        'song': LyricsCleaner.cleanTitle(info.title),
        'artist': info.artist,
        if (info.album != null && info.album!.isNotEmpty) 'album': info.album,
        if (info.durationSeconds > 0) 'duration': info.durationSeconds.toString(),
      });

      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body);
      if (json['success'] != true || json['data'] == null) return null;

      final data = json['data'];
      final text = data['lyrics']?.toString();
      if (text == null || text.trim().isEmpty) return null;

      final format = data['format']?.toString().toLowerCase();
      final syncType = data['syncType']?.toString().toLowerCase();

      List<LyricLine>? lines;

      if (format == 'ttml') {
        lines = await TTMLParser.parse(text);
      } else if (syncType == 'plain') {
        lines = text.split('\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .map((e) => LyricLine(timeInMs: 0, text: e))
            .toList();
      } else {
        lines = _parseStandardLrc(text);
      }

      if (lines.isEmpty) return null;

      return LyricResult(
        title: info.title,
        artists: [info.artist],
        lines: lines,
        lyrics: text,
        
        
        source: name,
      );
    } catch (e) {
      return null;
    }
  }
}

  List<LyricLine> _parseStandardLrc(String lrc) {
    final RegExp lineRegex = RegExp(r'^\[(\d{1,3}):(\d{2})[.:](\d{2,3})\](.*)$');
    final lines = <LyricLine>[];
    for (var line in lrc.split('\n')) {
      final match = lineRegex.firstMatch(line.trim());
      if (match != null) {
        final m = int.parse(match.group(1)!);
        final s = int.parse(match.group(2)!);
        final frac = match.group(3)!;
        final fracMs = frac.length == 3 ? int.parse(frac) : int.parse(frac) * 10;
        final timeMs = m * 60000 + s * 1000 + fracMs;
        lines.add(LyricLine(timeInMs: timeMs, text: match.group(4)?.trim() ?? ''));
      }
    }
    return lines;
  }
