import 'package:flutter/foundation.dart' show kDebugMode;
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import 'playback/playback.dart';
import 'ytmusic_api_service.dart';

/// Key for persisting streaming quality preference
const String kStreamingQualityKey = 'streaming_quality';

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
        other.isFetchingRadio == isFetchingRadio;
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

  /// The underlying audio player (ExoPlayer on Android)
  final AudioPlayer _player = AudioPlayer();

  /// OuterTune-style playback resolver
  final YTPlayerUtils _ytPlayerUtils = YTPlayerUtils.instance;

  /// ConcatenatingAudioSource for gapless playback
  /// This allows pre-buffering next tracks for instant skip
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
  Track? _currentTrack;
  PlaybackData? _currentPlaybackData;
  AudioQuality _audioQuality = AudioQuality.auto;
  String?
  _queueSourceId; // Track which playlist/album/artist started this queue

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

  void _init() {
    // Listen to player state changes
    _player.playerStateStream.listen((playerState) {
      _updateState(
        isPlaying: playerState.playing,
        isBuffering: playerState.processingState == ProcessingState.buffering,
        isLoading: playerState.processingState == ProcessingState.loading,
      );

      // Auto-play next track when current one completes
      if (playerState.processingState == ProcessingState.completed) {
        _onTrackComplete();
      }
    });

    // Listen to position changes - THROTTLED to avoid UI jank
    _player.positionStream.listen((position) {
      // Always update the dedicated position stream (for progress bars)
      _positionController.add(position);

      // Throttle full state updates to reduce rebuilds
      final now = DateTime.now();
      if (_lastPositionUpdate == null ||
          now.difference(_lastPositionUpdate!) >= _positionUpdateInterval) {
        _lastPositionUpdate = now;
        // Only update position in state occasionally (for other uses)
        _updateState(position: position);

        // Check if we need more radio tracks (every 500ms when playing)
        if (_isRadioMode && !_isFetchingRadio) {
          _checkAndFetchRadioTracks();
        }
      }

      // Pre-fetch next track when nearing end (check only once)
      _prefetchNextTrackIfNeeded(position);
    });

    // Listen to buffered position changes - use separate stream
    _player.bufferedPositionStream.listen((bufferedPosition) {
      _bufferedPositionController.add(bufferedPosition);
      // Don't call _updateState here - too frequent
    });

    // Listen to duration changes
    _player.durationStream.listen((duration) {
      _updateState(duration: duration);
      // Reset prefetch flag for new track
      _prefetchTriggered = false;
    });

    // Listen to errors
    _player.playbackEventStream.listen(
      (event) {},
      onError: (Object e, StackTrace st) {
        if (kDebugMode) {
          print('AudioPlayerService: Playback error: $e');
        }
        _handlePlaybackError(e);
      },
    );
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
      }
    }
  }

  /// Handle playback errors with fallback
  void _handlePlaybackError(Object error) {
    if (kDebugMode) {
      print('AudioPlayerService: Handling error: $error');
    }

    // Clear cache for current track and retry once
    if (_currentTrack != null) {
      _ytPlayerUtils.clearCache(_currentTrack!.id);

      // Could implement retry logic here
      _updateState(error: 'Playback error: ${error.toString()}');
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
      loopMode: loopMode ?? _player.loopMode,
      shuffleEnabled: shuffleEnabled ?? _shuffleEnabled,
      error: error,
      audioQuality: audioQuality ?? _audioQuality,
      currentPlaybackData: currentPlaybackData ?? _currentPlaybackData,
      queueSourceId: queueSourceId ?? _queueSourceId,
      isRadioMode: isRadioMode ?? _isRadioMode,
      isFetchingRadio: isFetchingRadio ?? _isFetchingRadio,
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
              AudioSource.uri(Uri.parse(currentData.streamUrl), tag: track),
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
          sources.add(
            AudioSource.uri(Uri.parse(result.data!.streamUrl), tag: track),
          );
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

    // Prefetch newly added tracks
    if (tracks.isNotEmpty) {
      _ytPlayerUtils.prefetch(
        tracks.map((t) => t.id).toList(),
        quality: _audioQuality,
      );
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

    // Prefetch the track that will play next
    _ytPlayerUtils.prefetchNext(track.id, quality: _audioQuality);
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
  }

  /// Jump to specific index in queue
  void skipToIndex(int index) {
    if (index < 0 || index >= _queue.length) return;
    if (index == _currentIndex) return;

    _currentIndex = index;
    _currentTrack = _queue[index];
    _loadAndPlayCurrent();
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
    stop();
    _queueRevision++;
    _updateState(
      queue: _queue,
      queueRevision: _queueRevision,
      currentIndex: _currentIndex,
      currentTrack: null,
    );
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

    _currentTrack = _queue[_currentIndex];
    _currentPlaybackData = null;

    // Show loading state immediately
    _updateState(
      currentTrack: _currentTrack,
      currentIndex: _currentIndex,
      isLoading: true,
      error: null,
      currentPlaybackData: null,
    );

    try {
      final trackId = _currentTrack!.id;
      final stopwatch = Stopwatch()..start();

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
                'AudioPlayerService: Local file too small (${fileSize} bytes), likely corrupted. Falling back to stream.',
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
              _player.play();
              _updateState(isLoading: false);
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

      await _player.setAudioSource(
        AudioSource.uri(Uri.parse(playbackData.streamUrl), tag: _currentTrack),
        // Pre-buffer ahead for smoother playback
        preload: true,
      );

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
    } catch (e) {
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

    switch (_player.loopMode) {
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
    await _player.stop();
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
    } else if (_player.loopMode == LoopMode.all) {
      newIndex = 0;
    } else {
      return;
    }

    _currentIndex = newIndex;

    // If playlist is ready and has the track, use it for instant skip
    // This avoids calling setAudioSource() which requires HTTP buffering
    if (_playlist != null &&
        _playlistIndexMap.containsKey(_queue[newIndex].id)) {
      final playlistIndex = _playlistIndexMap[_queue[newIndex].id]!;
      if (kDebugMode) {
        print(
          'AudioPlayerService: Instant skip using playlist (index $playlistIndex)',
        );
      }

      // Update state immediately
      _currentTrack = _queue[newIndex];
      _updateState(
        currentTrack: _currentTrack,
        currentIndex: _currentIndex,
        isLoading: false,
      );

      // Seek to the track in the concatenating source
      // Note: This requires the playlist to be set as the audio source
      // For now, fall back to _loadAndPlayCurrent
      await _loadAndPlayCurrent();
    } else {
      // Fall back to regular loading
      await _loadAndPlayCurrent();
    }
  }

  /// Skip to previous track
  Future<void> skipToPrevious() async {
    if (_queue.isEmpty) return;

    // If more than 3 seconds in, restart current track
    if (_player.position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }

    if (_currentIndex > 0) {
      _currentIndex--;
    } else if (_player.loopMode == LoopMode.all) {
      _currentIndex = _queue.length - 1;
    } else {
      await seek(Duration.zero);
      return;
    }

    await _loadAndPlayCurrent();
  }

  /// Set loop mode
  Future<void> setLoopMode(LoopMode mode) async {
    await _player.setLoopMode(mode);
    _updateState(loopMode: mode);
  }

  /// Cycle through loop modes
  Future<void> cycleLoopMode() async {
    final modes = [LoopMode.off, LoopMode.all, LoopMode.one];
    final currentModeIndex = modes.indexOf(_player.loopMode);
    final nextMode = modes[(currentModeIndex + 1) % modes.length];
    await setLoopMode(nextMode);
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

  /// Dispose resources
  void dispose() {
    _player.dispose();
    _stateController.close();
    _positionController.close();
    _bufferedPositionController.close();
    _ytPlayerUtils.dispose();
  }
}
