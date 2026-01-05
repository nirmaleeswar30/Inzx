import 'dart:convert';
import 'package:flutter/foundation.dart' show compute, kDebugMode;
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'lyrics_models.dart';

/// Genius provider - High quality plain text lyrics
/// Uses web scraping approach similar to Pear Desktop
class GeniusProvider implements LyricsProvider {
  @override
  String get name => 'Genius';

  static const _baseUrl = 'https://genius.com';

  @override
  Future<LyricResult?> search(LyricsSearchInfo info) async {
    try {
      // Search for song
      final query = Uri.encodeComponent('${info.artist} ${info.title}');
      final searchUri = Uri.parse(
        '$_baseUrl/api/search/song?q=$query&page=1&per_page=10',
      );

      final searchResponse = await http.get(searchUri);
      if (searchResponse.statusCode != 200) return null;

      final searchData = jsonDecode(searchResponse.body);
      final sections = searchData['response']?['sections'] as List?;
      if (sections == null || sections.isEmpty) return null;

      final hits = sections[0]['hits'] as List?;
      if (hits == null || hits.isEmpty) return null;

      // Sort by relevance (title and artist match)
      hits.sort((a, b) {
        final resultA = a['result'] as Map<String, dynamic>;
        final resultB = b['result'] as Map<String, dynamic>;

        int scoreA = 0;
        int scoreB = 0;

        if ((resultA['title'] as String).toLowerCase() ==
            info.title.toLowerCase())
          scoreA++;
        if ((resultB['title'] as String).toLowerCase() ==
            info.title.toLowerCase())
          scoreB++;

        final artistA = resultA['primary_artist']?['name'] as String? ?? '';
        final artistB = resultB['primary_artist']?['name'] as String? ?? '';

        if (artistA.toLowerCase().contains(info.artist.toLowerCase())) scoreA++;
        if (artistB.toLowerCase().contains(info.artist.toLowerCase())) scoreB++;

        return scoreB.compareTo(scoreA);
      });

      final closestHit = hits.first['result'] as Map<String, dynamic>;

      // Skip deleted artists
      final artistUrl = closestHit['primary_artist']?['url'] as String? ?? '';
      if (artistUrl.contains('Deleted-artist')) return null;

      final path = closestHit['path'] as String;

      // Fetch lyrics page
      final lyricsUri = Uri.parse('$_baseUrl$path');
      final lyricsResponse = await http.get(lyricsUri);
      if (lyricsResponse.statusCode != 200) return null;

      // Parse HTML in background isolate to avoid UI jank
      final lyrics = await compute(_extractLyricsIsolate, lyricsResponse.body);
      if (lyrics == null || lyrics.isEmpty) return null;

      // Check for instrumental
      if (lyrics.trim().toLowerCase().replaceAll(RegExp(r'[\[\]]'), '') ==
          'instrumental') {
        return null;
      }

      final primaryArtists = closestHit['primary_artists'] as List?;
      final artistNames =
          primaryArtists?.map((a) => a['name'] as String).toList() ??
          [closestHit['primary_artist']?['name'] as String? ?? info.artist];

      return LyricResult(
        title: closestHit['title'] as String,
        artists: artistNames,
        lyrics: lyrics,
        source: name,
      );
    } catch (e) {
      if (kDebugMode) {print('Genius error: $e');}
      return null;
    }
  }
}

/// Top-level function for compute() - parses Genius HTML to extract lyrics
/// Must be top-level or static to work with compute()
String? _extractLyricsIsolate(String html) {
  try {
    final document = html_parser.parse(html);

    // Find lyrics containers (Genius uses data-lyrics-container attribute)
    final lyricsContainers = document.querySelectorAll(
      '[data-lyrics-container="true"]',
    );

    if (lyricsContainers.isNotEmpty) {
      final lines = <String>[];
      for (final container in lyricsContainers) {
        // Replace <br> with newlines
        final htmlContent = container.innerHtml.replaceAll(
          RegExp(r'<br\s*/?>'),
          '\n',
        );
        final parsed = html_parser.parseFragment(htmlContent);
        lines.add(parsed.text ?? '');
      }
      return lines.join('\n').trim();
    }

    // Fallback: Look for preloaded state with lyrics
    final scripts = document.querySelectorAll('script');
    for (final script in scripts) {
      final content = script.text;
      if (content.contains('__PRELOADED_STATE__')) {
        // Extract lyrics from preloaded state (complex regex parsing)
        final match = RegExp(
          r'body":\{"html":"(.*?)","children"',
        ).firstMatch(content);
        if (match != null) {
          var lyricsHtml = match
              .group(1)!
              .replaceAll(r'\/', '/')
              .replaceAll(r'\\', r'\')
              .replaceAll(r'\n', '\n')
              .replaceAll(r"\'", "'")
              .replaceAll(r'\"', '"');

          final lyricsDoc = html_parser.parseFragment(lyricsHtml);
          return lyricsDoc.text?.trim();
        }
      }
    }

    return null;
  } catch (e) {
    if (kDebugMode) {print('Error extracting Genius lyrics: $e');}
    return null;
  }
}
