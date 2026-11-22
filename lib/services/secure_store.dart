import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/utils/secure_storage.dart';

/// Secrets (sign-in cookies, tokens, add-on keys): the system keyring, with a
/// private file to fall back on where Linux has no usable keyring.
///
/// flutter_secure_storage keeps them in the keyring, which on Linux is the
/// Secret Service (GNOME Keyring, KWallet...). Many Linux desktops run
/// without a working one: tiling window managers with none set up, or a
/// KWallet that started before the session bus and never registered. Every
/// read and write then throws, so YouTube Music sign-in saved nothing and its
/// window waited forever. There, secrets go to a file in Inzx's own data
/// folder that only this user can read, as Chromium's "basic" password store
/// does on Linux without a keyring. The keyring stays the first choice: a
/// value kept in the file moves into it once it works again.
///
/// Only Linux falls back; elsewhere keyring errors surface as before.
class SecureStore {
  SecureStore._(this._keyring, this._directory, this._fallback);

  static final SecureStore instance = SecureStore._(
    inzxSecureStorage,
    getApplicationSupportDirectory,
    Platform.isLinux,
  );

  @visibleForTesting
  SecureStore.forTest({
    required FlutterSecureStorage keyring,
    required Future<Directory> Function() directory,
    bool fallback = true,
  }) : this._(keyring, directory, fallback);

  final FlutterSecureStorage _keyring;
  final Future<Directory> Function() _directory;
  final bool _fallback;

  /// Set once the keyring has failed: the rest of the session uses the file
  /// directly, rather than waiting on (and logging) the same error each time.
  bool _keyringFailed = false;

  /// File reads and writes, one at a time.
  Future<void> _fileQueue = Future.value();

  Future<String?> read({required String key}) async {
    if (!_keyringFailed) {
      try {
        final value = await _keyring.read(key: key);
        if (value != null || !_fallback) return value;
        // The keyring works but hasn't got it: it may be in the file from
        // a session without one. Move it across.
        final kept = (await _readFile())[key];
        if (kept != null) await _moveToKeyring(key, kept);
        return kept;
      } catch (e) {
        if (!_fallback) rethrow;
        _keyringUnavailable(e);
      }
    }
    return (await _readFile())[key];
  }

  Future<void> write({required String key, required String? value}) async {
    if (value == null) return delete(key: key);
    if (!_keyringFailed) {
      try {
        await _keyring.write(key: key, value: value);
        if (_fallback) await _updateFile((values) => values.remove(key));
        return;
      } catch (e) {
        if (!_fallback) rethrow;
        _keyringUnavailable(e);
      }
    }
    await _updateFile((values) => values[key] = value);
  }

  Future<void> delete({required String key}) async {
    if (!_keyringFailed) {
      try {
        await _keyring.delete(key: key);
      } catch (e) {
        if (!_fallback) rethrow;
        _keyringUnavailable(e);
      }
    }
    if (_fallback) await _updateFile((values) => values.remove(key));
  }

  void _keyringUnavailable(Object error) {
    if (_keyringFailed) return;
    _keyringFailed = true;
    debugPrint(
      'SecureStore: the system keyring is unavailable ($error); '
      'keeping secrets in a private file instead',
    );
  }

  Future<void> _moveToKeyring(String key, String value) async {
    try {
      await _keyring.write(key: key, value: value);
      await _updateFile((values) => values.remove(key));
    } catch (_) {
      // Still readable from the file; try again another time.
    }
  }

  // ---- The file ---------------------------------------------------------------
  //
  // <app support>/secure/secrets.json: the directory is 0700 and the file
  // 0600, written whole to a temporary file and renamed over the old one.

  Future<File> _file() async {
    final dir = Directory(p.join((await _directory()).path, 'secure'));
    if (!await dir.exists()) await dir.create(recursive: true);
    await _chmod('700', dir.path);
    return File(p.join(dir.path, 'secrets.json'));
  }

  Future<Map<String, String>> _readFile() {
    final result = _fileQueue.then((_) => _load());
    _fileQueue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _updateFile(void Function(Map<String, String> values) change) {
    final result = _fileQueue.then((_) async {
      final values = await _load();
      final before = jsonEncode(values);
      change(values);
      if (jsonEncode(values) == before) return;
      await _save(values);
    });
    _fileQueue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<Map<String, String>> _load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return {};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    } catch (e) {
      debugPrint('SecureStore: could not read the secrets file: $e');
      return {};
    }
  }

  Future<void> _save(Map<String, String> values) async {
    final file = await _file();
    if (values.isEmpty) {
      if (await file.exists()) await file.delete();
      return;
    }
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(values), flush: true);
    await _chmod('600', temp.path);
    await temp.rename(file.path);
  }

  static Future<void> _chmod(String mode, String path) async {
    if (Platform.isWindows) return;
    try {
      await Process.run('chmod', [mode, path]);
    } catch (_) {}
  }
}
