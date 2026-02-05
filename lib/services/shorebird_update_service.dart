import 'package:flutter/foundation.dart' show kReleaseMode, kDebugMode;
import 'package:shorebird_code_push/shorebird_code_push.dart';

/// Lightweight wrapper for Shorebird OTA updates.
/// Checks for updates in release builds and installs them silently.
class ShorebirdUpdateService {
  ShorebirdUpdateService._();

  static final ShorebirdUpdateService instance = ShorebirdUpdateService._();

  final ShorebirdUpdater _updater = ShorebirdUpdater();

  Future<bool> checkForUpdates() async {
    if (!kReleaseMode) {
      if (kDebugMode) {
        // Skip OTA in debug/profile builds to avoid confusion.
        print('Shorebird: Skipping update check (not release build)');
      }
      return false;
    }

    try {
      final status = await _updater.checkForUpdate();
      if (status == UpdateStatus.outdated) {
        if (kDebugMode) {
          print('Shorebird: Update available, downloading...');
        }
        await _updater.update();
        if (kDebugMode) {
          print('Shorebird: Update installed (applies on next restart)');
        }
        return true;
      } else {
        if (kDebugMode) {
          print('Shorebird: No update available');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Shorebird: Update check failed: $e');
      }
    }
    return false;
  }
}
