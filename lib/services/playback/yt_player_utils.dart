import 'package:flutter/foundation.dart' show kDebugMode;
import 'dart:async';
import 'dart:math';

import 'package:inzx/core/services/cache/hive_service.dart';
import 'package:inzx/data/entities/stream_cache_entity.dart';
import 'package:inzx/data/repositories/music_repository.dart'
    show CacheAnalytics;
import 'yt_playback_client.dart';
import 'playback_data.dart';
import 'po_token_generator.dart';
import 'signature_decryptor.dart';

/// YouTube Player Utilities
///
/// This is the heart of the streaming system. It handles:
/// - Multi-client fallback for reliability (OuterTune-style)
/// - Audio-only format selection
/// - Stream URL validation with HEAD requests
/// - poToken integration for bot protection bypass
/// - Retry throttling with exponential backoff
///
/// Based on OuterTune's YTPlayerUtils implementation.
class YTPlayerUtils {
  static YTPlayerUtils? _instance;
  static YTPlayerUtils get instance => _instance ??= YTPlayerUtils._();

  YTPlayerUtils._() {
    // Eagerly load cached poTokens on instance creation
    // This prevents race conditions where multiple requests
    // check hasValidTokens before tokens are loaded from cache
    _initializePoTokens();
  }

  final InnerTubeApi _api = InnerTubeApi();
  final PoTokenGenerator _poToken = PoTokenGenerator.instance;
  final SignatureCipherDecryptor _signatureDecryptor =
      SignatureCipherDecryptor.instance;

  /// Whether poTokens have been initialized (loaded from cache)
  bool _poTokensInitialized = false;
  Completer<void>? _poTokenInitCompleter;

  /// Initialize poTokens from cache (called once on startup)
  void _initializePoTokens() {
    _poTokenInitCompleter = Completer<void>();
    _poToken
        .loadCachedTokens()
        .then((_) {
          _poTokensInitialized = true;
          _poTokenInitCompleter?.complete();
          if (kDebugMode) {print('YTPlayerUtils: poTokens initialized from cache');}
        })
        .catchError((e) {
          _poTokensInitialized = true;
          _poTokenInitCompleter?.complete();
          if (kDebugMode) {print('YTPlayerUtils: poToken cache load failed: $e');}
        });
  }

  /// Wait for poToken initialization to complete
  Future<void> _ensurePoTokensInitialized() async {
    if (_poTokensInitialized) return;
    await _poTokenInitCompleter?.future;
  }

  /// Cache of playback data keyed by videoId
  final Map<String, PlaybackData> _cache = {};

  /// Track consecutive failures per client for backoff
  final Map<String, int> _clientFailures = {};

  /// Track last request time per client for throttling
  final Map<String, DateTime> _clientLastRequest = {};

  /// Minimum interval between requests to same client (ms)
  static const int _minRequestIntervalMs = 1500;

  /// Base backoff delay (ms)
  static const int _baseBackoffMs = 2000;

  /// Maximum backoff delay (ms)
  static const int _maxBackoffMs = 30000;

  /// Maximum consecutive failures before skipping client
  static const int _maxConsecutiveFailures = 3;

  /// Load playback data from persistent cache (Hive)
  PlaybackData? _loadFromPersistentCache(String videoId) {
    try {
      final cached = HiveService.streamCacheBox.get(videoId);
      if (cached != null && cached.isValid) {
        return PlaybackData(
          format: AudioFormat(
            mimeType: cached.mimeType,
            bitrate: cached.bitrate,
            contentLength: cached.contentLength,
            codecs: cached.codec,
          ),
          streamUrl: cached.streamUrl,
          streamExpiresInSeconds: cached.expiresInSeconds,
          fetchedAt: cached.fetchedAt,
        );
      }
    } catch (e) {
      if (kDebugMode) {print('YTPlayerUtils: Persistent cache load error: $e');}
    }
    return null;
  }

  /// Save playback data to persistent cache (Hive)
  void _saveToPersistentCache(String videoId, PlaybackData data) {
    try {
      final entity = StreamCacheEntity(
        videoId: videoId,
        streamUrl: data.streamUrl,
        expiresInSeconds: data.streamExpiresInSeconds,
        fetchedAt: data.fetchedAt,
        mimeType: data.format.mimeType,
        bitrate: data.format.bitrate,
        contentLength: data.format.contentLength,
        codec: data.format.codecs,
      );
      HiveService.streamCacheBox.put(videoId, entity);
      if (kDebugMode) {print('YTPlayerUtils: Saved stream to persistent cache');}
    } catch (e) {
      if (kDebugMode) {print('YTPlayerUtils: Persistent cache save error: $e');}
    }
  }

  /// Get playback data for a video
  ///
  /// This is the main entry point. It:
  /// 1. Checks cache for valid data
  /// 2. Generates poToken if not available (OuterTune approach)
  /// 3. Tries multiple InnerTube playback clients in order
  /// 4. Selects best audio-only format
  /// 5. Validates stream URL with HEAD request
  /// 6. Returns complete PlaybackData or error
  Future<PlaybackResult> playerResponseForPlayback(
    String videoId, {
    String? playlistId,
    AudioQuality quality = AudioQuality.auto,
    bool isMetered = false,
  }) async {
    if (kDebugMode) {print('YTPlayerUtils: Getting playback for $videoId');}

    // Check in-memory cache first
    final cached = _cache[videoId];
    if (cached != null && cached.isValid) {
      CacheAnalytics.instance.recordCacheHit();
      if (kDebugMode) {print('YTPlayerUtils: Using cached playback data (memory)');}
      return PlaybackResult.success(cached);
    }

    // Check persistent cache (Hive)
    final persistedData = _loadFromPersistentCache(videoId);
    if (persistedData != null) {
      CacheAnalytics.instance.recordCacheHit();
      _cache[videoId] = persistedData; // Also add to memory cache
      if (kDebugMode) {print('YTPlayerUtils: Using cached playback data (disk)');}
      return PlaybackResult.success(persistedData);
    }

    CacheAnalytics.instance.recordCacheMiss();
    CacheAnalytics.instance.recordNetworkCall();

    // Wait for poToken initialization to complete (loads from cache)
    // This prevents race conditions on app startup
    await _ensurePoTokensInitialized();

    // Ensure poToken is generated BEFORE attempting any requests
    // This is critical - OuterTune always generates tokens upfront
    String? streamingPoToken;
    String? visitorData;

    if (!_poToken.hasValidTokens) {
      if (kDebugMode) {print('YTPlayerUtils: Generating poToken upfront...');}
      final tokenGenerated = await _poToken.generateTokens();
      if (tokenGenerated) {
        streamingPoToken = _poToken.streamingPoToken;
        visitorData = _poToken.visitorData;
        if (kDebugMode) {print(
          'YTPlayerUtils: poToken ready, visitorData: ${visitorData?.substring(0, min(20, visitorData.length))}...',
        );}
      } else {
        if (kDebugMode) {print('YTPlayerUtils: poToken generation failed, proceeding without');}
      }
    } else {
      streamingPoToken = _poToken.streamingPoToken;
      visitorData = _poToken.visitorData;
    }

    // Use playback-specific clients (OuterTune: separate metadata vs playback)
    final playbackClients = InnerTubeClient.playbackClients;
    PlaybackResult? lastError;

    for (final client in playbackClients) {
      // Check if client should be skipped due to too many failures
      final failures = _clientFailures[client.name] ?? 0;
      if (failures >= _maxConsecutiveFailures) {
        if (kDebugMode) {print(
          'YTPlayerUtils: Skipping ${client.name} due to $failures consecutive failures',
        );}
        continue;
      }

      // Apply throttling between requests
      await _applyThrottle(client.name);

      // Apply backoff if there were previous failures
      if (failures > 0) {
        final backoffMs = _calculateBackoff(failures);
        if (kDebugMode) {print(
          'YTPlayerUtils: Applying ${backoffMs}ms backoff for ${client.name}',
        );}
        await Future.delayed(Duration(milliseconds: backoffMs));
      }

      if (kDebugMode) {print('YTPlayerUtils: Trying client ${client.name}...');}
      _clientLastRequest[client.name] = DateTime.now();

      final result = await _tryClient(
        videoId,
        playlistId: playlistId,
        client: client,
        quality: quality,
        isMetered: isMetered,
        poToken: streamingPoToken,
        visitorData: visitorData,
      );

      if (result.isSuccess) {
        // Reset failure count on success
        _clientFailures[client.name] = 0;
        // Cache successful result (memory + persistent)
        _cache[videoId] = result.data!;
        _saveToPersistentCache(videoId, result.data!);
        return result;
      }

      // Increment failure count
      _clientFailures[client.name] = failures + 1;
      lastError = result;

      // If bot detection and we don't have valid tokens, try generating (but don't clear existing)
      // OuterTune: tokens are reused per session, not regenerated per track
      if (result.requiresPoToken && !_poToken.hasValidTokens) {
        if (kDebugMode) {print(
          'YTPlayerUtils: Bot detected, generating poToken (session-level)...',
        );}
        final generated = await _poToken.generateTokens();

        if (generated) {
          streamingPoToken = _poToken.streamingPoToken;
          visitorData = _poToken.visitorData;

          // Wait a bit before retry
          await Future.delayed(const Duration(milliseconds: 1500));

          final retryResult = await _tryClient(
            videoId,
            playlistId: playlistId,
            client: client,
            quality: quality,
            isMetered: isMetered,
            poToken: streamingPoToken,
            visitorData: visitorData,
          );

          if (retryResult.isSuccess) {
            _clientFailures[client.name] = 0;
            _cache[videoId] = retryResult.data!;
            _saveToPersistentCache(videoId, retryResult.data!);
            return retryResult;
          }
        }
      }
    }

    // All clients failed
    if (kDebugMode) {print('YTPlayerUtils: All clients failed for $videoId');}
    return lastError ?? PlaybackResult.failure('Could not get playback URL');
  }

  /// Get playback data for downloads - prefer Opus/WebM (more reliable for YouTube)
  /// Opus streams are more contiguous and less likely to truncate at chunk boundaries
  Future<PlaybackResult> playerResponseForDownload(
    String videoId, {
    AudioQuality quality = AudioQuality.high,
  }) async {
    if (kDebugMode) {print(
      'YTPlayerUtils: Getting format for download: $videoId (preferring Opus)',
    );}

    // Don't use cache for downloads - we need fresh URL
    await _ensurePoTokensInitialized();

    String? streamingPoToken;
    String? visitorData;

    if (_poToken.hasValidTokens) {
      streamingPoToken = _poToken.streamingPoToken;
      visitorData = _poToken.visitorData;
    }

    final playbackClients = InnerTubeClient.playbackClients;

    for (final client in playbackClients) {
      await _applyThrottle(client.name);

      try {
        int? sts;
        if (client.supportsSignatureCipher) {
          sts = await _api.getSignatureTimestamp(videoId);
        }

        final response = await _api.player(
          videoId,
          client: client,
          signatureTimestamp: sts,
          poToken: streamingPoToken,
          visitorData: visitorData,
        );

        if (response == null || !response.playabilityStatus.isPlayable) {
          if (kDebugMode) {print('YTPlayerUtils: ${client.name} not playable for download');}
          continue;
        }

        final adaptiveFormats =
            response.streamingData?['adaptiveFormats'] as List?;
        if (adaptiveFormats == null || adaptiveFormats.isEmpty) {
          if (kDebugMode) {print('YTPlayerUtils: No adaptive formats from ${client.name}');}
          continue;
        }

        // First try Opus/WebM (more reliable for downloads)
        var formatData = _selectOpusFormat(adaptiveFormats, quality: quality);

        // Fallback to AAC if no Opus available
        if (formatData == null) {
          if (kDebugMode) {print('YTPlayerUtils: No Opus format, falling back to AAC');}
          formatData = _selectAacFormat(adaptiveFormats, quality: quality);
        }

        if (formatData == null) {
          if (kDebugMode) {print(
            'YTPlayerUtils: No audio format found from ${client.name}, trying next client',
          );}
          continue;
        }

        final rawFormat = formatData['raw'] as Map<String, dynamic>;
        final audioFormat = formatData['format'] as AudioFormat;

        final streamUrl = await _extractStreamUrl(
          rawFormat,
          poToken: streamingPoToken,
          visitorData: visitorData,
        );

        if (streamUrl == null) {
          if (kDebugMode) {print(
            'YTPlayerUtils: Could not extract stream URL from ${client.name}',
          );}
          continue;
        }

        // Validate URL with HEAD request
        final isValid = await _api.validateStreamUrl(
          streamUrl,
          visitorData: visitorData,
        );
        if (!isValid) {
          if (kDebugMode) {print(
            'YTPlayerUtils: Stream URL validation failed for ${client.name}',
          );}
          continue;
        }

        // Extract expiry time from URL
        final expiresIn = _extractExpirySeconds(streamUrl);

        final playbackData = PlaybackData(
          audioConfig: AudioConfig.fromJson(
            response.playerConfig?['audioConfig'] as Map<String, dynamic>?,
          ),
          videoDetails: VideoDetails.fromJson(response.videoDetails),
          playbackTracking: PlaybackTracking.fromJson(
            response.playbackTracking,
          ),
          format: audioFormat,
          streamUrl: streamUrl,
          streamExpiresInSeconds: expiresIn,
          fetchedAt: DateTime.now(),
        );

        if (kDebugMode) {print(
          'YTPlayerUtils: Got format for download: ${audioFormat.mimeType} at ${audioFormat.bitrate}bps',
        );}
        return PlaybackResult.success(playbackData);
      } catch (e) {
        if (kDebugMode) {print('YTPlayerUtils: Download format error with ${client.name}: $e');}
      }
    }

    return PlaybackResult.failure('Could not get audio format for download');
  }

  /// Select Opus/WebM format for downloads (preferred - more reliable)
  Map<String, dynamic>? _selectOpusFormat(
    List<dynamic> adaptiveFormats, {
    required AudioQuality quality,
  }) {
    // Filter to Opus/WebM audio-only formats
    final opusFormats = adaptiveFormats
        .where((f) {
          final mimeType = f['mimeType']?.toString() ?? '';
          // Must be audio, must be Opus/WebM, no video
          return mimeType.startsWith('audio/') &&
              (mimeType.contains('webm') || mimeType.contains('opus')) &&
              f['width'] == null;
        })
        .map(
          (f) => {
            'format': AudioFormat.fromJson(f as Map<String, dynamic>),
            'raw': f,
          },
        )
        .toList();

    if (opusFormats.isEmpty) {
      if (kDebugMode) {print('YTPlayerUtils: No Opus formats available');}
      return null;
    }

    if (kDebugMode) {print('YTPlayerUtils: Found ${opusFormats.length} Opus formats');}

    // Sort by bitrate based on quality preference
    double qualityFactor;
    switch (quality) {
      case AudioQuality.low:
        qualityFactor = 0.3;
        break;
      case AudioQuality.medium:
        qualityFactor = 0.6;
        break;
      case AudioQuality.high:
      case AudioQuality.max:
      case AudioQuality.auto:
        qualityFactor = 1.0;
        break;
    }

    opusFormats.sort((a, b) {
      final formatA = a['format'] as AudioFormat;
      final formatB = b['format'] as AudioFormat;
      final scoreA = (formatA.bitrate * qualityFactor).toInt();
      final scoreB = (formatB.bitrate * qualityFactor).toInt();
      return scoreB.compareTo(scoreA);
    });

    final best = opusFormats.first;
    final format = best['format'] as AudioFormat;
    if (kDebugMode) {print(
      'YTPlayerUtils: Selected Opus: ${format.mimeType} at ${format.bitrate}bps',
    );}

    return best;
  }

  /// Select AAC/M4A format specifically for downloads
  Map<String, dynamic>? _selectAacFormat(
    List<dynamic> adaptiveFormats, {
    required AudioQuality quality,
  }) {
    // Filter to AAC/M4A audio-only formats
    final aacFormats = adaptiveFormats
        .where((f) {
          final mimeType = f['mimeType']?.toString() ?? '';
          // Must be audio, must be AAC/M4A (contains mp4 or m4a), no video
          return mimeType.startsWith('audio/') &&
              (mimeType.contains('mp4') || mimeType.contains('m4a')) &&
              f['width'] == null;
        })
        .map(
          (f) => {
            'format': AudioFormat.fromJson(f as Map<String, dynamic>),
            'raw': f,
          },
        )
        .toList();

    if (aacFormats.isEmpty) {
      if (kDebugMode) {print('YTPlayerUtils: No AAC formats available');}
      return null;
    }

    if (kDebugMode) {print('YTPlayerUtils: Found ${aacFormats.length} AAC formats');}

    // Sort by bitrate based on quality preference
    double qualityFactor;
    switch (quality) {
      case AudioQuality.low:
        qualityFactor = 0.3;
        break;
      case AudioQuality.medium:
        qualityFactor = 0.6;
        break;
      case AudioQuality.high:
      case AudioQuality.max:
      case AudioQuality.auto:
        qualityFactor = 1.0;
        break;
    }

    aacFormats.sort((a, b) {
      final formatA = a['format'] as AudioFormat;
      final formatB = b['format'] as AudioFormat;
      final scoreA = (formatA.bitrate * qualityFactor).toInt();
      final scoreB = (formatB.bitrate * qualityFactor).toInt();
      return scoreB.compareTo(scoreA);
    });

    final best = aacFormats.first;
    final format = best['format'] as AudioFormat;
    if (kDebugMode) {print(
      'YTPlayerUtils: Selected AAC: ${format.mimeType} at ${format.bitrate}bps',
    );}

    return best;
  }

  /// Apply throttling to prevent rapid-fire requests to same client
  Future<void> _applyThrottle(String clientName) async {
    final lastRequest = _clientLastRequest[clientName];
    if (lastRequest != null) {
      final elapsed = DateTime.now().difference(lastRequest).inMilliseconds;
      if (elapsed < _minRequestIntervalMs) {
        final waitMs = _minRequestIntervalMs - elapsed;
        await Future.delayed(Duration(milliseconds: waitMs));
      }
    }
  }

  /// Calculate exponential backoff with jitter
  int _calculateBackoff(int failures) {
    final exponential = _baseBackoffMs * pow(2, failures - 1).toInt();
    final capped = min(exponential, _maxBackoffMs);
    // Add random jitter (0-25% of delay)
    final jitter = Random().nextInt(capped ~/ 4);
    return capped + jitter;
  }

  /// Try a specific client to get playback data
  Future<PlaybackResult> _tryClient(
    String videoId, {
    String? playlistId,
    required InnerTubeClient client,
    required AudioQuality quality,
    required bool isMetered,
    String? poToken,
    String? visitorData,
  }) async {
    try {
      // Get signature timestamp if needed
      int? sts;
      if (client.supportsSignatureCipher) {
        sts = await _api.getSignatureTimestamp(videoId);
      }

      // Make player request with visitorData header
      final response = await _api.player(
        videoId,
        playlistId: playlistId,
        client: client,
        signatureTimestamp: sts,
        poToken: poToken,
        visitorData: visitorData,
      );

      if (response == null) {
        return PlaybackResult.failure('No response from ${client.name}');
      }

      // Check playability
      if (!response.playabilityStatus.isPlayable) {
        final reason = response.playabilityStatus.reason ?? 'Unknown';
        if (kDebugMode) {print('YTPlayerUtils: ${client.name} not playable: $reason');}

        // Check if it needs login/poToken (bot detection)
        if (response.playabilityStatus.requiresLogin ||
            reason.toLowerCase().contains('bot') ||
            reason.toLowerCase().contains('verification') ||
            reason.toLowerCase().contains('sign in') ||
            reason.toLowerCase().contains('confirm')) {
          return PlaybackResult.needsPoToken();
        }

        return PlaybackResult.failure(reason);
      }

      // Check for streaming data
      if (!response.hasAdaptiveFormats) {
        if (kDebugMode) {print('YTPlayerUtils: ${client.name} has no adaptive formats');}
        return PlaybackResult.failure('No streaming data');
      }

      // Select best audio format
      final formatResult = _selectBestFormat(
        response.streamingData!['adaptiveFormats'] as List,
        quality: quality,
        isMetered: isMetered,
      );

      if (formatResult == null) {
        return PlaybackResult.failure('No suitable audio format');
      }

      final rawFormat = formatResult['raw'] as Map<String, dynamic>;
      final audioFormat = formatResult['format'] as AudioFormat;

      // Extract stream URL with poToken binding
      String? streamUrl = await _extractStreamUrl(
        rawFormat,
        poToken: poToken,
        visitorData: visitorData,
      );

      if (streamUrl == null) {
        return PlaybackResult.failure('Could not extract stream URL');
      }

      // Validate URL with HEAD request (OuterTune approach)
      final isValid = await _api.validateStreamUrl(
        streamUrl,
        visitorData: visitorData,
      );
      if (!isValid) {
        if (kDebugMode) {print(
          'YTPlayerUtils: Stream URL validation failed (HEAD returned error)',
        );}
        return PlaybackResult.failure('Stream URL validation failed');
      }

      // Extract expiry time from URL
      final expiresIn = _extractExpirySeconds(streamUrl);

      // Build PlaybackData
      final playbackData = PlaybackData(
        audioConfig: AudioConfig.fromJson(
          response.playerConfig?['audioConfig'] as Map<String, dynamic>?,
        ),
        videoDetails: VideoDetails.fromJson(response.videoDetails),
        playbackTracking: PlaybackTracking.fromJson(response.playbackTracking),
        format: audioFormat,
        streamUrl: streamUrl,
        streamExpiresInSeconds: expiresIn,
        fetchedAt: DateTime.now(),
      );

      if (kDebugMode) {print('YTPlayerUtils: Success from ${client.name}');}
      return PlaybackResult.success(playbackData);
    } catch (e) {
      if (kDebugMode) {print('YTPlayerUtils: ${client.name} error: $e');}
      return PlaybackResult.failure(e.toString());
    }
  }

  /// Select the best audio format based on quality preference
  /// Returns both the AudioFormat and raw data for URL extraction
  Map<String, dynamic>? _selectBestFormat(
    List<dynamic> adaptiveFormats, {
    required AudioQuality quality,
    required bool isMetered,
  }) {
    // Filter to audio-only formats
    final audioFormats = adaptiveFormats
        .where((f) {
          final mimeType = f['mimeType']?.toString() ?? '';
          // Audio-only: has audio mime type and no width (video indicator)
          return mimeType.startsWith('audio/') && f['width'] == null;
        })
        .map(
          (f) => {
            'format': AudioFormat.fromJson(f as Map<String, dynamic>),
            'raw': f,
          },
        )
        .toList();

    if (audioFormats.isEmpty) {
      if (kDebugMode) {print('YTPlayerUtils: No audio-only formats found');}
      return null;
    }

    if (kDebugMode) {print('YTPlayerUtils: Found ${audioFormats.length} audio formats');}

    // Calculate quality factor for each format
    final qualityFactor = _getQualityFactor(quality, isMetered);

    // Sort by quality preference
    audioFormats.sort((a, b) {
      final formatA = a['format'] as AudioFormat;
      final formatB = b['format'] as AudioFormat;

      // Calculate weighted score
      final scoreA =
          formatA.bitrate * qualityFactor + (formatA.isOpus ? 10240 : 0);
      final scoreB =
          formatB.bitrate * qualityFactor + (formatB.isOpus ? 10240 : 0);

      return scoreB.compareTo(scoreA); // Descending
    });

    // Return the best format with both parsed and raw data
    final best = audioFormats.first;
    if (kDebugMode) {print(
      'YTPlayerUtils: Selected ${(best['format'] as AudioFormat).mimeType} at ${(best['format'] as AudioFormat).bitrate}bps',
    );}

    return best;
  }

  /// Get quality factor based on preference and network
  double _getQualityFactor(AudioQuality quality, bool isMetered) {
    if (isMetered) {
      // On metered connection, prefer lower bitrate
      return 0.5;
    }

    switch (quality) {
      case AudioQuality.low:
        return 0.3;
      case AudioQuality.medium:
        return 0.6;
      case AudioQuality.high:
        return 1.0;
      case AudioQuality.max:
        return 1.5;
      case AudioQuality.auto:
        return 1.0;
    }
  }

  /// Extract stream URL from format data
  /// Appends poToken and includes visitorData for request binding
  Future<String?> _extractStreamUrl(
    Map<String, dynamic> format, {
    String? poToken,
    String? visitorData,
  }) async {
    // Try direct URL first (preferred)
    if (format['url'] != null) {
      String url = format['url'] as String;

      // Append poToken if provided (OuterTune binds token to stream)
      if (poToken != null && poToken.isNotEmpty) {
        url += '&pot=$poToken';
      }

      return url;
    }

    // Handle signatureCipher (encrypted URL)
    if (format['signatureCipher'] != null) {
      final cipher = format['signatureCipher'] as String;
      final decrypted = await _decryptSignatureCipher(cipher);

      if (decrypted != null) {
        String url = decrypted;
        if (poToken != null && poToken.isNotEmpty) {
          url += '&pot=$poToken';
        }
        return url;
      }
    }

    return null;
  }

  /// Decrypt signature cipher
  ///
  /// YouTube encrypts some stream URLs with a signature cipher.
  /// This requires fetching and executing their JS decryption function.
  Future<String?> _decryptSignatureCipher(String cipher) async {
    try {
      // Use the signature decryptor
      return await _signatureDecryptor.decrypt(cipher);
    } catch (e) {
      if (kDebugMode) {print('YTPlayerUtils: Cipher decryption failed: $e');}
      return null;
    }
  }

  /// Extract expiry time from stream URL
  int _extractExpirySeconds(String url) {
    try {
      final uri = Uri.parse(url);
      final expire = uri.queryParameters['expire'];

      if (expire != null) {
        final expireTimestamp = int.tryParse(expire);
        if (expireTimestamp != null) {
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          return expireTimestamp - now;
        }
      }

      // Default to 6 hours if not found
      return 21600;
    } catch (e) {
      return 21600;
    }
  }

  /// Clear cache for a specific video
  void clearCache(String videoId) {
    _cache.remove(videoId);
  }

  /// Clear all cache
  void clearAllCache() {
    _cache.clear();
  }

  /// Reset client failure counters (call after successful playback)
  void resetClientFailures() {
    _clientFailures.clear();
    _clientLastRequest.clear();
    if (kDebugMode) {print('YTPlayerUtils: Client failures reset');}
  }

  /// Get cache size
  int get cacheSize => _cache.length;

  /// Get failure count for a specific client
  int getClientFailures(String clientName) => _clientFailures[clientName] ?? 0;

  /// Check if playback data is cached for a video
  bool hasCachedData(String videoId) {
    final cached = _cache[videoId];
    return cached != null && cached.isValid;
  }

  /// Prefetch playback data for multiple videos (OuterTune-style)
  ///
  /// Call this when:
  /// - Queue changes
  /// - Next track becomes known
  /// - Playlist is loaded
  ///
  /// This resolves streams BEFORE play is tapped, eliminating delay.
  /// Runs with low priority to avoid UI jank.
  Future<void> prefetch(
    List<String> videoIds, {
    AudioQuality quality = AudioQuality.auto,
    bool isMetered = false,
  }) async {
    if (videoIds.isEmpty) return;

    if (kDebugMode) {print('YTPlayerUtils: Prefetching ${videoIds.length} tracks...');}

    // Schedule as a low-priority background task
    // This ensures UI frames are never blocked by prefetch operations
    Future.microtask(() async {
      // Yield to UI thread before starting
      await Future.delayed(const Duration(milliseconds: 16));

      // Ensure tokens are ready before prefetching
      if (!_poToken.hasValidTokens) {
        await _poToken.generateTokens();
      }

      // Prefetch sequentially with delays to avoid UI jank
      for (int i = 0; i < videoIds.length; i++) {
        final videoId = videoIds[i];

        // Skip if already cached (memory or disk)
        if (hasCachedData(videoId)) continue;

        // Check disk cache before network call
        final diskCached = _loadFromPersistentCache(videoId);
        if (diskCached != null) {
          _cache[videoId] = diskCached;
          continue;
        }

        await _prefetchSingle(videoId, quality, isMetered);

        // Yield to UI thread between each fetch
        // Longer delays for later tracks (first few are higher priority)
        final delay = i < 3 ? 50 : 150;
        await Future.delayed(Duration(milliseconds: delay));
      }

      if (kDebugMode) {print('YTPlayerUtils: Prefetch complete, cache size: $cacheSize');}
    });
  }

  /// Prefetch a single video (internal)
  Future<void> _prefetchSingle(
    String videoId,
    AudioQuality quality,
    bool isMetered,
  ) async {
    try {
      await playerResponseForPlayback(
        videoId,
        quality: quality,
        isMetered: isMetered,
      );
    } catch (e) {
      if (kDebugMode) {print('YTPlayerUtils: Prefetch failed for $videoId: $e');}
    }
  }

  /// Prefetch next track (convenience method)
  /// Call this while current track is playing
  Future<void> prefetchNext(
    String videoId, {
    AudioQuality quality = AudioQuality.auto,
  }) async {
    if (hasCachedData(videoId)) return;

    if (kDebugMode) {print('YTPlayerUtils: Prefetching next track: $videoId');}
    await _prefetchSingle(videoId, quality, false);
  }

  void dispose() {
    _api.dispose();
    _cache.clear();
    _clientFailures.clear();
    _clientLastRequest.clear();
  }
}
