import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../audio_output_service.dart';
import '../automix/automix_service.dart';
import '../autoeq/desktop_auto_eq.dart';
import '../equalizer_service.dart';
import 'eq_chain.dart';

/// Desktop's equaliser, AutoEQ and bit-perfect output, all of it libmpv
/// settings on every player (the two just_audio players and Automix's blend
/// player).
///
/// * Equaliser + AutoEQ run as one lavfi chain in mpv's `af` (see
///   [EqChain]), rebuilt when either changes; flat means no filter at all.
///   Its overall gain (the preamps) rides on mpv's volume, which is cubic:
///   [volumeScale] is the gain's cube root.
/// * Bit-perfect output is WASAPI exclusive mode (`audio-exclusive`): the
///   device opens at the track's own sample rate and nothing else mixes in.
///   As on Android, the EQ and AutoEQ step aside while it's on, the
///   volume is held at 100%, and Automix / crossfades don't overlap tracks
///   (the device takes one stream). Windows only; Linux's PulseAudio /
///   PipeWire outputs have no exclusive mode.
class DesktopAudioDsp extends ChangeNotifier {
  DesktopAudioDsp._();
  static final DesktopAudioDsp instance = DesktopAudioDsp._();

  final _players = <mk.Player>{};
  bool _started = false;
  bool _exclusive = false;
  bool _shelves = !Platform.isWindows;
  MpvEq _eq = const MpvEq('', 0);
  Timer? _debounce;

  /// Bit-perfect (exclusive) output is on.
  bool get exclusive => _exclusive;

  /// Whether this platform can do exclusive output.
  static bool get exclusiveSupported => Platform.isWindows;

  /// The filter chain every player runs ('' when flat or bit-perfect).
  String get chain => _exclusive ? '' : _eq.af;

  /// What to multiply a player's mpv volume by for the chain's gain: mpv
  /// turns volume v into amplitude (v/100)^3, so a gain of g dB is a factor
  /// of 10^(g/60) on the volume.
  double get volumeScale => _exclusive ? 1.0 : math.pow(10, _eq.gainDb / 60).toDouble();

  /// mpv's default volume-max (130) only allows +6.8 dB; the chain's gain
  /// plus the app's own volume never needs more than this.
  static const _volumeMax = '400';

  /// Before the first player exists (from initDesktopPlatform). Rate changes
  /// then go to mpv's `speed` (pitch kept by mpv's own scaletempo2) instead
  /// of an `af=scaletempo` that would replace the equaliser chain; nothing
  /// in the app shifts pitch.
  void install() {
    JustAudioMediaKit.pitch = false;
    JustAudioMediaKit.onPlayerCreated = register;
    JustAudioMediaKit.onPlayerDisposed = unregister;
  }

  /// Reads the settings and starts following them.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    final prefs = await SharedPreferences.getInstance();
    _exclusive = exclusiveSupported && (prefs.getBool(AudioOutputService.bitPerfectKey) ?? false);
    _shelves = await _libmpvHasShelves();
    EqualizerService.instance.addListener(_schedule);
    DesktopAutoEq.instance.addListener(_schedule);
    await EqualizerService.instance.load();
    await DesktopAutoEq.instance.load();
    _applyExclusiveSideEffects();
    _rebuild();
  }

  void register(mk.Player player) {
    _players.add(player);
    unawaited(() async {
      await _prepare(player);
      await _applyTo(player, reloadOutput: false);
    }());
  }

  /// Once per player, before it opens the device. The bundled libmpv falls
  /// back from WASAPI to OpenAL Soft when the device is taken (another app
  /// in exclusive mode), and crashes the process there on any stream that
  /// needs a format conversion — i.e. every YouTube track. WASAPI alone,
  /// with mpv's null output as the fallback, keeps the player alive and
  /// its clock running silently until the device comes back.
  Future<void> _prepare(mk.Player player) async {
    if (!Platform.isWindows) return;
    final native = player.platform;
    if (native is! mk.NativePlayer) return;
    try {
      await native.setProperty('ao', 'wasapi');
      await native.setProperty('audio-fallback-to-null', 'yes');
    } catch (e) {
      debugPrint('DesktopAudioDsp: preparing a player failed: $e');
    }
  }

  void unregister(mk.Player player) => _players.remove(player);

  Future<void> setExclusive(bool on) async {
    on = on && exclusiveSupported;
    await (await SharedPreferences.getInstance()).setBool(AudioOutputService.bitPerfectKey, on);
    if (_exclusive == on) return;
    _exclusive = on;
    _applyExclusiveSideEffects();
    notifyListeners();
    for (final pl in List.of(_players)) {
      await _applyTo(pl, reloadOutput: true);
    }
  }

  void _applyExclusiveSideEffects() {
    JustAudioMediaKit.fixedVolume = _exclusive ? 100.0 : null;
    JustAudioMediaKit.volumeScale = volumeScale;
    unawaited(JustAudioMediaKit.refreshVolumes());
    AutomixService.instance.desktopEngine?.exclusiveOutput = _exclusive;
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
    final eqNow = chain.toMpv(shelves: _shelves);
    if (eqNow == _eq) return;
    final filtersChanged = eqNow.af != _eq.af;
    _eq = eqNow;
    debugPrint('DesktopAudioDsp: af = ${eqNow.af.isEmpty ? '(none)' : eqNow.af}, '
        'gain ${eqNow.gainDb.toStringAsFixed(2)} dB');
    notifyListeners();
    if (_exclusive) return;
    JustAudioMediaKit.volumeScale = volumeScale;
    unawaited(JustAudioMediaKit.refreshVolumes());
    if (!filtersChanged) return;
    for (final pl in List.of(_players)) {
      unawaited(_applyTo(pl, reloadOutput: false));
    }
  }

  Future<void> _applyTo(mk.Player player, {required bool reloadOutput}) async {
    final native = player.platform;
    if (native is! mk.NativePlayer) return;
    try {
      await native.setProperty('volume-max', _volumeMax);
      await native.setProperty('af', chain);
      await native.setProperty('audio-exclusive', _exclusive ? 'yes' : 'no');
      if (reloadOutput) await native.command(['ao-reload']);
      if (_exclusive) await player.setVolume(100);
    } catch (e) {
      debugPrint('DesktopAudioDsp: applying to a player failed: $e');
    }
  }

  /// What the active output is doing, for the Output card: the format the
  /// device was opened with and the source's own.
  Future<Map<String, Object?>> describe() async {
    final out = <String, Object?>{
      'bitPerfectSupported': exclusiveSupported,
      'bitPerfectRequested': _exclusive,
      'hiResOutput': true,
    };
    for (final pl in _players) {
      final native = pl.platform;
      if (native is! mk.NativePlayer || !pl.state.playing) continue;
      try {
        final rate = int.tryParse(await native.getProperty('audio-params/samplerate'));
        final format = await native.getProperty('audio-params/format');
        final outRate = int.tryParse(await native.getProperty('audio-out-params/samplerate'));
        final outFormat = await native.getProperty('audio-out-params/format');
        out['trackSampleRate'] = rate;
        out['trackEncoding'] = format;
        out['outSampleRate'] = outRate;
        out['outEncoding'] = outFormat;
        out['bitPerfectActive'] = _exclusive && rate != null && rate == outRate;
      } catch (_) {}
      break;
    }
    return out;
  }

  /// The libmpv media_kit bundles on Windows has only `equalizer` among
  /// FFmpeg's biquads (and `volume`); a full libmpv (Linux's system one)
  /// has the shelves. Filter names sit in the binary as plain strings.
  static Future<bool> _libmpvHasShelves() async {
    if (!Platform.isWindows) return true;
    final dll = p.join(p.dirname(Platform.resolvedExecutable), 'libmpv-2.dll');
    try {
      return await Isolate.run(() {
        final bytes = File(dll).readAsBytesSync();
        return _contains(bytes, '\u0000lowshelf\u0000'.codeUnits) &&
            _contains(bytes, '\u0000highshelf\u0000'.codeUnits);
      });
    } catch (_) {
      return false;
    }
  }

  static bool _contains(Uint8List hay, List<int> needle) {
    final first = needle[0];
    final last = hay.length - needle.length;
    outer:
    for (var i = 0; i <= last; i++) {
      if (hay[i] != first) continue;
      for (var j = 1; j < needle.length; j++) {
        if (hay[i + j] != needle[j]) continue outer;
      }
      return true;
    }
    return false;
  }
}
