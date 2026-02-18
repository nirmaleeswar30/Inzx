import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/widgets.dart';
import '../audio_player_service.dart';
import '../../models/models.dart';
import 'jams_models.dart';
import 'jams_service_supabase.dart';

/// Controller that syncs audio playback with Jams session
/// Handles both host broadcasting and participant receiving
class JamsSyncController {
  final JamsService _jamsService;
  final AudioPlayerService _audioPlayer;

  StreamSubscription? _playbackSubscription;
  StreamSubscription? _audioStateSubscription;
  StreamSubscription? _hostRoleChangeSubscription;
  StreamSubscription? _permissionChangeSubscription;
  Timer? _syncTimer;

  // Flag to prevent broadcast loops when applying received state
  bool _isApplyingRemoteState = false;

  // Track when we last broadcasted - if recent, we're the "active controller"
  // and should ignore incoming broadcasts from others
  DateTime? _lastBroadcastTimestamp;
  static const _activeControllerWindowMs = 2000; // 2 seconds

  // Drift correction
  static const _maxDriftMs = 1000; // 1 second max drift before correction
  static const _syncIntervalMs = 3000; // Sync every 3 seconds as host

  JamsSyncController({
    required JamsService jamsService,
    required AudioPlayerService audioPlayer,
  }) : _jamsService = jamsService,
       _audioPlayer = audioPlayer {
    WidgetsBinding.instance.addObserver(_lifecycleObserver);

    // Listen for host role changes to restart sync
    _hostRoleChangeSubscription = _jamsService.hostRoleChangeStream.listen((
      isNowHost,
    ) async {
      if (kDebugMode) {
        print(
          'JamsSyncController: Host role changed, isNowHost=$isNowHost - restarting sync',
        );
      }
      stopSync();
      startSync();

      // If becoming host, fetch radio if jam queue is low
      if (isNowHost) {
        // First append any local queue tracks
        await appendPlayerQueueToJam();
        // Then check if we need more tracks from radio
        _checkAndFetchJamRadio();
      }
    });

    // Listen for permission changes to enable/disable broadcasting for participant
    _permissionChangeSubscription = _jamsService.permissionChangeStream.listen((
      hasPermission,
    ) {
      if (kDebugMode) {
        print(
          'JamsSyncController: Permission changed, hasPermission=$hasPermission - restarting sync',
        );
      }
      stopSync();
      startSync();
    });
  }

  StreamSubscription? _trackCompleteSubscription;
  late final WidgetsBindingObserver _lifecycleObserver = _JamsLifecycleObserver(
    onStateChanged: (state) {
      if (!_jamsService.isInSession) return;

      if (state == AppLifecycleState.resumed) {
        if (kDebugMode) {
          print('JamsSyncController: App resumed, requesting state sync');
        }
        unawaited(_jamsService.requestStateSync(reason: 'app_resumed'));
        unawaited(_jamsService.keepAlive(reason: 'app_resumed'));
      } else if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.inactive) {
        if (kDebugMode) {
          print('JamsSyncController: App backgrounded, sending keepalive');
        }
        unawaited(_jamsService.keepAlive(reason: 'app_backgrounded'));
      }
    },
  );

  /// Start syncing - call when joining/creating a session
  void startSync() {
    if (kDebugMode) {
      print('JamsSyncController: Starting sync, isHost=${_jamsService.isHost}');
    }

    // Enable Jams mode on audio player (disables auto-skip behavior)
    _audioPlayer.setJamsMode(true);

    // Listen for track completion to play next from jam queue
    _trackCompleteSubscription = _audioPlayer.trackCompleteStream.listen((
      track,
    ) {
      if (kDebugMode) {
        print('JamsSyncController: Track completed: ${track.title}');
      }
      _onTrackComplete();
    });

    if (_jamsService.isHost) {
      _startHostSync();
    } else {
      _startParticipantSync();
    }
  }

  /// Stop syncing - call when leaving session
  void stopSync() {
    if (kDebugMode) {
      print('JamsSyncController: Stopping sync');
    }
    _playbackSubscription?.cancel();
    _playbackSubscription = null;
    _audioStateSubscription?.cancel();
    _audioStateSubscription = null;
    _syncTimer?.cancel();
    _syncTimer = null;
    _trackCompleteSubscription?.cancel();
    _trackCompleteSubscription = null;

    // Disable Jams mode on audio player
    _audioPlayer.setJamsMode(false);
  }

  // Jam queue radio fetch state
  static const _jamQueueLowThreshold =
      3; // Fetch more when 3 or fewer tracks remain
  bool _isFetchingJamRadio = false;

  /// Handle track completion - play next from jam queue
  Future<void> _onTrackComplete() async {
    // Only host (or participant with control) should handle this
    if (!_jamsService.canControlPlayback) {
      if (kDebugMode) {
        print('JamsSyncController: No control permission, waiting for sync');
      }
      return;
    }

    // Get next track from jam queue
    final nextItem = await _jamsService.popNextFromQueue();
    if (nextItem == null) {
      if (kDebugMode) {
        print('JamsSyncController: Jam queue empty, fetching radio...');
      }
      // Queue empty - fetch radio tracks from current track
      await _fetchRadioForJamQueue();
      // Try again after fetch
      final retryItem = await _jamsService.popNextFromQueue();
      if (retryItem != null) {
        await _playJamQueueItem(retryItem);
      }
      return;
    }

    await _playJamQueueItem(nextItem);

    // Check if jam queue is getting low - fetch more in background
    _checkAndFetchJamRadio();
  }

  /// Play a JamQueueItem
  Future<void> _playJamQueueItem(JamQueueItem item) async {
    if (kDebugMode) {
      print(
        'JamsSyncController: Playing next from jam queue: ${item.track.title}',
      );
    }

    // Convert JamTrack to Track and play
    final track = Track(
      id: item.track.videoId,
      title: item.track.title,
      artist: item.track.artist,
      thumbnailUrl: item.track.thumbnailUrl ?? '',
      duration: Duration(milliseconds: item.track.durationMs),
    );

    await _audioPlayer.playTrack(track);
  }

  /// Check jam queue level and fetch radio tracks if low
  void _checkAndFetchJamRadio() {
    if (!_jamsService.isHost) return; // Only host fetches radio for jam
    if (_isFetchingJamRadio) return;

    final jamQueue = _jamsService.jamQueue;
    if (jamQueue.length <= _jamQueueLowThreshold) {
      if (kDebugMode) {
        print(
          'JamsSyncController: Jam queue low (${jamQueue.length}), fetching more radio...',
        );
      }
      _fetchRadioForJamQueue();
    }
  }

  /// Fetch radio tracks based on current playing track and add to jam queue
  Future<void> _fetchRadioForJamQueue() async {
    if (_isFetchingJamRadio) return;
    if (!_jamsService.isHost) return; // Only host can add to jam queue

    final currentTrack = _audioPlayer.currentTrack;
    if (currentTrack == null) return;

    _isFetchingJamRadio = true;

    try {
      if (kDebugMode) {
        print(
          'JamsSyncController: Fetching radio for jam queue based on ${currentTrack.title}',
        );
      }

      // Use audio player's radio fetch capability
      // Get current player queue which has radio tracks
      final playerQueue = _audioPlayer.state.queue;
      final currentIndex = _audioPlayer.state.currentIndex;

      // Get tracks after current that aren't already in jam queue
      final existingJamIds = _jamsService.jamQueue
          .map((i) => i.track.videoId)
          .toSet();
      existingJamIds.add(currentTrack.id); // Don't add current track

      final upNextTracks = playerQueue
          .skip(currentIndex + 1)
          .where((t) => !existingJamIds.contains(t.id))
          .take(10) // Add up to 10 tracks at a time
          .toList();

      if (upNextTracks.isEmpty) {
        if (kDebugMode) {
          print('JamsSyncController: No new radio tracks to add to jam queue');
        }
        return;
      }

      // Convert to JamQueueItems
      final jamItems = upNextTracks
          .map(
            (track) => JamQueueItem(
              track: JamTrack(
                videoId: track.id,
                title: track.title,
                artist: track.artist,
                thumbnailUrl: track.thumbnailUrl,
                durationMs: track.duration.inMilliseconds,
              ),
              addedBy: _jamsService.oderId,
              addedAt: DateTime.now(),
            ),
          )
          .toList();

      await _jamsService.appendHostQueue(jamItems);
      if (kDebugMode) {
        print(
          'JamsSyncController: Added ${jamItems.length} radio tracks to jam queue',
        );
      }
    } finally {
      _isFetchingJamRadio = false;
    }
  }

  /// Initialize jam queue from current player queue (host only)
  /// Call this after creating a session
  Future<void> initializeJamQueueFromPlayer() async {
    if (!_jamsService.isHost) {
      if (kDebugMode) {
        print('JamsSyncController: Not host, cannot initialize queue');
      }
      return;
    }

    final playerQueue = _audioPlayer.state.queue;
    final currentIndex = _audioPlayer.state.currentIndex;

    // Get tracks after current (the "up next" tracks)
    final upNextTracks = playerQueue.skip(currentIndex + 1).toList();

    if (upNextTracks.isEmpty) {
      if (kDebugMode) {
        print('JamsSyncController: No tracks in queue to add to jam');
      }
      return;
    }

    // Convert to JamQueueItems
    final jamItems = upNextTracks
        .map(
          (track) => JamQueueItem(
            track: JamTrack(
              videoId: track.id,
              title: track.title,
              artist: track.artist,
              thumbnailUrl: track.thumbnailUrl,
              durationMs: track.duration.inMilliseconds,
            ),
            addedBy: _jamsService.oderId,
            addedAt: DateTime.now(),
          ),
        )
        .toList();

    await _jamsService.initializeJamQueue(jamItems);
    if (kDebugMode) {
      print(
        'JamsSyncController: Initialized jam queue with ${jamItems.length} tracks',
      );
    }
  }

  /// Append current player queue to jam queue (for new host after transfer)
  Future<void> appendPlayerQueueToJam() async {
    if (!_jamsService.isHost) {
      if (kDebugMode) {
        print('JamsSyncController: Not host, cannot append queue');
      }
      return;
    }

    final playerQueue = _audioPlayer.state.queue;
    final currentIndex = _audioPlayer.state.currentIndex;

    // Get tracks after current
    final upNextTracks = playerQueue.skip(currentIndex + 1).toList();

    if (upNextTracks.isEmpty) {
      if (kDebugMode) {
        print('JamsSyncController: No tracks in queue to append to jam');
      }
      return;
    }

    // Convert to JamQueueItems
    final jamItems = upNextTracks
        .map(
          (track) => JamQueueItem(
            track: JamTrack(
              videoId: track.id,
              title: track.title,
              artist: track.artist,
              thumbnailUrl: track.thumbnailUrl,
              durationMs: track.duration.inMilliseconds,
            ),
            addedBy: _jamsService.oderId,
            addedAt: DateTime.now(),
          ),
        )
        .toList();

    await _jamsService.appendHostQueue(jamItems);
    if (kDebugMode) {
      print(
        'JamsSyncController: Appended ${jamItems.length} tracks to jam queue',
      );
    }
  }

  /// Populate jam queue from player queue if jam queue is empty
  /// This handles the case where host creates jam first, then plays music
  Future<void> _populateJamQueueIfEmpty() async {
    if (!_jamsService.isHost) return;

    // Check if jam queue is already populated
    final jamQueue = _jamsService.jamQueue;
    if (jamQueue.isNotEmpty) {
      if (kDebugMode) {
        print(
          'JamsSyncController: Jam queue already has ${jamQueue.length} tracks',
        );
      }
      return;
    }

    // Jam queue is empty, populate from player queue
    await initializeJamQueueFromPlayer();
  }

  // ============ Host Sync ============

  // Throttling state for host
  DateTime? _lastBroadcastTime;
  int? _lastBroadcastPositionMs;
  bool? _lastBroadcastIsPlaying;
  String? _lastBroadcastTrackId;
  int _lastKnownQueueRevision = 0;

  void _startHostSync() {
    // Also listen to broadcasts from other controllers (for "last controller wins")
    _playbackSubscription = _jamsService.playbackStream.listen((playback) {
      if (kDebugMode) {
        print(
          'JamsSyncController: [HOST] Received playback from other controller',
        );
      }
      _applyPlaybackState(playback);
    });

    // Broadcast playback state when it changes (with throttling)
    _audioStateSubscription = _audioPlayer.stateStream.listen((state) {
      _throttledBroadcast(state);

      // Check if queue grew (radio tracks added) and jam queue is empty
      if (state.queueRevision != _lastKnownQueueRevision) {
        _lastKnownQueueRevision = state.queueRevision;
        // Try to populate jam queue when player queue grows
        if (_jamsService.jamQueue.isEmpty && state.queue.length > 1) {
          if (kDebugMode) {
            print(
              'JamsSyncController: Queue grew to ${state.queue.length}, populating jam queue',
            );
          }
          _populateJamQueueIfEmpty();
        }
      }
    });

    // Periodic sync for drift correction
    _syncTimer = Timer.periodic(
      const Duration(milliseconds: _syncIntervalMs),
      (_) => _periodicSync(),
    );
  }

  /// Throttled broadcast - only send if:
  /// 1. Track changed
  /// 2. Play/pause state changed
  /// 3. Position drifted more than _maxDriftMs
  /// 4. Periodic interval passed
  void _throttledBroadcast(PlaybackState state) {
    // Skip if we're applying remote state (prevents echo loops)
    if (_isApplyingRemoteState) return;

    final track = state.currentTrack;
    if (track == null) return;

    final now = DateTime.now();
    // Use currentPosition which gets real-time position from player
    final currentPositionMs = _audioPlayer.currentPosition.inMilliseconds;

    // Always broadcast if track changed
    if (_lastBroadcastTrackId != track.id) {
      _doBroadcast(state, 'track changed');

      // If jam queue is empty and host starts playing, populate it from player queue
      _populateJamQueueIfEmpty();
      return;
    }

    // Always broadcast if play/pause state changed
    if (_lastBroadcastIsPlaying != state.isPlaying) {
      _doBroadcast(state, 'play/pause changed');
      return;
    }

    // Broadcast if position drifted significantly (indicates seek)
    if (_lastBroadcastPositionMs != null) {
      final expectedPosition = state.isPlaying
          ? _lastBroadcastPositionMs! +
                (now.difference(_lastBroadcastTime!).inMilliseconds)
          : _lastBroadcastPositionMs!;
      final drift = (currentPositionMs - expectedPosition).abs();

      if (drift > _maxDriftMs) {
        _doBroadcast(state, 'seek detected (drift: ${drift}ms)');
        return;
      }
    }

    // Otherwise, throttle - rely on periodic sync
  }

  void _doBroadcast(PlaybackState state, String reason) async {
    final track = state.currentTrack;
    if (track == null) return;

    // Use currentPosition for real-time accuracy
    final positionMs = _audioPlayer.currentPosition.inMilliseconds;
    _lastBroadcastTime = DateTime.now();
    _lastBroadcastTimestamp = DateTime.now(); // Track when we last broadcasted
    _lastBroadcastPositionMs = positionMs;
    _lastBroadcastIsPlaying = state.isPlaying;
    _lastBroadcastTrackId = track.id;

    final roleLabel = _jamsService.isHost ? 'HOST' : 'CONTROLLER';
    if (kDebugMode) {
      print(
        'JamsSyncController: [$roleLabel] Broadcasting ($reason) - isPlaying=${state.isPlaying}, position=${positionMs}ms',
      );
    }

    try {
      await _jamsService.syncPlayback(
        videoId: track.id,
        title: track.title,
        artist: track.artist,
        thumbnailUrl: track.thumbnailUrl,
        durationMs: track.duration.inMilliseconds,
        positionMs:
            positionMs, // Use the real-time position we already calculated
        isPlaying: state.isPlaying,
      );
    } catch (e) {
      if (kDebugMode) {
        print('JamsSyncController: Broadcast error: $e');
      }
    }
  }

  void _periodicSync() {
    // Skip periodic sync if we're currently applying remote state
    if (_isApplyingRemoteState) return;

    final state = _audioPlayer.state;
    if (state.currentTrack != null) {
      _doBroadcast(state, 'periodic sync');
    }

    // Periodically check if jam queue needs more tracks
    _checkAndFetchJamRadio();
  }

  // ============ Participant Sync ============

  // Track last received state to avoid redundant processing
  bool? _lastReceivedIsPlaying;
  int? _lastReceivedPositionMs;
  DateTime?
  _lastReceivedTime; // When WE received the last broadcast (local time)
  bool _isLoadingTrack = false; // Separate flag for track loading

  void _startParticipantSync() {
    if (kDebugMode) {
      print(
        'JamsSyncController: Starting participant sync - listening to playback stream',
      );
    }
    _playbackSubscription = _jamsService.playbackStream.listen((playback) {
      if (kDebugMode) {
        print(
          'JamsSyncController: [PARTICIPANT] Received playback from stream',
        );
      }
      _applyPlaybackState(playback);
    });

    // If participant has control permission, also broadcast like host
    if (_jamsService.canControlPlayback) {
      if (kDebugMode) {
        print(
          'JamsSyncController: [PARTICIPANT] Has control permission - also broadcasting',
        );
      }
      _startParticipantBroadcast();
    }
  }

  /// Start broadcasting for participants with permission
  /// Similar to host but checks _isApplyingRemoteState to prevent loops
  void _startParticipantBroadcast() {
    _audioStateSubscription = _audioPlayer.stateStream.listen((state) {
      // Don't broadcast if we're currently applying remote state (prevents loops)
      if (_isApplyingRemoteState) return;
      _throttledBroadcast(state);
    });

    // Periodic sync for drift correction
    _syncTimer = Timer.periodic(const Duration(milliseconds: _syncIntervalMs), (
      _,
    ) {
      if (!_isApplyingRemoteState) {
        _periodicSync();
      }
    });
  }

  Future<void> _applyPlaybackState(JamPlaybackState playback) async {
    // If we have control permission and recently broadcasted, we're the "active controller"
    // Ignore incoming broadcasts to prevent conflicts
    if (_jamsService.canControlPlayback && _lastBroadcastTimestamp != null) {
      final timeSinceBroadcast = DateTime.now()
          .difference(_lastBroadcastTimestamp!)
          .inMilliseconds;
      if (timeSinceBroadcast < _activeControllerWindowMs) {
        if (kDebugMode) {
          print(
            'JamsSyncController: [CONTROLLER] Ignoring broadcast - we are active controller (${timeSinceBroadcast}ms since our last broadcast)',
          );
        }
        return;
      }
    }

    if (kDebugMode) {
      print(
        'JamsSyncController: [PARTICIPANT] _applyPlaybackState called, isPlaying=${playback.isPlaying}, position=${playback.positionMs}ms',
      );
    }

    // Set flag to prevent broadcast loops while applying remote state
    _isApplyingRemoteState = true;

    try {
      await _doApplyPlaybackState(playback);

      // Update our "last broadcast" state to match what we received
      // This prevents the throttling logic from immediately re-broadcasting
      if (playback.currentTrack != null) {
        _lastBroadcastTrackId = playback.currentTrack!.videoId;
        _lastBroadcastIsPlaying = playback.isPlaying;
        _lastBroadcastPositionMs = playback.positionMs;
        _lastBroadcastTime = DateTime.now();
      }
    } finally {
      // Longer delay before allowing broadcasts again to prevent immediate re-broadcast
      Future.delayed(const Duration(milliseconds: 500), () {
        _isApplyingRemoteState = false;
      });
    }
  }

  Future<void> _doApplyPlaybackState(JamPlaybackState playback) async {
    // Skip if we're currently loading a track (but allow play/pause sync)
    final hostTrack = playback.currentTrack;
    if (hostTrack == null) {
      if (kDebugMode) {
        print('JamsSyncController: [PARTICIPANT] No host track, skipping');
      }
      return;
    }

    final currentState = _audioPlayer.state;
    final currentTrack = currentState.currentTrack;

    if (kDebugMode) {
      print(
        'JamsSyncController: [PARTICIPANT] Current: isPlaying=${currentState.isPlaying}, track=${currentTrack?.title ?? "none"}',
      );
    }
    if (kDebugMode) {
      print(
        'JamsSyncController: [PARTICIPANT] Host: isPlaying=${playback.isPlaying}, track=${hostTrack.title}',
      );
    }

    // Calculate expected position accounting for time since sync
    final now = DateTime.now();
    final timeSinceSync = now.difference(playback.syncedAt).inMilliseconds;
    final hostExpectedPosition = playback.isPlaying
        ? playback.positionMs + timeSinceSync
        : playback.positionMs;

    // Check if host actually SEEKED (user action, not just normal playback progression)
    // Compare the new broadcast position with where we'd expect it to be
    // based on the PREVIOUS broadcast position + time elapsed since WE received it
    bool hostDidSeek = false;
    if (_lastReceivedPositionMs != null && _lastReceivedTime != null) {
      final timeSinceLastReceived = now
          .difference(_lastReceivedTime!)
          .inMilliseconds;
      final expectedFromLastReceived = _lastReceivedIsPlaying == true
          ? _lastReceivedPositionMs! + timeSinceLastReceived
          : _lastReceivedPositionMs!;
      // If the new position differs significantly from expected progression, it's a seek
      final seekDrift = (playback.positionMs - expectedFromLastReceived).abs();
      hostDidSeek = seekDrift > _maxDriftMs;

      // Debug: only log if something interesting
      if (hostDidSeek) {
        if (kDebugMode) {
          print(
            'JamsSyncController: [PARTICIPANT] Detected host seek: expected=$expectedFromLastReceived, got=${playback.positionMs}, drift=$seekDrift',
          );
        }
      }
    }

    // Update tracking - use NOW as when we received this broadcast
    _lastReceivedIsPlaying = playback.isPlaying;
    _lastReceivedPositionMs = playback.positionMs;
    _lastReceivedTime = now;

    // Handle track change - load in background, don't block other sync
    if (currentTrack?.id != hostTrack.videoId) {
      if (_isLoadingTrack) {
        if (kDebugMode) {
          print(
            'JamsSyncController: [PARTICIPANT] Already loading track, skipping',
          );
        }
        return;
      }
      if (kDebugMode) {
        print(
          'JamsSyncController: [PARTICIPANT] Switching to host track: ${hostTrack.title}',
        );
      }
      _isLoadingTrack = true;
      // Fire and forget - don't await, let it load in background
      _playTrackFromJam(
        hostTrack,
        hostExpectedPosition,
        playback.isPlaying,
      ).whenComplete(() => _isLoadingTrack = false);
      return;
    }

    // Skip play/pause/seek sync while track is loading
    if (_isLoadingTrack) {
      if (kDebugMode) {
        print(
          'JamsSyncController: [PARTICIPANT] Track still loading, skipping sync',
        );
      }
      return;
    }

    // Handle play/pause - compare with CURRENT PLAYER STATE
    final needsPlay = playback.isPlaying && !currentState.isPlaying;
    final needsPause = !playback.isPlaying && currentState.isPlaying;

    if (needsPlay) {
      if (kDebugMode) {
        print('JamsSyncController: [PARTICIPANT] Syncing: PLAY');
      }
      await _audioPlayer.play();
      return;
    }

    if (needsPause) {
      if (kDebugMode) {
        print('JamsSyncController: [PARTICIPANT] Syncing: PAUSE');
      }
      await _audioPlayer.pause();
      return;
    }

    // Handle seek (only if host actually seeked - user action, not normal playback)
    if (hostDidSeek) {
      if (kDebugMode) {
        print(
          'JamsSyncController: [PARTICIPANT] Host seeked to ${playback.positionMs}ms, seeking to $hostExpectedPosition',
        );
      }
      await _audioPlayer.seek(Duration(milliseconds: hostExpectedPosition));
      return;
    }

    // Drift correction - only if both playing and drift is significant
    // Use a larger threshold to avoid constant micro-corrections
    if (playback.isPlaying && currentState.isPlaying) {
      final currentPosition = _audioPlayer.currentPosition.inMilliseconds;
      final drift = (currentPosition - hostExpectedPosition).abs();

      // Only correct if drift is more than 2 seconds (avoid audio glitches for small drifts)
      if (drift > 2000) {
        if (kDebugMode) {
          print(
            'JamsSyncController: [PARTICIPANT] Drift correction: ${drift}ms, seeking to $hostExpectedPosition',
          );
        }
        await _audioPlayer.seek(Duration(milliseconds: hostExpectedPosition));
      }
    }
  }

  Future<void> _playTrackFromJam(
    JamTrack track,
    int positionMs,
    bool shouldPlay,
  ) async {
    // Create a Track object from JamTrack
    final audioTrack = Track(
      id: track.videoId,
      title: track.title,
      artist: track.artist,
      thumbnailUrl: track.thumbnailUrl,
      duration: Duration(milliseconds: track.durationMs),
    );

    // Play the track
    await _audioPlayer.playTrack(audioTrack);

    // Wait a bit for player to initialize
    await Future.delayed(const Duration(milliseconds: 500));

    // Seek to position
    if (positionMs > 1000) {
      await _audioPlayer.seek(Duration(milliseconds: positionMs));
    }

    // Match play/pause state
    if (!shouldPlay) {
      await _audioPlayer.pause();
    }
  }

  /// Dispose resources
  void dispose() {
    stopSync();
    _hostRoleChangeSubscription?.cancel();
    _hostRoleChangeSubscription = null;
    _permissionChangeSubscription?.cancel();
    _permissionChangeSubscription = null;
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
  }
}

class _JamsLifecycleObserver with WidgetsBindingObserver {
  final void Function(AppLifecycleState state) onStateChanged;

  _JamsLifecycleObserver({required this.onStateChanged});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onStateChanged(state);
  }
}
