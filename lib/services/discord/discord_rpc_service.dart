import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/models.dart';
import 'discord_oauth.dart';

enum DiscordRpcStatus {
  disconnected,
  connecting,
  connected,
  error,
}

class DiscordRpcState {
  final DiscordRpcStatus status;
  final String? username;
  final String? globalName;
  final String? discriminator;
  final String? avatarUrl;
  final String? errorMessage;

  const DiscordRpcState({
    required this.status,
    this.username,
    this.globalName,
    this.discriminator,
    this.avatarUrl,
    this.errorMessage,
  });

  String get displayName {
    if (globalName != null && globalName!.trim().isNotEmpty) {
      return globalName!.trim();
    }
    if (username != null && username!.isNotEmpty) {
      if (discriminator != null && discriminator != '0') {
        return '$username#$discriminator';
      }
      return username!;
    }
    return 'Discord User';
  }

  DiscordRpcState copyWith({
    DiscordRpcStatus? status,
    String? username,
    String? globalName,
    String? discriminator,
    String? avatarUrl,
    String? errorMessage,
  }) {
    return DiscordRpcState(
      status: status ?? this.status,
      username: username ?? this.username,
      globalName: globalName ?? this.globalName,
      discriminator: discriminator ?? this.discriminator,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      errorMessage: errorMessage,
    );
  }
}

/// Discord Rich Presence via OAuth2 (Metrolist-style).
///
/// Instead of scraping a user token in an embedded WebView (which blocks
/// passkeys and violates Discord's ToS), the user authorizes through the system
/// browser and the app receives an OAuth access token with the
/// `sdk.social_layer_presence` scope. That token drives presence over the
/// Gateway, exactly like a first-party client.
class DiscordRpcService {
  static final DiscordRpcService _instance = DiscordRpcService._internal();
  factory DiscordRpcService() => _instance;
  static DiscordRpcService get instance => _instance;

  DiscordRpcService._internal();

  // Preference keys
  static const String _prefClearOnPauseKey = 'inzx_discord_rpc_clear_on_pause';
  static const String _prefShowTimestampsKey =
      'inzx_discord_rpc_show_timestamps';
  static const String _prefShowAlbumArtKey = 'inzx_discord_rpc_show_album_art';
  static const String _prefCachedUsernameKey = 'inzx_discord_cached_username';
  static const String _prefCachedGlobalNameKey =
      'inzx_discord_cached_global_name';
  static const String _prefCachedAvatarUrlKey = 'inzx_discord_cached_avatar_url';

  // Secure storage keys (OAuth tokens)
  static const String _secureAccessTokenKey = 'inzx_discord_access_token';
  static const String _secureRefreshTokenKey = 'inzx_discord_refresh_token';
  static const String _secureExpiresAtKey = 'inzx_discord_expires_at';

  static const String _gatewayUrl =
      'wss://gateway.discord.gg/?v=10&encoding=json';
  static const String _apiBase = 'https://discord.com/api/v10';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  final ValueNotifier<DiscordRpcState> stateNotifier =
      ValueNotifier<DiscordRpcState>(
    const DiscordRpcState(status: DiscordRpcStatus.disconnected),
  );

  DiscordRpcState get state => stateNotifier.value;

  /// Discord application (client) ID — the OAuth client_id.
  String? get clientId => dotenv.env['DISCORD_CLIENT_ID']?.trim();
  bool get isConfigured => clientId != null && clientId!.isNotEmpty;

  // Display preferences
  bool _clearOnPause = true;
  bool get clearOnPause => _clearOnPause;
  bool _showTimestamps = true;
  bool get showTimestamps => _showTimestamps;
  bool _showAlbumArt = true;
  bool get showAlbumArt => _showAlbumArt;

  // OAuth token state
  String? _accessToken;
  String? _refreshToken;
  int _expiresAtEpochSec = 0;
  bool get isAuthorized => _accessToken != null && _accessToken!.isNotEmpty;

  bool _authorizeInProgress = false;

  // Gateway state
  WebSocket? _webSocket;
  StreamSubscription? _wsSubscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  Timer? _presenceDebounceTimer;

  int? _lastSequence;
  int _reconnectAttempts = 0;
  bool _intentionalDisconnect = false;
  bool _refreshedThisCycle = false;

  // Cached playback
  Track? _currentTrack;
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration? _currentDuration;

  // Resolved external asset cache (source url -> "mp:..." ref)
  final Map<String, String> _assetCache = {};

  /// Restore preferences + tokens and connect if signed in.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _clearOnPause = prefs.getBool(_prefClearOnPauseKey) ?? true;
      _showTimestamps = prefs.getBool(_prefShowTimestampsKey) ?? true;
      _showAlbumArt = prefs.getBool(_prefShowAlbumArtKey) ?? true;

      final cachedUsername = prefs.getString(_prefCachedUsernameKey);
      final cachedGlobalName = prefs.getString(_prefCachedGlobalNameKey);
      final cachedAvatar = prefs.getString(_prefCachedAvatarUrlKey);
      if (cachedUsername != null) {
        stateNotifier.value = DiscordRpcState(
          status: DiscordRpcStatus.disconnected,
          username: cachedUsername,
          globalName: cachedGlobalName,
          avatarUrl: cachedAvatar,
        );
      }

      try {
        _accessToken = await _secureStorage.read(key: _secureAccessTokenKey);
        _refreshToken = await _secureStorage.read(key: _secureRefreshTokenKey);
        final expiresAtStr =
            await _secureStorage.read(key: _secureExpiresAtKey);
        _expiresAtEpochSec = int.tryParse(expiresAtStr ?? '') ?? 0;
      } catch (e) {
        _debug('Failed to read tokens: $e');
      }

      if (isAuthorized) {
        _connectWithFreshToken();
      }
    } catch (e) {
      _debug('init error: $e');
    }
  }

  /// Start the browser OAuth flow, then connect. Returns true on success.
  Future<bool> authorize() async {
    if (!isConfigured) {
      stateNotifier.value = state.copyWith(
        status: DiscordRpcStatus.error,
        errorMessage: 'DISCORD_CLIENT_ID is not set in .env',
      );
      return false;
    }
    if (_authorizeInProgress) return false;
    _authorizeInProgress = true;

    stateNotifier.value = state.copyWith(
      status: DiscordRpcStatus.connecting,
      errorMessage: null,
    );

    try {
      _debug('authorize() start — clientId=<${clientId!}>');
      final tokens = await DiscordOAuth.authorize(clientId!);
      _debug('authorize() got tokens (accessLen=${tokens.accessToken.length}, '
          'scope=${tokens.scope})');
      await _storeTokens(tokens);
      await connect();
      return true;
    } on DiscordAuthException catch (e) {
      _debug('authorize() DiscordAuthException: ${e.message}');
      stateNotifier.value = state.copyWith(
        status: DiscordRpcStatus.disconnected,
        errorMessage: e.message,
      );
      return false;
    } catch (e) {
      stateNotifier.value = state.copyWith(
        status: DiscordRpcStatus.disconnected,
        errorMessage: 'Sign-in failed: $e',
      );
      return false;
    } finally {
      _authorizeInProgress = false;
    }
  }

  /// Sign out: disconnect and forget all tokens.
  Future<void> logout() async {
    _accessToken = null;
    _refreshToken = null;
    _expiresAtEpochSec = 0;
    try {
      await _secureStorage.delete(key: _secureAccessTokenKey);
      await _secureStorage.delete(key: _secureRefreshTokenKey);
      await _secureStorage.delete(key: _secureExpiresAtKey);
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefCachedUsernameKey);
    await prefs.remove(_prefCachedGlobalNameKey);
    await prefs.remove(_prefCachedAvatarUrlKey);

    disconnect();
    _assetCache.clear();
    stateNotifier.value =
        const DiscordRpcState(status: DiscordRpcStatus.disconnected);
  }

  Future<void> _storeTokens(DiscordTokens tokens) async {
    _accessToken = tokens.accessToken;
    if (tokens.refreshToken.isNotEmpty) _refreshToken = tokens.refreshToken;
    _expiresAtEpochSec = tokens.expiresInSec > 0
        ? (DateTime.now().millisecondsSinceEpoch ~/ 1000) + tokens.expiresInSec
        : 0;
    try {
      await _secureStorage.write(
          key: _secureAccessTokenKey, value: _accessToken);
      if (_refreshToken != null) {
        await _secureStorage.write(
            key: _secureRefreshTokenKey, value: _refreshToken);
      }
      await _secureStorage.write(
          key: _secureExpiresAtKey, value: _expiresAtEpochSec.toString());
    } catch (e) {
      _debug('Failed to persist tokens: $e');
    }
  }

  // ── Preferences ────────────────────────────────────────────────────
  Future<void> setClearOnPause(bool value) async {
    _clearOnPause = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefClearOnPauseKey, value);
    _triggerPresenceUpdate();
  }

  Future<void> setShowTimestamps(bool value) async {
    _showTimestamps = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefShowTimestampsKey, value);
    _triggerPresenceUpdate();
  }

  Future<void> setShowAlbumArt(bool value) async {
    _showAlbumArt = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefShowAlbumArtKey, value);
    _triggerPresenceUpdate();
  }

  // ── Token freshness ────────────────────────────────────────────────
  Future<void> _connectWithFreshToken() async {
    await _refreshIfNeeded();
    await connect();
  }

  Future<bool> _refreshIfNeeded() async {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final needs = _refreshToken != null &&
        _refreshToken!.isNotEmpty &&
        _expiresAtEpochSec > 0 &&
        (_expiresAtEpochSec - nowSec) < 3600;
    if (!needs) return true;
    return _doRefresh();
  }

  Future<bool> _doRefresh() async {
    if (_refreshToken == null || _refreshToken!.isEmpty || !isConfigured) {
      return false;
    }
    try {
      final tokens = await DiscordOAuth.refresh(clientId!, _refreshToken!);
      await _storeTokens(tokens);
      _debug('Token refreshed');
      return true;
    } catch (e) {
      _debug('Token refresh failed: $e');
      return false;
    }
  }

  // ── Gateway ────────────────────────────────────────────────────────
  Future<void> connect() async {
    if (!isAuthorized) {
      stateNotifier.value = state.copyWith(
        status: DiscordRpcStatus.disconnected,
        errorMessage: 'Not signed in',
      );
      return;
    }

    _intentionalDisconnect = false;
    _reconnectTimer?.cancel();
    _tearDownSocket();

    stateNotifier.value = state.copyWith(
      status: DiscordRpcStatus.connecting,
      errorMessage: null,
    );

    try {
      _debug('Connecting to gateway...');
      _webSocket = await WebSocket.connect(_gatewayUrl)
          .timeout(const Duration(seconds: 15));
      _reconnectAttempts = 0;
      _wsSubscription = _webSocket!.listen(
        _onMessageReceived,
        onError: _onSocketError,
        onDone: _onSocketDone,
        cancelOnError: false,
      );
    } catch (e) {
      _debug('Connection error: $e');
      _handleDisconnect(error: 'Connection failed: $e');
    }
  }

  void disconnect() {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _tearDownSocket();
    stateNotifier.value = state.copyWith(
      status: DiscordRpcStatus.disconnected,
      errorMessage: null,
    );
  }

  void _tearDownSocket() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _wsSubscription?.cancel();
    _wsSubscription = null;
    try {
      _webSocket?.close(1000, 'Client closed');
    } catch (_) {}
    _webSocket = null;
  }

  void _onSocketError(dynamic error) {
    _debug('socket error: $error');
    _handleDisconnect(error: 'Socket error: $error');
  }

  void _onSocketDone() {
    final closeCode = _webSocket?.closeCode;
    _debug('socket closed: code=$closeCode');

    // 4004 = authentication failed (expired/invalid token) → try one refresh.
    if (closeCode == 4004 && !_refreshedThisCycle) {
      _refreshedThisCycle = true;
      _tearDownSocket();
      _doRefresh().then((ok) {
        if (ok && !_intentionalDisconnect) {
          connect();
        } else {
          stateNotifier.value = state.copyWith(
            status: DiscordRpcStatus.error,
            errorMessage: 'Session expired. Please reconnect Discord.',
          );
        }
      });
      return;
    }

    if (!_intentionalDisconnect) {
      _handleDisconnect(error: 'Connection lost');
    }
  }

  void _handleDisconnect({String? error}) {
    _tearDownSocket();
    if (_intentionalDisconnect || !isAuthorized) {
      stateNotifier.value = state.copyWith(
        status: DiscordRpcStatus.disconnected,
        errorMessage: error,
      );
      return;
    }

    stateNotifier.value = state.copyWith(
      status: DiscordRpcStatus.connecting,
      errorMessage:
          error != null ? '$error (reconnecting...)' : 'Reconnecting...',
    );

    _reconnectAttempts++;
    final backoffSeconds =
        min(60, 3 * pow(2, min(_reconnectAttempts, 4)).toInt());
    _debug('Reconnecting in ${backoffSeconds}s (attempt $_reconnectAttempts)');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: backoffSeconds), () {
      if (isAuthorized && !_intentionalDisconnect) connect();
    });
  }

  void _onMessageReceived(dynamic message) {
    try {
      final data = jsonDecode(message as String);
      final int op = data['op'] as int? ?? -1;
      final dynamic d = data['d'];
      final int? s = data['s'] as int?;
      if (s != null) _lastSequence = s;

      switch (op) {
        case 10: // HELLO
          final int intervalMs = d['heartbeat_interval'] as int? ?? 41250;
          _startHeartbeat(intervalMs);
          _sendIdentify();
          break;
        case 0: // DISPATCH
          if (data['t'] == 'READY') _handleReadyEvent(d);
          break;
        case 1: // HEARTBEAT request
          _sendHeartbeat();
          break;
        case 7: // RECONNECT
          _handleDisconnect(error: 'Gateway requested reconnect');
          break;
        case 9: // INVALID_SESSION
          _handleDisconnect(error: 'Session invalidated');
          break;
        case 11: // HEARTBEAT_ACK
          break;
      }
    } catch (e) {
      _debug('Failed to parse message: $e');
    }
  }

  void _startHeartbeat(int intervalMs) {
    _heartbeatTimer?.cancel();
    final initialJitterMs =
        (intervalMs * (0.1 + 0.8 * Random().nextDouble())).floor();
    _heartbeatTimer = Timer(Duration(milliseconds: initialJitterMs), () {
      _sendHeartbeat();
      _heartbeatTimer = Timer.periodic(
        Duration(milliseconds: intervalMs),
        (_) => _sendHeartbeat(),
      );
    });
  }

  void _sendHeartbeat() {
    if (_webSocket != null && _webSocket!.readyState == WebSocket.open) {
      _webSocket!.add(jsonEncode({'op': 1, 'd': _lastSequence}));
    }
  }

  void _sendIdentify() {
    if (_webSocket == null ||
        _webSocket!.readyState != WebSocket.open ||
        _accessToken == null) {
      return;
    }
    final payload = jsonEncode({
      'op': 2,
      'd': {
        'token': 'Bearer $_accessToken',
        'intents': 0,
        'properties': {
          'os': 'android',
          'browser': 'Discord Android',
          'device': clientId ?? 'inzx',
        },
        'compress': false,
      },
    });
    _webSocket!.add(payload);
  }

  void _handleReadyEvent(dynamic d) async {
    _refreshedThisCycle = false;
    stateNotifier.value = state.copyWith(
      status: DiscordRpcStatus.connected,
      errorMessage: null,
    );
    _debug('Gateway READY');
    // Fetch identity for display (best-effort).
    _fetchCurrentUser();
    // Publish current activity.
    _sendPresenceUpdate();
  }

  Future<void> _fetchCurrentUser() async {
    final token = _accessToken;
    if (token == null) return;
    try {
      final resp = await http.get(
        Uri.parse('$_apiBase/users/@me'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode < 200 || resp.statusCode >= 300) return;
      final user = jsonDecode(resp.body) as Map<String, dynamic>;
      final id = user['id'] as String?;
      final username = user['username'] as String?;
      final globalName = user['global_name'] as String?;
      final avatarHash = user['avatar'] as String?;
      String? avatarUrl;
      if (id != null && avatarHash != null && avatarHash.isNotEmpty) {
        avatarUrl =
            'https://cdn.discordapp.com/avatars/$id/$avatarHash.png?size=128';
      }

      final prefs = await SharedPreferences.getInstance();
      if (username != null) {
        await prefs.setString(_prefCachedUsernameKey, username);
      }
      if (globalName != null) {
        await prefs.setString(_prefCachedGlobalNameKey, globalName);
      }
      if (avatarUrl != null) {
        await prefs.setString(_prefCachedAvatarUrlKey, avatarUrl);
      }

      stateNotifier.value = state.copyWith(
        status: DiscordRpcStatus.connected,
        username: username,
        globalName: globalName,
        avatarUrl: avatarUrl,
      );
    } catch (e) {
      _debug('fetchCurrentUser failed: $e');
    }
  }

  // ── Playback → presence ────────────────────────────────────────────
  void updatePlayback({
    Track? track,
    bool isPlaying = false,
    Duration position = Duration.zero,
    Duration? duration,
  }) {
    final trackChanged = _currentTrack?.id != track?.id;
    final playStateChanged = _isPlaying != isPlaying;

    _currentTrack = track;
    _isPlaying = isPlaying;
    _currentPosition = position;
    _currentDuration = duration ?? track?.duration;

    if (state.status != DiscordRpcStatus.connected) return;
    if (trackChanged || playStateChanged) _triggerPresenceUpdate();
  }

  void _triggerPresenceUpdate() {
    _presenceDebounceTimer?.cancel();
    _presenceDebounceTimer =
        Timer(const Duration(milliseconds: 400), _sendPresenceUpdate);
  }

  Future<void> _sendPresenceUpdate() async {
    if (_webSocket == null || _webSocket!.readyState != WebSocket.open) return;

    final activities = await _buildActivityPayload();
    final payload = jsonEncode({
      'op': 3,
      'd': {
        'since': null,
        'activities': activities,
        'status': 'online',
        'afk': false,
      },
    });
    try {
      _webSocket!.add(payload);
    } catch (e) {
      _debug('Error sending presence: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _buildActivityPayload() async {
    final id = clientId;
    if (id == null || id.isEmpty) return [];
    if (!_isPlaying && _clearOnPause) return [];
    final track = _currentTrack;
    if (track == null) return [];

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final startEpochMs = nowMs - _currentPosition.inMilliseconds;
    final dur = _currentDuration ?? track.duration;
    final endEpochMs =
        (dur.inMilliseconds > 0) ? (startEpochMs + dur.inMilliseconds) : null;

    final activity = <String, dynamic>{
      'name': 'Inzx Music',
      'type': 2, // Listening to
      'application_id': id,
      'details': track.title.isNotEmpty ? track.title : 'Unknown Track',
      'state': track.artist.isNotEmpty ? track.artist : 'Inzx Music',
    };

    if (_showTimestamps && _isPlaying) {
      final timestamps = <String, dynamic>{'start': startEpochMs};
      if (endEpochMs != null && endEpochMs > startEpochMs) {
        timestamps['end'] = endEpochMs;
      }
      activity['timestamps'] = timestamps;
    }

    final assets = <String, dynamic>{};
    if (_showAlbumArt &&
        track.thumbnailUrl != null &&
        track.thumbnailUrl!.isNotEmpty) {
      String cover = track.thumbnailUrl!;
      if (cover.contains('=w') || cover.contains('=s')) {
        cover = cover.replaceAll(RegExp(r'=w\d+-h\d+.*'), '=w544-h544-l90-rj');
        cover = cover.replaceAll(RegExp(r'=s\d+.*'), '=s544');
      }
      final large = await _resolveAsset(cover);
      if (large != null) {
        assets['large_image'] = large;
        assets['large_text'] =
            (track.album != null && track.album!.isNotEmpty)
                ? track.album
                : track.title;
      }
    }
    final small = await _resolveAsset(
      'https://raw.githubusercontent.com/nirmaleeswar30/Inzx/main/assets/icon/logo_dark.png',
    );
    if (small != null) {
      assets['small_image'] = small;
      assets['small_text'] = 'Inzx Music';
    }
    if (assets.isNotEmpty) activity['assets'] = assets;

    return [activity];
  }

  /// Converts an external https image URL into an `mp:` asset ref that Rich
  /// Presence accepts for an OAuth application. Cached per URL.
  Future<String?> _resolveAsset(String url) async {
    if (_assetCache.containsKey(url)) return _assetCache[url];
    final id = clientId;
    final token = _accessToken;
    if (id == null || token == null) return null;
    try {
      final resp = await http
          .post(
            Uri.parse('$_apiBase/applications/$id/external-assets'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'urls': [url]}),
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      final list = jsonDecode(resp.body) as List<dynamic>;
      if (list.isEmpty) return null;
      final path = (list.first as Map<String, dynamic>)['external_asset_path']
          as String?;
      if (path == null) return null;
      final ref = 'mp:$path';
      _assetCache[url] = ref;
      return ref;
    } catch (e) {
      _debug('external-assets resolve failed: $e');
      return null;
    }
  }

  void _debug(String msg) {
    // Uses debugPrint so it also surfaces in profile/release logcat while we
    // diagnose the OAuth flow.
    debugPrint('[DiscordRpc] $msg');
  }
}
