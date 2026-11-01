import 'dart:convert';

import 'package:http/http.dart' as http;

class ListenBrainzException implements Exception {
  const ListenBrainzException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// ListenBrainz submissions with the user's own token (from
/// https://listenbrainz.org/settings/).
class ListenBrainzClient {
  ListenBrainzClient({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  static const _base = 'https://api.listenbrainz.org/1';
  final http.Client _http;

  /// The account name the token belongs to, or null if it isn't valid.
  Future<String?> validateToken(String token) async {
    final response = await _http
        .get(
          Uri.parse('$_base/validate-token'),
          headers: {'Authorization': 'Token $token'},
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['valid'] == true ? json['user_name'] as String? : null;
  }

  Future<void> playingNow({
    required String token,
    required String artist,
    required String track,
    String? album,
    int? durationMs,
  }) => _submit(token, 'playing_now', {
    'track_metadata': _metadata(artist, track, album, durationMs),
  });

  Future<void> listened({
    required String token,
    required String artist,
    required String track,
    required int listenedAt,
    String? album,
    int? durationMs,
  }) => _submit(token, 'single', {
    'listened_at': listenedAt,
    'track_metadata': _metadata(artist, track, album, durationMs),
  });

  Map<String, dynamic> _metadata(
    String artist,
    String track,
    String? album,
    int? durationMs,
  ) => {
    'artist_name': artist,
    'track_name': track,
    if (album != null && album.isNotEmpty) 'release_name': album,
    'additional_info': {
      if (durationMs != null && durationMs > 0) 'duration_ms': durationMs,
      'submission_client': 'Inzx',
      'media_player': 'Inzx',
      'music_service': 'music.youtube.com',
    },
  };

  Future<void> _submit(
    String token,
    String type,
    Map<String, dynamic> listen,
  ) async {
    final response = await _http
        .post(
          Uri.parse('$_base/submit-listens'),
          headers: {
            'Authorization': 'Token $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'listen_type': type,
            'payload': [listen],
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw ListenBrainzException(
        'ListenBrainz HTTP ${response.statusCode}: ${response.body}',
      );
    }
  }
}
