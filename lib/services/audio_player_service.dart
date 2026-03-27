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
import 'youtube_music_service.dart';
import 'ytmusic_api_service.dart';
import 'queue_persistence_service.dart';
import 'lyrics/lyrics_service.dart';

/// Key for persisting streaming quality preference
const String kStreamingQualityKey = 'streaming_quality';
const String kStreamCacheWifiOnlyKey = 'stream_cache_wifi_only';
const String kStreamCacheSizeLimitMbKey = 'stream_cache_size_limit_mb';
const String kStreamCacheMaxConcurrentKey = 'stream_cache_max_concurrent';
const String kCrossfadeDurationMsKey = 'crossfade_duration_ms';
const int kDefaultStreamCacheSizeLimitMb = 1024;
const int kMinStreamCacheSizeLimitMb = 128;
const int kMaxStreamCacheSizeLimitMb = 4096;
const int kDefaultStreamCacheMaxConcurrent = 2;
const int kMinStreamCacheMaxConcurrent = 1;
const int kMaxStreamCacheMaxConcurrent = 4;
const int kDefaultCrossfadeDurationMs = 0;
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
  final bool isRadioMode; // Whether radio mode is active (infinite queue)
  final bool
  isFetchingRadio; // Whether we're currently fetching more radio tracks
  final bool streamCacheWifiOnly;
  final int streamCacheSizeLimitMb;
  final int streamCacheMaxConcurrent;
  final int crossfadeDurationMs;

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
    this.audioQuality = AudioQuality.auto,
    this.currentPlaybackData,
    this.queueRevision = 0,
    this.queueSourceId,
    this.isRadioMode = false,
    this.isFetchingRadio = false,
    this.streamCacheWifiOnly = false,
    this.streamCacheSizeLimitMb = kDefaultStreamCacheSizeLimitMb,
    this.streamCacheMaxConcurrent = kDefaultStreamCacheMaxConcurrent,
    this.crossfadeDurationMs = kDefaultCrossfadeDurationMs,
  });

  PlaybackState copyWith({
    Track? currentTrack,
    List<Track>? queue,
    int? currentIndex,
    bool? isPlaying,
    bool? isBuffering,
    bool? isLoading,
    Duration? position,
    Duration? bufferedPosition,
    Duration? duration,
    double? speed,
    LoopMode? loopMode,
    bool? shuffleEnabled,
    String? error,
    AudioQuality? audioQuality,
    PlaybackData? currentPlaybackData,
    int? queueRevision,
    String? queueSourceId,
    bool? isRadioMode,
    bool? isFetchingRadio,
    bool? streamCacheWifiOnly,
    int? streamCacheSizeLimitMb,
    int? streamCacheMaxConcurrent,
    int? crossfadeDurationMs,
  }) {
    return PlaybackState(
      currentTrack: currentTrack ?? this.currentTrack,
      queue: queue ?? this.queue,
      queueRevision: queueRevision ?? this.queueRevision,
      currentIndex: currentIndex ?? this.currentIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      isLoading: isLoading ?? this.isLoading,
      position: position ?? this.position,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      duration: duration ?? this.duration,
      speed: speed ?? this.speed,
      loopMode: loopMode ?? this.loopMode,
      shuffleEnabled: shuffleEnabled ?? this.shuffleEnabled,
      error: error,
      audioQuality: audioQuality ?? this.audioQuality,
      currentPlaybackData: currentPlaybackData ?? this.currentPlaybackData,
      queueSourceId: queueSourceId ?? this.queueSourceId,
      isRadioMode: isRadioMode ?? this.isRadioMode,
      isFetchingRadio: isFetchingRadio ?? this.isFetchingRadio,
      streamCacheWifiOnly: streamCacheWifiOnly ?? this.streamCacheWifiOnly,
      streamCacheSizeLimitMb:
          streamCacheSizeLimitMb ?? this.streamCacheSizeLimitMb,
      streamCacheMaxConcurrent:
          streamCacheMaxConcurrent ?? this.streamCacheMaxConcurrent,
      crossfadeDurationMs: crossfadeDurationMs ?? this.crossfadeDurationMs,
    );
  }

  /// Check if there's a next track
  bool get hasNext =>
      currentIndex < queue.length - 1 || loopMode == LoopMode.all;

  /// Check if there's a previous track
  bool get hasPrevious => currentIndex > 0 || loopMode == LoopMode.all;

  /// Progress as a fraction (0.0 to 1.0)
  double get progress {
    if (duration == null || duration!.inMilliseconds == 0) return 0.0;
    return position.inMilliseconds / duration!.inMilliseconds;
  }

  /// Current stream quality info
  String get qualityInfo {
    if (currentPlaybackData == null) return '';
    final format = currentPlaybackData!.format;
    final kbps = (format.bitrate / 1000).round();
    return '${format.codecs ?? format.mimeType.split('/').last} ${kbps}kbps';
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
        other.isRadioMode == isRadioMode &&
        other.isFetchingRadio == isFetchingRadio &&
        other.streamCacheWifiOnly == streamCacheWifiOnly &&
        other.streamCacheSizeLimitMb == streamCacheSizeLimitMb &&
        other.streamCacheMaxConcurrent == streamCacheMaxConcurrent &&
        other.crossfadeDurationMs == crossfadeDurationMs;
    // NOTE: position and bufferedPosition intentionally excluded
    // to prevent rebuilds on every position update
  }

  @override
  int get hashCode => Object.hash(
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
    isRadioMode,
    isFetchingRadio,
    streamCacheWifiOnly,
    streamCacheSizeLimitMb,
    streamCacheMaxConcurrent,
    crossfadeDurationMs,
  );
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
    // Load persisted queue from previous session
    _loadPersistedQueue();
  }

  /// Set the InnerTubeService instance (for personalized radio)
  /// Call this after authentication to enable personalized recommendations
  void setInnerTubeService(InnerTubeService service) {
    _innerTubeService = service;
    if (kDebugMode) {
      print(
        'AudioPlayerService: InnerTubeService set, authenticated=${service.isAuthenticated}',
      );
    }
  }

  /// Refresh authentication state - call when auth changes
  /// This ensures radio uses updated auth cookies
  void refreshAuthState() {
    if (_innerTubeService != null) {
      if (kDebugMode) {
        print(
          'AudioPlayerService: Auth refreshed, authenticated=${_innerTubeService!.isAuthenticated}',
        );
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

  /// ConcatenatingAudioSource for gapless playback
  /// This allows pre-buffering next tracks for instant skip
  // ignore: unused_field - retained for optional gapless rebuild strategy
  ConcatenatingAudioSource? _playlist;

  /// Map of videoId to index in playlist (for fast lookup)
  final Map<String, int> _playlistIndexMap = {};

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
  AudioQuality _audioQuality = AudioQuality.auto;
  bool _streamCacheWifiOnly = false;
  int _streamCacheSizeLimitMb = kDefaultStreamCacheSizeLimitMb;
  int _streamCacheMaxConcurrent = kDefaultStreamCacheMaxConcurrent;
  int _crossfadeDurationMs = kDefaultCrossfadeDurationMs;
  String?
  _queueSourceId; // Track which playlist/album/artist started this queue
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

  Future<({AudioSource source, PlaybackData? playbackData})>
  _buildSourceForTrack(Track track) async {
    if (track.localFilePath != null) {
      final localFile = File(track.localFilePath!);
      if (await localFile.exists()) {
        final fileSize = await localFile.length();
        if (fileSize >= 10000) {
          return (
            source: AudioSource.uri(Uri.file(track.localFilePath!), tag: track),
            playbackData: null,
          );
        }
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
      _currentTrack = targetTrack;
      _currentPlaybackData = built.playbackData;
      _activeSourceQueueIndices = <int>[targetIndex];
      _activeSourcePlaybackDataByQueueIndex = built.playbackData == null
          ? const <int, PlaybackData>{}
          : <int, PlaybackData>{targetIndex: built.playbackData!};
      _crossfadeTriggeredForTrack = false;

      _updateState(
        currentTrack: _currentTrack,
        currentIndex: _currentIndex,
        currentPlaybackData: _currentPlaybackData,
        isLoading: false,
      );
      _saveQueueDebounced();
      _prefetchNextTrack();
      _scheduleLyricsPrefetchAroundCurrent();

      unawaited(incomingPlayer.play());
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
    } catch (e) {
      if (kDebugMode) {
        print(
          'AudioPlayerService: Crossfade failed, fallback to hard switch: $e',
        );
      }
      _player = outgoingPlayer;
      _currentIndex = targetIndex;
      _currentTrack = _queue[targetIndex];
      await _loadAndPlayCurrent();
    } finally {
      _isCrossfading = false;
    }
  }

  void _maybeTriggerAutoCrossfade(Duration currentPosition) {
    if (_crossfadeDurationMs <= 0) return;
    if (_isCrossfading) return;
    if (_crossfadeTriggeredForTrack) return;
    if (_loopMode == LoopMode.one) return;
    if (!_player.playing) return;

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
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'com.google.android.apps.youtube.music/7.16.53 (Linux; U; Android 14; Pixel 8) gzip',
    );
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
    if (kIsWeb) {
      return AudioSource.uri(streamUri, tag: track);
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
      return AudioSource.uri(streamUri, tag: track);
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
      return AudioSource.uri(streamUri, tag: track);
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
      return AudioSource.uri(streamUri, tag: track);
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
    return LockCachingAudioSource(streamUri, cacheFile: cacheFile, tag: track);
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

        if (track.localFilePath != null &&
            await File(track.localFilePath!).exists()) {
          if (kDebugMode) {
            print(
              'AudioPlayerService: Skipping pre-cache for ${track.id} (local file)',
            );
          }
          continue;
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

  /// Track if we're currently building the playlist (to avoid duplicate work)
  bool _isPreparingPlaylist = false;

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
    if (kDebugMode) {
      print(
        'AudioPlayerService: Jams mode ${enabled ? "enabled" : "disabled"}',
      );
    }

    // Clear the gapless playlist when enabling Jams mode
    // This ensures track completion events fire properly
    if (enabled) {
      _playlist = null;
      _playlistIndexMap.clear();
    }
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

  /// Buffered position stream
  Stream<Duration> get bufferedPositionStream =>
      _bufferedPositionController.stream;

  /// Current playback state
  PlaybackState get state => _stateController.value;

  /// Current position (real-time, not throttled)
  Duration get currentPosition => _player.position;

  /// Current track
  Track? get currentTrack => _currentTrack;

  /// Current queue
  List<Track> get queue => List.unmodifiable(_queue);

  /// Current index in queue
  int get currentIndex => _currentIndex;

  /// Current audio quality setting
  AudioQuality get audioQuality => _audioQuality;

  void _bindPlayerEventStreams(AudioPlayer player) {
    player.playerStateStream.listen((playerState) {
      if (!identical(player, _player)) return;
      _updateState(
        isPlaying: playerState.playing,
        isBuffering: playerState.processingState == ProcessingState.buffering,
        isLoading: playerState.processingState == ProcessingState.loading,
      );

      // Auto-play next track when current one completes.
      if (playerState.processingState == ProcessingState.completed) {
        _onTrackComplete();
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
      _saveQueueDebounced();
      _prefetchNextTrack();
      _scheduleLyricsPrefetchAroundCurrent();
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
      final didUpdateDuration =
          duration != null && _applyDurationToCurrentTrack(duration);
      _crossfadeTriggeredForTrack = false;
      _updateState(
        duration: duration,
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
        if (kDebugMode) {
          print('AudioPlayerService: Pre-fetching next track: ${nextTrack.id}');
        }

        // Fire and forget - just warm up the cache
        _ytPlayerUtils.prefetchNext(nextTrack.id, quality: _audioQuality);
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

      final ytService = YouTubeMusicService();
      final fetched = await ytService.getTrack(_currentTrack!.id);
      if (fetched == null || fetched.duration <= Duration.zero) return;

      final didUpdate = _applyDurationToCurrentTrack(fetched.duration);
      if (didUpdate) {
        _updateState(
          duration: fetched.duration,
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
    List<Track>? queue,
    int? currentIndex,
    bool? isPlaying,
    bool? isBuffering,
    bool? isLoading,
    Duration? position,
    Duration? bufferedPosition,
    Duration? duration,
    double? speed,
    LoopMode? loopMode,
    bool? shuffleEnabled,
    String? error,
    AudioQuality? audioQuality,
    PlaybackData? currentPlaybackData,
    int? queueRevision,
    String? queueSourceId,
    bool? isRadioMode,
    bool? isFetchingRadio,
    bool? streamCacheWifiOnly,
    int? streamCacheSizeLimitMb,
    int? streamCacheMaxConcurrent,
    int? crossfadeDurationMs,
  }) {
    final newState = _stateController.value.copyWith(
      currentTrack: currentTrack ?? _currentTrack,
      queue: queue ?? _queue,
      queueRevision: queueRevision, // Passed explicitly when queue changes
      currentIndex: currentIndex ?? _currentIndex,
      isPlaying: isPlaying,
      isBuffering: isBuffering,
      isLoading: isLoading,
      position: position,
      bufferedPosition: bufferedPosition,
      duration: duration,
      speed: speed,
      loopMode: loopMode ?? _loopMode,
      shuffleEnabled: shuffleEnabled ?? _shuffleEnabled,
      error: error,
      audioQuality: audioQuality ?? _audioQuality,
      currentPlaybackData: currentPlaybackData ?? _currentPlaybackData,
      queueSourceId: queueSourceId ?? _queueSourceId,
      isRadioMode: isRadioMode ?? _isRadioMode,
      isFetchingRadio: isFetchingRadio ?? _isFetchingRadio,
      streamCacheWifiOnly: streamCacheWifiOnly ?? _streamCacheWifiOnly,
      streamCacheSizeLimitMb: streamCacheSizeLimitMb ?? _streamCacheSizeLimitMb,
      streamCacheMaxConcurrent:
          streamCacheMaxConcurrent ?? _streamCacheMaxConcurrent,
      crossfadeDurationMs: crossfadeDurationMs ?? _crossfadeDurationMs,
    );

    // Only emit if state actually changed (using == that excludes position)
    // This prevents unnecessary widget rebuilds
    if (newState != _stateController.value) {
      _stateController.add(newState);
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
    await playQueue([track], startIndex: 0, isRadioQueue: false);
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
  Future<void> playQueue(
    List<Track> tracks, {
    int startIndex = 0,
    bool isRadioQueue = false,
    String? sourceId,
  }) async {
    if (kDebugMode) {
      print(
        'AudioPlayerService.playQueue: tracks=${tracks.length}, startIndex=$startIndex, isRadioQueue=$isRadioQueue, sourceId=$sourceId',
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

    // Track the source of this queue (playlist/album/artist ID)
    _queueSourceId = isRadioQueue ? _queueSourceId : sourceId;

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
      // Build playlist for gapless skip
      _buildPlaylistInBackground();
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

  /// Prefetch all tracks in queue (OuterTune approach)
  /// This resolves stream URLs in background
  void _prefetchAllTracks() {
    if (_queue.isEmpty) return;

    // Prefetch all tracks, but prioritize current and next
    final allIds = _queue.map((t) => t.id).toList();
    if (kDebugMode) {
      print('AudioPlayerService: Prefetching ${allIds.length} tracks');
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

  /// Build ConcatenatingAudioSource in background for gapless playback
  /// This is called AFTER current track starts playing
  Future<void> _buildPlaylistInBackground() async {
    if (_isPreparingPlaylist || _queue.isEmpty) return;

    // Don't build gapless playlist in Jams mode - we need to intercept track transitions
    if (_jamsModeEnabled) {
      if (kDebugMode) {
        print('AudioPlayerService: Skipping playlist build in Jams mode');
      }
      return;
    }

    _isPreparingPlaylist = true;

    try {
      if (kDebugMode) {
        print('AudioPlayerService: Building playlist for gapless playback...');
      }

      final sources = <AudioSource>[];
      _playlistIndexMap.clear();

      // Build sources for all tracks in queue
      // Process in chunks of 3 with delays to avoid UI jank
      for (int i = 0; i < _queue.length; i++) {
        // Yield to UI thread every 3 tracks with longer delay
        if (i % 3 == 0 && i > 0) {
          await Future.delayed(const Duration(milliseconds: 100));
        }

        final track = _queue[i];

        // Skip current track (already playing)
        if (i == _currentIndex) {
          // Still need placeholder for index mapping
          final currentData = _currentPlaybackData;
          if (currentData != null) {
            sources.add(
              await _streamingAudioSourceForTrack(track, currentData),
            );
            _playlistIndexMap[track.id] = i;
          } else if (track.localFilePath != null) {
            // Local file for current track - use Uri.file for proper file:// URI
            sources.add(
              AudioSource.uri(Uri.file(track.localFilePath!), tag: track),
            );
            _playlistIndexMap[track.id] = i;
          }
          continue;
        }

        // Check for local file first
        if (track.localFilePath != null &&
            await File(track.localFilePath!).exists()) {
          // Use Uri.file for proper file:// URI on Android
          sources.add(
            AudioSource.uri(Uri.file(track.localFilePath!), tag: track),
          );
          _playlistIndexMap[track.id] = sources.length - 1;
          continue;
        }

        // Get cached or fetch stream URL
        final result = await _ytPlayerUtils.playerResponseForPlayback(
          track.id,
          quality: _audioQuality,
        );

        if (result.isSuccess) {
          sources.add(await _streamingAudioSourceForTrack(track, result.data!));
          _playlistIndexMap[track.id] = sources.length - 1;
        }
      }

      if (sources.length > 1) {
        _playlist = ConcatenatingAudioSource(children: sources);
        if (kDebugMode) {
          print(
            'AudioPlayerService: Playlist ready with ${sources.length} tracks',
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('AudioPlayerService: Failed to build playlist: $e');
      }
    } finally {
      _isPreparingPlaylist = false;
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
      _schedulePrecacheAhead();
      _scheduleLyricsPrefetchAroundCurrent();
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
    if (newIndex < 0 || newIndex > _queue.length) return;
    if (oldIndex == newIndex) return;

    // Adjust for removal shift
    if (newIndex > oldIndex) newIndex--;

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
    _queue.clear();
    _originalQueue.clear();
    _currentIndex = -1;
    _currentTrack = null;
    _currentPlaybackData = null;
    _playlist = null;
    _playlistIndexMap.clear();
    _activeSourceQueueIndices = const [];
    _activeSourcePlaybackDataByQueueIndex = const <int, PlaybackData>{};
    _isCrossfading = false;
    _crossfadeTriggeredForTrack = false;
    stop();
    _queueRevision++;
    _updateState(
      queue: _queue,
      queueRevision: _queueRevision,
      currentIndex: _currentIndex,
      currentTrack: null,
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

    _crossfadeTriggeredForTrack = false;
    _currentTrack = _queue[_currentIndex];
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
      if (_currentTrack!.localFilePath != null) {
        final localFile = File(_currentTrack!.localFilePath!);
        if (await localFile.exists()) {
          final fileSize = await localFile.length();
          if (kDebugMode) {
            print(
              'AudioPlayerService: Playing local file: ${_currentTrack!.localFilePath} (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)',
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
            try {
              // Use Uri.file for proper file:// URI on Android
              final fileUri = Uri.file(_currentTrack!.localFilePath!);
              if (kDebugMode) {
                print('AudioPlayerService: Using file URI: $fileUri');
              }

              await _player.setAudioSource(
                AudioSource.uri(fileUri, tag: _currentTrack),
              );
              _activeSourceQueueIndices = <int>[_currentIndex];
              _activeSourcePlaybackDataByQueueIndex =
                  const <int, PlaybackData>{};
              if (_pendingSeekPosition != null &&
                  _pendingSeekTrackId == _currentTrack!.id) {
                await _player.seek(_pendingSeekPosition);
                _positionController.add(_pendingSeekPosition!);
                _updateState(position: _pendingSeekPosition);
                _pendingSeekPosition = null;
                _pendingSeekTrackId = null;
              }
              _player.play();
              _updateState(isLoading: false);
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
              'AudioPlayerService: Local file not found at: ${_currentTrack!.localFilePath}',
            );
          }
        }
      }

      // Check if URL is already cached (should be instant if prefetched)
      final hasCached = _ytPlayerUtils.hasCachedData(trackId);
      if (hasCached) {
        if (kDebugMode) {
          print('AudioPlayerService: URL already cached (prefetched)');
        }
      }

      // Get stream URL (from cache or fetch)
      final result = await _ytPlayerUtils.playerResponseForPlayback(
        trackId,
        quality: _audioQuality,
        isMetered: false,
      );

      final urlResolveTime = stopwatch.elapsedMilliseconds;
      if (kDebugMode) {
        print(
          'AudioPlayerService: URL resolve took ${urlResolveTime}ms (cached: $hasCached)',
        );
      }

      if (!result.isSuccess) {
        if (kDebugMode) {
          print(
            'AudioPlayerService: Failed to get stream URL: ${result.error}',
          );
        }
        _updateState(
          error: result.error ?? 'Could not get stream URL',
          isLoading: false,
        );
        return;
      }

      final playbackData = result.data!;
      _currentPlaybackData = playbackData;

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

      // Start playback immediately
      await _player.play();

      _updateState(isLoading: false, currentPlaybackData: playbackData);

      final totalTime = urlResolveTime + bufferTime;
      if (kDebugMode) {
        print('AudioPlayerService: Playing! Total time: ${totalTime}ms');
      }

      // Prefetch next track while current plays
      _prefetchNextTrack();
      unawaited(_enforceAudioCacheLimit());
    } catch (e) {
      unawaited(_player.setVolume(1.0));
      if (kDebugMode) {
        print('AudioPlayerService: Error: $e');
      }
      _updateState(error: e.toString(), isLoading: false);
    }
  }

  /// Prefetch next track in background (OuterTune approach)
  /// This is called after current track starts playing
  void _prefetchNextTrack() {
    if (_currentIndex < _queue.length - 1) {
      final nextTrack = _queue[_currentIndex + 1];
      if (kDebugMode) {
        print('AudioPlayerService: Prefetching next track: ${nextTrack.title}');
      }

      // Fire and forget - don't await
      _ytPlayerUtils.prefetchNext(nextTrack.id, quality: _audioQuality);
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
    }
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
    await _player.play();
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
    _bufferedPositionController.close();
    _ytPlayerUtils.dispose();
  }
}
