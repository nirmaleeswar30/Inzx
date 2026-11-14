import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../audio_output_service.dart';
import 'desktop_output_device.dart';

/// Loudness normalization on desktop: Android's LoudnessGains.kt (BitChord's
/// `loudnessGainMb`) in Dart. Each song is brought to YouTube's reference by
/// minus its `loudnessDb`, in millibels clamped to [-15 dB, +3 dB].
///
/// The gain is applied per player (each one levelled for the song it is
/// actually playing, so both sides of a crossfade are right), through mpv's
/// volume; Automix's rendered blends bake each side's gain in instead. The
/// figures come with the queue, the same picture Android's engine is sent.
///
/// BitChord skips it on the phone's own speaker, where levelling a loud
/// master down mostly just makes it quieter. The desktop reading of that
/// setting is "speakers" as Windows reports the output (not headphones);
/// Linux doesn't report it, so there normalization just follows its switch.
class DesktopLoudness extends ChangeNotifier {
  DesktopLoudness._();
  static final DesktopLoudness instance = DesktopLoudness._();

  static const _minGainMb = -1500;
  static const _maxGainMb = 300;

  final _loudnessDb = <String, double>{};
  bool _enabled = true;
  bool _offOnSpeaker = true;
  bool _loaded = false;

  bool get enabled => _enabled;
  bool get offOnSpeaker => _offOnSpeaker;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(AudioOutputService.loudnessKey) ?? true;
    _offOnSpeaker = prefs.getBool(AudioOutputService.loudnessOffOnSpeakerKey) ?? true;
    DesktopOutputDevice.instance.addListener(notifyListeners);
    notifyListeners();
  }

  /// YouTube's figures for queued songs, by video id. Only grows, like
  /// Android's map: a figure never changes for a song.
  void update(Map<String, double> figures) {
    var changed = false;
    figures.forEach((id, db) {
      if (_loudnessDb[id] != db) {
        _loudnessDb[id] = db;
        changed = true;
      }
    });
    if (changed) notifyListeners();
  }

  void setEnabled(bool on) {
    if (_enabled == on) return;
    _enabled = on;
    notifyListeners();
  }

  void setOffOnSpeaker(bool on) {
    if (_offOnSpeaker == on) return;
    _offOnSpeaker = on;
    notifyListeners();
  }

  /// Linear gain for [trackId]: 1 when off, on speakers, or unknown.
  double gainFor(String? trackId) {
    if (trackId == null || !_enabled) return 1;
    if (_offOnSpeaker && (DesktopOutputDevice.instance.current?.isSpeakers ?? false)) return 1;
    final db = _loudnessDb[trackId];
    if (db == null) return 1;
    final mb = (-db * 100).round().clamp(_minGainMb, _maxGainMb);
    return math.pow(10, mb / 2000).toDouble();
  }
}
