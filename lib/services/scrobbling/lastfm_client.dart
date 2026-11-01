import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Inzx's Last.fm API application. Get a key and secret at
/// https://www.last.fm/api/account/create and pass them at build time:
/// `--dart-define=LASTFM_API_KEY=… --dart-define=LASTFM_API_SECRET=…`.
/// Users can also enter their own in the Scrobbling screen.
const String kLastFmApiKey = String.fromEnvironment('LASTFM_API_KEY');
const String kLastFmApiSecret = String.fromEnvironment('LASTFM_API_SECRET');

class LastFmException implements Exception {
  const LastFmException(this.code, this.message);
  final int code;
  final String message;
  @override
  String toString() => message;
}

/// The Last.fm (or Libre.fm) scrobbling API: web or username sign-in, now
/// playing, scrobble. Every call is signed with `api_sig`: the MD5 of the
/// parameters sorted by name, concatenated as name+value, then the secret.
class LastFmClient {
  LastFmClient({
    required this.apiKey,
    required this.secret,
    this.endpoint = defaultEndpoint,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  static const defaultEndpoint = 'https://ws.audioscrobbler.com/2.0/';
  static const libreFmEndpoint = 'https://libre.fm/2.0/';

  final String apiKey;
  final String secret;
  final String endpoint;
  final http.Client _http;

  bool get isConfigured => apiKey.isNotEmpty && secret.isNotEmpty;

  static String signature(Map<String, String> params, String secret) {
    final keys = params.keys
        .where((k) => k != 'format' && k != 'callback')
        .toList()
      ..sort();
    final raw = StringBuffer();
    for (final k in keys) {
      raw
        ..write(k)
        ..write(params[k]);
    }
    raw.write(secret);
    return md5.convert(utf8.encode(raw.toString())).toString();
  }

  Future<Map<String, dynamic>> _call(
    String method, {
    Map<String, String> params = const {},
    String? sessionKey,
  }) async {
    if (!isConfigured) {
      throw const LastFmException(10, 'No Last.fm API key is set up');
    }
    final body = <String, String>{
      ...params,
      'method': method,
      'api_key': apiKey,
      if (sessionKey != null) 'sk': sessionKey,
    };
    body['api_sig'] = signature(body, secret);
    body['format'] = 'json';

    final response = await _http
        .post(
          Uri.parse(endpoint),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'User-Agent': 'Inzx (https://inzx.nirmaleeswar.dev)',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 15));
    Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw LastFmException(
        response.statusCode,
        'Last.fm sent an unreadable answer (HTTP ${response.statusCode})',
      );
    }
    if (json['error'] != null) {
      throw LastFmException(
        (json['error'] as num).toInt(),
        json['message']?.toString() ?? 'Last.fm error ${json['error']}',
      );
    }
    return json;
  }

  // ---- Sign-in ------------------------------------------------------

  /// Step 1 of browser sign-in: a request token to approve.
  Future<String> getToken() async {
    final json = await _call('auth.getToken');
    return json['token'] as String;
  }

  /// The page where the user approves [token].
  Uri authUrl(String token) => endpoint.contains('libre.fm')
      ? Uri.parse('https://libre.fm/api/auth?api_key=$apiKey&token=$token')
      : Uri.parse('https://www.last.fm/api/auth/?api_key=$apiKey&token=$token');

  /// Step 2: once approved, trade the token for a session.
  Future<LastFmSession> getSession(String token) async {
    final json = await _call('auth.getSession', params: {'token': token});
    return LastFmSession.fromJson(json['session'] as Map<String, dynamic>);
  }

  /// Username/password sign-in (the "mobile session" flow).
  Future<LastFmSession> getMobileSession(
    String username,
    String password,
  ) async {
    final json = await _call(
      'auth.getMobileSession',
      params: {'username': username, 'password': password},
    );
    return LastFmSession.fromJson(json['session'] as Map<String, dynamic>);
  }

  // ---- Scrobbling ---------------------------------------------------

  Future<void> updateNowPlaying({
    required String sessionKey,
    required String artist,
    required String track,
    String? album,
    int? durationSeconds,
  }) async {
    await _call(
      'track.updateNowPlaying',
      sessionKey: sessionKey,
      params: {
        'artist': artist,
        'track': track,
        if (album != null && album.isNotEmpty) 'album': album,
        if (durationSeconds != null && durationSeconds > 0)
          'duration': '$durationSeconds',
      },
    );
  }

  Future<void> scrobble({
    required String sessionKey,
    required String artist,
    required String track,
    required int timestamp,
    String? album,
    int? durationSeconds,
  }) async {
    await _call(
      'track.scrobble',
      sessionKey: sessionKey,
      params: {
        'artist': artist,
        'track': track,
        'timestamp': '$timestamp',
        if (album != null && album.isNotEmpty) 'album': album,
        if (durationSeconds != null && durationSeconds > 0)
          'duration': '$durationSeconds',
      },
    );
  }
}

class LastFmSession {
  const LastFmSession({required this.name, required this.key});
  final String name;
  final String key;

  factory LastFmSession.fromJson(Map<String, dynamic> json) =>
      LastFmSession(name: json['name'] as String, key: json['key'] as String);
}
