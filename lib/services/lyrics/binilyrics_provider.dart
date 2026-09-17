import 'dart:convert';
import 'package:http/http.dart' as http;
import 'lyrics_models.dart';
import 'lyrics_cleaner.dart';
import 'ttml_parser.dart';

class BiniLyricsProvider implements LyricsProvider {
  @override
  String get name => 'BiniLyrics';

  static const _base = 'https://lyrics-api.binimum.org/';
  static final http.Client _client = http.Client();

  @override
  Future<LyricResult?> search(LyricsSearchInfo info) async {
    try {
      final uri = Uri.parse(_base).replace(queryParameters: {
        'track': LyricsCleaner.cleanTitle(info.title),
        'artist': info.artist,
        if (info.album != null && info.album!.isNotEmpty) 'album': info.album,
        if (info.durationSeconds > 0) 'duration': info.durationSeconds.toString(),
      });

      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body);
      final results = json['results'] as List?;
      if (results == null || results.isEmpty) return null;

      final hit = results.first;
      final lyricsUrl = hit['lyricsUrl']?.toString();
      if (lyricsUrl == null || lyricsUrl.isEmpty) return null;

      final ttmlResponse = await _client.get(Uri.parse(lyricsUrl)).timeout(const Duration(seconds: 10));
      if (ttmlResponse.statusCode != 200) return null;

      final ttml = ttmlResponse.body;
      final lines = await TTMLParser.parse(ttml);
      
      if (lines.isEmpty) return null;

      return LyricResult(
        title: info.title,
        artists: [info.artist],
        lines: lines,
        lyrics: ttml,
        
        
        source: name,
      );
    } catch (e) {
      return null;
    }
  }
}
