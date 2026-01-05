import 'dart:convert';
import 'package:flutter/foundation.dart' show compute, kDebugMode;
import 'package:http/http.dart' as http;
import 'lyrics_models.dart';

/// LRCLib provider - Free synced lyrics database
/// API docs: https://lrclib.net
class LRCLibProvider implements LyricsProvider {
  @override
  String get name => 'LRCLib';

  static const _baseUrl = 'https://lrclib.net';

  @override
  Future<LyricResult?> search(LyricsSearchInfo info) async {
    try {
      // First try exact match
      var result = await _searchExact(info);
      if (result != null) return result;

      // Try fuzzy search
      result = await _searchFuzzy(info);
      return result;
    } catch (e) {
      if (kDebugMode) {print('LRCLib error: $e');}
      return null;
    }
  }

  Future<LyricResult?> _searchExact(LyricsSearchInfo info) async {
    final params = {
      'artist_name': info.artist,
      'track_name': info.title,
      if (info.album != null) 'album_name': info.album!,
    };

    final uri = Uri.parse(
      '$_baseUrl/api/search',
    ).replace(queryParameters: params);
    final response = await http.get(
      uri,
      headers: {'Accept': 'application/json'},
    );

    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as List;
    if (data.isEmpty) return null;

    return await _findBestMatch(data, info);
  }

  Future<LyricResult?> _searchFuzzy(LyricsSearchInfo info) async {
    final query = '${info.artist} ${info.title}';
    final uri = Uri.parse(
      '$_baseUrl/api/search',
    ).replace(queryParameters: {'q': query});

    final response = await http.get(
      uri,
      headers: {'Accept': 'application/json'},
    );

    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as List;
    if (data.isEmpty) return null;

    return await _findBestMatch(data, info);
  }

  Future<LyricResult?> _findBestMatch(
    List results,
    LyricsSearchInfo info,
  ) async {
    // Filter by artist similarity
    final filtered = results.where((item) {
      final artistName = (item['artistName'] as String).toLowerCase();
      final searchArtist = info.artist.toLowerCase();

      // Check if any part of the artist name matches
      final searchParts = searchArtist
          .split(RegExp(r'[&,]'))
          .map((s) => s.trim());
      final itemParts = artistName.split(RegExp(r'[&,]')).map((s) => s.trim());

      return searchParts.any(
        (sp) => itemParts.any((ip) => ip.contains(sp) || sp.contains(ip)),
      );
    }).toList();

    if (filtered.isEmpty) {
      // If no artist match, use all results but sorted by title similarity
      filtered.addAll(results);
    }

    // Sort by duration difference
    filtered.sort((a, b) {
      final diffA = (a['duration'] as num).abs() - info.durationSeconds;
      final diffB = (b['duration'] as num).abs() - info.durationSeconds;
      return diffA.abs().compareTo(diffB.abs());
    });

    final closest = filtered.first;

    // Check duration is close enough (within 15 seconds)
    final durationDiff = ((closest['duration'] as num) - info.durationSeconds)
        .abs();
    if (durationDiff > 15) return null;

    // Skip instrumental
    if (closest['instrumental'] == true) return null;

    final syncedLyrics = closest['syncedLyrics'] as String?;
    final plainLyrics = closest['plainLyrics'] as String?;

    if (syncedLyrics == null && plainLyrics == null) return null;

    // Parse synced lyrics in background isolate to avoid UI jank
    List<LyricLine>? lines;
    if (syncedLyrics != null && syncedLyrics.isNotEmpty) {
      lines = await compute(_parseLrcIsolate, syncedLyrics);
    }

    return LyricResult(
      title: closest['trackName'] as String,
      artists: (closest['artistName'] as String)
          .split(RegExp(r'[&,]'))
          .map((s) => s.trim())
          .toList(),
      lines: lines,
      lyrics: plainLyrics,
      source: name,
    );
  }
}

/// Top-level function for compute() - parses LRC format lyrics
/// Must be top-level to work with compute()
List<LyricLine> _parseLrcIsolate(String lrc) {
  final lines = <LyricLine>[];

  for (final line in lrc.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;

    // Match [mm:ss.xx] or [mm:ss:xx] format
    final match = RegExp(r'\[(\d+):(\d+)[.:](\d+)\](.*)').firstMatch(trimmed);
    if (match == null) continue;

    final minutes = int.parse(match.group(1)!);
    final seconds = int.parse(match.group(2)!);
    var ms = int.parse(match.group(3)!);

    // Handle different precision (2 digits = centiseconds, 3 digits = milliseconds)
    if (ms < 100) ms *= 10;

    final text = match.group(4)!.trim();

    lines.add(
      LyricLine(timeInMs: minutes * 60000 + seconds * 1000 + ms, text: text),
    );
  }

  // Sort by time
  lines.sort((a, b) => a.timeInMs.compareTo(b.timeInMs));

  return lines;
}
