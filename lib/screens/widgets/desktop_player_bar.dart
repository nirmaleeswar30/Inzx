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
import 'artist_screen.dart';
import 'desktop_shell.dart';
import 'lyrics_view.dart';
import 'now_playing_screen.dart';
import 'track_artwork_view.dart';

const double _kPlayerBarHeight = 84;
const int _kUpNextTab = 0;
const int _kLyricsTab = 1;

/// Hides the volume bar and panel buttons when the window gets narrow.
const double _kPlayerBarCompactWidth = 980;

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

    // The text is loosely sized, so the + sits right after whichever of the
    // title and artist is wider.
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

class _TransportControls extends ConsumerWidget {
  const _TransportControls({required this.state, required this.track});

  final player_service.PlaybackState state;
  final Track track;

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
              iconSize: 20,
              tooltip: 'Shuffle',
              onPressed: player.toggleShuffle,
              icon: Icon(Icons.shuffle_rounded, color: toggled(shuffle)),
            ),
            IconButton(
              iconSize: 26,
              onPressed: player.skipToPrevious,
              icon: Icon(Icons.skip_previous_rounded, color: base),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 34,
              height: 34,
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
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: isDark ? Colors.black : Colors.white,
                        ),
                      )
                    : Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 22,
                      ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              iconSize: 26,
              onPressed: player.skipToNext,
              icon: Icon(Icons.skip_next_rounded, color: base),
            ),
            IconButton(
              iconSize: 20,
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
        if (!live)
          _ProgressRow(duration: duration ?? track.duration, base: base),
      ],
    );
  }
}

class _ProgressRow extends ConsumerStatefulWidget {
  const _ProgressRow({required this.duration, required this.base});

  final Duration duration;
  final Color base;

  @override
  ConsumerState<_ProgressRow> createState() => _ProgressRowState();
}

class _ProgressRowState extends ConsumerState<_ProgressRow> {
  double? _dragMs;

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
      fontSize: 12,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(
            _clock(Duration(milliseconds: valueMs.toInt())),
            textAlign: TextAlign.right,
            style: timeStyle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ThinSlider(
            value: valueMs,
            max: maxMs > 0 ? maxMs : 1.0,
            base: widget.base,
            onChanged: (value) => setState(() => _dragMs = value),
            onChangeEnd: (value) {
              ref
                  .read(audioPlayerServiceProvider)
                  .seek(Duration(milliseconds: value.toInt()));
              setState(() => _dragMs = null);
            },
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 44,
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
  });

  final double value;
  final double max;
  final Color base;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  ConsumerState<_ThinSlider> createState() => _ThinSliderState();
}

class _ThinSliderState extends ConsumerState<_ThinSlider> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = ref.watch(effectiveAccentColorProvider);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: SizedBox(
        height: 16,
        child: SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            padding: EdgeInsets.zero,
            activeTrackColor: _hovered ? accent : widget.base,
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
      ),
    );
  }
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

        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // Narrow windows only have room for three buttons; lyrics are
            // still a tab away in the queue panel.
            if (!compact)
              IconButton(
                iconSize: 20,
                tooltip: 'Lyrics',
                onPressed: () => _toggleNowPlaying(context, tab: _kLyricsTab),
                icon: Icon(Icons.mic_none_rounded, color: panel(_kLyricsTab)),
              ),
            IconButton(
              iconSize: 20,
              tooltip: 'Queue',
              onPressed: () => _toggleNowPlaying(context, tab: _kUpNextTab),
              icon: Icon(Icons.queue_music_rounded, color: panel(_kUpNextTab)),
            ),
            if (!compact) ...[
              _VolumeControl(base: base),
              const SizedBox(width: 12),
              IconButton(
                iconSize: 20,
                tooltip: 'Mini player',
                onPressed: enterDesktopMiniMode,
                icon: Icon(
                  Icons.picture_in_picture_alt_rounded,
                  color: base.withValues(alpha: 0.75),
                ),
              ),
            ],
            const _FullscreenButton(),
            IconButton(
              iconSize: 20,
              tooltip: 'Close player',
              onPressed: () {
                if (desktopNowPlayingOpen.value) {
                  NowPlayingScreen.closeDesktop();
                }
                ref.read(audioPlayerServiceProvider).clearQueue();
                // Nothing is playing now, so drop the closed song's colours.
                ref.read(playerAlbumColorsProvider.notifier).reset();
              },
              icon: Icon(
                Icons.close_rounded,
                color: base.withValues(alpha: 0.75),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _VolumeControl extends ConsumerStatefulWidget {
  const _VolumeControl({required this.base});

  final Color base;

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

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          iconSize: 20,
          tooltip: volume == 0 ? 'Unmute' : 'Mute',
          onPressed: () {
            if (volume > 0) _beforeMute = volume;
            setState(() {
              player.setMasterVolume(volume > 0 ? 0 : _beforeMute);
            });
          },
          icon: Icon(icon, color: widget.base.withValues(alpha: 0.75)),
        ),
        SizedBox(
          width: 100,
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
  }
}

class _FullscreenButton extends StatelessWidget {
  const _FullscreenButton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      iconSize: 22,
      tooltip: 'Full screen',
      onPressed: () => setDesktopFullScreen(true),
      icon: Icon(
        Icons.fullscreen_rounded,
        color: (isDark ? Colors.white : Colors.black87).withValues(alpha: 0.75),
      ),
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
