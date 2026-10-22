import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/desede_engine.dart';
import 'package:pointycastle/block/modes/ecb.dart';
import 'package:pointycastle/padded_block_cipher/padded_block_cipher_impl.dart';
import 'package:pointycastle/paddings/pkcs7.dart';

import '../../models/models.dart';
import 'track_matcher.dart';

/// Decoded stream information from JioSaavn
class JioSaavnStream {
  final String url;
  final int? kbps;
  final String format;

  const JioSaavnStream({
    required this.url,
    this.kbps,
    this.format = 'mp4',
  });

  String get streamUrl => url;
  int get bitrateKbps => kbps ?? 320;

  @override
  String toString() => 'JioSaavnStream(${kbps ?? '?'}kbps, $format, $url)';
}

/// Raw parsed song item from JioSaavn API
class JioSaavnSong implements TrackMatcherCandidate {
  final String id;
  @override
  final String title;
  @override
  final String artist;
  @override
  final String? album;
  final int durationSeconds;
  final String encryptedMediaUrl;
  final bool supports320;
  @override
  final bool isExplicit;
  final String? image;

  @override
  int? get durationSec => durationSeconds > 0 ? durationSeconds : null;

  const JioSaavnSong({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    required this.durationSeconds,
    required this.encryptedMediaUrl,
    required this.supports320,
    required this.isExplicit,
    this.image,
  });

  factory JioSaavnSong.fromJson(Map<String, dynamic> json) {
    final moreInfo = json['more_info'] as Map<String, dynamic>? ?? {};
    
    // Extract primary artists
    String artistName = '';
    final artistMap = moreInfo['artistMap'] as Map<String, dynamic>?;
    if (artistMap != null) {
      final primary = artistMap['primary_artists'] as List<dynamic>?;
      if (primary != null && primary.isNotEmpty) {
        artistName = primary
            .map((a) => (a as Map<String, dynamic>)['name']?.toString() ?? '')
            .where((n) => n.isNotEmpty)
            .join(', ');
      }
    }
    if (artistName.isEmpty) {
      artistName = moreInfo['singers']?.toString() ??
          moreInfo['music']?.toString() ??
          '';
    }

    final has320 = moreInfo['320kbps']?.toString().toLowerCase() == 'true';
    final explicit = json['explicit_content']?.toString() == '1' ||
        json['explicit_content']?.toString().toLowerCase() == 'true';

    final durationSec = int.tryParse(moreInfo['duration']?.toString() ?? '0') ?? 0;
    final albumName = moreInfo['album']?.toString();

    return JioSaavnSong(
      id: json['id']?.toString() ?? '',
      title: _decodeHtmlEntities(json['title']?.toString() ?? ''),
      artist: _decodeHtmlEntities(artistName),
      album: albumName != null ? _decodeHtmlEntities(albumName) : null,
      durationSeconds: durationSec,
      encryptedMediaUrl: moreInfo['encrypted_media_url']?.toString() ?? '',
      supports320: has320,
      isExplicit: explicit,
      image: json['image']?.toString(),
    );
  }

  static String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&#039;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
  }
}

/// Service to interact with JioSaavn API for 320kbps audio streams
class JioSaavnService {
  static final JioSaavnService _instance = JioSaavnService._internal();
  factory JioSaavnService() => _instance;
  static JioSaavnService get instance => _instance;

  JioSaavnService._internal();

  static const String _baseUrl = 'https://www.jiosaavn.com/api.php';
  static const String _desKey = '383465913834659138346591'; // 24-byte key for 3DES

  /// In-memory cache for resolved stream URLs by track ID
  final Map<String, JioSaavnStream> _streamCache = {};
  /// Track IDs where no matching JioSaavn stream was found
  final Set<String> _noMatchTrackIds = {};

  final http.Client _client = http.Client();

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
        'X-Forwarded-For': '49.36.0.1',
        'X-Real-IP': '49.36.0.1',
        'Accept-Language': 'en-IN,en;q=0.9',
        'Cookie': 'explicit_content=1',
      };

  /// Decrypts the media URL using DES/ECB/PKCS7
  String decryptUrl(String encryptedUrl) {
    if (encryptedUrl.trim().isEmpty) return '';
    try {
      final keyBytes = utf8.encode(_desKey);
      final cipher = PaddedBlockCipherImpl(
        PKCS7Padding(),
        ECBBlockCipher(DESedeEngine()),
      );
      final params = PaddedBlockCipherParameters(
        KeyParameter(Uint8List.fromList(keyBytes)),
        null,
      );
      cipher.init(false, params);
      final cipherText = base64.decode(encryptedUrl.trim());
      final decryptedBytes = cipher.process(Uint8List.fromList(cipherText));
      return utf8.decode(decryptedBytes).trim();
    } catch (e) {
      if (kDebugMode) {
        print('JioSaavnService: URL decryption failed: $e');
      }
      return '';
    }
  }

  /// Extracts the best available CDN stream URL with conditional 320kbps upgrade
  JioSaavnStream? bestStream(String encryptedUrl, bool supports320) {
    final decrypted = decryptUrl(encryptedUrl);
    if (decrypted.isEmpty) return null;

    final suffixRegex = RegExp(r'_(48|96|160|320)\.(mp4|aac|mp3)$');
    final match = suffixRegex.firstMatch(decrypted);

    if (match == null) {
      return JioSaavnStream(
        url: decrypted,
        kbps: supports320 ? 320 : null,
      );
    }

    final offered = int.tryParse(match.group(1) ?? '');
    final ext = match.group(2) ?? 'mp4';

    if (supports320) {
      final upgradedUrl = decrypted.replaceRange(
        match.start,
        match.end,
        '_320.$ext',
      );
      return JioSaavnStream(
        url: upgradedUrl,
        kbps: 320,
        format: ext,
      );
    } else {
      return JioSaavnStream(
        url: decrypted,
        kbps: offered,
        format: ext,
      );
    }
  }

  /// Search JioSaavn catalogue for songs matching [query]
  Future<List<JioSaavnSong>> searchSongs(String query, {int limit = 10}) async {
    if (query.trim().isEmpty) return [];

    try {
      final uri = Uri.parse(_baseUrl).replace(queryParameters: {
        '__call': 'search.getResults',
        '_format': 'json',
        '_marker': '0',
        'api_version': '4',
        'ctx': 'android',
        'q': query.trim(),
        'p': '1',
        'n': limit.toString(),
      });

      final response = await _client.get(uri, headers: _headers).timeout(
            const Duration(seconds: 5),
          );

      if (response.statusCode != 200) {
        return [];
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return [];

      final results = decoded['results'] as List<dynamic>? ?? [];
      final songs = results
          .map((item) => JioSaavnSong.fromJson(item as Map<String, dynamic>))
          .toList();

      // Prioritize explicit tracks ahead of clean edits
      songs.sort((a, b) {
        if (a.isExplicit && !b.isExplicit) return -1;
        if (!a.isExplicit && b.isExplicit) return 1;
        return 0;
      });

      return songs;
    } catch (e) {
      if (kDebugMode) {
        print('JioSaavnService: search error: $e');
      }
      return [];
    }
  }

  /// The lowest rendition worth taking over YouTube (160kbps Opus).
  /// Streams <= 96kbps are a downgrade and are rejected.
  static const int minUsableKbps = 96;

  static String? _sanitizeAlbum(String? album) {
    if (album == null) return null;
    final trimmed = album.trim();
    if (trimmed.isEmpty) return null;
    if (RegExp(r'^\d+(\.\d+)?[kmb]?\s+(views|plays|view|play)$', caseSensitive: false).hasMatch(trimmed)) {
      return null;
    }
    if (RegExp(r'^\d+:\d{2}(:\d{2})?$').hasMatch(trimmed)) {
      return null;
    }
    if (RegExp(r'^(song|video|track|audio|single)$', caseSensitive: false).hasMatch(trimmed)) {
      return null;
    }
    return trimmed;
  }

  /// Cleans packaging and suffixes from track title
  static String cleanTitle(String title) => TrackMatcher.searchableTitle(title);

  /// Extract primary artist name
  static String primaryArtist(String artist) => TrackMatcher.primaryArtist(artist);

  /// Match a target track with candidate songs from JioSaavn using TrackMatcher
  JioSaavnSong? matchTrack(Track target, List<JioSaavnSong> candidates) {
    if (candidates.isEmpty) return null;
    final targetModel = TrackMatcherTarget(
      title: target.title,
      artist: target.artist,
      durationSec: target.duration.inSeconds > 0 ? target.duration.inSeconds : null,
      album: _sanitizeAlbum(target.album),
      isExplicit: target.isExplicit ? true : null,
    );

    var matches = TrackMatcher.ranked(candidates, targetModel);
    if (matches.isEmpty) return null;

    if (TrackMatcher.hasConflictingAlbums(matches, targetModel)) {
      final canonical = TrackMatcher.uniquelyMostCreditedCloseMatch(matches, targetModel);
      if (canonical == null) return null;
      matches = [canonical];
    }

    return matches.firstOrNull;
  }

  /// Get the best stream for [track] from JioSaavn, using cache when available.
  /// Follows the strict TrackMatcher query & validation pipeline.
  Future<JioSaavnStream?> getBestStreamForTrack(Track track) async {
    // 1. Check in-memory stream cache
    if (_streamCache.containsKey(track.id)) {
      return _streamCache[track.id];
    }
    if (_noMatchTrackIds.contains(track.id)) {
      return null;
    }

    try {
      final target = TrackMatcherTarget(
        title: track.title,
        artist: track.artist,
        durationSec: track.duration.inSeconds > 0 ? track.duration.inSeconds : null,
        album: _sanitizeAlbum(track.album),
        isExplicit: track.isExplicit ? true : null,
      );

      final queries = TrackMatcher.queries(target);
      if (queries.isEmpty) {
        if (target.durationSec != null) {
          _noMatchTrackIds.add(track.id);
        }
        return null;
      }

      for (final query in queries) {
        final candidates = await searchSongs(query, limit: 10);
        if (candidates.isEmpty) continue;

        var matches = TrackMatcher.ranked(candidates, target);
        if (matches.isEmpty) continue;

        // JioSaavn can return different audio under the same title and
        // artist on different releases. With no album on the requested
        // track there is no honest way to choose between those rows;
        // duration is not enough when the wrong recording is only a
        // second away. Treat it as this source missing and retain the
        // known-correct fallback.
        if (TrackMatcher.hasConflictingAlbums(matches, target)) {
          final canonical = TrackMatcher.uniquelyMostCreditedCloseMatch(matches, target);
          if (canonical == null) {
            // Check if all close matches share the exact same primary artist, title core,
            // and tight duration (within durationTightSec = 3s). If so, these are simply
            // multiple releases (e.g. single vs album) of the identical recording, so
            // picking the top ranked match is safe.
            final close = target.durationSec != null
                ? matches.where((c) => TrackMatcher.withinSeconds(c, target, TrackMatcher.durationTightSec)).toList()
                : <JioSaavnSong>[];
            final firstClose = close.firstOrNull;
            final isSafeSameRecording = close.length >= 2 &&
                firstClose != null &&
                close.every((c) =>
                    TrackMatcher.primaryArtist(c.artist) == TrackMatcher.primaryArtist(firstClose.artist) &&
                    TrackMatcher.parseTitle(c.title).core == TrackMatcher.parseTitle(firstClose.title).core);

            if (isSafeSameRecording) {
              if (kDebugMode) {
                print(
                  'JioSaavnService: multiple releases share identical recording & artist for "${target.title}"; using top match: "${firstClose.album}"',
                );
              }
              matches = [firstClose];
            } else {
              if (kDebugMode) {
                print('JioSaavnService: conflicting albums for "${target.title}"; refusing to guess');
              }
              continue;
            }
          } else {
            if (kDebugMode) {
              print(
                'JioSaavnService: resolved conflicting albums for "${target.title}" using fullest credit: "${canonical.artist}"',
              );
            }
            matches = [canonical];
          }
        }

        final bestMatch = matches.firstOrNull;
        if (bestMatch == null || bestMatch.encryptedMediaUrl.isEmpty) {
          continue;
        }

        final stream = bestStream(bestMatch.encryptedMediaUrl, bestMatch.supports320);
        if (stream == null || stream.url.isEmpty) {
          continue;
        }

        // MIN_USABLE_KBPS check:
        // A rendition <= 96kbps is worse than YouTube's ~160kbps Opus stream.
        if (stream.kbps != null && stream.kbps! <= minUsableKbps) {
          if (kDebugMode) {
            print(
              'JioSaavnService: JioSaavn only offered ${stream.kbps}kbps for ${bestMatch.id}; not worth playing',
            );
          }
          continue;
        }

        _streamCache[track.id] = stream;
        if (kDebugMode) {
          print(
            'JioSaavnService: Matched "${track.title}" -> "${bestMatch.title}" (${stream.kbps}kbps)',
          );
        }
        return stream;
      }

      if (target.durationSec != null) {
        _noMatchTrackIds.add(track.id);
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('JioSaavnService: getBestStreamForTrack error: $e');
      }
      return null;
    }
  }

  /// Returns a cached stream for [trackId] if already resolved, without making network requests
  JioSaavnStream? getCachedStream(String trackId) => _streamCache[trackId];

  /// Clear all cached streams
  void clearCache() {
    _streamCache.clear();
    _noMatchTrackIds.clear();
  }
}
