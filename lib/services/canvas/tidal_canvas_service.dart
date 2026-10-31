import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'canvas_artwork.dart';

/// Tidal's "video cover" — a high-resolution (1280x1280) square looping clip
/// that albums and singles ship instead of a still sleeve.
///
/// Fetched via Tidal's public embed search endpoint which requires no account
/// credentials.
class TidalCanvasService {
  static const String _searchUrl = 'https://api.tidal.com/v1/search';
  static const String _embedToken = 'vNVdglQOjFJJGG2U';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  static final http.Client _client = http.Client();

  /// Search Tidal for a track and its album videoCover.
  static Future<CanvasArtwork?> search(
    String title,
    String artist, [
    String? album,
  ]) async {
    // 1. Try clean artist + title search first (best for singles & variant album releases)
    var result = await _executeTrackSearch(
      '$artist $title',
      title,
      artist,
      album,
    );
    if (result != null) return result;

    // 2. If artist contains multiple artists or features, try primary artist + title
    final primaryArtist = artist.split(RegExp(r'[,&]')).first.trim();
    if (primaryArtist.isNotEmpty &&
        primaryArtist.toLowerCase() != artist.toLowerCase()) {
      result = await _executeTrackSearch(
        '$primaryArtist $title',
        title,
        artist,
        album,
      );
      if (result != null) return result;
    }

    // 3. If no hit and album is known, try album + primary artist + title
    if (album != null && album.trim().isNotEmpty) {
      result = await _executeTrackSearch(
        '$album $primaryArtist $title',
        title,
        artist,
        album,
      );
      if (result != null) return result;
    }

    return null;
  }

  static Future<CanvasArtwork?> _executeTrackSearch(
    String query,
    String wantTitle,
    String wantArtist,
    String? wantAlbum,
  ) async {
    try {
      final uri = Uri.parse(_searchUrl).replace(
        queryParameters: {
          'query': query,
          'limit': '10',
          'types': 'TRACKS',
          'countryCode': CanvasArtwork.storefront.toUpperCase(),
        },
      );

      final response = await _client
          .get(
            uri,
            headers: {'X-Tidal-Token': _embedToken, 'User-Agent': _userAgent},
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tracks = data['tracks'] as Map<String, dynamic>?;
      final items = tracks?['items'] as List<dynamic>?;
      if (items == null || items.isEmpty) return null;

      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        final trackTitle = item['title'] as String?;
        if (trackTitle == null) continue;

        final artistsList = item['artists'] as List<dynamic>?;
        final artistNames =
            artistsList
                ?.whereType<Map<String, dynamic>>()
                .map((a) => a['name'] as String? ?? '')
                .where((name) => name.isNotEmpty)
                .toList() ??
            [];

        final albumObj = item['album'] as Map<String, dynamic>?;
        final videoCover = albumObj?['videoCover'] as String?;
        if (videoCover == null || videoCover.trim().isEmpty) continue;

        final videoUrl = _coverUrl(videoCover.trim());
        if (videoUrl == null) continue;

        final candidate = CanvasArtwork(
          url: videoUrl,
          title: trackTitle,
          artist: artistNames.join(', '),
          album: albumObj?['title'] as String?,
          source: CanvasSource.tidal,
        );

        if (candidate.matches(wantTitle, wantArtist, wantAlbum)) {
          debugPrint(
            'TidalCanvas: Found video cover for "$trackTitle" by ${artistNames.join(', ')}',
          );
          return candidate;
        }
      }
    } catch (e) {
      debugPrint('TidalCanvas: Search failed: $e');
    }
    return null;
  }

  /// Search Tidal for an album's video cover.
  static Future<CanvasArtwork?> searchAlbum(String album, String artist) async {
    try {
      final uri = Uri.parse(_searchUrl).replace(
        queryParameters: {
          'query': '$album $artist',
          'limit': '10',
          'types': 'ALBUMS',
          'countryCode': CanvasArtwork.storefront.toUpperCase(),
        },
      );

      final response = await _client
          .get(
            uri,
            headers: {'X-Tidal-Token': _embedToken, 'User-Agent': _userAgent},
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final albums = data['albums'] as Map<String, dynamic>?;
      final items = albums?['items'] as List<dynamic>?;
      if (items == null || items.isEmpty) return null;

      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        final recordTitle = item['title'] as String?;
        if (recordTitle == null) continue;

        final artistsList = item['artists'] as List<dynamic>?;
        final artistNames =
            artistsList
                ?.whereType<Map<String, dynamic>>()
                .map((a) => a['name'] as String? ?? '')
                .where((name) => name.isNotEmpty)
                .toList() ??
            [];

        final videoCover = item['videoCover'] as String?;
        if (videoCover == null || videoCover.trim().isEmpty) continue;

        final videoUrl = _coverUrl(videoCover.trim());
        if (videoUrl == null) continue;

        final candidate = CanvasArtwork(
          url: videoUrl,
          title: recordTitle,
          artist: artistNames.join(', '),
          album: recordTitle,
          source: CanvasSource.tidal,
        );

        if (candidate.matches(album, artist, album)) {
          debugPrint(
            'TidalCanvas: Found album video cover for "$recordTitle" by ${artistNames.join(', ')}',
          );
          return candidate;
        }
      }
    } catch (e) {
      debugPrint('TidalCanvas: Album search failed: $e');
    }
    return null;
  }

  /// A videoCover ID is five dash-separated segments (UUID) that spell out its CDN path:
  /// https://resources.tidal.com/videos/{p1}/{p2}/{p3}/{p4}/{p5}/1280x1280.mp4
  static String? _coverUrl(String id) {
    final parts = id.split('-');
    if (parts.length != 5) return null;
    return 'https://resources.tidal.com/videos/${parts.join('/')}/1280x1280.mp4';
  }
}
