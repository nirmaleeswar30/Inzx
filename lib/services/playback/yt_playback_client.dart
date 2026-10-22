import 'dart:convert';
import 'package:flutter/foundation.dart' show compute, kDebugMode;
import 'package:http/http.dart' as http;

/// InnerTube client configuration with content-aware fallback strategy
class InnerTubeClient {
  final String name;
  final String version;
  final Map<String, dynamic> context;
  final Map<String, String> headers;
  final bool useWebPoTokens;
  final bool supportsSignatureCipher;

  const InnerTubeClient({
    required this.name,
    required this.version,
    required this.context,
    required this.headers,
    this.useWebPoTokens = false,
    this.supportsSignatureCipher = false,
  });

  /// VISIONOS - Unreleased client, no cipher/PoToken needed. Best first-try.
  static final visionOs = InnerTubeClient(
    name: 'VISIONOS',
    version: '0.1',
    context: {
      'client': {
        'clientName': 'VISIONOS',
        'clientVersion': '0.1',
        'osName': 'visionOS',
        'osVersion': '1.3.21O771',
        'deviceMake': 'Apple',
        'deviceModel': 'RealityDevice14,1',
        'hl': 'en',
        'gl': 'US',
      },
      'user': {'lockedSafetyMode': false},
    },
    headers: {
      'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15',
      'X-YouTube-Client-Name': '101',
      'X-YouTube-Client-Version': '0.1',
    },
  );

  /// ANDROID_VR 1.65 - No cipher/PoToken, very reliable
  static final androidVr165 = InnerTubeClient(
    name: 'ANDROID_VR',
    version: '1.65.10',
    context: {
      'client': {
        'clientName': 'ANDROID_VR',
        'clientVersion': '1.65.10',
        'osName': 'Android',
        'osVersion': '12L',
        'deviceMake': 'Oculus',
        'deviceModel': 'Quest 3',
        'androidSdkVersion': 32,
        'userAgent': 'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
        'hl': 'en',
        'gl': 'US',
      },
      'user': {'lockedSafetyMode': false},
    },
    headers: {
      'User-Agent': 'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
      'X-YouTube-Client-Name': '28',
      'X-YouTube-Client-Version': '1.65.10',
    },
  );

  /// ANDROID_VR 1.43 - Uses non-adaptive bitrate, fixes audio stuttering
  static final androidVr143 = InnerTubeClient(
    name: 'ANDROID_VR_143',
    version: '1.43.32',
    context: {
      'client': {
        'clientName': 'ANDROID_VR',
        'clientVersion': '1.43.32',
        'osName': 'Android',
        'osVersion': '12',
        'deviceMake': 'Oculus',
        'deviceModel': 'Quest 3',
        'androidSdkVersion': 32,
        'userAgent': 'com.google.android.apps.youtube.vr.oculus/1.43.32 (Linux; U; Android 12; en_US; Quest 3; Build/SQ3A.220605.009.A1; Cronet/107.0.5284.2)',
        'hl': 'en',
        'gl': 'US',
      },
      'user': {'lockedSafetyMode': false},
    },
    headers: {
      'User-Agent': 'com.google.android.apps.youtube.vr.oculus/1.43.32 (Linux; U; Android 12; en_US; Quest 3; Build/SQ3A.220605.009.A1; Cronet/107.0.5284.2)',
      'X-YouTube-Client-Name': '28',
      'X-YouTube-Client-Version': '1.43.32',
    },
  );

  /// WEB_REMIX - YouTube Music web (needs poToken + cipher)
  static final webRemix = InnerTubeClient(
    name: 'WEB_REMIX',
    version: '1.20260114.03.00',
    context: {
      'client': {
        'clientName': 'WEB_REMIX',
        'clientVersion': '1.20260114.03.00',
        'hl': 'en',
        'gl': 'US',
      },
      'user': {'lockedSafetyMode': false},
    },
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0',
      'Origin': 'https://music.youtube.com',
      'Referer': 'https://music.youtube.com/',
    },
    useWebPoTokens: true,
    supportsSignatureCipher: true,
  );

  /// TVHTML5 - TV client (needs cipher)
  static final tvhtml5 = InnerTubeClient(
    name: 'TVHTML5',
    version: '7.20260114.12.00',
    context: {
      'client': {
        'clientName': 'TVHTML5',
        'clientVersion': '7.20260114.12.00',
        'userAgent': 'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold (unlike Gecko), Unknown_TV_Unknown_0/Unknown (Unknown, Unknown)',
        'hl': 'en',
        'gl': 'US',
      },
      'user': {'lockedSafetyMode': false},
    },
    headers: {
      'User-Agent': 'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold (unlike Gecko), Unknown_TV_Unknown_0/Unknown (Unknown, Unknown)',
      'X-YouTube-Client-Name': '7',
      'X-YouTube-Client-Version': '7.20260114.12.00',
    },
    useWebPoTokens: true,
    supportsSignatureCipher: true,
  );

  /// TVHTML5_SIMPLY - Simple TV (needs cipher + poToken required)
  static final tvhtml5Simply = InnerTubeClient(
    name: 'TVHTML5_SIMPLY',
    version: '1.0',
    context: {
      'client': {
        'clientName': 'TVHTML5_SIMPLY',
        'clientVersion': '1.0',
        'hl': 'en',
        'gl': 'US',
      },
      'user': {'lockedSafetyMode': false},
    },
    headers: {
      'User-Agent': 'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold (unlike Gecko), Unknown_TV_Unknown_0/Unknown (Unknown, Unknown)',
      'X-YouTube-Client-Name': '75',
      'X-YouTube-Client-Version': '1.0',
    },
    useWebPoTokens: true,
    supportsSignatureCipher: true,
  );

  /// TVHTML5_SIMPLY_EMBEDDED_PLAYER - Can bypass age-restriction
  static final tvEmbedded = InnerTubeClient(
    name: 'TVHTML5_SIMPLY_EMBEDDED_PLAYER',
    version: '2.0',
    context: {
      'client': {
        'clientName': 'TVHTML5_SIMPLY_EMBEDDED_PLAYER',
        'clientVersion': '2.0',
        'platform': 'TV',
        'clientScreen': 'EMBED',
        'hl': 'en',
        'gl': 'US',
      },
      'thirdParty': {'embedUrl': 'https://www.reddit.com/'},
      'user': {'lockedSafetyMode': false},
    },
    headers: {
      'User-Agent': 'Mozilla/5.0 (PlayStation; PlayStation 4/12.02) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.4 Safari/605.1.15',
      'X-YouTube-Client-Name': '85',
      'X-YouTube-Client-Version': '2.0',
    },
    supportsSignatureCipher: true,
  );

  /// WEB_CREATOR - YouTube Studio web client (login required)
  static final webCreator = InnerTubeClient(
    name: 'WEB_CREATOR',
    version: '1.20260114.05.00',
    context: {
      'client': {
        'clientName': 'WEB_CREATOR',
        'clientVersion': '1.20260114.05.00',
        'hl': 'en',
        'gl': 'US',
      },
      'user': {'lockedSafetyMode': false},
    },
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0',
      'Origin': 'https://music.youtube.com',
      'Referer': 'https://music.youtube.com/',
    },
    useWebPoTokens: true,
    supportsSignatureCipher: true,
  );

  /// WEB - Regular YouTube web client  
  static final web = InnerTubeClient(
    name: 'WEB',
    version: '2.20260114.08.00',
    context: {
      'client': {
        'clientName': 'WEB',
        'clientVersion': '2.20260114.08.00',
        'hl': 'en',
        'gl': 'US',
      },
      'user': {'lockedSafetyMode': false},
    },
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0',
      'Origin': 'https://www.youtube.com',
      'Referer': 'https://www.youtube.com/',
    },
    useWebPoTokens: true,
    supportsSignatureCipher: true,
  );

  /// IOS - Fallback with direct URLs
  static final ios = InnerTubeClient(
    name: 'IOS',
    version: '21.03.1',
    context: {
      'client': {
        'clientName': 'IOS',
        'clientVersion': '21.03.1',
        'deviceMake': 'Apple',
        'deviceModel': 'iPhone14,3',
        'osName': 'iOS',
        'osVersion': '17.5.1',
        'hl': 'en',
        'gl': 'US',
        'platform': 'MOBILE',
      },
      'user': {'lockedSafetyMode': false},
    },
    headers: {
      'User-Agent': 'com.google.ios.youtube/21.03.1 (iPhone16,2; U; CPU iOS 18_2 like Mac OS X;)',
      'X-YouTube-Client-Name': '5',
      'X-YouTube-Client-Version': '21.03.1',
    },
    useWebPoTokens: false,
    supportsSignatureCipher: false,
  );

  /// ANDROID_MUSIC - YouTube Music Android app client
  static final androidMusic = InnerTubeClient(
    name: 'ANDROID_MUSIC',
    version: '7.16.53',
    context: {
      'client': {
        'clientName': 'ANDROID_MUSIC',
        'clientVersion': '7.16.53',
        'androidSdkVersion': 34,
        'osName': 'Android',
        'osVersion': '14',
        'platform': 'MOBILE',
        'hl': 'en',
        'gl': 'US',
      },
      'user': {'lockedSafetyMode': false},
    },
    headers: {
      'User-Agent': 'com.google.android.apps.youtube.music/7.16.53 (Linux; U; Android 14; Pixel 8) gzip',
      'X-YouTube-Client-Name': '21',
      'X-YouTube-Client-Version': '7.16.53',
    },
    useWebPoTokens: false,
    supportsSignatureCipher: false,
  );

  /// Default playback client order (content-aware fallback)
  /// Starts with clients that DON'T need cipher/PoToken for fastest playback
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

  static final defaultClients = [
    visionOs,
    androidVr165,
    androidVr143,
    webRemix,
    tvhtml5,
    tvhtml5Simply,
  ];

  static final uploadedClients = [
    tvhtml5,
    webRemix,
    webCreator,
  ];

  static final explicitClients = [
    visionOs,
    tvhtml5,
    webRemix,
  ];

  static final kidsClients = [
    tvhtml5,
    webRemix,
    tvhtml5Simply,
    webCreator,
  ];

  static final liveClients = [
    tvhtml5,
    webRemix,
    webCreator,
    tvhtml5Simply,
  ];

  /// Client for METADATA - separate from playback to reduce fingerprinting
  static InnerTubeClient get metadataClient => webRemix;
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
  static const String _apiKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';

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

    // Use music API for web clients, otherwise standard
    final baseUrl =
        (innerTubeClient.name == 'WEB_REMIX' || innerTubeClient.name == 'WEB')
        ? _musicPlayerApiUrl
        : _playerApiUrl;

    try {
      final url = Uri.parse('$baseUrl?key=$_apiKey&prettyPrint=false');

      final headers = {
        'Content-Type': 'application/json',
        'Accept-Encoding': 'gzip, deflate',
        ...innerTubeClient.headers,
      };

      // Add visitorData header for binding
      if (visitorData != null && visitorData.isNotEmpty) {
        headers['X-Goog-Visitor-Id'] = visitorData;
      }

      // Build context with visitorData embedded
      final context = Map<String, dynamic>.from(innerTubeClient.context);
      if (visitorData != null && visitorData.isNotEmpty) {
        (context['client'] as Map<String, dynamic>)['visitorData'] =
            visitorData;
      }

      final body = <String, dynamic>{
        'context': context,
        'videoId': videoId,
        'racyCheckOk': true,
        'contentCheckOk': true,
      };

      if (playlistId != null) {
        body['playlistId'] = playlistId;
      }

      if (signatureTimestamp != null) {
        body['playbackContext'] = {
          'contentPlaybackContext': {'signatureTimestamp': signatureTimestamp},
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

  /// Get signature timestamp from embed page
  Future<int> getSignatureTimestamp(String videoId) async {
    try {
      final response = await _client
          .get(
            Uri.parse('https://www.youtube.com/embed/$videoId'),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final match = RegExp(r'"sts"\s*:\s*(\d+)').firstMatch(response.body);
        if (match != null) {
          return int.tryParse(match.group(1)!) ?? 20073;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('InnerTubeApi: Failed to get STS: $e');
      }
    }
    return 20073; // Fallback
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
