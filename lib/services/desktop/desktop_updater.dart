import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../github_release_update_service.dart';

enum DesktopUpdatePhase { idle, checking, available, downloading, ready, failed }

/// A newer desktop release and the file this platform installs it from.
class DesktopUpdate {
  const DesktopUpdate({
    required this.version,
    required this.releaseUrl,
    required this.assetUrl,
    required this.assetName,
    this.size,
    this.sha256,
    this.notes,
  });

  final String version;
  final String releaseUrl;
  final String assetUrl;
  final String assetName;
  final int? size;

  /// GitHub's digest for the asset, lowercase hex; checked after download.
  final String? sha256;
  final String? notes;
}

/// Keeps a desktop install current from GitHub releases.
///
/// * On start it looks for a newer release that has this platform's file
///   (Windows: the Inno Setup installer, `Inzx-Setup-<v>.exe`; Linux: the
///   AppImage). The top bar shows an indicator for it.
/// * With "Update automatically" on (the default) the file downloads in the
///   background into the app's local cache (never Documents), and is checked
///   against GitHub's SHA-256 digest and size before it's trusted.
/// * It installs when Inzx closes, or on the next start if Inzx was ended
///   some other way, or right away from the indicator. Windows runs the
///   installer silently (it upgrades only Inzx's own folder, per user, no
///   admin unless Inzx was installed for all users); Linux renames the new
///   AppImage over the running one, which is atomic and leaves the running
///   copy untouched until it exits.
///
/// Only copies that can update themselves do: a Windows install made by the
/// installer (it leaves `installed-by-setup` beside inzx.exe) or a Linux
/// AppImage in a folder Inzx can write to. Anything else (a development
/// build, a tarball) only gets the indicator and the release page.
class DesktopUpdater extends ChangeNotifier {
  DesktopUpdater._();
  static final DesktopUpdater instance = DesktopUpdater._();

  static const autoUpdateKey = 'desktop_auto_update';
  static const _pendingKey = 'desktop_update_pending';
  static const _attemptedKey = 'desktop_update_attempted';

  DesktopUpdatePhase _phase = DesktopUpdatePhase.idle;
  DesktopUpdate? _update;
  double? _progress;
  String? _error;
  File? _file;
  bool _autoUpdate = true;
  bool _checkedThisSession = false;
  http.Client? _client;

  DesktopUpdatePhase get phase => _phase;
  DesktopUpdate? get update => _update;
  double? get progress => _progress;
  String? get error => _error;
  bool get autoUpdate => _autoUpdate;

  static String get _exeDir => p.dirname(Platform.resolvedExecutable);

  static String? get _appImage {
    if (!Platform.isLinux) return null;
    final path = Platform.environment['APPIMAGE'];
    return path != null && path.isNotEmpty && File(path).existsSync() ? path : null;
  }

  /// Whether this copy can install updates itself (see the class comment).
  static bool get canSelfUpdate {
    if (Platform.isWindows) return File(p.join(_exeDir, 'installed-by-setup')).existsSync();
    final appImage = _appImage;
    if (appImage == null) return false;
    return _writable(p.dirname(appImage));
  }

  static bool _writable(String dir) {
    try {
      final probe = File(p.join(dir, '.inzx-write-test-$pid'));
      probe.writeAsStringSync('');
      probe.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _set(DesktopUpdatePhase phase, {double? progress, String? error}) {
    _phase = phase;
    _progress = progress;
    _error = error;
    notifyListeners();
  }

  // ---- Start-up -------------------------------------------------------------

  /// Before the window shows. Finishes an update downloaded earlier that
  /// didn't get installed on close (then this process exits and the new
  /// version starts), and tidies up after one that did.
  Future<void> applyPendingOnStartup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _autoUpdate = prefs.getBool(autoUpdateKey) ?? true;
      final raw = prefs.getString(_pendingKey);
      if (raw == null) return;
      final pending = jsonDecode(raw) as Map<String, dynamic>;
      final version = pending['version'] as String? ?? '';
      final path = pending['path'] as String? ?? '';
      final current = (await PackageInfo.fromPlatform()).version;
      final svc = GithubReleaseUpdateService.instance;
      final file = File(path);

      // Installed (or superseded): clean up.
      if (svc.compareVersions(version, svc.normalizeVersion(current)) <= 0 || !file.existsSync()) {
        await _forgetPending(prefs, file);
        return;
      }
      // Tried already and we're still on the old version: something stopped
      // the installer. Don't loop; the indicator offers it again.
      if (prefs.getString(_attemptedKey) == version || !canSelfUpdate) {
        await _forgetPending(prefs, file);
        return;
      }
      if (pending['sha256'] is String && !await _matches(file, pending['sha256'] as String)) {
        await _forgetPending(prefs, file);
        return;
      }
      if (!_autoUpdate) {
        // Downloaded by hand: it waits for "Restart and update".
        _file = file;
        _update = DesktopUpdate(
          version: version,
          releaseUrl: 'https://github.com/nirmaleeswar30/Inzx/releases/latest',
          assetUrl: '',
          assetName: p.basename(path),
        );
        _phase = DesktopUpdatePhase.ready;
        return;
      }
      await prefs.setString(_attemptedKey, version);
      debugPrint('DesktopUpdater: installing the $version downloaded earlier');
      await _install(file, relaunch: true);
      exit(0);
    } catch (e) {
      debugPrint('DesktopUpdater: start-up install skipped: $e');
    }
  }

  Future<void> _forgetPending(SharedPreferences prefs, File file) async {
    await prefs.remove(_pendingKey);
    try {
      if (file.existsSync()) await file.delete();
    } catch (_) {}
  }

  // ---- Checking and downloading ---------------------------------------------

  /// Looks for a newer release once per session (or again when [force]).
  /// Downloads it in the background when automatic updates are on.
  Future<void> check({bool force = false}) async {
    if (!isDesktopPlatform) return;
    if (_checkedThisSession && !force) return;
    if (_phase == DesktopUpdatePhase.downloading || _phase == DesktopUpdatePhase.ready) return;
    _checkedThisSession = true;
    final prefs = await SharedPreferences.getInstance();
    _autoUpdate = prefs.getBool(autoUpdateKey) ?? true;
    _set(DesktopUpdatePhase.checking);
    final update = await _latest();
    if (update == null) {
      _update = null;
      _set(DesktopUpdatePhase.idle);
      return;
    }
    _update = update;
    _set(DesktopUpdatePhase.available);
    if (_autoUpdate && canSelfUpdate) await download();
  }

  static bool get isDesktopPlatform => Platform.isWindows || Platform.isLinux;

  Future<DesktopUpdate?> _latest() async {
    final svc = GithubReleaseUpdateService.instance;
    final json = await svc.fetchLatestReleaseJson();
    if (json == null) return null;
    final version = svc.normalizeVersion((json['tag_name'] as String?) ?? '');
    final current = svc.normalizeVersion((await PackageInfo.fromPlatform()).version);
    if (version.isEmpty || svc.compareVersions(version, current) <= 0) return null;
    for (final asset in (json['assets'] as List? ?? const [])) {
      if (asset is! Map) continue;
      final name = (asset['name'] as String?) ?? '';
      final lower = name.toLowerCase();
      final matches = Platform.isWindows
          ? lower.endsWith('.exe') && lower.contains('setup')
          : lower.endsWith('.appimage') && lower.contains('x86_64');
      final url = asset['browser_download_url'] as String?;
      if (!matches || url == null) continue;
      final digest = asset['digest'] as String?;
      return DesktopUpdate(
        version: version,
        releaseUrl: (json['html_url'] as String?) ?? 'https://github.com/nirmaleeswar30/Inzx/releases/latest',
        assetUrl: url,
        assetName: name,
        size: (asset['size'] as num?)?.toInt(),
        sha256: digest != null && digest.startsWith('sha256:') ? digest.substring(7).toLowerCase() : null,
        notes: (json['body'] as String?)?.trim(),
      );
    }
    // A release without a desktop build (yet: the build attaches it a few
    // minutes after publishing) isn't an update here.
    return null;
  }

  /// Where the download goes. Windows: the app's local cache. Linux: beside
  /// the AppImage, so the swap is a rename on one filesystem.
  Future<File> _target(DesktopUpdate update) async {
    if (Platform.isLinux) {
      return File(p.join(p.dirname(_appImage!), '.Inzx-update.AppImage'));
    }
    final dir = Directory(p.join((await getApplicationCacheDirectory()).path, 'updates'));
    await dir.create(recursive: true);
    final safe = update.assetName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return File(p.join(dir.path, safe));
  }

  Future<void> download() async {
    final update = _update;
    if (update == null || !canSelfUpdate) return;
    if (_phase == DesktopUpdatePhase.downloading || _phase == DesktopUpdatePhase.ready) return;
    final target = await _target(update);
    final part = File('${target.path}.part');
    _set(DesktopUpdatePhase.downloading, progress: 0);
    final client = _client = http.Client();
    try {
      final response = await client.send(
        http.Request('GET', Uri.parse(update.assetUrl))..headers['User-Agent'] = 'Inzx-Desktop-Updater',
      );
      if (response.statusCode != 200) throw HttpException('HTTP ${response.statusCode}');
      final total = response.contentLength ?? update.size ?? 0;
      final sink = part.openWrite();
      final hashOut = _DigestSink();
      final hasher = sha256.startChunkedConversion(hashOut);
      var received = 0;
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          hasher.add(chunk);
          received += chunk.length;
          if (total > 0) {
            final value = (received / total).clamp(0.0, 1.0);
            if (_progress == null || value - _progress! >= 0.01 || value == 1) {
              _set(DesktopUpdatePhase.downloading, progress: value);
            }
          }
        }
      } finally {
        await sink.close();
        hasher.close();
      }
      if (update.size != null && received != update.size) {
        throw StateError('size mismatch ($received of ${update.size} bytes)');
      }
      if (update.sha256 != null && hashOut.value.toString() != update.sha256) {
        throw StateError('checksum mismatch');
      }
      if (target.existsSync()) await target.delete();
      await part.rename(target.path);
      if (Platform.isLinux) {
        final chmod = await Process.run('chmod', ['+x', target.path]);
        if (chmod.exitCode != 0) throw StateError('chmod failed: ${chmod.stderr}');
      }
      _file = target;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _pendingKey,
        jsonEncode({'version': update.version, 'path': target.path, 'sha256': update.sha256}),
      );
      _set(DesktopUpdatePhase.ready, progress: 1);
      debugPrint('DesktopUpdater: ${update.version} downloaded and verified');
    } catch (e) {
      try {
        if (part.existsSync()) await part.delete();
      } catch (_) {}
      debugPrint('DesktopUpdater: download failed: $e');
      _set(DesktopUpdatePhase.failed, error: '$e');
    } finally {
      client.close();
      _client = null;
    }
  }

  Future<bool> _matches(File file, String expected) async {
    try {
      final digest = await sha256.bind(file.openRead()).first;
      return digest.toString() == expected.toLowerCase();
    } catch (_) {
      return false;
    }
  }

  Future<void> setAutoUpdate(bool on) async {
    _autoUpdate = on;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(autoUpdateKey, on);
    if (on && _phase == DesktopUpdatePhase.available && canSelfUpdate) unawaited(download());
  }

  // ---- Installing ----------------------------------------------------------

  /// From the window's close handler: installs a downloaded update as Inzx
  /// goes away, without starting it again. Quick: it only launches the
  /// installer (or renames the AppImage).
  Future<void> applyOnExit() async {
    final file = _file;
    final update = _update;
    if (_phase != DesktopUpdatePhase.ready || file == null || update == null) return;
    if (!_autoUpdate) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_attemptedKey, update.version);
      await _install(file, relaunch: false);
    } catch (e) {
      debugPrint('DesktopUpdater: install on exit failed: $e');
    }
  }

  /// "Restart and update": installs now and starts the new version.
  Future<void> installNow() async {
    final file = _file;
    final update = _update;
    if (file == null || update == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_attemptedKey, update.version);
    await _install(file, relaunch: true);
    exit(0);
  }

  Future<void> _install(File file, {required bool relaunch}) async {
    if (Platform.isWindows) {
      // /SILENT shows the installer's progress when the person is waiting
      // for it; on close nothing should appear.
      final args = [
        relaunch ? '/SILENT' : '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
        '/NOCANCEL',
        if (relaunch) '/RELAUNCH=1',
      ];
      try {
        await Process.start(file.path, args, mode: ProcessStartMode.detached);
      } on ProcessException catch (e) {
        // 740: an all-users install, which needs admin rights; ShellExecute
        // (Start-Process) shows the UAC prompt a plain start can't.
        if (e.errorCode != 740) rethrow;
        final path = file.path.replaceAll("'", "''");
        await Process.start('powershell', [
          '-NoProfile',
          '-WindowStyle',
          'Hidden',
          '-Command',
          "Start-Process -FilePath '$path' -ArgumentList ${args.map((a) => "'$a'").join(',')}",
        ], mode: ProcessStartMode.detached);
      }
      return;
    }
    // Linux: the rename swaps which file the name points to; this process
    // keeps running from the old one until it exits.
    final appImage = _appImage!;
    await file.rename(appImage);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingKey);
    if (relaunch) {
      await Process.start('/bin/sh', [
        '-c',
        'while kill -0 "\$1" 2>/dev/null; do sleep 0.2; done; exec "\$0"',
        appImage,
        '$pid',
      ], mode: ProcessStartMode.detached);
    }
  }

  @override
  void dispose() {
    _client?.close();
    super.dispose();
  }
}

/// Collects the single digest a chunked SHA-256 conversion produces.
class _DigestSink implements Sink<Digest> {
  Digest? _value;
  Digest get value => _value!;
  @override
  void add(Digest data) => _value = data;
  @override
  void close() {}
}
