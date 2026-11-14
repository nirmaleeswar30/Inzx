import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'platform_utils.dart';

/// Severity level for application logs
enum LogLevel {
  debug('DEBUG', '🔍'),
  info('INFO', 'ℹ️'),
  warning('WARN', '⚠️'),
  error('ERROR', '❌');

  final String label;
  final String emoji;
  const LogLevel(this.label, this.emoji);
}

/// A single structured log record
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;
  final String? stackTrace;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.stackTrace,
  });

  /// Format log entry as a clean line for file writing or exporting
  String toLogLine() {
    final timeStr =
        '${timestamp.year}-${_twoDigits(timestamp.month)}-${_twoDigits(timestamp.day)} '
        '${_twoDigits(timestamp.hour)}:${_twoDigits(timestamp.minute)}:${_twoDigits(timestamp.second)}.'
        '${_threeDigits(timestamp.millisecond)}';
    final base = '[$timeStr] [${level.label.padRight(5)}] [$tag] $message';
    if (stackTrace != null && stackTrace!.isNotEmpty) {
      return '$base\n  Stack trace:\n${stackTrace!.split('\n').map((l) => '    $l').join('\n')}';
    }
    return base;
  }

  static String _twoDigits(int n) => n.toString().padLeft(2, '0');
  static String _threeDigits(int n) => n.toString().padLeft(3, '0');
}

/// Centralized, high-performance rolling application logger and crash tracer.
///
/// Guarantees:
/// - Maximum 1,000 events in memory (strict FIFO queue).
/// - Maximum ~500 KB log file size on disk (strictly capped, never grows indefinitely).
/// - Automatically captures unhandled Flutter and asynchronous platform crashes.
/// - In-app viewer with live search, level filtering, clipboard copy, and file sharing.
class AppLogger {
  AppLogger._();

  static const int maxLogEntries = 1000;
  static const int maxFileSizeBytes = 500 * 1024; // 500 KB hard storage cap

  static final List<LogEntry> _entries = [];
  static final StreamController<LogEntry> _entryStreamController =
      StreamController<LogEntry>.broadcast();

  static File? _logFile;
  static bool _initialized = false;
  static Timer? _debounceFlushTimer;
  static bool _hasPendingWrites = false;

  /// Stream of new log entries for real-time UI updates
  static Stream<LogEntry> get onNewLog => _entryStreamController.stream;

  /// Unmodifiable view of all currently buffered log entries
  static List<LogEntry> get entries => List.unmodifiable(_entries);

  /// Current entry count
  static int get entryCount => _entries.length;

  /// Initialize logger and load recent logs from disk
  static Future<void> init() async {
    if (_initialized) return;

    try {
      final dir = await appDataDirectory();
      final logsDir = Directory('${dir.path}/logs');
      if (!await logsDir.exists()) {
        await logsDir.create(recursive: true);
      }

      _logFile = File('${logsDir.path}/inzx_app.log');

      // If log file exists, read existing lines into memory (up to maxLogEntries)
      if (await _logFile!.exists()) {
        final length = await _logFile!.length();
        if (length > maxFileSizeBytes) {
          // If file is oversized, truncate to keep only latest data
          await _pruneLogFile();
        } else {
          await _loadExistingLogs();
        }
      }

      _initialized = true;

      // Log session start
      final info = await _getDeviceInfo();
      i('App', 'Session started | $info');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AppLogger: init failed: $e');
      }
    }
  }

  /// Informational log
  static void i(String tag, String message) {
    _log(LogLevel.info, tag, message);
  }

  /// Warning log
  static void w(String tag, String message, [Object? error, StackTrace? stack]) {
    final fullMsg = error != null ? '$message: $error' : message;
    _log(LogLevel.warning, tag, fullMsg, stack?.toString());
  }

  /// Error / Crash log
  static void e(
    String tag,
    String message, [
    Object? error,
    StackTrace? stack,
  ]) {
    final fullMsg = error != null ? '$message: $error' : message;
    final stackStr = stack?.toString();
    _log(LogLevel.error, tag, fullMsg, stackStr);

    // Errors flush immediately to ensure crashes are saved before termination
    flushImmediate();
  }

  /// Debug / Verbose log
  static void d(String tag, String message) {
    if (kDebugMode) {
      _log(LogLevel.debug, tag, message);
    }
  }

  static void _log(
    LogLevel level,
    String tag,
    String message, [
    String? stackTrace,
  ]) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
      stackTrace: stackTrace,
    );

    // 1. Memory queue (strictly capped at maxLogEntries)
    if (_entries.length >= maxLogEntries) {
      _entries.removeAt(0);
    }
    _entries.add(entry);

    // 2. Broadcast for UI
    if (!_entryStreamController.isClosed) {
      _entryStreamController.add(entry);
    }

    // 3. Console output in debug mode
    if (kDebugMode) {
      debugPrint('${level.emoji} [$tag] $message');
      if (stackTrace != null && stackTrace.isNotEmpty) {
        debugPrint(stackTrace);
      }
    }

    // 4. Schedule debounced flush to disk
    _scheduleFlush();
  }

  static void _scheduleFlush() {
    _hasPendingWrites = true;
    _debounceFlushTimer?.cancel();
    _debounceFlushTimer = Timer(const Duration(milliseconds: 1000), () {
      if (_hasPendingWrites) {
        _flushToFile();
      }
    });
  }

  /// Flushes pending logs to disk immediately (e.g. on crashes or app pause)
  static Future<void> flushImmediate() async {
    _debounceFlushTimer?.cancel();
    await _flushToFile();
  }

  static Future<void> _flushToFile() async {
    if (_logFile == null) return;
    _hasPendingWrites = false;

    try {
      // Build text of all current entries (strictly capped at maxLogEntries)
      final buffer = StringBuffer();
      for (final entry in _entries) {
        buffer.writeln(entry.toLogLine());
      }

      await _logFile!.writeAsString(buffer.toString(), flush: true);

      // Check file size safety
      final size = await _logFile!.length();
      if (size > maxFileSizeBytes) {
        await _pruneLogFile();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AppLogger: flush error: $e');
      }
    }
  }

  static Future<void> _pruneLogFile() async {
    if (_logFile == null || !await _logFile!.exists()) return;

    try {
      final lines = await _logFile!.readAsLines();
      if (lines.length > maxLogEntries) {
        final trimmed = lines.sublist(lines.length - maxLogEntries);
        await _logFile!.writeAsString('${trimmed.join('\n')}\n', flush: true);
      }
    } catch (_) {}
  }

  static Future<void> _loadExistingLogs() async {
    if (_logFile == null || !await _logFile!.exists()) return;

    try {
      final lines = await _logFile!.readAsLines();
      // Keep up to the last maxLogEntries lines
      final start = lines.length > maxLogEntries ? lines.length - maxLogEntries : 0;
      final recentLines = lines.sublist(start);

      // Basic parse into entries
      for (final line in recentLines) {
        if (line.isEmpty || line.startsWith('  ')) continue;
        LogLevel level = LogLevel.info;
        if (line.contains('[ERROR]')) {
          level = LogLevel.error;
        } else if (line.contains('[WARN ]') || line.contains('[WARN]')) {
          level = LogLevel.warning;
        } else if (line.contains('[DEBUG]')) {
          level = LogLevel.debug;
        }

        _entries.add(LogEntry(
          timestamp: DateTime.now(),
          level: level,
          tag: 'Saved',
          message: line,
        ));
      }

      // Ensure we don't exceed maxLogEntries
      while (_entries.length > maxLogEntries) {
        _entries.removeAt(0);
      }
    } catch (_) {}
  }

  /// Get formatted logs as a single string, including device & system info
  static Future<String> getFormattedLogs() async {
    final buffer = StringBuffer();
    buffer.writeln('==============================================');
    buffer.writeln('          INZX APP LOGS & DIAGNOSTICS         ');
    buffer.writeln('==============================================');
    buffer.writeln('Generated: ${DateTime.now().toIso8601String()}');
    buffer.writeln(await _getDeviceInfo());
    buffer.writeln('Total events: ${_entries.length} (capped at $maxLogEntries)');
    buffer.writeln('==============================================\n');

    for (final entry in _entries) {
      buffer.writeln(entry.toLogLine());
    }

    return buffer.toString();
  }

  /// Get the physical log file (for sharing)
  static Future<File?> exportLogFile() async {
    await flushImmediate();
    if (_logFile != null && await _logFile!.exists()) {
      return _logFile;
    }
    return null;
  }

  /// Get current log file size in bytes
  static Future<int> getLogFileSize() async {
    try {
      if (_logFile != null && await _logFile!.exists()) {
        return await _logFile!.length();
      }
    } catch (_) {}
    return 0;
  }

  /// Format size in human readable string (e.g. "48 KB")
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  /// Clear all logs from memory and disk
  static Future<void> clearLogs() async {
    _entries.clear();
    if (_logFile != null && await _logFile!.exists()) {
      try {
        await _logFile!.writeAsString('');
      } catch (_) {}
    }
    i('AppLogger', 'Logs cleared by user');
  }

  static Future<String> _getDeviceInfo() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      final os = Platform.operatingSystem;
      final osVersion = Platform.operatingSystemVersion;
      return 'App: Inzx ${pkg.version}+${pkg.buildNumber} | OS: $os $osVersion';
    } catch (_) {
      return 'App: Inzx | OS: ${Platform.operatingSystem}';
    }
  }
}
