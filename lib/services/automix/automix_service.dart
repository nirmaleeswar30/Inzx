import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/platform_utils.dart';
import '../desktop/desktop_audio_dsp.dart';
import 'desktop/automix_native.dart';
import 'desktop/desktop_automix_engine.dart';
import 'desktop/desktop_track_analyzer.dart';

/// How hard Automix's analysis (BitChord's beat and vocal models) works.
/// Names match BitChord's AutomixPerformanceMode, which reads them.
enum AutomixPerformanceMode {
  efficient('Efficient', 1),
  balanced('Balanced', 2),
  performance('Performance', 4);

  const AutomixPerformanceMode(this.label, this.fallbackThreads);
  final String label;
  /// BitChord's fixed counts, until the phone's own are known.
  final int fallbackThreads;

  String get wire => name.toUpperCase();

  static AutomixPerformanceMode fromWire(String? v) => values.firstWhere(
    (m) => m.wire == v,
    orElse: () => AutomixPerformanceMode.balanced,
  );
}

/// What the analyzer knows about one track (see AutomixBridge.describe).
class AutomixAnalysis {
  const AutomixAnalysis(this._m);
  final Map<dynamic, dynamic> _m;

  bool get analysed => _m['analysed'] == true;
  bool get analysing => _m['analysing'] == true;
  bool get hasAudio => _m['hasAudio'] == true;
  bool get usable => _m['usable'] == true;
  double get bpm => (_m['bpm'] as num?)?.toDouble() ?? 0;
  double get beatConfidence => (_m['beatConfidence'] as num?)?.toDouble() ?? 0;
  String get key => _m['key'] as String? ?? '';
  double get mixIn => (_m['mixIn'] as num?)?.toDouble() ?? 0;
  double get mixOut => (_m['mixOut'] as num?)?.toDouble() ?? 0;
  bool get modelGrid => _m['modelGrid'] == true;
}

/// Inzx's side of Automix. The engine (analysis, planning, transitions) is
/// BitChord's, ported natively; this keeps its settings and feeds it audio.
///
/// Analysis reads each track's whole YouTube audio file from Inzx's stream
/// cache, whatever source is audible (lossless and JioSaavn tracks included),
/// the way BitChord analyses its canonical YouTube copy.
class AutomixService extends ChangeNotifier {
  AutomixService._() {
    _channel.setMethodCallHandler(_onCall);
  }
  static final AutomixService instance = AutomixService._();

  static const _channel = MethodChannel('inzx/automix');

  // Keys BitChord's AppSettings stand-in reads (minus the "flutter." prefix).
  static const _enabledKey = 'automix_enabled';
  static const _modeKey = 'automix_performance_mode';

  bool _enabled = false;
  AutomixPerformanceMode _mode = AutomixPerformanceMode.balanced;
  bool _loaded = false;

  /// Set by the player: downloads a track's YouTube audio into the stream
  /// cache when the analyzer asks for it.
  Future<void> Function(String videoId)? fetchAudio;

  // The transition engine's requests (BitChord's controller, native), set by
  // the player, which owns the queue and the two just_audio players.

  /// Load queue entry `index` onto player `playerId` at `cueMs`.
  Future<void> Function(String playerId, int index, int cueMs)? onLoad;

  /// The blend's midpoint: player `to` is now the song, at queue `index`.
  void Function(String from, String to, int index)? onHandoff;

  /// The outgoing (or abandoned incoming) player is done with.
  Future<void> Function(String playerId)? onRetire;

  /// The engine started or paused a player itself.
  void Function(String playerId, bool playing)? onPlayState;

  bool get enabled => _enabled;
  AutomixPerformanceMode get mode => _mode;

  // ---- Desktop -------------------------------------------------------------
  //
  // Desktop runs the same analysis and planning in Dart over the native
  // library in desktop/automix, and renders each blend rather than riding
  // live filters; see desktop/desktop_automix_engine.dart.

  DesktopAutomixEngine? _desktop;

  /// Whether Automix can run here: always on Android, on desktop when the
  /// native library and models were bundled.
  bool get available => !isDesktop || AutomixPaths.available;

  /// The desktop engine, once the player service has attached to it.
  DesktopAutomixEngine? get desktopEngine => _desktop;

  /// Called by the player service on desktop with the players it owns.
  Future<void> attachDesktopHost(DesktopAutomixHost host) async {
    if (!isDesktop || _desktop != null || !AutomixPaths.available) return;
    final dataDir = await appDataDirectory();
    final analyzer = DesktopTrackAnalyzer(
      storeDir: p.join(dataDir.path, 'automix_analysis'),
      scratchDir: host.scratchDir,
      threads: () => threadsFor(_mode),
    );
    _desktop = DesktopAutomixEngine(host: host, analyzer: analyzer)
      ..enabled = _enabled
      ..exclusiveOutput = DesktopAudioDsp.instance.exclusive
      ..inJam = _paused;
  }

  /// Logical processors available to the desktop app.
  int get logicalProcessors => Platform.numberOfProcessors;

  /// Desktop's analysis thread counts, based on the available processors.
  Map<String, int> _desktopThreads() {
    final processors = logicalProcessors;
    return {
      AutomixPerformanceMode.efficient.wire: 1,
      AutomixPerformanceMode.balanced.wire: math.max(
        2,
        math.min(4, processors ~/ 4),
      ),
      AutomixPerformanceMode.performance.wire: math.max(
        4,
        math.min(8, processors ~/ 2),
      ),
    };
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    if (isDesktop) {
      if (!AutomixPaths.available) return;
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_enabledKey) ?? false;
      _mode = AutomixPerformanceMode.fromWire(prefs.getString(_modeKey));
      _threads = _desktopThreads();
      _desktop?.enabled = _enabled;
      notifyListeners();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? false;
    _mode = AutomixPerformanceMode.fromWire(prefs.getString(_modeKey));
    notifyListeners();
    try {
      _threads = await _channel.invokeMapMethod<String, int>('threads') ?? const {};
      notifyListeners();
    } catch (_) {}
  }

  /// Analysis threads per mode, plus core counts reported by Android.
  Map<String, int> _threads = const {};

  int threadsFor(AutomixPerformanceMode mode) =>
      _threads[mode.wire] ?? mode.fallbackThreads;

  int? get cores => _threads['cores'];
  int? get fastCores => _threads['fastCores'];

  Future<void> setEnabled(bool on) async {
    _enabled = on;
    _desktop?.enabled = on;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_enabledKey, on);
  }

  Future<void> setMode(AutomixPerformanceMode mode) async {
    _mode = mode;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(_modeKey, mode.wire);
  }

  /// A complete YouTube audio file for [videoId] is in the stream cache.
  Future<void> audioCached(String videoId, String path) async {
    if (isDesktop) {
      _desktop?.audioCached(videoId, path);
      return;
    }
    try {
      await _channel.invokeMethod('registerAudio', {
        'videoId': videoId,
        'path': path,
      });
    } catch (_) {}
  }

  /// Queue analysis for [videoId] if Automix is on. Cheap to repeat.
  Future<void> request(String videoId, Duration duration) async {
    if (!_enabled) return;
    if (isDesktop) {
      _desktop?.request(videoId, duration);
      return;
    }
    try {
      await _channel.invokeMethod('request', {
        'videoId': videoId,
        'durationSeconds': duration.inMilliseconds / 1000.0,
      });
    } catch (e) {
      debugPrint('Automix: request failed: $e');
    }
  }

  Future<AutomixAnalysis?> analysis(String videoId) async {
    if (isDesktop) {
      final engine = _desktop;
      return engine == null ? null : AutomixAnalysis(engine.describe(videoId));
    }
    try {
      final m = await _channel.invokeMapMethod<dynamic, dynamic>('analysis', {
        'videoId': videoId,
      });
      return m == null ? null : AutomixAnalysis(m);
    } catch (_) {
      return null;
    }
  }

  /// Automix's stats-for-nerds line for the coming transition (BitChord's
  /// wording), or null while Automix is off.
  Future<String?> statsLine(String currentId, String? nextId) async {
    if (!_enabled) return null;
    if (isDesktop) return _desktop?.statsLine(currentId, nextId);
    try {
      return await _channel.invokeMethod<String>('statsLine', {
        'current': currentId,
        'next': nextId,
      });
    } catch (_) {
      return null;
    }
  }

  bool _inJam = false;
  bool _inConnectGroup = false;

  /// Automix is on, but paused while this device plays in sync with another
  /// over Inzx Connect ("Play on both"): each device would plan its own
  /// transition from its own analysis and blend at a different moment. The
  /// group leader's crossfade carries each song change instead.
  bool get pausedForConnect => _enabled && _inConnectGroup;

  Future<void> setInJam(bool inJam) async {
    _inJam = inJam;
    await _pushPaused();
  }

  /// Joining or leaving "Play on both", on either device.
  Future<void> setInConnectGroup(bool grouped) async {
    if (_inConnectGroup == grouped) return;
    _inConnectGroup = grouped;
    notifyListeners();
    await _pushPaused();
  }

  /// Jams and "Play on both" both stop the engine mixing (and analysing).
  bool get _paused => _inJam || _inConnectGroup;

  Future<void> _pushPaused() async {
    if (isDesktop) {
      _desktop?.inJam = _paused;
      return;
    }
    try {
      await _channel.invokeMethod('setInJam', {'inJam': _paused});
    } catch (_) {}
  }

  // ---- To the engine ------------------------------------------------------

  /// The players, the queue and which player is the song right now.
  Future<void> sync({
    required String primary,
    required String secondary,
    required String active,
    required int index,
    required List<Map<String, Object?>> queue,
    required String repeat,
    required double speed,
    required int crossfadeSeconds,
    Map<String, double> loudness = const {},
  }) async {
    if (isDesktop) {
      _desktop?.sync(
        primary: primary,
        secondary: secondary,
        active: active,
        index: index,
        repeat: repeat,
        queue: [
          for (final e in queue)
            QueueEntry(
              id: e['id'] as String? ?? '',
              title: e['title'] as String? ?? '',
              artist: e['artist'] as String? ?? '',
              durationMs: (e['durationMs'] as num?)?.toInt() ?? 0,
              isVideo: e['video'] == true,
            ),
        ],
      );
      return;
    }
    try {
      await _channel.invokeMethod('sync', {
        'loudness': loudness,
        'primary': primary,
        'secondary': secondary,
        'active': active,
        'index': index,
        'queue': queue,
        'repeat': repeat,
        'speed': speed,
        'crossfadeSeconds': crossfadeSeconds,
      });
    } catch (e) {
      debugPrint('Automix: sync failed: $e');
    }
  }

  Future<void> loaded(String playerId, int index) async {
    if (isDesktop) return;
    try {
      await _channel.invokeMethod('loaded', {'playerId': playerId, 'index': index});
    } catch (_) {}
  }

  /// A lossless/JioSaavn hand-over is using the spare player: the engine
  /// waits it out (as BitChord's waits out a version swap).
  Future<void> setBusy(bool busy) async {
    if (isDesktop) return;
    try {
      await _channel.invokeMethod('busy', {'busy': busy});
    } catch (_) {}
  }

  /// The listener asked for another song: drop any blend in flight.
  Future<void> skip() async {
    if (!_enabled) return;
    if (isDesktop) {
      await _desktop?.skip();
      return;
    }
    try {
      await _channel.invokeMethod('skip');
    } catch (_) {}
  }

  /// For the player UI: mixing now, progress, the planned window, the beat.
  Future<Map<dynamic, dynamic>?> mixState() async {
    if (!_enabled) return null;
    if (isDesktop) return _desktop?.mixState();
    try {
      return await _channel.invokeMapMethod<dynamic, dynamic>('mixState');
    } catch (_) {
      return null;
    }
  }

  // ---- From the engine ------------------------------------------------------

  Future<dynamic> _onCall(MethodCall call) async {
    final args = (call.arguments as Map?) ?? const {};
    switch (call.method) {
      case 'needAudio':
        final id = args['videoId'] as String?;
        if (id != null && _enabled) await fetchAudio?.call(id);
      case 'load':
        await onLoad?.call(
          args['playerId'] as String,
          args['index'] as int,
          (args['cueMs'] as num).toInt(),
        );
      case 'handoff':
        onHandoff?.call(
          args['from'] as String,
          args['to'] as String,
          args['index'] as int,
        );
      case 'retire':
        await onRetire?.call(args['playerId'] as String);
      case 'playState':
        onPlayState?.call(args['playerId'] as String, args['playing'] == true);
    }
    return null;
  }
}
