import 'dart:convert';
import 'package:flutter/foundation.dart' show compute, kDebugMode;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

/// Queue persistence service
/// Saves and restores queue state across app restarts
class QueuePersistenceService {
  static const _queueKey = 'persisted_queue';
  static const _currentIndexKey = 'persisted_queue_index';
  static const _positionKey = 'persisted_position_ms';

  /// Save current queue state
  static Future<void> saveQueue({
    required List<Track> queue,
    required int currentIndex,
    required Duration position,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Save queue as JSON
      final queueJson = queue.map((t) => jsonEncode(t.toJson())).toList();
      await prefs.setStringList(_queueKey, queueJson);

      // Save current index
      await prefs.setInt(_currentIndexKey, currentIndex);

      // Save position
      await prefs.setInt(_positionKey, position.inMilliseconds);
    } catch (e) {
      if (kDebugMode) {print('Error saving queue: $e');}
    }
  }

  /// Load persisted queue state
  /// JSON parsing runs in background isolate to avoid UI jank
  static Future<PersistedQueueState?> loadQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final queueJson = prefs.getStringList(_queueKey);
      if (queueJson == null || queueJson.isEmpty) return null;

      // Parse queue in background isolate
      final queue = await compute(_parseQueueIsolate, queueJson);

      final currentIndex = prefs.getInt(_currentIndexKey) ?? 0;
      final positionMs = prefs.getInt(_positionKey) ?? 0;

      return PersistedQueueState(
        queue: queue,
        currentIndex: currentIndex.clamp(0, queue.length - 1),
        position: Duration(milliseconds: positionMs),
      );
    } catch (e) {
      if (kDebugMode) {print('Error loading queue: $e');}
      return null;
    }
  }

  /// Clear persisted queue
  static Future<void> clearQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_queueKey);
      await prefs.remove(_currentIndexKey);
      await prefs.remove(_positionKey);
    } catch (e) {
      if (kDebugMode) {print('Error clearing queue: $e');}
    }
  }

  /// Check if there's a persisted queue
  static Future<bool> hasPersistedQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_queueKey);
    return queue != null && queue.isNotEmpty;
  }
}

/// Persisted queue state data class
class PersistedQueueState {
  final List<Track> queue;
  final int currentIndex;
  final Duration position;

  const PersistedQueueState({
    required this.queue,
    required this.currentIndex,
    required this.position,
  });

  Track? get currentTrack => currentIndex >= 0 && currentIndex < queue.length
      ? queue[currentIndex]
      : null;
}

/// Top-level isolate function for parsing queue JSON
List<Track> _parseQueueIsolate(List<String> jsonList) {
  return jsonList
      .map((json) => Track.fromJson(jsonDecode(json) as Map<String, dynamic>))
      .toList();
}
