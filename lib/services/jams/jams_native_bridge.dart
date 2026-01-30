import 'dart:io';
import 'package:flutter/services.dart';
import 'jams_logger.dart';

/// Native platform channel bridge for Jams foreground service
///
/// This service shows a notification while in a Jam session
/// and keeps the app process alive with proper Android lifecycle.
class JamsNativeBridge {
  static const MethodChannel _methodChannel = MethodChannel('inzx/jams_native');

  static final JamsNativeBridge _instance = JamsNativeBridge._internal();
  factory JamsNativeBridge() => _instance;
  JamsNativeBridge._internal();

  static JamsNativeBridge get instance => _instance;

  /// Check if native service is supported (Android only)
  bool get isSupported => Platform.isAndroid;

  /// Check if native service is currently running
  Future<bool> isServiceRunning() async {
    if (!isSupported) return false;

    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'isServiceRunning',
      );
      return result ?? false;
    } catch (e) {
      jamsError('Error checking service status', tag: 'NativeBridge', error: e);
      return false;
    }
  }

  /// Start the native foreground service
  /// This keeps the app process alive with wake locks
  Future<bool> startService({
    required String sessionCode,
    required bool isHost,
    int participantCount = 1,
  }) async {
    if (!isSupported) {
      jamsLog(
        'Native service not supported on this platform',
        tag: 'NativeBridge',
      );
      return false;
    }

    jamsLog(
      '>>> Starting foreground service for $sessionCode, isHost=$isHost',
      tag: 'NativeBridge',
    );

    try {
      final result = await _methodChannel.invokeMethod<bool>('startService', {
        'sessionCode': sessionCode,
        'isHost': isHost,
        'participantCount': participantCount,
      });

      jamsLog(
        '>>> Foreground service startService returned: $result',
        tag: 'NativeBridge',
      );

      return result ?? false;
    } catch (e, stackTrace) {
      jamsError(
        'Error starting service',
        tag: 'NativeBridge',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Stop the native foreground service
  Future<bool> stopService() async {
    if (!isSupported) return false;

    try {
      final result = await _methodChannel.invokeMethod<bool>('stopService');
      jamsLog('Foreground service stopped: $result', tag: 'NativeBridge');
      return result ?? false;
    } catch (e) {
      jamsError('Error stopping service', tag: 'NativeBridge', error: e);
      return false;
    }
  }

  /// Update the notification with participant count
  Future<bool> updateNotification({
    required String sessionCode,
    required bool isHost,
    required int participantCount,
  }) async {
    if (!isSupported) return false;

    try {
      final result = await _methodChannel
          .invokeMethod<bool>('updateNotification', {
            'sessionCode': sessionCode,
            'isHost': isHost,
            'participantCount': participantCount,
          });

      jamsLog(
        'Notification updated: $participantCount participants',
        tag: 'NativeBridge',
      );

      return result ?? false;
    } catch (e) {
      jamsError('Error updating notification', tag: 'NativeBridge', error: e);
      return false;
    }
  }

  /// Dispose the bridge (no-op in simplified version)
  void dispose() {
    // Nothing to dispose in simplified version
  }

  /// Check if app is exempt from battery optimization
  Future<bool> isBatteryOptimizationExempt() async {
    if (!isSupported) return true; // Not applicable on iOS

    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'isBatteryOptimizationExempt',
      );
      return result ?? false;
    } catch (e) {
      jamsError(
        'Error checking battery optimization',
        tag: 'NativeBridge',
        error: e,
      );
      return false;
    }
  }

  /// Request battery optimization exemption
  /// Returns true if already exempt, false if dialog was shown
  Future<bool> requestBatteryOptimizationExemption() async {
    if (!isSupported) return true; // Not applicable on iOS

    try {
      jamsLog(
        'Requesting battery optimization exemption...',
        tag: 'NativeBridge',
      );
      final result = await _methodChannel.invokeMethod<bool>(
        'requestBatteryOptimizationExemption',
      );
      jamsLog('Battery exemption result: $result', tag: 'NativeBridge');
      return result ?? false;
    } catch (e) {
      jamsError(
        'Error requesting battery exemption',
        tag: 'NativeBridge',
        error: e,
      );
      return false;
    }
  }
}
