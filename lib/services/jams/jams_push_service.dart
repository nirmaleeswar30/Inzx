import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:http/http.dart' as http;
import 'jams_logger.dart';

/// Push notification service for Jams using ntfy.sh
///
/// This service sends push notifications for playback events
/// so participants can sync even when the app is in background.
///
/// Topics are formatted as: inzx-jams-{sessionCode}
class JamsPushService {
  static const String _ntfyBaseUrl = 'https://ntfy.sh';
  static const String _topicPrefix = 'inzx-jams';

  static final JamsPushService _instance = JamsPushService._internal();
  factory JamsPushService() => _instance;
  JamsPushService._internal();

  static JamsPushService get instance => _instance;

  String? _currentSessionCode;
  String? _userId;
  http.Client? _subscriptionClient;
  StreamSubscription? _streamSubscription;

  // Callback for received push events
  void Function(JamsPushEvent event)? onPushEvent;

  /// Get the topic name for a session
  String _getTopic(String sessionCode) =>
      '$_topicPrefix-${sessionCode.toLowerCase()}';

  /// Initialize for a session
  void initialize({required String sessionCode, required String userId}) {
    _currentSessionCode = sessionCode;
    _userId = userId;

    jamsLog(
      'Initialized push service for session $sessionCode',
      tag: 'PushService',
    );
  }

  /// Subscribe to push events for the current session
  /// Uses Server-Sent Events (SSE) for real-time updates
  Future<void> subscribe() async {
    if (_currentSessionCode == null) return;

    await unsubscribe(); // Clean up any existing subscription

    final topic = _getTopic(_currentSessionCode!);
    final url = '$_ntfyBaseUrl/$topic/sse';

    jamsLog('Subscribing to $url', tag: 'PushService');

    try {
      _subscriptionClient = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      final response = await _subscriptionClient!.send(request);

      if (response.statusCode == 200) {
        _streamSubscription = response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              (line) => _handleSSELine(line),
              onError: (error) {
                jamsError('SSE stream error', tag: 'PushService', error: error);
              },
              onDone: () {
                jamsLog('SSE stream closed', tag: 'PushService');
              },
            );

        jamsLog('Subscribed to push events', tag: 'PushService');
      } else {
        jamsError(
          'Failed to subscribe: ${response.statusCode}',
          tag: 'PushService',
        );
      }
    } catch (e) {
      jamsError('Subscribe error', tag: 'PushService', error: e);
    }
  }

  /// Handle SSE line from ntfy
  void _handleSSELine(String line) {
    if (line.isEmpty || line.startsWith(':')) return; // Skip keepalive/comments

    if (line.startsWith('data: ')) {
      final jsonStr = line.substring(6);
      try {
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;

        // ntfy SSE format has event type and message
        final eventType = data['event'] as String?;
        if (eventType != 'message') return; // Skip open/keepalive events

        final message = data['message'] as String?;
        if (message == null) return;

        // Parse the JSON message we sent
        final eventData = jsonDecode(message) as Map<String, dynamic>;

        // Skip our own messages (we put sender in the data)
        final senderId = eventData['senderId'] as String?;
        if (senderId == _userId) return;

        final event = JamsPushEvent.fromJson(eventData);

        jamsLog('Received push event: ${event.type}', tag: 'PushService');
        onPushEvent?.call(event);
      } catch (e) {
        // Not a valid JSON message, ignore
        jamsLog('SSE parse error: $e', tag: 'PushService');
      }
    }
  }

  /// Unsubscribe from push events
  Future<void> unsubscribe() async {
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    _subscriptionClient?.close();
    _subscriptionClient = null;

    jamsLog('Unsubscribed from push events', tag: 'PushService');
  }

  /// Send a push notification to all session participants
  Future<bool> sendEvent(JamsPushEvent event) async {
    if (_currentSessionCode == null) return false;

    final topic = _getTopic(_currentSessionCode!);
    final url = '$_ntfyBaseUrl/$topic';

    try {
      // Include senderId in the event data so we can filter our own messages
      final eventJson = event.toJson();
      eventJson['senderId'] = _userId;

      // ntfy expects: POST with message in body (plain text or JSON string)
      // The message will appear in the 'message' field when received
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Priority': event.priority,
          'Title': 'Jams Sync', // Optional title for notification
        },
        body: jsonEncode(eventJson), // JSON string becomes the message
      );

      if (response.statusCode == 200) {
        if (kDebugMode) {
          print('JamsPushService: Sent ${event.type} event');
        }
        return true;
      } else {
        jamsError(
          'Failed to send event: ${response.statusCode}',
          tag: 'PushService',
        );
        return false;
      }
    } catch (e) {
      jamsError('Send event error', tag: 'PushService', error: e);
      return false;
    }
  }

  /// Send playback state change
  Future<bool> sendPlaybackEvent({
    required String videoId,
    required String title,
    required String artist,
    String? thumbnailUrl,
    required int durationMs,
    required int positionMs,
    required bool isPlaying,
  }) async {
    return sendEvent(
      JamsPushEvent(
        type: JamsPushEventType.playback,
        data: {
          'videoId': videoId,
          'title': title,
          'artist': artist,
          'thumbnailUrl': thumbnailUrl,
          'durationMs': durationMs,
          'positionMs': positionMs,
          'isPlaying': isPlaying,
          'syncedAt': DateTime.now().toIso8601String(),
        },
      ),
    );
  }

  /// Send play event
  Future<bool> sendPlay({required int positionMs}) async {
    return sendEvent(
      JamsPushEvent(
        type: JamsPushEventType.play,
        data: {
          'positionMs': positionMs,
          'syncedAt': DateTime.now().toIso8601String(),
        },
      ),
    );
  }

  /// Send pause event
  Future<bool> sendPause({required int positionMs}) async {
    return sendEvent(
      JamsPushEvent(
        type: JamsPushEventType.pause,
        data: {
          'positionMs': positionMs,
          'syncedAt': DateTime.now().toIso8601String(),
        },
      ),
    );
  }

  /// Send seek event
  Future<bool> sendSeek({required int positionMs}) async {
    return sendEvent(
      JamsPushEvent(
        type: JamsPushEventType.seek,
        data: {
          'positionMs': positionMs,
          'syncedAt': DateTime.now().toIso8601String(),
        },
      ),
    );
  }

  /// Send track change event
  Future<bool> sendTrackChange({
    required String videoId,
    required String title,
    required String artist,
    String? thumbnailUrl,
    required int durationMs,
  }) async {
    return sendEvent(
      JamsPushEvent(
        type: JamsPushEventType.trackChange,
        data: {
          'videoId': videoId,
          'title': title,
          'artist': artist,
          'thumbnailUrl': thumbnailUrl,
          'durationMs': durationMs,
          'syncedAt': DateTime.now().toIso8601String(),
        },
      ),
    );
  }

  /// Clean up resources
  void dispose() {
    unsubscribe();
    _currentSessionCode = null;
    _userId = null;
  }
}

/// Types of push events
enum JamsPushEventType {
  playback, // Full playback state sync
  play, // Resume playback
  pause, // Pause playback
  seek, // Seek to position
  trackChange, // Track changed
  sessionEnd, // Session ended
}

/// Push event data
class JamsPushEvent {
  final JamsPushEventType type;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  JamsPushEvent({required this.type, required this.data, DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now();

  /// Priority for ntfy (affects delivery speed)
  String get priority {
    switch (type) {
      case JamsPushEventType.sessionEnd:
        return 'high';
      case JamsPushEventType.trackChange:
      case JamsPushEventType.play:
      case JamsPushEventType.pause:
        return 'default';
      case JamsPushEventType.seek:
      case JamsPushEventType.playback:
        return 'low';
    }
  }

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'data': data,
    'timestamp': timestamp.toIso8601String(),
  };

  factory JamsPushEvent.fromJson(Map<String, dynamic> json) {
    return JamsPushEvent(
      type: JamsPushEventType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => JamsPushEventType.playback,
      ),
      data: json['data'] as Map<String, dynamic>? ?? {},
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : null,
    );
  }
}
