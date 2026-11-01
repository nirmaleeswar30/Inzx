import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'addon_models.dart';

/// The shared client signing secret for LastWave addons. It's LastWave's
/// public default (the same value ships in their open-source client), so it
/// lives here rather than in a separate secrets file. A build can still
/// swap it with `--dart-define=LASTWAVE_CLIENT_SECRET=…` if LastWave issues
/// a different one; without a valid secret the server answers streams with
/// decoys (caught by [AddonClient.isDecoy]).
const String kAddonClientSecret = String.fromEnvironment(
  'LASTWAVE_CLIENT_SECRET',
  defaultValue:
      '36d96a751b12ee481c281a8a8e64c482d0c1634a22061ab72f40175017818b85',
);

bool get addonSigningConfigured => kAddonClientSecret.isNotEmpty;

/// Thrown for anything that keeps an addon from answering properly. Never
/// reaches playback: an addon failure just means no lossless upgrade.
class AddonException implements Exception {
  const AddonException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One installed addon, spoken to over the addon HTTP protocol.
class AddonClient {
  AddonClient(String rawUrl, {http.Client? httpClient})
    : baseUrl = normalizeBase(rawUrl),
      _http = httpClient ?? http.Client() {
    token = RegExp(r'/a/([^/]+)').firstMatch(Uri.parse(baseUrl).path)?.group(1);
  }

  /// Normalised base, without a trailing slash or endpoint suffix.
  final String baseUrl;

  /// The `/a/<token>` segment, when the addon uses tokenised URLs.
  late final String? token;

  final http.Client _http;

  static const _timeout = Duration(seconds: 10);

  /// Cleans whatever was pasted into the bare base URL: trims invisible
  /// characters, adds a scheme if missing, drops query/fragment, trailing
  /// slashes and a trailing `/manifest.json`, `/search` or `/stream`.
  static String normalizeBase(String raw) {
    var s = raw
        .replaceAll(RegExp('[​-‏﻿ \u0000-\u001F]'), '')
        .trim();
    if (s.isEmpty) return '';
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(s)) {
      s = 'https://$s';
    }
    s = s.split('#').first.split('?').first;
    s = s.replaceAll(RegExp(r'/+$'), '');
    s = s.replaceFirst(
      RegExp(r'/(?:manifest\.json|manifest|search|stream)$', caseSensitive: false),
      '',
    );
    return s.replaceAll(RegExp(r'/+$'), '');
  }

  /// Whether a pasted value looks like an addon URL at all.
  static bool looksValid(String raw) {
    final base = normalizeBase(raw);
    final uri = Uri.tryParse(base);
    return uri != null && uri.hasAuthority && uri.host.contains('.');
  }

  /// HMAC-SHA256 over `ts\nMETHOD\npath\ntoken`, hex lower-case. Null when
  /// there's no secret or no token to sign with.
  @visibleForTesting
  static Map<String, String>? signatureHeaders({
    required String secret,
    required String path,
    required String? token,
    String method = 'GET',
    DateTime? now,
  }) {
    if (secret.isEmpty || token == null || token.isEmpty) return null;
    final ts =
        ((now ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ 1000)
            .toString();
    final message = '$ts\n${method.toUpperCase()}\n$path\n$token';
    final sign = Hmac(
      sha256,
      utf8.encode(secret),
    ).convert(utf8.encode(message)).toString();
    return {'X-LW-TS': ts, 'X-LW-Sign': sign};
  }

  Map<String, String> _headers(Uri uri, {required bool download}) {
    return {
      'Accept': 'application/json',
      'X-LW-Intent': download ? 'download' : 'stream',
      'User-Agent': download ? 'LastWave-Downloader/1.0' : 'LastWave-Player/1.0',
      ...?signatureHeaders(
        secret: kAddonClientSecret,
        path: uri.path,
        token: token,
      ),
    };
  }

  Future<Object?> _getJson(Uri uri, {bool download = false}) async {
    final response = await _http
        .get(uri, headers: _headers(uri, download: download))
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw AddonException('HTTP ${response.statusCode} from ${uri.path}');
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const AddonException('Addon sent a response that isn\'t JSON');
    }
  }

  Future<AddonManifest> manifest() async {
    if (baseUrl.isEmpty) throw const AddonException('Empty addon URL');
    final json = await _getJson(Uri.parse('$baseUrl/manifest.json'));
    if (json is! Map<String, dynamic>) {
      throw const AddonException('Manifest is not a JSON object');
    }
    final manifest = AddonManifest.fromJson(json);
    if (manifest.id.isEmpty && manifest.name.isEmpty) {
      throw const AddonException('This URL doesn\'t serve an addon manifest');
    }
    return manifest;
  }

  Future<List<AddonTrack>> search(
    String query, {
    AddonQuality quality = AddonQuality.lossless,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final uri = Uri.parse('$baseUrl/search').replace(
      queryParameters: {'q': q, 'quality': quality.wire, 'atmos': 'none'},
    );
    final json = await _getJson(uri);
    final list = switch (json) {
      List l => l,
      Map m => (m['tracks'] ?? m['data'] ?? m['results'] ?? m['items']) as List?,
      _ => null,
    };
    return (list ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AddonTrack.fromJson)
        .where((t) => t.id.isNotEmpty)
        .toList();
  }

  Future<AddonStream> stream(
    String trackId, {
    AddonQuality quality = AddonQuality.lossless,
    bool download = false,
  }) async {
    final id = trackId.trim();
    if (id.isEmpty) throw const AddonException('Empty track id');
    final uri = Uri.parse(
      '$baseUrl/stream/${Uri.encodeComponent(id)}',
    ).replace(queryParameters: {'quality': quality.wire, 'atmos': 'none'});
    final json = await _getJson(uri, download: download);
    if (json is! Map<String, dynamic>) {
      throw const AddonException('Stream answer is not a JSON object');
    }
    if (isDecoy(json)) {
      throw AddonException(
        addonSigningConfigured
            ? 'The addon refused this request\'s signature'
            : 'This build has no addon signing secret',
      );
    }

    final inner = json['stream'] is Map<String, dynamic>
        ? json['stream'] as Map<String, dynamic>
        : json;
    final url = [
      inner['url'],
      inner['streamUrl'],
      inner['directUrl'],
      inner['mediaUrl'],
    ].whereType<String>().firstWhere((s) => s.isNotEmpty, orElse: () => '');
    if (url.isEmpty) throw const AddonException('Addon gave no stream URL');

    final format = '${inner['format'] ?? inner['manifest'] ?? ''}'.toLowerCase();
    final mime = '${inner['mimeType'] ?? ''}'.toLowerCase();
    final isDash =
        Uri.tryParse(url)?.path.toLowerCase().endsWith('.mpd') == true ||
        format == 'dash' ||
        mime.contains('dash');
    final bitrate = inner['bitrate'];

    return AddonStream(
      url: url,
      isDash: isDash,
      codec: '${inner['codec'] ?? 'flac'}',
      bitDepth: findBitDepth(inner) ?? findBitDepth(json),
      sampleRate: findSampleRate(inner) ?? findSampleRate(json),
      bitrate: bitrate is num ? bitrate.toInt() : null,
    );
  }

  /// The server answers a request it can't verify with HTTP 200 and a decoy
  /// clip on a "pranks" CDN rather than an error. Any URL-ish field pointing
  /// there means this answer must not be played.
  static bool isDecoy(Map<String, dynamic> json) {
    bool hit(Object? v) => v is String && v.contains('pranks-cdn');
    final inner = json['data'] is Map ? json['data'] as Map : const {};
    for (final key in const [
      'url',
      'directUrl',
      'streamUrl',
      'downloadUrl',
      'mediaUrl',
    ]) {
      if (hit(json[key]) || hit(inner[key])) return true;
    }
    return false;
  }

  void close() => _http.close();
}
