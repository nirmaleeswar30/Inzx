import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:http/http.dart' as http;
import 'lyrics_cleaner.dart';
import 'lyrics_models.dart';
import 'ttml_parser.dart';
import 'background_vocals.dart';
import 'instrumental_gaps.dart';

/// BetterLyrics provider - High quality synced lyrics with word-level timing
/// API: https://lyrics-api.boidu.dev/qq
/// Ported from Metrolist's BetterLyrics.kt
class BetterLyricsPortatoProvider implements LyricsProvider {
  @override
  String get name => 'BetterLyrics Portato';

  static const _baseUrl = 'https://lyrics-api.boidu.dev/qq';
  static const _requestTimeout = Duration(seconds: 10);
  static final http.Client _client = http.Client();

  @override
  Future<LyricResult?> search(LyricsSearchInfo info) async {
    try {
      // 1. Try exact search first
      var ttml = await _fetchTTML(
        title: info.title,
        artist: info.artist,
        duration: info.durationSeconds,
        album: info.album,
      );

      // 2. If no result, try with cleaned title & cleaned primary artist
      if (ttml == null || ttml.isEmpty) {
        final cleanTitle = LyricsCleaner.cleanTitle(info.title);
        final cleanArtist = LyricsCleaner.cleanArtist(info.artist);

        if (cleanTitle != info.title || cleanArtist != info.artist) {
          ttml = await _fetchTTML(
            title: cleanTitle,
            artist: cleanArtist,
            duration: info.durationSeconds,
          );
        }
      }

      // 3. If still no result, try cleaned title & artist WITHOUT duration filter
      // (Handles duration variations between single, audio, and video cuts)
      if (ttml == null || ttml.isEmpty) {
        final cleanTitle = LyricsCleaner.cleanTitle(info.title);
        final cleanArtist = LyricsCleaner.cleanArtist(info.artist);

        ttml = await _fetchTTML(
          title: cleanTitle,
          artist: cleanArtist,
          duration: 0,
        );
      }

      // 4. If still no result, try with cleaned title only
      if (ttml == null || ttml.isEmpty) {
        final cleanTitle = LyricsCleaner.cleanTitle(info.title);
        if (cleanTitle.isNotEmpty) {
          ttml = await _fetchTTML(
            title: cleanTitle,
            artist: '',
            duration: 0,
          );
        }
      }

      if (ttml == null || ttml.isEmpty) {
        if (kDebugMode) {
          print('BetterLyrics: No TTML returned for "${info.title}"');
        }
        return null;
      }

      // Parse TTML into LyricLines with word-level timing
      final lines = await TTMLParser.parse(ttml);

      if (lines.isEmpty) {
        if (kDebugMode) {
          print(
            'BetterLyrics: TTML parsing returned no lines for "${info.title}"',
          );
        }
        return null;
      }

      final processed = lines.withBackgroundVocals().withInstrumentalGaps();

      if (kDebugMode) {
        final wordCount = processed.fold<int>(
          0,
          (sum, line) => sum + (line.words?.length ?? 0),
        );
        print(
          'BetterLyrics: Parsed ${processed.length} lines, $wordCount words for "${info.title}"',
        );
      }

      return LyricResult(
        title: info.title,
        artists: [info.artist],
        lines: processed,
        source: name,
      );
    } catch (e) {
      if (kDebugMode) {
        print('BetterLyrics error: $e');
      }
      return null;
    }
  }

  /// Fetch TTML XML string from the BetterLyrics API
  Future<String?> _fetchTTML({
    required String title,
    required String artist,
    required int duration,
    String? album,
  }) async {
    final params = <String, String>{
      's': title,
    };

    if (artist.isNotEmpty) {
      params['a'] = artist;
    }
    if (duration > 0) {
      params['d'] = duration.toString();
    }
    if (album != null && album.isNotEmpty) {
      params['al'] = album;
    }

    final uri = Uri.parse(
      '$_baseUrl/getLyrics',
    ).replace(queryParameters: params);

    if (kDebugMode) {
      print('BetterLyrics: Fetching TTML for "$title" by "$artist"');
    }

    final response = await _client
        .get(
          uri,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Accept': 'application/json',
          },
        )
        .timeout(_requestTimeout);

    if (response.statusCode != 200) {
      if (kDebugMode) {
        print('BetterLyrics: API returned status ${response.statusCode}');
      }
      return null;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final ttml = data['ttml'] as String?;
    return ttml?.trim().isNotEmpty == true ? ttml!.trim() : null;
  }
}
