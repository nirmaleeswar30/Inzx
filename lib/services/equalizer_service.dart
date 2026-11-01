import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Starting points for the equaliser, one gain (dB) per band in
/// [EqualizerService.bandsHz]. Kept modest (nothing near the ±12 dB the
/// sliders allow): every decibel of boost costs headroom.
enum EqualizerPreset {
  flat('Flat', [0, 0, 0, 0, 0, 0, 0]),
  bassBoost('Bass boost', [5, 3.5, 1, 0, 0, 0, 0]),
  bassReducer('Bass reducer', [-5, -3, -1, 0, 0, 0, 0]),
  trebleBoost('Treble boost', [0, 0, 0, 0, 1, 3, 4.5]),
  trebleReducer('Treble reducer', [0, 0, 0, 0, -1, -3, -4.5]),
  vocal('Vocal', [-2, -1, 1, 3, 2.5, 1, 0]),
  pop('Pop', [-1, 1, 2, 2.5, 1, -0.5, -1]),
  rock('Rock', [3.5, 2, -1, -1, 1, 2.5, 3]),
  hipHop('Hip-hop', [5, 3.5, 0, -1, 0.5, 1.5, 2]),
  electronic('Electronic', [4.5, 3, 0, -1, 1, 2.5, 4]),
  jazz('Jazz', [2.5, 1.5, 0, 1, 1.5, 2, 2.5]),
  classical('Classical', [2.5, 1.5, 0, 0, 1, 2, 3]),
  acoustic('Acoustic', [2.5, 1.5, 0, 1, 2, 1.5, 1]),
  loudness('Loudness', [5, 3, 0, -1, -0.5, 2, 4]),
  lateNight('Late night', [2, 1, 0, 1, 0.5, -1, -2.5]),
  smallSpeakers('Small speakers', [4, 3, 1.5, 0, 0, -1, -1.5]),
  custom('Custom', []);

  const EqualizerPreset(this.label, this.gains);
  final String label;
  final List<double> gains;

  /// The preset these gains are, or [custom].
  static EqualizerPreset matching(List<double> gains) {
    for (final p in values) {
      if (p == custom || p.gains.length != gains.length) continue;
      var same = true;
      for (var i = 0; i < gains.length; i++) {
        if ((p.gains[i] - gains[i]).abs() > 0.05) {
          same = false;
          break;
        }
      }
      if (same) return p;
    }
    return custom;
  }
}

/// The equaliser's settings. The audio itself is processed natively
/// (android/.../audio/InzxEqualizer.kt), which reads these keys from shared
/// preferences and follows changes live.
class EqualizerService extends ChangeNotifier {
  EqualizerService._();
  static final EqualizerService instance = EqualizerService._();

  static const bandsHz = [60, 150, 400, 1000, 2500, 6000, 14000];
  static const double maxDb = 12;

  // Must match InzxEqualizer.KEY_* (minus the "flutter." prefix).
  static const _enabledKey = 'inzx_eq_enabled';
  static const _bandsKey = 'inzx_eq_bands';

  bool _enabled = false;
  List<double> _gains = List.filled(bandsHz.length, 0);
  bool _loaded = false;

  bool get enabled => _enabled;
  List<double> get gains => List.unmodifiable(_gains);
  EqualizerPreset get preset => EqualizerPreset.matching(_gains);

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? false;
    final saved = prefs.getString(_bandsKey);
    if (saved != null) {
      final parsed = saved.split(',').map(double.tryParse).toList();
      _gains = List.generate(
        bandsHz.length,
        (i) => ((i < parsed.length ? parsed[i] : null) ?? 0.0)
            .clamp(-maxDb, maxDb)
            .toDouble(),
      );
    }
    notifyListeners();
  }

  Future<void> setEnabled(bool on) async {
    _enabled = on;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_enabledKey, on);
  }

  Future<void> setBand(int index, double db) async {
    _gains[index] = (db * 2).roundToDouble() / 2; // 0.5 dB steps
    notifyListeners();
    await _saveGains();
  }

  Future<void> applyPreset(EqualizerPreset preset) async {
    if (preset == EqualizerPreset.custom) return;
    _gains = List.of(preset.gains);
    if (!_enabled) _enabled = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, true);
    await _saveGains();
  }

  Future<void> _saveGains() async {
    await (await SharedPreferences.getInstance()).setString(
      _bandsKey,
      _gains.map((g) => g.toStringAsFixed(1)).join(','),
    );
  }

  static String bandLabel(int hz) =>
      hz >= 1000 ? '${hz % 1000 == 0 ? hz ~/ 1000 : (hz / 1000).toStringAsFixed(1)}k' : '$hz';
}
