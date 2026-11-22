import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart' as ja;
import 'package:media_kit/media_kit.dart' as mk;

import '../../desktop/desktop_audio_dsp.dart';

/// The player Automix plays a rendered blend on, between the two song
/// players. libmpv (media_kit) on desktop, where it also runs the equaliser
/// chain; a just_audio player on iOS, whose items get the same audio tap as
/// the song players.
abstract class BlendClipPlayer {
  factory BlendClipPlayer.forPlatform() =>
      Platform.isIOS ? _JustAudioClipPlayer() : _MediaKitClipPlayer();

  bool get playing;
  Duration get position;
  Duration get duration;

  /// Loads the clip at [path], paused.
  Future<void> open(String path);

  /// Starts playing; returns once started, not when the clip ends.
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);

  /// Linear gain, 0 to 1.
  Future<void> setGain(double gain);
  Future<void> setRate(double rate);
  Future<void> dispose();
}

class _MediaKitClipPlayer implements BlendClipPlayer {
  _MediaKitClipPlayer() {
    DesktopAudioDsp.instance.register(_player);
  }

  final mk.Player _player = mk.Player();

  @override
  bool get playing => _player.state.playing;
  @override
  Duration get position => _player.state.position;
  @override
  Duration get duration => _player.state.duration;

  @override
  Future<void> open(String path) => _player.open(mk.Media(Uri.file(path).toString()), play: false);
  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  // mpv's volume is 0-100 and carries the equaliser chain's gain.
  @override
  Future<void> setGain(double gain) =>
      _player.setVolume(gain * 100 * DesktopAudioDsp.instance.volumeScale);
  @override
  Future<void> setRate(double rate) => _player.setRate(rate);
  @override
  Future<void> dispose() async {
    DesktopAudioDsp.instance.unregister(_player);
    await _player.dispose();
  }
}

class _JustAudioClipPlayer implements BlendClipPlayer {
  final ja.AudioPlayer _player = ja.AudioPlayer(handleInterruptions: false);

  @override
  bool get playing => _player.playing;
  @override
  Duration get position => _player.position;
  @override
  Duration get duration => _player.duration ?? Duration.zero;

  @override
  Future<void> open(String path) async {
    await _player.setAudioSource(ja.AudioSource.file(path), preload: true);
  }

  @override
  Future<void> play() async {
    // just_audio's play() completes when playback stops.
    unawaited(_player.play().catchError((Object _) {}));
  }

  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> setGain(double gain) => _player.setVolume(gain.clamp(0.0, 1.0));
  @override
  Future<void> setRate(double rate) => _player.setSpeed(rate);
  @override
  Future<void> dispose() => _player.dispose();
}
