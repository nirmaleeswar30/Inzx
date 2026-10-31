import 'dart:convert';
import 'package:http/http.dart' as http;
import 'lyrics_models.dart';
import 'lyrics_cleaner.dart';
import 'ttml_parser.dart';

/// lrc.red — Apple Music TTML filed by ISRC (syllable-timed where Apple has
/// it). Searched by title + artist, the closest hit by title, artist and
/// length is taken, and its `/s/{ISRC}.ttml` document parsed.
class LrcRedProvider implements LyricsProvider {
  @override
  String get name => 'lrc.red';

  static const _base = 'https://lrc.red/';
  static final http.Client _client = http.Client();

  /// A hit further than this from the track's length is a different edit.
  static const double _maxDurationDiffSeconds = 6;

  @override
  Future<LyricResult?> search(LyricsSearchInfo info) async {
    try {
      final title = LyricsCleaner.cleanTitle(info.title);
      final uri = Uri.parse('${_base}search.json').replace(
        queryParameters: {'q': '$title ${info.artist}'.trim()},
      );
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final hits = (jsonDecode(response.body)['hits'] as List?) ?? const [];
      final best = _bestHit(hits, title, info.artist, info.durationSeconds);
      if (best == null) return null;

      final isrc = best['isrc']?.toString().trim().toUpperCase();
      if (isrc == null || !RegExp(r'^[A-Z]{2}[A-Z0-9]{3}\d{7}$').hasMatch(isrc)) {
        return null;
      }

      final ttmlResponse = await _client
          .get(Uri.parse('${_base}s/$isrc.ttml'))
          .timeout(const Duration(seconds: 10));
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
    } catch (_) {
      return null;
    }
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[\(\[].*?[\)\]]'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9À-ɏЀ-ӿऀ-෿ ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Closest hit: same core title, an overlapping artist, and the length
  /// within [_maxDurationDiffSeconds]; ties go to the nearest length.
  static Map<String, dynamic>? _bestHit(
    List hits,
    String title,
    String artist,
    int durationSeconds,
  ) {
    final wantTitle = _norm(title);
    final wantArtists = _norm(artist).split(' ').where((w) => w.length > 1).toSet();
    Map<String, dynamic>? best;
    var bestScore = double.infinity;

    for (final raw in hits) {
      if (raw is! Map) continue;
      final hit = raw.cast<String, dynamic>();
      final hitTitle = _norm(hit['title']?.toString() ?? '');
      if (hitTitle.isEmpty) continue;
      if (hitTitle != wantTitle &&
          !hitTitle.startsWith(wantTitle) &&
          !wantTitle.startsWith(hitTitle)) {
        continue;
      }
      final hitArtists =
          _norm(hit['artist']?.toString() ?? '').split(' ').toSet();
      if (wantArtists.isNotEmpty && wantArtists.intersection(hitArtists).isEmpty) {
        continue;
      }
      final hitDuration = (hit['duration'] as num?)?.toDouble();
      double diff = 0;
      if (durationSeconds > 0 && hitDuration != null) {
        diff = (hitDuration - durationSeconds).abs();
        if (diff > _maxDurationDiffSeconds) continue;
      }
      // Exact title beats a prefix match; then the nearest length.
      final score = diff + (hitTitle == wantTitle ? 0 : 3);
      if (score < bestScore) {
        bestScore = score;
        best = hit;
      }
    }
    return best;
  }
}
