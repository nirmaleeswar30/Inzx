import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the native output layer (android/.../audio/InzxAudioOutput.kt)
/// reports about the last audio track: its format and whether it went to a
/// USB DAC bit-perfect.
class AudioOutputStatus {
  const AudioOutputStatus({
    required this.bitPerfectSupported,
    required this.bitPerfectRequested,
    required this.hiResOutput,
    this.usbDac,
    this.trackSampleRate,
    this.trackEncoding,
    this.trackBitDepth,
    this.bitPerfectActive = false,
    this.bitPerfectDevice,
    this.bitPerfectReason,
  });

  final bool bitPerfectSupported;
  final bool bitPerfectRequested;
  final bool hiResOutput;
  final String? usbDac;
  final int? trackSampleRate;
  final String? trackEncoding;
  final int? trackBitDepth;
  final bool bitPerfectActive;
  final String? bitPerfectDevice;
  final String? bitPerfectReason;

  factory AudioOutputStatus.fromMap(Map<dynamic, dynamic> m) =>
      AudioOutputStatus(
        bitPerfectSupported: m['bitPerfectSupported'] == true,
        bitPerfectRequested: m['bitPerfectRequested'] == true,
        hiResOutput: m['hiResOutput'] != false,
        usbDac: m['usbDac'] as String?,
        trackSampleRate: m['trackSampleRate'] as int?,
        trackEncoding: m['trackEncoding'] as String?,
        trackBitDepth: m['trackBitDepth'] as int?,
        bitPerfectActive: m['bitPerfectActive'] == true,
        bitPerfectDevice: m['bitPerfectDevice'] as String?,
        bitPerfectReason: m['bitPerfectReason'] as String?,
      );
}

/// Output settings. The native side reads them straight from shared
/// preferences when it creates each track, so no call is needed to apply
/// them: bit-perfect takes effect from the next track, hi-res output from
/// the next app start (it's fixed when a player is created).
class AudioOutputService {
  static const _channel = MethodChannel('inzx/audio_output');

  // Must match InzxAudioOutput.KEY_* (without the "flutter." prefix that
  // shared_preferences adds on Android).
  static const hiResKey = 'inzx_hires_output';
  static const bitPerfectKey = 'inzx_bitperfect_usb';

  static Future<AudioOutputStatus?> describe() async {
    try {
      final m = await _channel.invokeMapMethod<dynamic, dynamic>('describe');
      return m == null ? null : AudioOutputStatus.fromMap(m);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> hiResOutput() async =>
      (await SharedPreferences.getInstance()).getBool(hiResKey) ?? true;

  static Future<bool> bitPerfectUsb() async =>
      (await SharedPreferences.getInstance()).getBool(bitPerfectKey) ?? false;

  static Future<void> setHiResOutput(bool on) async =>
      (await SharedPreferences.getInstance()).setBool(hiResKey, on);

  static Future<void> setBitPerfectUsb(bool on) async =>
      (await SharedPreferences.getInstance()).setBool(bitPerfectKey, on);

  // Loudness normalization (BitChord's, native: LoudnessGains.kt). Both on
  // by default, as in BitChord; read live by the audio thread.
  static const loudnessKey = 'loudness_normalization';
  static const loudnessOffOnSpeakerKey = 'loudness_off_on_speaker';

  static Future<bool> loudnessNormalization() async =>
      (await SharedPreferences.getInstance()).getBool(loudnessKey) ?? true;

  static Future<bool> loudnessOffOnSpeaker() async =>
      (await SharedPreferences.getInstance()).getBool(loudnessOffOnSpeakerKey) ??
      true;

  static Future<void> setLoudnessNormalization(bool on) async =>
      (await SharedPreferences.getInstance()).setBool(loudnessKey, on);

  static Future<void> setLoudnessOffOnSpeaker(bool on) async =>
      (await SharedPreferences.getInstance()).setBool(loudnessOffOnSpeakerKey, on);
}
