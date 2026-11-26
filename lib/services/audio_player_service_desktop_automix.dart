part of 'audio_player_service.dart';

/// Desktop Automix's view of the player service: the two players it blends
/// between, and the "clip mode" that carries the UI through a rendered blend.
///
/// While the clip plays, neither of the service's players is what's heard,
/// so their own position and state are ignored (see `_automixClipActive` in
/// `_bindPlayerEventStreams`) and the engine reports the blend's position on
/// the song's own timeline instead: the outgoing song's until the blend's
/// midpoint, the incoming song's after it, exactly as the session moves on
/// Android.
class _DesktopAutomixHost implements DesktopAutomixHost {
  _DesktopAutomixHost(this.s);

  final AudioPlayerService s;

  AudioPlayer _player(String id) => s._playerById(id);

  @override
  Duration positionOf(String playerId) => _player(playerId).position;

  @override
  Duration? durationOf(String playerId) => _player(playerId).duration;

  @override
  bool isPlaying(String playerId) {
    final player = _player(playerId);
    return player.playing && player.processingState == ProcessingState.ready;
  }

  @override
  double get listenerSpeed => s._listenerSpeed;

  @override
  double get masterVolume => s._masterVolume;

  @override
  String get scratchDir => p.join(Directory.systemTemp.path, 'inzx_automix');

  @override
  DecodeSource? sourceOf(String playerId) {
    final source = _player(playerId).sequenceState.currentSource;
    if (source is UriAudioSource) {
      return DecodeSource(source.uri.toString(), source.headers ?? const {});
    }
    // iOS streams YouTube's AAC through YouTubeAacAudioSource. The analysis
    // copy is the same file, and the only kind AVAssetReader can decode.
    if (source is YouTubeAacAudioSource) {
      final tag = source.tag;
      final copy = tag is Track
          ? AutomixService.instance.desktopEngine?.analyzer.audioFor(tag.id)
          : null;
      return copy == null ? null : DecodeSource(Uri.file(copy).toString(), const {});
    }
    return null;
  }

  @override
  Future<bool> loadIncoming(String playerId, int index, Duration at) async {
    if (index < 0 || index >= s._queue.length) return false;
    final player = _player(playerId);
    if (identical(player, s._player)) return false;
    s._automixMixing = true;
    final track = s._queue[index];
    try {
      final built = await s._buildSourceForTrack(track);
      await player.setLoopMode(s._nativeLoopModeFor(s._loopMode));
      await s._setVolumeSafely(player, 0.0, context: 'automix-arm');
      await player.setAudioSource(built.source, initialPosition: at, preload: true);
      s._automixIncomingData = built.playbackData;
      s._automixIncomingIndex = index;
      return true;
    } catch (e) {
      if (kDebugMode) print('AudioPlayerService: Automix load failed: $e');
      s._automixMixing = false;
      return false;
    }
  }

  @override
  Future<void> setVolume(String playerId, double volume) =>
      s._setVolumeSafely(_player(playerId), volume, context: 'automix');

  @override
  Future<void> setSpeed(String playerId, double speed) async {
    try {
      await _player(playerId).setSpeed(speed);
    } catch (_) {}
  }

  @override
  Future<void> seek(String playerId, Duration at) async {
    try {
      await _player(playerId).seek(at);
    } catch (_) {}
  }

  @override
  void play(String playerId) {
    unawaited(_player(playerId).play().catchError((Object _) {}));
  }

  @override
  Future<void> pause(String playerId) async {
    try {
      await _player(playerId).pause();
    } catch (_) {}
  }

  @override
  Future<void> retire(String playerId) async {
    final player = _player(playerId);
    if (identical(player, s._player) && !s._automixClipActive) return;
    try {
      await player.stop();
    } catch (_) {}
    await s._setVolumeSafely(player, 1.0, context: 'automix-retire');
    await setSpeed(playerId, s._listenerSpeed);
    if (!s._automixClipActive) s._automixMixing = false;
  }

  @override
  bool wantsToPlay(String playerId) => _player(playerId).playing;

  @override
  bool get mixesLive => isIOS;

  @override
  void setTransitionFilter(String playerId,
      {double lowPassHz = 20000, double highPassHz = 20, double echoSeconds = 0, double echoSend = 0, double echoDry = 1}) {
    if (!isIOS) return;
    unawaited(IosNative.setTransition(playerId,
        lowPassHz: lowPassHz,
        highPassHz: highPassHz,
        echoSeconds: echoSeconds,
        echoSend: echoSend,
        echoDry: echoDry));
  }

  @override
  void liveHandoff(String toPlayerId, int index) => _handoff(toPlayerId, index, playing: _player(toPlayerId).playing);

  @override
  void clipBegan() {
    s._automixClipActive = true;
    s._automixClipPlaying = true;
    s._automixMixing = true;
  }

  @override
  void clipProgress(int index, Duration position, bool playing) {
    if (!s._automixClipActive) return;
    s._positionController.add(position);
    final now = DateTime.now();
    final changed = playing != s._automixClipPlaying;
    s._automixClipPlaying = playing;
    final last = s._automixClipStateAt;
    if (changed || last == null || now.difference(last) >= AudioPlayerService._positionUpdateInterval) {
      s._automixClipStateAt = now;
      s._updateState(position: position, isPlaying: playing, isBuffering: false, isLoading: false);
    }
  }

  @override
  void clipHandoff(String toPlayerId, int index) => _handoff(toPlayerId, index, playing: s._automixClipPlaying);

  /// The incoming song becomes the current one: the session moves onto its
  /// player (which a clip hands the rest of the song to, and a live blend is
  /// already playing on).
  void _handoff(String toPlayerId, int index, {required bool playing}) {
    if (index < 0 || index >= s._queue.length) return;
    s._flushWatchtimeForCurrentTrackBeforeSwitch();
    final incoming = _player(toPlayerId);
    s._player = incoming;
    s._markPlayheadJump();
    s._currentIndex = index;
    s._currentTrack = s._queue[index];
    final data = s._automixIncomingIndex == index ? s._automixIncomingData : null;
    if (data != null) s._currentPlaybackData = data;
    s._activeSourceQueueIndices = <int>[index];
    s._activeSourcePlaybackDataByQueueIndex =
        data == null ? const <int, PlaybackData>{} : <int, PlaybackData>{index: data};
    s._crossfadeTriggeredForTrack = false;
    final duration = incoming.duration;
    if (duration != null) s._applyDurationToCurrentTrack(duration);
    s._updateState(
      currentTrack: s._currentTrack,
      currentIndex: s._currentIndex,
      currentPlaybackData: s._currentPlaybackData,
      queue: s._queue,
      queueRevision: s._queueRevision,
      duration: duration,
      resetDuration: duration == null,
      isLoading: false,
      isPlaying: playing,
    );
    s._resetYoutubePlaybackTrackingForCurrentTrack();
    s._startYoutubePlaybackTracking();
    s._saveQueueDebounced();
    s._prefetchNextTrack();
    s._scheduleLyricsPrefetchAroundCurrent();
    s._syncAutomix();
    if (kDebugMode) print('AudioPlayerService: Automix handoff -> ${s._currentTrack?.id}');
  }

  @override
  void clipEnded(String sessionPlayerId) {
    final player = _player(sessionPlayerId);
    s._automixClipActive = false;
    s._automixMixing = false;
    s._player = player;
    s._updateState(
      position: player.position,
      duration: player.duration,
      isPlaying: player.playing,
      isBuffering: player.processingState == ProcessingState.buffering,
      isLoading: player.processingState == ProcessingState.loading,
    );
    s._positionController.add(player.position);
    s._syncAutomix();
    final track = s._currentTrack;
    if (track != null) unawaited(s._upgradeToLosslessIfPossible(track));
  }

  @override
  Future<void> fetchAudio(String videoId) => s.fetchAnalysisAudio(videoId);

  @override
  double loudnessGain(String trackId) {
    final db = s._ytPlayerUtils.loudnessDbFor(trackId);
    if (db != null) DesktopLoudness.instance.update({trackId: db});
    return DesktopLoudness.instance.gainFor(trackId);
  }

  @override
  Future<List<LoopLyricLine>?> syncedLyrics(String videoId) async {
    var lines = LyricsNotifier.cachedSyncedLines(videoId);
    if (lines == null) {
      final track = s._queue.where((t) => t.id == videoId).firstOrNull;
      if (track == null) return null;
      await LyricsWarmupService.instance.prefetchForTrack(
        videoId: track.id,
        title: track.title,
        artist: track.artist,
        album: track.album,
        durationSeconds: track.duration.inSeconds,
        localFilePath: track.localFilePath,
      );
      lines = LyricsNotifier.cachedSyncedLines(videoId);
    }
    if (lines == null) return null;
    return [
      for (final line in lines)
        LoopLyricLine(
          line.timeInMs,
          line.sungUntilMs ?? (line.words != null && line.words!.isNotEmpty ? line.words!.last.endTimeMs : null),
          blank: line.isGap || line.text.trim().isEmpty,
        ),
    ];
  }
}

/// Desktop loudness normalization (DesktopLoudness): each player is levelled
/// for the song it holds, re-checked when its source changes or a figure or
/// setting does. Automix's rendered blends level each side themselves (see
/// [_DesktopAutomixHost.loudnessGain]).
extension _DesktopLoudnessWiring on AudioPlayerService {
  void _attachDesktopLoudness() {
    final loudness = DesktopLoudness.instance;
    unawaited(loudness.load());
    loudness.addListener(_applyDesktopLoudness);
    for (final player in [_primaryPlayer, _secondaryPlayer]) {
      player.sequenceStateStream.listen((_) => _applyDesktopLoudness());
    }
  }

  String? _trackIdOn(AudioPlayer player) {
    final tag = player.sequenceState.currentSource?.tag;
    return tag is Track ? tag.id : null;
  }

  void _applyDesktopLoudness() {
    final loudness = DesktopLoudness.instance;
    for (final player in [_primaryPlayer, _secondaryPlayer]) {
      final id = _trackIdOn(player);
      if (id != null) {
        final db = _ytPlayerUtils.loudnessDbFor(id);
        if (db != null) loudness.update({id: db});
      }
      if (isIOS) {
        IosAudioDsp.instance.setTrackGain(player.playerId, loudness.gainFor(id));
      } else {
        JustAudioMediaKit.setTrackGain(player.playerId, loudness.gainFor(id));
      }
    }
  }
}
