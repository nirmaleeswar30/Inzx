// Desktop AutoEQ: a Dart port of LastWave's AutoEqController and
// AutoEqCatalog (android/.../lastwave/app/data/autoeq) behind the same calls
// AutoEqBridge.kt answers on Android, so the AutoEQ screen works unchanged.
// The correction it publishes runs in libmpv's filter chain
// (DesktopAudioDsp).
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../desktop/desktop_output_device.dart';
import 'peq.dart';

enum FormFactor { overEar, inEar }

/// One headphone result of the AutoEQ database (results/INDEX.md).
class AutoEqEntry {
  const AutoEqEntry(this.name, this.source, this.rig, this.encodedPath);

  final String name;
  final String source;
  final String? rig;

  /// Percent-encoded path below results/, as written in INDEX.md.
  final String encodedPath;

  String get _decodedPath => Uri.decodeComponent(encodedPath.replaceAll('+', '%2B'));

  FormFactor get formFactor {
    final folder = _decodedPath.toLowerCase();
    return folder.contains('in-ear') || folder.contains('earbud')
        ? FormFactor.inEar
        : FormFactor.overEar;
  }

  String get folderName {
    final path = _decodedPath;
    return path.substring(path.lastIndexOf('/') + 1);
  }

  String get subtitle => (rig == null || rig!.trim().isEmpty) ? source : '$source • $rig';

  Map<String, Object?> toJson() => {
    'name': name,
    'source': source,
    'rig': rig,
    'encodedPath': encodedPath,
  };

  factory AutoEqEntry.fromJson(Map m) => AutoEqEntry(
    m['name'] as String,
    m['source'] as String? ?? '',
    m['rig'] as String?,
    m['encodedPath'] as String,
  );

  /// What the AutoEQ screen reads (AutoEqBridge's toMap).
  Map<String, Object?> toScreenMap() => {
    'name': name,
    'subtitle': subtitle,
    'path': encodedPath,
    'inEar': formFactor == FormFactor.inEar,
  };
}

/// Everything that defines the active correction (AutoEqState.kt).
class AutoEqData {
  const AutoEqData({
    this.entry,
    this.base,
    this.settings = const PeqSettings(),
    this.targetId = AutoEqTargets.defaultTargetId,
    this.bassDb = 0,
    this.tiltDbPerOctave = 0,
    this.isCustom = false,
  });

  final AutoEqEntry? entry;
  final PeqSettings? base;
  final PeqSettings settings;
  final String targetId;
  final double bassDb;
  final double tiltDbPerOctave;
  final bool isCustom;

  AutoEqData copyWith({
    AutoEqEntry? entry,
    PeqSettings? base,
    PeqSettings? settings,
    String? targetId,
    double? bassDb,
    double? tiltDbPerOctave,
    bool? isCustom,
  }) => AutoEqData(
    entry: entry ?? this.entry,
    base: base ?? this.base,
    settings: settings ?? this.settings,
    targetId: targetId ?? this.targetId,
    bassDb: bassDb ?? this.bassDb,
    tiltDbPerOctave: tiltDbPerOctave ?? this.tiltDbPerOctave,
    isCustom: isCustom ?? this.isCustom,
  );

  Map<String, Object?> toJson() => {
    'entry': entry?.toJson(),
    'base': base?.toJson(),
    'settings': settings.toJson(),
    'targetId': targetId,
    'bassDb': bassDb,
    'tiltDbPerOctave': tiltDbPerOctave,
    'isCustom': isCustom,
  };

  factory AutoEqData.fromJson(Map m) => AutoEqData(
    entry: m['entry'] == null ? null : AutoEqEntry.fromJson(m['entry'] as Map),
    base: m['base'] == null ? null : PeqSettings.fromJson(m['base'] as Map),
    settings: m['settings'] == null
        ? const PeqSettings()
        : PeqSettings.fromJson(m['settings'] as Map),
    targetId: m['targetId'] as String? ?? AutoEqTargets.defaultTargetId,
    bassDb: (m['bassDb'] as num?)?.toDouble() ?? 0,
    tiltDbPerOctave: (m['tiltDbPerOctave'] as num?)?.toDouble() ?? 0,
    isCustom: m['isCustom'] == true,
  );
}

/// Pure parsing helpers (AutoEqIndexParser.kt).
abstract final class AutoEqIndexParser {
  static final _line = RegExp(r'^- \[(.+)]\(\./(.+)\) by (.+?)(?: on (.+))?\s*$');

  static List<AutoEqEntry> parse(String markdown) => [
    for (final raw in const LineSplitter().convert(markdown))
      if (_line.firstMatch(raw.trim()) case final m?)
        AutoEqEntry(
          m.group(1)!.trim(),
          m.group(3)!.trim(),
          (m.group(4)?.trim().isEmpty ?? true) ? null : m.group(4)!.trim(),
          m.group(2)!.trim(),
        ),
  ];

  /// Every query word must appear in name, source or rig (case-insensitive).
  static List<AutoEqEntry> search(List<AutoEqEntry> entries, String query, {int limit = 200}) {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return const [];
    final hits = entries.where((e) {
      final hay = '${e.name} ${e.source} ${e.rig ?? ''}'.toLowerCase();
      return words.every(hay.contains);
    }).toList();
    int rank(AutoEqEntry e) => e.name.toLowerCase().startsWith(words.first) ? 0 : 1;
    hits.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      final l = a.name.length.compareTo(b.name.length);
      if (l != 0) return l;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return hits.take(limit).toList();
  }

  static String encodeSegment(String segment) => Uri.encodeComponent(segment);
}

/// Downloads the AutoEQ index and profiles from the public
/// jaakkopasanen/AutoEq repository (MIT) on demand and keeps them on disk,
/// so a chosen profile keeps working offline (AutoEqCatalog.kt).
class AutoEqCatalog {
  static const baseUrl = 'https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/results';
  static const mirrorUrl = 'https://cdn.jsdelivr.net/gh/jaakkopasanen/AutoEq@master/results';
  static const _indexMaxAge = Duration(days: 14);

  List<AutoEqEntry>? _cached;
  Future<void>? _busy;

  Future<Directory> _root() async {
    final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'autoeq'));
    await Directory(p.join(dir.path, 'profiles')).create(recursive: true);
    return dir;
  }

  Future<List<AutoEqEntry>> entries({bool forceRefresh = false}) async {
    while (_busy != null) {
      await _busy;
    }
    final done = Completer<void>();
    _busy = done.future;
    try {
      final file = File(p.join((await _root()).path, 'INDEX.md'));
      final exists = await file.exists();
      final stale = !exists || DateTime.now().difference(await file.lastModified()) > _indexMaxAge;
      if (forceRefresh || stale) {
        try {
          final body = await _download('$baseUrl/INDEX.md');
          if (AutoEqIndexParser.parse(body).length > 100) {
            await file.writeAsString(body);
            _cached = null;
          }
        } catch (e) {
          if (!exists) rethrow;
          debugPrint('AutoEQ: index refresh failed, using cache: $e');
        }
      }
      return _cached ??= AutoEqIndexParser.parse(await file.readAsString());
    } finally {
      _busy = null;
      done.complete();
    }
  }

  Future<List<AutoEqEntry>> search(String query) async =>
      AutoEqIndexParser.search(await entries(), query);

  /// The lab's ParametricEQ.txt for [entry] (cached after the first download).
  Future<PeqSettings> profile(AutoEqEntry entry) async {
    final cache = File(p.join((await _root()).path, 'profiles', '${_key(entry)}.txt'));
    String text;
    if (await cache.exists() && await cache.length() > 0) {
      text = await cache.readAsString();
    } else {
      text = await _download(_fileUrl(entry, '${entry.folderName} ParametricEQ.txt'));
      await cache.writeAsString(text);
    }
    final parsed = ParametricEqText.parse(text);
    if (parsed == null) throw const FileSystemException('Profile has no filters');
    return parsed;
  }

  String _fileUrl(AutoEqEntry entry, String fileName) =>
      '$baseUrl/${entry.encodedPath}/${AutoEqIndexParser.encodeSegment(fileName)}';

  // GitHub's raw host is blocked on some networks, so a failed fetch retries
  // on jsDelivr's mirror of the same repository (byte-identical files).
  Future<String> _download(String url) async {
    try {
      return await _fetch(url);
    } on _NotFound {
      rethrow;
    } catch (e) {
      if (!url.startsWith(baseUrl)) rethrow;
      debugPrint('AutoEQ: GitHub unreachable, trying the jsDelivr mirror: $e');
      return _fetch(mirrorUrl + url.substring(baseUrl.length));
    }
  }

  Future<String> _fetch(String url) async {
    final response = await http
        .get(Uri.parse(url), headers: const {'User-Agent': 'Inzx-AutoEQ'})
        .timeout(const Duration(seconds: 20));
    if (response.statusCode == 404) throw _NotFound(url);
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw HttpException('HTTP ${response.statusCode} for $url');
    }
    return utf8.decode(response.bodyBytes);
  }

  String _key(AutoEqEntry entry) =>
      sha1.convert(utf8.encode(entry.encodedPath)).toString().substring(0, 24);
}

class _NotFound implements Exception {
  const _NotFound(this.url);
  final String url;
  @override
  String toString() => 'Not found: $url';
}

class AutoEqTarget {
  const AutoEqTarget(this.id, this.name, this.family, this.deltaOverEar, this.deltaInEar);

  final String id;
  final String name;
  final String family;
  final List<double> deltaOverEar;
  final List<double> deltaInEar;

  List<double> delta(FormFactor f) => f == FormFactor.inEar ? deltaInEar : deltaOverEar;
}

/// Bundled target deltas (autoeq_targets.json, installed next to the app
/// from android/app/src/main/assets by the desktop CMake files).
class AutoEqTargets {
  static const defaultTargetId = 'default';

  List<AutoEqTarget>? _targets;

  List<AutoEqTarget> get targets => _targets ??= _load();

  static String get path => p.join(p.dirname(Platform.resolvedExecutable), 'data', 'autoeq_targets.json');

  List<AutoEqTarget> _load() {
    try {
      final m = jsonDecode(File(path).readAsStringSync()) as Map;
      List<double> nums(Object? l) => [for (final v in (l as List? ?? const [])) (v as num).toDouble()];
      return [
        for (final t in (m['targets'] as List? ?? const []))
          AutoEqTarget(
            (t as Map)['id'] as String,
            t['name'] as String,
            t['family'] as String? ?? '',
            nums(t['deltaOverEar']),
            nums(t['deltaInEar']),
          ),
      ];
    } catch (e) {
      debugPrint('AutoEQ: target file unreadable: $e');
      return const [];
    }
  }

  AutoEqTarget? byId(String id) {
    for (final t in targets) {
      if (t.id == id) return t;
    }
    return null;
  }
}

/// The controller (AutoEqController.kt). Publishes the correction to run as
/// [active]; listeners (the DSP) re-apply on every change.
class DesktopAutoEq extends ChangeNotifier {
  DesktopAutoEq._();
  static final DesktopAutoEq instance = DesktopAutoEq._();

  static const _kEnabled = 'autoeq_enabled';
  static const _kState = 'autoeq_state';
  static const _kAutoDevice = 'autoeq_auto_per_device';
  static const _kDevices = 'autoeq_device_profiles';
  static const _kDeviceLabels = 'autoeq_device_labels';

  final catalog = AutoEqCatalog();
  final targets = AutoEqTargets();

  bool _loaded = false;
  Future<void>? _loading;
  bool _enabled = false;
  bool _autoPerDevice = true;
  bool _busy = false;
  AutoEqData _state = const AutoEqData();
  Map<String, AutoEqData> _deviceProfiles = {};
  Map<String, String> _deviceLabels = {};
  OutputDevice? _device;

  /// The last search's rows, by path, so a tap selects the exact entry.
  final _lastResults = <String, AutoEqEntry>{};

  /// What should run now, or null for nothing.
  PeqSettings? get active =>
      _enabled && !_state.settings.isFlat ? _state.settings : null;

  /// Loads the saved correction and starts following the output device.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_kEnabled) ?? false;
    _autoPerDevice = prefs.getBool(_kAutoDevice) ?? true;
    _state = _decode(prefs.getString(_kState), AutoEqData.fromJson) ?? const AutoEqData();
    _deviceProfiles = _decode(
          prefs.getString(_kDevices),
          (m) => {
            for (final e in m.entries) e.key as String: AutoEqData.fromJson(e.value as Map),
          },
        ) ??
        {};
    _deviceLabels = _decode(
          prefs.getString(_kDeviceLabels),
          (m) => {for (final e in m.entries) e.key as String: e.value as String},
        ) ??
        {};
    _loaded = true;
    notifyListeners();
    DesktopOutputDevice.instance.addListener(_refreshDevice);
    _refreshDevice();
  }

  static T? _decode<T>(String? raw, T Function(Map m) read) {
    if (raw == null) return null;
    try {
      return read(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  /// One AutoEqBridge call: same method names, arguments and result map.
  Future<Object?> invoke(String method, Map<String, Object?> args) async {
    await load();
    if (!_loaded) throw PlatformException(code: 'AUTOEQ', message: 'Not ready');
    try {
      switch (method) {
        case 'state':
          return _describe();
        case 'search':
          final rows = await catalog.search((args['query'] as String?) ?? '');
          _lastResults
            ..clear()
            ..addEntries(rows.map((r) => MapEntry(r.encodedPath, r)));
          return [for (final r in rows) r.toScreenMap()];
        case 'select':
          final entry = _lastResults[args['path']];
          if (entry == null) {
            throw PlatformException(code: 'AUTOEQ', message: 'Search again and pick the headphone');
          }
          await _runBusy(() async {
            final base = await catalog.profile(entry);
            final next = _state.copyWith(entry: entry, base: base, isCustom: false);
            await _writeState(next.copyWith(settings: await _computeSettings(next)));
            await _setEnabled(true);
          });
          return _describe();
        case 'setEnabled':
          await _setEnabled(args['on'] == true);
          return _describe();
        case 'setAutoPerDevice':
          _autoPerDevice = args['on'] == true;
          await (await SharedPreferences.getInstance()).setBool(_kAutoDevice, _autoPerDevice);
          notifyListeners();
          return _describe();
        case 'setTarget':
          await _updateComputed(
            (s) => s.copyWith(targetId: (args['id'] as String?) ?? AutoEqTargets.defaultTargetId),
          );
          return _describe();
        case 'setBass':
          final db = ((args['db'] as num?)?.toDouble() ?? 0).clamp(-12.0, 12.0);
          await _updateComputed((s) => s.copyWith(bassDb: db));
          return _describe();
        case 'setTilt':
          final db = ((args['db'] as num?)?.toDouble() ?? 0).clamp(-1.5, 1.5);
          await _updateComputed((s) => s.copyWith(tiltDbPerOctave: db));
          return _describe();
        case 'reset':
          await _updateComputed((s) => s);
          return _describe();
        case 'clear':
          await _writeState(const AutoEqData());
          return _describe();
        case 'saveForDevice':
          final device = _device;
          if (device != null) {
            _deviceProfiles = {..._deviceProfiles, device.key: _state};
            _deviceLabels = {..._deviceLabels, device.key: device.label};
            await _saveDevices();
          }
          return _describe();
        case 'forgetDevice':
          _deviceProfiles = Map.of(_deviceProfiles)..remove(args['key']);
          await _saveDevices();
          return _describe();
      }
    } on PlatformException {
      rethrow;
    } catch (e) {
      throw PlatformException(code: 'AUTOEQ', message: '$e');
    }
    throw PlatformException(code: 'AUTOEQ', message: 'Unknown method $method');
  }

  Future<void> _setEnabled(bool on) async {
    _enabled = on;
    await (await SharedPreferences.getInstance()).setBool(_kEnabled, on);
    notifyListeners();
  }

  Future<void> _updateComputed(AutoEqData Function(AutoEqData) change) => _runBusy(() async {
    final next = change(_state).copyWith(isCustom: false);
    await _writeState(next.copyWith(settings: await _computeSettings(next)));
  });

  /// Lab profile when nothing is adjusted, else a refit of profile + target
  /// delta + bass + tilt (in a background isolate: the fit takes a moment).
  Future<PeqSettings> _computeSettings(AutoEqData s) async {
    final base = s.base;
    if (base == null) return s.settings;
    final entry = s.entry;
    final delta = entry != null && s.targetId != AutoEqTargets.defaultTargetId
        ? targets.byId(s.targetId)?.delta(entry.formFactor)
        : null;
    if (delta == null && s.bassDb == 0 && s.tiltDbPerOctave == 0) return base;
    return PeqSettings.fromJson(
      await _refit(base.toJson(), delta, s.bassDb, s.tiltDbPerOctave),
    );
  }

  /// The refit, off the UI thread. Static and synchronous so the isolate's
  /// closure holds only these arguments.
  static Future<Map<String, Object?>> _refit(
    Map<String, Object?> baseJson,
    List<double>? delta,
    double bass,
    double tilt,
  ) => Isolate.run(() {
    final b = PeqSettings.fromJson(baseJson);
    final grid = PeqMath.logGrid;
    final desired = [
      for (var i = 0; i < grid.length; i++)
        (PeqMath.filtersDb(b.filters, grid[i]) +
                (delta != null && i < delta.length ? delta[i] : 0.0) +
                PeqMath.bassShelfDb(bass, grid[i]) +
                PeqMath.tiltDb(tilt, grid[i]))
            .clamp(-15.0, 12.0)
            .toDouble(),
    ];
    return PeqFitter.fit(desired, grid).toJson();
  });

  Future<void> _writeState(AutoEqData next) async {
    _state = next;
    await (await SharedPreferences.getInstance()).setString(_kState, jsonEncode(next.toJson()));
    notifyListeners();
  }

  Future<void> _saveDevices() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kDevices,
      jsonEncode({for (final e in _deviceProfiles.entries) e.key: e.value.toJson()}),
    );
    await prefs.setString(_kDeviceLabels, jsonEncode(_deviceLabels));
    notifyListeners();
  }

  Future<void> _runBusy(Future<void> Function() block) async {
    _busy = true;
    notifyListeners();
    try {
      await block();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Map<String, Object?> _describe() {
    final s = _state;
    final settings = s.settings;
    final grid = PeqMath.logGrid;
    return {
      'enabled': _enabled,
      'busy': _busy,
      'autoPerDevice': _autoPerDevice,
      'entry': s.entry?.toScreenMap(),
      'targetId': s.targetId,
      'bassDb': s.bassDb,
      'tiltDb': s.tiltDbPerOctave,
      'isCustom': s.isCustom,
      'preampDb': settings.preampDb,
      'filterCount': settings.filters.where((f) => f.enabled).length,
      'targets': [
        for (final t in targets.targets) {'id': t.id, 'name': t.name, 'family': t.family},
      ],
      'device': _device == null ? null : {'key': _device!.key, 'label': _device!.label},
      'savedDevices': [
        for (final key in _deviceProfiles.keys)
          {
            'key': key,
            'label': _deviceLabels[key] ?? key,
            'headphone': _deviceProfiles[key]?.entry?.name,
          },
      ],
      'curveHz': grid,
      'curveDb': [for (final f in grid) PeqMath.responseDb(settings, f)],
    };
  }

  // ---- Output device ---------------------------------------------------------

  void _refreshDevice() {
    final device = DesktopOutputDevice.instance.current;
    final previous = _device;
    _device = device;
    if (device?.key != previous?.key) notifyListeners();
    if (device == null || device.key == previous?.key) return;
    if (!_autoPerDevice) return;
    final saved = _deviceProfiles[device.key];
    if (saved == null) return;
    debugPrint('AutoEQ: output ${device.label}: applying its profile');
    unawaited(_writeState(saved));
  }
}
