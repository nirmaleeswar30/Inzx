import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'jams_models.dart';

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
  final _hostRoleChangeController =
      StreamController<bool>.broadcast(); // Notifies when host role changes
  final _permissionChangeController =
      StreamController<
        bool
      >.broadcast(); // Notifies when control permission changes

  // Presence state
  final Map<String, JamParticipant> _participants = {};

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
  Stream<bool> get hostRoleChangeStream => _hostRoleChangeController.stream;
  Stream<bool> get permissionChangeStream => _permissionChangeController.stream;

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
      _currentSessionCode = code.toUpperCase();
      _isHost = false;

      await _joinChannel(_currentSessionCode!);

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

    // Track presence (who's in the session)
    _channel!.onPresenceSync((payload) => _handlePresenceSync());
    _channel!.onPresenceJoin(
      (payload) => _handlePresenceJoin(payload.newPresences),
    );
    _channel!.onPresenceLeave(
      (payload) => _handlePresenceLeave(payload.leftPresences),
    );

    // Subscribe to channel
    await _channel!.subscribe((status, error) async {
      if (kDebugMode) {
        print('JamsService: Channel status: $status');
      }
      if (status == RealtimeSubscribeStatus.subscribed) {
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
      }
    });
  }

  /// Leave the current session
  Future<void> leaveSession() async {
    if (_channel == null) return;

    try {
      // If host, broadcast session end
      if (_isHost) {
        await _channel!.sendBroadcastMessage(
          event: 'session_end',
          payload: {'reason': 'Host left'},
        );
      }

      await _channel!.untrack();
      await _channel!.unsubscribe();
      _channel = null;
    } catch (e) {
      if (kDebugMode) {
        print('JamsService: Leave session error: $e');
      }
    }

    _currentSessionCode = null;
    _currentSession = null;
    _isHost = false;
    _canControlPlayback = false;
    _participants.clear();
    _sessionController.add(null);
    if (kDebugMode) {
      print('JamsService: Left session');
    }
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
      await _channel!.sendBroadcastMessage(
        event: 'host_transfer',
        payload: {'newHostId': newHostId, 'newHostName': newHost.name},
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
      await _channel!.sendBroadcastMessage(
        event: 'permission_update',
        payload: {
          'participantId': participantId,
          'canControlPlayback': canControl,
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

    await _channel!.sendBroadcastMessage(
      event: 'queue',
      payload: {
        'queue': items.map((t) => t.toJson()).toList(),
        'action': 'initialize',
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

    await _channel!.sendBroadcastMessage(
      event: 'queue',
      payload: {
        'queue': newQueue.map((t) => t.toJson()).toList(),
        'action': 'append',
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

    await _channel!.sendBroadcastMessage(
      event: 'queue',
      payload: {
        'queue': newQueue.map((t) => t.toJson()).toList(),
        'addedBy': oderId,
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

    await _channel!.sendBroadcastMessage(
      event: 'queue',
      payload: {
        'queue': newQueue.map((t) => t.toJson()).toList(),
        'addedBy': oderId,
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

      await _channel!.sendBroadcastMessage(
        event: 'queue',
        payload: {'queue': newQueue.map((t) => t.toJson()).toList()},
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

      await _channel!.sendBroadcastMessage(
        event: 'queue',
        payload: {
          'queue': newQueue.map((t) => t.toJson()).toList(),
          'action': 'reorder',
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

    await _channel!.sendBroadcastMessage(
      event: 'queue',
      payload: {
        'queue': newQueue.map((t) => t.toJson()).toList(),
        'action': 'user_left',
        'userId': userId,
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

    await _channel!.sendBroadcastMessage(
      event: 'queue',
      payload: {
        'queue': newQueue.map((t) => t.toJson()).toList(),
        'action': 'play_at',
        'playedIndex': index,
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

    await _channel!.sendBroadcastMessage(
      event: 'queue',
      payload: {
        'queue': newQueue.map((t) => t.toJson()).toList(),
        'action': 'pop_next',
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

    if (kDebugMode) {
      print(
        'JamsService: [PARTICIPANT] Received playback broadcast from $controllerId!',
      );
    }

    try {
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
    try {
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
    try {
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
    try {
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
    final reason = payload['reason'] as String? ?? 'Session ended';
    if (kDebugMode) {
      print('JamsService: Session ended - $reason');
    }

    _currentSessionCode = null;
    _currentSession = null;
    _isHost = false;
    _participants.clear();
    _sessionController.add(null);
    _errorController.add(reason);

    _channel?.unsubscribe();
    _channel = null;
  }

  void _handlePresenceSync() {
    if (_channel == null) return;

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

    // Don't clear if new state is empty but we already have participants
    // This handles race conditions during initial sync
    if (presenceState.isEmpty && _participants.isNotEmpty) {
      if (kDebugMode) {
        print(
          'JamsService: Presence sync skipped - empty state but have participants',
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
      _participants.clear();
      _participants.addAll(newParticipants);
      _updateSessionParticipants(hostId, hostName);
    }

    if (kDebugMode) {
      print(
        'JamsService: Presence sync - ${_participants.length} participants',
      );
    }
  }

  void _handlePresenceJoin(List<Presence> newPresences) async {
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

        if (participant.isHost) {
          hostId = participant.id;
          hostName = participant.name;
        }
      }

      _updateSessionParticipants(hostId, hostName);
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
    } catch (e) {
      if (kDebugMode) {
        print('JamsService: Presence join error: $e');
      }
    }
  }

  void _handlePresenceLeave(List<Presence> leftPresences) {
    try {
      for (final presence in leftPresences) {
        final data = presence.payload;
        final userId = data['user_id'] as String;
        final wasHost = _participants[userId]?.isHost ?? false;
        _participants.remove(userId);

        // If host left, end session
        if (wasHost && !_isHost) {
          _handleSessionEnd({'reason': 'Host left the session'});
          return;
        }

        // If I'm the host, remove leaving user's songs from queue
        if (_isHost) {
          removeUserSongsFromQueue(userId);
        }
      }

      _updateSessionParticipants(null, null);
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

    // Find host info from participants if not provided
    final host = participants.firstWhere(
      (p) => p.isHost,
      orElse: () => participants.isNotEmpty
          ? participants.first
          : JamParticipant(
              id: oderId,
              name: userName,
              isHost: true,
              joinedAt: DateTime.now(),
            ),
    );

    _currentSession = JamSession(
      sessionCode: _currentSessionCode!,
      hostId: hostId ?? host.id,
      hostName: hostName ?? host.name,
      participants: participants,
      playbackState:
          _currentSession?.playbackState ??
          JamPlaybackState(syncedAt: DateTime.now()),
      queue: _currentSession?.queue ?? [],
      createdAt: _currentSession?.createdAt ?? DateTime.now(),
    );

    _sessionController.add(_currentSession);
  }

  // ============ Cleanup ============

  void dispose() {
    leaveSession();
    _sessionController.close();
    _playbackController.close();
    _errorController.close();
    _hostRoleChangeController.close();
  }
}
