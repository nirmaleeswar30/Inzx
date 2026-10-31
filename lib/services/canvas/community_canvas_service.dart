import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'canvas_artwork.dart';

class _CommunityEntry {
  final String song;
  final String artist;
  final String album;
  final String url;

  _CommunityEntry({
    required this.song,
    required this.artist,
    required this.album,
    required this.url,
  });
}

/// Community-curated index of song and artist to looping video URLs.
/// Covers back-catalogue classics and popular tracks.
class CommunityCanvasService {
  static const String _manifestUrl =
      'https://vivimusicanvas.mkmdevilmi.workers.dev/canvas.json';
  static const Duration _ttl = Duration(minutes: 30);

  static List<_CommunityEntry> _entries = [];
  static DateTime? _fetchedAt;
  static bool _isLoading = false;

  static final http.Client _client = http.Client();

  /// Search community index for a matching track.
  static Future<CanvasArtwork?> search(
    String title,
    String artist, [
    String? album,
  ]) async {
    try {
      final entries = await _getManifest();
      if (entries.isEmpty) return null;

      final wantTitle = CanvasArtwork.normalizeForMatch(title);
      final wantArtist = CanvasArtwork.normalizeForMatch(artist);
      final wantAlbum = album != null
          ? CanvasArtwork.normalizeForMatch(album)
          : null;

      for (final entry in entries) {
        final song = CanvasArtwork.normalizeForMatch(entry.song);
        final credited = CanvasArtwork.normalizeForMatch(entry.artist);
        final listedAlbum = CanvasArtwork.normalizeForMatch(entry.album);

        final titleOk =
            song.isNotEmpty &&
            (wantTitle.contains(song) ||
                song.contains(wantTitle) ||
                wantTitle == song);

        final artistOk =
            credited.isNotEmpty &&
            (wantArtist.contains(credited) ||
                credited.contains(wantArtist) ||
                wantArtist == credited);

        final albumOk =
            listedAlbum.isEmpty ||
            wantAlbum == null ||
            wantAlbum.isEmpty ||
            listedAlbum == wantAlbum;

        if (titleOk && artistOk && albumOk) {
          debugPrint(
            'CommunityCanvas: Manifest hit for "${entry.song}" by "${entry.artist}"',
          );
          return CanvasArtwork(
            url: entry.url,
            title: entry.song,
            artist: entry.artist,
            album: entry.album.isNotEmpty ? entry.album : null,
            source: CanvasSource.community,
          );
        }
      }
    } catch (e) {
      debugPrint('CommunityCanvas: Search error: $e');
    }
    return null;
  }

  /// Search community index for an album.
  static Future<CanvasArtwork?> searchAlbum(String album, String artist) async {
    try {
      final entries = await _getManifest();
      if (entries.isEmpty) return null;

      final wantAlbum = CanvasArtwork.normalizeForMatch(album);
      final wantArtist = CanvasArtwork.normalizeForMatch(artist);
      if (wantAlbum.isEmpty) return null;

      for (final entry in entries) {
        final listedAlbum = CanvasArtwork.normalizeForMatch(entry.album);
        final credited = CanvasArtwork.normalizeForMatch(entry.artist);

        if (listedAlbum == wantAlbum &&
            credited.isNotEmpty &&
            (wantArtist.contains(credited) || credited.contains(wantArtist))) {
          debugPrint(
            'CommunityCanvas: Album hit for "${entry.album}" by "${entry.artist}"',
          );
          return CanvasArtwork(
            url: entry.url,
            title: entry.album,
            artist: entry.artist,
            album: entry.album,
            source: CanvasSource.community,
          );
        }
      }
    } catch (e) {
      debugPrint('CommunityCanvas: Album search error: $e');
    }
    return null;
  }

  static Future<List<_CommunityEntry>> _getManifest() async {
    final now = DateTime.now();
    if (_entries.isNotEmpty &&
        _fetchedAt != null &&
        now.difference(_fetchedAt!) < _ttl) {
      return _entries;
    }

    if (_isLoading) return _entries;
    _isLoading = true;

    try {
      final response = await _client
          .get(
            Uri.parse(_manifestUrl),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = (data is Map ? data['items'] : data) as List<dynamic>?;
        if (items != null) {
          final parsed = <_CommunityEntry>[];
          for (final item in items) {
            if (item is! Map<String, dynamic>) continue;
            final song = item['song'] as String?;
            final artist = item['artist'] as String?;
            final url = item['url'] as String?;
            if (song == null || artist == null || url == null) continue;

            parsed.add(
              _CommunityEntry(
                song: song,
                artist: artist,
                album: item['album'] as String? ?? '',
                url: url,
              ),
            );
          }
          if (parsed.isNotEmpty) {
            _entries = parsed;
            _fetchedAt = now;
            debugPrint(
              'CommunityCanvas: Loaded ${_entries.length} canvas entries',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('CommunityCanvas: Failed to fetch manifest: $e');
    } finally {
      _isLoading = false;
    }

    return _entries;
  }
}
