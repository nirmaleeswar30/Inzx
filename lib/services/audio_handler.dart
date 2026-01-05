import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../models/models.dart';
import 'audio_player_service.dart' as player;
import 'playback/playback.dart';

/// Audio handler for background playback and media controls
///
/// This is the Android MediaLibraryService equivalent.
/// It runs independently of UI lifecycle and handles:
/// - Background playback
/// - Notification controls
/// - Media session integration
/// - Audio focus management
///
/// Based on OuterTune's MusicService architecture.
class InzxAudioHandler extends BaseAudioHandler with SeekHandler {
  final player.AudioPlayerService _playerService = player.AudioPlayerService();
  StreamSubscription<player.PlaybackState>? _stateSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _bufferedPositionSubscription;
  String? _lastTrackId;
  int? _lastQueueLength;

  // Current position for system updates (not from stateStream)
  Duration _currentPosition = Duration.zero;
  Duration _bufferedPosition = Duration.zero;

  InzxAudioHandler() {
    _init();
  }

  void _init() {
    // Listen to player service state for track/play state changes
    // Position is handled separately via positionStream
    _stateSubscription = _playerService.stateStream.listen((state) {
      // Update playback state with current position values
      _updatePlaybackState(state);

      // Only update media item when track changes
      if (state.currentTrack?.id != _lastTrackId) {
        _lastTrackId = state.currentTrack?.id;
        _updateMediaItem(state.currentTrack);
      }

      // Only update queue when it changes
      if (state.queue.length != _lastQueueLength) {
        _lastQueueLength = state.queue.length;
        _updateQueue(state.queue);
      }
    });

    // Separate position stream for system UI updates (more frequent)
    _positionSubscription = _playerService.positionStream.listen((position) {
      _currentPosition = position;
      // Update just the position in playback state
      _updatePosition();
    });

    // Buffered position stream
    _bufferedPositionSubscription = _playerService.bufferedPositionStream
        .listen((bufferedPos) {
          _bufferedPosition = bufferedPos;
        });
  }

  void _updatePosition() {
    // Lightweight update for position only
    playbackState.add(
      playbackState.value.copyWith(
        updatePosition: _currentPosition,
        bufferedPosition: _bufferedPosition,
      ),
    );
  }

  void _updatePlaybackState(player.PlaybackState state) {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          state.isPlaying ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: _mapProcessingState(state),
        playing: state.isPlaying,
        updatePosition:
            _currentPosition, // Use tracked position, not state.position
        bufferedPosition: _bufferedPosition,
        speed: state.speed,
        queueIndex: state.currentIndex >= 0 ? state.currentIndex : null,
      ),
    );
  }

  AudioProcessingState _mapProcessingState(player.PlaybackState state) {
    if (state.error != null) return AudioProcessingState.error;
    if (state.isLoading) return AudioProcessingState.loading;
    if (state.isBuffering) return AudioProcessingState.buffering;
    if (state.currentTrack == null) return AudioProcessingState.idle;
    return AudioProcessingState.ready;
  }

  void _updateMediaItem(Track? track) {
    if (track == null) {
      mediaItem.add(null);
      return;
    }

    mediaItem.add(
      MediaItem(
        id: track.id,
        title: track.title,
        artist: track.artist,
        album: track.album ?? '',
        duration: track.duration,
        artUri: track.bestThumbnail != null
            ? Uri.parse(track.bestThumbnail!)
            : null,
      ),
    );
  }

  void _updateQueue(List<Track> tracks) {
    queue.add(
      tracks
          .map(
            (track) => MediaItem(
              id: track.id,
              title: track.title,
              artist: track.artist,
              album: track.album ?? '',
              duration: track.duration,
              artUri: track.bestThumbnail != null
                  ? Uri.parse(track.bestThumbnail!)
                  : null,
            ),
          )
          .toList(),
    );
  }

  @override
  Future<void> play() => _playerService.play();

  @override
  Future<void> pause() => _playerService.pause();

  @override
  Future<void> stop() async {
    await _playerService.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _playerService.seek(position);

  @override
  Future<void> skipToNext() => _playerService.skipToNext();

  @override
  Future<void> skipToPrevious() => _playerService.skipToPrevious();

  @override
  Future<void> skipToQueueItem(int index) async =>
      _playerService.skipToIndex(index);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final loopMode = switch (repeatMode) {
      AudioServiceRepeatMode.none => LoopMode.off,
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all => LoopMode.all,
      AudioServiceRepeatMode.group => LoopMode.all,
    };
    await _playerService.setLoopMode(loopMode);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final shouldShuffle = shuffleMode != AudioServiceShuffleMode.none;
    if (shouldShuffle != _playerService.state.shuffleEnabled) {
      await _playerService.toggleShuffle();
    }
  }

  @override
  Future<void> setSpeed(double speed) => _playerService.setSpeed(speed);

  @override
  Future<void> fastForward() =>
      _playerService.seekBy(const Duration(seconds: 10));

  @override
  Future<void> rewind() => _playerService.seekBy(const Duration(seconds: -10));

  /// Play a track
  Future<void> playTrack(Track track) => _playerService.playTrack(track);

  /// Play a queue
  Future<void> playQueue(List<Track> tracks, {int startIndex = 0}) =>
      _playerService.playQueue(tracks, startIndex: startIndex);

  /// Add to queue
  void addToQueue(List<Track> tracks) => _playerService.addToQueue(tracks);

  /// Play next
  void playNext(Track track) => _playerService.playNext(track);

  /// Get current state
  player.PlaybackState get currentState => _playerService.state;

  /// State stream
  Stream<player.PlaybackState> get stateStream => _playerService.stateStream;

  /// Toggle shuffle
  Future<void> toggleShuffle() => _playerService.toggleShuffle();

  /// Cycle loop mode
  Future<void> cycleLoopMode() => _playerService.cycleLoopMode();

  /// Set audio quality preference
  void setAudioQuality(AudioQuality quality) =>
      _playerService.setAudioQuality(quality);

  /// Get current audio quality
  AudioQuality get audioQuality => _playerService.audioQuality;

  /// Get current player state (not to be confused with audio_service's playbackState)
  player.PlaybackState get currentPlayerState => _playerService.state;

  @override
  Future<void> onTaskRemoved() async {
    await stop();
  }

  void dispose() {
    _stateSubscription?.cancel();
    _positionSubscription?.cancel();
    _bufferedPositionSubscription?.cancel();
    _playerService.dispose();
  }
}

/// Initialize audio service
Future<InzxAudioHandler> initAudioService() async {
  return await AudioService.init(
    builder: () => InzxAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.mine.mine.audio',
      androidNotificationChannelName: 'Mine Music',
      androidNotificationChannelDescription: 'Music playback controls',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'drawable/ic_notification',
      fastForwardInterval: Duration(seconds: 10),
      rewindInterval: Duration(seconds: 10),
    ),
  );
}
