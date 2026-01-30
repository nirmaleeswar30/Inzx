import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:path_provider/path_provider.dart';

/// Simple file logger for Jams debugging
class JamsLogger {
  static JamsLogger? _instance;
  static JamsLogger get instance => _instance ??= JamsLogger._();

  JamsLogger._();

  File? _logFile;
  bool _initialized = false;

  /// Initialize the logger
  Future<void> init() async {
    // Disable file logging in release mode
    if (!kDebugMode) return;

    if (_initialized) return;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final logsDir = Directory('${dir.path}/logs');
      if (!await logsDir.exists()) {
        await logsDir.create(recursive: true);
      }

      // Use date-based log file
      final now = DateTime.now();
      final fileName =
          'jams_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.log';
      _logFile = File('${logsDir.path}/$fileName');

      _initialized = true;
      log('========== Session Started ==========');
      log('Log file: ${_logFile?.path}');
    } catch (e) {
      if (kDebugMode) {
        print('JamsLogger: Failed to initialize: $e');
      }
    }
  }

  /// Log a message
  void log(String message, {String tag = 'Jams'}) {
    final timestamp = DateTime.now().toIso8601String();
    final line = '[$timestamp] [$tag] $message';

    // Always print to console in debug mode
    if (kDebugMode) {
      print(line);
      // Write to file only in debug mode
      _writeToFile(line);
    }
  }

  /// Log an error
  void error(
    String message, {
    String tag = 'Jams',
    Object? error,
    StackTrace? stackTrace,
  }) {
    final timestamp = DateTime.now().toIso8601String();
    final line = '[$timestamp] [$tag] ERROR: $message';

    if (kDebugMode) {
      print(line);
      if (error != null) print('  Error: $error');
      if (stackTrace != null) print('  Stack: $stackTrace');

      _writeToFile(line);
      if (error != null) _writeToFile('  Error: $error');
      if (stackTrace != null) _writeToFile('  Stack: $stackTrace');
    }
  }

  void _writeToFile(String line) {
    if (!kDebugMode) return;
    try {
      _logFile?.writeAsStringSync(
        '$line\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (e) {
      // Ignore file write errors
    }
  }

  /// Get the log file path
  String? get logFilePath => _logFile?.path;

  /// Read all logs
  Future<String> readLogs() async {
    try {
      if (_logFile != null && await _logFile!.exists()) {
        return await _logFile!.readAsString();
      }
    } catch (e) {
      // Ignore
    }
    return 'No logs available';
  }

  /// Clear logs
  Future<void> clearLogs() async {
    try {
      if (_logFile != null && await _logFile!.exists()) {
        await _logFile!.writeAsString('');
      }
    } catch (e) {
      // Ignore
    }
  }

  /// Copy logs to clipboard and print path
  Future<void> printLogInfo() async {
    if (kDebugMode) {
      print('==========================================');
      print('JAMS LOG FILE: ${_logFile?.path}');
      print('==========================================');
      print('To pull logs via adb:');
      print('adb pull ${_logFile?.path} jams_logs.txt');
      print('==========================================');
    }
  }
}

/// Shorthand for logging
void jamsLog(String message, {String tag = 'Jams'}) {
  JamsLogger.instance.log(message, tag: tag);
}

void jamsError(
  String message, {
  String tag = 'Jams',
  Object? error,
  StackTrace? stackTrace,
}) {
  JamsLogger.instance.error(
    message,
    tag: tag,
    error: error,
    stackTrace: stackTrace,
  );
}
