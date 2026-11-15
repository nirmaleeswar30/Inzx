import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter/widgets.dart'
    show AppLifecycleState, AppLifecycleListener;
import 'package:just_audio/just_audio.dart' show LoopMode;
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/platform_utils.dart' show isDesktop;
import '../models/models.dart';
import 'audio_player_service.dart';
import 'audio_routing_service.dart';
import 'desktop/desktop_audio_dsp.dart';
import 'inzx_connect_service.dart';

/// What a paired device is playing, as it last said.
class ConnectPlayback {
  ConnectPlayback({
    required this.track,
    required this.isPlaying,
    required this.positionMs,
    required this.durationMs,
    required this.receivedAt,
    required this.queue,
    required this.queueStart,
    required this.currentIndex,
    required this.queueRevision,
    required this.shuffleEnabled,
    required this.loopMode,
    required this.speed,
    required this.isBuffering,
    required this.seeks,
    this.volume,
    this.isTransitioning,
  });

  final Track? track;
  final bool isPlaying;
  final int positionMs;
  final int durationMs;
  final DateTime receivedAt;
  final List<Track> queue;
  final int queueStart;
  final int currentIndex;
  final int queueRevision;
  final bool shuffleEnabled;
  final LoopMode loopMode;
  final double speed;
  final bool isBuffering;
  final int seeks;

  /// The device's own volume, 0..1: the app's volume on a computer, the
  /// media volume on a phone. Null when it doesn't say (an older build, or
  /// bit-perfect output, where the level is the hardware's).
  final double? volume;

  /// Whether the device was crossfading (or blending) into its song when it
  /// reported: a song change it makes then is a transition to fade along
  /// with, while one without is a skip, to cut to. Null from older builds,
  /// which don't say; those song changes are faded as before.
  final bool? isTransitioning;

  /// Where the song has got to now, running on from the last report while
  /// it plays.
  Duration get position {
    var ms = positionMs;
    if (isPlaying && !isBuffering) {
      ms += (DateTime.now().difference(receivedAt).inMilliseconds * speed)
          .round();
    }
    if (durationMs > 0 && ms > durationMs) ms = durationMs;
    return Duration(milliseconds: ms);
  }
}

/// Inzx Connect after pairing: paired devices see what each other is
/// playing, control it, and move playback between them.
///
/// Every device listens on its own private Realtime topic,
/// `inzx-connect:<device id>`. It publishes its playback there (`state`) and
/// takes commands from there (`command`). Supabase only lets a device use its
/// own topic and the topics of devices it is paired with (see the
/// `inzx_connect_remote` migration).
///
/// A device publishes while a peer is looking. Android also keeps watching
/// an active desktop session while the Connect notification is running.
class InzxConnectRemote extends ChangeNotifier {
  InzxConnectRemote._([this._testPlayer]);

  static final instance = InzxConnectRemote._();

  @visibleForTesting
  InzxConnectRemote.forTest(AudioPlayerService player) : this._(player);

  static const _event = 'command';
  static const _stateEvent = 'state';
  static const _channelConfig = RealtimeChannelConfig(private: true, ack: true);
  static const _backgroundChannel = MethodChannel('inzx/connect_background');

  /// How long a `hello` keeps this device publishing its changes.
  static const _watchedFor = Duration(seconds: 25);

  /// How often a watching device says `hello`.
  static const _helloEvery = Duration(seconds: 8);

  /// A peer that hasn't answered for this long is shown offline.
  static const _offlineAfter = Duration(seconds: 20);
  static const _refreshDevicesEvery = Duration(seconds: 30);

  /// Limit queue snapshots and handoffs to keep broadcasts small.
  static const _maxQueue = 100;

  final _connect = InzxConnectService.instance;
  final AudioPlayerService? _testPlayer;
  AudioPlayerService get _player => _testPlayer ?? AudioPlayerService.instance;

  SupabaseClient? _client;
  String? _deviceId;
  RealtimeChannel? _own;
  final Map<String, RealtimeChannel> _peers = {};
  final Map<String, ConnectPlayback> _playback = {};
  final Map<String, DateTime> _lastSeen = {};
  final Map<String, DateTime> _lastHello = {};
  final Map<String, DateTime> _firstWatched = {};
  DateTime _watchedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  StreamSubscription<PlaybackState>? _playerSub;
  StreamSubscription<Duration>? _positionSub;
  String? _sentSignature;
  Future<void>? _starting;
  bool _started = false;
  List<ConnectDevice> _devices = const [];
  List<ConnectDevice> get pairedDevices => List.unmodifiable(_devices);
  String? _followedId;
  String? _selectedOutput;
  String? _groupPeer;
  String? _groupId;
  bool _groupLeader = false;
  bool _groupConfirmed = false;
  Timer? _groupStartTimeout;
  bool _applyingGroup = false;
  ConnectPlayback? _pendingGroupPlayback;
  ConnectPlayback? _appliedGroupPlayback;
  Future<void> _groupCommands = Future<void>.value();

  /// After following the leader's fade, drift isn't corrected until this
  /// passes, so the fade isn't interrupted by a seek.
  DateTime _settleUntil = DateTime.fromMillisecondsSinceEpoch(0);
  static const _settleAfterFade = Duration(milliseconds: 1500);
  bool get isPlayingOnBoth => _groupId != null;
  bool get isLocalOutputSelected =>
      _selectedOutput != null && _selectedOutput == _deviceId;
  bool isGroupedWith(String id) => _groupPeer == id;

  @visibleForTesting
  Future<void> receiveGroupCommandForTest(Map<String, dynamic> command) =>
      _onCommand({'payload': command});

  /// A state report from [deviceId], as its broadcast would deliver it.
  @visibleForTesting
  void receiveStateForTest(String deviceId, Map<String, dynamic> state) =>
      _onState(deviceId, {'payload': state});

  @visibleForTesting
  Future<void> followGroupForTest(
    String peer,
    String group,
    ConnectPlayback playback,
  ) {
    if (!isGroupedWith(peer)) _setGroup(peer, group, leader: false);
    return _followGroup(playback);
  }

  bool isOutputSelected(String id) =>
      _selectedOutput == id ||
      (_selectedOutput == null && activePlayback?.device.id == id);

  void _setGroup(String peer, String group, {required bool leader}) {
    _groupPeer = peer;
    _groupId = group;
    _groupLeader = leader;
    _groupConfirmed = leader;
    _selectedOutput = null;
    _player.connectTransport = _groupCommand;
    _player.followsConnectLeader = !leader;
    _sentSignature = null;
    notifyListeners();
    _groupStartTimeout?.cancel();
    if (!leader) {
      _groupStartTimeout = Timer(_offlineAfter, () {
        if (_groupId == group && !_groupConfirmed) _clearGroup();
      });
    }
  }

  void _clearGroup() {
    if (_groupId == null) return;
    _groupStartTimeout?.cancel();
    _groupStartTimeout = null;
    _groupPeer = null;
    _groupId = null;
    _groupLeader = false;
    _groupConfirmed = false;
    _pendingGroupPlayback = null;
    _appliedGroupPlayback = null;
    _player.connectTransport = null;
    _player.followsConnectLeader = false;
    _sentSignature = null;
    notifyListeners();
    unawaited(_syncNotification());
  }

  @override
  void dispose() {
    _groupStartTimeout?.cancel();
    super.dispose();
  }

  Future<void> leaveGroup() => _leaveGroup();
  Future<void> stopBoth() => _leaveGroup();

  Future<void> _leaveGroup() async {
    final peer = _groupPeer;
    final group = _groupId;
    if (peer == null) return;
    _clearGroup();
    await _sendTo(peer, {'action': 'group_end', 'group': group});
  }

  Future<void> _groupCommand(Map<String, dynamic> body) async {
    final peer = _groupPeer;
    final group = _groupId;
    if (peer == null) return;
    if (!_groupLeader) {
      final action = body['action'];
      final queueStart = _appliedGroupPlayback?.queueStart ?? 0;
      final index = body['index'];
      final to = body['to'];
      final tracks = body['tracks'];
      await _sendTo(peer, {
        ...body,
        'group': group,
        if (index is int &&
            (action == 'queue_remove' || action == 'queue_reorder'))
          'index': index + queueStart,
        if (to is int && action == 'queue_reorder') 'to': to + queueStart,
        if (tracks is List)
          'tracks': _readQueue(tracks).map(_trackMetadata).toList(),
      });
      return;
    }
    await _runGroupCommand(group, body);
  }

  Future<void> _runGroupCommand(String? group, Map body) {
    final next = _groupCommands.then((_) async {
      if (_groupId != group || !_groupLeader) return;
      await _applyCommand(body);
      _sentSignature = null;
      await _publish();
    });
    _groupCommands = next.catchError((Object error) {
      if (kDebugMode) debugPrint('InzxConnect: group command failed: $error');
    });
    return _groupCommands;
  }

  Future<void> _followGroup(ConnectPlayback playback) async {
    _pendingGroupPlayback = playback;
    if (_applyingGroup) return;
    _applyingGroup = true;
    try {
      while (_groupId != null && !_groupLeader) {
        final next = _pendingGroupPlayback;
        if (next == null) break;
        _pendingGroupPlayback = null;
        final previous = _appliedGroupPlayback;
        if (next.isBuffering && previous?.track?.id != next.track?.id) {
          continue;
        }
        _appliedGroupPlayback = next;
        await _applyGroupPlayback(next, previous);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('InzxConnect: group sync failed: $e');
    } finally {
      _applyingGroup = false;
    }
  }

  Future<void> _applyGroupPlayback(
    ConnectPlayback peer,
    ConnectPlayback? previous,
  ) async {
    final track = peer.track;
    if (track == null) {
      if (_player.currentTrack != null) _player.clearQueue(fromConnect: true);
      return;
    }
    if (_isLocal(track)) {
      await _player.pause(fromConnect: true);
      return;
    }
    final queueChanged =
        previous == null ||
        previous.queueRevision != peer.queueRevision ||
        previous.queueStart != peer.queueStart ||
        !listEquals(previous.queue, peer.queue);
    if (_player.state.loopMode != peer.loopMode) {
      await _player.setLoopMode(peer.loopMode, fromConnect: true);
    }
    if (_player.state.speed != peer.speed &&
        peer.speed >= 0.25 &&
        peer.speed <= 4) {
      await _player.setSpeed(peer.speed, fromConnect: true);
    }
    if (_player.state.shuffleEnabled != peer.shuffleEnabled) {
      _player.setConnectShuffle(peer.shuffleEnabled);
    }
    // The leader moved on to the next song in the same queue: a crossfade,
    // or an Automix blend handing over. Fade into it here as well, from
    // where the leader is, rather than reloading it over the song still
    // playing (that cut was the hiccup in every transition).
    final index = peer.currentIndex;
    final lines = !queueChanged &&
        index >= 0 &&
        index < _player.queue.length &&
        _player.queue[index].id == track.id;
    // A skip on the leader (no transition running there) cuts straight to
    // the song below instead, as it did on the leader.
    if (lines &&
        previous.track?.id != track.id &&
        _player.currentTrack?.id != track.id &&
        peer.isPlaying &&
        peer.isTransitioning != false) {
      if (await _player.connectFadeTo(index, peer.position)) {
        _settleUntil = DateTime.now().add(_settleAfterFade);
        return;
      }
    }
    // Already on the leader's song (its own fade got there): nothing to load.
    final alreadyThere =
        lines &&
        _player.currentTrack?.id == track.id &&
        _player.state.currentIndex == index;
    if (!alreadyThere &&
        (queueChanged ||
            _player.currentTrack == null ||
            previous.track?.id != track.id ||
            previous.currentIndex != peer.currentIndex)) {
      final tracks = peer.queue.isEmpty ? [track] : peer.queue;
      await _player.playQueue(
        tracks,
        startIndex: peer.currentIndex.clamp(0, tracks.length - 1),
        startPosition: peer.position,
        startPaused: !peer.isPlaying && !peer.isBuffering,
        fromConnect: true,
      );
      return;
    }
    // Mid-fade the playhead belongs to two songs, and seeking then is
    // audible; drift is put right once the transition has settled.
    final settling =
        _player.isTransitioning ||
        peer.isBuffering ||
        DateTime.now().isBefore(_settleUntil);
    if (!settling &&
        (peer.seeks != previous.seeks ||
            (!_player.state.isLoading &&
                (_player.currentPosition - peer.position).abs() >
                    const Duration(milliseconds: 900)))) {
      await _player.seek(peer.position, fromConnect: true);
    }
    if (!peer.isBuffering) {
      if (peer.isPlaying) {
        if (!_player.state.isPlaying || !previous.isPlaying) {
          await _player.play(fromConnect: true);
        }
      } else if (_player.state.isPlaying ||
          _player.state.isLoading ||
          previous.isPlaying) {
        await _player.pause(fromConnect: true);
      }
    }
  }

  Timer? _discoveryTimer;
  AppLifecycleListener? _lifecycle;
  DateTime? _lastDeviceRefresh;
  bool _refreshingDevices = false;
  bool _discoveryPausedByUser = false;
  bool _inForeground = false;
  bool _localPlaying = false;
  bool _inJam = false;
  ({
    String id,
    String device,
    String track,
    String artist,
    String? artwork,
    bool playing,
    bool buffering,
    int duration,
    int seeks,
    double speed,
  })?
  _notification;
  bool _updatingNotification = false;
  bool _notificationNeedsUpdate = false;
  bool _requestedNotifications = false;
  ({String id, String url})? _notificationArtwork;

  ({ConnectDevice device, ConnectPlayback playback})? get followedPlayback {
    if (isPlayingOnBoth || isLocalOutputSelected) return null;
    final id = _selectedOutput ?? _followedId;
    final playback = _playback[id];
    if (playback?.track == null || id == null || !isOnline(id)) return null;
    final device = _devices.where((device) => device.id == id).firstOrNull;
    return device == null ? null : (device: device, playback: playback!);
  }

  ({ConnectDevice device, ConnectPlayback playback})? get activePlayback =>
      _localPlaying || _inJam ? null : followedPlayback;

  void _selectFollowedDevice() {
    if (!InzxConnectService.canScanQr ||
        _discoveryPausedByUser ||
        _selectedOutput != null ||
        isPlayingOnBoth) {
      return;
    }
    if (followedPlayback != null) return;
    _followedId = _devices
        .where((device) {
          final playback = _playback[device.id];
          return isOnline(device.id) &&
              playback?.track != null &&
              playback!.isPlaying;
        })
        .firstOrNull
        ?.id;
  }

  @override
  void notifyListeners() {
    _syncFollowWatch();
    super.notifyListeners();
  }

  /// Phones run a discovery loop that keeps paired devices reporting. A
  /// computer has none, so while its playback is out on a paired device
  /// (its "Play on …" button, or "Play here" on that device), it keeps that
  /// device reporting the same way, and its player follows it. Without this
  /// the device stopped reporting 25 seconds later (see [_watchedFor]).
  void _syncFollowWatch() {
    if (InzxConnectService.canScanQr || !_started) return;
    final following = _selectedOutput != null && _selectedOutput != _deviceId;
    if (following && _discoveryTimer == null) {
      _startDiscovery();
    } else if (!following && _discoveryTimer != null) {
      _pauseDiscovery();
    }
  }

  void _resumeDiscovery() {
    _inForeground = true;
    if (_discoveryPausedByUser) return;
    _lastDeviceRefresh = null;
    _startDiscovery();
    unawaited(_syncNotification());
  }

  void _startDiscovery() {
    _discoveryTimer ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_discover()),
    );
    unawaited(_discover());
  }

  void _onBackgrounded() {
    _inForeground = false;
    if (_notification == null && !isPlayingOnBoth) _pauseDiscovery();
  }

  void _pauseDiscovery() {
    _discoveryTimer?.cancel();
    _discoveryTimer = null;
  }

  Future<void> _discover() async {
    final previousId = _followedId;
    _selectFollowedDevice();
    if (_followedId != previousId) notifyListeners();
    unawaited(_syncNotification());
    final now = DateTime.now();
    final lastRefresh = _lastDeviceRefresh;
    // Keep sending heartbeats even while a status request is in flight.
    await watch(_devices);
    if (_discoveryTimer != null &&
        !_refreshingDevices &&
        (lastRefresh == null ||
            now.difference(lastRefresh) >= _refreshDevicesEvery)) {
      _lastDeviceRefresh = now;
      _refreshingDevices = true;
      final previousDevices = _devices;
      try {
        final devices = (await _connect.status()).devices;
        if (_discoveryTimer != null && identical(_devices, previousDevices)) {
          await watch(devices);
        }
      } catch (_) {
        // Keep checking the last known peers until the service responds.
      } finally {
        _refreshingDevices = false;
      }
    }
  }

  /// What [deviceId] is playing, or null if it hasn't said.
  ConnectPlayback? playbackOf(String deviceId) => _playback[deviceId];

  /// Whether [deviceId] has answered recently.
  bool isOnline(String deviceId) {
    final seen = _lastSeen[deviceId];
    return seen != null && DateTime.now().difference(seen) < _offlineAfter;
  }

  /// Whether a peer is still in its initial discovery window.
  bool isLookingFor(String deviceId) {
    if (_lastSeen.containsKey(deviceId)) return false;
    final started = _firstWatched[deviceId];
    return started == null ||
        DateTime.now().difference(started) < _offlineAfter;
  }

  /// Starts listening for commands, if this install has used Connect before.
  /// Safe to call repeatedly. Never throws.
  Future<void> start() {
    if (_started) return Future<void>.value();
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<void> _start() async {
    try {
      if (!await _connect.hasSession()) return;
      final client = await _connect.client();
      final id = _connect.deviceId;
      if (id == null) return;
      _client = client;
      _deviceId = id;
      _player.connectRemoteOutput = _remoteOutput;
      _player.masterVolumeListenable.addListener(_onLocalVolume);
      final token = client.auth.currentSession?.accessToken;
      if (token != null) await client.realtime.setAuth(token);

      _own = client
          .channel(_topic(id), opts: _channelConfig)
          .onBroadcast(event: _event, callback: _onCommand)
          .subscribe((status, error) {
            if (kDebugMode && error != null) {
              debugPrint('InzxConnect: own channel $status: $error');
            }
          });

      _localPlaying = _player.state.isPlaying || _player.state.isLoading;
      _playerSub = _player.stateStream.listen((state) {
        final localPlaying = state.isPlaying || state.isLoading;
        if (_localPlaying != localPlaying) {
          _localPlaying = localPlaying;
          notifyListeners();
          unawaited(_syncNotification());
        }
        _publishIfWatched();
      });
      if (InzxConnectService.canShowQr) {
        _positionSub = _player.positionStream.listen(
          (_) => _publishIfWatched(),
        );
      }
      _started = true;
      if (InzxConnectService.canScanQr) {
        _backgroundChannel.setMethodCallHandler((call) async {
          final id = activePlayback?.device.id;
          switch (call.method) {
            case 'play':
              if (id != null) await setPlaying(id, true);
            case 'pause':
              if (id != null) await setPlaying(id, false);
            case 'previous':
              if (id != null) await previous(id);
            case 'next':
              if (id != null) await next(id);
            case 'seek':
              final ms = call.arguments;
              if (id != null && ms is int) {
                await seek(id, Duration(milliseconds: ms));
              }
            case 'disconnect':
              disconnect();
          }
        });
        _localPlaying = _player.state.isPlaying || _player.state.isLoading;
        _lifecycle = AppLifecycleListener(
          onResume: _resumeDiscovery,
          onHide: _onBackgrounded,
        );
        final lifecycle = _lifecycle!.binding.lifecycleState;
        if (lifecycle == AppLifecycleState.resumed) _resumeDiscovery();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('InzxConnect: remote unavailable: $e');
    }
  }

  /// Stops listening and drops what's known about peers.
  Future<void> stop() async {
    _pauseDiscovery();
    _inForeground = false;
    _lifecycle?.dispose();
    _lifecycle = null;
    await _positionSub?.cancel();
    _positionSub = null;
    await _playerSub?.cancel();
    _playerSub = null;
    final client = _client;
    if (client != null) {
      for (final channel in [?_own, ..._peers.values]) {
        await client.removeChannel(channel);
      }
    }
    _own = null;
    _peers.clear();
    _playback.clear();
    _lastSeen.clear();
    _lastHello.clear();
    _firstWatched.clear();
    _devices = const [];
    _followedId = null;
    _clearGroup();
    _selectedOutput = null;
    _player.connectRemoteOutput = null;
    _player.masterVolumeListenable.removeListener(_onLocalVolume);
    _volumePublish?.cancel();
    _started = false;
    if (InzxConnectService.canScanQr) {
      _backgroundChannel.setMethodCallHandler(null);
      await _syncNotification();
    }
    notifyListeners();
  }

  /// Re-enables playback following when the user opens Connect again.
  void resumeFollowing() {
    if (!InzxConnectService.canScanQr) return;
    _discoveryPausedByUser = false;
    if (_inForeground) _startDiscovery();
  }

  void disconnect() {
    _discoveryPausedByUser = true;
    _followedId = null;
    _selectedOutput = _deviceId;
    unawaited(_leaveGroup());
    _pauseDiscovery();
    notifyListeners();
    unawaited(_syncNotification());
  }

  void setJamActive(bool active) {
    if (!InzxConnectService.canScanQr || _inJam == active) return;
    _inJam = active;
    if (active) unawaited(_leaveGroup());
    notifyListeners();
    unawaited(_syncNotification());
  }

  Future<void> _syncNotification() async {
    if (!InzxConnectService.canScanQr) return;
    if (_updatingNotification) {
      _notificationNeedsUpdate = true;
      return;
    }
    final followed = activePlayback;
    final desired = followed == null
        ? null
        : (
            id: followed.playback.track!.id,
            device: followed.device.label,
            track: followed.playback.track!.title,
            artist: followed.playback.track!.artist,
            artwork: followed.playback.track!.systemArtworkUrl,
            playing: followed.playback.isPlaying,
            buffering: followed.playback.isBuffering,
            duration: followed.playback.durationMs,
            seeks: followed.playback.seeks,
            speed: followed.playback.speed,
          );
    if (_notification == desired || (!_inForeground && _notification == null)) {
      return;
    }

    _updatingNotification = true;
    try {
      if (desired == null) {
        await _backgroundChannel.invokeMethod<void>('stop');
        _notificationArtwork = null;
      } else {
        await _backgroundChannel.invokeMethod<bool>('show', {
          'device': desired.device,
          'track': desired.track,
          'id': desired.id,
          'artist': desired.artist,
          'artwork': desired.artwork,
          'playing': desired.playing,
          'buffering': desired.buffering,
          'duration': desired.duration,
          'position': followed!.playback.position.inMilliseconds,
          'speed': desired.speed,
        });
      }
      _notification = desired;
      final artworkUrl = desired?.artwork;
      if (desired != null && artworkUrl != null) {
        final artwork = (id: desired.id, url: artworkUrl);
        if (_notificationArtwork != artwork) {
          _notificationArtwork = artwork;
          unawaited(_loadNotificationArtwork(artwork));
        }
      }
      if (desired != null && _inForeground && !_requestedNotifications) {
        _requestedNotifications = true;
        unawaited(_requestNotifications());
      }
      if (!_inForeground && desired == null && !isPlayingOnBoth) {
        _pauseDiscovery();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('InzxConnect: notification unavailable: $e');
    } finally {
      _updatingNotification = false;
      if (_notificationNeedsUpdate) {
        _notificationNeedsUpdate = false;
        unawaited(_syncNotification());
      }
    }
  }

  Future<void> _loadNotificationArtwork(
    ({String id, String url}) artwork,
  ) async {
    try {
      final file = await DefaultCacheManager().getSingleFile(artwork.url);
      if (_notificationArtwork != artwork) return;
      await _backgroundChannel.invokeMethod<void>('artwork', {
        'id': artwork.id,
        'url': artwork.url,
        'path': file.path,
      });
    } catch (_) {
      // Track metadata and controls are available while artwork loads.
    }
  }

  Future<void> _requestNotifications() async {
    try {
      if (await Permission.notification.isDenied && _inForeground) {
        await Permission.notification.request();
      }
    } catch (_) {
      // The foreground service can still run if notifications are disabled.
    }
  }

  static String _topic(String deviceId) => 'inzx-connect:$deviceId';

  /// Keeps up with [devices]: listens to each one's playback and says
  /// `hello` so they report it. Also called by foreground Android discovery.
  Future<void> watch(List<ConnectDevice> devices) async {
    final devicesChanged = !listEquals(
      _devices.map((d) => (d.id, d.label)).toList(),
      devices.map((d) => (d.id, d.label)).toList(),
    );
    _devices = devices;
    final wanted = {for (final d in devices) d.id};
    final now = DateTime.now();
    _firstWatched.removeWhere((id, _) => !wanted.contains(id));
    for (final id in wanted) {
      _firstWatched.putIfAbsent(id, () => now);
    }
    await start();
    final client = _client;
    if (client == null) return;
    for (final id in _peers.keys.toList()) {
      if (!wanted.contains(id)) {
        if (_groupPeer == id) _clearGroup();
        if (_selectedOutput == id) _selectedOutput = null;
        unawaited(client.removeChannel(_peers.remove(id)!));
        _playback.remove(id);
        _lastSeen.remove(id);
        _lastHello.remove(id);
      }
    }
    for (final id in wanted) {
      final channel = _peers[id] ??= client
          .channel(_topic(id), opts: _channelConfig)
          .onBroadcast(
            event: _stateEvent,
            callback: (message) => _onState(id, message),
          )
          .subscribe((status, error) {
            if (status == RealtimeSubscribeStatus.subscribed) {
              final channel = _peers[id];
              if (channel != null) _hello(id, channel, DateTime.now());
            } else if (kDebugMode && error != null) {
              debugPrint('InzxConnect: peer channel $status: $error');
            }
          });
      if (!channel.canPush) continue;
      final last = _lastHello[id];
      if (last == null || now.difference(last) >= _helloEvery) {
        _hello(id, channel, now);
      }
    }
    final previousId = _followedId;
    _selectFollowedDevice();
    if (devicesChanged || _followedId != previousId) notifyListeners();
    unawaited(_syncNotification());
  }

  void _hello(String id, RealtimeChannel channel, DateTime now) {
    _lastHello[id] = now;
    unawaited(_send(channel, {'action': 'hello'}));
  }

  Future<bool> _send(RealtimeChannel channel, Map<String, dynamic> body) async {
    final from = _deviceId;
    if (from == null || !channel.canPush) return false;
    try {
      final response = await channel.sendBroadcastMessage(
        event: _event,
        payload: {
          'payload': {...body, 'from': from},
        },
      );
      if (kDebugMode && response != ChannelResponse.ok) {
        debugPrint('InzxConnect: send failed: $response');
      }
      return response == ChannelResponse.ok;
    } catch (e) {
      if (kDebugMode) debugPrint('InzxConnect: send failed: $e');
      return false;
    }
  }

  /// The device the player is showing and controlling, as a command sender,
  /// or null when playback is on this device (or in a Jam). Songs started
  /// or queued here go to it: see [AudioPlayerService.connectRemoteOutput].
  Future<void> Function(Map<String, dynamic>)? _remoteOutput() {
    if (_player.isJamsModeEnabled) return null;
    final id = activePlayback?.device.id;
    if (id == null) return null;
    return (body) => _command(id, body);
  }

  /// Shows [deviceId] as playing [playback] and online, as its reports would,
  /// with this device controlling it; [send] receives the commands.
  @visibleForTesting
  void controlForTest(
    ConnectDevice device,
    ConnectPlayback playback,
    Future<void> Function(Map<String, dynamic>) send,
  ) {
    _devices = [device];
    _playback[device.id] = playback;
    _lastSeen[device.id] = DateTime.now();
    _selectedOutput = device.id;
    _testSend = send;
    _player.connectRemoteOutput = _remoteOutput;
  }

  /// Takes the place of the Realtime channel in tests.
  Future<void> Function(Map<String, dynamic>)? _testSend;

  /// What this device reports about its own player, as its state stream
  /// would set it.
  @visibleForTesting
  set localPlayingForTest(bool playing) => _localPlaying = playing;

  Future<void> _command(String deviceId, Map<String, dynamic> body) async {
    if (isGroupedWith(deviceId) && body['action'] != 'hello') {
      await _groupCommand(body);
      return;
    }
    await _sendTo(deviceId, body);
  }

  Future<bool> _sendTo(String deviceId, Map<String, dynamic> body) async {
    final testSend = _testSend;
    if (testSend != null) {
      await testSend(body);
      return true;
    }
    final channel = _peers[deviceId];
    if (channel != null && channel.canPush) return _send(channel, body);
    final client = _client;
    final from = _deviceId;
    if (client == null || from == null) return false;
    final target =
        channel ?? client.channel(_topic(deviceId), opts: _channelConfig);
    try {
      final result = await target.sendBroadcastMessage(
        event: _event,
        payload: {...body, 'from': from},
      );
      return result == ChannelResponse.ok;
    } catch (e) {
      if (kDebugMode) debugPrint('InzxConnect: send failed: $e');
      return false;
    } finally {
      if (channel == null) unawaited(client.removeChannel(target));
    }
  }

  // Remote control.
  Future<void> togglePlay(String deviceId) =>
      _command(deviceId, {'action': 'toggle'});
  Future<void> next(String deviceId) => _command(deviceId, {'action': 'next'});
  Future<void> previous(String deviceId) =>
      _command(deviceId, {'action': 'previous'});
  Future<void> setPlaying(String deviceId, bool playing) =>
      _command(deviceId, {'action': playing ? 'play' : 'pause'});
  Future<void> seek(String deviceId, Duration position) => _command(deviceId, {
    'action': 'seek',
    'position_ms': position.inMilliseconds,
  });
  Future<void> skipTo(String deviceId, int index) async {
    final playback = _playback[deviceId];
    if (playback == null || index < 0 || index >= playback.queue.length) return;
    await _command(deviceId, {
      'action': 'skip_to',
      'index': index + playback.queueStart,
      'track_id': playback.queue[index].id,
    });
  }

  /// Sets [deviceId]'s own volume, 0..1 (see [ConnectPlayback.volume]).
  /// Sent straight to that device, also while playing on both: each device
  /// keeps its own level.
  Future<void> setVolume(String deviceId, double volume) =>
      _sendTo(deviceId, {'action': 'volume', 'volume': volume.clamp(0.0, 1.0)});

  /// This device's volume, as peers are told it: the app's volume on a
  /// computer (none with bit-perfect output, where the level is the
  /// hardware's), the media volume on a phone.
  Future<double?> _localVolume() async {
    if (isDesktop) {
      return DesktopAudioDsp.instance.exclusive ? null : _player.masterVolume;
    }
    return AudioRoutingService.getVolume();
  }

  Future<void> _setLocalVolume(double volume) async {
    final level = volume.clamp(0.0, 1.0);
    if (isDesktop) {
      if (!DesktopAudioDsp.instance.exclusive) {
        await _player.setMasterVolume(level);
      }
    } else {
      await AudioRoutingService.setVolume(level);
    }
  }

  /// The computer's volume moved (its player bar): peers' sliders follow,
  /// once a drag has paused rather than on every step of it.
  void _onLocalVolume() {
    _volumePublish?.cancel();
    _volumePublish = Timer(const Duration(milliseconds: 150), () {
      _sentSignature = null;
      _publishIfWatched();
    });
  }

  Timer? _volumePublish;

  Future<void> toggleShuffle(String deviceId) =>
      _command(deviceId, {'action': 'shuffle'});
  Future<void> cycleLoopMode(String deviceId) =>
      _command(deviceId, {'action': 'repeat'});

  /// Moves what this device is playing onto [deviceId], and pauses here.
  Future<bool> playOn(String deviceId) async {
    final grouped = isGroupedWith(deviceId);
    final handoff = grouped ? null : _handoff();
    if (!grouped && handoff == null) return false;
    final sent = await _sendTo(deviceId, {
      'action': grouped ? 'group_end' : 'take_over',
      if (grouped) 'group': _groupId,
      if (grouped) 'play': true,
      ...?handoff,
    });
    if (!sent) return false;
    _selectedOutput = deviceId;
    if (grouped) {
      _clearGroup();
    } else {
      await _leaveGroup();
    }
    notifyListeners();
    await _player.pause(fromConnect: true);
    return true;
  }

  /// Starts the same song on both devices from the current playhead.
  Future<bool> playOnBoth(String deviceId) async {
    if (!isOnline(deviceId) || _inJam || _player.isJamsModeEnabled) {
      return false;
    }
    if (isGroupedWith(deviceId)) return true;
    final peer = _playback[deviceId];
    final localSource =
        !isOutputSelected(deviceId) &&
        (_player.state.isPlaying || peer?.track == null);
    final handoff = localSource ? _handoff() : null;
    final peerTrack = peer?.track;
    if (localSource
        ? handoff == null
        : peerTrack == null || _isLocal(peerTrack)) {
      return false;
    }
    await _leaveGroup();
    final group = '$_deviceId:${DateTime.now().microsecondsSinceEpoch}';
    _setGroup(deviceId, group, leader: false);
    if (!await _sendTo(deviceId, {
      'action': 'group_start',
      'group': group,
      ...?handoff,
    })) {
      if (_groupId == group) _clearGroup();
      return false;
    }
    if (InzxConnectService.canScanQr && _discoveryTimer == null) {
      _startDiscovery();
    }
    return true;
  }

  /// Takes over what [deviceId] is playing.
  Future<void> playHere(String deviceId) async {
    if (isGroupedWith(deviceId)) {
      if (!await _sendTo(deviceId, {
        'action': 'group_end',
        'group': _groupId,
        'pause': true,
      })) {
        return;
      }
      _selectedOutput = _deviceId;
      _clearGroup();
      notifyListeners();
      await _player.play(fromConnect: true);
      return;
    }
    if (await _sendTo(deviceId, {'action': 'send_to'})) {
      _selectedOutput = _deviceId;
      notifyListeners();
    }
  }

  /// The song playing here, the queue after it and where it's got to, for
  /// another device to carry on from. Null when there's nothing it could
  /// play (nothing on, or a file only this device has).
  Map<String, dynamic>? _handoff() {
    final queue = _player.queue;
    var index = _player.currentIndex;
    final current = _player.currentTrack;
    if (current == null || _isLocal(current)) return null;
    if (index < 0 || index >= queue.length || queue[index].id != current.id) {
      return {
        'tracks': [current.toJson()],
        'index': 0,
        'position_ms': _player.currentPosition.inMilliseconds,
      };
    }
    final tracks = <Map<String, dynamic>>[];
    var start = -1;
    for (var i = index; i < queue.length && tracks.length < _maxQueue; i++) {
      final track = queue[i];
      if (_isLocal(track)) {
        if (i == index) return null;
        continue;
      }
      if (i == index) start = tracks.length;
      tracks.add(track.toJson());
    }
    if (start < 0) return null;
    index = start;
    return {
      'tracks': tracks,
      'index': index,
      'position_ms': _player.currentPosition.inMilliseconds,
    };
  }

  static bool _isLocal(Track track) =>
      track.localFilePath != null || track.id.startsWith('local_');

  void _onState(String deviceId, Map<String, dynamic> message) {
    final body = _broadcastBody(message);
    if (body['playing'] is! bool) return;
    _lastSeen[deviceId] = DateTime.now();
    final track = _readTrack(body['track']);
    final queueStart = (body['queue_start'] as num?)?.toInt() ?? 0;
    final currentIndex = (body['current_index'] as num?)?.toInt() ?? 0;
    final queueRevision = (body['queue_revision'] as num?)?.toInt() ?? 0;
    final previous = _playback[deviceId];
    final rawQueue = body['queue'];
    final queue = rawQueue is List
        ? (previous != null &&
                  previous.queueRevision == queueRevision &&
                  previous.queueStart == queueStart &&
                  previous.queue.length == rawQueue.length &&
                  previous.track?.id == track?.id
              ? previous.queue
              : List<Track>.unmodifiable(
                  rawQueue.map(_readTrack).whereType<Track>(),
                ))
        : const <Track>[];
    final hasCurrent =
        currentIndex >= 0 &&
        currentIndex < queue.length &&
        queue[currentIndex].id == track?.id;
    final loop = (body['loop_mode'] as num?)?.toInt() ?? 0;
    _playback[deviceId] = ConnectPlayback(
      track: track,
      isPlaying: body['playing'] == true,
      positionMs: (body['position_ms'] as num?)?.toInt() ?? 0,
      durationMs: (body['duration_ms'] as num?)?.toInt() ?? 0,
      receivedAt: DateTime.now(),
      queue: hasCurrent
          ? queue
          : track == null
          ? const []
          : [track],
      queueStart: hasCurrent ? queueStart : queueStart + currentIndex,
      currentIndex: track == null
          ? -1
          : hasCurrent
          ? currentIndex
          : 0,
      queueRevision: queueRevision,
      shuffleEnabled: body['shuffle'] == true,
      loopMode: LoopMode.values.elementAtOrNull(loop) ?? LoopMode.off,
      speed: (body['speed'] as num?)?.toDouble() ?? 1,
      isBuffering: body['buffering'] == true,
      seeks: (body['seeks'] as num?)?.toInt() ?? 0,
      volume: (body['volume'] as num?)?.toDouble().clamp(0.0, 1.0),
      isTransitioning: switch (body['transitioning']) {
        final bool transitioning => transitioning,
        _ => null,
      },
    );
    if (isGroupedWith(deviceId) && !_groupLeader) {
      if (body['group'] == _groupId) {
        _groupConfirmed = true;
        _groupStartTimeout?.cancel();
        unawaited(_followGroup(_playback[deviceId]!));
      } else if (_groupConfirmed) {
        _clearGroup();
      }
    }
    _selectFollowedDevice();
    notifyListeners();
    unawaited(_syncNotification());
    if (!_inForeground && _notification != null && _followedId == deviceId) {
      unawaited(_keepAwake());
    }
  }

  Future<void> _keepAwake() async {
    try {
      await _backgroundChannel.invokeMethod<void>('keepAwake');
    } catch (_) {
      // Android may have stopped the foreground service.
    }
  }

  static Track? _readTrack(Object? json) {
    if (json is! Map) return null;
    try {
      return Track.fromJson(Map<String, dynamic>.from(json));
    } catch (_) {
      return null;
    }
  }

  Future<void> _onCommand(Map<String, dynamic> message) async {
    final body = _broadcastBody(message);
    final from = body['from'];
    if (from is! String || from == _deviceId) return;
    // Supabase only lets paired devices onto this topic, so a command here
    // is from one of them.
    _watchedUntil = DateTime.now().add(_watchedFor);
    try {
      final action = body['action'];
      final group = body['group'];
      if (action == 'volume') {
        // Each device keeps its own level, "Play on both" or not.
        final volume = body['volume'];
        if (volume is num) await _setLocalVolume(volume.toDouble());
      } else if (action == 'group_start' &&
          group is String &&
          !_player.isJamsModeEnabled) {
        await _leaveGroup();
        _setGroup(from, group, leader: true);
        if (body['tracks'] is List) {
          await _takeOver(body);
        } else {
          await _player.play(fromConnect: true);
        }
      } else if (action == 'group_end') {
        if (isGroupedWith(from) && group == _groupId) {
          _selectedOutput = body['pause'] == true ? from : _deviceId;
          _clearGroup();
          if (body['pause'] == true) {
            await _player.pause(fromConnect: true);
          } else if (body['play'] == true) {
            await _player.play(fromConnect: true);
          }
          notifyListeners();
        }
      } else if (group != null) {
        if (isGroupedWith(from) && group == _groupId && _groupLeader) {
          await _runGroupCommand(_groupId, body);
        }
      } else if (action == 'take_over' || action == 'send_to') {
        await _leaveGroup();
        if (action == 'take_over') {
          _selectedOutput = _deviceId;
          await _takeOver(body);
        } else {
          await playOn(from);
        }
      } else if (!isPlayingOnBoth || _groupLeader) {
        await _applyCommand(body);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('InzxConnect: command failed: $e');
    }
    _sentSignature = null;
    await _publish();
  }

  Future<void> _applyCommand(Map body) async {
    switch (body['action']) {
      case 'hello':
        break;
      case 'toggle':
        if (_player.state.isPlaying) {
          await _player.pause(fromConnect: true);
        } else {
          await _player.play(fromConnect: true);
        }
      case 'play':
        await _player.play(fromConnect: true);
      case 'pause':
        await _player.pause(fromConnect: true);
      case 'next':
        await _player.skipToNext(fromConnect: true);
      case 'previous':
        await _player.skipToPrevious(fromConnect: true);
      case 'seek':
        final position = body['position_ms'];
        if (position is num && position >= 0) {
          await _player.seek(
            Duration(milliseconds: position.toInt()),
            fromConnect: true,
          );
        }
      case 'seek_by':
        final offset = body['offset_ms'];
        if (offset is int) {
          final ms = _player.currentPosition.inMilliseconds + offset;
          await _player.seek(
            Duration(milliseconds: ms < 0 ? 0 : ms),
            fromConnect: true,
          );
        }
      case 'speed':
        final speed = body['speed'];
        if (speed is num && speed >= 0.25 && speed <= 4) {
          await _player.setSpeed(speed.toDouble(), fromConnect: true);
        }
      case 'skip_to':
        final queue = _player.queue;
        final index =
            body['index'] ??
            queue.indexWhere((track) => track.id == body['track_id']);
        if (index is int &&
            index >= 0 &&
            index < queue.length &&
            queue[index].id == body['track_id']) {
          _player.skipToIndex(index, fromConnect: true);
        }
      case 'shuffle':
        await _player.toggleShuffle(fromConnect: true);
      case 'repeat':
        final modes = [LoopMode.off, LoopMode.all, LoopMode.one];
        await _player.setLoopMode(
          modes[(modes.indexOf(_player.state.loopMode) + 1) % modes.length],
          fromConnect: true,
        );
      case 'set_repeat':
        final mode = body['loop_mode'];
        if (mode is int && mode >= 0 && mode < LoopMode.values.length) {
          await _player.setLoopMode(LoopMode.values[mode], fromConnect: true);
        }
      case 'group_queue':
        await _takeOver(body);
      case 'queue_add':
        final tracks = _readQueue(body['tracks']);
        if (tracks.isNotEmpty) _player.addToQueue(tracks);
      case 'queue_next':
        final track = _readQueue(body['tracks']).firstOrNull;
        if (track != null) _player.playNext(track);
      case 'queue_clear':
        _player.clearQueue(fromConnect: true);
      case 'queue_remove' || 'queue_reorder':
        final index = body['index'];
        final queue = _player.queue;
        if (index is! int ||
            index < 0 ||
            index >= queue.length ||
            queue[index].id != body['track_id']) {
          return;
        }
        if (body['action'] == 'queue_remove') {
          _player.removeFromQueue(index);
        } else if (body['to'] case final int to) {
          _player.reorderQueue(index, to);
        }
    }
  }

  // Earlier builds sent the body directly on the WebSocket broadcast frame.
  static Map _broadcastBody(Map<String, dynamic> message) {
    final payload = message['payload'];
    return payload is Map ? payload : message;
  }

  static List<Track> _readQueue(Object? list) => list is List
      ? list.take(_maxQueue).map(_readTrack).whereType<Track>().toList()
      : const [];

  Future<void> _takeOver(Map body) async {
    final tracks = _readQueue(body['tracks']);
    if (tracks.isEmpty) return;
    final index = ((body['index'] as num?)?.toInt() ?? 0).clamp(
      0,
      tracks.length - 1,
    );
    final positionMs = (body['position_ms'] as num?)?.toInt() ?? 0;
    await _player.playQueue(
      tracks,
      startIndex: index,
      startPosition: Duration(milliseconds: positionMs),
      fromConnect: true,
    );
  }

  void _publishIfWatched() {
    if (!_groupLeader && DateTime.now().isAfter(_watchedUntil)) return;
    unawaited(_publish());
  }

  /// Tells peers what's playing. They advance the clock between updates.
  Future<void> _publish() async {
    final channel = _own;
    if (channel == null || !channel.canPush) return;
    final track = _player.currentTrack;
    final state = _player.state;
    final playing = state.isPlaying;
    final playhead = _player.playhead;
    final buffering = state.isBuffering || state.isLoading;
    final volume = await _localVolume();
    final transitioning = _player.isTransitioning;
    final signature =
        '${track?.id}|${state.currentIndex}|$playing|$buffering|'
        '${state.queueRevision}|${state.loopMode}|${state.shuffleEnabled}|'
        '${state.speed}|${playhead.seeks}|${state.duration}|'
        '${volume?.toStringAsFixed(2)}|$transitioning';
    if (signature == _sentSignature) return;
    _sentSignature = signature;
    final position = _player.currentPosition.inMilliseconds;
    final duration = (state.duration ?? track?.duration)?.inMilliseconds ?? 0;
    final queue = state.queue;
    final queueStart = (state.currentIndex - 20).clamp(0, queue.length);
    final queueEnd = (queueStart + _maxQueue).clamp(queueStart, queue.length);
    try {
      final response = await channel.sendBroadcastMessage(
        event: _stateEvent,
        payload: {
          'payload': {
            'track': track == null ? null : _trackMetadata(track),
            'playing': playing,
            'position_ms': position,
            'duration_ms': duration,
            'queue': queue
                .sublist(queueStart, queueEnd)
                .map(_trackMetadata)
                .toList(),
            'current_index': state.currentIndex - queueStart,
            'queue_start': queueStart,
            'queue_revision': state.queueRevision,
            'shuffle': state.shuffleEnabled,
            'loop_mode': state.loopMode.index,
            'speed': state.speed,
            'buffering': buffering,
            'seeks': playhead.seeks,
            'volume': ?volume,
            'transitioning': transitioning,
            if (_groupId != null) 'group': _groupId,
          },
        },
      );
      if (response != ChannelResponse.ok) {
        if (_sentSignature == signature) _sentSignature = null;
        if (kDebugMode) debugPrint('InzxConnect: publish failed: $response');
      }
    } catch (e) {
      if (_sentSignature == signature) _sentSignature = null;
      if (kDebugMode) debugPrint('InzxConnect: publish failed: $e');
    }
  }

  static Map<String, dynamic> _trackMetadata(Track track) => track.toJson()
    ..remove('localFilePath')
    ..remove('setVideoId');
}
