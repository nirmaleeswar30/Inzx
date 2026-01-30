import 'dart:async';
import 'package:flutter/widgets.dart';
import 'jams_native_bridge.dart';
import 'jams_logger.dart';

/// Background service for keeping Jams connection alive
///
/// Uses native Kotlin foreground service to show a notification
/// while the user is in a Jam session.
class JamsBackgroundService with WidgetsBindingObserver {
  static final JamsBackgroundService _instance =
      JamsBackgroundService._internal();
  factory JamsBackgroundService() => _instance;
  JamsBackgroundService._internal();

  static JamsBackgroundService get instance => _instance;

  final JamsNativeBridge _nativeBridge = JamsNativeBridge.instance;

  bool _isInBackground = false;
  bool _isServiceRunning = false;
  int _currentParticipantCount = 1;

  /// Initialize the background service
  Future<void> initialize() async {
    // Initialize the logger first
    await JamsLogger.instance.init();

    // Print log file location for debugging
    await JamsLogger.instance.printLogInfo();

    // Register lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    jamsLog(
      'Initialized (native=${_nativeBridge.isSupported})',
      tag: 'BackgroundService',
    );
  }

  /// Attach to a JamsService instance (no-op in simplified version)
  void attachService(dynamic service) {
    // No-op - the native service only keeps the process alive
  }

  /// Detach from the JamsService
  void detachService() {
    stopService();
  }

  /// Called when entering a Jam session - start native foreground service
  Future<void> onSessionJoined({
    required String sessionCode,
    required String oderId,
    required String userName,
    String? userPhotoUrl,
    required bool isHost,
    int participantCount = 1,
  }) async {
    _currentParticipantCount = participantCount;

    jamsLog(
      '>>> Session joined - $sessionCode, isHost=$isHost, user=$userName',
      tag: 'BackgroundService',
    );

    if (_nativeBridge.isSupported) {
      // Check and request battery optimization exemption
      final isExempt = await _nativeBridge.isBatteryOptimizationExempt();
      jamsLog(
        '>>> Battery optimization exempt: $isExempt',
        tag: 'BackgroundService',
      );

      if (!isExempt) {
        jamsLog(
          '>>> Requesting battery optimization exemption...',
          tag: 'BackgroundService',
        );
        await _nativeBridge.requestBatteryOptimizationExemption();
      }

      jamsLog(
        '>>> Calling nativeBridge.startService...',
        tag: 'BackgroundService',
      );

      _isServiceRunning = await _nativeBridge.startService(
        sessionCode: sessionCode,
        isHost: isHost,
        participantCount: participantCount,
      );

      jamsLog(
        '>>> Foreground service started: $_isServiceRunning',
        tag: 'BackgroundService',
      );
    } else {
      jamsLog('>>> Native bridge not supported!', tag: 'BackgroundService');
    }
  }

  /// Called when leaving a Jam session - stop native service
  Future<void> onSessionLeft() async {
    jamsLog('Session left', tag: 'BackgroundService');

    _currentParticipantCount = 1;
    await stopService();
  }

  /// Stop the background service
  Future<void> stopService() async {
    if (_nativeBridge.isSupported && _isServiceRunning) {
      await _nativeBridge.stopService();
      _isServiceRunning = false;
      jamsLog('Foreground service stopped', tag: 'BackgroundService');
    }
  }

  /// Update notification with participant count
  Future<void> updateNotification(
    String sessionCode,
    bool isHost,
    int participantCount,
  ) async {
    _currentParticipantCount = participantCount;

    if (!_nativeBridge.isSupported || !_isServiceRunning) {
      return;
    }

    await _nativeBridge.updateNotification(
      sessionCode: sessionCode,
      isHost: isHost,
      participantCount: participantCount,
    );
  }

  /// Handle app lifecycle changes
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    jamsLog(
      'Lifecycle state: $state, isServiceRunning=$_isServiceRunning',
      tag: 'BackgroundService',
    );

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _isInBackground = true;
        break;

      case AppLifecycleState.resumed:
        _isInBackground = false;
        break;

      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  bool get isServiceRunning => _isServiceRunning;
  bool get isInBackground => _isInBackground;
  int get currentParticipantCount => _currentParticipantCount;

  /// Dispose the background service
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nativeBridge.dispose();
  }
}

/// Widget wrapper for WillStartForegroundTask (kept for compatibility)
class JamsForegroundTaskWrapper extends StatelessWidget {
  final Widget child;

  const JamsForegroundTaskWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // Native service handles foreground task, no wrapper needed
    return child;
  }
}
