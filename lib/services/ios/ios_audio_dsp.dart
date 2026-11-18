import 'dart:async';

import 'package:flutter/foundation.dart';

import '../autoeq/desktop_auto_eq.dart';
import '../desktop/desktop_loudness.dart';
import '../desktop/eq_chain.dart';
import '../equalizer_service.dart';
import 'ios_native.dart';

/// iOS's equaliser and AutoEQ: the same filter chain desktop builds for
/// libmpv ([EqChain]: the equaliser's shelves and bells, then the AutoEQ
/// correction, and their preamps), run by the audio tap the inzx_ios plugin
/// attaches to every item the just_audio players queue. Shelves and passes
/// are real biquads there, as on Android, so nothing is approximated.
///
/// Loudness normalization rides on the same tap as a per-player gain (see
/// the player service's loudness wiring), which unlike AVPlayer's volume can
/// lift a quiet master as well as lower a loud one.
class IosAudioDsp {
  IosAudioDsp._();
  static final IosAudioDsp instance = IosAudioDsp._();

  bool _started = false;
  Timer? _debounce;
  String _sent = '';

  Future<void> start() async {
    if (_started) return;
    _started = true;
    EqualizerService.instance.addListener(_schedule);
    DesktopAutoEq.instance.addListener(_schedule);
    await EqualizerService.instance.load();
    await DesktopAutoEq.instance.load();
    await DesktopLoudness.instance.load();
    _rebuild();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 40), _rebuild);
  }

  void _rebuild() {
    final eq = EqualizerService.instance;
    var chain = eq.enabled ? EqChain.equalizer(eq.gains) : EqChain.empty;
    final auto = DesktopAutoEq.instance.active;
    if (auto != null) chain = chain + EqChain.autoEq(auto);
    final flat = chain.isFlat;
    final filters = <Map<String, Object>>[
      if (!flat)
        for (final f in chain.filters)
          if (f.enabled && (!f.type.hasGain || f.gainDb.abs() >= 0.01))
            {
              'type': f.type.nativeId,
              'f': f.frequencyHz,
              'g': f.gainDb,
              'q': f.q,
            },
    ];
    final preamp = flat ? 0.0 : chain.volumeDb;
    final key = '$preamp|$filters';
    if (key == _sent) return;
    _sent = key;
    debugPrint('IosAudioDsp: ${filters.length} filters, preamp ${preamp.toStringAsFixed(2)} dB');
    unawaited(IosNative.setDspChain(preamp, filters));
  }

  /// Loudness gain for one player (linear, 1 for none).
  void setTrackGain(String playerId, double gain) =>
      unawaited(IosNative.setTrackGain(playerId, gain));
}
