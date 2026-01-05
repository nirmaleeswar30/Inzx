import 'package:flutter/foundation.dart';

/// Centralized logger that only outputs in debug mode.
/// In release builds, all logs are no-ops (zero overhead).
///
/// Usage:
///   Log.i('MyService', 'Initializing...');
///   Log.success('Operation completed');
///   Log.e('MyService', 'Failed', error);
///
/// Why this matters:
/// - Regular print() runs even in release builds
/// - 498+ prints at startup = cumulative UI jank
/// - kDebugMode check is compile-time constant, so release builds
///   completely eliminate the logging code (tree shaking)
class Log {
  Log._();

  /// Enable/disable verbose debug logging (even in debug mode)
  /// Set to false to reduce noise during development
  static bool verbose = true;

  /// General info log
  static void i(String tag, String message) {
    if (kDebugMode) {
      debugPrint('$tag: $message');
    }
  }

  /// Success log (with ✅)
  static void success(String message) {
    if (kDebugMode) {
      debugPrint('✅ $message');
    }
  }

  /// Warning log (with ⚠️)
  static void w(String tag, String message) {
    if (kDebugMode) {
      debugPrint('⚠️ $tag: $message');
    }
  }

  /// Error log (with ❌) - always logs even if verbose=false
  static void e(String tag, String message, [Object? error]) {
    if (kDebugMode) {
      if (error != null) {
        debugPrint('❌ $tag: $message - $error');
      } else {
        debugPrint('❌ $tag: $message');
      }
    }
  }

  /// Debug-only detailed/verbose log
  /// Only outputs if verbose=true (for noisy debug info)
  static void d(String tag, String message) {
    if (kDebugMode && verbose) {
      debugPrint('[$tag] $message');
    }
  }
}
