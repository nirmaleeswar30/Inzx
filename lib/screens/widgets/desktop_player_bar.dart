import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../main.dart' show rootNavigatorKey;
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../services/audio_player_service.dart' as player_service;
import '../../services/desktop/desktop_bootstrap.dart'
    show kDesktopMinWindowSize;
import '../../services/lyrics/lyrics_models.dart';
import '../../services/lyrics/lyrics_service.dart';
import '../../services/desktop/desktop_audio_dsp.dart';
import '../inzx_connect_screen.dart';
import 'artist_screen.dart';
import 'automix_mix_pulse.dart';
import 'desktop_shell.dart';
import 'lyrics_view.dart';
import 'lossless_badge.dart';
import 'now_playing_screen.dart';
import 'track_artwork_view.dart';

const double _kPlayerBarHeight = 84;
const int _kUpNextTab = 0;
const int _kLyricsTab = 1;

/// Hides the volume and secondary controls when the window gets narrow.
const double _kPlayerBarCompactWidth = 980;
const double _kRightControlWidth = 36;

String _clock(Duration d) {
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (d.inHours > 0) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours}:$minutes:$seconds';
  }
  return '${d.inMinutes}:$seconds';
}

Rect? _boundsBeforeMini;
bool _wasMaximizedBeforeMini = false;

/// Shrinks the window into a small always-on-top player.
Future<void> enterDesktopMiniMode() async {
  if (desktopMiniMode.value) return;
  if (await windowManager.isFullScreen()) {
    await windowManager.setFullScreen(false);
  }
  _wasMaximizedBeforeMini = await windowManager.isMaximized();
  if (_wasMaximizedBeforeMini) await windowManager.unmaximize();
  _boundsBeforeMini = await windowManager.getBounds();
  // Switch first: the full layout mustn't be on screen while the window shrinks.
  desktopMiniMode.value = true;
  await windowManager.setMinimumSize(const Size(260, 260));
  await windowManager.setSize(const Size(320, 340));
  await windowManager.setAlwaysOnTop(true);
}

/// Puts the window back the way it was before the mini player.
Future<void> exitDesktopMiniMode() async {
  if (!desktopMiniMode.value) return;
  await windowManager.setAlwaysOnTop(false);
  await windowManager.setMinimumSize(kDesktopMinWindowSize);
  final bounds = _boundsBeforeMini;
  if (bounds != null) await windowManager.setBounds(bounds);
  if (_wasMaximizedBeforeMini) await windowManager.maximize();
  desktopMiniMode.value = false;
}

/// Opens the now playing view on [tab], or closes it if it's already there.
void _toggleNowPlaying(BuildContext context, {int? tab}) {
  if (desktopNowPlayingOpen.value &&
      (tab == null || desktopNowPlayingTab.value == tab)) {
    NowPlayingScreen.closeDesktop();
    return;
  }
  if (tab != null) desktopNowPlayingTab.value = tab;
  NowPlayingScreen.showDesktop();
}

/// The full-width player along the bottom of the window.
class DesktopPlayerBar extends ConsumerWidget {
  const DesktopPlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackStateProvider).valueOrNull;
    final track = state?.currentTrack;
    if (state == null || track == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final albumColors = ref.watch(albumColorsProvider);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      height: _kPlayerBarHeight,
      color:
          (isDark ? albumColors : albumColors.toLightMode()).backgroundPrimary,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < _kPlayerBarCompactWidth;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(flex: 3, child: _TrackDetails(track: track)),
                const SizedBox(width: 12),
                Expanded(
                  flex: 4,
                  child: _TransportControls(state: state, track: track),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: compact ? 2 : 3,
                  child: _RightControls(compact: compact),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TrackDetails extends ConsumerWidget {
  const _TrackDetails({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.white : Colors.black87;
    final accent = ref.watch(effectiveAccentColorProvider);
    final liked = ref.watch(isTrackLikedProvider(track.id));

    final artistId = track.artistId;

    // The + sits right after the track details.
    return Row(
      children: [
        _ArtButton(track: track),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LinkText(
                text: track.title,
                style: TextStyle(
                  color: base,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                onTap: () => _toggleNowPlaying(context),
              ),
              const SizedBox(height: 2),
              _LinkText(
                text: track.artist,
                style: TextStyle(
                  color: base.withValues(alpha: 0.65),
                  fontSize: 13,
                ),
                onTap: artistId.isEmpty
                    ? null
                    : () {
                        final navigator = rootNavigatorKey.currentContext;
                        if (navigator == null) return;
                        ArtistScreen.open(
                          navigator,
                          artistId: artistId,
                          name: track.artist,
                        );
                      },
              ),
              LosslessBadge(
                color: base.withValues(alpha: 0.75),
                horizontalPadding: 0,
                sheetContext: rootNavigatorKey.currentContext,
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: liked ? 'Remove from Liked Songs' : 'Add to Liked Songs',
          onPressed: () => toggleTrackLike(ref: ref, track: track),
          icon: Icon(
            liked
                ? Icons.check_circle_rounded
                : Icons.add_circle_outline_rounded,
            size: 22,
            color: liked ? accent : base.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

/// The album art, with its own hover: opens and closes the now playing view.
class _ArtButton extends StatefulWidget {
  const _ArtButton({required this.track});

  final Track track;

  @override
  State<_ArtButton> createState() => _ArtButtonState();
}

class _ArtButtonState extends State<_ArtButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => _toggleNowPlaying(context),
        child: Stack(
          alignment: Alignment.center,
          children: [
            TrackArtworkView(
              track: widget.track,
              width: 56,
              height: 56,
              borderRadius: BorderRadius.circular(5),
            ),
            AnimatedOpacity(
              opacity: _hovered ? 1 : 0,
              duration: const Duration(milliseconds: 120),
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: ListenableBuilder(
                  listenable: desktopNowPlayingOpen,
                  builder: (context, _) => Icon(
                    desktopNowPlayingOpen.value
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of text that underlines under the pointer, on its own.
class _LinkText extends StatefulWidget {
  const _LinkText({required this.text, required this.style, this.onTap});

  final String text;
  final TextStyle style;
  final VoidCallback? onTap;

  @override
  State<_LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<_LinkText> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final clickable = widget.onTap != null;
    return MouseRegion(
      cursor: clickable ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          widget.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: widget.style.copyWith(
            decoration: clickable && _hovered
                ? TextDecoration.underline
                : TextDecoration.none,
            decorationColor: widget.style.color,
          ),
        ),
      ),
    );
  }
}

/// The bar's transport buttons and seek bar, larger by [scale]: the full
/// screen player uses them too, since the bar is hidden there.
class DesktopTransportControls extends StatelessWidget {
  const DesktopTransportControls({
    super.key,
    required this.state,
    required this.track,
    this.scale = 1,
    this.showProgress = true,
  });

  final player_service.PlaybackState state;
  final Track track;
  final double scale;

  /// Off when the caller draws its own seek bar under the buttons.
  final bool showProgress;

  @override
  Widget build(BuildContext context) => _TransportControls(
    state: state,
    track: track,
    scale: scale,
    showProgress: showProgress,
  );
}

/// The bar's mute button and volume slider, for the full screen player.
class DesktopVolumeControl extends StatelessWidget {
  const DesktopVolumeControl({
    super.key,
    required this.base,
    this.sliderWidth = 120,
  });

  final Color base;
  final double sliderWidth;

  @override
  Widget build(BuildContext context) =>
      _VolumeControl(base: base, sliderWidth: sliderWidth);
}

class _TransportControls extends ConsumerWidget {
  const _TransportControls({
    required this.state,
    required this.track,
    this.scale = 1,
    this.showProgress = true,
  });

  final player_service.PlaybackState state;
  final Track track;
  final double scale;
  final bool showProgress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.white : Colors.black87;
    final accent = ref.watch(effectiveAccentColorProvider);
    final player = ref.read(audioPlayerServiceProvider);
    final bool shuffle = state.shuffleEnabled;
    final LoopMode loop = state.loopMode;
    final bool playing = state.isPlaying;
    final bool loading = state.isLoading;
    final bool live = state.isLive;
    final Duration? duration = state.duration;

    Color toggled(bool on) => on ? accent : base.withValues(alpha: 0.7);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              iconSize: 20 * scale,
              tooltip: 'Shuffle',
              onPressed: player.toggleShuffle,
              icon: Icon(Icons.shuffle_rounded, color: toggled(shuffle)),
            ),
            IconButton(
              iconSize: 26 * scale,
              onPressed: player.skipToPrevious,
              icon: Icon(Icons.skip_previous_rounded, color: base),
            ),
            SizedBox(width: 4 * scale),
            SizedBox(
              width: 34 * scale,
              height: 34 * scale,
              child: IconButton.filled(
                padding: EdgeInsets.zero,
                style: IconButton.styleFrom(
                  backgroundColor: base,
                  foregroundColor: isDark ? Colors.black : Colors.white,
                  shape: const CircleBorder(),
                ),
                onPressed: player.togglePlayPause,
                icon: loading
                    ? SizedBox(
                        width: 16 * scale,
                        height: 16 * scale,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: isDark ? Colors.black : Colors.white,
                        ),
                      )
                    : Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 22 * scale,
                      ),
              ),
            ),
            SizedBox(width: 4 * scale),
            IconButton(
              iconSize: 26 * scale,
              onPressed: player.skipToNext,
              icon: Icon(Icons.skip_next_rounded, color: base),
            ),
            IconButton(
              iconSize: 20 * scale,
              tooltip: 'Repeat',
              onPressed: player.cycleLoopMode,
              icon: Icon(
                loop == LoopMode.one
                    ? Icons.repeat_one_rounded
                    : Icons.repeat_rounded,
                color: toggled(loop != LoopMode.off),
              ),
            ),
          ],
        ),
        if (!live && showProgress)
          _ProgressRow(
            duration: duration ?? track.duration,
            base: base,
            scale: scale,
          ),
      ],
    );
  }
}

class _ProgressRow extends ConsumerStatefulWidget {
  const _ProgressRow({
    required this.duration,
    required this.base,
    this.scale = 1,
  });

  final Duration duration;
  final Color base;
  final double scale;

  @override
  ConsumerState<_ProgressRow> createState() => _ProgressRowState();
}

class _ProgressRowState extends ConsumerState<_ProgressRow>
    with TickerProviderStateMixin {
  double? _dragMs;

  // Automix, as on the phone's seek bar: the planned window as a feathered
  // band, and during a blend the fill gliding out to the end and pulsing on
  // the beat. A drag shows the plain position.
  late final AutomixMixPulse _mixPulse = AutomixMixPulse(this);

  @override
  void dispose() {
    _mixPulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final position =
        ref.watch(positionStreamProvider).valueOrNull ?? Duration.zero;
    final maxMs = widget.duration.inMilliseconds.toDouble();
    final valueMs = (_dragMs ?? position.inMilliseconds.toDouble()).clamp(
      0.0,
      maxMs > 0 ? maxMs : 1.0,
    );
    final timeStyle = TextStyle(
      color: widget.base.withValues(alpha: 0.65),
      fontSize: 12 * widget.scale,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Row(
      children: [
        SizedBox(
          width: 44 * widget.scale,
          child: Text(
            _clock(Duration(milliseconds: valueMs.toInt())),
            textAlign: TextAlign.right,
            style: timeStyle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AnimatedBuilder(
            animation: _mixPulse,
            builder: (context, _) {
              final max = maxMs > 0 ? maxMs : 1.0;
              final dragging = _dragMs != null;
              final cover = dragging ? 0.0 : AutomixMixPulse.eased(_mixPulse.cover);
              final start = _mixPulse.windowStart;
              final end = _mixPulse.windowEnd;
              return _ThinSlider(
                value: valueMs + (max - valueMs) * cover,
                max: max,
                base: widget.base,
                fillOpacity: dragging ? 1.0 : _mixPulse.alpha(1.0),
                window: start != null && end != null && _mixPulse.windowAlpha > 0 && !dragging
                    ? (start: start, end: end, alpha: _mixPulse.windowAlpha)
                    : null,
                onChanged: (value) => setState(() => _dragMs = value),
                onChangeEnd: (value) {
                  ref
                      .read(audioPlayerServiceProvider)
                      .seek(Duration(milliseconds: value.toInt()));
                  setState(() => _dragMs = null);
                },
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 44 * widget.scale,
          child: Text(_clock(widget.duration), style: timeStyle),
        ),
      ],
    );
  }
}

/// A slim track that shows its thumb and accent colour on hover.
class _ThinSlider extends ConsumerStatefulWidget {
  const _ThinSlider({
    required this.value,
    required this.max,
    required this.base,
    required this.onChanged,
    this.onChangeEnd,
    this.fillOpacity = 1.0,
    this.window,
  });

  final double value;
  final double max;
  final Color base;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final double fillOpacity;
  /// Automix's planned window, as fractions of the track.
  final ({double start, double end, double alpha})? window;

  @override
  ConsumerState<_ThinSlider> createState() => _ThinSliderState();
}

class _ThinSliderState extends ConsumerState<_ThinSlider> {
  static const double _trackHeight = 4;

  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = ref.watch(effectiveAccentColorProvider);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: SizedBox(
        height: 16,
        child: Stack(
          children: [
            if (widget.window case final window?)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _WindowBandPainter(
                      start: window.start,
                      end: window.end,
                      color: accent.withValues(alpha: 0.55 * window.alpha),
                      trackHeight: _trackHeight,
                    ),
                  ),
                ),
              ),
            SliderTheme(
              data: SliderThemeData(
                trackHeight: _trackHeight,
                padding: EdgeInsets.zero,
                activeTrackColor: (_hovered ? accent : widget.base).withValues(
                  alpha:
                      (_hovered ? accent : widget.base).a * widget.fillOpacity,
                ),
                inactiveTrackColor: widget.base.withValues(alpha: 0.25),
                thumbColor: widget.base,
                overlayShape: SliderComponentShape.noOverlay,
                thumbShape: RoundSliderThumbShape(
                  enabledThumbRadius: _hovered ? 6 : 0,
                  elevation: 0,
                ),
              ),
              child: Slider(
                value: widget.value.clamp(0.0, widget.max),
                max: widget.max,
                onChanged: widget.onChanged,
                onChangeEnd: widget.onChangeEnd,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Automix's planned window on the track: a band feathered at both ends.
class _WindowBandPainter extends CustomPainter {
  _WindowBandPainter({
    required this.start,
    required this.end,
    required this.color,
    required this.trackHeight,
  });

  final double start;
  final double end;
  final Color color;
  final double trackHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final left = size.width * start;
    final right = size.width * end;
    if (right <= left) return;
    final centerY = size.height / 2;
    final radius = trackHeight / 2;
    final rect = Rect.fromLTRB(left, centerY - radius, right, centerY + radius);
    final feather = ((right - left) * 0.2).clamp(2.0, 12.0) / (right - left);
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          color.withValues(alpha: 0),
          color,
          color,
          color.withValues(alpha: 0),
        ],
        stops: [0, feather, 1 - feather, 1],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_WindowBandPainter old) =>
      old.start != start ||
      old.end != end ||
      old.color != color ||
      old.trackHeight != trackHeight;
}

class _RightControls extends ConsumerWidget {
  const _RightControls({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.white : Colors.black87;
    final accent = ref.watch(effectiveAccentColorProvider);

    return ListenableBuilder(
      listenable: Listenable.merge([
        desktopNowPlayingOpen,
        desktopNowPlayingTab,
      ]),
      builder: (context, _) {
        final open = desktopNowPlayingOpen.value;
        final tab = desktopNowPlayingTab.value;
        Color panel(int index) =>
            open && tab == index ? accent : base.withValues(alpha: 0.75);

        final color = base.withValues(alpha: 0.75);
        return LayoutBuilder(
          builder: (context, constraints) {
            // Reserve room for all seven buttons before sizing the slider.
            final sliderWidth = (constraints.maxWidth - 7 * _kRightControlWidth)
                .clamp(0.0, 100.0);
            return Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!compact)
                  _RightControlButton(
                    tooltip: 'Lyrics',
                    onPressed: () =>
                        _toggleNowPlaying(context, tab: _kLyricsTab),
                    icon: Icons.mic_none_rounded,
                    color: panel(_kLyricsTab),
                  ),
                _RightControlButton(
                  tooltip: 'Queue',
                  onPressed: () => _toggleNowPlaying(context, tab: _kUpNextTab),
                  icon: Icons.queue_music_rounded,
                  color: panel(_kUpNextTab),
                ),
                _RightControlButton(
                  tooltip: InzxConnectScreen.title,
                  onPressed: () =>
                      InzxConnectScreen.open(rootNavigatorKey.currentState),
                  icon: InzxConnectScreen.icon,
                  color: color,
                ),
                if (!compact) ...[
                  _VolumeControl(
                    base: base,
                    sliderWidth: sliderWidth >= 44 ? sliderWidth : 0,
                  ),
                  _RightControlButton(
                    tooltip: 'Mini player',
                    onPressed: enterDesktopMiniMode,
                    icon: Icons.picture_in_picture_alt_rounded,
                    color: color,
                  ),
                ],
                _RightControlButton(
                  tooltip: 'Full screen',
                  onPressed: () => setDesktopFullScreen(true),
                  icon: Icons.fullscreen_rounded,
                  color: color,
                  iconSize: 22,
                ),
                _RightControlButton(
                  tooltip: 'Close player',
                  onPressed: () {
                    if (desktopNowPlayingOpen.value) {
                      NowPlayingScreen.closeDesktop();
                    }
                    ref.read(audioPlayerServiceProvider).clearQueue();
                    // Nothing is playing now, so drop the closed song's colours.
                    ref.read(playerAlbumColorsProvider.notifier).reset();
                  },
                  icon: Icons.close_rounded,
                  color: color,
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _RightControlButton extends StatelessWidget {
  const _RightControlButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    required this.color,
    this.iconSize = 20,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final IconData icon;
  final Color color;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kRightControlWidth,
      height: 40,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: iconSize,
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: color),
      ),
    );
  }
}

class _VolumeControl extends ConsumerStatefulWidget {
  const _VolumeControl({required this.base, required this.sliderWidth});

  final Color base;
  final double sliderWidth;

  @override
  ConsumerState<_VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends ConsumerState<_VolumeControl> {
  double _beforeMute = 1;

  @override
  Widget build(BuildContext context) {
    final player = ref.read(audioPlayerServiceProvider);
    final volume = player.masterVolume;
    final IconData icon;
    if (volume == 0) {
      icon = Icons.volume_off_rounded;
    } else if (volume < 0.5) {
      icon = Icons.volume_down_rounded;
    } else {
      icon = Icons.volume_up_rounded;
    }

    final control = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RightControlButton(
          tooltip: volume == 0 ? 'Unmute' : 'Mute',
          onPressed: () {
            if (volume > 0) _beforeMute = volume;
            setState(() {
              player.setMasterVolume(volume > 0 ? 0 : _beforeMute);
            });
          },
          icon: icon,
          color: widget.base.withValues(alpha: 0.75),
        ),
        if (widget.sliderWidth > 0)
          SizedBox(
            width: widget.sliderWidth,
            child: _ThinSlider(
              value: volume,
              max: 1,
              base: widget.base,
              onChanged: (value) => setState(() {
                player.setMasterVolume(value, persist: false);
              }),
              onChangeEnd: player.setMasterVolume,
            ),
          ),
      ],
    );
    // Bit-perfect output plays at full scale; the level is the device's.
    return ListenableBuilder(
      listenable: DesktopAudioDsp.instance,
      builder: (context, child) => DesktopAudioDsp.instance.exclusive
          ? Tooltip(
              message:
                  'Bit-perfect output is on: set the volume on your device',
              child: IgnorePointer(child: Opacity(opacity: 0.35, child: child)),
            )
          : child!,
      child: control,
    );
  }
}

/// Whether the small player shows lyrics instead of the artwork. Kept for the
/// session, so it reopens the way it was left.
final desktopMiniLyrics = ValueNotifier<bool>(false);

/// What the window shows while it's the small always-on-top player.
class DesktopPopoutPlayer extends ConsumerStatefulWidget {
  const DesktopPopoutPlayer({super.key});

  @override
  ConsumerState<DesktopPopoutPlayer> createState() =>
      _DesktopPopoutPlayerState();
}

class _DesktopPopoutPlayerState extends ConsumerState<DesktopPopoutPlayer> {
  bool _hovered = false;
  String? _lyricsRequestedFor;

  @override
  void initState() {
    super.initState();
    desktopMiniLyrics.addListener(_rebuild);
  }

  @override
  void dispose() {
    desktopMiniLyrics.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  /// The full window's now playing view normally loads lyrics, but it isn't
  /// running while the window is this small, so fetch them here.
  void _ensureLyrics(Track track) {
    if (_lyricsRequestedFor == track.id || ref.read(isLiveProvider)) return;
    _lyricsRequestedFor = track.id;
    if (ref.read(lyricsProvider).videoId == track.id) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(lyricsProvider.notifier)
          .fetchLyrics(
            LyricsSearchInfo(
              videoId: track.id,
              title: track.title,
              artist: track.artist,
              album: track.album,
              durationSeconds: track.duration.inSeconds,
              localFilePath: track.localFilePath,
            ),
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playbackStateProvider).valueOrNull;
    final track = state?.currentTrack;
    final player = ref.read(audioPlayerServiceProvider);
    if (state == null || track == null) {
      return const ColoredBox(color: Colors.black);
    }
    final showLyrics = desktopMiniLyrics.value;
    if (showLyrics) _ensureLyrics(track);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final albumColors = ref.watch(playerAlbumColorsProvider);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          fit: StackFit.expand,
          children: [
            if (showLyrics) ...[
              AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                color: (isDark ? albumColors : albumColors.toLightMode())
                    .backgroundPrimary,
              ),
              const Padding(
                padding: EdgeInsets.only(top: 40, bottom: 8),
                child: Material(
                  type: MaterialType.transparency,
                  child: _MiniLyrics(),
                ),
              ),
              // Lyrics scroll, so only the strip along the top drags.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 40,
                child: DragToMoveArea(child: const SizedBox.expand()),
              ),
            ] else ...[
              const ColoredBox(color: Colors.black),
              _MiniArtwork(
                track: track,
                width: constraints.maxWidth,
                height: constraints.maxHeight,
              ),
              DragToMoveArea(child: const SizedBox.expand()),
            ],
            AnimatedOpacity(
              opacity: _hovered ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: Stack(
                children: [
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          // Lyrics stay readable under the controls.
                          colors: showLyrics
                              ? const [
                                  Color(0x00000000),
                                  Color(0x00000000),
                                  Color(0xCC000000),
                                ]
                              : const [Color(0x66000000), Color(0xCC000000)],
                          stops: showLyrics ? const [0, 0.5, 1] : null,
                        ),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  Positioned(
                    top: 2,
                    left: 2,
                    child: IconButton(
                      tooltip: showLyrics ? 'Show artwork' : 'Show lyrics',
                      onPressed: () =>
                          desktopMiniLyrics.value = !desktopMiniLyrics.value,
                      icon: Icon(
                        showLyrics
                            ? Icons.album_rounded
                            : Icons.lyrics_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: IconButton(
                      tooltip: 'Back to full window',
                      onPressed: exitDesktopMiniMode,
                      icon: const Icon(
                        Icons.open_in_full_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 10,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              iconSize: 30,
                              onPressed: player.skipToPrevious,
                              icon: const Icon(
                                Icons.skip_previous_rounded,
                                color: Colors.white,
                              ),
                            ),
                            IconButton(
                              iconSize: 42,
                              onPressed: player.togglePlayPause,
                              icon: Icon(
                                state.isPlaying
                                    ? Icons.pause_circle_filled_rounded
                                    : Icons.play_circle_fill_rounded,
                                color: Colors.white,
                              ),
                            ),
                            IconButton(
                              iconSize: 30,
                              onPressed: player.skipToNext,
                              icon: const Icon(
                                Icons.skip_next_rounded,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lyrics for the small player. Watches the position on its own so the rest
/// of the player doesn't rebuild on every tick.
class _MiniLyrics extends ConsumerWidget {
  const _MiniLyrics();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(isLiveProvider)) {
      return const Center(
        child: Text(
          'Lyrics aren’t available for live streams',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
      );
    }
    final position =
        ref.watch(positionStreamProvider).valueOrNull ?? Duration.zero;
    // The lyrics are sized for the full window; scale them to this one.
    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(0.75)),
      child: RepaintBoundary(child: LyricsView(currentPosition: position)),
    );
  }
}

/// The cover at full size for the small player. Song covers come as small
/// thumbnails and video thumbnails have black bars, so both look rough here:
/// use the 1200px cover, or a video's full-HD frame when it has one.
class _MiniArtwork extends StatelessWidget {
  const _MiniArtwork({
    required this.track,
    required this.width,
    required this.height,
  });

  final Track track;
  final double width;
  final double height;

  static final _videoThumb = RegExp(
    r'(i\.ytimg\.com/vi(?:_webp)?/[^/]+/)(?:default|mqdefault|hqdefault|sddefault)\.(jpg|webp)',
  );

  @override
  Widget build(BuildContext context) {
    final art = track.systemArtworkUrl ?? track.bestThumbnail;
    final maxRes = art != null && _videoThumb.hasMatch(art)
        ? art.replaceFirstMapped(
            _videoThumb,
            (m) => '${m[1]}maxresdefault.${m[2]}',
          )
        : null;

    return TrackArtworkView(
      track: track.copyWith(thumbnailUrl: maxRes ?? art),
      width: width,
      height: height,
      // Not every video has a full-HD frame; keep the original then.
      errorWidget: maxRes != null
          ? CachedNetworkImage(
              imageUrl: art!,
              width: width,
              height: height,
              fit: BoxFit.cover,
            )
          : null,
    );
  }
}
