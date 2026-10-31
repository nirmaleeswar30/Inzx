import 'dart:collection';
import 'package:flutter/foundation.dart';
import '../../models/models.dart';
import 'canvas_artwork.dart';
import 'tidal_canvas_service.dart';
import 'community_canvas_service.dart';
import 'apple_music_canvas_service.dart';

class _CacheEntry {
  final CanvasArtwork? artwork;
  final bool withAlbum;
  final DateTime timestamp;

  _CacheEntry({
    required this.artwork,
    required this.withAlbum,
    required this.timestamp,
  });

  bool reusable(bool hasAlbumNow) {
    // If we have a hit, it's always reusable.
    if (artwork != null) return true;
    // If it was a miss with album, it's final.
    if (withAlbum) return true;
    // If it was a miss without album, and we still don't have album, it's reusable.
    return !hasAlbumNow;
  }
}

/// Central repository orchestrating motion artwork (Canvas) resolution across
/// Tidal, Community, and Apple Music providers.
///
/// Features:
/// - Priority: Apple Music (largest catalogue) -> Tidal (square covers on much
///   of what Apple misses) -> Community Canvas (the only one reaching back
///   catalogue). Each is asked only if the ones before found nothing.
/// - Every answer is re-checked against the request; a mismatch counts as
///   nothing found and the next source is asked.
/// - Lookups run one at a time, so skipping through a queue doesn't put
///   three providers' requests per track on the wire at once, and a track
///   resolved while waiting is answered from the cache.
/// - In-flight query deduplication.
/// - LRU memory cache with negative-caching to eliminate redundant queries for songs without canvas.
/// - Intelligent title noise scrubbing (removes YouTube packaging such as "| Official Video").
class CanvasRepository {
  CanvasRepository._();
  static final CanvasRepository instance = CanvasRepository._();

  static const int _maxCacheSize = 128;
  final LinkedHashMap<String, _CacheEntry> _cache = LinkedHashMap();
  final Map<String, Future<CanvasArtwork?>> _inFlight = {};

  /// Tail of the lookup queue; each lookup waits for the one before it.
  Future<void> _queue = Future<void>.value();

  Future<CanvasArtwork?> _serially(Future<CanvasArtwork?> Function() task) {
    final run = _queue.then((_) => task());
    _queue = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// Get the animated canvas for a [track], or null if none exists.
  Future<CanvasArtwork?> canvasFor(Track track) async {
    final title = cleanTitle(track.title);
    final artist = cleanArtist(track.artist);
    if (title.isEmpty || artist.isEmpty) return null;

    final album = track.album?.trim();
    final hasAlbum = album != null && album.isNotEmpty;
    final key = 'track|${track.id}';

    // Check synchronous cache
    final cached = _cache[key];
    if (cached != null && cached.reusable(hasAlbum)) {
      return cached.artwork;
    }

    // Deduplicate in-flight fetches
    if (_inFlight.containsKey(key)) {
      return _inFlight[key];
    }

    final future = _resolve(title, artist, album, hasAlbum);
    _inFlight[key] = future;

    try {
      final result = await future;
      _putCache(
        key,
        _CacheEntry(
          artwork: result,
          withAlbum: hasAlbum,
          timestamp: DateTime.now(),
        ),
      );
      return result;
    } finally {
      _inFlight.remove(key);
    }
  }

  /// Get the animated canvas for an [album] and [artist].
  Future<CanvasArtwork?> canvasForAlbum(String album, String artist) async {
    final cleanAlbumName = cleanTitle(album);
    final cleanArtistName = cleanArtist(artist);
    if (cleanAlbumName.isEmpty || cleanArtistName.isEmpty) return null;

    final key = 'album|$cleanAlbumName|$cleanArtistName';
    final cached = _cache[key];
    if (cached != null) return cached.artwork;

    if (_inFlight.containsKey(key)) {
      return _inFlight[key];
    }

    final future = _resolveAlbum(cleanAlbumName, cleanArtistName);
    _inFlight[key] = future;

    try {
      final result = await future;
      _putCache(
        key,
        _CacheEntry(
          artwork: result,
          withAlbum: true,
          timestamp: DateTime.now(),
        ),
      );
      return result;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<CanvasArtwork?> _resolve(
    String title,
    String artist,
    String? album,
    bool hasAlbum,
  ) {
    return _firstHit([
      (
        'Apple Music',
        () => AppleMusicCanvasService.search(title, artist, album),
      ),
      ('Tidal', () => TidalCanvasService.search(title, artist, album)),
      ('Community', () => CommunityCanvasService.search(title, artist, album)),
    ], (found) => found.matches(title, artist, album));
  }

  Future<CanvasArtwork?> _resolveAlbum(String album, String artist) {
    return _firstHit([
      ('Apple Music', () => AppleMusicCanvasService.searchAlbum(album, artist)),
      ('Tidal', () => TidalCanvasService.searchAlbum(album, artist)),
      ('Community', () => CommunityCanvasService.searchAlbum(album, artist)),
    ], (found) => found.matches(album, artist, album));
  }

  /// The first source whose answer survives [accept]. Sources run lazily,
  /// in order, so later ones are only paid for when earlier ones come up
  /// empty; one that throws counts as one that found nothing.
  Future<CanvasArtwork?> _firstHit(
    List<(String, Future<CanvasArtwork?> Function())> sources,
    bool Function(CanvasArtwork) accept,
  ) {
    return _serially(() async {
      for (final (name, source) in sources) {
        CanvasArtwork? found;
        try {
          found = await source();
        } catch (e) {
          debugPrint('CanvasRepository: $name error: $e');
        }
        if (found == null) continue;
        if (!accept(found)) {
          debugPrint(
            'CanvasRepository: $name answered "${found.title}" by '
            '"${found.artist}", not a match',
          );
          continue;
        }
        return found;
      }
      return null;
    });
  }

  void _putCache(String key, _CacheEntry entry) {
    _cache.remove(key);
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = entry;
  }

  /// Remove YouTube video title packaging, bracketed noise, and labels
  /// that catalogue services never see.
  static String cleanTitle(String input) {
    var s = input
        .split(' | ')
        .first
        .replaceAll(
          RegExp(
            r'\((?:from|official|lyrical|video|audio|lyrics|music video|full song|visualizer|remastered|deluxe|explicit)[^)]*\)',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'\[(?:from|official|lyrical|video|audio|lyrics|music video|full song|visualizer|remastered|deluxe|explicit|hd|4k)[^\]]*\]',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'\b(?:official (?:video|audio|music video|lyric video)|lyrical|full song|4k video|hd video)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // If formatted as "Artist - Title", extract the title
    if (s.contains(' - ')) {
      final parts = s.split(' - ');
      if (parts.length == 2 && parts[1].trim().isNotEmpty) {
        s = parts[1].trim();
      }
    }

    return s.isEmpty ? input.trim() : s;
  }

  static String cleanArtist(String input) {
    var s = input
        .replaceAll(RegExp(r'\s*-\s*Topic', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*VEVO', caseSensitive: false), '')
        .replaceAll(
          RegExp(r'\s*Official\s*(?:Channel)?', caseSensitive: false),
          '',
        )
        .trim();
    return s.isEmpty ? input.trim() : s;
  }

  static String cleanNoise(String input) => cleanTitle(input);
}
