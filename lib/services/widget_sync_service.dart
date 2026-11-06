import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import 'audio_player_service.dart' as player;
import 'local_artwork_service.dart';

/// Syncs playback metadata to the native Android home-screen widget.
///
/// Artwork travels separately from everything else, so a slow network can
/// never hold back the title and play state. It's looked for in the
/// background until the widget has the full cover or the song changes.
class WidgetSyncService {
  static const MethodChannel _channel = MethodChannel('inzx/widget');

  static String? _lastFingerprint;

  /// Bumped by each state actually sent; an older one still waiting on its
  /// artwork grace period is then out of date and is dropped.
  static int _syncGeneration = 0;

  /// The song the artwork below belongs to.
  static String? _artTrackId;

  /// What the current search is looking for; a change restarts it.
  static String? _artSearchKey;

  /// Bumped to stop a running search.
  static int _artSearchId = 0;

  /// Done once the search's first attempt has settled, either way.
  static Completer<void>? _firstAttempt;

  /// The song whose title and state the widget has been sent.
  static String? _sentTrackId;

  /// Artwork found before the state for its song was sent: goes with it.
  static Uint8List? _pendingArt;

  /// Whether [_pendingArt] is a low-res thumbnail (virtual trackId needed).
  static bool _pendingIsThumbnail = false;

  /// How long a new song's state waits for its artwork, so a normal
  /// connection changes the title and cover together.
  @visibleForTesting
  static Duration artGrace = const Duration(milliseconds: 1200);

  /// Waits between attempts; the last one repeats.
  @visibleForTesting
  static List<Duration> retryDelays = const [
    Duration(seconds: 3),
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  /// Keeps a paused song on a dead network from trying forever; the next
  /// state change starts a fresh search.
  static const _maxAttempts = 20;

  /// First try at the full cover. Most connections manage this; one that
  /// doesn't gets the small thumbnail meanwhile, then longer tries.
  static const _quickFullTimeout = Duration(seconds: 4);
  static const _smallTimeout = Duration(seconds: 8);
  static const _fullTimeout = Duration(seconds: 20);

  @visibleForTesting
  static Future<Uint8List?> Function(String url, Duration timeout) download =
      _downloadArtworkBytes;

  /// What the app's own screens already loaded, which needs no network.
  @visibleForTesting
  static Future<Uint8List?> Function(String url) readCache = _readFromImageCache;

  static Future<void> syncPlaybackState(
    player.PlaybackState state, {
    String? statusLabel,
    bool isLiked = false,
  }) async {
    final track = state.currentTrack;
    final hasTrack = track != null;
    final effectiveDuration =
        state.duration ?? track?.duration ?? Duration.zero;
    final isNewTrack = track?.id != _artTrackId;

    // Before the fingerprint check: a cover URL that turns up later doesn't
    // change the fingerprint, and has to be noticed all the same.
    _watchArtwork(track);

    final payload = <String, dynamic>{
      'trackId': track?.id,
      'title': track?.title ?? 'Not playing',
      'artist': track?.artist ?? 'Open Inzx to start music',
      'isPlaying': state.isPlaying,
      'hasTrack': hasTrack,
      'positionMs': state.position.inMilliseconds,
      'durationMs': effectiveDuration.inMilliseconds,
      'isLiked': isLiked,
      'shuffle': state.shuffleEnabled,
    };
    payload['statusLabel'] = statusLabel?.trim() ?? '';

    final fingerprint =
        '${_fingerprintFrom(track, state.isPlaying, hasTrack, statusLabel)}'
        '|$isLiked|${state.shuffleEnabled}';
    if (_lastFingerprint == fingerprint) return;
    _lastFingerprint = fingerprint;
    final generation = ++_syncGeneration;

    final firstAttempt = _firstAttempt;
    if (isNewTrack && firstAttempt != null) {
      await Future.any<void>([
        firstAttempt.future,
        Future<void>.delayed(artGrace),
      ]);
      if (generation != _syncGeneration) return;
    }

    final art = _pendingArt;
    if (art != null) {
      payload['artBytes'] = art;
      if (_pendingIsThumbnail) {
        payload['trackId'] = '${track?.id}_thumb';
      }
      _pendingArt = null;
      _pendingIsThumbnail = false;
    }
    _sentTrackId = track?.id;

    try {
      await _channel.invokeMethod('syncPlaybackState', payload);
    } catch (_) {
      // Widget sync is best-effort and should never block playback controls.
    }
  }

  static void _watchArtwork(Track? track) {
    if (track?.id != _artTrackId) {
      _artTrackId = track?.id;
      _artSearchKey = null;
      _pendingArt = null;
      _firstAttempt = null;
      _artSearchId++;
    }
    if (track == null) return;
    final key = '${track.systemArtworkUrl}|${track.localFilePath}';
    if (key == _artSearchKey) return;
    if (track.systemArtworkUrl == null && track.localFilePath == null) return;
    _artSearchKey = key;
    final searchId = ++_artSearchId;
    final firstAttempt = Completer<void>();
    _firstAttempt = firstAttempt;
    unawaited(_searchForArtwork(track, searchId, firstAttempt));
  }

  /// Runs until the widget has the full cover, the song changes, or
  /// [_maxAttempts] is spent.
  static Future<void> _searchForArtwork(
    Track track,
    int searchId,
    Completer<void> firstAttempt,
  ) async {
    var hasSmall = false;
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      if (attempt > 0) {
        final delays = retryDelays;
        await Future<void>.delayed(
          delays[(attempt - 1).clamp(0, delays.length - 1)],
        );
        if (searchId != _artSearchId) return;
      }

      final full = await _loadFullCover(track, attempt);
      if (searchId != _artSearchId) return;
      if (full != null) {
        await _deliverArt(track.id, full);
        if (!firstAttempt.isCompleted) firstAttempt.complete();
        return;
      }

      if (!hasSmall) {
        final small = await _loadSmallCover(track);
        if (searchId != _artSearchId) return;
        if (small != null) {
          hasSmall = true;
          await _deliverArt(track.id, small, isThumbnail: true);
        }
      }
      if (!firstAttempt.isCompleted) firstAttempt.complete();
    }
    // Spent: let the next state change start a new search.
    if (searchId == _artSearchId) _artSearchKey = null;
  }

  static Future<Uint8List?> _loadFullCover(Track track, int attempt) async {
    final local = track.localFilePath;
    if (local != null) {
      try {
        final bytes = await LocalArtworkService.getArtworkBytes(
          local,
          track: track,
        );
        if (bytes != null && bytes.isNotEmpty) return bytes;
      } catch (_) {}
    }
    final url = track.systemArtworkUrl;
    if (url == null || url.isEmpty) return null;
    return await readCache(url) ??
        await download(url, attempt == 0 ? _quickFullTimeout : _fullTimeout);
  }

  /// The thumbnail the app's screens show, for a connection too slow for
  /// the full cover: something on the widget while the search goes on.
  static Future<Uint8List?> _loadSmallCover(Track track) async {
    final urls = {track.bestThumbnail, track.thumbnailUrl}
      ..remove(track.systemArtworkUrl)
      ..remove(null);
    for (final url in urls.cast<String>()) {
      if (url.isEmpty) continue;
      final bytes = await readCache(url) ?? await download(url, _smallTimeout);
      if (bytes != null) return bytes;
    }
    return null;
  }

  static Future<void> _deliverArt(
    String trackId,
    Uint8List bytes, {
    bool isThumbnail = false,
  }) async {
    if (trackId != _artTrackId) return;
    if (_sentTrackId != trackId) {
      _pendingArt = bytes;
      _pendingIsThumbnail = isThumbnail;
      return;
    }
    try {
      await _channel.invokeMethod('syncPlaybackState', <String, dynamic>{
        'trackId': isThumbnail ? '${trackId}_thumb' : trackId,
        'artBytes': bytes,
      });
    } catch (_) {}
  }

  static String _fingerprintFrom(
    Track? track,
    bool isPlaying,
    bool hasTrack,
    String? statusLabel,
  ) {
    final id = track?.id ?? '';
    final title = track?.title ?? '';
    final artist = track?.artist ?? '';
    final status = statusLabel ?? '';
    return '$id|$title|$artist|$isPlaying|$hasTrack|$status';
  }

  static Future<Uint8List?> _readFromImageCache(String url) async {
    try {
      final cached = await DefaultCacheManager().getFileFromCache(url);
      if (cached == null) return null;
      final bytes = await cached.file.readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _downloadArtworkBytes(
    String url,
    Duration timeout,
  ) async {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null) return null;
      final response = await http
          .get(uri, headers: {'User-Agent': 'InzxWidget/1.0'})
          .timeout(timeout);
      if (response.statusCode != 200) return null;
      if (response.bodyBytes.isEmpty) return null;
      return response.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _lastFingerprint = null;
    _syncGeneration = 0;
    _artTrackId = null;
    _artSearchKey = null;
    _artSearchId++;
    _firstAttempt = null;
    _sentTrackId = null;
    _pendingArt = null;
    _pendingIsThumbnail = false;
  }
}
