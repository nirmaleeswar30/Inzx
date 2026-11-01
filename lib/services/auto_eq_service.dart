import 'package:flutter/services.dart';

/// One headphone in the AutoEQ database.
class AutoEqHeadphone {
  const AutoEqHeadphone(this.name, this.subtitle, this.path, this.inEar);
  final String name;
  final String subtitle;
  final String path;
  final bool inEar;

  factory AutoEqHeadphone.fromMap(Map m) => AutoEqHeadphone(
    m['name'] as String,
    m['subtitle'] as String? ?? '',
    m['path'] as String,
    m['inEar'] == true,
  );
}

/// The AutoEQ correction as the native side (LastWave's controller) has it.
class AutoEqState {
  const AutoEqState(this._m);
  final Map _m;

  bool get enabled => _m['enabled'] == true;
  bool get busy => _m['busy'] == true;
  bool get autoPerDevice => _m['autoPerDevice'] != false;
  AutoEqHeadphone? get headphone =>
      _m['entry'] == null ? null : AutoEqHeadphone.fromMap(_m['entry'] as Map);
  String get targetId => _m['targetId'] as String? ?? 'default';
  double get bassDb => (_m['bassDb'] as num?)?.toDouble() ?? 0;
  double get tiltDb => (_m['tiltDb'] as num?)?.toDouble() ?? 0;
  bool get isCustom => _m['isCustom'] == true;
  double get preampDb => (_m['preampDb'] as num?)?.toDouble() ?? 0;
  int get filterCount => (_m['filterCount'] as num?)?.toInt() ?? 0;

  List<({String id, String name, String family})> get targets => [
    for (final t in (_m['targets'] as List? ?? const []))
      (
        id: (t as Map)['id'] as String,
        name: t['name'] as String,
        family: t['family'] as String? ?? '',
      ),
  ];

  ({String key, String label})? get device {
    final d = _m['device'] as Map?;
    return d == null ? null : (key: d['key'] as String, label: d['label'] as String);
  }

  List<({String key, String label, String? headphone})> get savedDevices => [
    for (final d in (_m['savedDevices'] as List? ?? const []))
      (
        key: (d as Map)['key'] as String,
        label: d['label'] as String,
        headphone: d['headphone'] as String?,
      ),
  ];

  List<double> get curveHz =>
      [for (final v in (_m['curveHz'] as List? ?? const [])) (v as num).toDouble()];
  List<double> get curveDb =>
      [for (final v in (_m['curveDb'] as List? ?? const [])) (v as num).toDouble()];
}

/// AutoEQ, ported from LastWave: headphone correction from the AutoEQ
/// database (Jaakko Pasanen, MIT), with LastWave's target/bass/tilt refitting
/// and per-device profiles. The correction runs natively on every player.
class AutoEqService {
  static const _channel = MethodChannel('inzx/autoeq');

  static Future<AutoEqState?> _state(String method, [Map<String, Object?>? args]) async {
    final m = await _channel.invokeMethod<Map>(method, args);
    return m == null ? null : AutoEqState(m);
  }

  static Future<AutoEqState?> state() => _state('state');

  static Future<List<AutoEqHeadphone>> search(String query) async {
    final rows = await _channel.invokeMethod<List>('search', {'query': query});
    return [for (final r in rows ?? const []) AutoEqHeadphone.fromMap(r as Map)];
  }

  static Future<AutoEqState?> select(AutoEqHeadphone h) => _state('select', {'path': h.path});
  static Future<AutoEqState?> setEnabled(bool on) => _state('setEnabled', {'on': on});
  static Future<AutoEqState?> setAutoPerDevice(bool on) =>
      _state('setAutoPerDevice', {'on': on});
  static Future<AutoEqState?> setTarget(String id) => _state('setTarget', {'id': id});
  static Future<AutoEqState?> setBass(double db) => _state('setBass', {'db': db});
  static Future<AutoEqState?> setTilt(double db) => _state('setTilt', {'db': db});
  static Future<AutoEqState?> reset() => _state('reset');
  static Future<AutoEqState?> clear() => _state('clear');
  static Future<AutoEqState?> saveForDevice() => _state('saveForDevice');
  static Future<AutoEqState?> forgetDevice(String key) =>
      _state('forgetDevice', {'key': key});
}
