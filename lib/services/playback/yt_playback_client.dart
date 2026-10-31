import 'dart:convert';
import 'package:flutter/foundation.dart' show compute, kDebugMode;
import 'package:http/http.dart' as http;

/// InnerTube client configuration with content-aware fallback strategy.
///
/// Versions, device profiles and endpoints track Metrolist's innertubex
/// (2026-10) and BitChord: stale web/TV versions and sending the VR/visionOS
/// clients to www.youtube.com are what made every client fail at once.
class InnerTubeClient {
  final String name;
  final String version;

  /// X-YouTube-Client-Name.
  final String clientId;
  final String userAgent;
  final Map<String, dynamic> context;
  final bool useWebPoTokens;
  final bool supportsSignatureCipher;

  /// Player requests go to music.youtube.com instead of www.youtube.com.
  final bool useMusicPlayerEndpoint;

  /// Embedded player (thirdParty.embedUrl, reddit referer).
  final bool isEmbedded;

  const InnerTubeClient({
    required this.name,
    required this.version,
    required this.clientId,
    required this.userAgent,
    required this.context,
    this.useWebPoTokens = false,
    this.supportsSignatureCipher = false,
    this.useMusicPlayerEndpoint = false,
    this.isEmbedded = false,
  });

  /// Request headers for this client's InnerTube calls.
  Map<String, String> get headers => {
    'User-Agent': userAgent,
    'X-YouTube-Client-Name': clientId,
    'X-YouTube-Client-Version': version,
  };

  static Map<String, dynamic> _context(Map<String, dynamic> client) => {
    'client': {...client, 'hl': 'en', 'gl': 'US'},
    'user': {'lockedSafetyMode': false},
  };

  static const String _webUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0';
  static const String _tvUserAgent =
      'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold '
      '(unlike Gecko), Unknown_TV_Unknown_0/Unknown (Unknown, Unknown)';

  /// VISIONOS 1.02 — current visionOS profile; no cipher / PoToken.
  static final visionOs = InnerTubeClient(
    name: 'VISIONOS',
    version: '1.02',
    clientId: '101',
    userAgent:
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 '
        '(KHTML, like Gecko) Version/26.0 Safari/605.1.15',
    context: _context({
      'clientName': 'VISIONOS',
      'clientVersion': '1.02',
      'osName': 'visionOS',
      'osVersion': '26.5.23O471',
      'deviceMake': 'Apple',
      'deviceModel': 'RealityDevice17,1',
    }),
    useMusicPlayerEndpoint: true,
  );

  /// VISIONOS 0.1 — the original unreleased build, kept as a fallback.
  static final visionOs01 = InnerTubeClient(
    name: 'VISIONOS_0_1',
    version: '0.1',
    clientId: '101',
    userAgent:
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6) AppleWebKit/605.1.15 '
        '(KHTML, like Gecko) Version/17.5 Safari/605.1.15',
    context: _context({
      'clientName': 'VISIONOS',
      'clientVersion': '0.1',
      'osName': 'VISION_OS',
      'osVersion': '1.3',
      'deviceMake': 'Apple',
      'deviceModel': 'RealityDevice14,1',
      'platform': 'MOBILE',
    }),
    useMusicPlayerEndpoint: true,
  );

  static InnerTubeClient _androidVr({
    required String name,
    required String version,
    required String userAgent,
    required String osVersion,
  }) => InnerTubeClient(
    name: name,
    version: version,
    clientId: '28',
    userAgent: userAgent,
    context: _context({
      'clientName': 'ANDROID_VR',
      'clientVersion': version,
      'osName': 'Android',
      'osVersion': osVersion,
      'deviceMake': 'Oculus',
      'deviceModel': 'Quest 3',
      'androidSdkVersion': 32,
      'userAgent': userAgent,
    }),
    useMusicPlayerEndpoint: true,
  );

  /// ANDROID_VR 1.65 — no cipher / PoToken, very reliable.
  static final androidVr165 = _androidVr(
    name: 'ANDROID_VR',
    version: '1.65.10',
    osVersion: '12L',
    userAgent:
        'com.google.android.apps.youtube.vr.oculus/1.65.10 '
        '(Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
  );

  /// ANDROID_VR 1.43 — non-adaptive bitrate, avoids audio stutter.
  static final androidVr143 = _androidVr(
    name: 'ANDROID_VR_143',
    version: '1.43.32',
    osVersion: '12',
    userAgent:
        'com.google.android.apps.youtube.vr.oculus/1.43.32 '
        '(Linux; U; Android 12; en_US; Quest 3; Build/SQ3A.220605.009.A1; '
        'Cronet/107.0.5284.2)',
  );

  /// ANDROID_VR 1.61.
  static final androidVr161 = _androidVr(
    name: 'ANDROID_VR_161',
    version: '1.61.48',
    osVersion: '12',
    userAgent:
        'com.google.android.apps.youtube.vr.oculus/1.61.48 '
        '(Linux; U; Android 12; en_US; Quest 3; Build/SQ3A.220605.009.A1; '
        'Cronet/132.0.6808.3)',
  );

  /// WEB_REMIX — YouTube Music web (needs poToken + cipher).
  static final webRemix = InnerTubeClient(
    name: 'WEB_REMIX',
    version: '1.20260707.12.00',
    clientId: '67',
    userAgent: _webUserAgent,
    context: _context({
      'clientName': 'WEB_REMIX',
      'clientVersion': '1.20260707.12.00',
    }),
    useWebPoTokens: true,
    supportsSignatureCipher: true,
    useMusicPlayerEndpoint: true,
  );

  /// TVHTML5 — TV client (needs cipher).
  static final tvhtml5 = InnerTubeClient(
    name: 'TVHTML5',
    version: '7.20260707.07.00',
    clientId: '7',
    userAgent: _tvUserAgent,
    context: _context({
      'clientName': 'TVHTML5',
      'clientVersion': '7.20260707.07.00',
      'userAgent': _tvUserAgent,
    }),
    useWebPoTokens: true,
    supportsSignatureCipher: true,
  );

  /// TVHTML5_SIMPLY — simple TV (needs cipher + poToken).
  static final tvhtml5Simply = InnerTubeClient(
    name: 'TVHTML5_SIMPLY',
    version: '1.0',
    clientId: '75',
    userAgent: _tvUserAgent,
    context: _context({
      'clientName': 'TVHTML5_SIMPLY',
      'clientVersion': '1.0',
    }),
    useWebPoTokens: true,
    supportsSignatureCipher: true,
    useMusicPlayerEndpoint: true,
  );

  /// TVHTML5_SIMPLY_EMBEDDED_PLAYER — can bypass age restriction.
  static final tvEmbedded = InnerTubeClient(
    name: 'TVHTML5_SIMPLY_EMBEDDED_PLAYER',
    version: '2.0',
    clientId: '85',
    userAgent: _tvUserAgent,
    context: {
      ..._context({
        'clientName': 'TVHTML5_SIMPLY_EMBEDDED_PLAYER',
        'clientVersion': '2.0',
      }),
      'thirdParty': {'embedUrl': 'https://www.reddit.com/'},
    },
    useWebPoTokens: true,
    supportsSignatureCipher: true,
    isEmbedded: true,
  );

  /// WEB_CREATOR — YouTube Studio web client (login required).
  static final webCreator = InnerTubeClient(
    name: 'WEB_CREATOR',
    version: '1.20260708.06.00',
    clientId: '62',
    userAgent: _webUserAgent,
    context: _context({
      'clientName': 'WEB_CREATOR',
      'clientVersion': '1.20260708.06.00',
    }),
    useWebPoTokens: true,
    supportsSignatureCipher: true,
  );

  /// WEB — regular YouTube web client.
  static final web = InnerTubeClient(
    name: 'WEB',
    version: '2.20260708.00.00',
    clientId: '1',
    userAgent: _webUserAgent,
    context: _context({
      'clientName': 'WEB',
      'clientVersion': '2.20260708.00.00',
    }),
    useWebPoTokens: true,
    supportsSignatureCipher: true,
  );

  /// IOS — direct URLs.
  static final ios = InnerTubeClient(
    name: 'IOS',
    version: '21.26.4',
    clientId: '5',
    userAgent:
        'com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
    context: _context({
      'clientName': 'IOS',
      'clientVersion': '21.26.4',
      'deviceMake': 'Apple',
      'deviceModel': 'iPhone16,2',
      'osName': 'iPhone',
      'osVersion': '18.3.2.22D82',
    }),
  );

  /// ANDROID_MUSIC — YouTube Music Android app.
  static final androidMusic = InnerTubeClient(
    name: 'ANDROID_MUSIC',
    version: '8.39.42',
    clientId: '21',
    userAgent:
        'com.google.android.apps.youtube.music/8.39.42 '
        '(Linux; U; Android 15; en_US; Pixel 9 Pro; Build/AP4A.250205.002) gzip',
    context: _context({
      'clientName': 'ANDROID_MUSIC',
      'clientVersion': '8.39.42',
      'androidSdkVersion': 35,
      'osName': 'Android',
      'osVersion': '15',
    }),
  );

  /// Default playback client order (content-aware fallback). Starts with
  /// clients that don't need cipher / PoToken — Metrolist's automatic order.
  static List<InnerTubeClient> get playbackClients => defaultClients;

  /// Content-aware fallback: choose clients based on content type
  static List<InnerTubeClient> getClientsForContent({
    bool isUploaded = false,
    bool isExplicit = false,
    bool isKidsContent = false,
    bool isLive = false,
  }) {
    if (isUploaded) return uploadedClients;
    if (isLive) return liveClients;
    if (isKidsContent) return kidsClients;
    if (isExplicit) return explicitClients;
    return defaultClients;
  }

  static final List<InnerTubeClient> defaultClients = List.unmodifiable([
    visionOs,
    visionOs01,
    androidVr165,
    androidVr143,
    androidVr161,
    tvhtml5,
    webRemix,
    tvhtml5Simply,
  ]);

  static final List<InnerTubeClient> uploadedClients = List.unmodifiable([
    tvhtml5,
    webRemix,
    webCreator,
  ]);

  static final List<InnerTubeClient> explicitClients = List.unmodifiable([
    visionOs,
    tvhtml5,
    tvEmbedded,
    webRemix,
  ]);

  static final List<InnerTubeClient> kidsClients = List.unmodifiable([
    tvhtml5,
    webRemix,
    tvhtml5Simply,
    webCreator,
  ]);

  static final List<InnerTubeClient> liveClients = List.unmodifiable([
    tvhtml5,
    webRemix,
    webCreator,
    tvhtml5Simply,
  ]);

  /// Client for METADATA - separate from playback to reduce fingerprinting
  static InnerTubeClient get metadataClient => webRemix;

  /// Headers for fetching a googlevideo stream URL: the user agent (and for
  /// web clients the origin) of the client that produced it, which the URL
  /// names in its `c` / `cver` parameters. A mismatched user agent gets
  /// throttled or refused.
  static Map<String, String> streamHeadersFor(Uri url) {
    if (!url.host.endsWith('googlevideo.com')) return const {};
    final name = url.queryParameters['c']?.toUpperCase();
    final cver = url.queryParameters['cver'];
    InnerTubeClient client;
    if (name == null) {
      return const {};
    } else if (name == 'ANDROID_VR') {
      client = [androidVr143, androidVr161].firstWhere(
        (c) => c.version == cver,
        orElse: () => androidVr165,
      );
    } else if (name == 'VISIONOS') {
      client = cver == visionOs01.version ? visionOs01 : visionOs;
    } else if (name.startsWith('TVHTML5')) {
      client = tvhtml5;
    } else if (name == 'WEB_REMIX') {
      return {
        'User-Agent': webRemix.userAgent,
        'Origin': 'https://music.youtube.com',
        'Referer': 'https://music.youtube.com/',
      };
    } else if (name.startsWith('WEB') || name == 'MWEB') {
      return {
        'User-Agent': web.userAgent,
        'Origin': 'https://www.youtube.com',
        'Referer': 'https://www.youtube.com/',
      };
    } else if (name == 'ANDROID_MUSIC') {
      client = androidMusic;
    } else if (name.startsWith('IOS')) {
      client = ios;
    } else {
      return const {};
    }
    return {'User-Agent': client.userAgent};
  }
}

/// Playability status from YouTube
class PlayabilityStatus {
  final String status;
  final String? reason;
  final bool isPlayable;
  final bool requiresLogin;
  final bool isAgeRestricted;
  final bool isLiveContent;

  const PlayabilityStatus({
    required this.status,
    this.reason,
    required this.isPlayable,
    this.requiresLogin = false,
    this.isAgeRestricted = false,
    this.isLiveContent = false,
  });

  factory PlayabilityStatus.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const PlayabilityStatus(status: 'UNKNOWN', isPlayable: false);
    }

    final status = json['status'] as String? ?? 'UNKNOWN';
    final reason =
        json['reason'] as String? ??
        (json['messages'] as List?)?.firstOrNull as String?;

    return PlayabilityStatus(
      status: status,
      reason: reason,
      isPlayable: status == 'OK',
      requiresLogin: reason?.contains('Sign in') == true,
      isAgeRestricted: json['reasonTitle']?.toString().contains('age') == true,
      isLiveContent: json['liveStreamability'] != null,
    );
  }
}

/// Player response from InnerTube API
class PlayerResponse {
  final PlayabilityStatus playabilityStatus;
  final Map<String, dynamic>? streamingData;
  final Map<String, dynamic>? videoDetails;
  final Map<String, dynamic>? playerConfig;
  final Map<String, dynamic>? playbackTracking;
  final String? poToken;

  const PlayerResponse({
    required this.playabilityStatus,
    this.streamingData,
    this.videoDetails,
    this.playerConfig,
    this.playbackTracking,
    this.poToken,
  });

  bool get hasStreamingData => streamingData != null;
  bool get hasAdaptiveFormats =>
      (streamingData?['adaptiveFormats'] as List?)?.isNotEmpty == true;

  factory PlayerResponse.fromJson(Map<String, dynamic> json) {
    return PlayerResponse(
      playabilityStatus: PlayabilityStatus.fromJson(
        json['playabilityStatus'] as Map<String, dynamic>?,
      ),
      streamingData: json['streamingData'] as Map<String, dynamic>?,
      videoDetails: json['videoDetails'] as Map<String, dynamic>?,
      playerConfig: json['playerConfig'] as Map<String, dynamic>?,
      playbackTracking: json['playbackTracking'] as Map<String, dynamic>?,
    );
  }

  PlayerResponse withPoToken(String token) {
    return PlayerResponse(
      playabilityStatus: playabilityStatus,
      streamingData: streamingData,
      videoDetails: videoDetails,
      playerConfig: playerConfig,
      playbackTracking: playbackTracking,
      poToken: token,
    );
  }
}

/// YouTube InnerTube API wrapper
class InnerTubeApi {
  static const String _playerApiUrl =
      'https://www.youtube.com/youtubei/v1/player';
  static const String _musicPlayerApiUrl =
      'https://music.youtube.com/youtubei/v1/player';

  final http.Client _client;

  InnerTubeApi({http.Client? client}) : _client = client ?? http.Client();

  /// Get player response for a video
  /// Includes visitorData header for bot protection binding
  Future<PlayerResponse?> player(
    String videoId, {
    String? playlistId,
    InnerTubeClient? client,
    int? signatureTimestamp,
    String? poToken,
    String? visitorData,
  }) async {
    final innerTubeClient = client ?? InnerTubeClient.visionOs;

    // Endpoint and origin as YouTube's own clients use them (Metrolist
    // innertubex): the VR / visionOS / Simply / WEB_REMIX clients talk to
    // music.youtube.com, the rest to www.youtube.com. No API key.
    final musicEndpoint = innerTubeClient.useMusicPlayerEndpoint;
    final baseUrl = musicEndpoint ? _musicPlayerApiUrl : _playerApiUrl;
    final origin = musicEndpoint
        ? 'https://music.youtube.com'
        : 'https://www.youtube.com';

    try {
      final url = Uri.parse('$baseUrl?prettyPrint=false');

      final headers = {
        'Content-Type': 'application/json',
        'Accept-Encoding': 'gzip, deflate',
        'Accept-Language': 'en-US,en;q=0.9',
        'X-Goog-Api-Format-Version': '1',
        'Origin': origin,
        'X-Origin': origin,
        'Referer': innerTubeClient.isEmbedded
            ? 'https://www.reddit.com/'
            : '$origin/',
        ...innerTubeClient.headers,
      };

      // Add visitorData header for binding
      if (visitorData != null && visitorData.isNotEmpty) {
        headers['X-Goog-Visitor-Id'] = visitorData;
      }

      // Build context with visitorData embedded
      // Copy the client map too: it's shared by every request for this client.
      final context = Map<String, dynamic>.from(innerTubeClient.context);
      final clientContext = Map<String, dynamic>.from(
        context['client'] as Map<String, dynamic>,
      );
      if (visitorData != null && visitorData.isNotEmpty) {
        clientContext['visitorData'] = visitorData;
      }
      context['client'] = clientContext;

      final body = <String, dynamic>{
        'context': context,
        'videoId': videoId,
        'racyCheckOk': true,
        'contentCheckOk': true,
        if (!musicEndpoint) 'videoCheckOk': true,
      };

      if (playlistId != null) {
        body['playlistId'] = playlistId;
      }

      if (innerTubeClient.supportsSignatureCipher || innerTubeClient.isEmbedded) {
        body['playbackContext'] = {
          'contentPlaybackContext': {
            if (!musicEndpoint) 'html5Preference': 'HTML5_PREF_WANTS',
            if (signatureTimestamp != null &&
                innerTubeClient.supportsSignatureCipher)
              'signatureTimestamp': signatureTimestamp,
          },
        };
      }

      // Add serviceIntegrityDimensions if poToken provided (for web clients)
      if (poToken != null &&
          poToken.isNotEmpty &&
          innerTubeClient.useWebPoTokens) {
        body['serviceIntegrityDimensions'] = {'poToken': poToken};
      }

      if (kDebugMode) {
        print(
          'InnerTubeApi: Requesting player for $videoId with ${innerTubeClient.name}',
        );
      }

      final response = await _client
          .post(url, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        // Decode JSON in background isolate to avoid UI jank during prefetch
        final json = await compute(_jsonDecodeIsolate, response.body);
        return PlayerResponse.fromJson(json);
      } else {
        if (kDebugMode) {
          print('InnerTubeApi: HTTP ${response.statusCode} for $videoId');
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        print('InnerTubeApi: Error getting player for $videoId: $e');
      }
      return null;
    }
  }

  static int? _cachedSignatureTimestamp;
  static DateTime? _cachedSignatureTimestampAt;

  /// Get signature timestamp from embed page or player JS.
  ///
  /// BitChord/MetroList approach: first try the embed page for a quick inline
  /// `"sts"` value, then fall back to fetching the actual player base.js and
  /// extracting `signatureTimestamp: <number>` from it. YouTube has stopped
  /// including STS in page HTML on some builds, so the player JS path is the
  /// reliable source. Cached for 6 hours so base.js isn't repeatedly fetched.
  Future<int> getSignatureTimestamp(String videoId, {bool refresh = false}) async {
    final cachedAt = _cachedSignatureTimestampAt;
    if (!refresh &&
        _cachedSignatureTimestamp != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < const Duration(hours: 6)) {
      return _cachedSignatureTimestamp!;
    }
    const ua =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
    try {
      final response = await _client
          .get(
            Uri.parse('https://www.youtube.com/embed/$videoId'),
            headers: {'User-Agent': ua},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = response.body;

        // Try inline STS first (fast path).
        final match = RegExp(r'"sts"\s*:\s*(\d+)').firstMatch(body);
        if (match != null) {
          final sts = int.tryParse(match.group(1)!);
          if (sts != null) {
            _cachedSignatureTimestamp = sts;
            _cachedSignatureTimestampAt = DateTime.now();
            return sts;
          }
        }

        // No inline STS — extract from the player JS referenced in the page.
        final jsUrlMatch =
            RegExp(r'"jsUrl"\s*:\s*"([^"]+)"').firstMatch(body) ??
            RegExp(r'(/s/player/[^"]+/base\.js)').firstMatch(body);
        if (jsUrlMatch != null) {
          var jsPath = jsUrlMatch.group(1)!.replaceAll(r'\/', '/');
          if (jsPath.startsWith('/')) {
            jsPath = 'https://www.youtube.com$jsPath';
          }
          final jsResponse = await _client
              .get(Uri.parse(jsPath), headers: {'User-Agent': ua})
              .timeout(const Duration(seconds: 15));
          if (jsResponse.statusCode == 200) {
            final stsMatch = RegExp(r'signatureTimestamp\s*[:=]\s*(\d+)')
                .firstMatch(jsResponse.body);
            if (stsMatch != null) {
              final sts = int.tryParse(stsMatch.group(1)!);
              if (sts != null) {
                _cachedSignatureTimestamp = sts;
                _cachedSignatureTimestampAt = DateTime.now();
                if (kDebugMode) {
                  print('InnerTubeApi: STS from player JS: $sts');
                }
                return sts;
              }
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('InnerTubeApi: Failed to get STS: $e');
      }
    }
    return _cachedSignatureTimestamp ?? 20753; // Current fallback (was 20073)
  }

  /// Validate stream URL with HEAD request
  /// Includes visitorData header for consistency
  Future<bool> validateStreamUrl(String url, {String? visitorData}) async {
    try {
      final request = http.Request('HEAD', Uri.parse(url));

      // Add headers for consistency with original request
      request.headers['User-Agent'] =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
      if (visitorData != null && visitorData.isNotEmpty) {
        request.headers['X-Goog-Visitor-Id'] = visitorData;
      }

      final streamedResponse = await _client
          .send(request)
          .timeout(const Duration(seconds: 8));

      final statusCode = streamedResponse.statusCode;
      if (kDebugMode) {
        print('InnerTubeApi: HEAD validation returned $statusCode');
      }
      return statusCode == 200 || statusCode == 206;
    } catch (e) {
      if (kDebugMode) {
        print('InnerTubeApi: URL validation failed: $e');
      }
      return false;
    }
  }

  void dispose() {
    _client.close();
  }
}

/// Top-level function for compute() - decodes JSON in background isolate
/// Must be top-level to work with compute()
Map<String, dynamic> _jsonDecodeIsolate(String jsonString) {
  return jsonDecode(jsonString) as Map<String, dynamic>;
}
