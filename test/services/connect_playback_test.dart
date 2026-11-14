import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inzx/models/models.dart';
import 'package:inzx/providers/providers.dart';
import 'package:inzx/services/audio_player_service.dart';
import 'package:inzx/services/inzx_connect_remote.dart';
import 'package:inzx/services/inzx_connect_service.dart';
import 'package:rxdart/rxdart.dart';

class _LocalPlayer extends Fake implements AudioPlayerService {
  final states = BehaviorSubject.seeded(const PlaybackState());
  int pauses = 0;

  @override
  PlaybackState get state => states.value;

  @override
  Stream<PlaybackState> get stateStream => states.stream;

  @override
  Future<void> pause({bool fromConnect = false}) async {
    pauses++;
  }
}

class _GroupPlayer extends _LocalPlayer {
  Future<void> Function(Map<String, dynamic>)? _transport;
  @override
  Future<void> Function(Map<String, dynamic>)? get connectTransport =>
      _transport;
  @override
  set connectTransport(Future<void> Function(Map<String, dynamic>)? value) {
    _transport = value;
  }

  @override
  set followsConnectLeader(bool value) {}
  Duration position = Duration.zero;

  @override
  bool get isJamsModeEnabled => false;
  @override
  Track? get currentTrack => state.currentTrack;
  @override
  List<Track> get queue => state.queue;
  @override
  Duration get currentPosition => position;

  bool transitioning = false;
  @override
  bool get isTransitioning => transitioning;

  /// Each fade into a queue entry: (index, where it started).
  final fades = <(int, Duration)>[];
  int reloads = 0;
  final seeks = <Duration>[];

  @override
  Future<bool> connectFadeTo(int index, Duration startAt) async {
    if (!state.isPlaying || index == state.currentIndex) return false;
    fades.add((index, startAt));
    position = startAt;
    states.add(
      state.copyWith(currentTrack: state.queue[index], currentIndex: index),
    );
    return true;
  }

  @override
  Future<void> play({bool fromConnect = false}) async {
    expect(fromConnect, true);
    states.add(state.copyWith(isPlaying: true));
  }

  @override
  Future<void> pause({bool fromConnect = false}) async {
    expect(fromConnect, true);
    states.add(state.copyWith(isPlaying: false));
  }

  @override
  Future<void> seek(Duration value, {bool fromConnect = false}) async {
    expect(fromConnect, true);
    seeks.add(value);
    position = value;
  }

  @override
  Future<void> playQueue(
    List<Track> tracks, {
    int startIndex = 0,
    Duration? startPosition,
    bool startPaused = false,
    bool fromConnect = false,
    bool isRadioQueue = false,
    String? sourceId,
    String? sourceTitle,
  }) async {
    expect(fromConnect, true);
    reloads++;
    position = startPosition ?? Duration.zero;
    states.add(
      state.copyWith(
        currentTrack: tracks[startIndex],
        queue: tracks,
        currentIndex: startIndex,
        isPlaying: !startPaused,
      ),
    );
  }
}

void main() {
  test(
    'both devices stay grouped through play, pause, seek and a new track',
    () async {
      final desktop = _GroupPlayer();
      final phone = _GroupPlayer();
      final leader = InzxConnectRemote.forTest(desktop);
      final follower = InzxConnectRemote.forTest(phone);
      addTearDown(() async {
        leader.dispose();
        follower.dispose();
        await desktop.states.close();
        await phone.states.close();
      });
      const first = Track(
        id: 'first',
        title: 'First',
        artist: 'Artist',
        duration: Duration(minutes: 2),
      );
      final second = first.copyWith(id: 'second');
      const group = 'group';
      Future<void> receive(
        String action, [
        Map<String, dynamic> fields = const {},
      ]) => leader.receiveGroupCommandForTest({
        'from': 'phone',
        'action': action,
        'group': group,
        ...fields,
      });
      Future<void> sync({int seeks = 0}) {
        final state = desktop.state;
        return follower.followGroupForTest(
          'pc',
          group,
          ConnectPlayback(
            track: state.currentTrack,
            queue: state.queue,
            queueStart: 0,
            currentIndex: state.currentIndex,
            queueRevision: 1,
            isPlaying: state.isPlaying,
            isBuffering: false,
            positionMs: desktop.position.inMilliseconds,
            durationMs: 120000,
            receivedAt: DateTime.now(),
            shuffleEnabled: false,
            loopMode: LoopMode.off,
            speed: 1,
            seeks: seeks,
          ),
        );
      }

      await receive('group_start', {
        'tracks': [first.toJson(), second.toJson()],
      });
      await sync();
      expect(phone.state.isPlaying, true);
      await receive('pause');
      await sync();
      expect(phone.state.isPlaying, false);
      expect(follower.isPlayingOnBoth, true);
      expect(follower.followedPlayback, isNull);
      await receive('seek', {'position_ms': 42000});
      await sync(seeks: 1);
      expect(phone.position, const Duration(seconds: 42));
      await desktop.connectTransport!({'action': 'play'});
      await sync(seeks: 1);
      expect(phone.state.isPlaying, true);
      await desktop.connectTransport!({
        'action': 'group_queue',
        'tracks': [second.toJson()],
      });
      await sync();
      expect(phone.currentTrack, second);
      expect(leader.isPlayingOnBoth && follower.isPlayingOnBoth, true);
      await receive('group_end', {'pause': true});
      expect(leader.isPlayingOnBoth, false);
      expect(desktop.state.isPlaying, false);
    },
  );

  test(
    'a crossfade on the leader fades the follower too, with no reload or seek',
    () async {
      final desktop = _GroupPlayer();
      final phone = _GroupPlayer();
      final leader = InzxConnectRemote.forTest(desktop);
      final follower = InzxConnectRemote.forTest(phone);
      addTearDown(() async {
        leader.dispose();
        follower.dispose();
        await desktop.states.close();
        await phone.states.close();
      });
      const first = Track(
        id: 'first',
        title: 'First',
        artist: 'Artist',
        duration: Duration(minutes: 2),
      );
      final second = first.copyWith(id: 'second');
      const group = 'group';

      ConnectPlayback leaderState({required int positionMs}) => ConnectPlayback(
        track: desktop.state.currentTrack,
        queue: desktop.state.queue,
        queueStart: 0,
        currentIndex: desktop.state.currentIndex,
        queueRevision: 1,
        isPlaying: desktop.state.isPlaying,
        isBuffering: false,
        positionMs: positionMs,
        durationMs: 120000,
        receivedAt: DateTime.now(),
        shuffleEnabled: false,
        loopMode: LoopMode.off,
        speed: 1,
        seeks: 0,
      );

      await leader.receiveGroupCommandForTest({
        'from': 'phone',
        'action': 'group_start',
        'group': group,
        'tracks': [first.toJson(), second.toJson()],
      });
      await follower.followGroupForTest(
        'pc',
        group,
        leaderState(positionMs: 110000),
      );
      expect(phone.currentTrack, first);
      final reloadsBefore = phone.reloads;

      // The leader's crossfade (or Automix handoff) moves it to the second
      // song, already 8 s in.
      desktop.states.add(
        desktop.state.copyWith(currentTrack: second, currentIndex: 1),
      );
      await follower.followGroupForTest(
        'pc',
        group,
        leaderState(positionMs: 8000),
      );

      expect(phone.currentTrack, second);
      expect(phone.fades, hasLength(1));
      expect(phone.fades.single.$1, 1);
      expect(
        phone.fades.single.$2.inMilliseconds,
        inInclusiveRange(8000, 8500),
      );
      expect(phone.reloads, reloadsBefore, reason: 'no reload over the fade');

      // Right after, a drifted reading doesn't seek into the settling fade.
      phone.position = const Duration(seconds: 5);
      await follower.followGroupForTest(
        'pc',
        group,
        leaderState(positionMs: 9000),
      );
      expect(phone.seeks, isEmpty);
      expect(phone.reloads, reloadsBefore);
    },
  );

  test(
    'the phone shows the PC queue and routes controls away from local audio',
    () async {
      final local = _LocalPlayer();
      final updates = StreamController<ConnectPeerPlayback?>();
      final container = ProviderContainer(
        overrides: [
          audioPlayerServiceProvider.overrideWithValue(local),
          connectPeerPlaybackProvider.overrideWith((_) => updates.stream),
          isInJamSessionProvider.overrideWithValue(false),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await updates.close();
        await local.states.close();
      });

      const first = Track(
        id: 'first',
        title: 'First',
        artist: 'Artist',
        duration: Duration(minutes: 2),
      );
      final second = first.copyWith(id: 'second', title: 'Second');
      ConnectPeerPlayback sample({bool playing = false, int ms = 12000}) => (
        device: ConnectDevice.fromJson({'id': 'pc', 'label': 'PC'}),
        playback: ConnectPlayback(
          track: second,
          queue: [first, second],
          queueStart: 0,
          currentIndex: 1,
          queueRevision: 2,
          isPlaying: playing,
          isBuffering: false,
          positionMs: ms,
          durationMs: 120000,
          receivedAt: DateTime.now(),
          shuffleEnabled: false,
          loopMode: LoopMode.off,
          speed: 1,
          seeks: 0,
        ),
      );
      updates.add(sample());
      await container.read(connectPeerPlaybackProvider.future);

      final state = await container.read(playbackStateProvider.future);
      expect(state.currentTrack, second);
      expect(state.queue, [first, second]);
      expect(state.currentIndex, 1);
      expect(
        await container.read(positionStreamProvider.future),
        const Duration(seconds: 12),
      );
      await container.read(playbackTransportProvider).pause();
      expect(local.pauses, 0);

      final states = <AsyncValue<PlaybackState>>[];
      final positions = <AsyncValue<Duration>>[];
      final playbackSub = container.listen(playbackStateProvider, (_, next) {
        states.add(next);
      });
      final positionSub = container.listen(positionStreamProvider, (_, next) {
        positions.add(next);
      });
      addTearDown(playbackSub.close);
      addTearDown(positionSub.close);

      // A heartbeat for the same paused track should leave the player alone.
      updates.add(sample());
      await pumpEventQueue();
      expect(states, isEmpty);
      expect(positions, isEmpty);

      updates.add(sample(playing: true));
      await pumpEventQueue();
      expect(states.single.valueOrNull?.isPlaying, true);

      // Pause, then seek on the PC. Only the progress stream changes on seek.
      updates.add(sample());
      await pumpEventQueue();
      expect(states.last.valueOrNull?.isPlaying, false);
      final stateCount = states.length;
      updates.add(sample(ms: 42000));
      await pumpEventQueue();
      expect(states, hasLength(stateCount));
      expect(positions.last.valueOrNull, const Duration(seconds: 42));
      expect(states.every((state) => !state.isLoading), true);
      expect(positions.every((position) => !position.isLoading), true);

      local.states.add(
        const PlaybackState(currentTrack: first, isPlaying: true),
      );
      await pumpEventQueue();
      expect(
        container.read(playbackStateProvider).valueOrNull?.currentTrack,
        first,
      );
      await container.read(playbackTransportProvider).pause();
      expect(local.pauses, 1);
    },
  );
}
