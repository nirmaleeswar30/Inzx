import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import '../models/models.dart';
import '../core/services/cache/hive_service.dart';
import 'safe_audio_metadata_reader.dart';
import 'tagger/media_tagger.dart';
import 'tagger/webm_tagger.dart';
import 'ytmusic_api_service.dart';
import 'jiosaavn/jiosaavn_service.dart';

/// Resolved track metadata from online providers (iTunes, YouTube Music, JioSaavn).
class OnlineTrackMetadata {
  final String? artworkUrl;
  final String? artist;
  final String? title;
  final String? album;

  const OnlineTrackMetadata({
    this.artworkUrl,
    this.artist,
    this.title,
    this.album,
  });

  bool get hasArtist =>
      artist != null && !LocalArtworkService.isArtistMissing(artist);
  bool get hasArtwork =>
      artworkUrl != null && artworkUrl!.trim().isNotEmpty;
}

/// Service for extracting and caching embedded album art from local audio files,
/// with online search fallback (iTunes, YouTube Music, JioSaavn) when metadata is missing.
class LocalArtworkService {
  static final Map<String, Uint8List> _memoryCache = <String, Uint8List>{};
  static final Map<String, Future<Uint8List?>> _inFlight = <String, Future<Uint8List?>>{};

  /// When a lookup last came up empty, per file. Misses are retried after
  /// [_notFoundRetryAfter]: most of them just mean there was no connection
  /// at the time, and that shouldn't last until the app restarts.
  static final Map<String, DateTime> _notFoundCache = <String, DateTime>{};
  static const Duration _notFoundRetryAfter = Duration(minutes: 5);

  static Directory? _cacheDir;
  static InnerTubeService? _innerTubeService;

  static final StreamController<Track> _trackEnrichedController =
      StreamController<Track>.broadcast();

  /// Stream of local tracks that have been enriched with online metadata (artist/album/art).
  static Stream<Track> get onTrackEnriched => _trackEnrichedController.stream;

  static const Set<String> _placeholderArtists = {
    'unknown artist',
    '<unknown>',
    'unknown',
    'unknown song',
    'various artists',
    'various',
    'artiest onbekend',
    'unbekannter künstler',
    'artiste inconnu',
    'artista desconocido',
    'artista sconosciuto',
    'artistas vários',
    'track',
    'audio',
    'music',
    'song',
    '',
  };

  /// Check whether an artist string is missing or a placeholder.
  static bool isArtistMissing(String? artist) {
    if (artist == null) return true;
    final trimmed = artist.trim().toLowerCase();
    return _placeholderArtists.contains(trimmed);
  }

  static bool _isRecentMiss(String key) {
    final at = _notFoundCache[key];
    if (at == null) return false;
    if (DateTime.now().difference(at) < _notFoundRetryAfter) return true;
    _notFoundCache.remove(key);
    return false;
  }

  /// Fast synchronous check for cached image bytes in memory.
  static Uint8List? getCachedBytes(String localFilePath) {
    return _memoryCache[localFilePath.trim()];
  }

  /// Fast synchronous check for cached artwork file on disk.
  static File? getCachedFile(String localFilePath) {
    final trimmed = localFilePath.trim();
    if (trimmed.isEmpty) return null;
    if (_cacheDir != null) {
      try {
        final file = File('${_cacheDir!.path}/${trimmed.hashCode}.jpg');
        if (file.existsSync() && file.lengthSync() > 0) {
          if (_fileStartsLikeImage(file)) return file;
          // Saved by a build that could mistake audio for artwork.
          file.deleteSync();
        }
      } catch (_) {}
    }
    // Also check companion .cover.jpg if present
    try {
      final companion = File('$trimmed.cover.jpg');
      if (companion.existsSync() && companion.lengthSync() > 0) {
        return companion;
      }
    } catch (_) {}
    return null;
  }

  static bool _fileStartsLikeImage(File file) {
    final raf = file.openSync();
    try {
      return MediaTagger.isImageBytes(raf.readSync(12));
    } finally {
      raf.closeSync();
    }
  }

  static const int _maxMemoryCacheEntries = 60;

  static void _setMemoryCache(String localFilePath, Uint8List bytes) {
    final trimmed = localFilePath.trim();
    if (trimmed.isEmpty || bytes.isEmpty) return;
    if (_memoryCache.length >= _maxMemoryCacheEntries && !_memoryCache.containsKey(trimmed)) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
    _memoryCache[trimmed] = bytes;
  }

  /// Manually populate memory cache (e.g., right after downloading or in tests).
  static void setMemoryCache(String localFilePath, Uint8List bytes) {
    _setMemoryCache(localFilePath, bytes);
  }

  /// Evict cached artwork for a deleted or rescanned file from memory, inflight, and disk.
  static void evict(String localFilePath) {
    final trimmed = localFilePath.trim();
    if (trimmed.isEmpty) return;
    _memoryCache.remove(trimmed);
    _notFoundCache.remove(trimmed);
    _inFlight.remove(trimmed);
    try {
      if (_cacheDir != null) {
        final cacheFile = File('${_cacheDir!.path}/${trimmed.hashCode}.jpg');
        if (cacheFile.existsSync()) {
          cacheFile.deleteSync();
        }
      }
    } catch (_) {}
  }

  /// Get the persistent artwork cache directory.
  static Future<Directory> _getCacheDirectory() async {
    if (_cacheDir != null) return _cacheDir!;
    try {
      final tempDir = await getTemporaryDirectory();
      final artDir = Directory('${tempDir.path}/embedded_art');
      if (!await artDir.exists()) {
        await artDir.create(recursive: true);
      }
      _cacheDir = artDir;
      return artDir;
    } catch (_) {
      final sysTemp = Directory.systemTemp;
      final artDir = Directory('${sysTemp.path}/inzx_art');
      if (!await artDir.exists()) {
        await artDir.create(recursive: true);
      }
      _cacheDir = artDir;
      return artDir;
    }
  }

  /// Resolve embedded or online cover art bytes for a local audio file.
  static Future<Uint8List?> getArtworkBytes(
    String localFilePath, {
    Track? track,
  }) async {
    final trimmedPath = localFilePath.trim();
    if (trimmedPath.isEmpty) return null;

    // 1. In-memory cache hit
    final memoryHit = _memoryCache[trimmedPath];
    if (memoryHit != null && memoryHit.isNotEmpty) {
      return memoryHit;
    }

    // Deduplicate concurrent in-flight requests for the same track
    final activeFuture = _inFlight[trimmedPath];
    if (activeFuture != null) {
      return activeFuture;
    }

    final future = _getArtworkBytesInternal(trimmedPath, track: track);
    _inFlight[trimmedPath] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(trimmedPath);
    }
  }

  static Future<Uint8List?> _getArtworkBytesInternal(
    String trimmedPath, {
    Track? track,
  }) async {
    // 2. Persistent disk cache check
    try {
      final cacheDir = await _getCacheDirectory();
      final cacheFile = File('${cacheDir.path}/${trimmedPath.hashCode}.jpg');
      if (await cacheFile.exists() && await cacheFile.length() > 0) {
        final bytes = await cacheFile.readAsBytes();
        if (MediaTagger.isImageBytes(bytes)) {
          _setMemoryCache(trimmedPath, bytes);
          return bytes;
        }
        // Saved by a build that could mistake audio for artwork.
        await cacheFile.delete();
      }
    } catch (_) {}

    // 3. Legacy companion .cover.jpg check (if present from older downloads)
    try {
      final legacyCover = File('$trimmedPath.cover.jpg');
      if (await legacyCover.exists() && await legacyCover.length() > 0) {
        final bytes = await legacyCover.readAsBytes();
        if (MediaTagger.isImageBytes(bytes)) {
          _setMemoryCache(trimmedPath, bytes);
          _saveToDiskCache(trimmedPath, bytes);
          return bytes;
        }
      }
    } catch (_) {}

    // Nothing in the file last time and nothing online: don't reread the
    // whole file on every rebuild while waiting to try again.
    if (track != null && _isRecentMiss(trimmedPath)) return null;

    final audioFile = File(trimmedPath);
    final fileExists = await audioFile.exists();

    // 4. In-file extraction (if file exists on disk)
    Uint8List? extracted;
    if (fileExists) {
      final lower = trimmedPath.toLowerCase();

      // M4A / MP4 direct box parse
      if (lower.endsWith('.m4a') || lower.endsWith('.mp4')) {
        try {
          final fileBytes = await audioFile.readAsBytes();
          extracted = _extractMp4Cover(fileBytes);
        } catch (e) {
          if (kDebugMode) {
            print('LocalArtworkService: MP4 direct extract error: $e');
          }
        }
      }

      // WebM / Opus Matroska attachments
      if (extracted == null && (lower.endsWith('.opus') || lower.endsWith('.webm'))) {
        try {
          final fileBytes = await audioFile.readAsBytes();
          extracted = WebmTagger.readEmbedded(fileBytes).cover;
        } catch (e) {
          if (kDebugMode) {
            print('LocalArtworkService: WebM direct extract error: $e');
          }
        }
      }

      // Fast, leak-proof safe reader (FLAC, MP3, M4A)
      if (extracted == null && !lower.endsWith('.webm') && !lower.endsWith('.opus')) {
        try {
          final safeMeta = SafeAudioMetadataReader.readMetadata(audioFile, extractPicture: true);
          if (safeMeta.pictureBytes != null && safeMeta.pictureBytes!.isNotEmpty) {
            extracted = safeMeta.pictureBytes;
          }
        } catch (_) {}

        // Fallback to audio_metadata_reader for OGG / WAV / rare tags
        if (extracted == null) {
          try {
            final meta = readMetadata(audioFile, getImage: true);
            if (meta.pictures.isNotEmpty) {
              final picBytes = meta.pictures.first.bytes;
              if (picBytes.isNotEmpty) {
                extracted = picBytes;
              }
            }
          } catch (e) {
            if (kDebugMode) {
              print('LocalArtworkService: audio_metadata_reader fallback error: $e');
            }
          }
        }
      }
    }

    if (extracted != null && MediaTagger.isImageBytes(extracted)) {
      _setMemoryCache(trimmedPath, extracted);
      _saveToDiskCache(trimmedPath, extracted);

      // Even if embedded artwork is present, if artist is missing, enrich online in background
      if (track != null && isArtistMissing(track.artist)) {
        unawaited(fetchOnlineMetadata(track));
      }

      return extracted;
    }

    // 5. Online lookup fallback if track info is available
    if (track != null) {
      // If track already has a valid remote thumbnail URL, try downloading directly
      for (final url in artworkUrlCandidates(track)) {
        final downloaded = await _downloadArtworkBytes(url);
        if (downloaded != null && downloaded.isNotEmpty) {
          _setMemoryCache(trimmedPath, downloaded);
          _saveToDiskCache(trimmedPath, downloaded);
          if (isArtistMissing(track.artist)) {
            unawaited(fetchOnlineMetadata(track));
          }
          return downloaded;
        }
      }

      // Search online using sanitized title and artist
      final cleanQuery = sanitizeTrackQuery(track.title, track.artist);
      if (cleanQuery.isNotEmpty) {
        final onlineMeta = await _lookupOnlineMetadata(cleanQuery);
        if (onlineMeta != null) {
          Uint8List? downloaded;
          if (onlineMeta.hasArtwork) {
            downloaded = await _downloadArtworkBytes(onlineMeta.artworkUrl!);
            if (downloaded != null && downloaded.isNotEmpty) {
              _setMemoryCache(trimmedPath, downloaded);
              _saveToDiskCache(trimmedPath, downloaded);
            }
          }

          var updated = track;
          bool changed = false;
          if (isArtistMissing(updated.artist) && onlineMeta.hasArtist) {
            updated = updated.copyWith(artist: onlineMeta.artist!.trim());
            changed = true;
          }
          if ((updated.album == null || updated.album!.trim().isEmpty) &&
              onlineMeta.album != null &&
              onlineMeta.album!.trim().isNotEmpty) {
            updated = updated.copyWith(album: onlineMeta.album!.trim());
            changed = true;
          }
          if ((updated.thumbnailUrl == null || updated.thumbnailUrl!.trim().isEmpty) &&
              onlineMeta.hasArtwork) {
            updated = updated.copyWith(
              thumbnailUrl: onlineMeta.artworkUrl,
              highResThumbnailUrl: onlineMeta.artworkUrl,
            );
            changed = true;
          }

          if (changed) {
            _updateHiveTrackMetadata(updated);
            _trackEnrichedController.add(updated);
          } else if (onlineMeta.hasArtwork) {
            _updateHiveTrackThumbnail(track, onlineMeta.artworkUrl!);
          }

          if (downloaded != null && downloaded.isNotEmpty) {
            return downloaded;
          }
        }
      }

      // Negative cache to prevent hammering APIs on subsequent rebuilds
      _notFoundCache[trimmedPath] = DateTime.now();
    }

    return null;
  }

  /// The URLs [track] has for its art, sharpest first. YouTube Music's
  /// thumbnails state their size in the URL, so a bigger one can be asked for.
  static List<String> artworkUrlCandidates(Track track, {String? extraUrl}) {
    final sized = RegExp(r'([=/])w\d+-h\d+');
    final urls = <String>{};
    for (final raw in [track.highResThumbnailUrl, track.thumbnailUrl, extraUrl]) {
      final url = raw?.trim();
      if (url == null || !url.startsWith('http')) continue;
      if (sized.hasMatch(url)) {
        urls.add(url.replaceAllMapped(sized, (m) => '${m[1]}w800-h800'));
      }
      urls.add(url);
    }
    return urls.toList();
  }

  /// Art for [track] from a search of the online catalogues, for when it has
  /// no thumbnail of its own to use.
  static Future<Uint8List?> searchArtworkBytes(Track track) async {
    final query = sanitizeTrackQuery(track.title, track.artist);
    if (query.isEmpty) return null;
    final meta = await _lookupOnlineMetadata(query);
    if (meta == null || !meta.hasArtwork) return null;
    return _downloadArtworkBytes(meta.artworkUrl!);
  }

  /// Asynchronously fetch online metadata (including artist, album, artwork) for a local track.
  static Future<Track?> fetchOnlineMetadata(Track track) async {
    final cleanQuery = sanitizeTrackQuery(track.title, track.artist);
    if (cleanQuery.isEmpty) return null;

    final key = 'meta_${track.id}_${cleanQuery.hashCode}';
    if (_isRecentMiss(key)) return null;

    final meta = await _lookupOnlineMetadata(cleanQuery);
    if (meta == null) {
      _notFoundCache[key] = DateTime.now();
      return null;
    }

    bool changed = false;
    var updated = track;

    if (isArtistMissing(updated.artist) && meta.hasArtist) {
      updated = updated.copyWith(artist: meta.artist!.trim());
      changed = true;
    }

    if ((updated.album == null || updated.album!.trim().isEmpty) &&
        meta.album != null &&
        meta.album!.trim().isNotEmpty) {
      updated = updated.copyWith(album: meta.album!.trim());
      changed = true;
    }

    if ((updated.thumbnailUrl == null || updated.thumbnailUrl!.trim().isEmpty) &&
        meta.hasArtwork) {
      updated = updated.copyWith(
        thumbnailUrl: meta.artworkUrl,
        highResThumbnailUrl: meta.artworkUrl,
      );
      changed = true;
    }

    if (changed) {
      _updateHiveTrackMetadata(updated);
      _trackEnrichedController.add(updated);
      return updated;
    }

    return null;
  }

  /// Look up metadata online across iTunes -> YouTube Music -> JioSaavn.
  static Future<OnlineTrackMetadata?> _lookupOnlineMetadata(String query) async {
    // Tier 1: iTunes Search API (Fastest, zero auth, official 600x600 covers & clean artist)
    try {
      final itunesUri = Uri.parse(
        'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&entity=song&limit=1',
      );
      final res = await http.get(itunesUri).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final dynamic data = jsonDecode(res.body);
        if (data is Map<String, dynamic>) {
          final results = data['results'] as List<dynamic>?;
          if (results != null && results.isNotEmpty) {
            final first = results.first as Map<String, dynamic>;
            final art100 = first['artworkUrl100']?.toString();
            final artistName = first['artistName']?.toString();
            final trackName = first['trackName']?.toString();
            final collectionName = first['collectionName']?.toString();

            return OnlineTrackMetadata(
              artworkUrl: art100 != null && art100.isNotEmpty
                  ? art100.replaceAll('100x100bb', '600x600bb')
                  : null,
              artist: artistName,
              title: trackName,
              album: collectionName,
            );
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('LocalArtworkService: iTunes lookup error: $e');
      }
    }

    // Tier 2: YouTube Music API (InnerTube fallback for indie, remixes, mashups)
    try {
      _innerTubeService ??= InnerTubeService();
      final results = await _innerTubeService!
          .search(query, filter: 'EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D')
          .timeout(const Duration(seconds: 5));
      if (results.tracks.isNotEmpty) {
        final track = results.tracks.first;
        var thumb = track.bestThumbnail;
        if (thumb != null && thumb.isNotEmpty) {
          if (thumb.contains('w120-h120')) {
            thumb = thumb.replaceAll('w120-h120', 'w600-h600');
          } else if (thumb.contains('=w60-h60')) {
            thumb = thumb.replaceAll('=w60-h60', '=w600-h600');
          }
        }
        return OnlineTrackMetadata(
          artworkUrl: thumb,
          artist: track.artist,
          title: track.title,
          album: track.album,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('LocalArtworkService: YouTube Music lookup error: $e');
      }
    }

    // Tier 3: JioSaavn API (Regional Indian music fallback)
    try {
      final saavnSongs = await JioSaavnService.instance
          .searchSongs(query, limit: 1)
          .timeout(const Duration(seconds: 5));
      if (saavnSongs.isNotEmpty) {
        final song = saavnSongs.first;
        var img = song.image;
        if (img != null && img.isNotEmpty) {
          img = img
              .replaceAll('150x150', '500x500')
              .replaceAll('50x50', '500x500');
        }
        return OnlineTrackMetadata(
          artworkUrl: img,
          artist: song.artist,
          title: song.title,
          album: song.album,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('LocalArtworkService: JioSaavn lookup error: $e');
      }
    }

    return null;
  }

  /// Download raw image bytes from an artwork URL with validation.
  static Future<Uint8List?> _downloadArtworkBytes(String url) async {
    try {
      final res = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200 && MediaTagger.isImageBytes(res.bodyBytes)) {
        return res.bodyBytes;
      }
    } catch (e) {
      if (kDebugMode) {
        print('LocalArtworkService: download error: $e');
      }
    }
    return null;
  }

  /// Update local Hive track entity with discovered metadata (artist, album, thumbnail).
  static void _updateHiveTrackMetadata(Track track) {
    try {
      if (HiveService.localMusicTracksBox.isOpen) {
        final entity = HiveService.localMusicTracksBox.get(track.id);
        if (entity != null) {
          bool entityChanged = false;
          if (isArtistMissing(entity.artist) && !isArtistMissing(track.artist)) {
            entity.artist = track.artist;
            entityChanged = true;
          }
          if ((entity.album == null || entity.album!.isEmpty) &&
              track.album != null &&
              track.album!.isNotEmpty) {
            entity.album = track.album;
            entityChanged = true;
          }
          if ((entity.thumbnailUrl == null || entity.thumbnailUrl!.isEmpty) &&
              track.thumbnailUrl != null &&
              track.thumbnailUrl!.isNotEmpty) {
            entity.thumbnailUrl = track.thumbnailUrl;
            entityChanged = true;
          }
          if (entityChanged) {
            entity.save();
          }
        }
      }
    } catch (_) {}
  }

  /// Update local Hive track entity with the discovered thumbnail URL.
  static void _updateHiveTrackThumbnail(Track track, String artworkUrl) {
    try {
      if (HiveService.localMusicTracksBox.isOpen) {
        final entity = HiveService.localMusicTracksBox.get(track.id);
        if (entity != null && (entity.thumbnailUrl == null || entity.thumbnailUrl!.isEmpty)) {
          entity.thumbnailUrl = artworkUrl;
          entity.save();
        }
      }
    } catch (_) {}
  }

  /// Sanitize song title and artist into a clean search query for online matching.
  static String sanitizeTrackQuery(String title, String? artist) {
    var cleanTitle = title.trim();

    // 1. Remove audio file extension if title ends with it
    cleanTitle = cleanTitle.replaceAll(
      RegExp(r'\.(mp3|m4a|mp4|opus|webm|flac|wav|ogg|aac|wma)$', caseSensitive: false),
      '',
    );

    // 2. Remove common ripper/website prefixes and domain tags
    cleanTitle = cleanTitle.replaceAll(
      RegExp(r'(?:www\.)?[a-zA-Z0-9_\-]+\.(?:com|is|net|org|in|co|cc|io|to|me|mp3|site)\s*[-_:]*\s*', caseSensitive: false),
      '',
    );

    // 3. Remove leading track numbering (e.g. "01 - ", "01. ", "01 ")
    cleanTitle = cleanTitle.replaceAll(RegExp(r'^\s*\d{1,3}[\.\-_\s]+\s*'), '');

    // 4. Remove bitrate, quality, and rip tags (e.g. [320kbps], (128 kbps), [FLAC])
    cleanTitle = cleanTitle.replaceAll(
      RegExp(r'\[\s*(?:320\s*kbps|128\s*kbps|flac|hq|lossless|audio|cd\s*rip|remastered[^\ designs\]]*)\s*\]', caseSensitive: false),
      '',
    );
    cleanTitle = cleanTitle.replaceAll(
      RegExp(r'\(\s*(?:320\s*kbps|128\s*kbps|flac|hq|lossless|audio|cd\s*rip|remastered[^\)]*)\s*\)', caseSensitive: false),
      '',
    );

    // 5. Remove video & media indicators (e.g. (Official Video), [Official Audio], (Lyrics))
    cleanTitle = cleanTitle.replaceAll(
      RegExp(r'[\(\[]\s*(?:official\s*(?:video|audio|music\s*video|lyric\s*video|visualizer)|lyrics?|visualizer|audio\s*track|full\s*song|hd|4k|remastered)\s*[\)\]]', caseSensitive: false),
      '',
    );

    // 6. Replace underscores with spaces
    cleanTitle = cleanTitle.replaceAll('_', ' ');

    // 7. Collapse repeated whitespace and trim
    cleanTitle = cleanTitle.replaceAll(RegExp(r'\s+'), ' ').trim();

    // 8. Skip voice notes, system recordings, or generic 'track 01'
    final lowerTitle = cleanTitle.toLowerCase();
    if (lowerTitle.startsWith('aud-') ||
        lowerTitle.startsWith('ptt-') ||
        lowerTitle.startsWith('voice') ||
        lowerTitle.startsWith('recording') ||
        RegExp(r'^track\s*\d+$').hasMatch(lowerTitle) ||
        RegExp(r'^\d+$').hasMatch(cleanTitle)) {
      return '';
    }

    // 9. Format artist
    var cleanArtist = artist?.trim() ?? '';
    if (isArtistMissing(cleanArtist)) {
      cleanArtist = '';
    }

    if (cleanArtist.isNotEmpty) {
      final lowerArtist = cleanArtist.toLowerCase();
      // Avoid duplicate artist name if title already contains it
      if (lowerTitle.contains(lowerArtist)) {
        return cleanTitle;
      }
      return '$cleanArtist $cleanTitle';
    }

    return cleanTitle;
  }

  /// Get the cached File containing the artwork for a local audio file.
  static Future<File?> getArtworkFile(
    String localFilePath, {
    Track? track,
  }) async {
    // 1. Check synchronous fast cache first
    final fastFile = getCachedFile(localFilePath);
    if (fastFile != null) return fastFile;

    final bytes = await getArtworkBytes(localFilePath, track: track);
    if (bytes == null || bytes.isEmpty) return null;

    try {
      final cacheDir = await _getCacheDirectory();
      final cacheFile = File('${cacheDir.path}/${localFilePath.trim().hashCode}.jpg');
      if (await cacheFile.exists() && await cacheFile.length() > 0) {
        return cacheFile;
      }
      await cacheFile.writeAsBytes(bytes, flush: true);
      return cacheFile;
    } catch (_) {
      return null;
    }
  }

  static void _saveToDiskCache(String localFilePath, Uint8List bytes) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final cacheFile = File('${cacheDir.path}/${localFilePath.trim().hashCode}.jpg');
      await cacheFile.writeAsBytes(bytes, flush: true);
    } catch (_) {}
  }

  /// Extract `covr` payload from MP4/M4A box tree.
  static Uint8List? _extractMp4Cover(Uint8List bytes) {
    final covrPattern = latin1.encode('covr');
    final dataPattern = latin1.encode('data');
    for (int i = 0; i < bytes.length - 16; i++) {
      if (bytes[i] == covrPattern[0] &&
          bytes[i + 1] == covrPattern[1] &&
          bytes[i + 2] == covrPattern[2] &&
          bytes[i + 3] == covrPattern[3]) {
        for (int j = i + 4; j < bytes.length - 16 && j < i + 250; j++) {
          if (bytes[j] == dataPattern[0] &&
              bytes[j + 1] == dataPattern[1] &&
              bytes[j + 2] == dataPattern[2] &&
              bytes[j + 3] == dataPattern[3]) {
            final dataSize = ((bytes[j - 4] & 0xFF) << 24) |
                ((bytes[j - 3] & 0xFF) << 16) |
                ((bytes[j - 2] & 0xFF) << 8) |
                (bytes[j - 1] & 0xFF);
            final payloadStart = j + 12; // (j - 4) + 8 byte box header + 8 byte data header
            final payloadLength = dataSize - 16;
            if (payloadStart + payloadLength <= bytes.length &&
                payloadLength > 0) {
              final payload = bytes.sublist(
                payloadStart,
                payloadStart + payloadLength,
              );
              // "covr" can turn up by chance in the audio: keep looking.
              if (MediaTagger.isImageBytes(payload)) return payload;
            }
          }
        }
      }
    }
    return null;
  }

  /// Clear in-memory cache and negative lookup cache.
  static void clearMemoryCache() {
    _memoryCache.clear();
    _notFoundCache.clear();
  }
}
