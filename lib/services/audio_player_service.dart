import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import 'playback/playback.dart';
import 'jiosaavn/jiosaavn_service.dart';
import 'addons/addon_service.dart';
import 'automix/automix_service.dart';
import 'ytmusic_api_service.dart';
import 'ytmusic_auth_service.dart';
import 'queue_persistence_service.dart';
import 'lyrics/lyrics_service.dart';
import 'album_color_extractor.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'local_artwork_service.dart';
import 'package:hive/hive.dart';
import '../data/entities/download_entity.dart';
import '../data/entities/track_entity.dart';
import 'audio_routing_service.dart';

/// Key for persisting streaming quality preference
const String kStreamingQualityKey = 'streaming_quality';
const String kStreamCacheWifiOnlyKey = 'stream_cache_wifi_only';
const String kStreamCacheSizeLimitMbKey = 'stream_cache_size_limit_mb';
const String kStreamCacheMaxConcurrentKey = 'stream_cache_max_concurrent';
const String kCrossfadeDurationMsKey = 'crossfade_duration_ms';
const String kShowNerdStatsKey = 'show_nerd_stats';
const String kJioSaavnEnabledKey = 'jiosaavn_enabled';
const int kDefaultStreamCacheSizeLimitMb = 1024;
const int kMinStreamCacheSizeLimitMb = 128;
const int kMaxStreamCacheSizeLimitMb = 4096;
const int kDefaultStreamCacheMaxConcurrent = 2;
const int kMinStreamCacheMaxConcurrent = 1;
const int kMaxStreamCacheMaxConcurrent = 4;
const int kDefaultCrossfadeDurationMs = 8000;
const int kMinCrossfadeDurationMs = 0;
const int kMaxCrossfadeDurationMs = 12000;
const int kPrecacheAheadTrackCount = 3;
const int kLyricsPrefetchAheadTrackCount = 4;
const int kMinValidStreamCacheFileBytes = 50 * 1024;
const int kParallelPrecacheMinBytes = 1024 * 1024;
const int kParallelPrecachePartCount = 4;

/// ConcatenatingAudioSource for gapless playback with pre-buffering
/// This is the key to OuterTune's instant playback
class PlaybackState {
  final Track? currentTrack;
  final List<Track> queue;
  final int queueRevision;
  final int currentIndex;
  final bool isPlaying;
  final bool isBuffering;
  final bool isLoading;
  final Duration position;
  final Duration bufferedPosition;
  final Duration? duration;
  final double speed;
  final LoopMode loopMode;
  final bool shuffleEnabled;
  final String? error;
  final AudioQuality audioQuality;
  final PlaybackData? currentPlaybackData;
  final String?
  queueSourceId; // Track which playlist/album/artist started this queue
  final String?
  queueTitle; // Track title of the playlist/album/artist
  final bool isRadioMode; // Whether radio mode is active (infinite queue)
  final bool
  isFetchingRadio; // Whether we're currently fetching more radio tracks
  final bool streamCacheWifiOnly;
  final int streamCacheSizeLimitMb;
  final int streamCacheMaxConcurrent;
  final int crossfadeDurationMs;
  final bool showNerdStats;
  final bool jioSaavnEnabled;

  const PlaybackState({
    this.currentTrack,
    this.queue = const [],
    this.currentIndex = -1,
    this.isPlaying = false,
    this.isBuffering = false,
    this.isLoading = false,
    this.position = Duration.zero,
    this.bufferedPosition = Duration.zero,
    this.duration,
    this.speed = 1.0,
    this.loopMode = LoopMode.off,
    this.shuffleEnabled = false,
    this.error,
    this.audioQuality = AudioQuality.max,
    this.currentPlaybackData,
    this.queueRevision = 0,
    this.queueSourceId,
    this.queueTitle,
    this.isRadioMode = false,
    this.isFetchingRadio = false,
    this.streamCacheWifiOnly = false,
    this.streamCacheSizeLimitMb = kDefaultStreamCacheSizeLimitMb,
    this.streamCacheMaxConcurrent = kDefaultStreamCacheMaxConcurrent,
    this.crossfadeDurationMs = kDefaultCrossfadeDurationMs,
    this.showNerdStats = false,
    this.jioSaavnEnabled = true,
  });

  PlaybackState copyWith({
    Track? currentTrack,
    bool resetCurrentTrack = false,
    List<Track>? queue,
    int? currentIndex,
    bool? isPlaying,
    bool? isBuffering,
    bool? isLoading,
    Duration? position,
    Duration? bufferedPosition,
    Duration? duration,
    bool resetDuration = false,
    double? speed,
    LoopMode? loopMode,
    bool? shuffleEnabled,
    String? error,
    AudioQuality? audioQuality,
    PlaybackData? currentPlaybackData,
    bool resetCurrentPlaybackData = false,
    int? queueRevision,
    String? queueSourceId,
    String? queueTitle,
    bool resetQueueTitle = false,
    bool? isRadioMode,
    bool? isFetchingRadio,
    bool? streamCacheWifiOnly,
    int? streamCacheSizeLimitMb,
    int? streamCacheMaxConcurrent,
    int? crossfadeDurationMs,
    bool? showNerdStats,
    bool? jioSaavnEnabled,
  }) {
    return PlaybackState(
      currentTrack: resetCurrentTrack ? null : (currentTrack ?? this.currentTrack),
      queue: queue ?? this.queue,
      queueRevision: queueRevision ?? this.queueRevision,
      currentIndex: currentIndex ?? this.currentIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      isLoading: isLoading ?? this.isLoading,
      position: position ?? this.position,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      duration: resetDuration ? null : (duration ?? this.duration),
      speed: speed ?? this.speed,
      loopMode: loopMode ?? this.loopMode,
      shuffleEnabled: shuffleEnabled ?? this.shuffleEnabled,
      error: error,
      audioQuality: audioQuality ?? this.audioQuality,
      currentPlaybackData: resetCurrentPlaybackData
          ? null
          : (currentPlaybackData ?? this.currentPlaybackData),
      queueSourceId: queueSourceId ?? this.queueSourceId,
      queueTitle: resetQueueTitle ? null : (queueTitle ?? this.queueTitle),
      isRadioMode: isRadioMode ?? this.isRadioMode,
      isFetchingRadio: isFetchingRadio ?? this.isFetchingRadio,
      streamCacheWifiOnly: streamCacheWifiOnly ?? this.streamCacheWifiOnly,
      streamCacheSizeLimitMb:
          streamCacheSizeLimitMb ?? this.streamCacheSizeLimitMb,
      streamCacheMaxConcurrent:
          streamCacheMaxConcurrent ?? this.streamCacheMaxConcurrent,
      crossfadeDurationMs: crossfadeDurationMs ?? this.crossfadeDurationMs,
      showNerdStats: showNerdStats ?? this.showNerdStats,
      jioSaavnEnabled: jioSaavnEnabled ?? this.jioSaavnEnabled,
    );
  }

  /// Check if there's a next track
  bool get hasNext =>
      currentIndex < queue.length - 1 || loopMode == LoopMode.all;

  /// Check if there's a previous track
  bool get hasPrevious => currentIndex > 0 || loopMode == LoopMode.all;

  /// Whether the current track is a live stream (radio/live broadcast).
  bool get isLive => currentPlaybackData?.isLive == true;

  /// Progress as a fraction (0.0 to 1.0)
  double get progress {
    if (isLive) return 1.0;
    if (duration == null || duration!.inMilliseconds == 0) return 0.0;
    return position.inMilliseconds / duration!.inMilliseconds;
  }

  /// Current stream quality info
  String get qualityInfo {
    if (currentPlaybackData != null) {
      return currentPlaybackData!.statsSummary;
    }
    return '';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlaybackState &&
        other.currentTrack?.id == currentTrack?.id &&
        other.currentIndex == currentIndex &&
        other.queueRevision ==
            queueRevision && // Check revision instead of length
        other.isPlaying == isPlaying &&
        other.isBuffering == isBuffering &&
        other.isLoading == isLoading &&
        other.speed == speed &&
        other.loopMode == loopMode &&
        other.shuffleEnabled == shuffleEnabled &&
        other.error == error &&
        other.audioQuality == audioQuality &&
        other.duration == duration &&
        other.queueSourceId == queueSourceId &&
        other.queueTitle == queueTitle &&
        other.isRadioMode == isRadioMode &&
        other.isFetchingRadio == isFetchingRadio &&
        other.streamCacheWifiOnly == streamCacheWifiOnly &&
        other.streamCacheSizeLimitMb == streamCacheSizeLimitMb &&
        other.streamCacheMaxConcurrent == streamCacheMaxConcurrent &&
        other.crossfadeDurationMs == crossfadeDurationMs &&
        other.showNerdStats == showNerdStats &&
        other.jioSaavnEnabled == jioSaavnEnabled &&
        other.currentPlaybackData == currentPlaybackData;
    // NOTE: position and bufferedPosition intentionally excluded
    // to prevent rebuilds on every position update
  }

  @override
  int get hashCode => Object.hashAll([
    currentTrack?.id,
    currentIndex,
    queueRevision, // Include queue revision
    isPlaying,
    isBuffering,
    isLoading,
    speed,
    loopMode,
    shuffleEnabled,
    error,
    audioQuality,
    duration,
    queueSourceId,
    queueTitle,
    isRadioMode,
    isFetchingRadio,
    streamCacheWifiOnly,
    streamCacheSizeLimitMb,
    streamCacheMaxConcurrent,
    crossfadeDurationMs,
    showNerdStats,
    jioSaavnEnabled,
    currentPlaybackData,
  ]);
}

/// OuterTune-style Audio Player Service
///
/// This service implements the OuterTune playback architecture:
/// - Uses InnerTube API with multi-client fallback
/// - Audio-only CDN streams (no video, no WebView)
/// - Proper stream URL validation
/// - Background playback support via just_audio
///
/// The playback pipeline is:
/// 1. Track requested → YTPlayerUtils.playerResponseForPlayback()
/// 2. InnerTube API → Multi-client fallback until success
/// 3. Audio-only format selection → Best quality for network
/// 4. URL validation → HEAD request confirmation
/// 5. ExoPlayer/just_audio → Direct CDN streaming
class AudioPlayerService {
  static final AudioPlayerService _instance = AudioPlayerService._internal();
  factory AudioPlayerService() => _instance;

  /// Explicit singleton getter (preferred for clarity)
  static AudioPlayerService get instance => _instance;

  AudioPlayerService._internal() {
    _init();
    // Load persisted streaming quality
    _loadStreamingQuality();
    _loadStreamCacheSettings();
    _loadNerdStatsSetting();
    _loadPreferAudioVersionsSetting();
    _loadJioSaavnSetting();
    unawaited(AddonService.instance.load());
    AddonService.instance.matches.listen(_onLosslessFound);
    unawaited(AutomixService.instance.load());
    AutomixService.instance.fetchAudio = fetchAnalysisAudio;
    _wireAutomixEngine();
    unawaited(_watchNetworkType());
    // Load persisted queue from previous session
    _loadPersistedQueue();
    // Eagerly restore InnerTube auth in background
    unawaited(_ensureInnerTubeAuth());
  }

  /// Load prefer audio versions preference
  Future<void> _loadPreferAudioVersionsSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _preferAudioVersions = prefs.getBool('inzx_prefer_audio_versions') ?? false;
    } catch (e) {
      if (kDebugMode) {
        print('AudioPlayerService: Failed to load prefer audio versions setting: $e');
      }
    }
  }

  /// Set prefer audio versions
  void setPreferAudioVersions(bool enabled) {
    _preferAudioVersions = enabled;
  }

  /// Set the InnerTubeService instance (for personalized radio)
  /// Call this after authentication to enable personalized recommendations
  void setInnerTubeService(InnerTubeService service) {
    if (_innerTubeService != null &&
        _innerTubeService!.isAuthenticated &&
        !service.isAuthenticated) {
      if (kDebugMode) {
        print(
          'AudioPlayerService: Ignoring setInnerTubeService with unauthenticated instance because current instance is already authenticated.',
        );
      }
      return;
    }
    _innerTubeService = service;
    if (kDebugMode) {
      print(
        'AudioPlayerService: InnerTubeService set, authenticated=${service.isAuthenticated}',
      );
    }
    if (service.isAuthenticated && _player.playing) {
      _startYoutubePlaybackTracking();
    }
  }

  /// Refresh authentication state - call when auth changes
  /// This ensures radio uses updated auth cookies
  void refreshAuthState() {
    _authenticatedPlaybackTracking = null;
    if (_innerTubeService != null) {
      if (kDebugMode) {
        print(
          'AudioPlayerService: Auth refreshed, authenticated=${_innerTubeService!.isAuthenticated}',
        );
      }
      if (_innerTubeService!.isAuthenticated && _player.playing) {
        _startYoutubePlaybackTracking();
      }
    }
  }

  /// Check if radio is currently active
  bool get isRadioMode => _isRadioMode;

  /// Dual-player engine for true overlap crossfade.
  final AudioPlayer _primaryPlayer = AudioPlayer();
  final AudioPlayer _secondaryPlayer = AudioPlayer();
  late AudioPlayer _player = _primaryPlayer;

  /// OuterTune-style playback resolver
  final YTPlayerUtils _ytPlayerUtils = YTPlayerUtils.instance;
  final LyricsWarmupService _lyricsWarmupService = LyricsWarmupService.instance;


  // Queue management
  List<Track> _queue = [];
  List<Track> _originalQueue = []; // For unshuffling
  int _queueRevision =
      0; // Incremented on every queue change to force UI updates
  int _currentIndex = -1;
  bool _shuffleEnabled = false;
  LoopMode _loopMode = LoopMode.off;
  Track? _currentTrack;
  PlaybackData? _currentPlaybackData;
  AudioQuality _audioQuality = AudioQuality.max;

  /// Wi-Fi or ethernet right now, kept current by a connectivity listener
  /// so quality checks don't have to wait on the platform.
  bool _onUnmeteredNetwork = true;
  bool _streamCacheWifiOnly = false;
  int _streamCacheSizeLimitMb = kDefaultStreamCacheSizeLimitMb;
  int _streamCacheMaxConcurrent = kDefaultStreamCacheMaxConcurrent;
  int _crossfadeDurationMs = kDefaultCrossfadeDurationMs;
  bool _showNerdStats = false;
  bool get showNerdStats => _showNerdStats;
  bool _preferAudioVersions = false;
  bool _jioSaavnEnabled = true;
  bool get jioSaavnEnabled => _jioSaavnEnabled;
  int _upgradeSessionId = 0;
  int _losslessUpgradeId = 0;
  String?
  _queueSourceId; // Track which playlist/album/artist started this queue
  String?
  _queueSourceTitle; // Track title of which playlist/album/artist started this queue
  String? get queueSourceTitle => _queueSourceTitle;
  Duration? _pendingSeekPosition;
  String? _pendingSeekTrackId;
  bool _durationMigrationInProgress = false;
  static const String _streamAudioCacheDirName = 'stream_audio_cache';
  static const String _durationMigrationKey =
      'persisted_queue_duration_migrated_v1';
  final Connectivity _connectivity = Connectivity();
  final Set<String> _precacheInProgress = <String>{};
  final Queue<Completer<void>> _precacheSlotWaiters = Queue<Completer<void>>();
  int _activePrecacheDownloads = 0;
  bool _isPrecachingAhead = false;
  bool _allowProxyCachingSource = true;
  Timer? _cacheMaintenanceTimer;
  final Map<String, Timer> _liveCacheLogTimers = {};
  final Map<String, int> _liveCacheLastLoggedBytes = {};
  final Map<String, DateTime> _liveCacheLastLoggedAt = {};
  bool _isCrossfading = false;
  bool _crossfadeTriggeredForTrack = false;
  DateTime? _lastVolumeRecoveryAt;
  static const _volumeRecoveryInterval = Duration(milliseconds: 800);
  List<int> _activeSourceQueueIndices = const [];
  Map<int, PlaybackData> _activeSourcePlaybackDataByQueueIndex =
      const <int, PlaybackData>{};
  static const _cacheMaintenanceInterval = Duration(minutes: 3);
  Timer? _youtubeWatchtimeTimer;
  String? _youtubeTrackingVideoId;
  String? _youtubeTrackingCpn;
  bool _youtubeAtrSent = false;
  Duration _youtubeTrackingLastPosition = Duration.zero;
  bool _youtubePlaybackStartSent = false;
  final Set<String> _youtubeTrackingResolveInProgress = <String>{};
  static const _youtubeWatchtimeInterval = Duration(seconds: 10);
  /// Tracking URLs obtained from an authenticated WEB_REMIX player request.
  /// These are session-bound and required for play history to update.
  /// Unauthenticated tracking URLs (from ANDROID_VR/IOS) do NOT update history.
  PlaybackTracking? _authenticatedPlaybackTracking;
  final Set<String> _youtubeTrackingResolveFailed = <String>{};
  bool _isUpgradingStream = false;

  /// Load streaming quality from SharedPreferences on init
  Future<void> _loadStreamingQuality() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final qualityIndex = prefs.getInt(kStreamingQualityKey);
      if (qualityIndex != null &&
          qualityIndex >= 0 &&
          qualityIndex < AudioQuality.values.length) {
        _audioQuality = AudioQuality.values[qualityIndex];
        _updateState(audioQuality: _audioQuality);
        if (kDebugMode) {
          print('AudioPlayerService: Loaded streaming quality: $_audioQuality');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('AudioPlayerService: Failed to load streaming quality: $e');
      }
    }
  }

  /// Save streaming quality to SharedPreferences
  Future<void> _saveStreamingQuality(AudioQuality quality) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(kStreamingQualityKey, quality.index);
    } catch (e) {
      if (kDebugMode) {
        print('AudioPlayerService: Failed to save streaming quality: $e');
      }
    }
  }

  /// Load stream byte-cache settings from SharedPreferences.
  Future<void> _loadStreamCacheSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _streamCacheWifiOnly = prefs.getBool(kStreamCacheWifiOnlyKey) ?? false;
      _streamCacheSizeLimitMb =
          prefs.getInt(kStreamCacheSizeLimitMbKey) ??
          kDefaultStreamCacheSizeLimitMb;
      _streamCacheSizeLimitMb = _streamCacheSizeLimitMb.clamp(
        kMinStreamCacheSizeLimitMb,
        kMaxStreamCacheSizeLimitMb,
      );
      _streamCacheMaxConcurrent =
          prefs.getInt(kStreamCacheMaxConcurrentKey) ??
          kDefaultStreamCacheMaxConcurrent;
      _streamCacheMaxConcurrent = _streamCacheMaxConcurrent.clamp(
        kMinStreamCacheMaxConcurrent,
        kMaxStreamCacheMaxConcurrent,
      );
      _crossfadeDurationMs =
          prefs.getInt(kCrossfadeDurationMsKey) ?? kDefaultCrossfadeDurationMs;
      _crossfadeDurationMs = _crossfadeDurationMs.clamp(
        kMinCrossfadeDurationMs,
        kMaxCrossfadeDurationMs,
      );
      // 1–3s options were removed; move anyone on them to the new default.
      if (_crossfadeDurationMs > 0 && _crossfadeDurationMs < 5000) {
        _crossfadeDurationMs = kDefaultCrossfadeDurationMs;
        unawaited(
          prefs.setInt(kCrossfadeDurationMsKey, _crossfadeDurationMs),
        );
      }

      _updateState(
        streamCacheWifiOnly: _streamCacheWifiOnly,
        streamCacheSizeLimitMb: _streamCacheSizeLimitMb,
        streamCacheMaxConcurrent: _streamCacheMaxConcurrent,
        crossfadeDurationMs: _crossfadeDurationMs,
      );

      unawaited(_applyCrossfadeDurationToPlayer());
      unawaited(_enforceAudioCacheLimit());
    } catch (e) {
      if (kDebugMode) {
        print('AudioPlayerService: Failed to load stream cache settings: $e');
      }
    }
  }

  bool get streamCacheWifiOnly => _streamCacheWifiOnly;
  int get streamCacheSizeLimitMb => _streamCacheSizeLimitMb;
  int get streamCacheMaxConcurrent => _streamCacheMaxConcurrent;
  int get crossfadeDurationMs => _crossfadeDurationMs;
  AudioPlayer get _inactivePlayer =>
      identical(_player, _primaryPlayer) ? _secondaryPlayer : _primaryPlayer;

  Future<void> _applyCrossfadeDurationToPlayer() async {
    try {
      if (_crossfadeDurationMs <= 0) {
        _crossfadeTriggeredForTrack = false;
        await _player.setVolume(1.0);
        await _inactivePlayer.setVolume(1.0);
      }
      if (kDebugMode) {
        print(
          'AudioPlayerService: Transition fade set to ${_crossfadeDurationMs}ms',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('AudioPlayerService: Failed to apply crossfade: $e');
      }
    }
  }

  Future<void> setStreamCacheWifiOnly(bool value) async {
    _streamCacheWifiOnly = value;
    _updateState(streamCacheWifiOnly: value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kStreamCacheWifiOnlyKey, value);
    } catch (e) {
      if (kDebugMode) {
        print(
          'AudioPlayerService: Failed to persist wifi-only cache setting: $e',
        );
      }
    }

    if (!value) {
      _schedulePrecacheAhead();
    }
  }

  Future<void> setStreamCacheSizeLimitMb(int value) async {
    final clamped = value.clamp(
      kMinStreamCacheSizeLimitMb,
      kMaxStreamCacheSizeLimitMb,
    );
    _streamCacheSizeLimitMb = clamped;
    _updateState(streamCacheSizeLimitMb: clamped);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(kStreamCacheSizeLimitMbKey, clamped);
    } catch (e) {
      if (kDebugMode) {
        print('AudioPlayerService: Failed to persist stream cache limit: $e');
      }
    }
    await _enforceAudioCacheLimit();
  }

  Future<void> setStreamCacheMaxConcurrent(int value) async {
    final clamped = value.clamp(
      kMinStreamCacheMaxConcurrent,
      kMaxStreamCacheMaxConcurrent,
    );
    _streamCacheMaxConcurrent = clamped;
    _updateState(streamCacheMaxConcurrent: clamped);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(kStreamCacheMaxConcurrentKey, clamped);
    } catch (e) {
      if (kDebugMode) {
        print(
          'AudioPlayerService: Failed to persist stream cache max concurrent: $e',
        );
      }
    }
    _schedulePrecacheAhead();
  }

  Future<void> setCrossfadeDurationMs(int value) async {
    final clamped = value.clamp(
      kMinCrossfadeDurationMs,
      kMaxCrossfadeDurationMs,
    );
    _crossfadeDurationMs = clamped;
    _updateState(crossfadeDurationMs: clamped);
    await _applyCrossfadeDurationToPlayer();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(kCrossfadeDurationMsKey, clamped);
    } catch (e) {
      if (kDebugMode) {
        print(
          'AudioPlayerService: Failed to persist crossfade duration setting: $e',
        );
      }
    }
  }

  /// Load Stats for nerds preference
  Future<void> _loadNerdStatsSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _showNerdStats = prefs.getBool(kShowNerdStatsKey) ?? false;
      _updateState(showNerdStats: _showNerdStats);
    } catch (e) {
      if (kDebugMode) {
        print('AudioPlayerService: Failed to load nerd stats setting: $e');
      }
    }
  }

  /// Toggle Stats for nerds preference
  Future<void> setShowNerdStats(bool enabled) async {
    _showNerdStats = enabled;
    _updateState(showNerdStats: enabled);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kShowNerdStatsKey, enabled);
    } catch (e) {
      if (kDebugMode) {
        print('AudioPlayerService: Failed to persist nerd stats setting: $e');
      }
    }
  }

  /// Load JioSaavn source preference
  Future<void> _loadJioSaavnSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _jioSaavnEnabled = prefs.getBool(kJioSaavnEnabledKey) ?? true;
      _updateState(jioSaavnEnabled: _jioSaavnEnabled);
    } catch (e) {
      if (kDebugMode) {
        print('AudioPlayerService: Failed to load JioSaavn setting: $e');
      }
    }
  }

  /// Toggle JioSaavn source preference
  Future<void> setJioSaavnEnabled(bool enabled) async {
    _jioSaavnEnabled = enabled;
    _updateState(jioSaavnEnabled: enabled);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kJioSaavnEnabledKey, enabled);
    } catch (e) {
      if (kDebugMode) {
        print('AudioPlayerService: Failed to persist JioSaavn setting: $e');
      }
    }
  }

  Duration get _crossfadeDuration =>
      Duration(milliseconds: _crossfadeDurationMs);

  Future<void> _setVolumeSafely(
    AudioPlayer player,
    double volume, {
    String? context,
  }) async {
    try {
      await player
          .setVolume(volume)
          .timeout(const Duration(milliseconds: 1200));
    } catch (e) {
      if (kDebugMode) {
        print(
          'AudioPlayerService: setVolume(${volume.toStringAsFixed(2)}) failed${context == null ? '' : ' [$context]'}: $e',
        );
      }
    }
  }

  Future<void> _runOverlapFade({
    required AudioPlayer outgoing,
    required AudioPlayer incoming,
    required Duration duration,
  }) async {
    if (duration <= Duration.zero) {
      await Future.wait(<Future<void>>[
        _setVolumeSafely(outgoing, 0.0, context: 'fade-immediate-out'),
        _setVolumeSafely(incoming, 1.0, context: 'fade-immediate-in'),
      ]);
      return;
    }

    const steps = 24;
    final stepDelayMs = (duration.inMilliseconds / steps).round().clamp(
      10,
      500,
    );
    final stepDelay = Duration(milliseconds: stepDelayMs);
    try {
      for (int step = 1; step <= steps; step++) {
        final t = step / steps;
        // Equal-power curve avoids perceived dip/silence in the middle.
        final outgoingGain = cos(t * pi * 0.5);
        final incomingGain = sin(t * pi * 0.5);
        await Future.wait(<Future<void>>[
          _setVolumeSafely(
            outgoing,
            outgoingGain.clamp(0.0, 1.0),
            context: 'fade-step-$step-out',
          ),
          _setVolumeSafely(
            incoming,
            incomingGain.clamp(0.0, 1.0),
            context: 'fade-step-$step-in',
          ),
        ]);
        await Future.delayed(stepDelay);
      }
    } finally {
      // Always force final settled volumes even if ramp loop is interrupted.
      await Future.wait(<Future<void>>[
        _setVolumeSafely(outgoing, 0.0, context: 'fade-final-out'),
        _setVolumeSafely(incoming, 1.0, context: 'fade-final-in'),
      ]);
    }
  }

  Future<void> _stabilizeIncomingAfterCrossfade(AudioPlayer incoming) async {
    // Re-apply audio route natively in case just_audio or OS dropped it during player switch
    AudioRoutingService.reapplyAudioRoute();
    // Some devices/platform stacks can briefly re-emit stale low volume state
    // right after source/track handoff. Re-assert full gain a few times.
    const retryDelaysMs = <int>[0, 120, 320, 700, 1400];
    for (final delayMs in retryDelaysMs) {
      if (delayMs > 0) {
        await Future.delayed(Duration(milliseconds: delayMs));
      }
      if (!identical(_player, incoming)) return;
      if (!incoming.playing) {
        unawaited(incoming.play());
      }
      await _setVolumeSafely(
        incoming,
        1.0,
        context: 'post-crossfade-stabilize',
      );
      if (incoming.volume >= 0.98) {
        break;
      }
    }
  }

  void _recoverStuckVolumeIfNeeded() {
    if (_isCrossfading) return;
    if (_crossfadeDurationMs <= 0) return;
    if (!_player.playing) return;
    final currentVolume = _player.volume;
    if (currentVolume >= 0.95) return;

    final now = DateTime.now();
    final last = _lastVolumeRecoveryAt;
    if (last != null && now.difference(last) < _volumeRecoveryInterval) {
      return;
    }
    _lastVolumeRecoveryAt = now;
    if (kDebugMode) {
      print(
        'AudioPlayerService: Recovering stuck player volume ${currentVolume.toStringAsFixed(2)} -> 1.00',
      );
    }
    unawaited(_setVolumeSafely(_player, 1.0, context: 'runtime-recovery'));
  }

  Future<PlaybackData?> _resolvePlaybackDataForLocalTrack(
    Track track,
    File file,
    int fileSize,
  ) async {
    try {
      final path = file.path.toLowerCase();
      String codec = 'Audio';
      String mimeType = 'audio/unknown';
      if (path.endsWith('.mp3')) {
        codec = 'MP3';
        mimeType = 'audio/mpeg';
      } else if (path.endsWith('.m4a') || path.endsWith('.aac')) {
        codec = 'AAC';
        mimeType = 'audio/mp4';
      } else if (path.endsWith('.opus')) {
        codec = 'Opus';
        mimeType = 'audio/opus';
      } else if (path.endsWith('.webm')) {
        codec = 'Opus';
        mimeType = 'audio/webm';
      } else if (path.endsWith('.flac')) {
        codec = 'FLAC';
        mimeType = 'audio/flac';
      } else if (path.endsWith('.wav')) {
        codec = 'WAV';
        mimeType = 'audio/wav';
      } else if (path.endsWith('.ogg')) {
        codec = 'Vorbis';
        mimeType = 'audio/ogg';
      }

      int? bitrateBps;

      // 1. Try reading from audio metadata (ID3, Vorbis, RIFF, MP4)
      try {
        final metadata = readMetadata(file, getImage: false);
        if (metadata.bitrate != null && metadata.bitrate! > 0) {
          bitrateBps = metadata.bitrate! > 1000
              ? metadata.bitrate!
              : metadata.bitrate! * 1000;
        }
      } catch (_) {}

      // 2. Check if this file is a known download entity
      bool isDownloaded = false;
      try {
        if (!Hive.isBoxOpen('music_downloads')) {
          await Hive.openBox<DownloadEntity>('music_downloads');
        }
        final box = Hive.box<DownloadEntity>('music_downloads');
        final normPath = file.path.replaceAll('\\', '/').toLowerCase();
        for (final entity in box.values) {
          final entityNorm =
              entity.localPath.replaceAll('\\', '/').toLowerCase();
          if (entityNorm == normPath || entity.trackId == track.id) {
            isDownloaded = true;
            if (bitrateBps == null && entity.durationMs > 0 && fileSize > 0) {
              final seconds = entity.durationMs / 1000.0;
              if (seconds > 0) {
                final kbps = ((fileSize * 8) / seconds / 1000).round();
                if (kbps > 0) bitrateBps = kbps * 1000;
              }
            }
            break;
          }
        }
      } catch (_) {}

      // 3. If bitrate still not detected from metadata/entity, check track duration
      if (bitrateBps == null && track.duration > Duration.zero && fileSize > 0) {
        final seconds = track.duration.inMilliseconds / 1000.0;
        if (seconds > 0) {
          final kbps = ((fileSize * 8) / seconds / 1000).round();
          if (kbps > 0) bitrateBps = kbps * 1000;
        }
      }

      // If no bitrate info is present, return null so stats for nerds does not show
      if (bitrateBps == null || bitrateBps <= 0) {
        return null;
      }

      final source = isDownloaded ? 'Downloaded' : 'Local';
      final format = AudioFormat(
        mimeType: mimeType,
        bitrate: bitrateBps,
        codecs: codec,
        contentLength: fileSize,
      );

      return PlaybackData(
        format: format,
        streamUrl: file.uri.toString(),
        streamExpiresInSeconds: 86400 * 365,
        fetchedAt: DateTime.now(),
        audioSource: source,
      );
    } catch (_) {
      return null;
    }
  }

  Future<({AudioSource source, PlaybackData? playbackData})>
  _buildSourceForTrack(Track track) async {
    String? resolvedLocalPath = track.localFilePath;
    if (resolvedLocalPath == null) {
      try {
        if (!Hive.isBoxOpen('music_downloads')) {
          await Hive.openBox<DownloadEntity>('music_downloads');
        }
        final box = Hive.box<DownloadEntity>('music_downloads');
        final entity = box.values.where((e) => e.trackId == track.id).firstOrNull;
        if (entity != null) {
          resolvedLocalPath = entity.localPath;
        }
      } catch (_) {}
    }

    if (resolvedLocalPath != null) {
      final localFile = File(resolvedLocalPath);
      if (await localFile.exists()) {
        final fileSize = await localFile.length();
        if (fileSize >= 10000) {
          if (LocalArtworkService.isArtistMissing(track.artist)) {
            unawaited(LocalArtworkService.fetchOnlineMetadata(track));
          }
          final playbackData = await _resolvePlaybackDataForLocalTrack(
            track,
            localFile,
            fileSize,
          );
          return (
            source: AudioSource.uri(Uri.file(resolvedLocalPath), tag: track),
            playbackData: playbackData,
          );
        }
      }
    }

    // Crossfading into a track whose lossless copy was resolved ahead of
    // time: fade straight into the FLAC.
    if (_qualityAllowsLossless) {
      final lossless = AddonService.instance.cachedFor(track);
      if (lossless != null) {
        _logLossless('Crossfading straight into ${lossless.stream.formatLabel}');
        return (
          source: _addonAudioSource(lossless, track),
          // This track isn't current yet; its history tracking is resolved
          // once it is, so don't carry the outgoing track's over.
          playbackData: _addonPlaybackData(lossless, forCurrentTrack: false),
        );
      }
    }

    final result = await _ytPlayerUtils.playerResponseForPlayback(
      track.id,
      quality: _audioQuality,
      isMetered: false,
    );
    if (!result.isSuccess || result.data == null) {
      throw Exception(
        result.error ?? 'Could not resolve stream for ${track.id}',
      );
    }

    final playbackData = result.data!;
    final source = await _streamingAudioSourceForTrack(
      track,
      playbackData,
      preferDirectStreamWithBackgroundPrecache: true,
    );
    return (source: source, playbackData: playbackData);
  }

  int? _nextQueueIndexForTransition() {
    if (_queue.isEmpty) return null;
    if (_currentIndex < _queue.length - 1) return _currentIndex + 1;
    if (_loopMode == LoopMode.all) return 0;
    return null;
  }

  Future<void> _crossfadeToIndex(int targetIndex) async {
    if (_isCrossfading) return;
    if (_crossfadeDurationMs <= 0) {
      _currentIndex = targetIndex;
      _currentTrack = _queue[targetIndex];
      await _loadAndPlayCurrent();
      return;
    }
    if (targetIndex < 0 || targetIndex >= _queue.length) return;
    if (_currentIndex == targetIndex) return;
    if (_jamsModeEnabled) {
      _currentIndex = targetIndex;
      _currentTrack = _queue[targetIndex];
      await _loadAndPlayCurrent();
      return;
    }

    _isCrossfading = true;
    var crossfadeSucceeded = false;
    final outgoingPlayer = _player;
    final incomingPlayer = _inactivePlayer;
    final targetTrack = _queue[targetIndex];
    final sourceTrackId = _currentTrack?.id ?? 'unknown';

    try {
      final built = await _buildSourceForTrack(targetTrack);
      await incomingPlayer.stop();
      await incomingPlayer.setLoopMode(_nativeLoopModeFor(_loopMode));
      await incomingPlayer.setSpeed(outgoingPlayer.speed);
      await incomingPlayer.setAudioSource(built.source, preload: true);
      await _setVolumeSafely(
        incomingPlayer,
        0.12,
        context: 'crossfade-bootstrap',
      );

      _player = incomingPlayer;
      _currentIndex = targetIndex;
      var enrichedTrack = targetTrack;
      final crossfadeDetails = built.playbackData?.videoDetails;
      if (crossfadeDetails != null) {
        const badPlaceholders = {
          'unknown artist',
          'song',
          'video',
          'album',
          'single',
          'ep',
          'playlist',
          '',
        };
        final artistLower = enrichedTrack.artist.toLowerCase().trim();
        if (badPlaceholders.contains(artistLower) &&
            crossfadeDetails.author.isNotEmpty &&
            !badPlaceholders.contains(crossfadeDetails.author.toLowerCase().trim())) {
          enrichedTrack =
              enrichedTrack.copyWith(artist: crossfadeDetails.author);
        }
        if (enrichedTrack.duration <= Duration.zero &&
            crossfadeDetails.duration > Duration.zero) {
          enrichedTrack =
              enrichedTrack.copyWith(duration: crossfadeDetails.duration);
        }
        if (enrichedTrack != targetTrack) {
          _queue[targetIndex] = enrichedTrack;
          for (int i = 0; i < _originalQueue.length; i++) {
            if (_originalQueue[i].id == enrichedTrack.id) {
              _originalQueue[i] = enrichedTrack;
              break;
            }
          }
          _queueRevision++;
        }
      }
      _currentTrack = enrichedTrack;
      _currentPlaybackData = built.playbackData;
      _activeSourceQueueIndices = <int>[targetIndex];
      _activeSourcePlaybackDataByQueueIndex = built.playbackData == null
          ? const <int, PlaybackData>{}
          : <int, PlaybackData>{targetIndex: built.playbackData!};
      _crossfadeTriggeredForTrack = false;

      final newDuration = incomingPlayer.duration;
      if (newDuration != null) {
        _applyDurationToCurrentTrack(newDuration);
      }

      _updateState(
        currentTrack: _currentTrack,
        currentIndex: _currentIndex,
        currentPlaybackData: _currentPlaybackData,
        queue: _queue,
        queueRevision: _queueRevision,
        duration: newDuration,
        resetDuration: newDuration == null,
        isLoading: false,
      );
      _saveQueueDebounced();
      _prefetchNextTrack();
      _scheduleLyricsPrefetchAroundCurrent();

      AudioRoutingService.reapplyAudioRoute();
      unawaited(incomingPlayer.play());
      for (int i = 1; i <= 6; i++) {
        Future.delayed(Duration(milliseconds: i * 25), AudioRoutingService.reapplyAudioRoute);
      }

      await Future.delayed(const Duration(milliseconds: 90));
      if (kDebugMode) {
        print(
          'AudioPlayerService: Crossfade started $sourceTrackId -> ${targetTrack.id} (${_crossfadeDurationMs}ms)',
        );
      }
      await _runOverlapFade(
        outgoing: outgoingPlayer,
        incoming: incomingPlayer,
        duration: _crossfadeDuration,
      );

      await outgoingPlayer.stop();
      await _setVolumeSafely(
        outgoingPlayer,
        1.0,
        context: 'crossfade-reset-outgoing',
      );
      await _setVolumeSafely(
        incomingPlayer,
        1.0,
        context: 'crossfade-settle-incoming',
      );
      if (!incomingPlayer.playing) {
        unawaited(incomingPlayer.play());
      }
      await _stabilizeIncomingAfterCrossfade(incomingPlayer);
      if (kDebugMode) {
        print(
          'AudioPlayerService: Crossfade completed on ${targetTrack.id}, incomingVolume=${incomingPlayer.volume.toStringAsFixed(2)}',
        );
      }
      crossfadeSucceeded = true;
    } catch (e) {
      if (kDebugMode) {
        print(
          'AudioPlayerService: Crossfade failed, fallback to hard switch: $e',
        );
      }
      _player = outgoingPlayer;
      _currentIndex = targetIndex;
      _currentTrack = _queue[targetIndex];
      // (The hard switch goes through the normal load, which upgrades.)
      await _loadAndPlayCurrent();
    } finally {
      _isCrossfading = false;
    }
    // Most tracks start here (crossfade is on by default), so this is where
    // the second look for a lossless copy matters most.
    final arrived = _currentTrack;
    if (crossfadeSucceeded &&
        arrived != null &&
        arrived.id == targetTrack.id &&
        _currentPlaybackData?.isLive != true) {
      unawaited(_upgradeToLosslessIfPossible(arrived));
    }
  }

  void _maybeTriggerAutoCrossfade(Duration currentPosition) {
    if (_jamsModeEnabled) return;
    // With Automix on, the engine plans and runs every transition.
    if (_automixOn) return;
    if (_crossfadeDurationMs <= 0) return;
    if (_isCrossfading) return;
    if (_crossfadeTriggeredForTrack) return;
    if (_loopMode == LoopMode.one) return;
    if (!_player.playing) return;
    // Live streams have no real end — never crossfade/advance off them.
    if (_currentPlaybackData?.isLive == true) return;

    final duration = _player.duration;
    if (duration == null || duration <= Duration.zero) return;
    final remaining = duration - currentPosition;
    if (remaining <= Duration.zero) return;

    final triggerLeadMs = max(300, _crossfadeDurationMs + 120);
    if (remaining.inMilliseconds > triggerLeadMs) return;

    final nextIndex = _nextQueueIndexForTransition();
    if (nextIndex == null) return;

    _crossfadeTriggeredForTrack = true;
    unawaited(_crossfadeToIndex(nextIndex));
  }

  int _effectivePrecacheConcurrency() {
    return _streamCacheMaxConcurrent.clamp(
      kMinStreamCacheMaxConcurrent,
      kMaxStreamCacheMaxConcurrent,
    );
  }

  Future<void> _acquirePrecacheSlot() async {
    while (true) {
      final limit = _effectivePrecacheConcurrency();
      if (_activePrecacheDownloads < limit) {
        _activePrecacheDownloads++;
        return;
      }

      final waiter = Completer<void>();
      _precacheSlotWaiters.add(waiter);
      await waiter.future;
    }
  }

  void _releasePrecacheSlot() {
    if (_activePrecacheDownloads > 0) {
      _activePrecacheDownloads--;
    }

    while (_precacheSlotWaiters.isNotEmpty) {
      final waiter = _precacheSlotWaiters.removeFirst();
      if (!waiter.isCompleted) {
        waiter.complete();
        break;
      }
    }
  }

  String _sanitizeCacheKey(String value) {
    return value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  String _formatTransferRate(double bytesPerSecond) {
    if (bytesPerSecond >= 1024 * 1024) {
      return '${(bytesPerSecond / 1024 / 1024).toStringAsFixed(2)} MB/s';
    }
    return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
  }

  void _applyPrecacheRequestHeaders(HttpClientRequest request) {
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    // Same identity as the client that issued the URL (see streamHeadersFor).
    final clientHeaders = InnerTubeClient.streamHeadersFor(request.uri);
    request.headers.set(
      HttpHeaders.userAgentHeader,
      clientHeaders['User-Agent'] ??
          InnerTubeClient.androidVr165.userAgent,
    );
    clientHeaders.forEach((key, value) {
      if (key != 'User-Agent') request.headers.set(key, value);
    });
    request.headers.set(HttpHeaders.acceptHeader, '*/*');
  }

  Future<int?> _downloadWithParallelRanges({
    required Track track,
    required Uri streamUri,
    required File tempFile,
    required int expectedBytes,
  }) async {
    if (expectedBytes < kParallelPrecacheMinBytes) {
      return null;
    }

    final partCount = min(
      kParallelPrecachePartCount,
      max(2, expectedBytes ~/ (512 * 1024)),
    );

    final parts = <({int start, int end, File file})>[];
    int cursor = 0;
    final basePartSize = expectedBytes ~/ partCount;
    final remainder = expectedBytes % partCount;
    for (int i = 0; i < partCount; i++) {
      final partSize = basePartSize + (i < remainder ? 1 : 0);
      final start = cursor;
      final end = start + partSize - 1;
      cursor = end + 1;
      parts.add((
        start: start,
        end: end,
        file: File('${tempFile.path}.seg$i.part'),
      ));
    }

    if (kDebugMode) {
      print(
        'AudioPlayerService: Trying parallel part pre-cache for ${track.id} '
        '(${_formatBytes(expectedBytes)}, parts=$partCount)',
      );
    }

    int downloadedBytes = 0;
    int nextProgressLogPercent = 10;
    final downloadTimer = Stopwatch()..start();
    int speedSampleBytes = 0;
    int speedSampleMs = 0;

    String sampleSpeed() {
      final nowMs = downloadTimer.elapsedMilliseconds;
      final elapsedMs = max(1, nowMs - speedSampleMs);
      final deltaBytes = max(0, downloadedBytes - speedSampleBytes);
      speedSampleBytes = downloadedBytes;
      speedSampleMs = nowMs;
      return _formatTransferRate(deltaBytes * 1000 / elapsedMs);
    }

    void maybeLogProgress() {
      if (!kDebugMode) return;
      final progress = ((downloadedBytes / expectedBytes) * 100).clamp(
        0.0,
        100.0,
      );
      if (progress < nextProgressLogPercent) return;
      final speed = sampleSpeed();
      debugPrint(
        'AudioPlayerService: Parallel pre-cache progress ${track.id} '
        '${progress.toStringAsFixed(1)}% '
        '(${_formatBytes(downloadedBytes)} / ${_formatBytes(expectedBytes)} @ $speed)',
      );
      while (progress >= nextProgressLogPercent) {
        nextProgressLogPercent += 10;
      }
    }

    Future<void> cleanupParts() async {
      for (final part in parts) {
        if (await part.file.exists()) {
          await part.file.delete();
        }
      }
    }

    try {
      for (final part in parts) {
        if (await part.file.exists()) {
          await part.file.delete();
        }
      }

      Future<void> downloadPart(({int start, int end, File file}) part) async {
        HttpClient? partClient;
        IOSink? partSink;
        try {
          partClient = HttpClient()
            ..connectionTimeout = const Duration(seconds: 20);
          final request = await partClient.getUrl(streamUri);
          _applyPrecacheRequestHeaders(request);
          request.headers.set(
            HttpHeaders.rangeHeader,
            'bytes=${part.start}-${part.end}',
          );

          final response = await request.close();
          if (response.statusCode != 206) {
            throw HttpException(
              'Range request returned HTTP ${response.statusCode}',
            );
          }

          partSink = part.file.openWrite(mode: FileMode.writeOnly);
          int partBytes = 0;
          await for (final chunk in response) {
            partSink.add(chunk);
            partBytes += chunk.length;
            downloadedBytes += chunk.length;
            maybeLogProgress();
          }
          await partSink.flush();
          await partSink.close();
          partSink = null;

          final expectedPartBytes = part.end - part.start + 1;
          if (partBytes != expectedPartBytes) {
            throw FormatException(
              'Range part size mismatch ($partBytes vs $expectedPartBytes)',
            );
          }
        } finally {
          if (partSink != null) {
            await partSink.close();
          }
          partClient?.close(force: true);
        }
      }

      await Future.wait(parts.map(downloadPart));

      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      final mergeSink = tempFile.openWrite(mode: FileMode.writeOnly);
      try {
        for (final part in parts) {
          await mergeSink.addStream(part.file.openRead());
        }
        await mergeSink.flush();
      } finally {
        await mergeSink.close();
      }

      final mergedBytes = await tempFile.length();
      if (mergedBytes != expectedBytes) {
        throw FormatException(
          'Merged range file size mismatch ($mergedBytes vs $expectedBytes)',
        );
      }

      final elapsedMs = max(1, downloadTimer.elapsedMilliseconds);
      final avgSpeed = _formatTransferRate(mergedBytes * 1000 / elapsedMs);
      if (kDebugMode) {
        print(
          'AudioPlayerService: Parallel pre-cache complete ${track.id} '
          '(${_formatBytes(mergedBytes)}, avg $avgSpeed, parts=$partCount)',
        );
      }

      await cleanupParts();
      return mergedBytes;
    } catch (e) {
      if (kDebugMode) {
        print(
          'AudioPlayerService: Parallel pre-cache fallback for ${track.id}: $e',
        );
      }
      await cleanupParts();
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      return null;
    }
  }

  void _stopLiveCacheProgressLogger(String cachePath) {
    _liveCacheLogTimers.remove(cachePath)?.cancel();
    _liveCacheLastLoggedBytes.remove(cachePath);
    _liveCacheLastLoggedAt.remove(cachePath);
  }

  void _stopAllLiveCacheProgressLoggers() {
    for (final timer in _liveCacheLogTimers.values) {
      timer.cancel();
    }
    _liveCacheLogTimers.clear();
    _liveCacheLastLoggedBytes.clear();
    _liveCacheLastLoggedAt.clear();
  }

  void _startLiveCacheProgressLogger({
    required Track track,
    required File cacheFile,
    int? expectedBytes,
  }) {
    if (!kDebugMode || kIsWeb) return;

    final cachePath = cacheFile.path;
    if (_liveCacheLogTimers.containsKey(cachePath)) return;
    _liveCacheLastLoggedAt[cachePath] = DateTime.now();

    int idleTicks = 0;
    if (expectedBytes != null && expectedBytes > 0) {
      debugPrint(
        'AudioPlayerService: Live cache monitor started for ${track.id} '
        '(target ${_formatBytes(expectedBytes)})',
      );
    } else {
      debugPrint(
        'AudioPlayerService: Live cache monitor started for ${track.id}',
      );
    }

    final timer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (_liveCacheLogTimers[cachePath] != timer) {
        timer.cancel();
        return;
      }

      try {
        if (!await cacheFile.exists()) {
          idleTicks++;
          if (idleTicks >= 20) {
            _stopLiveCacheProgressLogger(cachePath);
          }
          return;
        }

        final size = await cacheFile.length();
        final lastLoggedBytes = _liveCacheLastLoggedBytes[cachePath] ?? 0;
        final grewEnough = size - lastLoggedBytes >= (512 * 1024);
        final isComplete =
            expectedBytes != null && expectedBytes > 0 && size >= expectedBytes;

        if (!grewEnough && !isComplete) {
          idleTicks++;
          if (idleTicks >= 20) {
            _stopLiveCacheProgressLogger(cachePath);
          }
          return;
        }

        idleTicks = 0;
        final now = DateTime.now();
        final lastAt = _liveCacheLastLoggedAt[cachePath] ?? now;
        final elapsedMs = max(1, now.difference(lastAt).inMilliseconds);
        final deltaBytes = max(0, size - lastLoggedBytes);
        final throughput = _formatTransferRate(deltaBytes * 1000 / elapsedMs);
        _liveCacheLastLoggedBytes[cachePath] = size;
        _liveCacheLastLoggedAt[cachePath] = now;
        if (expectedBytes != null && expectedBytes > 0) {
          final progress = ((size / expectedBytes) * 100).clamp(0.0, 100.0);
          debugPrint(
            'AudioPlayerService: Live stream-cache progress ${track.id} '
            '${progress.toStringAsFixed(1)}% '
            '(${_formatBytes(size)} / ${_formatBytes(expectedBytes)} @ $throughput)',
          );
          if (isComplete) {
            debugPrint(
              'AudioPlayerService: Live stream-cache complete for ${track.id}',
            );
            _stopLiveCacheProgressLogger(cachePath);
          }
        } else {
          debugPrint(
            'AudioPlayerService: Live stream-cache progress ${track.id} '
            '${_formatBytes(size)} (total size unknown @ $throughput)',
          );
        }
      } catch (_) {
        _stopLiveCacheProgressLogger(cachePath);
      }
    });

    _liveCacheLogTimers[cachePath] = timer;
  }

  Future<Directory> _getStreamAudioCacheDir({bool create = true}) async {
    final tempDir = await getTemporaryDirectory();
    final cacheDir = Directory('${tempDir.path}/$_streamAudioCacheDirName');
    if (create && !await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  Future<File> _cacheFileForTrack(
    Track track,
    PlaybackData playbackData,
  ) async {
    final cacheDir = await _getStreamAudioCacheDir();
    final safeTrackId = _sanitizeCacheKey(track.id);
    final cacheKey =
        '${safeTrackId}_${_audioQuality.name}_${playbackData.format.bitrate}';
    return File('${cacheDir.path}/$cacheKey.audio');
  }

  Future<bool> _isConnectedToWifi() async {
    if (kIsWeb) return true;
    try {
      final connections = await _connectivity.checkConnectivity();
      return connections.contains(ConnectivityResult.wifi) ||
          connections.contains(ConnectivityResult.ethernet);
    } catch (e) {
      if (kDebugMode) {
        print('AudioPlayerService: Connectivity check failed: $e');
      }
      return false;
    }
  }

  Future<bool> _canPrecacheOnCurrentNetwork() async {
    if (!_streamCacheWifiOnly) return true;
    return await _isConnectedToWifi();
  }

  Future<void> _touchCacheFile(File file) async {
    try {
      if (await file.exists()) {
        await file.setLastModified(DateTime.now());
      }
    } catch (_) {}
  }

  Future<void> _deleteAudioCacheArtifact(File file) async {
    _stopLiveCacheProgressLogger(file.path);
    final mimeFile = File('${file.path}.mime');
    final partialFile = File('${file.path}.part');
    final precachePartFile = File('${file.path}.precache.part');
    if (await file.exists()) {
      await file.delete();
    }
    if (await mimeFile.exists()) {
      await mimeFile.delete();
    }
    if (await partialFile.exists()) {
      await partialFile.delete();
    }
    if (await precachePartFile.exists()) {
      await precachePartFile.delete();
    }
  }

  Future<int> getStreamAudioCacheSizeBytes() async {
    if (kIsWeb) return 0;
    try {
      final cacheDir = await _getStreamAudioCacheDir(create: false);
      if (!await cacheDir.exists()) return 0;
      int totalBytes = 0;
      await for (final entity in cacheDir.list(followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.audio')) continue;
        totalBytes += await entity.length();
      }
      return totalBytes;
    } catch (_) {
      return 0;
    }
  }

  /// Clear all on-disk streaming audio cache files.
  Future<void> clearStreamAudioCache() async {
    await _clearAllAudioCache();
  }

  Future<void> _enforceAudioCacheLimit() async {
    if (kIsWeb) return;
    try {
      final cacheDir = await _getStreamAudioCacheDir(create: false);
      if (!await cacheDir.exists()) return;

      final files = <File>[];
      await for (final entity in cacheDir.list(followLinks: false)) {
        if (entity is File && entity.path.endsWith('.audio')) {
          files.add(entity);
        }
      }
      if (files.isEmpty) return;

      int totalSizeBytes = 0;
      final fileStats = <({File file, int size, DateTime modified})>[];
      for (final file in files) {
        if (!await file.exists()) continue;
        final stat = await file.stat();
        final size = stat.size;
        totalSizeBytes += size;
        fileStats.add((file: file, size: size, modified: stat.modified));
      }

      final maxSizeBytes = _streamCacheSizeLimitMb * 1024 * 1024;
      if (totalSizeBytes <= maxSizeBytes) return;

      fileStats.sort((a, b) => a.modified.compareTo(b.modified));
      for (final entry in fileStats) {
        if (totalSizeBytes <= maxSizeBytes) break;
        await _deleteAudioCacheArtifact(entry.file);
        totalSizeBytes -= entry.size;
      }
    } catch (e) {
      if (kDebugMode) {
        print('AudioPlayerService: Failed to enforce cache limit: $e');
      }
    }
  }

  Future<AudioSource> _streamingAudioSourceForTrack(
    Track track,
    PlaybackData playbackData, {
    bool preferDirectStreamWithBackgroundPrecache = false,
  }) async {
    final streamUri = Uri.parse(playbackData.streamUrl);
    // The user agent (and origin) of the client that produced this URL.
    final streamHeaders = InnerTubeClient.streamHeadersFor(streamUri);
    final headers = streamHeaders.isEmpty ? null : streamHeaders;
    if (kIsWeb) {
      return AudioSource.uri(streamUri, headers: headers, tag: track);
    }

    // Live streams are an endless HLS/DASH manifest — hand the manifest URL
    // straight to the player (ExoPlayer plays live HLS/DASH natively) and never
    // attempt to file-cache it. The .m3u8 URL lets ExoPlayer infer HLS.
    if (playbackData.isLive || playbackData.isManifestStream) {
      if (kDebugMode) {
        print(
          'AudioPlayerService: Live/manifest stream for ${track.id} → direct manifest source (no cache)',
        );
      }
      return AudioSource.uri(streamUri, headers: headers, tag: track);
    }

    final cacheFile = await _cacheFileForTrack(track, playbackData);
    if (await cacheFile.exists()) {
      final size = await cacheFile.length();
      if (size < kMinValidStreamCacheFileBytes) {
        await _deleteAudioCacheArtifact(cacheFile);
      } else {
        _stopLiveCacheProgressLogger(cacheFile.path);
        unawaited(_touchCacheFile(cacheFile));
        final expectedBytes = playbackData.format.contentLength;
        if (kDebugMode) {
          if (expectedBytes != null && expectedBytes > 0) {
            final progress = ((size / expectedBytes) * 100).clamp(0.0, 100.0);
            print(
              'AudioPlayerService: Using cached audio bytes for ${track.id} '
              '(${_formatBytes(size)} / ${_formatBytes(expectedBytes)}, ${progress.toStringAsFixed(1)}%)',
            );
          } else {
            print(
              'AudioPlayerService: Using cached audio bytes for ${track.id} '
              '(${_formatBytes(size)})',
            );
          }
        }
        return AudioSource.uri(Uri.file(cacheFile.path), tag: track);
      }
    }

    // Avoid competing writers for the same cache file.
    if (_precacheInProgress.contains(track.id)) {
      _stopLiveCacheProgressLogger(cacheFile.path);
      if (kDebugMode) {
        print(
          'AudioPlayerService: Pre-cache in progress for ${track.id}, using direct stream',
        );
      }
      return AudioSource.uri(streamUri, headers: headers, tag: track);
    }

    if (!_allowProxyCachingSource) {
      _stopLiveCacheProgressLogger(cacheFile.path);
      if (preferDirectStreamWithBackgroundPrecache) {
        if (await _canPrecacheOnCurrentNetwork()) {
          unawaited(_precacheTrackAudioBytes(track, playbackData));
        } else if (kDebugMode) {
          print(
            'AudioPlayerService: Skipping aggressive background cache for ${track.id} (Wi-Fi only)',
          );
        }
      }
      if (kDebugMode) {
        print(
          'AudioPlayerService: Proxy caching disabled, using direct stream for ${track.id}',
        );
      }
      return AudioSource.uri(streamUri, headers: headers, tag: track);
    }

    if (preferDirectStreamWithBackgroundPrecache) {
      _stopLiveCacheProgressLogger(cacheFile.path);
      if (kDebugMode) {
        print(
          'AudioPlayerService: Using direct stream + aggressive background cache for ${track.id}',
        );
      }
      if (await _canPrecacheOnCurrentNetwork()) {
        unawaited(_precacheTrackAudioBytes(track, playbackData));
      } else if (kDebugMode) {
        print(
          'AudioPlayerService: Skipping aggressive background cache for ${track.id} (Wi-Fi only)',
        );
      }
      return AudioSource.uri(streamUri, headers: headers, tag: track);
    }

    if (kDebugMode) {
      print(
        'AudioPlayerService: Streaming + caching audio bytes for ${track.id}',
      );
    }
    _startLiveCacheProgressLogger(
      track: track,
      cacheFile: cacheFile,
      expectedBytes: playbackData.format.contentLength,
    );
    // ignore: experimental_member_use
    return LockCachingAudioSource(
      streamUri,
      cacheFile: cacheFile,
      headers: headers,
      tag: track,
    );
  }

  ({
    AudioSource source,
    List<int> queueIndices,
    Map<int, PlaybackData> playbackDataByQueueIndex,
  })
  _singleTrackSourcePlan(AudioSource source, PlaybackData playbackData) {
    return (
      source: source,
      queueIndices: <int>[_currentIndex],
      playbackDataByQueueIndex: <int, PlaybackData>{
        _currentIndex: playbackData,
      },
    );
  }

  Future<
    ({
      AudioSource source,
      List<int> queueIndices,
      Map<int, PlaybackData> playbackDataByQueueIndex,
    })
  >
  _buildPlaybackSourcePlanForCurrentTrack(
    Track track,
    PlaybackData playbackData,
  ) async {
    final currentSource = await _streamingAudioSourceForTrack(
      track,
      playbackData,
      preferDirectStreamWithBackgroundPrecache: true,
    );
    return _singleTrackSourcePlan(currentSource, playbackData);
  }

  bool _isLoopbackCleartextError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('cleartext http traffic') &&
        (message.contains('127.0.0.1') || message.contains('localhost'));
  }

  bool _isHostLookupError(Object error) {
    if (error is! SocketException) return false;
    final message = error.message.toLowerCase();
    return message.contains('failed host lookup') ||
        message.contains('no address associated with hostname');
  }

  void _schedulePrecacheAhead() {
    if (_isPrecachingAhead) return;
    if (kDebugMode) {
      print(
        'AudioPlayerService: Scheduling pre-cache ahead (index=$_currentIndex, queue=${_queue.length})',
      );
    }
    unawaited(_precacheAheadTracks());
  }

  Future<void> _precacheAheadTracks() async {
    if (_isPrecachingAhead) return;
    if (_currentIndex < 0 || _queue.isEmpty) {
      if (kDebugMode) {
        print(
          'AudioPlayerService: Skipping pre-cache (index=$_currentIndex, queue=${_queue.length})',
        );
      }
      return;
    }

    _isPrecachingAhead = true;
    try {
      if (kDebugMode) {
        print(
          'AudioPlayerService: Pre-cache pass started from index $_currentIndex (queue=${_queue.length})',
        );
      }
      final onWifi = await _isConnectedToWifi();
      if (_streamCacheWifiOnly && !onWifi) {
        if (kDebugMode) {
          print('AudioPlayerService: Skipping pre-cache (not on Wi-Fi)');
        }
        return;
      }

      final start = _currentIndex + 1;
      if (start >= _queue.length) {
        if (kDebugMode) {
          print('AudioPlayerService: No upcoming tracks to pre-cache');
        }
        return;
      }
      final maxConcurrent = _effectivePrecacheConcurrency();
      final candidateLimit = min(kPrecacheAheadTrackCount, maxConcurrent);
      final end = min(_queue.length, start + candidateLimit);
      if (kDebugMode) {
        print(
          'AudioPlayerService: Pre-cache candidates ${end - start} tracks ($start..${end - 1}, limit=$candidateLimit)',
        );
      }

      final candidates = <({Track track, PlaybackData playbackData})>[];
      for (int i = start; i < end; i++) {
        final track = _queue[i];
        if (_precacheInProgress.contains(track.id)) continue;

        String? resolvedLocalPath = track.localFilePath;
        if (resolvedLocalPath == null) {
          try {
            if (!Hive.isBoxOpen('music_downloads')) {
              await Hive.openBox<DownloadEntity>('music_downloads');
            }
            final box = Hive.box<DownloadEntity>('music_downloads');
            final entity = box.values.where((e) => e.trackId == track.id).firstOrNull;
            if (entity != null) resolvedLocalPath = entity.localPath;
          } catch (_) {}
        }

        if (resolvedLocalPath != null &&
            await File(resolvedLocalPath).exists()) {
          if (kDebugMode) {
            print(
              'AudioPlayerService: Skipping pre-cache for ${track.id} (local file)',
            );
          }
          continue;
        }

        // A track that will play lossless never uses its YouTube file, so
        // don't spend data downloading one. (The lossless copy itself isn't
        // pre-downloaded: a FLAC is ~10x the size, so it streams instead.)
        if (_qualityAllowsLossless && AddonService.instance.isEnabled) {
          final lossless = await AddonService.instance.matchFor(track);
          if (lossless != null) {
            _logLossless(
              'Skipping YouTube pre-cache for ${track.id}: will play '
              '${lossless.stream.formatLabel}',
            );
            continue;
          }
        }

        if (kDebugMode) {
          print('AudioPlayerService: Pre-cache candidate ${track.id}');
        }

        final result = await _ytPlayerUtils.playerResponseForPlayback(
          track.id,
          quality: _audioQuality,
          isMetered: false,
        );
        if (!result.isSuccess || result.data == null) continue;
        candidates.add((track: track, playbackData: result.data!));
      }

      if (candidates.isEmpty) {
        if (kDebugMode) {
          print('AudioPlayerService: No valid tracks resolved for pre-cache');
        }
        return;
      }

      if (kDebugMode) {
        print(
          'AudioPlayerService: Pre-cache download workers=$maxConcurrent (wifiOnly=$_streamCacheWifiOnly, onWifi=$onWifi, jobs=${candidates.length})',
        );
      }

      if (maxConcurrent <= 1 || candidates.length == 1) {
        for (final candidate in candidates) {
          await _precacheTrackAudioBytes(
            candidate.track,
            candidate.playbackData,
          );
          await _enforceAudioCacheLimit();
        }
        return;
      }

      int cursor = 0;
      Future<void> worker(int workerId) async {
        while (true) {
          if (cursor >= candidates.length) return;
          final next = candidates[cursor++];
          if (kDebugMode) {
            print(
              'AudioPlayerService: Pre-cache worker#$workerId downloading ${next.track.id}',
            );
          }
          await _precacheTrackAudioBytes(next.track, next.playbackData);
          await _enforceAudioCacheLimit();
        }
      }

      final workerCount = min(maxConcurrent, candidates.length);
      await Future.wait(
        List.generate(workerCount, (index) => worker(index + 1)),
      );
    } finally {
      _isPrecachingAhead = false;
    }
  }

  Future<void> _precacheTrackAudioBytes(
    Track track,
    PlaybackData playbackData, {
    bool allowDnsRetry = true,
  }) async {
    if (kIsWeb) return;
    // Never try to download a live/manifest stream to a file — it's endless.
    if (playbackData.isLive || playbackData.isManifestStream) return;
    if (_precacheInProgress.contains(track.id)) return;

    final cacheFile = await _cacheFileForTrack(track, playbackData);
    if (await cacheFile.exists()) {
      final existingSize = await cacheFile.length();
      if (existingSize >= kMinValidStreamCacheFileBytes) {
        _stopLiveCacheProgressLogger(cacheFile.path);
        final expectedBytes = playbackData.format.contentLength;
        if (kDebugMode) {
          if (expectedBytes != null && expectedBytes > 0) {
            final progress = ((existingSize / expectedBytes) * 100).clamp(
              0.0,
              100.0,
            );
            print(
              'AudioPlayerService: Pre-cache skipped, already cached ${track.id} '
              '(${_formatBytes(existingSize)} / ${_formatBytes(expectedBytes)}, ${progress.toStringAsFixed(1)}%)',
            );
          } else {
            print(
              'AudioPlayerService: Pre-cache skipped, already cached ${track.id} '
              '(${_formatBytes(existingSize)})',
            );
          }
        }
        await _touchCacheFile(cacheFile);
        _offerToAutomix(track, cacheFile.path);
        return;
      }
      await _deleteAudioCacheArtifact(cacheFile);
    }

    await _acquirePrecacheSlot();
    bool slotAcquired = true;
    if (_precacheInProgress.contains(track.id)) {
      _releasePrecacheSlot();
      slotAcquired = false;
      return;
    }

    _precacheInProgress.add(track.id);
    final tempFile = File('${cacheFile.path}.precache.part');
    HttpClient? client;
    IOSink? sink;
    int downloadedBytes = 0;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
      final request = await client.getUrl(Uri.parse(playbackData.streamUrl));
      _applyPrecacheRequestHeaders(request);
      HttpClientResponse response = await request.close();
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final responseContentLength = response.contentLength;
      int? expectedBytes = responseContentLength > 0
          ? responseContentLength
          : playbackData.format.contentLength;

      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      bool usedParallelDownload = false;
      if (expectedBytes != null && expectedBytes >= kParallelPrecacheMinBytes) {
        client.close(force: true);
        client = null;
        final parallelBytes = await _downloadWithParallelRanges(
          track: track,
          streamUri: Uri.parse(playbackData.streamUrl),
          tempFile: tempFile,
          expectedBytes: expectedBytes,
        );
        if (parallelBytes != null) {
          downloadedBytes = parallelBytes;
          usedParallelDownload = true;
        } else {
          client = HttpClient()
            ..connectionTimeout = const Duration(seconds: 20);
          final fallbackRequest = await client.getUrl(
            Uri.parse(playbackData.streamUrl),
          );
          _applyPrecacheRequestHeaders(fallbackRequest);
          response = await fallbackRequest.close();
          if (response.statusCode != 200 && response.statusCode != 206) {
            throw HttpException('HTTP ${response.statusCode}');
          }
          if (response.contentLength > 0) {
            expectedBytes = response.contentLength;
          }
        }
      }

      if (!usedParallelDownload) {
        sink = tempFile.openWrite(mode: FileMode.writeOnly);

        int nextProgressLogPercent = 10;
        int nextProgressLogBytes = 2 * 1024 * 1024;
        final downloadTimer = Stopwatch()..start();
        int speedSampleBytes = 0;
        int speedSampleMs = 0;

        String sampleSpeed() {
          final nowMs = downloadTimer.elapsedMilliseconds;
          final elapsedMs = max(1, nowMs - speedSampleMs);
          final deltaBytes = max(0, downloadedBytes - speedSampleBytes);
          speedSampleBytes = downloadedBytes;
          speedSampleMs = nowMs;
          return _formatTransferRate(deltaBytes * 1000 / elapsedMs);
        }

        if (kDebugMode) {
          if (expectedBytes != null && expectedBytes > 0) {
            print(
              'AudioPlayerService: Pre-cache started for ${track.id} '
              '(target ${_formatBytes(expectedBytes)})',
            );
          } else {
            print('AudioPlayerService: Pre-cache started for ${track.id}');
          }
        }

        await for (final chunk in response) {
          sink.add(chunk);
          downloadedBytes += chunk.length;
          if (kDebugMode) {
            if (expectedBytes != null && expectedBytes > 0) {
              final progress = ((downloadedBytes / expectedBytes) * 100).clamp(
                0.0,
                100.0,
              );
              if (progress >= nextProgressLogPercent) {
                final speed = sampleSpeed();
                print(
                  'AudioPlayerService: Pre-cache progress ${track.id} '
                  '${progress.toStringAsFixed(1)}% '
                  '(${_formatBytes(downloadedBytes)} / ${_formatBytes(expectedBytes)} @ $speed)',
                );
                while (progress >= nextProgressLogPercent) {
                  nextProgressLogPercent += 10;
                }
              }
            } else if (downloadedBytes >= nextProgressLogBytes) {
              final speed = sampleSpeed();
              print(
                'AudioPlayerService: Pre-cache progress ${track.id} '
                '${_formatBytes(downloadedBytes)} (total size unknown @ $speed)',
              );
              nextProgressLogBytes += 2 * 1024 * 1024;
            }
          }
        }
        await sink.flush();
        await sink.close();
        sink = null;
      }

      if (downloadedBytes < kMinValidStreamCacheFileBytes) {
        throw const FormatException('Pre-cache file too small');
      }

      if (await cacheFile.exists()) {
        await cacheFile.delete();
      }
      await tempFile.rename(cacheFile.path);
      await _touchCacheFile(cacheFile);
      // A whole YouTube file is what Automix analyses this track from.
      _offerToAutomix(track, cacheFile.path);
      _stopLiveCacheProgressLogger(cacheFile.path);
      if (kDebugMode) {
        if (expectedBytes != null && expectedBytes > 0) {
          final progress = ((downloadedBytes / expectedBytes) * 100).clamp(
            0.0,
            100.0,
          );
          print(
            'AudioPlayerService: Pre-cached ${track.id} '
            '(${_formatBytes(downloadedBytes)} / ${_formatBytes(expectedBytes)}, ${progress.toStringAsFixed(1)}%)',
          );
        } else {
          print(
            'AudioPlayerService: Pre-cached ${track.id} (${_formatBytes(downloadedBytes)})',
          );
        }
      }
    } catch (e) {
      if (allowDnsRetry && _isHostLookupError(e)) {
        if (kDebugMode) {
          print(
            'AudioPlayerService: DNS lookup failed for ${track.id}, refreshing URL and retrying pre-cache once',
          );
        }

        // Cached stream URL can become unreachable after network/DNS changes.
        _ytPlayerUtils.clearCache(track.id);
        final refreshed = await _ytPlayerUtils.playerResponseForPlayback(
          track.id,
          quality: _audioQuality,
          isMetered: false,
        );

        if (refreshed.isSuccess && refreshed.data != null) {
          _precacheInProgress.remove(track.id);
          await _precacheTrackAudioBytes(
            track,
            refreshed.data!,
            allowDnsRetry: false,
          );
          return;
        }
      }

      if (kDebugMode) {
        print('AudioPlayerService: Failed to pre-cache ${track.id}: $e');
      }
      if (sink != null) {
        await sink.close();
      }
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    } finally {
      client?.close(force: true);
      _precacheInProgress.remove(track.id);
      if (slotAcquired) {
        _releasePrecacheSlot();
      }
    }
  }

  Future<void> _clearTrackAudioCache(String trackId) async {
    if (kIsWeb) return;
    try {
      final cacheDir = await _getStreamAudioCacheDir(create: false);
      if (!await cacheDir.exists()) return;
      final safeTrackId = _sanitizeCacheKey(trackId);

      await for (final entity in cacheDir.list(followLinks: false)) {
        if (entity is! File) continue;
        final fileName = entity.path.split(RegExp(r'[\\/]')).last;
        if (fileName.startsWith('${safeTrackId}_')) {
          await _deleteAudioCacheArtifact(entity);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('AudioPlayerService: Failed to clear track audio cache: $e');
      }
    }
  }

  Future<void> _clearAllAudioCache() async {
    if (kIsWeb) return;
    try {
      _stopAllLiveCacheProgressLoggers();
      final cacheDir = await _getStreamAudioCacheDir(create: false);
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
    } catch (e) {
      if (kDebugMode) {
        print('AudioPlayerService: Failed to clear audio cache directory: $e');
      }
    }
  }

  // YouTube Radio mode - auto-fetches related tracks when queue runs low
  bool _isRadioMode = false;
  String? _radioSourceTrackId;
  bool _isFetchingRadio = false;
  final Set<String> _radioFetchedIds =
      {}; // Track all fetched IDs to avoid duplicates
  int _radioFetchCount = 0; // Track how many times we've fetched for variety

  // Jams mode - when true, external controller handles track completion
  bool _jamsModeEnabled = false;

  /// Enable/disable Jams mode (external controller handles track completion)
  void setJamsMode(bool enabled) {
    _jamsModeEnabled = enabled;
    // Jams never automix (every member would mix at a different moment).
    unawaited(AutomixService.instance.setInJam(enabled));
    if (kDebugMode) {
      print(
        'AudioPlayerService: Jams mode ${enabled ? "enabled" : "disabled"}',
      );
    }

    // Gapless playlist logic was removed to prevent resource leaks
  }

  /// Check if Jams mode is enabled
  bool get isJamsModeEnabled => _jamsModeEnabled;

  // Use InnerTubeService for proper YouTube Music radio queue
  // This should be the shared authenticated instance for personalized radio
  InnerTubeService? _innerTubeService;

  // Stream controllers
  final _stateController = BehaviorSubject<PlaybackState>.seeded(
    const PlaybackState(),
  );

  // Separate position stream for UI progress (avoids full state rebuilds)
  final _positionController = BehaviorSubject<Duration>.seeded(Duration.zero);
  final _bufferedPositionController = BehaviorSubject<Duration>.seeded(
    Duration.zero,
  );

  // Stream for track completion (for Jams integration)
  final _trackCompleteController = StreamController<Track>.broadcast();

  /// Stream that emits when a track completes playing
  Stream<Track> get trackCompleteStream => _trackCompleteController.stream;

  // Throttle tracking
  DateTime? _lastPositionUpdate;
  bool _prefetchTriggered = false;
  static const _positionUpdateInterval = Duration(
    milliseconds: 500,
  ); // Throttle to 2 updates/sec

  // Queue persistence debounce
  Timer? _persistenceDebounceTimer;
  static const _persistenceDebounceDelay = Duration(seconds: 2);
  // If the app was closed for more than this window, clear persisted queue.
  static const _closedRestoreTtl = Duration(minutes: 5);
  // Position persistence (periodic while playing)
  DateTime? _lastPositionPersistAt;
  Duration _lastPositionPersisted = Duration.zero;
  static const _positionPersistInterval = Duration(seconds: 5);
  static const _positionPersistForceDelta = Duration(seconds: 15);

  /// Stream of playback state changes (for major UI updates)
  Stream<PlaybackState> get stateStream => _stateController.stream;

  /// Separate position stream for progress bar (high frequency, no full rebuild)
  Stream<Duration> get positionStream => _positionController.stream;

  final _losslessUpgradingController = BehaviorSubject<String?>.seeded(null);

  /// The id of the track being moved onto its lossless copy mid-song — a
  /// copy was found and the hand-over is under way — or null.
  Stream<String?> get losslessUpgradingStream =>
      _losslessUpgradingController.stream.distinct();

  int _seekCount = 0;

  /// The active player's latest reading of the playhead, dated by when the
  /// native player took it — what the lyrics clock steers by (see
  /// LyricClock). Read every frame rather than streamed, so it follows the
  /// active player through Automix hand-overs and lossless swaps.
  ///
  /// [advancing] is whether the audio is really moving: playing, and not
  /// loading or buffering — just_audio's `playing` alone stays true through
  /// both. [seeks] changes whenever the playhead jumps on purpose.
  ({int positionMs, double sampledAtMs, bool advancing, int seeks}) get playhead {
    final event = _player.playbackEvent;
    final advancing =
        _player.playing && event.processingState == ProcessingState.ready;
    return advancing
        ? (
            positionMs: event.updatePosition.inMilliseconds,
            sampledAtMs: event.updateTime.microsecondsSinceEpoch / 1000,
            advancing: true,
            seeks: _seekCount,
          )
        : (
            positionMs: _player.position.inMilliseconds,
            sampledAtMs: DateTime.now().microsecondsSinceEpoch / 1000,
            advancing: false,
            seeks: _seekCount,
          );
  }

  /// Buffered position stream
  Stream<Duration> get bufferedPositionStream =>
      _bufferedPositionController.stream;

  /// Current playback state
  PlaybackState get state => _stateController.value;

  /// Current position (real-time, not throttled)
  Duration get currentPosition => _player.position;

  /// Current track
  Track? get currentTrack => _currentTrack;

  // Read-outs for the Signal path sheet.
  double get currentSpeed => _player.speed;
  double get currentVolume => _player.volume;
  bool get isUpgradingStream => _isUpgradingStream;
  bool get isOnUnmeteredNetwork => _onUnmeteredNetwork;

  /// How much audio is downloaded past the playhead right now.
  Duration get bufferedAhead {
    final ahead = _player.bufferedPosition - _player.position;
    return ahead.isNegative ? Duration.zero : ahead;
  }

  Future<void> _watchNetworkType() async {
    _onUnmeteredNetwork = await _isConnectedToWifi();
    _connectivity.onConnectivityChanged.listen((connections) {
      _onUnmeteredNetwork = connections.contains(ConnectivityResult.wifi) ||
          connections.contains(ConnectivityResult.ethernet);
    });
  }

  /// Current queue
  List<Track> get queue => List.unmodifiable(_queue);

  /// Current index in queue
  int get currentIndex => _currentIndex;

  /// Current audio quality setting
  AudioQuality get audioQuality => _audioQuality;

  void _bindPlayerEventStreams(AudioPlayer player) {
    // Seeks made straight on the player (restart, repeat-one) jump too.
    player.positionDiscontinuityStream.listen((d) {
      if (identical(player, _player) &&
          d.reason == PositionDiscontinuityReason.seek) {
        _seekCount++;
      }
    });

    player.playerStateStream.listen((playerState) {
      if (!identical(player, _player)) return;
      _updateState(
        isPlaying: playerState.playing,
        isBuffering: playerState.processingState == ProcessingState.buffering,
        isLoading: playerState.processingState == ProcessingState.loading,
      );

      _handleYoutubeTrackingPlaybackState(playerState);

      // Auto-play next track when current one completes.
      if (playerState.processingState == ProcessingState.completed) {
        // Live streams have no real end — ExoPlayer only reports "completed"
        // because it reached the end of the short DVR window. Never advance the
        // queue; jump back to the live edge and keep playing.
        if (_currentPlaybackData?.isLive == true) {
          if (kDebugMode) {
            print(
              'AudioPlayerService: Live stream hit DVR-window end, resuming at live edge (not skipping)',
            );
          }
          unawaited(_resumeLiveEdge());
        } else {
          _onTrackComplete();
        }
      }
    });

    player.currentIndexStream.listen((playerIndex) {
      if (!identical(player, _player)) return;
      if (playerIndex == null) return;
      if (playerIndex < 0 || playerIndex >= _activeSourceQueueIndices.length) {
        return;
      }

      final queueIndex = _activeSourceQueueIndices[playerIndex];
      if (queueIndex < 0 || queueIndex >= _queue.length) return;
      if (queueIndex == _currentIndex) return;

      _flushWatchtimeForCurrentTrackBeforeSwitch();
      _currentIndex = queueIndex;
      _currentTrack = _queue[queueIndex];
      final playbackData = _activeSourcePlaybackDataByQueueIndex[queueIndex];
      if (playbackData != null) {
        _currentPlaybackData = playbackData;
      }

      _updateState(
        currentTrack: _currentTrack,
        currentIndex: _currentIndex,
        currentPlaybackData: playbackData ?? _currentPlaybackData,
        isLoading: false,
      );
      _resetYoutubePlaybackTrackingForCurrentTrack();
      if (_player.playing) {
        _startYoutubePlaybackTracking();
      }
      _saveQueueDebounced();
      _prefetchNextTrack();
      _scheduleLyricsPrefetchAroundCurrent();
      if (_currentTrack != null) {
        unawaited(_upgradeTrackQualityIfPossible(_currentTrack!));
        // Gapless auto-advance starts the next track on whatever the
        // playlist was built with; it gets its second look too.
        if (playbackData?.format.isLossless != true &&
            _currentPlaybackData?.isLive != true) {
          unawaited(_upgradeToLosslessIfPossible(_currentTrack!));
        }
      }
    });

    player.positionStream.listen((position) {
      if (!identical(player, _player)) return;

      // Avoid overwriting restored position while idle.
      if (player.processingState == ProcessingState.idle &&
          position == Duration.zero &&
          _pendingSeekPosition != null &&
          _pendingSeekTrackId == _currentTrack?.id) {
        return;
      }

      _positionController.add(position);
      _maybePersistPosition(position);

      final now = DateTime.now();
      if (_lastPositionUpdate == null ||
          now.difference(_lastPositionUpdate!) >= _positionUpdateInterval) {
        _lastPositionUpdate = now;
        _updateState(position: position);

        if (_isRadioMode && !_isFetchingRadio) {
          _checkAndFetchRadioTracks();
        }
      }

      _prefetchNextTrackIfNeeded(position);
      _maybeTriggerAutoCrossfade(position);
      _recoverStuckVolumeIfNeeded();
    });

    player.bufferedPositionStream.listen((bufferedPosition) {
      if (!identical(player, _player)) return;
      _bufferedPositionController.add(bufferedPosition);
    });

    player.durationStream.listen((duration) {
      if (!identical(player, _player)) return;
      final isLive = _currentPlaybackData?.isLive == true;
      final didUpdateDuration =
          duration != null && _applyDurationToCurrentTrack(duration);
      _crossfadeTriggeredForTrack = false;
      _updateState(
        // For live streams report no duration so the UI shows a LIVE state
        // instead of a bogus ~30s progress bar that would "complete".
        duration: isLive ? null : duration,
        resetDuration: isLive,
        currentTrack: _currentTrack,
        queue: _queue,
        queueRevision: didUpdateDuration ? _queueRevision : null,
      );
      _prefetchTriggered = false;
    });

    player.playbackEventStream.listen(
      (event) {},
      onError: (Object e, StackTrace st) {
        if (!identical(player, _player)) return;
        if (kDebugMode) {
          print('AudioPlayerService: Playback error: $e');
        }
        _handlePlaybackError(e);
      },
    );
  }

  void _init() {
    _player = _primaryPlayer;
    unawaited(_player.setVolume(1.0));
    unawaited(_applyCrossfadeDurationToPlayer());
    _bindPlayerEventStreams(_primaryPlayer);
    _bindPlayerEventStreams(_secondaryPlayer);

    // Periodic cache maintenance for LRU limit enforcement.
    _cacheMaintenanceTimer?.cancel();
    _cacheMaintenanceTimer = Timer.periodic(_cacheMaintenanceInterval, (_) {
      unawaited(_enforceAudioCacheLimit());
    });

    // Listen for local tracks enriched with online metadata (artist, album, artwork)
    LocalArtworkService.onTrackEnriched.listen((updatedTrack) {
      enrichTrackMetadata(updatedTrack);
    });
  }

  /// Enrich currentTrack and queue when online metadata (artist, album, artwork) is resolved
  void enrichTrackMetadata(Track updatedTrack) {
    bool trackChanged = false;
    if (_currentTrack != null && _currentTrack!.id == updatedTrack.id) {
      var updated = _currentTrack!;
      if (LocalArtworkService.isArtistMissing(updated.artist) &&
          !LocalArtworkService.isArtistMissing(updatedTrack.artist)) {
        updated = updated.copyWith(artist: updatedTrack.artist);
        trackChanged = true;
      }
      if ((updated.album == null || updated.album!.trim().isEmpty) &&
          updatedTrack.album != null &&
          updatedTrack.album!.trim().isNotEmpty) {
        updated = updated.copyWith(album: updatedTrack.album);
        trackChanged = true;
      }
      if ((updated.thumbnailUrl == null || updated.thumbnailUrl!.trim().isEmpty) &&
          updatedTrack.thumbnailUrl != null &&
          updatedTrack.thumbnailUrl!.trim().isNotEmpty) {
        updated = updated.copyWith(
          thumbnailUrl: updatedTrack.thumbnailUrl,
          highResThumbnailUrl: updatedTrack.highResThumbnailUrl,
        );
        trackChanged = true;
      }
      if (trackChanged) {
        _currentTrack = updated;
      }
    }

    for (int i = 0; i < _queue.length; i++) {
      if (_queue[i].id == updatedTrack.id) {
        var item = _queue[i];
        bool itemChanged = false;
        if (LocalArtworkService.isArtistMissing(item.artist) &&
            !LocalArtworkService.isArtistMissing(updatedTrack.artist)) {
          item = item.copyWith(artist: updatedTrack.artist);
          itemChanged = true;
        }
        if ((item.album == null || item.album!.trim().isEmpty) &&
            updatedTrack.album != null &&
            updatedTrack.album!.trim().isNotEmpty) {
          item = item.copyWith(album: updatedTrack.album);
          itemChanged = true;
        }
        if (itemChanged) {
          _queue[i] = item;
          trackChanged = true;
        }
      }
    }

    for (int i = 0; i < _originalQueue.length; i++) {
      if (_originalQueue[i].id == updatedTrack.id) {
        var item = _originalQueue[i];
        bool itemChanged = false;
        if (LocalArtworkService.isArtistMissing(item.artist) &&
            !LocalArtworkService.isArtistMissing(updatedTrack.artist)) {
          item = item.copyWith(artist: updatedTrack.artist);
          itemChanged = true;
        }
        if (itemChanged) {
          _originalQueue[i] = item;
          trackChanged = true;
        }
      }
    }

    if (trackChanged) {
      _queueRevision++;
      _updateState(
        currentTrack: _currentTrack,
        queue: _queue,
        queueRevision: _queueRevision,
      );
    }
  }

  void _handleYoutubeTrackingPlaybackState(PlayerState playerState) {
    debugPrint('[YTM-Tracking] PlayerState changed: playing=${playerState.playing}, processingState=${playerState.processingState}');
    if (_isUpgradingStream) {
      debugPrint('[YTM-Tracking] Stream upgrade in progress, preserving tracking session');
      return;
    }
    if (playerState.playing &&
        playerState.processingState != ProcessingState.completed) {
      _startYoutubePlaybackTracking();
      return;
    }

    if (_youtubeWatchtimeTimer != null) {
      final state = playerState.processingState == ProcessingState.completed
          ? 'ended'
          : 'paused';
      debugPrint('[YTM-Tracking] Playback paused/completed ($state), flushing final watchtime');
      unawaited(_sendYoutubeWatchtime(state: state, force: true));
      _stopYoutubeWatchtimeTimer();
    }
  }

  /// Only session-bound tracking (authenticated WEB_REMIX) writes history.
  PlaybackTracking? get _activePlaybackTracking =>
      (_authenticatedPlaybackTracking?.hasStatsUrls == true)
          ? _authenticatedPlaybackTracking
          : null;

  Future<void> _ensureInnerTubeAuth() async {
    debugPrint('[YTM-Tracking] AudioPlayerService._ensureInnerTubeAuth: currently isAuth=${_innerTubeService?.isAuthenticated}');
    if (_innerTubeService != null && _innerTubeService!.isAuthenticated) return;
    _innerTubeService ??= InnerTubeService();
    if (!_innerTubeService!.isAuthenticated) {
      try {
        final authService = YTMusicAuthService(_innerTubeService!);
        final success = await authService.restoreCachedAuth();
        debugPrint('[YTM-Tracking] AudioPlayerService._ensureInnerTubeAuth: direct restore success=$success, isAuth=${_innerTubeService!.isAuthenticated}');
      } catch (e) {
        debugPrint('[YTM-Tracking] AudioPlayerService._ensureInnerTubeAuth error: $e');
      }
    }
  }

  void _flushWatchtimeForCurrentTrackBeforeSwitch() {
    if (_youtubeWatchtimeTimer != null &&
        _youtubePlaybackStartSent &&
        _currentTrack != null) {
      final position = _player.position;
      if (position > _youtubeTrackingLastPosition) {
        debugPrint(
          '[YTM-Tracking] Flushing watchtime before track change for ${_currentTrack?.id} (pos: ${position.inSeconds}s, lastPos: ${_youtubeTrackingLastPosition.inSeconds}s)',
        );
        unawaited(_sendYoutubeWatchtime(state: 'ended', force: true));
      }
    }
    _stopYoutubeWatchtimeTimer();
  }

  void _resetYoutubePlaybackTrackingForCurrentTrack() {
    final videoId = _currentTrack?.id;
    if (_youtubeTrackingVideoId == videoId) return;

    debugPrint('[YTM-Tracking] Resetting tracking for track: previous=$_youtubeTrackingVideoId, new=$videoId');

    _stopYoutubeWatchtimeTimer();
    _youtubeTrackingVideoId = videoId;
    _youtubeTrackingCpn = _generateYoutubeCpn();
    _youtubeAtrSent = false;
    _youtubeTrackingLastPosition = Duration.zero;
    _youtubePlaybackStartSent = false;
    _authenticatedPlaybackTracking = null;
    if (videoId != null) {
      _youtubeTrackingResolveFailed.remove(videoId);
    }
  }

  void _startYoutubePlaybackTracking() {
    final track = _currentTrack;
    if (track == null) return;
    // Only real YouTube video ids can be registered against YT Music history
    // (local files, podcasts from other sources etc. cannot).
    if (!_youtubeVideoIdPattern.hasMatch(track.id)) {
      debugPrint('[YTM-Tracking] Skipped: not a YouTube video id (${track.id})');
      return;
    }

    if (_innerTubeService?.isAuthenticated != true) {
      debugPrint('[YTM-Tracking] InnerTube not authenticated yet, restoring auth...');
      unawaited(_ensureInnerTubeAuth().then((_) {
        if (_innerTubeService?.isAuthenticated == true &&
            _player.playing &&
            _currentTrack?.id == track.id) {
          _startYoutubePlaybackTracking();
        }
      }));
      return;
    }

    // Ensure tracking state is initialized for the current track.
    _resetYoutubePlaybackTrackingForCurrentTrack();

    // History is only written by the session-bound tracking URLs from an
    // authenticated WEB_REMIX player request. Those from the stream clients
    // (ANDROID_VR / IOS) never reach the user's history.
    final tracking = _activePlaybackTracking;
    if (tracking == null) {
      if (!_youtubeTrackingResolveFailed.contains(track.id)) {
        unawaited(_resolveYoutubeTrackingForCurrentTrack(track.id));
      }
      return;
    }

    if (!_youtubePlaybackStartSent) {
      _youtubePlaybackStartSent = true;
      final playbackUrl = tracking.videostatsPlaybackUrl;
      if (playbackUrl != null && playbackUrl.isNotEmpty) {
        debugPrint('[YTM-Tracking] Registering play for ${track.id}');
        unawaited(
          _innerTubeService!.sendPlaybackStatsPing(
            playbackUrl,
            cpn: _youtubeTrackingCpn ??= _generateYoutubeCpn(),
          ),
        );
      }
    }

    // One cheap timer drives both the atr ping and periodic watchtime; the
    // network is only touched every [_youtubeWatchtimeReportSeconds] of audio.
    _youtubeWatchtimeTimer ??= Timer.periodic(_youtubeWatchtimeInterval, (_) {
      _maybeSendYoutubeAtr();
      unawaited(_sendYoutubeWatchtime(state: 'playing'));
    });
  }

  void _maybeSendYoutubeAtr() {
    if (_youtubeAtrSent) return;
    final tracking = _activePlaybackTracking;
    final atrUrl = tracking?.atrUrl;
    if (tracking == null || atrUrl == null || atrUrl.isEmpty) return;
    if (_player.position.inSeconds < tracking.atrAfterSeconds) return;
    _youtubeAtrSent = true;
    unawaited(
      _innerTubeService?.sendPlaybackStatsPing(
        atrUrl,
        cpn: _youtubeTrackingCpn ??= _generateYoutubeCpn(),
        isAtr: true,
      ),
    );
  }

  Future<void> _resolveYoutubeTrackingForCurrentTrack(String trackId) async {
    final innerTube = _innerTubeService;
    if (innerTube?.isAuthenticated != true) return;
    if (!_youtubeTrackingResolveInProgress.add(trackId)) return;

    try {
      // Retry a couple of times: a track starting is exactly when the network
      // is busiest (stream resolve, wifi/cellular hand-over), and one blip
      // should not lose the play.
      PlaybackTracking? tracking;
      for (var attempt = 0; attempt < 3 && tracking == null; attempt++) {
        if (_currentTrack?.id != trackId) return;
        if (attempt > 0) await Future.delayed(const Duration(seconds: 2));
        try {
          final fallbackSts = innerTube!.sessionSignatureTimestamp ??
              await InnerTubeApi().getSignatureTimestamp(trackId);
          final json = await innerTube.getAuthenticatedPlaybackTracking(
            trackId,
            signatureTimestamp: fallbackSts,
          );
          final t = PlaybackTracking.fromJson(json);
          if (t.hasStatsUrls) tracking = t;
        } catch (e, st) {
          debugPrint('[YTM-Tracking] Resolve attempt ${attempt + 1} failed: $e\n$st');
        }
      }

      if (_currentTrack?.id != trackId) return;
      if (tracking == null) {
        debugPrint('[YTM-Tracking] WARNING: no tracking URLs for $trackId; play not registered');
        _youtubeTrackingResolveFailed.add(trackId);
        return;
      }
      _authenticatedPlaybackTracking = tracking;
      if (_player.playing) _startYoutubePlaybackTracking();
    } finally {
      _youtubeTrackingResolveInProgress.remove(trackId);
    }
  }

  Future<void> _sendYoutubeWatchtime({
    required String state,
    bool force = false,
  }) async {
    final innerTube = _innerTubeService;
    final watchtimeUrl = _activePlaybackTracking?.videostatsWatchtimeUrl;
    if (innerTube == null || !innerTube.isAuthenticated) return;
    if (_currentTrack == null || !_youtubePlaybackStartSent) return;
    if (watchtimeUrl == null || watchtimeUrl.isEmpty) return;

    final seconds = _player.position.inSeconds;
    final lastReported = _youtubeTrackingLastPosition.inSeconds;
    if (!force && seconds - lastReported < _youtubeWatchtimeReportSeconds) {
      return;
    }
    if (force && seconds <= 0) return;
    final isFinal = state != 'playing';

    _youtubeTrackingLastPosition = Duration(seconds: seconds);
    await innerTube.sendPlaybackStatsPing(
      watchtimeUrl,
      cpn: _youtubeTrackingCpn ??= _generateYoutubeCpn(),
      extraParams: {
        'st': '0',
        'et': '$seconds',
        'cmt': '$seconds',
        'state': isFinal ? 'paused' : 'playing',
        if (state == 'ended') 'final': '1',
      },
    );
  }

  void _stopYoutubeWatchtimeTimer() {
    _youtubeWatchtimeTimer?.cancel();
    _youtubeWatchtimeTimer = null;
  }

  static final RegExp _youtubeVideoIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');
  static const int _youtubeWatchtimeReportSeconds = 30;

  String _generateYoutubeCpn() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    final random = Random.secure();
    return List.generate(16, (_) => chars[random.nextInt(chars.length)]).join();
  }

  /// Pre-fetch the next track's stream URL for seamless playback
  /// Only triggers ONCE per track to avoid repeated calls
  void _prefetchNextTrackIfNeeded(Duration currentPosition) {
    if (_prefetchTriggered) return; // Already triggered for this track

    final duration = _player.duration;
    if (duration == null || duration.inSeconds < 60) return;

    final remainingTime = duration - currentPosition;
    if (remainingTime.inSeconds <= 30 && remainingTime.inSeconds > 0) {
      _prefetchTriggered = true; // Mark as triggered

      // Pre-fetch next track
      if (_currentIndex < _queue.length - 1) {
        final nextTrack = _queue[_currentIndex + 1];
        if (!_isLocalTrack(nextTrack)) {
          if (kDebugMode) {
            print('AudioPlayerService: Pre-fetching next track: ${nextTrack.id}');
          }

          // Fire and forget - just warm up the cache
          _ytPlayerUtils.prefetchNext(nextTrack.id, quality: _audioQuality);
        }
        _schedulePrecacheAhead();
      }
    }
  }

  /// Handle playback errors with fallback
  void _handlePlaybackError(Object error) {
    if (kDebugMode) {
      print('AudioPlayerService: Handling error: $error');
    }

    // If Android blocks local proxy cleartext, disable proxy-based caching and
    // retry current track using direct stream.
    if (_isLoopbackCleartextError(error) &&
        _allowProxyCachingSource &&
        _currentTrack != null) {
      _allowProxyCachingSource = false;
      if (kDebugMode) {
        print(
          'AudioPlayerService: Disabling proxy caching due to cleartext policy and retrying track',
        );
      }
      unawaited(_loadAndPlayCurrent());
      return;
    }

    // Clear cache for current track and retry once
    if (_currentTrack != null) {
      _ytPlayerUtils.clearCache(_currentTrack!.id);
      unawaited(_clearTrackAudioCache(_currentTrack!.id));

      // Could implement retry logic here
      _updateState(error: 'Playback error: ${error.toString()}');
    }
  }

  bool _applyDurationToCurrentTrack(Duration duration) {
    if (_currentTrack == null) return false;
    // Live streams report only their DVR-window length (e.g. 30s), not a real
    // track length — never pin a live track to a finite duration.
    if (_currentPlaybackData?.isLive == true) return false;
    if (duration <= Duration.zero) return false;
    if (_currentTrack!.duration == duration) return false;

    final updatedTrack = _currentTrack!.copyWith(duration: duration);
    _currentTrack = updatedTrack;

    if (_currentIndex >= 0 && _currentIndex < _queue.length) {
      _queue[_currentIndex] = updatedTrack;
    }

    for (int i = 0; i < _originalQueue.length; i++) {
      if (_originalQueue[i].id == updatedTrack.id) {
        _originalQueue[i] = updatedTrack;
        break;
      }
    }

    _queueRevision++;
    _saveQueueDebounced();
    return true;
  }

  Future<void> _runDurationMigrationIfNeeded() async {
    if (_durationMigrationInProgress) return;
    if (_currentTrack == null) return;
    if (_currentTrack!.duration > Duration.zero) return;

    try {
      _durationMigrationInProgress = true;
      final prefs = await SharedPreferences.getInstance();
      final migrated = prefs.getBool(_durationMigrationKey) ?? false;
      if (migrated) return;

      // Get track info via InnerTube player API for duration migration
      final playerResult = await _ytPlayerUtils.playerResponseForPlayback(
        _currentTrack!.id,
        quality: _audioQuality,
      );
      if (!playerResult.isSuccess || playerResult.data == null) return;
      
      final fetchedDuration = playerResult.data!.videoDetails?.duration ?? Duration.zero;
      if (fetchedDuration <= Duration.zero) return;

      final didUpdate = _applyDurationToCurrentTrack(fetchedDuration);
      if (didUpdate) {
        _updateState(
          duration: fetchedDuration,
          currentTrack: _currentTrack,
          queue: _queue,
          queueRevision: _queueRevision,
        );
        await prefs.setBool(_durationMigrationKey, true);
      }
    } catch (e) {
      if (kDebugMode) {
        print('AudioPlayerService: Duration migration failed: $e');
      }
    } finally {
      _durationMigrationInProgress = false;
    }
  }

  void _updateState({
    Track? currentTrack,
    bool resetCurrentTrack = false,
    List<Track>? queue,
    int? currentIndex,
    bool? isPlaying,
    bool? isBuffering,
    bool? isLoading,
    Duration? position,
    Duration? bufferedPosition,
    Duration? duration,
    bool resetDuration = false,
    double? speed,
    LoopMode? loopMode,
    bool? shuffleEnabled,
    String? error,
    AudioQuality? audioQuality,
    PlaybackData? currentPlaybackData,
    bool resetCurrentPlaybackData = false,
    int? queueRevision,
    String? queueSourceId,
    String? queueTitle,
    bool resetQueueTitle = false,
    bool? isRadioMode,
    bool? isFetchingRadio,
    bool? streamCacheWifiOnly,
    int? streamCacheSizeLimitMb,
    int? streamCacheMaxConcurrent,
    int? crossfadeDurationMs,
    bool? showNerdStats,
    bool? jioSaavnEnabled,
  }) {
    final shouldResetCurrentTrack =
        resetCurrentTrack || (currentTrack == null && _currentTrack == null);
    final shouldResetPlaybackData =
        resetCurrentPlaybackData ||
        (currentPlaybackData == null && _currentPlaybackData == null);

    final newState = _stateController.value.copyWith(
      currentTrack:
          shouldResetCurrentTrack ? null : (currentTrack ?? _currentTrack),
      resetCurrentTrack: shouldResetCurrentTrack,
      queue: queue ?? _queue,
      queueRevision: queueRevision, // Passed explicitly when queue changes
      currentIndex: currentIndex ?? _currentIndex,
      isPlaying: isPlaying,
      isBuffering: isBuffering,
      isLoading: isLoading,
      position: position,
      bufferedPosition: bufferedPosition,
      duration: duration,
      resetDuration: resetDuration,
      speed: speed,
      loopMode: loopMode ?? _loopMode,
      shuffleEnabled: shuffleEnabled ?? _shuffleEnabled,
      error: error,
      audioQuality: audioQuality ?? _audioQuality,
      currentPlaybackData: shouldResetPlaybackData
          ? null
          : (currentPlaybackData ?? _currentPlaybackData),
      resetCurrentPlaybackData: shouldResetPlaybackData,
      queueSourceId: queueSourceId ?? _queueSourceId,
      queueTitle: resetQueueTitle ? null : (queueTitle ?? _queueSourceTitle),
      resetQueueTitle: resetQueueTitle,
      isRadioMode: isRadioMode ?? _isRadioMode,
      isFetchingRadio: isFetchingRadio ?? _isFetchingRadio,
      streamCacheWifiOnly: streamCacheWifiOnly ?? _streamCacheWifiOnly,
      streamCacheSizeLimitMb: streamCacheSizeLimitMb ?? _streamCacheSizeLimitMb,
      streamCacheMaxConcurrent:
          streamCacheMaxConcurrent ?? _streamCacheMaxConcurrent,
      crossfadeDurationMs: crossfadeDurationMs ?? _crossfadeDurationMs,
      showNerdStats: showNerdStats ?? _showNerdStats,
      jioSaavnEnabled: jioSaavnEnabled ?? _jioSaavnEnabled,
    );

    // Only emit if state actually changed (using == that excludes position)
    // This prevents unnecessary widget rebuilds
    if (newState != _stateController.value) {
      _stateController.add(newState);
    }

    // The Automix engine follows the song, the queue and the loop mode.
    if (currentTrack != null ||
        queue != null ||
        currentIndex != null ||
        queueRevision != null ||
        loopMode != null ||
        speed != null) {
      _scheduleAutomixSync();
    }
  }

  /// Start radio mode based on a track.
  /// If the track is already playing or loaded, it keeps playing seamlessly without restarting from 0:00,
  /// clears subsequent queue items, turns on radio mode, and fetches recommendations in background.
  Future<void> startRadio(Track track) async {
    final isCurrentTrack = _currentTrack?.id == track.id;
    final hasActiveSource = _player.processingState != ProcessingState.idle &&
        _player.audioSource != null;

    if (isCurrentTrack && hasActiveSource) {
      if (kDebugMode) {
        print(
          'AudioPlayerService: Starting radio for currently playing track ${track.title} without restart',
        );
      }
      _isRadioMode = true;
      _radioSourceTrackId = track.id;
      _radioFetchedIds.clear();
      _radioFetchedIds.add(track.id);
      _radioFetchCount = 0;

      // Keep only the current playing track in queue
      _queue = [_currentTrack!];
      _originalQueue = [_currentTrack!];
      _currentIndex = 0;
      _queueRevision++;
      _queueSourceId = null;
      _queueSourceTitle = null;

      _updateState(
        queue: _queue,
        queueRevision: _queueRevision,
        currentIndex: _currentIndex,
        currentTrack: _currentTrack,
        queueSourceId: null,
        queueTitle: null,
        resetQueueTitle: true,
        isRadioMode: true,
        isFetchingRadio: false,
      );

      _saveQueueDebounced();

      // Immediately fetch upcoming radio tracks in background
      unawaited(_fetchRadioTracks());
    } else {
      await playTrack(track, enableRadio: true);
    }
  }

  /// Play a single track (enables YouTube Radio mode by default)
  /// When radio mode is on, related tracks are auto-fetched when queue runs low
  Future<void> playTrack(Track track, {bool enableRadio = true}) async {
    _isRadioMode = enableRadio;
    _radioSourceTrackId = enableRadio ? track.id : null;
    // Reset radio state for new session
    if (enableRadio) {
      _radioFetchedIds.clear();
      _radioFetchedIds.add(track.id); // Don't re-add the initial track
      _radioFetchCount = 0;
    }
    await playQueue(
      [track],
      startIndex: 0,
      isRadioQueue: false,
      sourceId: null,
      sourceTitle: null,
    );
  }

  /// Play a queue of tracks
  ///
  /// OuterTune approach:
  /// 1. Immediately start prefetching stream URLs for all tracks
  /// 2. Build ConcatenatingAudioSource with resolved URLs
  /// 3. Player starts at the requested index
  /// 4. Next tracks are pre-buffered automatically
  ///
  /// [sourceId] - optional ID of the playlist/album/artist this queue came from
  /// [sourceTitle] - optional title of the playlist/album/artist this queue came from
  Future<void> playQueue(
    List<Track> tracks, {
    int startIndex = 0,
    bool isRadioQueue = false,
    String? sourceId,
    String? sourceTitle,
  }) async {
    if (kDebugMode) {
      print(
        'AudioPlayerService.playQueue: tracks=${tracks.length}, startIndex=$startIndex, isRadioQueue=$isRadioQueue, sourceId=$sourceId, sourceTitle=$sourceTitle',
      );
    }
    if (tracks.isEmpty) return;

    // Disable radio mode when playing from a playlist/album (unless it's a radio queue extension)
    if (!isRadioQueue) {
      _isRadioMode = tracks.length == 1; // Only enable radio for single tracks
      _radioSourceTrackId = tracks.length == 1 ? tracks.first.id : null;
      if (kDebugMode) {
        print(
          'AudioPlayerService: Radio mode set to $_isRadioMode, sourceId=$_radioSourceTrackId',
        );
      }
    }

    // Track the source of this queue (playlist/album/artist ID & Title)
    _queueSourceId = isRadioQueue ? _queueSourceId : sourceId;
    _queueSourceTitle = isRadioQueue ? _queueSourceTitle : sourceTitle;

    _originalQueue = List.from(tracks);
    _queue = _shuffleEnabled
        ? _shuffleList(tracks, startIndex)
        : List.from(tracks);
    _currentIndex = _shuffleEnabled ? 0 : startIndex;
    _currentTrack = _queue[_currentIndex];
    _queueRevision++; // Force update

    // IMPORTANT: Update state with queue immediately so UI shows queue
    _updateState(
      queue: _queue,
      queueRevision: _queueRevision,
      currentIndex: _currentIndex,
      currentTrack: _currentTrack,
      isLoading: true, // Show loading state while buffering
      queueSourceId: _queueSourceId,
      queueTitle: _queueSourceTitle,
      resetQueueTitle: _queueSourceTitle == null,
      isRadioMode: _isRadioMode,
      isFetchingRadio: false, // Reset fetching state for new queue
    );

    // Persist queue state (debounced)
    _saveQueueDebounced();
    _scheduleLyricsPrefetchAroundCurrent();

    // Fire and forget - start playback without blocking caller
    // This allows UI to remain responsive while audio loads
    unawaited(_loadAndPlayCurrent());

    // Delay heavy background work to let UI settle (500ms after play starts)
    Future.delayed(const Duration(milliseconds: 500), () {
      if (kDebugMode) {
        print(
          'AudioPlayerService: Running delayed work, _isRadioMode=$_isRadioMode, queue.length=${_queue.length}',
        );
      }
      // Start prefetching ALL tracks in background
      _prefetchAllTracks();
      // Playlist build removed to fix native ExoPlayer leaks
      // If radio mode is on and queue is short, immediately fetch related tracks
      // This ensures the queue is populated right away, not just after first song ends
      if (_isRadioMode && _queue.length <= 2) {
        if (kDebugMode) {
          print('AudioPlayerService: Triggering immediate radio fetch');
        }
        _fetchRadioTracks();
      }
    });
  }

  /// Public method to prefetch tracks (called by TrackPrefetchManager)
  /// This resolves stream URLs so play taps are instant
  Future<void> prefetchTracks(List<String> videoIds) async {
    if (videoIds.isEmpty) return;
    if (kDebugMode) {
      print(
        'AudioPlayerService: Prefetching ${videoIds.length} visible tracks',
      );
    }
    await _ytPlayerUtils.prefetch(videoIds, quality: _audioQuality);
  }

  bool _isLocalTrack(Track track) {
    if (track.localFilePath != null) return true;
    try {
      if (Hive.isBoxOpen('music_downloads')) {
        final box = Hive.box<DownloadEntity>('music_downloads');
        if (box.values.any((e) => e.trackId == track.id)) return true;
      }
      if (Hive.isBoxOpen('local_music_tracks')) {
        final box = Hive.box<TrackEntity>('local_music_tracks');
        if (box.containsKey(track.id)) return true;
      }
    } catch (_) {}
    return false;
  }

  /// Prefetch all tracks in queue (OuterTune approach)
  /// This resolves stream URLs in background
  void _prefetchAllTracks() {
    if (_queue.isEmpty) return;

    // Prefetch all tracks, but prioritize current and next, filtering out local tracks
    final allIds = _queue
        .where((t) => !_isLocalTrack(t))
        .map((t) => t.id)
        .toList();
        
    if (allIds.isEmpty) return;
    
    if (kDebugMode) {
      print('AudioPlayerService: Prefetching ${allIds.length} remote tracks');
    }

    // Fire and forget - prefetch happens in background
    _ytPlayerUtils.prefetch(allIds, quality: _audioQuality);
  }

  void _scheduleLyricsPrefetchAroundCurrent() {
    if (_queue.isEmpty) return;
    final start = _currentIndex < 0 ? 0 : _currentIndex;
    final end = min(_queue.length, start + kLyricsPrefetchAheadTrackCount);
    if (start >= end) return;

    final tracks = _queue.sublist(start, end);
    if (kDebugMode) {
      print(
        'AudioPlayerService: Prefetching lyrics for ${tracks.length} tracks (from index $start)',
      );
    }
    unawaited(_prefetchLyricsForTracks(tracks));
  }

  Future<void> _prefetchLyricsForTracks(List<Track> tracks) async {
    for (final track in tracks) {
      await _lyricsWarmupService.prefetchForTrack(
        videoId: track.id,
        title: track.title,
        artist: track.artist,
        album: track.album,
        durationSeconds: track.duration.inSeconds,
      );
    }
  }



  /// Add tracks to the end of the queue
  void addToQueue(List<Track> tracks) {
    _queue.addAll(tracks);
    _originalQueue.addAll(tracks);
    _queueRevision++;
    _updateState(queue: _queue, queueRevision: _queueRevision);
    _saveQueueDebounced();

    // Prefetch newly added tracks
    if (tracks.isNotEmpty) {
      _ytPlayerUtils.prefetch(
        tracks.map((t) => t.id).toList(),
        quality: _audioQuality,
      );
      if (_jioSaavnEnabled &&
          (_audioQuality == AudioQuality.high ||
              _audioQuality == AudioQuality.max ||
              _audioQuality == AudioQuality.auto)) {
        for (final track in tracks.take(3)) {
          unawaited(JioSaavnService.instance.getBestStreamForTrack(track));
        }
      }
      _schedulePrecacheAhead();
      _scheduleLyricsPrefetchAroundCurrent();

      // If we were at the end of the queue, the immediate next track is now available
      if (_currentIndex >= _queue.length - tracks.length - 1) {
        _prefetchNextTrack();
      }
    }
  }

  /// Insert track to play next
  void playNext(Track track) {
    if (_currentIndex >= 0 && _currentIndex < _queue.length - 1) {
      _queue.insert(_currentIndex + 1, track);
      _originalQueue.insert(_currentIndex + 1, track);
    } else {
      _queue.add(track);
      _originalQueue.add(track);
    }
    _queueRevision++;
    _updateState(queue: _queue, queueRevision: _queueRevision);
    _saveQueueDebounced();

    // Prefetch the track that will play next
    _ytPlayerUtils.prefetchNext(track.id, quality: _audioQuality);
    if (_jioSaavnEnabled &&
        (_audioQuality == AudioQuality.high ||
            _audioQuality == AudioQuality.max ||
            _audioQuality == AudioQuality.auto)) {
      unawaited(JioSaavnService.instance.getBestStreamForTrack(track));
    }
    _schedulePrecacheAhead();
    _scheduleLyricsPrefetchAroundCurrent();
  }

  /// Remove track from queue
  void removeFromQueue(int index) {
    if (index < 0 || index >= _queue.length) return;

    final track = _queue[index];
    _queue.removeAt(index);
    _originalQueue.remove(track);

    if (index < _currentIndex) {
      _currentIndex--;
    } else if (index == _currentIndex) {
      // Current track was removed, play next or stop
      if (_queue.isEmpty) {
        stop();
      } else {
        _currentIndex = _currentIndex.clamp(0, _queue.length - 1);
        _loadAndPlayCurrent();
      }
    }

    _queueRevision++;
    _updateState(
      queue: _queue,
      queueRevision: _queueRevision,
      currentIndex: _currentIndex,
    );
    _saveQueueDebounced();
  }

  /// Reorder queue item from oldIndex to newIndex
  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    if (newIndex < 0 || newIndex >= _queue.length) return;
    if (oldIndex == newIndex) return;

    final track = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, track);

    // Update current index if affected
    if (oldIndex == _currentIndex) {
      _currentIndex = newIndex;
    } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
      _currentIndex--;
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      _currentIndex++;
    }

    _queueRevision++;
    _updateState(
      queue: _queue,
      queueRevision: _queueRevision,
      currentIndex: _currentIndex,
    );
    _saveQueueDebounced();
  }

  /// Jump to specific index in queue
  void skipToIndex(int index) {
    if (index < 0 || index >= _queue.length) return;
    if (index == _currentIndex) return;

    _currentIndex = index;
    _currentTrack = _queue[index];
    unawaited(_loadAndPlayCurrent());
  }

  /// Clear the queue
  void clearQueue() {
    unawaited(_sendYoutubeWatchtime(state: 'paused', force: true));
    _stopYoutubeWatchtimeTimer();
    _queue.clear();
    _originalQueue.clear();
    _currentIndex = -1;
    _currentTrack = null;
    _currentPlaybackData = null;

    _activeSourceQueueIndices = const [];
    _activeSourcePlaybackDataByQueueIndex = const <int, PlaybackData>{};
    _isCrossfading = false;
    _crossfadeTriggeredForTrack = false;
    _isRadioMode = false;
    stop();
    _queueRevision++;
    _updateState(
      queue: _queue,
      queueRevision: _queueRevision,
      currentIndex: _currentIndex,
      currentTrack: null,
      resetCurrentTrack: true,
      currentPlaybackData: null,
      resetCurrentPlaybackData: true,
      isPlaying: false,
      isBuffering: false,
      isLoading: false,
      isRadioMode: false,
      isFetchingRadio: false,
    );
    // Clear persisted queue when explicitly cleared
    QueuePersistenceService.clearQueue();
  }

  /// Load and play the current track using OuterTune pipeline
  ///
  /// Key optimization: If stream URL is already cached, this is nearly instant.
  /// The only delay is the HTTP buffer fill, which we minimize by:
  /// 1. Using audio-only streams (smaller)
  /// 2. Pre-resolving URLs before play is tapped
  /// 3. Not re-validating on play (validation done during prefetch)
  Future<void> _loadAndPlayCurrent() async {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return;
    _flushWatchtimeForCurrentTrackBeforeSwitch();

    _crossfadeTriggeredForTrack = false;
    _currentTrack = _queue[_currentIndex];
    
    // --- SMART AUTO-SWAP (Prefer Audio Versions) ---
    if (_preferAudioVersions && _currentTrack != null && !_isLocalTrack(_currentTrack!)) {
      final t = _currentTrack!;
      final title = t.title.toLowerCase();
      // Heuristic for YouTube Music: Music videos rarely have an album field, and often have "video" in the title
      if (t.album == null || t.album!.isEmpty || title.contains('video') || title.contains('visualizer')) {
        if (_innerTubeService != null) {
          try {
            final query = "${t.title} ${t.artist} song";
            if (kDebugMode) print('AudioPlayerService: Auto-swapping to audio version for $query...');
            final results = await _innerTubeService!.search(query, filter: 'songs');
            if (results.tracks.isNotEmpty) {
              final best = results.tracks.first;
              if (best.id != t.id) {
                final diff = (t.duration.inSeconds - best.duration.inSeconds).abs();
                // Ensure it's roughly the same song length (prevent swapping with extended remixes)
                if (diff <= 30) {
                  if (kDebugMode) print('AudioPlayerService: Swapped ${t.id} for ${best.id}');
                  _currentTrack = best.copyWith(setVideoId: t.setVideoId);
                  _queue[_currentIndex] = _currentTrack!;
                  
                  // Update the original queue too if it's there
                  final origIdx = _originalQueue.indexWhere((x) => x.id == t.id);
                  if (origIdx != -1) _originalQueue[origIdx] = _currentTrack!;
                }
              }
            }
          } catch (e) {
            if (kDebugMode) print('AudioPlayerService: Auto-swap failed: $e');
          }
        }
      }
    }
    // ---------------------------------------------

    final trackForLyrics = _currentTrack!;
    _currentPlaybackData = null;
    if (_pendingSeekTrackId != null &&
        _pendingSeekTrackId != _currentTrack!.id) {
      _pendingSeekPosition = null;
      _pendingSeekTrackId = null;
    }

    // Show loading state immediately
    _updateState(
      currentTrack: _currentTrack,
      currentIndex: _currentIndex,
      duration: _currentTrack?.duration,
      resetDuration: _currentTrack?.duration == null || _currentTrack!.duration == Duration.zero,
      isLoading: true,
      error: null,
      currentPlaybackData: null,
    );

    // Warm lyrics cache immediately when track changes.
    unawaited(
      _lyricsWarmupService.prefetchForTrack(
        videoId: trackForLyrics.id,
        title: trackForLyrics.title,
        artist: trackForLyrics.artist,
        album: trackForLyrics.album,
        durationSeconds: trackForLyrics.duration.inSeconds,
      ),
    );

    try {
      final trackId = _currentTrack!.id;
      final stopwatch = Stopwatch()..start();
      await _inactivePlayer.stop();
      await _player.setVolume(1.0);

      if (kDebugMode) {
        print(
          'AudioPlayerService: Getting stream for $trackId (${_currentTrack!.title})',
        );
      }

      // Check if track has a local file - play directly without streaming
      String? resolvedLocalPath = _currentTrack!.localFilePath;
      if (resolvedLocalPath == null) {
        try {
          if (!Hive.isBoxOpen('music_downloads')) {
            await Hive.openBox<DownloadEntity>('music_downloads');
          }
          final box = Hive.box<DownloadEntity>('music_downloads');
          final entity = box.values.where((e) => e.trackId == _currentTrack!.id).firstOrNull;
          if (entity != null) {
            resolvedLocalPath = entity.localPath;
          }
        } catch (_) {}
      }

      if (resolvedLocalPath != null) {
        final localFile = File(resolvedLocalPath);
        if (await localFile.exists()) {
          final fileSize = await localFile.length();
          if (kDebugMode) {
            print(
              'AudioPlayerService: Playing local file: $resolvedLocalPath (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)',
            );
          }

          // Check if file is too small (likely corrupted)
          if (fileSize < 10000) {
            if (kDebugMode) {
              print(
                'AudioPlayerService: Local file too small ($fileSize bytes), likely corrupted. Falling back to stream.',
              );
            }
          } else {
            // Enrich track metadata (artist, album, artwork) in background if missing
            if (LocalArtworkService.isArtistMissing(_currentTrack!.artist)) {
              unawaited(LocalArtworkService.fetchOnlineMetadata(_currentTrack!));
            }
            try {
              // Use Uri.file for proper file:// URI on Android
              final fileUri = Uri.file(resolvedLocalPath);
              if (kDebugMode) {
                print('AudioPlayerService: Using file URI: $fileUri');
              }

              final localPlaybackData = await _resolvePlaybackDataForLocalTrack(
                _currentTrack!,
                localFile,
                fileSize,
              );
              _currentPlaybackData = localPlaybackData;

              await _player.setAudioSource(
                AudioSource.uri(fileUri, tag: _currentTrack),
              );
              _activeSourceQueueIndices = <int>[_currentIndex];
              if (localPlaybackData != null) {
                _activeSourcePlaybackDataByQueueIndex = <int, PlaybackData>{
                  _currentIndex: localPlaybackData,
                };
              } else {
                _activeSourcePlaybackDataByQueueIndex =
                    const <int, PlaybackData>{};
              }
              if (_pendingSeekPosition != null &&
                  _pendingSeekTrackId == _currentTrack!.id) {
                await _player.seek(_pendingSeekPosition);
                _positionController.add(_pendingSeekPosition!);
                _updateState(position: _pendingSeekPosition);
                _pendingSeekPosition = null;
                _pendingSeekTrackId = null;
              }
              _player.play();
              _updateState(
                isLoading: false,
                currentPlaybackData: localPlaybackData,
                resetCurrentPlaybackData: localPlaybackData == null,
              );
              _prefetchNextTrack();
              return;
            } catch (e) {
              if (kDebugMode) {
                print('AudioPlayerService: Failed to play local file: $e');
              }
              if (kDebugMode) {
                print('AudioPlayerService: Falling back to streaming...');
              }
            }
          }
        } else {
          if (kDebugMode) {
            print(
              'AudioPlayerService: Local file not found at: $resolvedLocalPath',
            );
          }
        }
      }

      // 0. A lossless copy already resolved (prefetched while the previous
      // track played) starts straight away; otherwise the track starts on
      // whatever answers first and is upgraded once lossless turns up.
      if (_qualityAllowsLossless) {
        final cachedLossless = AddonService.instance.cachedFor(_currentTrack!);
        if (cachedLossless != null) {
          try {
            await _playAddonStream(
              cachedLossless,
              _currentTrack!,
              resolveTimeMs: stopwatch.elapsedMilliseconds,
            );
            return;
          } catch (e) {
            if (kDebugMode) {
              print('AudioPlayerService: Lossless start failed, falling back: $e');
            }
          }
        }
      }

      // 1. Check if JioSaavn stream is requested.
      final qualityAllowsSaavn = _jioSaavnEnabled &&
          (_audioQuality == AudioQuality.high ||
              _audioQuality == AudioQuality.max ||
              _audioQuality == AudioQuality.auto);

      // Check if JioSaavn stream is already cached (e.g. from prefetch)
      if (qualityAllowsSaavn) {
        final cachedSaavnStream =
            JioSaavnService.instance.getCachedStream(trackId);
        if (cachedSaavnStream != null && cachedSaavnStream.bitrateKbps >= 320) {
          await _playJioSaavnStream(
            cachedSaavnStream,
            _currentTrack!,
            resolveTimeMs: stopwatch.elapsedMilliseconds,
          );
          return;
        }
      }

      final wantsJioSaavn = qualityAllowsSaavn;

      // Check if URL is already cached (should be instant if prefetched)
      final hasCached = _ytPlayerUtils.hasCachedData(trackId);
      if (hasCached) {
        if (kDebugMode) {
          print('AudioPlayerService: URL already cached (prefetched)');
        }
      }

      // 2. Concurrently resolve JioSaavn and YouTube streams
      Future<JioSaavnStream?>? saavnFuture;
      if (wantsJioSaavn) {
        saavnFuture =
            JioSaavnService.instance.getBestStreamForTrack(_currentTrack!);
      }

      final ytFuture = _ytPlayerUtils.playerResponseForPlayback(
        trackId,
        quality: _audioQuality,
        isMetered: false,
      );

      PlaybackResult? ytResult;
      JioSaavnStream? directSaavnStream;

      if (saavnFuture != null) {
        // Race JioSaavn against YouTube
        final first = await Future.any<dynamic>([
          saavnFuture
              .then((s) => ('saavn', s))
              .catchError((_) => ('saavn', null)),
          ytFuture
              .then((r) => ('yt', r))
              .catchError((e) => ('yt', PlaybackResult.failure(e.toString()))),
        ]);

        if (first.$1 == 'saavn') {
          final s = first.$2 as JioSaavnStream?;
          if (s != null && s.bitrateKbps >= 320) {
            directSaavnStream = s;
          } else {
            ytResult = await ytFuture;
          }
        } else {
          ytResult = first.$2 as PlaybackResult;
          // If YouTube finished first, give JioSaavn a short 400ms bounded race window
          try {
            final quickSaavn =
                await saavnFuture.timeout(const Duration(milliseconds: 400));
            if (quickSaavn != null && quickSaavn.bitrateKbps >= 320) {
              directSaavnStream = quickSaavn;
            }
          } catch (_) {
            // Still pending or timed out, will be handed to background upgrade
          }
        }
      } else {
        ytResult = await ytFuture;
      }

      // If JioSaavn won the race, play directly with 320kbps!
      if (directSaavnStream != null && directSaavnStream.bitrateKbps >= 320) {
        await _playJioSaavnStream(
          directSaavnStream,
          _currentTrack!,
          resolveTimeMs: stopwatch.elapsedMilliseconds,
        );
        return;
      }

      // Otherwise proceed with YouTube stream
      ytResult ??= await ytFuture;

      final urlResolveTime = stopwatch.elapsedMilliseconds;
      if (kDebugMode) {
        print(
          'AudioPlayerService: URL resolve took ${urlResolveTime}ms (cached: $hasCached)',
        );
      }

      if (!ytResult.isSuccess) {
        if (kDebugMode) {
          print(
            'AudioPlayerService: Failed to get stream URL: ${ytResult.error}',
          );
        }
        // Fallback: If YouTube failed, wait up to 4s for JioSaavn
        if (saavnFuture != null) {
          try {
            final fallbackSaavn =
                await saavnFuture.timeout(const Duration(seconds: 4));
            if (fallbackSaavn != null && fallbackSaavn.bitrateKbps >= 320) {
              await _playJioSaavnStream(
                fallbackSaavn,
                _currentTrack!,
                resolveTimeMs: stopwatch.elapsedMilliseconds,
              );
              return;
            }
          } catch (_) {}
        }
        // Last resort: the lossless addon may still have this song.
        if (_qualityAllowsLossless && AddonService.instance.isEnabled) {
          try {
            final lossless = await AddonService.instance
                .matchFor(_currentTrack!)
                .timeout(const Duration(seconds: 8));
            if (lossless != null && _currentTrack?.id == trackId) {
              _logLossless('YouTube failed; playing the lossless copy instead');
              await _playAddonStream(
                lossless,
                _currentTrack!,
                resolveTimeMs: stopwatch.elapsedMilliseconds,
              );
              return;
            }
          } catch (_) {}
        }
        _updateState(
          error: ytResult.error ?? 'Could not get stream URL',
          isLoading: false,
        );
        return;
      }

      final playbackData = ytResult.data!;
      _currentPlaybackData = playbackData;

      // Enrich currentTrack if artist or duration were missing/placeholder
      final details = playbackData.videoDetails;
      if (details != null && _currentTrack != null) {
        bool trackChanged = false;
        var updated = _currentTrack!;
        const badPlaceholders = {
          'unknown artist',
          'song',
          'video',
          'album',
          'single',
          'ep',
          'playlist',
          '',
        };
        final artistLower = updated.artist.toLowerCase().trim();
        if (badPlaceholders.contains(artistLower) &&
            details.author.isNotEmpty &&
            !badPlaceholders.contains(details.author.toLowerCase().trim())) {
          updated = updated.copyWith(artist: details.author);
          trackChanged = true;
        }
        if (updated.duration <= Duration.zero &&
            details.duration > Duration.zero) {
          updated = updated.copyWith(duration: details.duration);
          trackChanged = true;
        }
        if (trackChanged) {
          _currentTrack = updated;
          if (_currentIndex >= 0 && _currentIndex < _queue.length) {
            _queue[_currentIndex] = updated;
          }
          for (int i = 0; i < _originalQueue.length; i++) {
            if (_originalQueue[i].id == updated.id) {
              _originalQueue[i] = updated;
              break;
            }
          }
          _queueRevision++;
          _updateState(
            currentTrack: _currentTrack,
            duration: updated.duration,
            queue: _queue,
            queueRevision: _queueRevision,
          );
        }
      }

      // Reset client failures on success
      _ytPlayerUtils.resetClientFailures();

      if (kDebugMode) {
        print('AudioPlayerService: Got stream: ${playbackData.format}');
      }
      if (kDebugMode) {
        print(
          'AudioPlayerService: URL expires in ${playbackData.timeUntilExpiry.inMinutes} minutes',
        );
      }

      // Set URL and start playback
      // Note: setAudioSource does HTTP buffering - this is the main delay
      stopwatch.reset();
      final sourcePlan = await _buildPlaybackSourcePlanForCurrentTrack(
        _currentTrack!,
        playbackData,
      );
      final source = sourcePlan.source;
      _activeSourceQueueIndices = sourcePlan.queueIndices;
      _activeSourcePlaybackDataByQueueIndex =
          sourcePlan.playbackDataByQueueIndex;

      try {
        if (source is ConcatenatingAudioSource) {
          await _player.setAudioSource(
            source,
            // Pre-buffer ahead for smoother playback
            preload: true,
            initialIndex: 0,
          );
        } else {
          await _player.setAudioSource(
            source,
            // Pre-buffer ahead for smoother playback
            preload: true,
          );
        }
      } catch (e) {
        // ignore: experimental_member_use
        if (source is LockCachingAudioSource && _isLoopbackCleartextError(e)) {
          if (kDebugMode) {
            print(
              'AudioPlayerService: Local proxy blocked by cleartext policy, falling back to direct stream',
            );
          }
          _allowProxyCachingSource = false;
          _activeSourceQueueIndices = <int>[_currentIndex];
          _activeSourcePlaybackDataByQueueIndex = <int, PlaybackData>{
            _currentIndex: playbackData,
          };
          await _player.setAudioSource(
            AudioSource.uri(
              Uri.parse(playbackData.streamUrl),
              tag: _currentTrack,
            ),
            preload: true,
          );
        } else {
          rethrow;
        }
      }

      if (_pendingSeekPosition != null &&
          _pendingSeekTrackId == _currentTrack!.id) {
        await _player.seek(_pendingSeekPosition);
        _positionController.add(_pendingSeekPosition!);
        _updateState(position: _pendingSeekPosition);
        _pendingSeekPosition = null;
        _pendingSeekTrackId = null;
      }

      final bufferTime = stopwatch.elapsedMilliseconds;
      if (kDebugMode) {
        print('AudioPlayerService: Buffer setup took ${bufferTime}ms');
      }

      // Start playback immediately (without waiting on it — see
      // _startPlayback; awaiting held the lossless upgrade back until pause)
      _startPlayback();

      _updateState(isLoading: false, currentPlaybackData: playbackData);

      final totalTime = urlResolveTime + bufferTime;
      if (kDebugMode) {
        print('AudioPlayerService: Playing! Total time: ${totalTime}ms');
      }

      // Prefetch next track while current plays
      _prefetchNextTrack();
      unawaited(_enforceAudioCacheLimit());

      // Attempt seamless upgrade to JioSaavn 320kbps in background.
      // Never for live streams — JioSaavn would overwrite the live HLS.
      if (_currentTrack != null && wantsJioSaavn && !playbackData.isLive) {
        unawaited(
          _upgradeTrackQualityIfPossible(
            _currentTrack!,
            inFlightStream: saavnFuture,
          ),
        );
      }
      if (_currentTrack != null && !playbackData.isLive) {
        unawaited(_upgradeToLosslessIfPossible(_currentTrack!));
      }
    } catch (e) {
      unawaited(_player.setVolume(1.0));
      if (kDebugMode) {
        print('AudioPlayerService: Error: $e');
      }
      _updateState(error: e.toString(), isLoading: false);
    }
  }

  /// Plays a resolved JioSaavn 320kbps stream directly.
  Future<void> _playJioSaavnStream(
    JioSaavnStream saavnStream,
    Track track, {
    int? resolveTimeMs,
  }) async {
    if (kDebugMode) {
      print(
        'AudioPlayerService: Playing JioSaavn 320kbps stream (${saavnStream.streamUrl})',
      );
    }
    final saavnPlaybackData = PlaybackData(
      streamUrl: saavnStream.streamUrl,
      format: AudioFormat(
        mimeType: 'audio/mp4',
        bitrate: saavnStream.bitrateKbps * 1000,
        codecs: 'mp4a.40.2',
      ),
      playbackTracking: _authenticatedPlaybackTracking ?? _currentPlaybackData?.playbackTracking,
      streamExpiresInSeconds: 86400,
      fetchedAt: DateTime.now(),
      audioSource: 'JioSaavn',
    );
    _currentPlaybackData = saavnPlaybackData;
    _activeSourceQueueIndices = <int>[_currentIndex];
    _activeSourcePlaybackDataByQueueIndex = <int, PlaybackData>{
      _currentIndex: saavnPlaybackData,
    };
    final saavnSource = AudioSource.uri(
      Uri.parse(saavnStream.streamUrl),
      tag: track,
    );
    await _player.setAudioSource(saavnSource, preload: true);
    if (_pendingSeekPosition != null && _pendingSeekTrackId == track.id) {
      await _player.seek(_pendingSeekPosition);
      _positionController.add(_pendingSeekPosition!);
      _updateState(position: _pendingSeekPosition);
      _pendingSeekPosition = null;
      _pendingSeekTrackId = null;
    }
    _startPlayback();
    _updateState(isLoading: false, currentPlaybackData: saavnPlaybackData);
    if (_activePlaybackTracking == null && !track.id.startsWith('local_')) {
      debugPrint('[YTM-Tracking] JioSaavn stream playing, resolving YouTube tracking for ${track.id}...');
      unawaited(_resolveYoutubeTrackingForCurrentTrack(track.id));
    }
    // 320 kbps is the interim copy; lossless still replaces it when found.
    unawaited(_upgradeToLosslessIfPossible(track));
    if (kDebugMode) {
      if (resolveTimeMs != null) {
        print(
          'AudioPlayerService: JioSaavn playing! Total resolve time: ${resolveTimeMs}ms',
        );
      }
    }
    _prefetchNextTrack();
    unawaited(_enforceAudioCacheLimit());
  }

  /// Lossless (a FLAC is ~10x a lossy stream) on Max always, and on Auto
  /// while on Wi-Fi. High stays on the best lossy copy.
  bool get _qualityAllowsLossless =>
      _audioQuality == AudioQuality.max ||
      (_audioQuality == AudioQuality.auto && _onUnmeteredNetwork);

  /// Waits before looking again when the addon couldn't be reached.
  static const _losslessLookRetries = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
  ];

  void _logLossless(String message) {
    if (kDebugMode) debugPrint('[Lossless] $message');
  }

  // ---- Automix analysis feed ------------------------------------------

  /// A complete audio file for [track] exists: let Automix analyse from it.
  void _offerToAutomix(Track track, String path) {
    final automix = AutomixService.instance;
    if (!automix.enabled) return;
    unawaited(automix.audioCached(track.id, path));
    unawaited(automix.request(track.id, track.duration));
  }

  /// Queues Automix analysis for [track]. A local file is its own analysis
  /// copy; a streamed track waits for (or asks for) its YouTube file.
  void _requestAutomixAnalysis(Track track) {
    final automix = AutomixService.instance;
    if (!automix.enabled || _jamsModeEnabled) return;
    final local = track.localFilePath;
    if (local != null) unawaited(automix.audioCached(track.id, local));
    unawaited(automix.request(track.id, track.duration));
  }

  // ---- Automix transition engine (BitChord's controller, native) ----------
  //
  // With Automix on, the engine decides when and how each song blends into
  // the next and drives both players' volume, tempo and filters itself. This
  // side does what only it can: load the next song onto the spare player,
  // take over at the blend's midpoint, and stop the outgoing player after.

  /// The engine has the spare player (armed or blending).
  bool _automixMixing = false;
  PlaybackData? _automixIncomingData;
  int _automixIncomingIndex = -1;
  bool _automixSyncScheduled = false;

  bool get _automixOn => AutomixService.instance.enabled && !_jamsModeEnabled;

  AudioPlayer _playerById(String id) =>
      _primaryPlayer.playerId == id ? _primaryPlayer : _secondaryPlayer;

  void _wireAutomixEngine() {
    final automix = AutomixService.instance
      ..onLoad = _automixLoad
      ..onHandoff = _automixHandoff
      ..onRetire = _automixRetire
      ..onPlayState = _automixPlayState;
    // Turning Automix on gives the engine its first picture of the queue.
    automix.addListener(_scheduleAutomixSync);
  }

  /// Coalesces the many state changes of one track change into one sync.
  void _scheduleAutomixSync() {
    if (_automixSyncScheduled) return;
    _automixSyncScheduled = true;
    scheduleMicrotask(() {
      _automixSyncScheduled = false;
      _syncAutomix();
    });
  }

  /// Sent whether or not Automix is on: the same picture drives loudness
  /// normalization, which levels every song (BitChord does it always). With
  /// Automix off the engine is told there's no crossfade, so it never
  /// transitions and Inzx's own crossfade carries on.
  void _syncAutomix() {
    final loudness = <String, double>{};
    for (final t in _queue) {
      final db = _ytPlayerUtils.loudnessDbFor(t.id);
      if (db != null) loudness[t.id] = db;
    }
    unawaited(
      AutomixService.instance.sync(
        primary: _primaryPlayer.playerId,
        secondary: _secondaryPlayer.playerId,
        active: _player.playerId,
        index: _currentIndex,
        queue: [
          for (final t in _queue)
            {
              'id': t.id,
              'title': t.title,
              'artist': t.artist,
              'durationMs': t.duration.inMilliseconds,
              'artwork': t.thumbnailUrl,
              // Podcasts and local files without an id aren't mixed.
              'video': t.podcastId != null,
            },
        ],
        repeat: switch (_loopMode) {
          LoopMode.one => 'one',
          LoopMode.all => 'all',
          LoopMode.off => 'off',
        },
        speed: _player.speed,
        crossfadeSeconds: _automixOn
            ? (_crossfadeDurationMs / 1000).round()
            : 0,
        loudness: loudness,
      ),
    );
  }

  /// The arm: queue entry [index] onto the spare player at [cueMs], silent
  /// and paused; the engine starts it at the blend.
  Future<void> _automixLoad(String playerId, int index, int cueMs) async {
    if (index < 0 || index >= _queue.length) return;
    final player = _playerById(playerId);
    if (identical(player, _player)) return; // never load over the song
    _automixMixing = true;
    final track = _queue[index];
    try {
      final built = await _buildSourceForTrack(track);
      await player.setLoopMode(_nativeLoopModeFor(_loopMode));
      await _setVolumeSafely(player, 0.0, context: 'automix-arm');
      await player.setAudioSource(
        built.source,
        initialPosition: Duration(milliseconds: cueMs),
        preload: true,
      );
      _automixIncomingData = built.playbackData;
      _automixIncomingIndex = index;
      await AutomixService.instance.loaded(playerId, index);
      if (kDebugMode) {
        print('AudioPlayerService: Automix armed ${track.id} at ${cueMs}ms');
      }
    } catch (e) {
      // The engine's arm deadline lapses and it carries on with no blend.
      if (kDebugMode) print('AudioPlayerService: Automix arm failed: $e');
    }
  }

  /// The blend's midpoint: the incoming player is the song now.
  void _automixHandoff(String from, String to, int index) {
    if (index < 0 || index >= _queue.length) return;
    _flushWatchtimeForCurrentTrackBeforeSwitch();
    final incoming = _playerById(to);
    _player = incoming;
    _currentIndex = index;
    _currentTrack = _queue[index];
    final data = _automixIncomingIndex == index ? _automixIncomingData : null;
    if (data != null) _currentPlaybackData = data;
    _activeSourceQueueIndices = <int>[index];
    _activeSourcePlaybackDataByQueueIndex = data == null
        ? const <int, PlaybackData>{}
        : <int, PlaybackData>{index: data};
    _crossfadeTriggeredForTrack = false;
    final duration = incoming.duration;
    if (duration != null) _applyDurationToCurrentTrack(duration);
    _updateState(
      currentTrack: _currentTrack,
      currentIndex: _currentIndex,
      currentPlaybackData: _currentPlaybackData,
      queue: _queue,
      queueRevision: _queueRevision,
      duration: duration,
      resetDuration: duration == null,
      isLoading: false,
      isPlaying: true,
    );
    _resetYoutubePlaybackTrackingForCurrentTrack();
    _startYoutubePlaybackTracking();
    _saveQueueDebounced();
    _prefetchNextTrack();
    _scheduleLyricsPrefetchAroundCurrent();
    AudioRoutingService.reapplyAudioRoute();
    _syncAutomix();
    if (kDebugMode) {
      print('AudioPlayerService: Automix handoff -> ${_currentTrack?.id}');
    }
  }

  /// The engine is done with a player: stop it (after a blend, the old
  /// song; after an abandoned arm, the never-heard incoming one).
  Future<void> _automixRetire(String playerId) async {
    _automixMixing = false;
    final player = _playerById(playerId);
    if (identical(player, _player)) return;
    await player.stop();
    await _setVolumeSafely(player, 1.0, context: 'automix-retire');
    // The blend is over, so the spare player is free for the song's
    // lossless hand-over now.
    final track = _currentTrack;
    if (track != null && _currentPlaybackData?.format.isLossless != true) {
      unawaited(_upgradeToLosslessIfPossible(track));
    }
  }

  /// The engine started/paused a player itself; keep just_audio's own
  /// idea of it in step.
  void _automixPlayState(String playerId, bool playing) {
    final player = _playerById(playerId);
    if (playing && !player.playing) {
      unawaited(player.play().catchError((Object _) {}));
    } else if (!playing && player.playing) {
      unawaited(player.pause());
    }
  }

  /// Downloads [videoId]'s YouTube audio into the stream cache for Automix
  /// to analyse, whatever source is audible for it (lossless, JioSaavn) —
  /// the canonical copy BitChord analyses too.
  Future<void> fetchAnalysisAudio(String videoId) async {
    final track = _currentTrack?.id == videoId
        ? _currentTrack
        : _queue.where((t) => t.id == videoId).firstOrNull;
    if (track == null || _isLocalTrack(track)) return;
    try {
      final result = await _ytPlayerUtils.playerResponseForPlayback(
        videoId,
        quality: _audioQuality,
        isMetered: false,
      );
      final data = result.data;
      if (!result.isSuccess || data == null) return;
      await _precacheTrackAudioBytes(track, data);
    } catch (e) {
      if (kDebugMode) print('AudioPlayerService: Automix audio fetch failed: $e');
    }
  }

  /// Starts the current player without waiting on it.
  ///
  /// just_audio's `play()` future only completes when playback is paused,
  /// stopped or finished (it returns at once only if already playing). So
  /// `await _player.play()` on a fresh start held back everything after it
  /// — the next-track prefetch and the mid-song lossless upgrade — until
  /// the listener paused. That is why a song tapped from Home stayed on
  /// Opus while the ones after it (already playing → instant return)
  /// upgraded.
  void _startPlayback() {
    unawaited(
      _player.play().catchError((Object e) {
        if (kDebugMode) print('AudioPlayerService: play() failed: $e');
      }),
    );
  }

  PlaybackData _addonPlaybackData(
    AddonMatch match, {
    bool forCurrentTrack = true,
  }) {
    final stream = match.stream;
    return PlaybackData(
      streamUrl: stream.url,
      format: AudioFormat(
        mimeType: stream.isDash ? 'application/dash+xml' : 'audio/flac',
        bitrate: stream.bitrate ?? 1411200,
        sampleRate: stream.sampleRate ?? 44100,
        bitsPerSample: stream.bitDepth ?? 16,
        codecs: stream.codec.toLowerCase(),
      ),
      playbackTracking: forCurrentTrack
          ? _authenticatedPlaybackTracking ??
                _currentPlaybackData?.playbackTracking
          : null,
      // Addon stream URLs are pre-signed and short-lived.
      streamExpiresInSeconds: 20 * 60,
      fetchedAt: DateTime.now(),
      audioSource: match.addonName,
    );
  }

  AudioSource _addonAudioSource(AddonMatch match, Track track) {
    final uri = Uri.parse(match.stream.url);
    return match.stream.isDash
        ? DashAudioSource(uri, tag: track)
        : AudioSource.uri(uri, tag: track);
  }

  /// Starts [track] directly on its lossless copy.
  Future<void> _playAddonStream(
    AddonMatch match,
    Track track, {
    int? resolveTimeMs,
  }) async {
    if (kDebugMode) {
      print(
        'AudioPlayerService: Playing ${match.stream.formatLabel} from ${match.addonName}',
      );
    }
    final playbackData = _addonPlaybackData(match);
    await _player.setAudioSource(_addonAudioSource(match, track), preload: true);
    _currentPlaybackData = playbackData;
    _activeSourceQueueIndices = <int>[_currentIndex];
    _activeSourcePlaybackDataByQueueIndex = <int, PlaybackData>{
      _currentIndex: playbackData,
    };
    if (_pendingSeekPosition != null && _pendingSeekTrackId == track.id) {
      await _player.seek(_pendingSeekPosition);
      _positionController.add(_pendingSeekPosition!);
      _updateState(position: _pendingSeekPosition);
      _pendingSeekPosition = null;
      _pendingSeekTrackId = null;
    }
    _startPlayback();
    _updateState(isLoading: false, currentPlaybackData: playbackData);
    if (_activePlaybackTracking == null && !track.id.startsWith('local_')) {
      unawaited(_resolveYoutubeTrackingForCurrentTrack(track.id));
    }
    if (kDebugMode && resolveTimeMs != null) {
      debugPrint('AudioPlayerService: Lossless playing in ${resolveTimeMs}ms');
    }
    _prefetchNextTrack();
    unawaited(_enforceAudioCacheLimit());
  }

  /// The second look: a track that started on a lossy copy asks the addon
  /// for its lossless one while it plays, and moves onto it mid-song if
  /// it's the same recording ([AddonService.pickBest] decides that).
  ///
  /// Every guard here errs towards not swapping — a missed upgrade is
  /// silent, an interrupted song isn't.
  Future<void> _upgradeToLosslessIfPossible(Track track) async {
    final addons = AddonService.instance;
    if (!_qualityAllowsLossless) {
      _logLossless('Off: lossless needs Max quality, or Auto on Wi-Fi');
      return;
    }
    if (!addons.isEnabled) return;
    if (track.localFilePath != null || track.id.startsWith('local_')) return;
    if (_currentPlaybackData?.format.isLossless == true) return;
    // Several start paths ask for the same song (playback start, crossfade
    // arrival, gapless advance, the end of a blend). A second ask must not
    // start a second search; it's the same question.
    if (_losslessLookupTrackId == track.id) {
      _logLossless('Already looking for "${track.title}"');
      return;
    }
    _losslessLookupTrackId = track.id;
    try {
      _logLossless('Looking for a lossless copy of "${track.title}"');
      var match = await addons.matchFor(track);
      // A slow or dropped connection isn't a verdict on the track: look
      // again while the song plays, until the addon actually answers.
      for (final wait in _losslessLookRetries) {
        if (match != null || addons.isSettledMiss(track)) break;
        _logLossless(
          'Couldn\'t reach the addon for "${track.title}"; '
          'trying again in ${wait.inSeconds}s',
        );
        await Future.delayed(wait);
        if (_currentTrack?.id != track.id) {
          _logLossless('Stopped looking for "${track.title}": the song changed');
          return;
        }
        match = await addons.matchFor(track);
      }
      if (match == null) {
        _logLossless('No matching lossless copy for "${track.title}"');
        return;
      }
      // A fresh find was already announced (see _onLosslessFound); a cached
      // one wasn't, so start the hand-over here. Starting twice is harmless.
      unawaited(_beginLosslessHandOver(track, match));
    } finally {
      if (_losslessLookupTrackId == track.id) _losslessLookupTrackId = null;
    }
  }

  String? _losslessLookupTrackId;
  String? _losslessHandOverTrackId;

  /// The addon found a lossless copy of some song. If it's the one playing
  /// (on a lossy stream), move onto it now — whichever lookup asked, and
  /// whatever became of that lookup since.
  void _onLosslessFound(({String trackId, AddonMatch match}) found) {
    final track = _currentTrack;
    if (track == null || track.id != found.trackId) return;
    if (!_qualityAllowsLossless) return;
    unawaited(_beginLosslessHandOver(track, found.match));
  }

  /// Moves the playing [track] onto [match] mid-song. Only one hand-over
  /// runs per song; a newer one for another song takes over.
  Future<void> _beginLosslessHandOver(Track track, AddonMatch match) async {
    if (_losslessHandOverTrackId == track.id) return; // already under way
    if (_currentTrack?.id != track.id) {
      _logLossless('Not upgrading "${track.title}": the song changed');
      return;
    }
    if (_currentPlaybackData?.format.isLossless == true) return;
    if (_currentPlaybackData?.isLive == true) return;

    final handOverId = ++_losslessUpgradeId;
    _losslessHandOverTrackId = track.id;
    bool stillWanted() =>
        handOverId == _losslessUpgradeId &&
        _currentTrack?.id == track.id &&
        _currentPlaybackData?.format.isLossless != true;

    _logLossless(
      'Found ${match.stream.formatLabel} for "${track.title}"; handing over',
    );
    // A copy is known to exist from here, so the player can truthfully say
    // it's upgrading until the hand-over lands or is given up on.
    _losslessUpgradingController.add(track.id);
    try {
      await _handOverToLossless(track, match, stillWanted);
    } finally {
      if (_losslessUpgradingController.value == track.id) {
        _losslessUpgradingController.add(null);
      }
      if (_losslessHandOverTrackId == track.id) _losslessHandOverTrackId = null;
    }
  }

  Future<void> _handOverToLossless(
    Track track,
    AddonMatch match,
    bool Function() stillWanted,
  ) async {
    // Two tries: the first can lose to a crossfade or JioSaavn hand-over
    // starting at the same moment, or to a slow network.
    for (var attempt = 1; attempt <= 2; attempt++) {
      // Let a crossfade or another hand-over already under way finish
      // (a crossfade alone is 8 s by default).
      // An Automix blend (up to ~30 s) holds the spare player too.
      for (var i = 0;
          i < 400 && (_isUpgradingStream || _isCrossfading || _automixMixing);
          i++) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      if (!stillWanted()) {
        _logLossless('Hand-over for "${track.title}" dropped: the song changed or is already lossless');
        return;
      }
      if (_isUpgradingStream || _isCrossfading || _automixMixing) {
        _logLossless('Gave up waiting for another hand-over to finish');
        return;
      }

      final swapped = await _seamlessSwap(
        track: track,
        source: _addonAudioSource(match, track),
        playbackData: _addonPlaybackData(match),
        stillWanted: stillWanted,
        // The second try parks further ahead: the first usually lost to a
        // slow network buffering the FLAC.
        lead: Duration(milliseconds: attempt == 1 ? 2500 : 6000),
      );
      if (swapped) {
        _logLossless(
          'Upgraded "${track.title}" to ${match.stream.formatLabel} '
          'at ${_player.position.inSeconds}s',
        );
        return;
      }
      if (!stillWanted()) {
        _logLossless('Hand-over for "${track.title}" dropped: the song changed or is already lossless');
        return;
      }
      if (attempt == 1) await Future.delayed(const Duration(seconds: 3));
    }
    _logLossless('Upgrade for "${track.title}" didn\'t happen');
  }

  /// Moves the playing track onto [source] mid-song without a gap.
  ///
  /// A single player can't change source mid-track without a break while
  /// the new stream buffers. With two players it can: the new copy loads
  /// silently on the idle player, parked a little ahead of where the song
  /// is; once the playing copy reaches that point the new one starts, and a
  /// short equal-power overlap (inaudible between two copies of the same
  /// recording) hands over. Returns false, leaving playback untouched,
  /// whenever that can't be done cleanly.
  Future<bool> _seamlessSwap({
    required Track track,
    required AudioSource source,
    required PlaybackData playbackData,
    required bool Function() stillWanted,
    Duration lead = const Duration(milliseconds: 2500),
  }) async {
    if (_jamsModeEnabled) {
      _logLossless('Hand-over skipped: in a Jam (playback is synced)');
      return false;
    }
    if (_isCrossfading) {
      _logLossless('Hand-over skipped: a crossfade is running');
      return false;
    }
    if (_automixMixing) {
      _logLossless('Hand-over skipped: an Automix blend holds the spare player');
      return false;
    }
    final outgoing = _player;
    final incoming = _inactivePlayer;
    final previousData = _currentPlaybackData;
    final previousByIndex = _activeSourcePlaybackDataByQueueIndex;
    const overlap = Duration(milliseconds: 400);

    Future<bool> abandon(String why) async {
      _logLossless('Hand-over abandoned: $why');
      if (!identical(_player, incoming)) {
        await incoming.stop();
        await _setVolumeSafely(incoming, 1.0, context: 'upgrade-abandon');
      }
      return false;
    }

    void commit() {
      _player = incoming;
      _currentPlaybackData = playbackData;
      _activeSourcePlaybackDataByQueueIndex = <int, PlaybackData>{
        _currentIndex: playbackData,
      };
      _updateState(
        currentPlaybackData: playbackData,
        duration: incoming.duration,
        isLoading: false,
      );
      AudioRoutingService.reapplyAudioRoute();
      // The song is on the other player now: tell the Automix engine.
      _syncAutomix();
    }

    _isUpgradingStream = true;
    // The Automix engine waits out the hand-over (it shares the spare).
    unawaited(AutomixService.instance.setBusy(true));
    try {
      final total = outgoing.duration ?? track.duration;
      var startAt = outgoing.position + lead;
      // Too close to the end to be worth it; the next track starts soon.
      if (total > Duration.zero &&
          startAt > total - const Duration(seconds: 8)) {
        _logLossless('Hand-over skipped: too close to the end of the song');
        return false;
      }

      await incoming.stop();
      await incoming.setLoopMode(_nativeLoopModeFor(_loopMode));
      await incoming.setSpeed(outgoing.speed);
      await _setVolumeSafely(incoming, 0.0, context: 'upgrade-bootstrap');
      final loading = Stopwatch()..start();
      await incoming.setAudioSource(
        source,
        initialPosition: startAt,
        preload: true,
      );
      // How long this connection takes to get the new copy going: a re-park
      // has to be at least that far ahead to be ready in time.
      final loadTook = loading.elapsed;
      _logLossless(
        'Lossless copy buffered, parked at ${startAt.inMilliseconds} ms '
        '(playing at ${outgoing.position.inMilliseconds} ms)',
      );
      if (!stillWanted() || _isCrossfading) {
        return await abandon('track changed or a crossfade started');
      }

      if (!outgoing.playing) {
        // Paused: nothing audible to blend. Line up and hand over.
        await incoming.seek(outgoing.position);
        commit();
        await outgoing.stop();
        await _setVolumeSafely(outgoing, 1.0, context: 'upgrade-paused-out');
        await _setVolumeSafely(incoming, 1.0, context: 'upgrade-paused-in');
        return true;
      }

      // Buffering took longer than the lead: park once more, as far ahead as
      // the load just took (a slow network needs the room).
      if (outgoing.position >= startAt - const Duration(milliseconds: 100)) {
        final repark = loadTook > const Duration(milliseconds: 1500)
            ? loadTook + const Duration(milliseconds: 500)
            : const Duration(milliseconds: 1500);
        startAt = outgoing.position + repark;
        if (total > Duration.zero &&
            startAt > total - const Duration(seconds: 8)) {
          return await abandon('too close to the end after re-parking');
        }
        _logLossless('Slow to buffer (${loadTook.inMilliseconds} ms); '
            're-parking ${repark.inMilliseconds} ms ahead');
        await incoming.seek(startAt);
        if (!stillWanted() || outgoing.position >= startAt) {
          return await abandon('the new copy couldn\'t keep up');
        }
      }

      // Wait for the playing copy to reach the parked position.
      final deadline = DateTime.now().add(
        startAt - outgoing.position + const Duration(seconds: 3),
      );
      while (outgoing.position < startAt - const Duration(milliseconds: 12)) {
        if (!stillWanted() ||
            !outgoing.playing ||
            _isCrossfading ||
            DateTime.now().isAfter(deadline)) {
          return await abandon(
            !outgoing.playing
                ? 'paused while lining up'
                : 'track changed, crossfade, or timed out lining up',
          );
        }
        final remaining = startAt - outgoing.position;
        await Future.delayed(
          remaining > const Duration(milliseconds: 80)
              ? const Duration(milliseconds: 25)
              : const Duration(milliseconds: 3),
        );
      }

      // Handing over to a copy that's still buffering is an audible gap —
      // exactly what this exists to avoid. Leave the song where it is.
      if (incoming.processingState != ProcessingState.ready) {
        return await abandon('the new copy was still buffering at the hand-over');
      }

      commit();
      unawaited(incoming.play());
      await _runOverlapFade(
        outgoing: outgoing,
        incoming: incoming,
        duration: overlap,
      );
      await outgoing.stop();
      await _setVolumeSafely(outgoing, 1.0, context: 'upgrade-reset-out');
      await _stabilizeIncomingAfterCrossfade(incoming);
      return true;
    } catch (e) {
      _logLossless('Hand-over failed: $e');
      if (identical(_player, incoming)) {
        // Failed after handing over: put the old copy back in charge.
        _player = outgoing;
        _currentPlaybackData = previousData;
        _activeSourcePlaybackDataByQueueIndex = previousByIndex;
        _updateState(currentPlaybackData: previousData);
        await _setVolumeSafely(outgoing, 1.0, context: 'upgrade-restore');
        if (!outgoing.playing) unawaited(outgoing.play());
      }
      await incoming.stop();
      await _setVolumeSafely(incoming, 1.0, context: 'upgrade-failed-in');
      return false;
    } finally {
      _isUpgradingStream = false;
      unawaited(AutomixService.instance.setBusy(false));
    }
  }

  /// Prefetch next track in background (OuterTune approach)
  /// This is called after current track starts playing
  void _prefetchNextTrack() {
    // Automix reads both sides of the coming transition: the playing
    // track's ending and the next one's opening.
    final playing = _currentTrack;
    if (playing != null) _requestAutomixAnalysis(playing);
    if (_currentIndex < _queue.length - 1) {
      _requestAutomixAnalysis(_queue[_currentIndex + 1]);
    }
    if (_currentIndex < _queue.length - 1) {
      final nextTrack = _queue[_currentIndex + 1];
      if (!_isLocalTrack(nextTrack)) {
        if (kDebugMode) {
          print('AudioPlayerService: Prefetching next track: ${nextTrack.title}');
        }

        // Fire and forget - don't await
        _ytPlayerUtils.prefetchNext(nextTrack.id, quality: _audioQuality);
      }
      _schedulePrecacheAhead();
      unawaited(
        _lyricsWarmupService.prefetchForTrack(
          videoId: nextTrack.id,
          title: nextTrack.title,
          artist: nextTrack.artist,
          album: nextTrack.album,
          durationSeconds: nextTrack.duration.inSeconds,
        ),
      );

      // Resolve the next track's lossless copy now, so it can start on it.
      if (_qualityAllowsLossless && AddonService.instance.isEnabled) {
        unawaited(AddonService.instance.matchFor(nextTrack));
      }

      // Prefetch JioSaavn 320kbps stream in background if enabled
      if (_jioSaavnEnabled &&
          (_audioQuality == AudioQuality.high ||
              _audioQuality == AudioQuality.max ||
              _audioQuality == AudioQuality.auto)) {
        unawaited(JioSaavnService.instance.getBestStreamForTrack(nextTrack));
        if (_currentIndex < _queue.length - 2) {
          final subsequentTrack = _queue[_currentIndex + 2];
          unawaited(JioSaavnService.instance.getBestStreamForTrack(subsequentTrack));
        }
      }

      // Pre-extract colors for upcoming tracks so song change is instant 0ms
      for (int i = 1; i <= 3 && (_currentIndex + i) < _queue.length; i++) {
        final t = _queue[_currentIndex + i];
        if (t.thumbnailUrl != null) {
          unawaited(AlbumColorExtractor.extractFromUrl(t.thumbnailUrl));
        }
      }
    }
  }

  /// Seamlessly upgrade the current playing track to JioSaavn 320kbps if available
  Future<void> _upgradeTrackQualityIfPossible(
    Track track, {
    Future<JioSaavnStream?>? inFlightStream,
  }) async {
    final sessionId = ++_upgradeSessionId;

    if (!_jioSaavnEnabled) return;

    // Respect data saver quality preferences
    if (_audioQuality == AudioQuality.low ||
        _audioQuality == AudioQuality.medium) {
      return;
    }

    // Do not attempt upgrade for local files
    if (track.localFilePath != null) return;

    // Lossless already: 320 kbps would be a downgrade.
    if (_currentPlaybackData?.format.isLossless == true) return;

    // The lossless upgrade looks this track up at the same moment (the
    // lookup is shared, not repeated). If it finds a FLAC, step aside rather
    // than race it with a 320 kbps hand-over of our own.
    if (_qualityAllowsLossless && AddonService.instance.isEnabled) {
      final lossless = await AddonService.instance.matchFor(track);
      if (lossless != null) return;
      if (sessionId != _upgradeSessionId || _currentTrack?.id != track.id) {
        return;
      }
    }

    // Already playing JioSaavn at 320kbps
    if (_currentPlaybackData?.audioSource == 'JioSaavn' &&
        (_currentPlaybackData?.bitrateKbps ?? 0) >= 320) {
      return;
    }

    try {
      var saavnStream = inFlightStream != null
          ? await inFlightStream
          : null;

      if (saavnStream == null) {
        final current = _currentTrack;
        final candidate =
            (current != null && current.id == track.id) ? current : track;
        saavnStream =
            await JioSaavnService.instance.getBestStreamForTrack(candidate);
      }

      // User changed track or queue in the meantime
      if (sessionId != _upgradeSessionId || _currentTrack?.id != track.id) {
        return;
      }

      if (saavnStream == null) {
        if (kDebugMode) {
          print(
            'AudioPlayerService: No matching JioSaavn stream found for "${track.title}"',
          );
        }
        return;
      }

      // If current bitrate is already higher or equal to this stream
      final currentBitrate = _currentPlaybackData?.bitrateKbps ?? 0;
      if (_currentPlaybackData?.audioSource == 'JioSaavn' &&
          currentBitrate >= saavnStream.bitrateKbps) {
        return;
      }

      if (kDebugMode) {
        print(
          'AudioPlayerService: Upgrading "${track.title}" to JioSaavn ${saavnStream.bitrateKbps}kbps (${saavnStream.streamUrl})',
        );
      }

      final wasPlaying = _player.playing;
      final currentPos = _player.position;

      final upgradedPlaybackData = PlaybackData(
        streamUrl: saavnStream.streamUrl,
        format: AudioFormat(
          mimeType: 'audio/mp4',
          bitrate: saavnStream.bitrateKbps * 1000,
          codecs: 'mp4a.40.2',
        ),
        playbackTracking: _authenticatedPlaybackTracking ?? _currentPlaybackData?.playbackTracking,
        streamExpiresInSeconds: 86400,
        fetchedAt: DateTime.now(),
        audioSource: 'JioSaavn',
      );

      final newSource = AudioSource.uri(
        Uri.parse(saavnStream.streamUrl),
        tag: track,
      );

      // A lossless swap may have landed while JioSaavn was resolving.
      if (_currentPlaybackData?.format.isLossless == true) return;

      bool stillWanted() =>
          sessionId == _upgradeSessionId &&
          _currentTrack?.id == track.id &&
          _currentPlaybackData?.format.isLossless != true;
      if (!_isUpgradingStream &&
          !_isCrossfading &&
          await _seamlessSwap(
            track: track,
            source: newSource,
            playbackData: upgradedPlaybackData,
            stillWanted: stillWanted,
          )) {
        return;
      }
      if (!stillWanted() || _isUpgradingStream) return;

      // Fallback: hot-swap the one player in place (brief break).
      _isUpgradingStream = true;
      try {
        await _player.setAudioSource(
          newSource,
          initialPosition: currentPos,
          preload: true,
        );

        if (sessionId != _upgradeSessionId || _currentTrack?.id != track.id) {
          return;
        }

        if (wasPlaying && !_player.playing) {
          _startPlayback();
        }
      } finally {
        _isUpgradingStream = false;
      }

      _currentPlaybackData = upgradedPlaybackData;
      _activeSourcePlaybackDataByQueueIndex = <int, PlaybackData>{
        _currentIndex: upgradedPlaybackData,
      };

      _updateState(
        currentPlaybackData: upgradedPlaybackData,
        isPlaying: _player.playing,
      );

      if (kDebugMode) {
        print(
          'AudioPlayerService: Successfully upgraded "${track.title}" to JioSaavn at ${currentPos.inSeconds}s',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('AudioPlayerService: Quality upgrade failed gracefully: $e');
      }
    }
  }

  DateTime? _lastLiveResume;

  /// Resume a live stream that hit the end of its DVR window by reloading the
  /// manifest (which re-resolves to the current live edge). Debounced so a
  /// stream that keeps signalling completion can't spin in a tight loop.
  Future<void> _resumeLiveEdge() async {
    final now = DateTime.now();
    if (_lastLiveResume != null &&
        now.difference(_lastLiveResume!) < const Duration(seconds: 3)) {
      // Completing again within 3s means we can't sustain the live edge —
      // stop rather than loop-reload forever.
      _updateState(isPlaying: false, isLoading: false);
      return;
    }
    _lastLiveResume = now;
    await _loadAndPlayCurrent();
  }

  /// Handle track completion
  void _onTrackComplete() {
    // Emit track complete event (for Jams integration)
    if (_currentTrack != null) {
      _trackCompleteController.add(_currentTrack!);
    }

    // If Jams mode is enabled, let the sync controller handle next track
    if (_jamsModeEnabled) {
      if (kDebugMode) {
        print(
          'AudioPlayerService: Track complete - Jams mode, waiting for sync controller',
        );
      }
      _updateState(isPlaying: false);
      return;
    }

    // Check if we should fetch more radio tracks before handling completion
    _checkAndFetchRadioTracks();

    switch (_loopMode) {
      case LoopMode.one:
        _player.seek(Duration.zero);
        _player.play();
        break;
      case LoopMode.all:
        skipToNext();
        break;
      case LoopMode.off:
        if (_currentIndex < _queue.length - 1) {
          skipToNext();
        } else if (_isRadioMode && !_isFetchingRadio) {
          // Queue finished but radio mode is on - fetch more tracks
          _fetchRadioTracks().then((_) {
            if (_queue.length > _currentIndex + 1) {
              skipToNext();
            } else {
              _updateState(isPlaying: false);
            }
          });
        } else {
          // Queue finished
          _updateState(isPlaying: false);
        }
        break;
    }
  }

  /// Check and fetch radio tracks when nearing end of queue
  void _checkAndFetchRadioTracks() {
    if (!_isRadioMode || _isFetchingRadio) return;

    // Calculate remaining tracks
    final remaining = _queue.length - _currentIndex - 1;

    // Fetch more tracks when 5 or fewer tracks remaining (more aggressive for seamless experience)
    if (remaining <= 5) {
      if (kDebugMode) {
        print(
          'AudioPlayerService: $remaining tracks remaining, fetching more radio...',
        );
      }
      _fetchRadioTracks();
    }
  }

  /// Fetch related tracks for YouTube Radio mode using InnerTube's "next" endpoint
  /// This gets the ACTUAL YouTube Music radio queue, not just similar videos
  /// Called repeatedly for infinite radio queue
  Future<void> _fetchRadioTracks() async {
    if (_isFetchingRadio || !_isRadioMode) return;

    // Select source track for variety:
    // - First fetch: use original track
    // - Later fetches: rotate through recent tracks for diversity
    String? sourceId;
    if (_radioFetchCount == 0) {
      sourceId = _radioSourceTrackId ?? _currentTrack?.id;
    } else {
      // Use a track from the latter part of the queue for variety
      // This gives us different "radio seeds" over time
      final queueLength = _queue.length;
      if (queueLength > 3) {
        // Pick from last 30% of queue, rotating based on fetch count
        final startIdx = (queueLength * 0.7).floor();
        final idx = startIdx + (_radioFetchCount % (queueLength - startIdx));
        sourceId = _queue[idx.clamp(0, queueLength - 1)].id;
      } else {
        sourceId = _radioSourceTrackId ?? _currentTrack?.id;
      }
    }

    if (sourceId == null) return;

    // Create fallback InnerTubeService if not set (non-personalized)
    _innerTubeService ??= InnerTubeService();

    _isFetchingRadio = true;
    // Update state to notify UI
    _updateState(isFetchingRadio: true);

    _radioFetchCount++;
    final isPersonalized = _innerTubeService!.isAuthenticated;
    if (kDebugMode) {
      print(
        'AudioPlayerService: Fetching radio batch #$_radioFetchCount for $sourceId (personalized=$isPersonalized)',
      );
    }

    try {
      // Use InnerTube's "next" endpoint to get the proper YouTube Music radio queue
      // Request more tracks for better queue building
      final radioTracks = await _innerTubeService!.getWatchPlaylist(
        sourceId,
        limit: 25, // Request more for better selection
      );

      if (!_isRadioMode) {
        return;
      }

      if (radioTracks.isNotEmpty) {
        // Filter out tracks already in queue AND previously fetched
        final existingIds = _queue.map((t) => t.id).toSet();
        final newTracks = radioTracks
            .where(
              (t) =>
                  !existingIds.contains(t.id) &&
                  !_radioFetchedIds.contains(t.id),
            )
            .toList();

        if (newTracks.isNotEmpty) {
          if (kDebugMode) {
            print(
              'AudioPlayerService: Adding ${newTracks.length} radio tracks to queue (total queue: ${_queue.length + newTracks.length})',
            );
          }

          // Track fetched IDs to avoid future duplicates
          for (final track in newTracks) {
            _radioFetchedIds.add(track.id);
          }

          // Add to queue
          _queue.addAll(newTracks);
          _originalQueue.addAll(newTracks);
          _queueRevision++;

          // Update state
          _updateState(queue: _queue, queueRevision: _queueRevision);

          // Prefetch new tracks for instant playback
          _ytPlayerUtils.prefetch(
            newTracks.map((t) => t.id).toList(),
            quality: _audioQuality,
          );
          _schedulePrecacheAhead();
          _scheduleLyricsPrefetchAroundCurrent();

          // Update radio source for next fetch - use track from new batch
          if (newTracks.length > 2) {
            _radioSourceTrackId = newTracks[newTracks.length ~/ 2].id;
          } else if (newTracks.isNotEmpty) {
            _radioSourceTrackId = newTracks.last.id;
          }
        } else {
          if (kDebugMode) {
            print(
              'AudioPlayerService: All radio tracks were duplicates, trying different source...',
            );
          }
          // If all tracks were duplicates, pick a random source from queue
          if (_queue.length > 5) {
            final randomIdx =
                (_queue.length * 0.5 +
                        (_radioFetchCount * 3) % (_queue.length ~/ 2))
                    .floor();
            _radioSourceTrackId =
                _queue[randomIdx.clamp(0, _queue.length - 1)].id;
          }
        }
      } else {
        if (kDebugMode) {
          print('AudioPlayerService: No radio tracks returned from InnerTube');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('AudioPlayerService: Failed to fetch radio tracks: $e');
      }
    } finally {
      _isFetchingRadio = false;
      // Update state to notify UI
      _updateState(isFetchingRadio: false);
    }
  }

  /// Public method to manually trigger radio track fetching
  /// Used by queue UI when user scrolls near the end
  Future<void> fetchMoreRadioTracks() async {
    if (!_isRadioMode) return;
    await _fetchRadioTracks();
  }

  /// Play
  Future<void> play() async {
    if (_currentTrack == null) return;

    // If no source is loaded (e.g., app restarted), load and play current track.
    if (_player.processingState == ProcessingState.idle ||
        _player.audioSource == null) {
      await _loadAndPlayCurrent();
      return;
    }

    // Check if current stream is still valid
    if (_currentPlaybackData != null && !_currentPlaybackData!.isValid) {
      if (kDebugMode) {
        print('AudioPlayerService: Stream expired, refreshing...');
      }
      await _loadAndPlayCurrent();
      return;
    }
    AudioRoutingService.reapplyAudioRoute();
    unawaited(_player.play());
    for (int i = 1; i <= 6; i++) {
      Future.delayed(Duration(milliseconds: i * 25), AudioRoutingService.reapplyAudioRoute);
    }
  }

  /// Fades the music down over [duration], pauses, and puts the volume back
  /// so the next play starts at full level. Used by the sleep timer.
  Future<void> fadeOutAndPause({
    Duration duration = const Duration(seconds: 10),
  }) async {
    if (!_player.playing) return;
    // A crossfade or quality hand-over is already driving the volumes.
    if (_isCrossfading || _isUpgradingStream) {
      await pause();
      return;
    }
    final player = _player;
    const steps = 40;
    final stepDelay = Duration(
      milliseconds: (duration.inMilliseconds / steps).round(),
    );
    final start = player.volume;
    for (var i = 1; i <= steps; i++) {
      // Stop early if the user paused, skipped or a crossfade took over.
      if (!identical(player, _player) || !player.playing || _isCrossfading) {
        break;
      }
      final t = i / steps;
      await _setVolumeSafely(
        player,
        start * cos(t * pi * 0.5),
        context: 'sleep-fade-$i',
      );
      await Future.delayed(stepDelay);
    }
    await pause();
    await _setVolumeSafely(player, 1.0, context: 'sleep-fade-restore');
  }

  /// Pause
  Future<void> pause() async {
    await _player.pause();
    await _inactivePlayer.pause();
    _persistQueueNow(position: _player.position);
  }

  /// Toggle play/pause
  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await pause();
    } else {
      await play();
    }
  }

  /// Stop playback
  Future<void> stop() async {
    final position = _player.position;
    unawaited(_sendYoutubeWatchtime(state: 'paused', force: true));
    _stopYoutubeWatchtimeTimer();
    _persistQueueNow(position: position);
    await _player.stop();
    await _inactivePlayer.stop();
    _activeSourceQueueIndices = const [];
    _activeSourcePlaybackDataByQueueIndex = const <int, PlaybackData>{};
    _isCrossfading = false;
    _crossfadeTriggeredForTrack = false;
    await _player.setVolume(1.0);
    await _inactivePlayer.setVolume(1.0);
  }

  /// Seek to position
  Future<void> seek(Duration position) async {
    if (_youtubeWatchtimeTimer != null && _player.playing) {
      unawaited(_sendYoutubeWatchtime(state: 'playing', force: true));
      _youtubeTrackingLastPosition = position;
    }
    _seekCount++;
    await _player.seek(position);
  }

  /// Seek by offset
  Future<void> seekBy(Duration offset) async {
    final newPosition = _player.position + offset;
    await seek(newPosition);
  }

  /// Skip to next track
  /// Uses pre-built playlist for instant skip if available (OuterTune approach)
  Future<void> skipToNext() async {
    // A skip is never blended: drop any Automix blend in flight first.
    unawaited(AutomixService.instance.skip());
    // In Jams mode, emit track complete event and let sync controller handle it
    if (_jamsModeEnabled) {
      if (kDebugMode) {
        print(
          'AudioPlayerService: Skip in Jams mode - letting sync controller handle',
        );
      }
      if (_currentTrack != null) {
        _trackCompleteController.add(_currentTrack!);
      }
      _updateState(isPlaying: false);
      return;
    }

    if (_queue.isEmpty) return;

    int newIndex;
    if (_currentIndex < _queue.length - 1) {
      newIndex = _currentIndex + 1;
    } else if (_loopMode == LoopMode.all) {
      newIndex = 0;
    } else {
      return;
    }

    _currentIndex = newIndex;
    await _loadAndPlayCurrent();
  }

  /// Skip to previous track
  Future<void> skipToPrevious() async {
    unawaited(AutomixService.instance.skip());
    if (_queue.isEmpty) return;

    // If more than 3 seconds in, restart current track
    if (_player.position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }

    int newIndex;
    if (_currentIndex > 0) {
      newIndex = _currentIndex - 1;
    } else if (_loopMode == LoopMode.all) {
      newIndex = _queue.length - 1;
    } else {
      await seek(Duration.zero);
      return;
    }

    _currentIndex = newIndex;
    await _loadAndPlayCurrent();
  }

  /// Set loop mode
  Future<void> setLoopMode(LoopMode mode) async {
    _loopMode = mode;
    final nativeMode = _nativeLoopModeFor(mode);
    await _player.setLoopMode(nativeMode);
    await _inactivePlayer.setLoopMode(nativeMode);
    _updateState(loopMode: mode);
  }

  /// Cycle through loop modes
  Future<void> cycleLoopMode() async {
    final modes = [LoopMode.off, LoopMode.all, LoopMode.one];
    final currentModeIndex = modes.indexOf(_loopMode);
    final nextMode = modes[(currentModeIndex + 1) % modes.length];
    await setLoopMode(nextMode);
  }

  LoopMode _nativeLoopModeFor(LoopMode mode) {
    // Playback usually runs on a single-track source, so native "repeat all"
    // would just loop that one item. Playlist repeat is handled in app logic.
    return mode == LoopMode.one ? LoopMode.one : LoopMode.off;
  }

  /// Toggle shuffle
  Future<void> toggleShuffle() async {
    _shuffleEnabled = !_shuffleEnabled;

    if (_shuffleEnabled && _queue.isNotEmpty) {
      // Shuffle queue but keep current track at position 0
      final current = _currentTrack;
      _queue = _shuffleList(_queue, _currentIndex);
      if (current != null) {
        _queue.remove(current);
        _queue.insert(0, current);
      }
      _currentIndex = 0;
    } else if (!_shuffleEnabled && _originalQueue.isNotEmpty) {
      // Restore original order
      final current = _currentTrack;
      _queue = List.from(_originalQueue);
      if (current != null) {
        _currentIndex = _queue.indexOf(current);
        if (_currentIndex == -1) _currentIndex = 0;
      }
    }

    _updateState(
      shuffleEnabled: _shuffleEnabled,
      queue: _queue,
      currentIndex: _currentIndex,
    );
  }

  /// Set playback speed
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
    await _inactivePlayer.setSpeed(speed);
    _updateState(speed: speed);
  }

  /// Set audio quality preference
  void setAudioQuality(AudioQuality quality) {
    _audioQuality = quality;
    _updateState(audioQuality: quality);

    // Persist the setting
    _saveStreamingQuality(quality);

    // Clear cache to force new quality on next track
    _ytPlayerUtils.clearAllCache();
    unawaited(_clearAllAudioCache());
    _schedulePrecacheAhead();
  }

  /// Shuffle a list, optionally keeping an item at index 0
  List<Track> _shuffleList(List<Track> list, int keepAtStart) {
    final shuffled = List<Track>.from(list);
    final random = Random();

    // Fisher-Yates shuffle
    for (var i = shuffled.length - 1; i > 0; i--) {
      final j = random.nextInt(i + 1);
      final temp = shuffled[i];
      shuffled[i] = shuffled[j];
      shuffled[j] = temp;
    }

    // Move the track at keepAtStart to position 0
    if (keepAtStart >= 0 && keepAtStart < list.length) {
      final track = list[keepAtStart];
      shuffled.remove(track);
      shuffled.insert(0, track);
    }

    return shuffled;
  }

  /// Load persisted queue from previous session
  Future<void> _loadPersistedQueue() async {
    try {
      final persistedState = await QueuePersistenceService.loadQueue();
      if (persistedState != null && persistedState.queue.isNotEmpty) {
        if (kDebugMode) {
          print(
            'AudioPlayerService: Restoring ${persistedState.queue.length} tracks from persisted queue',
          );
        }
        final savedAt = persistedState.savedAt;
        final isExpired =
            savedAt != null &&
            DateTime.now().difference(savedAt) > _closedRestoreTtl;
        if (isExpired) {
          // App was closed for too long: clear persisted queue so no stale track shows.
          await QueuePersistenceService.clearQueue();
          return;
        }
        final restoredPosition = persistedState.position;
        _queue = persistedState.queue;
        _originalQueue = List.from(_queue);
        _currentIndex = persistedState.currentIndex;
        _currentTrack = persistedState.currentTrack;
        _queueRevision++;
        final restoredDuration = _currentTrack?.duration;
        final hasRestoredDuration =
            restoredDuration != null && restoredDuration > Duration.zero;
        _lastPositionPersisted = restoredPosition;
        if (restoredPosition > Duration.zero && _currentTrack != null) {
          _pendingSeekPosition = restoredPosition;
          _pendingSeekTrackId = _currentTrack!.id;
          _positionController.add(restoredPosition);
        }

        // Update state to show restored queue (but don't auto-play)
        _updateState(
          queue: _queue,
          queueRevision: _queueRevision,
          currentIndex: _currentIndex,
          currentTrack: _currentTrack,
          position: restoredPosition,
          duration: hasRestoredDuration ? restoredDuration : null,
        );

        if (!hasRestoredDuration) {
          unawaited(_runDurationMigrationIfNeeded());
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('AudioPlayerService: Failed to load persisted queue: $e');
      }
    }
  }

  Duration _resolvePersistPosition(Duration? position) {
    if (position != null) return position;
    if (_pendingSeekPosition != null &&
        _pendingSeekTrackId == _currentTrack?.id) {
      return _pendingSeekPosition!;
    }
    return _player.position;
  }

  void _persistQueueNow({Duration? position, bool log = false}) {
    if (_queue.isEmpty || _currentIndex < 0) return;
    final resolvedPosition = _resolvePersistPosition(position);
    _lastPositionPersisted = resolvedPosition;
    _lastPositionPersistAt = DateTime.now();
    unawaited(
      QueuePersistenceService.saveQueue(
        queue: _queue,
        currentIndex: _currentIndex,
        position: resolvedPosition,
      ),
    );
    if (log && kDebugMode) {
      debugPrint(
        'AudioPlayerService: Queue persisted (${_queue.length} tracks, index $_currentIndex)',
      );
    }
  }

  void _maybePersistPosition(Duration position) {
    if (!_player.playing) return;
    if (_queue.isEmpty || _currentIndex < 0) return;

    final now = DateTime.now();
    final lastAt = _lastPositionPersistAt;
    final delta = (position - _lastPositionPersisted).abs();

    final shouldPersist =
        lastAt == null ||
        now.difference(lastAt) >= _positionPersistInterval ||
        delta >= _positionPersistForceDelta;
    if (!shouldPersist) return;

    _persistQueueNow(position: position);
  }

  /// Save queue state with debouncing to prevent excessive writes
  void _saveQueueDebounced() {
    _persistenceDebounceTimer?.cancel();
    _persistenceDebounceTimer = Timer(_persistenceDebounceDelay, () {
      _persistQueueNow(log: true);
    });
  }

  /// Dispose resources
  void dispose() {
    _persistenceDebounceTimer?.cancel();
    _cacheMaintenanceTimer?.cancel();
    unawaited(_sendYoutubeWatchtime(state: 'paused', force: true));
    _stopYoutubeWatchtimeTimer();
    _stopAllLiveCacheProgressLoggers();
    while (_precacheSlotWaiters.isNotEmpty) {
      final waiter = _precacheSlotWaiters.removeFirst();
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
    _persistQueueNow(position: _player.position);
    _primaryPlayer.dispose();
    _secondaryPlayer.dispose();
    _stateController.close();
    _positionController.close();
    _losslessUpgradingController.close();
    _bufferedPositionController.close();
    _ytPlayerUtils.dispose();
  }
}