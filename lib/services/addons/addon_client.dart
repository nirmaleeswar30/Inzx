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

/// The addon answered, and doesn't have this (a 404, a 200 with an `error`
/// and no URL, or a stream it can't hand over). A settled miss, not a
/// fault: it's remembered instead of retried.
class AddonMiss extends AddonException {
  const AddonMiss(super.message);
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

  /// Whether this is a LastWave addon (a tokenised `/a/<token>` URL): only
  /// those get LastWave's signature and intent headers. Any other addon
  /// speaking the same protocol gets a plain request.
  bool get isLastWave => token != null && token!.isNotEmpty;

  Map<String, String> _headers(Uri uri, {required bool download}) {
    if (!isLastWave) {
      return const {'Accept': 'application/json', 'User-Agent': 'Inzx/1.0'};
    }
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

  /// One GET. A 404 is the protocol's "I don't have that" ([AddonMiss]),
  /// not a fault; a 429 is waited out (its `Retry-After`, else a doubling
  /// wait, both capped) rather than read as the addon lacking the track.
  Future<Object?> _getJson(Uri uri, {bool download = false}) async {
    for (var attempt = 0; ; attempt++) {
      final response = await _http
          .get(uri, headers: _headers(uri, download: download))
          .timeout(_timeout);
      final code = response.statusCode;
      if (code >= 200 && code < 300) {
        try {
          return jsonDecode(utf8.decode(response.bodyBytes));
        } on FormatException {
          throw const AddonException('Addon sent a response that isn\'t JSON');
        }
      }
      if (code == 404) throw AddonMiss('Not found: ${uri.path}');
      if (code == 429 && attempt < _maxRateLimitRetries) {
        await Future.delayed(_retryAfter(response.headers['retry-after'], attempt));
        continue;
      }
      throw AddonException('HTTP $code from ${uri.path}');
    }
  }

  static const _maxRateLimitRetries = 2;

  static Duration _retryAfter(String? header, int attempt) {
    final stated = double.tryParse(header?.trim() ?? '');
    final ms = stated != null ? (stated * 1000).round() : 1000 << attempt;
    return Duration(milliseconds: ms.clamp(500, 8000));
  }

  AddonManifest? _manifest;
  Future<AddonManifest?>? _manifestLoad;

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
    return _manifest = manifest;
  }

  /// The manifest if it can be had, read once; null when the addon has none.
  /// Only shapes the query parameters, so it never fails a request.
  Future<AddonManifest?> _manifestOrNull() =>
      _manifestLoad ??= _manifest != null
          ? Future.value(_manifest)
          : manifest().then<AddonManifest?>((m) => m).catchError((_) => null);

  /// Whether `/search` answers like an addon: for addons that publish no
  /// manifest, which are still perfectly good addons.
  Future<bool> probeSearch() async {
    try {
      await search('love');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The parameters every request carries. The addon's own declared
  /// defaults first (what its reference host sends untouched), then
  /// `quality` set to what's wanted — in the addon's own vocabulary when it
  /// lists one, since `quality=lossless` to an addon offering
  /// `hifi|high|low` is an invalid value that lands on its fallback. Atmos
  /// is never wanted here (a different mix, not a better copy).
  Future<Map<String, String>> _params(AddonQuality quality) async {
    final declared = (await _manifestOrNull())?.settings ?? const <AddonSetting>[];
    final params = <String, String>{
      for (final s in declared)
        if (s.defaultValue != null) s.key: s.defaultValue!,
    };
    final qualityOptions = declared
        .where((s) => s.key == 'quality')
        .expand((s) => s.options)
        .toList();
    params['quality'] = matchQuality(quality, qualityOptions) ?? quality.wire;
    final atmos = declared.where((s) => s.key == 'atmos').firstOrNull;
    params['atmos'] = atmos == null
        ? 'none'
        : atmos.options.firstWhere(
            (o) => RegExp(r'^(0|false|off|no|none|never|stereo)$', caseSensitive: false)
                .hasMatch(o),
            orElse: () => '0',
          );
    return params;
  }

  /// The option in [options] that best answers [quality], or null when the
  /// addon enumerated none. Matched on what an option says, not its
  /// position; failing that, the first listed (the addon's recommended).
  @visibleForTesting
  static String? matchQuality(AddonQuality quality, List<String> options) {
    if (options.isEmpty) return null;
    for (final o in options) {
      if (o.toLowerCase() == quality.wire) return o;
    }
    if (quality == AddonQuality.hiRes) {
      const hiResWords = [
        'hi_res',
        'hires',
        'hi-res',
        'hi res',
        'max',
        'master',
        '24bit',
        '24-bit',
        '24',
      ];
      for (final o in options) {
        final lower = o.toLowerCase();
        if (hiResWords.any(lower.contains)) return o;
      }
      // Asked for hi-res on an addon with no hi-res tier: its lossless one.
      return matchQuality(AddonQuality.lossless, options);
    }

    const losslessWords = [
      'lossless',
      'flac',
      'alac',
      'hifi',
      'hi-fi',
      'cd',
      '16bit',
      '16-bit',
      '16',
    ];
    for (final o in options) {
      final lower = o.toLowerCase();
      if (losslessWords.any(lower.contains)) return o;
    }

    // High quality fallback if no lossless label
    const highWords = ['high', 'hq', 'best'];
    for (final o in options) {
      final lower = o.toLowerCase();
      if (highWords.any(lower.contains)) return o;
    }

    return options.first;
  }

  Future<List<AddonTrack>> search(
    String query, {
    AddonQuality quality = AddonQuality.lossless,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final uri = Uri.parse('$baseUrl/search').replace(
      queryParameters: {...await _params(quality), 'q': q},
    );
    final Object? json;
    try {
      json = await _getJson(uri);
    } on AddonMiss {
      return const []; // nothing for this query
    }
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
    ).replace(queryParameters: await _params(quality));
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
    return parseStream(json, assumeFlac: isLastWave);
  }

  /// A `/stream` answer, read leniently. [assumeFlac] is for LastWave's own
  /// addon, which leaves `codec` out and means FLAC by it; any other addon
  /// is only taken as lossless when something in its answer says so, so a
  /// bare MP3 can never be passed off as FLAC.
  @visibleForTesting
  static AddonStream parseStream(
    Map<String, dynamic> json, {
    required bool assumeFlac,
  }) {
    final inner = json['stream'] is Map<String, dynamic>
        ? json['stream'] as Map<String, dynamic>
        : json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;

    if (inner['success'] == false || json['success'] == false) {
      final why = inner['error'] ??
          json['error'] ??
          inner['message'] ??
          json['message'];
      throw AddonMiss(
        why is String && why.isNotEmpty ? why : 'Addon reported unsuccessful',
      );
    }

    final url = [
      inner['url'],
      inner['streamUrl'],
      inner['streamURL'],
      inner['directUrl'],
      inner['mediaUrl'],
      inner['dataUrl'],
    ].whereType<String>().firstWhere((s) => s.isNotEmpty, orElse: () => '');
    if (url.isEmpty) {
      // Addons answer a track they can't serve with 200 + {"error": …} as
      // often as with a 404; both are a miss, not a fault.
      final why = inner['error'] ??
          json['error'] ??
          inner['message'] ??
          json['message'];
      throw AddonMiss(why is String && why.isNotEmpty ? why : 'No stream URL');
    }

    if (_isDrmProtected(inner) || _isDrmProtected(json)) {
      throw const AddonMiss('DRM-protected stream');
    }

    final format = '${inner['format'] ?? inner['container'] ?? ''}'.toLowerCase();
    final transport =
        '${inner['manifest'] ?? inner['mediaType'] ?? ''}'.toLowerCase();
    final mime = '${inner['mimeType'] ?? inner['contentType'] ?? ''}'.toLowerCase();
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    final isDash = path.endsWith('.mpd') ||
        format == 'dash' ||
        transport == 'dash' ||
        mime.contains('dash');
    final bitrate = inner['bitrate'];

    return AddonStream(
      url: url,
      isDash: isDash,
      codec: _codecOf(inner, format, mime, path, assumeFlac: assumeFlac),
      bitDepth: findBitDepth(inner) ?? findBitDepth(json),
      sampleRate: findSampleRate(inner) ?? findSampleRate(json),
      bitrate: bitrate is num ? bitrate.toInt() : null,
    );
  }

  /// Whether a stream object indicates DRM protection or encryption that cannot
  /// be played cleanly by our audio engine without external CDM licenses.
  static bool _isDrmProtected(Map<String, dynamic> map) {
    bool isTruthy(Object? v) {
      if (v == null || v == false) return false;
      final s = '$v'.trim().toLowerCase();
      return s.isNotEmpty && s != 'false' && s != 'no' && s != 'none' && s != '0';
    }

    if (isTruthy(map['drm']) ||
        isTruthy(map['isDrm']) ||
        isTruthy(map['is_drm']) ||
        isTruthy(map['encrypted']) ||
        isTruthy(map['isEncrypted']) ||
        isTruthy(map['is_encrypted'])) {
      return true;
    }

    final license = map['licenseUrl'] ??
        map['license_url'] ??
        map['keySystem'] ??
        map['key_system'];
    if (license is String && license.trim().isNotEmpty) return true;

    final protection =
        '${map['protection'] ?? map['encryption'] ?? ''}'.toLowerCase();
    if (protection.contains('drm') ||
        protection.contains('widevine') ||
        protection.contains('fairplay') ||
        protection.contains('playready')) {
      return true;
    }

    return false;
  }

  /// The codec, from the first thing in the answer that names one: the
  /// codec fields, the format, the MIME type, the file extension, then the
  /// quality words. Empty when nothing does (and the addon isn't LastWave).
  static String _codecOf(
    Map<String, dynamic> inner,
    String format,
    String mime,
    String path, {
    required bool assumeFlac,
  }) {
    String? named(String text) {
      final t = text.toLowerCase();
      if (t.contains('flac')) return 'flac';
      if (t.contains('alac')) return 'alac';
      if (t.contains('wav')) return 'wav';
      if (t.contains('aiff')) return 'aiff';
      if (t.contains('opus')) return 'opus';
      if (t.contains('mp3') || t.contains('mpeg')) return 'mp3';
      if (t.contains('aac') || t.contains('mp4a') || t.contains('m4a')) return 'aac';
      if (t.contains('vorbis') || t.contains('ogg')) return 'vorbis';
      return null;
    }

    for (final field in [
      inner['codec'],
      inner['fileCodec'],
      inner['audioCodec'],
      inner['format'],
      inner['container'],
      inner['encoding'],
    ]) {
      if (field is String && field.trim().isNotEmpty) {
        final n = named(field);
        if (n != null) return n;
      }
    }
    final file = path.split('/').last;
    final extension = file.contains('.') ? file.split('.').last : '';
    final fromFormat = named(format) ?? named(mime) ?? named(extension);
    if (fromFormat != null) return fromFormat;
    final qualityText = [
      inner['quality'],
      inner['streamQuality'],
      inner['audioQuality'],
      inner['audio_quality'],
    ].whereType<String>().join(' ');
    if (losslessText.hasMatch(qualityText)) return 'flac';
    return assumeFlac ? 'flac' : '';
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
