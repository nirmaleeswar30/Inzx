import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'jams_models.dart';
import 'jams_background_service_native.dart';

/// Supabase Realtime-based Jams Service
/// Uses Broadcast for playback sync and Presence for participant tracking
class JamsService {
  final String oderId;
  final String userName;
  final String? userPhotoUrl;

  RealtimeChannel? _channel;
  String? _currentSessionCode;
  bool _isHost = false;
  bool _canControlPlayback = false; // Permission granted by host
  JamSession? _currentSession;

  // Stream controllers
  final _sessionController = StreamController<JamSession?>.broadcast();
  final _playbackController = StreamController<JamPlaybackState>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _connectionStateController =
      StreamController<JamConnectionState>.broadcast();
  final _hostRoleChangeController =
      StreamController<bool>.broadcast(); // Notifies when host role changes
  final _permissionChangeController =
      StreamController<
        bool
      >.broadcast(); // Notifies when control permission changes

  // Presence state
  final Map<String, JamParticipant> _participants = {};
  final JamsBackgroundService _backgroundService =
      JamsBackgroundService.instance;
  Timer? _hostDisconnectTimer;
  static const Duration _hostDisconnectGrace = Duration(seconds: 45);
  final Map<String, Timer> _participantDisconnectTimers = {};
  static const Duration _participantDisconnectGrace = Duration(seconds: 45);
  Timer? _reconnectTimer;
  bool _isLeavingSession = false;
  bool _isReconnectInFlight = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectDelaySeconds = 30;
  DateTime _lastInboundRealtimeAt = DateTime.now();
  DateTime? _lastKeepAliveReconnectAt;
  static const Duration _maxInboundSilenceBeforeReconnect = Duration(
    seconds: 20,
  );
  static const Duration _keepAliveReconnectCooldown = Duration(seconds: 25);

  // Monotonic state version for ordering/recovery across clients
  int _stateVersion = 0;
  int _lastAppliedStateVersion = 0;
  JamConnectionState _connectionState = JamConnectionState.disconnected(
    reason: 'idle',
  );

  JamsService({
    required this.oderId,
    required this.userName,
    this.userPhotoUrl,
  });

  // ============ Public Getters ============

  JamSession? get currentSession => _currentSession;
  bool get isHost => _isHost;
  bool get canControlPlayback => _isHost || _canControlPlayback;
  bool get isInSession => _currentSession != null;
  String? get sessionCode => _currentSessionCode;
  List<JamQueueItem> get jamQueue => _currentSession?.queue ?? [];

  Stream<JamSession?> get sessionStream => _sessionController.stream;
  Stream<JamPlaybackState> get playbackStream => _playbackController.stream;
  Stream<String> get errorStream => _errorController.stream;
  Stream<JamConnectionState> get connectionStateStream =>
      _connectionStateController.stream;
  Stream<bool> get hostRoleChangeStream => _hostRoleChangeController.stream;
  Stream<bool> get permissionChangeStream => _permissionChangeController.stream;
  int get stateVersion => _lastAppliedStateVersion;
  JamConnectionState get connectionState => _connectionState;

  int _nextStateVersion() {
    _stateVersion += 1;
    _lastAppliedStateVersion = _stateVersion;
    return _stateVersion;
  }

  int _extractStateVersion(Map<String, dynamic> payload) {
    final raw = payload['stateVersion'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return 0;
  }

  bool _isStaleStateVersion(int incomingVersion) {
    if (incomingVersion <= 0) return false;
    return incomingVersion < _lastAppliedStateVersion;
  }

  void _markAppliedStateVersion(int version) {
    if (version <= 0) return;
    if (version > _lastAppliedStateVersion) {
      _lastAppliedStateVersion = version;
    }
    if (version > _stateVersion) {
      _stateVersion = version;
    }
  }

  void _markInboundRealtime(String source) {
    _lastInboundRealtimeAt = DateTime.now();
    if (kDebugMode) {
      print('JamsService: inbound realtime event ($source)');
    }
  }

  void _cancelHostDisconnectTimer() {
    _hostDisconnectTimer?.cancel();
    _hostDisconnectTimer = null;
  }

  void _startHostDisconnectTimer(String hostId) {
    if (_hostDisconnectTimer != null) return;
    _hostDisconnectTimer = Timer(_hostDisconnectGrace, () {
      _hostDisconnectTimer = null;
      if (_currentSession == null) return;
      final stillMissing = !_participants.containsKey(hostId);
      if (stillMissing && !_isHost) {
        _errorController.add(
          'Host disconnected. Waiting for host to reconnect.',
        );
      }
    });
  }

  void _cancelParticipantDisconnectTimer(String userId) {
    _participantDisconnectTimers.remove(userId)?.cancel();
  }

  void _cancelAllParticipantDisconnectTimers() {
    for (final timer in _participantDisconnectTimers.values) {
      timer.cancel();
    }
    _participantDisconnectTimers.clear();
  }

  void _scheduleParticipantDisconnect(String userId, {bool wasHost = false}) {
    if (userId == oderId) return;
    if (!_participants.containsKey(userId)) return;
    if (_participantDisconnectTimers.containsKey(userId)) return;

    _participantDisconnectTimers[userId] = Timer(
      _participantDisconnectGrace,
      () {
        _participantDisconnectTimers.remove(userId);
        final existed = _participants.remove(userId) != null;
        if (!existed) return;

        if (wasHost && !_isHost) {
          _errorController.add(
            'Host disconnected. Waiting for host to reconnect.',
          );
        }

        // Host-owned cleanup should happen only after grace expires.
        if (_isHost) {
          unawaited(removeUserSongsFromQueue(userId));
        }

        _updateSessionParticipants(null, null);
      },
    );
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _resetReconnectState() {
    _cancelReconnectTimer();
    _reconnectAttempts = 0;
  }

  void _emitConnectionState(JamConnectionState state) {
    _connectionState = state;
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(state);
    }
  }

  void _scheduleReconnect(String reason) {
    if (_isLeavingSession || _currentSessionCode == null) return;
    if (_reconnectTimer != null) return;
    if (_isReconnectInFlight) return;

    _reconnectAttempts += 1;
    final exp = min(_reconnectAttempts, 5); // 1,2,4,8,16 then clamp
    final delaySeconds = min(1 << exp, _maxReconnectDelaySeconds);

    if (kDebugMode) {
      print(
        'JamsService: scheduling reconnect in ${delaySeconds}s (attempt $_reconnectAttempts, reason: $reason)',
      );
    }
    _emitConnectionState(
      JamConnectionState.reconnecting(
        attempt: _reconnectAttempts,
        nextRetrySeconds: delaySeconds,
        reason: reason,
      ),
    );

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      _reconnectTimer = null;
      unawaited(_attemptReconnect(reason));
    });
  }

  Future<void> _attemptReconnect(String reason) async {
    if (_isLeavingSession || _currentSessionCode == null) return;
    if (_isReconnectInFlight) {
      if (kDebugMode) {
        print('JamsService: reconnect already in flight, skipping ($reason)');
      }
      return;
    }
    final code = _currentSessionCode!;

    _isReconnectInFlight = true;
    try {
      if (kDebugMode) {
        print('JamsService: reconnect attempt for $code (reason: $reason)');
      }
      _emitConnectionState(
        JamConnectionState.reconnecting(
          attempt: _reconnectAttempts,
          nextRetrySeconds: 0,
          reason: 'attempting_reconnect',
        ),
      );
      await _joinChannel(code);
    } catch (e) {
      if (kDebugMode) {
        print('JamsService: reconnect attempt failed: $e');
      }
      _scheduleReconnect('reconnect_failed');
    } finally {
      _isReconnectInFlight = false;
    }
  }

  // ============ Session Management ============

  /// Generate a 6-character session code
  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }

  /// Create a new Jam session (become host)
  Future<String?> createSession() async {
    try {
      _isLeavingSession = false;
      _resetReconnectState();
      _emitConnectionState(
        JamConnectionState.reconnecting(
          attempt: 0,
          nextRetrySeconds: 0,
          reason: 'creating_session',
        ),
      );
      final code = _generateCode();
      _currentSessionCode = code;
      _isHost = true;

      await _joinChannel(code);

      // Create initial session
      _currentSession = JamSession(
        sessionCode: code,
        hostId: oderId,
        hostName: userName,
        participants: [
          JamParticipant(
            id: oderId,
            name: userName,
            photoUrl: userPhotoUrl,
            isHost: true,
            joinedAt: DateTime.now(),
          ),
        ],
        playbackState: JamPlaybackState(syncedAt: DateTime.now()),
        queue: [],
        createdAt: DateTime.now(),
      );

      _sessionController.add(_currentSession);
      _backgroundService.attachService(this);
      await _backgroundService.onSessionJoined(
        sessionCode: code,
        oderId: oderId,
        userName: userName,
        userPhotoUrl: userPhotoUrl,
        isHost: true,
        participantCount: 1,
      );
      if (kDebugMode) {
        print('JamsService: Created session $code');
      }
      return code;
    } catch (e) {
      if (kDebugMode) {
        print('JamsService: Create session error: $e');
      }
      _errorController.add('Failed to create session: $e');
      return null;
    }
  }

  /// Join an existing Jam session
  Future<bool> joinSession(String code) async {
    try {
      _isLeavingSession = false;
      _resetReconnectState();
      _emitConnectionState(
        JamConnectionState.reconnecting(
          attempt: 0,
          nextRetrySeconds: 0,
          reason: 'joining_session',
        ),
      );
      _currentSessionCode = code.toUpperCase();
      _isHost = false;

      await _joinChannel(_currentSessionCode!);
      _backgroundService.attachService(this);
      await _backgroundService.onSessionJoined(
        sessionCode: _currentSessionCode!,
        oderId: oderId,
        userName: userName,
        userPhotoUrl: userPhotoUrl,
        isHost: false,
        participantCount: 1,
      );

      if (kDebugMode) {
        print('JamsService: Joined session $_currentSessionCode');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('JamsService: Join session error: $e');
      }
      _errorController.add('Failed to join session: $e');
      _currentSessionCode = null;
      return false;
    }
  }

  /// Join a Supabase Realtime channel for the session
  Future<void> _joinChannel(String code) async {
    final supabase = Supabase.instance.client;

    // Clean up previous channel before creating a new one (reconnect path).
    final previousChannel = _channel;
    if (previousChannel != null) {
      try {
        await previousChannel.untrack();
      } catch (_) {}
      try {
        await previousChannel.unsubscribe();
      } catch (_) {}
    }

    _channel = supabase.channel(
      'jam:$code',
      opts: const RealtimeChannelConfig(
        self: true, // Receive own broadcasts
      ),
    );

    // Listen for playback sync broadcasts
    _channel!.onBroadcast(
      event: 'playback',
      callback: (payload) => _handlePlaybackBroadcast(payload),
    );

    // Listen for queue updates
    _channel!.onBroadcast(
      event: 'queue',
      callback: (payload) => _handleQueueBroadcast(payload),
    );

    // Listen for session end
    _channel!.onBroadcast(
      event: 'session_end',
      callback: (payload) => _handleSessionEnd(payload),
    );

    // Listen for host transfer
    _channel!.onBroadcast(
      event: 'host_transfer',
      callback: (payload) => _handleHostTransfer(payload),
    );

    // Listen for permission updates
    _channel!.onBroadcast(
      event: 'permission_update',
      callback: (payload) => _handlePermissionUpdate(payload),
    );

    // Participants request full state snapshot from host after reconnect/resume
    _channel!.onBroadcast(
      event: 'state_request',
      callback: (payload) => _handleStateRequest(payload),
    );

    // Host responds with full session snapshot for recovery
    _channel!.onBroadcast(
      event: 'state_snapshot',
      callback: (payload) => _handleStateSnapshot(payload),
    );

    // Lightweight keepalive event for background resilience.
    _channel!.onBroadcast(
      event: 'heartbeat',
      callback: (payload) => _handleHeartbeat(payload),
    );

    // Track presence (who's in the session)
    _channel!.onPresenceSync((payload) => _handlePresenceSync());
    _channel!.onPresenceJoin(
      (payload) => _handlePresenceJoin(payload.newPresences),
    );
    _channel!.onPresenceLeave(
      (payload) => _handlePresenceLeave(payload.leftPresences),
    );

    // Subscribe to channel
    _channel!.subscribe((status, error) async {
      if (kDebugMode) {
        print('JamsService: Channel status: $status (error: $error)');
      }
      if (status == RealtimeSubscribeStatus.subscribed) {
        _resetReconnectState();
        _markInboundRealtime('subscribed');
        _emitConnectionState(JamConnectionState.connected());

        // Track our presence
        await _channel!.track({
          'user_id': oderId,
          'user_name': userName,
          'photo_url': userPhotoUrl,
          'is_host': _isHost,
          'joined_at': DateTime.now().toIso8601String(),
        });

        // Wait a moment for presence to sync across all clients
        await Future.delayed(const Duration(milliseconds: 500));

        // Force a presence sync to get current state
        _handlePresenceSync();

        // Ask host for latest authoritative state after subscribe/reconnect
        if (!_isHost) {
          unawaited(requestStateSync(reason: 'initial_subscribe'));
        }
      } else if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.closed ||
          status == RealtimeSubscribeStatus.timedOut) {
        _scheduleReconnect(status.name);
      }
    });
  }

  /// Leave the current session
  Future<void> leaveSession() async {
    _isLeavingSession = true;
    _cancelReconnectTimer();
    _emitConnectionState(
      JamConnectionState.disconnected(reason: 'left_session'),
    );

    final channel = _channel;
    final wasHost = _isHost;
    final previousSessionCode = _currentSessionCode;

    // Clear local state first so UI updates immediately.
    _channel = null;
    _currentSessionCode = null;
    _currentSession = null;
    _isHost = false;
    _canControlPlayback = false;
    _participants.clear();
    _cancelHostDisconnectTimer();
    _cancelAllParticipantDisconnectTimers();
    _stateVersion = 0;
    _lastAppliedStateVersion = 0;
    _sessionController.add(null);

    try {
      if (channel != null && wasHost) {
        // If host, broadcast session end.
        // Use local monotonic version for this final event.
        final stateVersion = _nextStateVersion();
        await channel.sendBroadcastMessage(
          event: 'session_end',
          payload: {'reason': 'Host left', 'stateVersion': stateVersion},
        );
      }

      // Best-effort channel cleanup.
      if (channel != null) {
        await channel.untrack();
        await channel.unsubscribe();
      }
    } catch (e) {
      if (kDebugMode) {
        print('JamsService: Leave session error: $e');
      }
    }

    await _backgroundService.onSessionLeft();
    _backgroundService.detachService();
    if (kDebugMode) {
      print('JamsService: Left session $previousSessionCode');
    }
  }

  /// Ask the host to rebroadcast the latest session snapshot.
  /// Used after app resume/background reconnect to recover missed realtime events.
  Future<void> requestStateSync({String reason = 'manual'}) async {
    if (_currentSessionCode == null || _isLeavingSession) return;
    if (_channel == null) {
      _scheduleReconnect('state_sync_$reason');
      return;
    }
    if (_isHost) {
      return; // Host already owns source-of-truth for outgoing state.
    }

    await _channel!.sendBroadcastMessage(
      event: 'state_request',
      payload: {
        'requesterId': oderId,
        'knownStateVersion': _lastAppliedStateVersion,
        'reason': reason,
        'requestedAt': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Keep the realtime channel warm and force state recovery when backgrounded.
  Future<void> keepAlive({String reason = 'manual'}) async {
    if (_currentSessionCode == null || _isLeavingSession) {
      if (kDebugMode) {
        print(
          'JamsService: keepAlive skipped (reason=$reason, inSession=${_currentSessionCode != null}, leaving=$_isLeavingSession)',
        );
      }
      return;
    }
    if (_channel == null) {
      if (kDebugMode) {
        print(
          'JamsService: keepAlive no channel, scheduling reconnect ($reason)',
        );
      }
      _scheduleReconnect('keepalive_$reason');
      return;
    }

    try {
      final silenceDuration = DateTime.now().difference(_lastInboundRealtimeAt);
      if (!_isHost &&
          silenceDuration > _maxInboundSilenceBeforeReconnect &&
          !_isLeavingSession) {
        final now = DateTime.now();
        final canForceReconnect =
            _lastKeepAliveReconnectAt == null ||
            now.difference(_lastKeepAliveReconnectAt!) >
                _keepAliveReconnectCooldown;

        if (canForceReconnect) {
          _lastKeepAliveReconnectAt = now;
          if (kDebugMode) {
            print(
              'JamsService: keepAlive detected stale inbound (${silenceDuration.inSeconds}s), forcing reconnect',
            );
          }
          unawaited(_attemptReconnect('stale_inbound_keepalive'));
        } else if (kDebugMode) {
          print(
            'JamsService: keepAlive stale inbound but reconnect cooldown active (${silenceDuration.inSeconds}s)',
          );
        }
      }

      if (kDebugMode) {
        print(
          'JamsService: keepAlive send heartbeat (reason=$reason, isHost=$_isHost, stateVersion=$_lastAppliedStateVersion)',
        );
      }
      await _channel!.sendBroadcastMessage(
        event: 'heartbeat',
        payload: {
          'senderId': oderId,
          'stateVersion': _lastAppliedStateVersion,
          'reason': reason,
          'sentAt': DateTime.now().toIso8601String(),
        },
      );

      if (_isHost) {
        if (kDebugMode) {
          print('JamsService: keepAlive host snapshot broadcast ($reason)');
        }
        await _broadcastStateSnapshot(reason: 'keepalive_$reason');
      } else {
        if (kDebugMode) {
          print('JamsService: keepAlive participant state request ($reason)');
        }
        await requestStateSync(reason: 'keepalive_$reason');
      }

      if (kDebugMode) {
        print('JamsService: keepAlive completed ($reason)');
      }
    } catch (e) {
      if (kDebugMode) {
        print('JamsService: keepAlive failed ($reason): $e');
      }
      _scheduleReconnect('keepalive_failed_$reason');
    }
  }

  void _handleHeartbeat(Map<String, dynamic> payload) {
    final senderId = payload['senderId'] as String?;
    if (senderId == null || senderId == oderId) return;
    _markInboundRealtime('heartbeat');
    if (kDebugMode) {
      final reason = payload['reason'] as String? ?? 'unknown';
      final version = _extractStateVersion(payload);
      print(
        'JamsService: Heartbeat received from $senderId (reason=$reason, v=$version)',
      );
    }
  }

  Future<void> _broadcastStateSnapshot({
    String? targetRequesterId,
    String reason = 'state_update',
  }) async {
    if (_channel == null || _currentSession == null) return;

    await _channel!.sendBroadcastMessage(
      event: 'state_snapshot',
      payload: {
        'senderId': oderId,
        'targetRequesterId': targetRequesterId,
        'stateVersion': _lastAppliedStateVersion,
        'reason': reason,
        'session': _currentSession!.toJson(),
        'sentAt': DateTime.now().toIso8601String(),
      },
    );
  }

  // ============ Playback Control (Host or Permitted Participants) ============

  /// Sync playback state to all participants
  /// Can be called by host or participants with playback control permission
  Future<void> syncPlayback({
    required String videoId,
    required String title,
    required String artist,
    String? thumbnailUrl,
    required int durationMs,
    required int positionMs,
    required bool isPlaying,
  }) async {
    if (!canControlPlayback || _channel == null) {
      if (kDebugMode) {
        print('JamsService: Cannot sync - no permission or not in session');
      }
      return;
    }

    final syncedAt = DateTime.now();
    final stateVersion = _nextStateVersion();
    final track = JamTrack(
      videoId: videoId,
      title: title,
      artist: artist,
      thumbnailUrl: thumbnailUrl,
      durationMs: durationMs,
    );

    final payload = {
      'track': track.toJson(),
      'positionMs': positionMs,
      'isPlaying': isPlaying,
      'syncedAt': syncedAt.toIso8601String(),
      'controllerId': oderId, // Who sent this broadcast
      'stateVersion': stateVersion,
    };

    await _channel!.sendBroadcastMessage(event: 'playback', payload: payload);

    // Also update local session state for host (so UI updates)
    if (_currentSession != null) {
      final newPlaybackState = JamPlaybackState(
        currentTrack: track,
        positionMs: positionMs,
        isPlaying: isPlaying,
        syncedAt: syncedAt,
      );
      _currentSession = _currentSession!.copyWith(
        playbackState: newPlaybackState,
      );
      _sessionController.add(_currentSession);
    }
  }

  /// Transfer host role to another participant (host only)
  Future<bool> transferHost(String newHostId) async {
    if (!_isHost || _channel == null || _currentSession == null) return false;

    final newHost = _participants[newHostId];
    if (newHost == null) return false;

    try {
      final stateVersion = _nextStateVersion();
      await _channel!.sendBroadcastMessage(
        event: 'host_transfer',
        payload: {
          'newHostId': newHostId,
          'newHostName': newHost.name,
          'stateVersion': stateVersion,
        },
      );

      // Update local state
      _isHost = false;
      if (kDebugMode) {
        print('JamsService: Transferred host to ${newHost.name}');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('JamsService: Host transfer error: $e');
      }
      return false;
    }
  }

  /// Grant or revoke playback control permission (host only)
  Future<bool> setParticipantPermission(
    String participantId,
    bool canControl,
  ) async {
    if (!_isHost || _channel == null) return false;

    try {
      final stateVersion = _nextStateVersion();
      await _channel!.sendBroadcastMessage(
        event: 'permission_update',
        payload: {
          'participantId': participantId,
          'canControlPlayback': canControl,
          'stateVersion': stateVersion,
        },
      );

      // Update local participant state
      if (_participants.containsKey(participantId)) {
        _participants[participantId] = _participants[participantId]!.copyWith(
          canControlPlayback: canControl,
        );
        _updateSessionParticipants(null, null);
      }

      if (kDebugMode) {
        print(
          'JamsService: ${canControl ? "Granted" : "Revoked"} control permission for $participantId',
        );
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('JamsService: Permission update error: $e');
      }
      return false;
    }
  }

  /// Initialize jam queue with host's current radio queue
  /// Called when host creates session
  Future<void> initializeJamQueue(List<JamQueueItem> items) async {
    if (_channel == null || _currentSession == null || !_isHost) return;
    final stateVersion = _nextStateVersion();

    await _channel!.sendBroadcastMessage(
      event: 'queue',
      payload: {
        'queue': items.map((t) => t.toJson()).toList(),
        'action': 'initialize',
        'stateVersion': stateVersion,
      },
    );

    // Update local session
    _currentSession = _currentSession!.copyWith(queue: items);
    _sessionController.add(_currentSession);
    if (kDebugMode) {
      print('JamsService: Initialized jam queue with ${items.length} tracks');
    }
  }

  /// Append new host's radio queue to existing jam queue
  /// Called when host transfers to a new user
  Future<void> appendHostQueue(List<JamQueueItem> items) async {
    if (_channel == null || _currentSession == null || !_isHost) return;

    final newQueue = List<JamQueueItem>.from(_currentSession!.queue);
    newQueue.addAll(items);
    final stateVersion = _nextStateVersion();

    await _channel!.sendBroadcastMessage(
      event: 'queue',
      payload: {
        'queue': newQueue.map((t) => t.toJson()).toList(),
        'action': 'append',
        'stateVersion': stateVersion,
      },
    );

    // Update local session
    _currentSession = _currentSession!.copyWith(queue: newQueue);
    _sessionController.add(_currentSession);
    if (kDebugMode) {
      print('JamsService: Appended ${items.length} tracks to jam queue');
    }
  }

  /// Add a single track to the queue (host or participant with permission)
  Future<void> addToQueue({
    required String videoId,
    required String title,
    required String artist,
    String? thumbnailUrl,
    required int durationMs,
  }) async {
    if (_channel == null || _currentSession == null) return;
    if (!canControlPlayback) {
      if (kDebugMode) {
        print('JamsService: No permission to add to queue');
      }
      return;
    }

    final newQueue = List<JamQueueItem>.from(_currentSession!.queue);
    newQueue.add(
      JamQueueItem(
        track: JamTrack(
          videoId: videoId,
          title: title,
          artist: artist,
          thumbnailUrl: thumbnailUrl,
          durationMs: durationMs,
        ),
        addedBy: oderId,
        addedAt: DateTime.now(),
      ),
    );
    final stateVersion = _nextStateVersion();

    await _channel!.sendBroadcastMessage(
      event: 'queue',
      payload: {
        'queue': newQueue.map((t) => t.toJson()).toList(),
        'addedBy': oderId,
        'stateVersion': stateVersion,
      },
    );
  }

  /// Insert a track at the front of the queue (play next)
  Future<void> playNextInQueue({
    required String videoId,
    required String title,
    required String artist,
    String? thumbnailUrl,
    required int durationMs,
  }) async {
    if (_channel == null || _currentSession == null) return;
    if (!canControlPlayback) {
      if (kDebugMode) {
        print('JamsService: No permission to add to queue');
      }
      return;
    }

    final newQueue = List<JamQueueItem>.from(_currentSession!.queue);
    newQueue.insert(
      0, // Insert at the front
      JamQueueItem(
        track: JamTrack(
          videoId: videoId,
          title: title,
          artist: artist,
          thumbnailUrl: thumbnailUrl,
          durationMs: durationMs,
        ),
        addedBy: oderId,
        addedAt: DateTime.now(),
      ),
    );
    final stateVersion = _nextStateVersion();

    await _channel!.sendBroadcastMessage(
      event: 'queue',
      payload: {
        'queue': newQueue.map((t) => t.toJson()).toList(),
        'addedBy': oderId,
        'stateVersion': stateVersion,
      },
    );
  }

  /// Remove a track from the queue (host or participant with permission)
  Future<void> removeFromQueue(int index) async {
    if (!canControlPlayback || _channel == null || _currentSession == null) {
      if (kDebugMode) {
        print('JamsService: No permission to remove from queue');
      }
      return;
    }

    final newQueue = List<JamQueueItem>.from(_currentSession!.queue);
    if (index >= 0 && index < newQueue.length) {
      newQueue.removeAt(index);
      final stateVersion = _nextStateVersion();

      await _channel!.sendBroadcastMessage(
        event: 'queue',
        payload: {
          'queue': newQueue.map((t) => t.toJson()).toList(),
          'stateVersion': stateVersion,
        },
      );
    }
  }

  /// Reorder tracks in the queue (host or participant with permission)
  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (!canControlPlayback || _channel == null || _currentSession == null) {
      if (kDebugMode) {
        print('JamsService: No permission to reorder queue');
      }
      return;
    }

    final newQueue = List<JamQueueItem>.from(_currentSession!.queue);
    if (oldIndex >= 0 &&
        oldIndex < newQueue.length &&
        newIndex >= 0 &&
        newIndex <= newQueue.length) {
      final item = newQueue.removeAt(oldIndex);
      newQueue.insert(newIndex, item);

      // Update local state first for instant feedback
      _currentSession = _currentSession!.copyWith(queue: newQueue);
      _sessionController.add(_currentSession);
      final stateVersion = _nextStateVersion();

      await _channel!.sendBroadcastMessage(
        event: 'queue',
        payload: {
          'queue': newQueue.map((t) => t.toJson()).toList(),
          'action': 'reorder',
          'stateVersion': stateVersion,
        },
      );
    }
  }

  /// Remove all songs added by a specific user (when they leave)
  Future<void> removeUserSongsFromQueue(String userId) async {
    if (_channel == null || _currentSession == null || !_isHost) return;

    final newQueue = _currentSession!.queue
        .where((item) => item.addedBy != userId)
        .toList();
    final stateVersion = _nextStateVersion();

    await _channel!.sendBroadcastMessage(
      event: 'queue',
      payload: {
        'queue': newQueue.map((t) => t.toJson()).toList(),
        'action': 'user_left',
        'userId': userId,
        'stateVersion': stateVersion,
      },
    );

    // Update local session
    _currentSession = _currentSession!.copyWith(queue: newQueue);
    _sessionController.add(_currentSession);
    if (kDebugMode) {
      print('JamsService: Removed songs from user $userId');
    }
  }

  /// Play a specific track from the queue by index
  /// Removes only that track from the queue, returns the track to play
  Future<JamQueueItem?> playFromQueueAt(int index) async {
    if (_channel == null || _currentSession == null) return null;
    if (index < 0 || index >= _currentSession!.queue.length) return null;

    final trackToPlay = _currentSession!.queue[index];
    // Remove only the tapped track, keep all others
    final newQueue = List<JamQueueItem>.from(_currentSession!.queue);
    newQueue.removeAt(index);
    final stateVersion = _nextStateVersion();

    await _channel!.sendBroadcastMessage(
      event: 'queue',
      payload: {
        'queue': newQueue.map((t) => t.toJson()).toList(),
        'action': 'play_at',
        'playedIndex': index,
        'stateVersion': stateVersion,
      },
    );

    // Update local session
    _currentSession = _currentSession!.copyWith(queue: newQueue);
    _sessionController.add(_currentSession);

    return trackToPlay;
  }

  /// Pop the first item from queue (when a song finishes)
  Future<JamQueueItem?> popNextFromQueue() async {
    if (_channel == null || _currentSession == null) return null;
    if (_currentSession!.queue.isEmpty) return null;

    final nextItem = _currentSession!.queue.first;
    final newQueue = _currentSession!.queue.skip(1).toList();
    final stateVersion = _nextStateVersion();

    await _channel!.sendBroadcastMessage(
      event: 'queue',
      payload: {
        'queue': newQueue.map((t) => t.toJson()).toList(),
        'action': 'pop_next',
        'stateVersion': stateVersion,
      },
    );

    // Update local session
    _currentSession = _currentSession!.copyWith(queue: newQueue);
    _sessionController.add(_currentSession);

    return nextItem;
  }

  // ============ Event Handlers ============

  void _handlePlaybackBroadcast(Map<String, dynamic> payload) {
    // Get who sent this broadcast
    final controllerId = payload['controllerId'] as String?;

    // Skip if this is our own broadcast (echo prevention)
    // But DO apply broadcasts from other controllers - "last controller wins"
    if (controllerId == oderId) {
      return;
    }
    _markInboundRealtime('playback');

    if (kDebugMode) {
      print(
        'JamsService: [PARTICIPANT] Received playback broadcast from $controllerId!',
      );
    }

    try {
      final incomingVersion = _extractStateVersion(payload);
      if (_isStaleStateVersion(incomingVersion)) {
        if (kDebugMode) {
          print(
            'JamsService: Ignoring stale playback state v$incomingVersion (< $_lastAppliedStateVersion)',
          );
        }
        return;
      }
      _markAppliedStateVersion(incomingVersion);

      final playback = JamPlaybackState(
        currentTrack: payload['track'] != null
            ? JamTrack.fromJson(payload['track'] as Map<String, dynamic>)
            : null,
        positionMs: payload['positionMs'] as int? ?? 0,
        isPlaying: payload['isPlaying'] as bool? ?? false,
        syncedAt: DateTime.parse(payload['syncedAt'] as String),
      );

      if (kDebugMode) {
        print(
          'JamsService: [PARTICIPANT] isPlaying=${playback.isPlaying}, position=${playback.positionMs}ms',
        );
      }

      // Update session
      if (_currentSession != null) {
        _currentSession = _currentSession!.copyWith(playbackState: playback);
        _sessionController.add(_currentSession);
      }

      _playbackController.add(playback);
      // Reduced logging - only log track changes
      if (_lastBroadcastTrackTitle != playback.currentTrack?.title) {
        _lastBroadcastTrackTitle = playback.currentTrack?.title;
        if (kDebugMode) {
          print('JamsService: Now playing - ${playback.currentTrack?.title}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('JamsService: Playback parse error: $e');
      }
    }
  }

  // Track last broadcast for reduced logging
  String? _lastBroadcastTrackTitle;

  void _handleQueueBroadcast(Map<String, dynamic> payload) {
    _markInboundRealtime('queue');
    try {
      final incomingVersion = _extractStateVersion(payload);
      if (_isStaleStateVersion(incomingVersion)) {
        if (kDebugMode) {
          print(
            'JamsService: Ignoring stale queue state v$incomingVersion (< $_lastAppliedStateVersion)',
          );
        }
        return;
      }
      _markAppliedStateVersion(incomingVersion);

      final queueData = payload['queue'];
      final List<JamQueueItem> queue;

      if (queueData == null) {
        queue = [];
      } else {
        queue = (queueData as List)
            .map((t) => JamQueueItem.fromJson(t as Map<String, dynamic>))
            .toList();
      }

      if (_currentSession != null) {
        _currentSession = _currentSession!.copyWith(queue: queue);
        _sessionController.add(_currentSession);
      }
      if (kDebugMode) {
        print('JamsService: Queue updated - ${queue.length} tracks');
      }
    } catch (e) {
      if (kDebugMode) {
        print('JamsService: Queue parse error: $e');
      }
    }
  }

  void _handleHostTransfer(Map<String, dynamic> payload) {
    _markInboundRealtime('host_transfer');
    try {
      final incomingVersion = _extractStateVersion(payload);
      if (_isStaleStateVersion(incomingVersion)) {
        if (kDebugMode) {
          print(
            'JamsService: Ignoring stale host_transfer v$incomingVersion (< $_lastAppliedStateVersion)',
          );
        }
        return;
      }
      _markAppliedStateVersion(incomingVersion);

      final newHostId = payload['newHostId'] as String;
      final newHostName = payload['newHostName'] as String;

      final wasHost = _isHost;

      // Update my host status
      if (newHostId == oderId) {
        _isHost = true;
        if (kDebugMode) {
          print('JamsService: I am now the host!');
        }
      } else if (_isHost) {
        // I was the host, but now someone else is
        _isHost = false;
        if (kDebugMode) {
          print('JamsService: I am no longer the host');
        }
      }

      // Update participant isHost flags
      for (final entry in _participants.entries) {
        _participants[entry.key] = entry.value.copyWith(
          isHost: entry.key == newHostId,
        );
      }

      // Update session with new host and refreshed participants
      _updateSessionParticipants(newHostId, newHostName);

      // Notify about host role change (for sync controller to restart)
      if (wasHost != _isHost) {
        _hostRoleChangeController.add(_isHost);
      }

      if (kDebugMode) {
        print('JamsService: Host transferred to $newHostName');
      }
    } catch (e) {
      if (kDebugMode) {
        print('JamsService: Host transfer error: $e');
      }
    }
  }

  void _handlePermissionUpdate(Map<String, dynamic> payload) {
    _markInboundRealtime('permission_update');
    try {
      final incomingVersion = _extractStateVersion(payload);
      if (_isStaleStateVersion(incomingVersion)) {
        if (kDebugMode) {
          print(
            'JamsService: Ignoring stale permission_update v$incomingVersion (< $_lastAppliedStateVersion)',
          );
        }
        return;
      }
      _markAppliedStateVersion(incomingVersion);

      final participantId = payload['participantId'] as String;
      final canControl = payload['canControlPlayback'] as bool? ?? false;

      // Check if this is for me
      if (participantId == oderId) {
        _canControlPlayback = canControl;
        if (kDebugMode) {
          print('JamsService: My control permission updated to: $canControl');
        }
        _permissionChangeController.add(canControl);
      }

      // Update participant state
      if (_participants.containsKey(participantId)) {
        _participants[participantId] = _participants[participantId]!.copyWith(
          canControlPlayback: canControl,
        );
        _updateSessionParticipants(null, null);
      }
    } catch (e) {
      if (kDebugMode) {
        print('JamsService: Permission update error: $e');
      }
    }
  }

  void _handleSessionEnd(Map<String, dynamic> payload) {
    final incomingVersion = _extractStateVersion(payload);
    if (_isStaleStateVersion(incomingVersion)) {
      return;
    }
    _markAppliedStateVersion(incomingVersion);

    final reason = payload['reason'] as String? ?? 'Session ended';
    if (kDebugMode) {
      print('JamsService: Session ended - $reason');
    }

    _isLeavingSession = true;
    _cancelReconnectTimer();
    _emitConnectionState(JamConnectionState.disconnected(reason: reason));
    _currentSessionCode = null;
    _currentSession = null;
    _isHost = false;
    _participants.clear();
    _cancelHostDisconnectTimer();
    _cancelAllParticipantDisconnectTimers();
    _sessionController.add(null);
    _errorController.add(reason);

    _channel?.unsubscribe();
    _channel = null;
    unawaited(_backgroundService.onSessionLeft());
    _backgroundService.detachService();
  }

  void _handleStateRequest(Map<String, dynamic> payload) {
    _markInboundRealtime('state_request');
    if (!_isHost || _channel == null || _currentSession == null) return;

    final requesterId = payload['requesterId'] as String?;
    if (requesterId == null || requesterId == oderId) return;

    if (kDebugMode) {
      print('JamsService: State snapshot requested by $requesterId');
    }
    unawaited(
      _broadcastStateSnapshot(
        targetRequesterId: requesterId,
        reason: payload['reason'] as String? ?? 'state_request',
      ),
    );
  }

  void _handleStateSnapshot(Map<String, dynamic> payload) {
    _markInboundRealtime('state_snapshot');
    final senderId = payload['senderId'] as String?;
    if (senderId == oderId) return;

    final targetRequesterId = payload['targetRequesterId'] as String?;
    if (targetRequesterId != null && targetRequesterId != oderId) return;

    final incomingVersion = _extractStateVersion(payload);
    if (_isStaleStateVersion(incomingVersion)) {
      return;
    }

    final sessionJson = payload['session'] as Map<String, dynamic>?;
    if (sessionJson == null) return;

    try {
      final snapshot = JamSession.fromJson(sessionJson);
      final wasHost = _isHost;
      final wasCanControl = _canControlPlayback;

      _currentSessionCode = snapshot.sessionCode;
      _currentSession = snapshot;

      _participants
        ..clear()
        ..addEntries(snapshot.participants.map((p) => MapEntry(p.id, p)));
      _cancelHostDisconnectTimer();
      _cancelAllParticipantDisconnectTimers();

      final me = snapshot.participants.where((p) => p.id == oderId).firstOrNull;
      _isHost = snapshot.hostId == oderId;
      _canControlPlayback = me?.canControlPlayback ?? false;

      _markAppliedStateVersion(incomingVersion);
      _sessionController.add(snapshot);
      _playbackController.add(snapshot.playbackState);

      if (wasHost != _isHost) {
        _hostRoleChangeController.add(_isHost);
      }
      if (wasCanControl != _canControlPlayback) {
        _permissionChangeController.add(_canControlPlayback);
      }

      if (kDebugMode) {
        print(
          'JamsService: Applied state snapshot v$incomingVersion from $senderId',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('JamsService: Failed to apply state snapshot: $e');
      }
    }
  }

  void _handlePresenceSync() {
    if (_channel == null) return;
    _markInboundRealtime('presence_sync');

    final presenceState = _channel!.presenceState();

    // Debug: log raw presence state
    if (kDebugMode) {
      print('JamsService: Raw presence state count: ${presenceState.length}');
    }
    for (int i = 0; i < presenceState.length; i++) {
      final state = presenceState[i];
      if (kDebugMode) {
        print('JamsService: Presence[$i] presences: ${state.presences.length}');
      }
      for (final p in state.presences) {
        if (kDebugMode) {
          print('JamsService: - User: ${p.payload['user_name']}');
        }
      }
    }

    // Empty snapshots can happen briefly during reconnect/background transitions.
    // Apply disconnect grace instead of dropping participants immediately.
    if (presenceState.isEmpty && _participants.isNotEmpty) {
      final expectedHostId = _currentSession?.hostId;
      for (final participantId in _participants.keys.toList()) {
        _scheduleParticipantDisconnect(participantId, wasHost: false);
      }
      if (expectedHostId != null &&
          !_isHost &&
          _participants.containsKey(expectedHostId)) {
        _startHostDisconnectTimer(expectedHostId);
      }
      _updateSessionParticipants(null, null);
      if (kDebugMode) {
        print(
          'JamsService: Presence sync empty - scheduled grace disconnect timers',
        );
      }
      return;
    }

    final newParticipants = <String, JamParticipant>{};
    String? hostId;
    String? hostName;

    // presenceState is a List<SinglePresenceState>
    // Each SinglePresenceState has a key and a list of Presence objects
    for (final singleState in presenceState) {
      for (final presence in singleState.presences) {
        final data = presence.payload;
        final participant = JamParticipant(
          id: data['user_id'] as String,
          name: data['user_name'] as String,
          photoUrl: data['photo_url'] as String?,
          isHost: data['is_host'] as bool? ?? false,
          joinedAt: DateTime.parse(data['joined_at'] as String),
        );
        newParticipants[participant.id] = participant;

        if (participant.isHost) {
          hostId = participant.id;
          hostName = participant.name;
        }
      }
    }

    // Only update if we got participants, or we're intentionally clearing
    if (newParticipants.isNotEmpty) {
      final previousIds = _participants.keys.toSet();
      final newIds = newParticipants.keys.toSet();

      // Upsert live presences and cancel any pending disconnect grace timers.
      for (final entry in newParticipants.entries) {
        _participants[entry.key] = entry.value;
        _cancelParticipantDisconnectTimer(entry.key);
      }

      // Presence may momentarily drop while app/network transitions.
      // Keep participant visible until grace expires.
      for (final missingId in previousIds.difference(newIds)) {
        final wasHost =
            _participants[missingId]?.isHost ??
            (missingId == _currentSession?.hostId);
        _scheduleParticipantDisconnect(missingId, wasHost: false);
        if (wasHost && !_isHost) {
          _startHostDisconnectTimer(missingId);
        }
      }

      _updateSessionParticipants(hostId, hostName);

      final expectedHostId = _currentSession?.hostId;
      final hostPresent =
          hostId != null ||
          (expectedHostId != null && newIds.contains(expectedHostId));
      if (hostPresent) {
        _cancelHostDisconnectTimer();
      } else if (expectedHostId != null && !_isHost) {
        _startHostDisconnectTimer(expectedHostId);
      }
    }

    if (kDebugMode) {
      print(
        'JamsService: Presence sync - ${_participants.length} participants',
      );
    }
  }

  void _handlePresenceJoin(List<Presence> newPresences) async {
    _markInboundRealtime('presence_join');
    try {
      String? hostId;
      String? hostName;

      for (final presence in newPresences) {
        final data = presence.payload;
        final participant = JamParticipant(
          id: data['user_id'] as String,
          name: data['user_name'] as String,
          photoUrl: data['photo_url'] as String?,
          isHost: data['is_host'] as bool? ?? false,
          joinedAt: DateTime.parse(data['joined_at'] as String),
        );
        _participants[participant.id] = participant;
        _cancelParticipantDisconnectTimer(participant.id);

        if (participant.isHost) {
          hostId = participant.id;
          hostName = participant.name;
        }
      }

      _updateSessionParticipants(hostId, hostName);
      final expectedHostId = _currentSession?.hostId;
      final hostPresent =
          hostId != null ||
          (expectedHostId != null && _participants.containsKey(expectedHostId));
      if (hostPresent) {
        _cancelHostDisconnectTimer();
      }
      if (kDebugMode) {
        print(
          'JamsService: Participant joined - ${_participants.length} total',
        );
      }

      // If I'm the host, broadcast current queue to sync new participant
      if (_isHost &&
          _currentSession != null &&
          _currentSession!.queue.isNotEmpty) {
        await _channel?.sendBroadcastMessage(
          event: 'queue',
          payload: {
            'queue': _currentSession!.queue.map((t) => t.toJson()).toList(),
          },
        );
      }

      if (_isHost) {
        for (final presence in newPresences) {
          final requesterId = presence.payload['user_id'] as String?;
          if (requesterId != null && requesterId != oderId) {
            await _broadcastStateSnapshot(
              targetRequesterId: requesterId,
              reason: 'presence_join',
            );
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('JamsService: Presence join error: $e');
      }
    }
  }

  void _handlePresenceLeave(List<Presence> leftPresences) {
    _markInboundRealtime('presence_leave');
    try {
      String? disconnectedHostId;
      for (final presence in leftPresences) {
        final data = presence.payload;
        final userId = data['user_id'] as String;
        final wasHost =
            _participants[userId]?.isHost ??
            (userId == _currentSession?.hostId);
        _scheduleParticipantDisconnect(userId, wasHost: false);

        // Host presence can drop temporarily when app/network changes.
        // Keep the session alive and wait for host to reconnect.
        if (wasHost && !_isHost) {
          disconnectedHostId = userId;
        }
      }

      _updateSessionParticipants(null, null);
      if (disconnectedHostId != null) {
        _startHostDisconnectTimer(disconnectedHostId);
      }
      if (kDebugMode) {
        print('JamsService: Participant left - ${_participants.length} total');
      }
    } catch (e) {
      if (kDebugMode) {
        print('JamsService: Presence leave error: $e');
      }
    }
  }

  void _updateSessionParticipants(String? hostId, String? hostName) {
    if (_currentSessionCode == null) return;

    final participants = _participants.values.toList();
    final previousHostId = _currentSession?.hostId;
    final previousHostName = _currentSession?.hostName;
    final resolvedHostId =
        hostId ?? previousHostId ?? participants.firstOrNull?.id ?? oderId;
    final resolvedHostName =
        hostName ??
        participants.where((p) => p.id == resolvedHostId).firstOrNull?.name ??
        previousHostName ??
        userName;

    _currentSession = JamSession(
      sessionCode: _currentSessionCode!,
      hostId: resolvedHostId,
      hostName: resolvedHostName,
      participants: participants,
      playbackState:
          _currentSession?.playbackState ??
          JamPlaybackState(syncedAt: DateTime.now()),
      queue: _currentSession?.queue ?? [],
      createdAt: _currentSession?.createdAt ?? DateTime.now(),
    );

    _sessionController.add(_currentSession);

    if (_backgroundService.isServiceRunning) {
      unawaited(
        _backgroundService.updateNotification(
          _currentSessionCode!,
          _isHost,
          participants.length,
        ),
      );
    }
  }

  // ============ Cleanup ============

  void dispose() {
    _isLeavingSession = true;
    _cancelReconnectTimer();
    _backgroundService.detachService();
    leaveSession();
    _cancelHostDisconnectTimer();
    _cancelAllParticipantDisconnectTimers();
    _sessionController.close();
    _playbackController.close();
    _errorController.close();
    _connectionStateController.close();
    _hostRoleChangeController.close();
    _permissionChangeController.close();
  }
}
