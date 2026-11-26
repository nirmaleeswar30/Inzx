import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../services/canvas/mpv_canvas_player.dart';
import '../../services/playback/yt_player_utils.dart';

/// What the podcast screen can do with whichever player it has.
abstract interface class PodcastPlayerHandle {
  Future<void> seekTo(int seconds);
}

/// Plays a podcast episode in the app on Linux, straight from YouTube's
/// streams through libmpv ([MpvCanvasPlayer]): the separate video and audio
/// streams (up to 720p, since frames are decoded on the CPU), else a muxed
/// file, else the HLS manifest (see [_startMpv] for the order). Linux has
/// no web view the YouTube embed could run in.
///
/// (Windows keeps the embed in WebView2: Media Foundation can't play
/// YouTube's HLS, and the bundled libmpv decodes audio only.)
///
/// [onUnavailable] is called when there's nothing it can play.
class DesktopPodcastPlayer extends StatefulWidget {
  const DesktopPodcastPlayer({
    super.key,
    required this.videoId,
    required this.accent,
    this.volume = 1.0,
    this.fullscreen = false,
    this.onToggleFullscreen,
    this.onUnavailable,
  });

  final String videoId;
  final Color accent;

  /// Inzx's own volume (the player bar's slider), 0..1.
  final double volume;

  /// Whether the page shows only this player, the window fullscreen.
  final bool fullscreen;
  final VoidCallback? onToggleFullscreen;
  final VoidCallback? onUnavailable;

  @override
  State<DesktopPodcastPlayer> createState() => DesktopPodcastPlayerState();
}

class DesktopPodcastPlayerState extends State<DesktopPodcastPlayer>
    implements PodcastPlayerHandle {
  MpvCanvasPlayer? _mpv;
  bool _loading = true;
  bool _controlsVisible = true;
  Timer? _hideTimer;
  final _position = ValueNotifier<_Playback>(const _Playback());

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final stream = await YTPlayerUtils.instance.videoStreamFor(
      widget.videoId,
      maxHeight: 720,
    );
    if (!mounted) return;
    final ok = stream != null && await _startMpv(stream);
    if (!mounted) return;
    if (!ok) {
      widget.onUnavailable?.call();
      return;
    }
    setState(() => _loading = false);
    _scheduleHide();
  }

  /// Tries each source the stream offers until one opens: the separate
  /// video and audio streams first (they open in a second or two), then the
  /// muxed file, then HLS. HLS is last because YouTube's master playlists
  /// now list dozens of auto-dubbed audio renditions, and FFmpeg's HLS
  /// demuxer opens every one of them before the first frame, which can take
  /// longer than any sensible timeout.
  Future<bool> _startMpv(VideoStream stream) async {
    final base = <String, String>{
      'aid': 'auto',
      'loop-file': 'no',
      'cache': 'yes',
      // mpv's volume is cubic (see DesktopAudioDsp): this matches the slider.
      'volume': (widget.volume * 100).toStringAsFixed(1),
    };
    final attempts = <(String, Map<String, String>, Duration)>[
      if (stream.video != null && stream.audio != null)
        (stream.video!, {...base, 'audio-files-append': stream.audio!}, const Duration(seconds: 15)),
      if (stream.muxed != null) (stream.muxed!, base, const Duration(seconds: 15)),
      // The best variant up to ~720p (frames are decoded and scaled on the
      // CPU here).
      if (stream.hls != null)
        (stream.hls!, {...base, 'hls-bitrate': '3500000'}, const Duration(seconds: 25)),
    ];
    MpvCanvasPlayer? player;
    for (final (source, options, timeout) in attempts) {
      final candidate = MpvCanvasPlayer(maxSide: 1280, options: options);
      final ok = await candidate.open(source, timeout: timeout);
      if (!mounted) {
        candidate.dispose();
        return false;
      }
      if (ok) {
        player = candidate;
        break;
      }
      candidate.dispose();
    }
    if (player == null) return false;
    final opened = player;
    opened.playback.addListener(() {
      final s = opened.playback.value;
      _position.value = _Playback(
        position: s.position,
        duration: s.duration,
        playing: !s.paused && !s.ended,
        buffering: s.buffering,
      );
    });
    opened.play();
    _mpv = opened;
    return true;
  }

  @override
  Future<void> seekTo(int seconds) async {
    _mpv?.seek(Duration(seconds: seconds));
  }

  void _togglePlay() {
    final playing = _position.value.playing;
    if (playing) {
      _mpv?.pause();
    } else {
      _mpv?.play();
    }
    _showControls();
  }

  void _showControls() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _position.value.playing) setState(() => _controlsVisible = false);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _mpv?.dispose();
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2.5, color: widget.accent),
        ),
      );
    }
    final mpv = _mpv!;
    final Size size = mpv.size;
    return MouseRegion(
      onHover: (_) => _showControls(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _togglePlay,
        child: ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: size.width > 0 ? size.width : 16,
                  height: size.height > 0 ? size.height : 9,
                  child: MpvCanvasView(mpv),
                ),
              ),
              ValueListenableBuilder<_Playback>(
                valueListenable: _position,
                builder: (context, p, _) => p.buffering
                    ? Center(
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: widget.accent),
                      )
                    : const SizedBox.shrink(),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedOpacity(
                  opacity: _controlsVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: _Controls(
                      position: _position,
                      accent: widget.accent,
                      fullscreen: widget.fullscreen,
                      onFullscreen: widget.onToggleFullscreen,
                      onToggle: _togglePlay,
                      onSeek: (d) {
                        seekTo(d.inSeconds);
                        _showControls();
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Playback {
  const _Playback({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playing = false,
    this.buffering = false,
  });
  final Duration position;
  final Duration duration;
  final bool playing;
  final bool buffering;
}

class _Controls extends StatefulWidget {
  const _Controls({
    required this.position,
    required this.accent,
    required this.onToggle,
    required this.onSeek,
    this.fullscreen = false,
    this.onFullscreen,
  });

  final ValueNotifier<_Playback> position;
  final Color accent;
  final bool fullscreen;
  final VoidCallback? onFullscreen;
  final VoidCallback onToggle;
  final ValueChanged<Duration> onSeek;

  @override
  State<_Controls> createState() => _ControlsState();
}

class _ControlsState extends State<_Controls> {
  double? _dragging;

  static String _fmt(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0'), ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 24, 16, 6),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black87],
        ),
      ),
      child: ValueListenableBuilder<_Playback>(
        valueListenable: widget.position,
        builder: (context, p, _) {
          final total = p.duration.inMilliseconds.toDouble();
          final value = _dragging ?? (total > 0 ? p.position.inMilliseconds / total : 0.0);
          return Row(
            children: [
              IconButton(
                onPressed: widget.onToggle,
                icon: Icon(
                  p.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                ),
              ),
              Text(
                _fmt(_dragging != null ? p.duration * _dragging! : p.position),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: SliderComponentShape.noOverlay,
                    activeTrackColor: widget.accent,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: widget.accent,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Slider(
                      value: value.clamp(0.0, 1.0),
                      onChanged: total > 0 ? (v) => setState(() => _dragging = v) : null,
                      onChangeEnd: (v) {
                        setState(() => _dragging = null);
                        widget.onSeek(p.duration * v);
                      },
                    ),
                  ),
                ),
              ),
              Text(
                _fmt(p.duration),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              if (widget.onFullscreen != null)
                IconButton(
                  tooltip: widget.fullscreen ? 'Exit full screen' : 'Full screen',
                  onPressed: widget.onFullscreen,
                  icon: Icon(
                    widget.fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                    color: Colors.white,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
