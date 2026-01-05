import 'dart:convert';
import 'package:flutter/foundation.dart' show compute, kDebugMode;
import 'package:http/http.dart' as http;

/// InnerTube client configuration
/// OuterTune uses ANDROID_VR_NO_AUTH as main client - most reliable currently
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

  /// ANDROID_VR - Main client (most reliable, no auth required)
  static final androidVr = InnerTubeClient(
    name: 'ANDROID_VR',
    version: '1.57.29',
    context: {
      'client': {
        'clientName': 'ANDROID_VR',
        'clientVersion': '1.57.29',
        'androidSdkVersion': 30,
        'osName': 'Android',
        'osVersion': '12',
        'platform': 'MOBILE',
        'hl': 'en',
        'gl': 'US',
      },
      'user': {'lockedSafetyMode': false},
    },
    headers: {
      'User-Agent':
          'com.google.android.apps.youtube.vr.oculus/1.57.29 (Linux; U; Android 12; Quest 2) gzip',
      'X-YouTube-Client-Name': '28',
      'X-YouTube-Client-Version': '1.57.29',
    },
    useWebPoTokens: false,
    supportsSignatureCipher: false,
  );

  /// ANDROID_TESTSUITE - Good fallback
  static final androidTestSuite = InnerTubeClient(
    name: 'ANDROID_TESTSUITE',
    version: '1.9',
    context: {
      'client': {
        'clientName': 'ANDROID_TESTSUITE',
        'clientVersion': '1.9',
        'androidSdkVersion': 30,
        'osName': 'Android',
        'osVersion': '11',
        'platform': 'MOBILE',
        'hl': 'en',
        'gl': 'US',
      },
      'user': {'lockedSafetyMode': false},
    },
    headers: {
      'User-Agent':
          'com.google.android.youtube/19.09.37 (Linux; U; Android 11) gzip',
      'X-YouTube-Client-Name': '30',
      'X-YouTube-Client-Version': '1.9',
    },
    useWebPoTokens: false,
    supportsSignatureCipher: false,
  );

  /// IOS - Fallback with direct URLs
  static final ios = InnerTubeClient(
    name: 'IOS',
    version: '19.16.3',
    context: {
      'client': {
        'clientName': 'IOS',
        'clientVersion': '19.16.3',
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
      'User-Agent':
          'com.google.ios.youtube/19.16.3 (iPhone14,3; U; CPU iOS 17_5_1 like Mac OS X)',
      'X-YouTube-Client-Name': '5',
      'X-YouTube-Client-Version': '19.16.3',
    },
    useWebPoTokens: false,
    supportsSignatureCipher: false,
  );

  /// TVHTML5_SIMPLY_EMBEDDED_PLAYER - Embed fallback
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
      'thirdParty': {'embedUrl': 'https://www.youtube.com'},
      'user': {'lockedSafetyMode': false},
    },
    headers: {
      'User-Agent':
          'Mozilla/5.0 (SMART-TV; Linux; Tizen 6.0) AppleWebKit/538.1 (KHTML, like Gecko) Version/5.0 SmartHub/2021 TV Safari/538.1',
      'X-YouTube-Client-Name': '85',
      'X-YouTube-Client-Version': '2.0',
    },
    useWebPoTokens: false,
    supportsSignatureCipher: false,
  );

  /// WEB_REMIX - YouTube Music web client (may need poToken)
  static final webRemix = InnerTubeClient(
    name: 'WEB_REMIX',
    version: '1.20240520.01.00',
    context: {
      'client': {
        'clientName': 'WEB_REMIX',
        'clientVersion': '1.20240520.01.00',
        'hl': 'en',
        'gl': 'US',
        'experimentIds': [],
        'experimentsToken': '',
        'browserName': 'Chrome',
        'browserVersion': '125.0.0.0',
        'osName': 'Windows',
        'osVersion': '10.0',
        'platform': 'DESKTOP',
        'utcOffsetMinutes': 0,
      },
      'user': {'lockedSafetyMode': false},
    },
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
      'Origin': 'https://music.youtube.com',
      'Referer': 'https://music.youtube.com/',
    },
    useWebPoTokens: true,
    supportsSignatureCipher: true,
  );

  /// WEB - Regular YouTube web client
  static final web = InnerTubeClient(
    name: 'WEB',
    version: '2.20241126.01.00',
    context: {
      'client': {
        'clientName': 'WEB',
        'clientVersion': '2.20241126.01.00',
        'hl': 'en',
        'gl': 'US',
        'browserName': 'Chrome',
        'browserVersion': '131.0.0.0',
        'osName': 'Windows',
        'osVersion': '10.0',
        'platform': 'DESKTOP',
      },
      'user': {'lockedSafetyMode': false},
    },
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
      'Origin': 'https://www.youtube.com',
      'Referer': 'https://www.youtube.com/',
    },
    useWebPoTokens: true,
    supportsSignatureCipher: true,
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
      'User-Agent':
          'com.google.android.apps.youtube.music/7.16.53 (Linux; U; Android 14; Pixel 8) gzip',
      'X-YouTube-Client-Name': '21',
      'X-YouTube-Client-Version': '7.16.53',
    },
    useWebPoTokens: false,
    supportsSignatureCipher: false,
  );

  /// Client fallback order for PLAYBACK - based on user preference
  /// ANDROID_VR is most reliable, then IOS, ANDROID_MUSIC as last resort
  static List<InnerTubeClient> get playbackClients => [
    androidVr, // Primary - most reliable, no auth required
    ios, // Fallback - direct URLs, less bot checks
    androidMusic, // Last resort - YouTube Music specific
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
    final innerTubeClient = client ?? InnerTubeClient.androidVr;

    // Use music API for web clients, otherwise standard
    final baseUrl =
        (innerTubeClient.name == 'WEB_REMIX' || innerTubeClient.name == 'WEB')
        ? _playerApiUrl
        : _playerApiUrl;

    try {
      final url = Uri.parse('$baseUrl?key=$_apiKey&prettyPrint=false');

      final headers = {
        'Content-Type': 'application/json',
        'Accept-Encoding': 'gzip, deflate',
        ...innerTubeClient.headers,
      };

      // Add visitorData header for binding (OuterTune approach)
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

      if (kDebugMode) {print(
        'InnerTubeApi: Requesting player for $videoId with ${innerTubeClient.name}',
      );}

      final response = await _client
          .post(url, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        // Decode JSON in background isolate to avoid UI jank during prefetch
        final json = await compute(_jsonDecodeIsolate, response.body);
        return PlayerResponse.fromJson(json);
      } else {
        if (kDebugMode) {print('InnerTubeApi: HTTP ${response.statusCode} for $videoId');}
        return null;
      }
    } catch (e) {
      if (kDebugMode) {print('InnerTubeApi: Error getting player for $videoId: $e');}
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
      if (kDebugMode) {print('InnerTubeApi: Failed to get STS: $e');}
    }
    return 20073; // Fallback
  }

  /// Validate stream URL with HEAD request (OuterTune approach)
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
      if (kDebugMode) {print('InnerTubeApi: HEAD validation returned $statusCode');}
      return statusCode == 200 || statusCode == 206;
    } catch (e) {
      if (kDebugMode) {print('InnerTubeApi: URL validation failed: $e');}
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
