/// `package:media_kit` bindings for `just_audio` to support Linux and Windows.
library just_audio_media_kit;

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:just_audio_media_kit/mediakit_player.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart';
import 'package:universal_platform/universal_platform.dart';

class JustAudioMediaKit extends JustAudioPlatform {
  JustAudioMediaKit();

  /// The internal MPV player's logLevel
  static MPVLogLevel mpvLogLevel = MPVLogLevel.error;

  /// Sets the demuxer's cache size (in bytes)
  static int bufferSize = 32 * 1024 * 1024;

  /// Sets the name of the underlying window & process for native backend. This is visible inside the Windows' volume mixer.
  static String title = 'JustAudioMediaKit';

  /// Sets the list of allowed protocols for native backend.
  static List<String> protocolWhitelist = const [
    'udp',
    'rtp',
    'tcp',
    'tls',
    'data',
    'file',
    'http',
    'https',
    'crypto',
  ];

  /// Enables or disables pitch shift control for native backend (with this set to false, [setPitch] won't work).
  ///
  /// This uses `scaletempo` under the hood & disables `audio-pitch-correction`.
  static bool pitch = true;

  /// Enables gapless playback via the [`--prefetch-playlist`](https://mpv.io/manual/stable/#options-prefetch-playlist) in libmpv
  ///
  /// This is highly experimental. Use at your own risk.
  ///
  /// Check [mpv's docs](https://mpv.io/manual/stable/#options-prefetch-playlist) and
  /// [the related issue](https://github.com/Pato05/just_audio_media_kit/issues/11) for more information
  static bool prefetchPlaylist = false;

  /// Inzx: called with each new player's media_kit [Player] once it is
  /// ready, before anything is loaded into it, so the app can set mpv
  /// properties on it (its equaliser chain, exclusive output).
  static void Function(Player player)? onPlayerCreated;

  /// Inzx: called when a player is about to be released.
  static void Function(Player player)? onPlayerDisposed;

  /// Inzx: when set, every player's mpv volume (percent) is held at this,
  /// whatever just_audio asks for. Bit-perfect output needs exactly 100.
  static double? fixedVolume;

  /// Inzx: every volume just_audio asks for is multiplied by this before it
  /// reaches mpv (the equaliser's preamp: the bundled libmpv has no gain
  /// filter, so it rides on mpv's own volume). Players need a `volume-max`
  /// high enough for it.
  static double volumeScale = 1.0;

  static final _live = <MediaKitPlayer>{};

  static final _trackGains = <String, double>{};

  /// Inzx: a linear gain for one player (by just_audio player id) on top of
  /// everything else: loudness normalization, which levels each player for
  /// the song it is playing. Applied at once if the player is live.
  static void setTrackGain(String playerId, double gain) {
    if (_trackGains[playerId] == gain) return;
    _trackGains[playerId] = gain;
    for (final p in _live) {
      if (p.id == playerId) unawaited(p.reapplyVolume().catchError((_) {}));
    }
  }

  /// Inzx: what to multiply [playerId]'s mpv volume by for its track gain.
  /// mpv turns volume v into amplitude (v/100)^3, hence the cube root.
  static double volumeFactorFor(String playerId) {
    final g = _trackGains[playerId] ?? 1.0;
    return g == 1.0 ? 1.0 : math.pow(g, 1 / 3).toDouble();
  }

  /// Inzx: applies a changed [fixedVolume] to every live player.
  static Future<void> refreshVolumes() async {
    for (final p in List.of(_live)) {
      try {
        await p.reapplyVolume();
      } catch (_) {}
    }
  }

  static final _logger = Logger('JustAudioMediaKit');
  final _players = HashMap<String, MediaKitPlayer>();

  /// Players that are disposing (player id -> future that completes when the player is disposed)
  final _disposingPlayers = HashMap<String, Future<void>>();

  /// Initializes the plugin if the platform we're running on is marked
  /// as true, otherwise it will leave everything unchanged.
  ///
  /// Can also be safely called from Web, even though it'll have no effect
  static void ensureInitialized({
    bool linux = true,
    bool windows = true,
    bool android = false,
    bool iOS = false,
    bool macOS = false,

    /// The path to the libmpv dynamic library.
    /// The name of the library is generally `libmpv.so` on GNU/Linux and `libmpv-2.dll` on Windows.
    String? libmpv,
  }) {
    if ((UniversalPlatform.isLinux && linux) ||
        (UniversalPlatform.isWindows && windows) ||
        (UniversalPlatform.isAndroid && android) ||
        (UniversalPlatform.isIOS && iOS) ||
        (UniversalPlatform.isMacOS && macOS)) {
      registerWith();
      MediaKit.ensureInitialized(libmpv: libmpv);
    }
  }

  /// Registers the plugin with [JustAudioPlatform]
  static void registerWith() {
    JustAudioPlatform.instance = JustAudioMediaKit();
  }

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    if (_players.containsKey(request.id)) {
      throw PlatformException(
          code: 'error', message: 'Player ${request.id} already exists!');
    }

    _logger.fine('instantiating new player ${request.id}');
    final player = MediaKitPlayer(request.id);
    _players[request.id] = player;
    await player.ready();
    _live.add(player);
    onPlayerCreated?.call(player.mediaKitPlayer);
    _logger.fine('player ready! (players: $_players)');
    return player;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
      DisposePlayerRequest request) async {
    _logger.fine('disposing player ${request.id}');

    // temporary workaround because disposePlayer is called more than once
    if (_disposingPlayers.containsKey(request.id)) {
      _logger.fine('disposePlayer() called more than once!');
      await _disposingPlayers[request.id]!;
      return DisposePlayerResponse();
    }

    if (!_players.containsKey(request.id)) {
      throw PlatformException(
          code: 'error', message: 'Player ${request.id} doesn\'t exist.');
    }

    _live.remove(_players[request.id]);
    onPlayerDisposed?.call(_players[request.id]!.mediaKitPlayer);
    final future = _players[request.id]!.release();
    _players.remove(request.id);
    _disposingPlayers[request.id] = future;
    await future;
    _disposingPlayers.remove(request.id);

    _logger.fine('player ${request.id} disposed!');
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
      DisposeAllPlayersRequest request) async {
    _logger.fine('disposing of all players...');
    if (_players.isNotEmpty) {
      for (final p in _players.values) {
        _live.remove(p);
        onPlayerDisposed?.call(p.mediaKitPlayer);
      }
      await Future.wait(_players.values.map((e) => e.release()));
      _players.clear();
    }
    return DisposeAllPlayersResponse();
  }
}
