import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/models.dart';
import '../audio_player_service.dart';
import 'lastfm_client.dart';
import 'listenbrainz_client.dart';

/// Scrobbles to Last.fm and/or ListenBrainz, following the player.
///
/// The standard rule: a song counts once it has been *listened to* (paused
/// time doesn't count) for half its length or 3 minutes, whichever comes
/// first, and songs of 30 seconds or less never count. "Now playing" is
/// sent when a song starts. Session keys and tokens live in secure storage.
class ScrobbleService extends ChangeNotifier {
  ScrobbleService._();
  static final ScrobbleService instance = ScrobbleService._();

  static const int minSongSeconds = 30;
  static const double scrobblePercent = 0.5;
  static const int scrobbleMaxSeconds = 180;

  final _secure = const FlutterSecureStorage();
  final _listenBrainz = ListenBrainzClient();

  // Settings.
  bool lastFmEnabled = true;
  bool lastFmNowPlaying = true;
  bool listenBrainzEnabled = true;
  bool primaryArtistOnly = false;
  bool useLibreFm = false;
  String customApiKey = '';
  String customApiSecret = '';

  // Accounts.
  String? lastFmUser;
  String? _lastFmSessionKey;
  String? listenBrainzUser;
  String? _listenBrainzToken;

  bool get lastFmSignedIn => _lastFmSessionKey != null;
  bool get listenBrainzSignedIn => _listenBrainzToken != null;

  LastFmClient get lastFm => LastFmClient(
    apiKey: customApiKey.isNotEmpty ? customApiKey : kLastFmApiKey,
    secret: customApiSecret.isNotEmpty ? customApiSecret : kLastFmApiSecret,
    endpoint: useLibreFm
        ? LastFmClient.libreFmEndpoint
        : LastFmClient.defaultEndpoint,
  );

  // Playback tracking.
  StreamSubscription<PlaybackState>? _sub;
  Track? _song;
  int _startedAt = 0; // unix seconds
  Duration _listened = Duration.zero;
  DateTime? _playingSince;
  Duration? _threshold;
  bool _scrobbled = false;
  bool _nowPlayingSent = false;
  Timer? _timer;

  Future<void> start() async {
    await _load();
    _sub ??= AudioPlayerService.instance.stateStream.listen(_onState);
  }

  // ---- Persistence ----------------------------------------------------

  static const _kLfEnabled = 'scrobble_lastfm_enabled';
  static const _kLfNowPlaying = 'scrobble_lastfm_now_playing';
  static const _kLbEnabled = 'scrobble_listenbrainz_enabled';
  static const _kPrimary = 'scrobble_primary_artist_only';
  static const _kLibre = 'scrobble_use_librefm';
  static const _kLfUser = 'scrobble_lastfm_user';
  static const _kLbUser = 'scrobble_listenbrainz_user';
  static const _kLfKey = 'scrobble_lastfm_api_key';
  static const _sLfSession = 'lastfm_session_key';
  static const _sLfSecret = 'lastfm_api_secret';
  static const _sLbToken = 'listenbrainz_token';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    lastFmEnabled = prefs.getBool(_kLfEnabled) ?? true;
    lastFmNowPlaying = prefs.getBool(_kLfNowPlaying) ?? true;
    listenBrainzEnabled = prefs.getBool(_kLbEnabled) ?? true;
    primaryArtistOnly = prefs.getBool(_kPrimary) ?? false;
    useLibreFm = prefs.getBool(_kLibre) ?? false;
    lastFmUser = prefs.getString(_kLfUser);
    listenBrainzUser = prefs.getString(_kLbUser);
    customApiKey = prefs.getString(_kLfKey) ?? '';
    try {
      _lastFmSessionKey = await _secure.read(key: _sLfSession);
      customApiSecret = await _secure.read(key: _sLfSecret) ?? '';
      _listenBrainzToken = await _secure.read(key: _sLbToken);
    } catch (e) {
      debugPrint('Scrobble: secure storage read failed: $e');
    }
    notifyListeners();
  }

  Future<void> setOption(String key, bool value) async {
    switch (key) {
      case _kLfEnabled:
        lastFmEnabled = value;
      case _kLfNowPlaying:
        lastFmNowPlaying = value;
      case _kLbEnabled:
        listenBrainzEnabled = value;
      case _kPrimary:
        primaryArtistOnly = value;
      case _kLibre:
        useLibreFm = value;
    }
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(key, value);
  }

  static const optLastFm = _kLfEnabled;
  static const optNowPlaying = _kLfNowPlaying;
  static const optListenBrainz = _kLbEnabled;
  static const optPrimaryArtist = _kPrimary;
  static const optLibreFm = _kLibre;

  Future<void> setCustomApi(String key, String secret) async {
    customApiKey = key.trim();
    customApiSecret = secret.trim();
    await (await SharedPreferences.getInstance()).setString(_kLfKey, customApiKey);
    await _secure.write(key: _sLfSecret, value: customApiSecret);
    notifyListeners();
  }

  // ---- Accounts -------------------------------------------------------

  Future<void> saveLastFmSession(LastFmSession session) async {
    _lastFmSessionKey = session.key;
    lastFmUser = session.name;
    await _secure.write(key: _sLfSession, value: session.key);
    await (await SharedPreferences.getInstance()).setString(_kLfUser, session.name);
    notifyListeners();
  }

  Future<void> signOutLastFm() async {
    _lastFmSessionKey = null;
    lastFmUser = null;
    await _secure.delete(key: _sLfSession);
    await (await SharedPreferences.getInstance()).remove(_kLfUser);
    notifyListeners();
  }

  /// Checks [token] with ListenBrainz and keeps it if it's valid.
  Future<bool> connectListenBrainz(String token) async {
    final user = await _listenBrainz.validateToken(token.trim());
    if (user == null) return false;
    _listenBrainzToken = token.trim();
    listenBrainzUser = user;
    await _secure.write(key: _sLbToken, value: _listenBrainzToken);
    await (await SharedPreferences.getInstance()).setString(_kLbUser, user);
    notifyListeners();
    return true;
  }

  Future<void> disconnectListenBrainz() async {
    _listenBrainzToken = null;
    listenBrainzUser = null;
    await _secure.delete(key: _sLbToken);
    await (await SharedPreferences.getInstance()).remove(_kLbUser);
    notifyListeners();
  }

  // ---- Following playback ---------------------------------------------

  bool get _anyTarget =>
      (lastFmEnabled && lastFmSignedIn) ||
      (listenBrainzEnabled && listenBrainzSignedIn);

  void _onState(PlaybackState state) {
    final track = state.currentTrack;
    if (track?.id != _song?.id) {
      _beginSong(track, state);
    } else if (track != null && _threshold == null) {
      // Duration often arrives a moment after the track does.
      _setThreshold(state.duration ?? track.duration);
    }
    _setPlaying(state.isPlaying);
  }

  void _beginSong(Track? track, PlaybackState state) {
    _timer?.cancel();
    _song = track;
    _listened = Duration.zero;
    _playingSince = null;
    _threshold = null;
    _scrobbled = false;
    _nowPlayingSent = false;
    _startedAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (track == null) return;
    _setThreshold(state.duration ?? track.duration);
  }

  void _setThreshold(Duration duration) {
    if (duration.inSeconds <= 0) return;
    if (duration.inSeconds <= minSongSeconds) {
      _threshold = const Duration(days: 1); // never
      return;
    }
    final half = Duration(
      milliseconds: (duration.inMilliseconds * scrobblePercent).round(),
    );
    const cap = Duration(seconds: scrobbleMaxSeconds);
    _threshold = half < cap ? half : cap;
    _schedule();
  }

  void _setPlaying(bool playing) {
    final now = DateTime.now();
    if (playing && _playingSince == null) {
      _playingSince = now;
      if (!_nowPlayingSent && _song != null) {
        _nowPlayingSent = true;
        unawaited(_sendNowPlaying(_song!));
      }
      _schedule();
    } else if (!playing && _playingSince != null) {
      _listened += now.difference(_playingSince!);
      _playingSince = null;
      _timer?.cancel();
    }
  }

  Duration get _listenedNow => _playingSince == null
      ? _listened
      : _listened + DateTime.now().difference(_playingSince!);

  void _schedule() {
    _timer?.cancel();
    final threshold = _threshold;
    if (threshold == null || _scrobbled || _playingSince == null) return;
    final remaining = threshold - _listenedNow;
    if (remaining <= Duration.zero) {
      _fire();
      return;
    }
    _timer = Timer(remaining, _fire);
  }

  void _fire() {
    final song = _song;
    if (song == null || _scrobbled) return;
    _scrobbled = true;
    unawaited(_sendScrobble(song, _startedAt));
  }

  String _artistFor(Track t) {
    if (!primaryArtistOnly) return t.artist;
    final first = t.artist
        .split(RegExp(r'\s*,\s*|\s+&\s+|\s+x\s+|\s+feat\.?\s+'))
        .first
        .trim();
    return first.isEmpty ? t.artist : first;
  }

  Future<void> _sendNowPlaying(Track t) async {
    if (!_anyTarget) return;
    final artist = _artistFor(t);
    if (lastFmEnabled && lastFmNowPlaying && _lastFmSessionKey != null) {
      try {
        await lastFm.updateNowPlaying(
          sessionKey: _lastFmSessionKey!,
          artist: artist,
          track: t.title,
          album: t.album,
          durationSeconds: t.duration.inSeconds,
        );
      } catch (e) {
        debugPrint('Scrobble: Last.fm now playing failed: $e');
      }
    }
    if (listenBrainzEnabled && _listenBrainzToken != null) {
      try {
        await _listenBrainz.playingNow(
          token: _listenBrainzToken!,
          artist: artist,
          track: t.title,
          album: t.album,
          durationMs: t.duration.inMilliseconds,
        );
      } catch (e) {
        debugPrint('Scrobble: ListenBrainz playing now failed: $e');
      }
    }
  }

  Future<void> _sendScrobble(Track t, int startedAt) async {
    if (!_anyTarget) return;
    final artist = _artistFor(t);
    if (lastFmEnabled && _lastFmSessionKey != null) {
      try {
        await lastFm.scrobble(
          sessionKey: _lastFmSessionKey!,
          artist: artist,
          track: t.title,
          timestamp: startedAt,
          album: t.album,
          durationSeconds: t.duration.inSeconds,
        );
        debugPrint('Scrobble: Last.fm scrobbled "${t.title}"');
      } on LastFmException catch (e) {
        debugPrint('Scrobble: Last.fm scrobble failed: $e');
        // 9 = invalid session (revoked in Last.fm settings): sign out.
        if (e.code == 9) await signOutLastFm();
      } catch (e) {
        debugPrint('Scrobble: Last.fm scrobble failed: $e');
      }
    }
    if (listenBrainzEnabled && _listenBrainzToken != null) {
      try {
        await _listenBrainz.listened(
          token: _listenBrainzToken!,
          artist: artist,
          track: t.title,
          listenedAt: startedAt,
          album: t.album,
          durationMs: t.duration.inMilliseconds,
        );
        debugPrint('Scrobble: ListenBrainz submitted "${t.title}"');
      } catch (e) {
        debugPrint('Scrobble: ListenBrainz submit failed: $e');
      }
    }
  }
}
