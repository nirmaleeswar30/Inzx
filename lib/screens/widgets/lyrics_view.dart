import '../../core/utils/open_once.dart';
import '../../core/utils/platform_utils.dart';
import 'dart:async';
import 'dart:ui' show ImageFilter, TileMode;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import '../../core/l10n/app_localizations_x.dart';
import '../../providers/music_providers.dart';
import '../../providers/providers.dart';
import '../../services/dynamic_font_service.dart';
import '../../services/lyrics/lyrics_service.dart';
import '../../services/lyrics/lyrics_models.dart';
import '../../services/lyrics/instrumental_gaps.dart';
import 'swept_lyric_line.dart';
import 'lyric_clock.dart';
import 'lyrics_menu_sheet.dart';

/// Preview duration before auto-scroll resumes after manual scrolling
const _lyricsPreviewTimeMs = 8000;
const _lyricsAnchorRatio = 0.35; // 35% from the top of the viewport
const _lyricsScrollCache = 1500.0;

// ── Line-to-line handover (after BitChord) ───────────────────────────────
// One curve for everything that moves when a line hands over — the scroll,
// the dim, the scale — so it reads as a single movement: away quickly, in
// slowly and softly.
const Cubic _lyricEase = Cubic(0.41, 0.0, 0.12, 0.99);
const Duration _lyricSettle = Duration(milliseconds: 400);
// The scroll runs over the silence before the next line, bounded so it is
// neither a snap nor a drift.
const int _scrollLeadMinMs = 350;
const int _scrollLeadMaxMs = 500;
// Rows below the line being scrolled to set off slightly later than the one
// above them (up to 3 rows), so the spacing opens and closes as the list moves
// instead of the whole block sliding rigidly.
const int _staggerSteps = 3;
const double _staggerFraction = 0.06;
// Every line is set in the same type and shown at the same size: the playing
// line is picked out by colour and opacity only, never by zooming it (a zoom
// pushed the line wider than its row and read as the words jumping).
const double _inactiveLineScale = 1.0;
// Inactive lines are grey, starting from the app's 50% secondary text and
// fading further with distance; only the playing line is full strength.
const List<double> _lineFalloffAlpha = [1.0, 0.5, 0.44, 0.38, 0.32, 0.28];
const double _syncedFontSize = 26.0;

/// BitChord's blur either side of the line being sung, by distance from it.
const List<double> _lineFalloffBlur = [0, 1, 1, 1.7, 2.4];

double _falloffAlpha(int dist) =>
    _lineFalloffAlpha[dist.clamp(0, _lineFalloffAlpha.length - 1)];

/// Lyrics view widget for Now Playing screen with synced animations
class LyricsView extends ConsumerStatefulWidget {
  final Duration currentPosition;
  final bool isActive;

  /// Sizes the lyric lines up, for the desktop full screen player.
  final double fontScale;

  /// Whether the options menu button shows; the full screen player fades it
  /// out while the mouse is idle.
  final bool menuVisible;

  /// Use viewport-only blur layers for the windowed desktop panel.
  final bool windowedDesktop;

  const LyricsView({
    super.key,
    required this.currentPosition,
    this.isActive = true,
    this.fontScale = 1.0,
    this.menuVisible = true,
    this.windowedDesktop = false,
  });

  @override
  ConsumerState<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<LyricsView>
    with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  int _currentLineIndex = -1;

  /// The line the panel is moving to — runs a few hundred ms ahead of
  /// [_currentLineIndex] so the scroll lands as the line starts.
  int _focusLineIndex = -1;

  // The current handover, read by each row to work out how far behind the
  // list it should trail.
  late final AnimationController _handover;
  double _runDelta = 0;
  int _runDurationMs = _scrollLeadMinMs;
  int _runFocus = -1;
  List<GlobalKey> _lineKeys = [];

  // High-frequency frame ticker for 60/120fps smooth karaoke sweep without rebuilding the full widget tree
  late final Ticker _ticker;
  final ValueNotifier<int> _smoothPositionNotifier = ValueNotifier<int>(0);

  /// The lyric playhead, steered by the player's dated readings (BitChord's
  /// LyricClock); a new one per track.
  LyricClock? _clock;
  String? _clockTrackId;

  // Auto-scroll management
  bool _isAutoScrollEnabled = true;
  Timer? _autoScrollResumeTimer;
  bool _isUserScrolling = false;

  @override
  void initState() {
    super.initState();
    _smoothPositionNotifier.value = _heldPositionMs;

    _handover = AnimationController(vsync: this);

    DynamicFontService.instance.addListener(_onFontLoaded);

    _ticker = createTicker((_) {
      final current = _stepClock();
      if (_smoothPositionNotifier.value != current) {
        _smoothPositionNotifier.value = current;
        _checkLineIndexChange(current);
      }
    });
    // Only run the per-frame clock while the lyrics are on screen and the
    // song is playing; otherwise it would tick (and wake the CPU) for nothing.
    ref.listenManual(isPlayingProvider, (_, _) => _syncTicker());
    _syncTicker();

    if (!widget.windowedDesktop) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.isActive) {
          _checkLineIndexChange(_smoothPositionNotifier.value);
          if (_isAutoScrollEnabled) {
            _scrollToCurrentLine(immediate: true);
          }
        }
      });
    }
  }

  /// The position the widget was handed, with the lyrics offset: where the
  /// lyrics sit while the frame clock isn't running.
  int get _heldPositionMs =>
      widget.currentPosition.inMilliseconds + ref.read(lyricsSyncOffsetProvider);

  /// One frame of the lyric clock. Stalled (loading, buffering) it holds on
  /// the player's reading rather than running on by itself, so lines never
  /// get ahead of a song that hasn't started or has paused to buffer; and
  /// it learns the real playback rate, so Automix tempo matching stays in
  /// step.
  int _stepClock() {
    final playhead = ref.read(playbackTransportProvider).playhead;
    final offset = ref.read(lyricsSyncOffsetProvider);
    final trackId = ref.read(currentTrackIdProvider);
    if (_clock == null || trackId != _clockTrackId) {
      _clockTrackId = trackId;
      _clock = LyricClock(playhead.positionMs + offset);
    }
    return stepLyricClock(_clock!, playhead, offset);
  }

  void _syncTicker() {
    final shouldRun = widget.isActive && ref.read(isPlayingProvider);
    if (shouldRun && !_ticker.isActive) {
      // A fresh run from the latest reading: a pause or a spell off screen
      // isn't mistaken for one very long frame.
      _clock?.restart();
      _ticker.start();
    } else if (!shouldRun && _ticker.isActive) {
      _ticker.stop();
      _smoothPositionNotifier.value = _heldPositionMs;
      _checkLineIndexChange(_heldPositionMs);
    }
  }

  void _checkLineIndexChange(int currentPositionMs, {bool scroll = true}) {
    final lyricsState = ref.read(lyricsProvider);
    final lines = lyricsState.currentLyrics?.lines;
    if (lines == null || lines.isEmpty) return;

    int newIdx = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].timeInMs <= currentPositionMs) {
        newIdx = i;
      } else {
        break;
      }
    }

    // The panel starts moving to the next line a run-up ahead of it, so the
    // scroll lands as the line does instead of chasing it.
    var focusIdx = newIdx;
    final nextIdx = newIdx + 1;
    if (nextIdx < lines.length &&
        lines[nextIdx].timeInMs - currentPositionMs <=
            _scrollLeadMs(lines, nextIdx)) {
      focusIdx = nextIdx;
    }

    if (newIdx != _currentLineIndex && newIdx >= 0) {
      setState(() {
        _currentLineIndex = newIdx;
      });
    }

    if (focusIdx != _focusLineIndex && focusIdx >= 0) {
      _focusLineIndex = focusIdx;
      if (scroll && _isAutoScrollEnabled && widget.isActive) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _isAutoScrollEnabled && widget.isActive) {
            _scrollToCurrentLine(immediate: false);
          }
        });
      }
    }
  }

  /// The silence before line [index] (bounded): how far ahead the panel
  /// starts moving to it, and how long the move takes.
  int _scrollLeadMs(List<LyricLine> lines, int index) {
    if (index <= 0 || index >= lines.length) return _scrollLeadMinMs;
    final previous = lines[index - 1];
    final previousEnd = previous.hasKnownEnd
        ? previous.endMs
        : lines[index].timeInMs - _scrollLeadMaxMs;
    return (lines[index].timeInMs - previousEnd)
        .clamp(_scrollLeadMinMs, _scrollLeadMaxMs)
        .toInt();
  }

  /// How far row [index] trails the list during the current handover. Rows
  /// below the focus line set off up to [_staggerSteps] steps later; with one
  /// curve for both, a row with no delay sits exactly still against the list.
  double _staggerOffset(int index) {
    if (_runDelta == 0 || !_handover.isAnimating) return 0;
    final behind =
        (_runDelta >= 0 ? index - _runFocus : _runFocus - index)
            .clamp(0, _staggerSteps);
    if (behind <= 0) return 0;
    final duration = _runDurationMs.toDouble();
    final delay = behind * _staggerFraction * duration;
    final elapsed = _handover.value * duration * (1 + _staggerFraction * _staggerSteps);
    return _runDelta *
        (_lyricEase.transform((elapsed / duration).clamp(0.0, 1.0)) -
            _lyricEase.transform(((elapsed - delay) / duration).clamp(0.0, 1.0)));
  }

  @override
  void didUpdateWidget(covariant LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isActive != widget.isActive) _syncTicker();

    if (!oldWidget.isActive && widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isAutoScrollEnabled && widget.isActive) {
          _scrollToCurrentLine(immediate: true);
        }
      });
    }

    // While the frame clock runs it reads the player itself; otherwise each
    // new position is the truth, which is how a seek made while paused (or
    // with the lyrics off screen) still moves the words.
    if (!_ticker.isActive) {
      final newMs = _heldPositionMs;
      if (_smoothPositionNotifier.value != newMs) {
        _smoothPositionNotifier.value = newMs;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _checkLineIndexChange(newMs);
        });
      }
    }
  }

  void _onFontLoaded() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    DynamicFontService.instance.removeListener(_onFontLoaded);
    _ticker.dispose();
    _handover.dispose();
    _smoothPositionNotifier.dispose();
    _autoScrollResumeTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onUserManualScroll() {
    if (_isAutoScrollEnabled) {
      setState(() {
        _isAutoScrollEnabled = false;
      });
    }
    _autoScrollResumeTimer?.cancel();
    _autoScrollResumeTimer = Timer(
      const Duration(milliseconds: _lyricsPreviewTimeMs),
      () {
        if (mounted && !_isUserScrolling) {
          _resumeAutoScroll();
        }
      },
    );
  }

  void _resumeAutoScroll() {
    _autoScrollResumeTimer?.cancel();
    if (mounted) {
      setState(() {
        _isAutoScrollEnabled = true;
      });
      if (widget.isActive) {
        _scrollToCurrentLine(immediate: false);
      }
    }
  }

  // During a lyrics-source transition the outgoing list can still be attached.
  ScrollPosition get _lyricsScrollPosition => widget.windowedDesktop
      ? _scrollController.positions.last
      : _scrollController.position;

  void _scrollToCurrentLine({bool immediate = false}) {
    if (!widget.isActive) return;
    final target = _focusLineIndex >= 0 ? _focusLineIndex : _currentLineIndex;
    if (!_scrollController.hasClients ||
        target < 0 ||
        target >= _lineKeys.length) {
      return;
    }

    final keyContext = _lineKeys[target].currentContext;
    if (keyContext != null) {
      _ensureLineVisible(keyContext, target, immediate: immediate);
    } else {
      // Far off screen (a seek): get close first, then settle precisely once
      // the row has been laid out.
      final position = _lyricsScrollPosition;
      final approxOffset = (target * 60.0).clamp(
        0.0,
        position.maxScrollExtent,
      );
      position.jumpTo(approxOffset);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            widget.isActive &&
            _scrollController.hasClients &&
            target < _lineKeys.length) {
          final newContext = _lineKeys[target].currentContext;
          if (newContext != null) {
            _ensureLineVisible(newContext, target, immediate: immediate);
          } else if (widget.windowedDesktop) {
            _scrollToUnlaidLine(target, immediate: immediate);
          }
        }
      });
    }
  }

  // A reopened panel starts without row positions. Wrapped lyrics and
  // translations can put the target well past the first offset estimate.
  void _scrollToUnlaidLine(int target, {required bool immediate}) {
    if (!mounted ||
        !widget.isActive ||
        !_isAutoScrollEnabled ||
        target != _focusLineIndex ||
        target >= _lineKeys.length ||
        !_scrollController.hasClients) {
      return;
    }
    final context = _lineKeys[target].currentContext;
    if (context != null) {
      _ensureLineVisible(context, target, immediate: immediate);
      return;
    }

    final firstLaidOut = _lineKeys.indexWhere(
      (key) => key.currentContext != null,
    );
    if (firstLaidOut < 0) return;
    final position = _lyricsScrollPosition;
    // Step by the cache extent so the next layout can't skip over the row.
    final step = target < firstLaidOut ? -_lyricsScrollCache : _lyricsScrollCache;
    final offset = (position.pixels + step)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (offset == position.pixels) return;
    position.jumpTo(offset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToUnlaidLine(target, immediate: immediate);
    });
  }

  void _ensureLineVisible(
    BuildContext keyContext,
    int lineIndex, {
    bool immediate = false,
  }) {
    if (!widget.isActive) return;
    final renderObject = keyContext.findRenderObject();
    if (renderObject == null || !renderObject.attached) return;

    if (!_scrollController.hasClients) return;
    final position = _lyricsScrollPosition;
    if (!position.hasContentDimensions) return;

    // Scroll ONLY the lyrics ScrollController position.
    // Never call Scrollable.ensureVisible(keyContext) because that bubbles up all
    // ancestor Scrollables including the parent horizontal PageView in NowPlayingScreen,
    // halting PageView transitions and forcefully switching tabs.
    final viewport = RenderAbstractViewport.maybeOf(renderObject);
    if (viewport == null) return;
    final targetOffset = viewport
        .getOffsetToReveal(renderObject, _lyricsAnchorRatio)
        .offset
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    final delta = targetOffset - position.pixels;

    if (immediate || delta.abs() < 0.5) {
      position.jumpTo(targetOffset);
      return;
    }

    final lines = ref.read(lyricsProvider).currentLyrics?.lines ?? const [];
    final durationMs = _scrollLeadMs(lines, lineIndex);

    // Publish this handover so rows can trail it (see _staggerOffset).
    _runDelta = delta;
    _runDurationMs = durationMs;
    _runFocus = lineIndex;
    _handover.duration = Duration(
      milliseconds:
          (durationMs * (1 + _staggerFraction * _staggerSteps)).round(),
    );
    _handover.forward(from: 0);

    position.animateTo(
      targetOffset,
      duration: Duration(milliseconds: durationMs),
      curve: _lyricEase,
    );
  }

  /// Seek to a specific position when a lyric line is tapped
  void _seekToLyric(int timeInMs) {
    ref.read(playbackTransportProvider).seek(Duration(milliseconds: timeInMs));
    _resumeAutoScroll();
  }

  @override
  Widget build(BuildContext context) {
    final lyricsState = ref.watch(lyricsProvider);
    final albumColors = ref.watch(playerAlbumColorsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = isDark ? albumColors : albumColors.toLightMode();
    final textColor = colors.onBackground;
    final secondaryColor = textColor.withValues(alpha: 0.5);
    final accentColor = isDark ? albumColors.accentLight : albumColors.accent;
    final showNerdStats = ref.watch(showNerdStatsProvider);

    // Reset scroll and line index when switching tracks or lyrics
    ref.listen(currentTrackProvider, (previous, next) {
      if (previous?.id != next?.id && mounted) {
        setState(() {
          _currentLineIndex = -1;
          _focusLineIndex = -1;
          _lineKeys = [];
          _isAutoScrollEnabled = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scrollController.hasClients) {
            _scrollController.jumpTo(0);
          }
        });
      }
    });

    ref.listen(lyricsProvider, (previous, next) {
      final prevData = previous?.currentLyrics;
      final nextData = next.currentLyrics;
      if (prevData != nextData && mounted) {
        if (prevData?.title != nextData?.title || prevData?.source != nextData?.source) {
          setState(() {
            _currentLineIndex = -1;
            _focusLineIndex = -1;
            _lineKeys = [];
            _isAutoScrollEnabled = true;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _scrollController.hasClients) {
              _scrollController.jumpTo(0);
            }
          });
        }
      }
    });

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 650),
      switchInCurve: Curves.easeOutQuart,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: KeyedSubtree(
        key: ValueKey(
          '${lyricsState.currentProvider}_${lyricsState.currentStatus.state}_${lyricsState.currentLyrics?.lines?.length ?? 0}',
        ),
        child: _buildLyricsContent(
          context,
          lyricsState,
          isDark,
          textColor,
          secondaryColor,
          accentColor,
          showNerdStats,
        ),
      ),
    );
  }

  Widget _buildLyricsContent(
    BuildContext context,
    LyricsState lyricsState,
    bool isDark,
    Color textColor,
    Color secondaryColor,
    Color accentColor,
    bool showNerdStats,
  ) {
    final l10n = context.l10n;
    final status = lyricsState.currentStatus;

    // Loading state
    if (status.state == LyricsProviderState.fetching) {
      final currentTrack = ref.watch(currentTrackProvider);
      final seed = currentTrack?.id.hashCode ?? 0;
      final phrase = LyricsLoadingTexts.getText(seed);

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                color: accentColor,
                strokeWidth: 2.8,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.music_note_rounded,
                  size: 22,
                  color: accentColor,
                  shadows: [
                    Shadow(
                      color: accentColor.withValues(alpha: 0.4),
                      blurRadius: 10,
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                Text(
                  phrase,
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.90),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              lyricsState.currentProvider.displayName,
              style: TextStyle(
                color: secondaryColor,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      );
    }

    // Error state
    if (status.state == LyricsProviderState.error) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Iconsax.warning_2, size: 48, color: secondaryColor),
            const SizedBox(height: 16),
            Text(
              l10n.failedToLoadLyrics,
              style: TextStyle(color: secondaryColor),
            ),

            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.read(lyricsProvider.notifier).nextProvider(),
              child: Text(l10n.tryAnotherProvider),
            ),
          ],
        ),
      );
    }

    // No lyrics found
    if (status.data == null || !status.data!.hasLyrics) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Iconsax.music, size: 48, color: secondaryColor),
            const SizedBox(height: 16),
            Text(l10n.noLyricsFound, style: TextStyle(color: secondaryColor)),

            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.read(lyricsProvider.notifier).nextProvider(),
              child: Text(l10n.tryAnotherProvider),
            ),
          ],
        ),
      );
    }

    final result = status.data!;

    final Widget lyricsBody;
    // Synced lyrics
    if (result.hasSyncedLyrics) {
      lyricsBody = _buildSyncedLyrics(
        result.lines!,
        isDark,
        textColor,
        secondaryColor,
        accentColor,
        showNerdStats: showNerdStats,
        result: result,
      );
    } else {
      // Plain lyrics
      lyricsBody = _buildPlainLyrics(
        result.lyrics!,
        isDark,
        textColor,
        showNerdStats: showNerdStats,
        result: result,
      );
    }

    return lyricsBody;
  }

  Widget _buildSyncedLyrics(
    List<LyricLine> lines,
    bool isDark,
    Color textColor,
    Color secondaryColor,
    Color accentColor, {
    bool showNerdStats = false,
    LyricResult? result,
  }) {
    if (_lineKeys.length != lines.length) {
      _lineKeys = List.generate(lines.length, (_) => GlobalKey());
      _currentLineIndex = -1;
      _focusLineIndex = -1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(0);
          if (widget.windowedDesktop && widget.isActive && _isAutoScrollEnabled) {
            _checkLineIndexChange(_smoothPositionNotifier.value, scroll: false);
            _scrollToCurrentLine(immediate: true);
          }
        }
      });
    }

    final currentIdx = _currentLineIndex;

    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollStartNotification &&
                notification.dragDetails != null) {
              _isUserScrolling = true;
              _onUserManualScroll();
            } else if (notification is ScrollUpdateNotification &&
                notification.dragDetails != null) {
              _onUserManualScroll();
            } else if (notification is ScrollEndNotification) {
              _isUserScrolling = false;
            }
            return false;
          },
          child: ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.white,
                Colors.white,
                Colors.transparent,
              ],
              stops: [0.0, 0.12, 0.88, 1.0],
            ).createShader(bounds),
            blendMode: BlendMode.dstIn,
            child: ListView.builder(
              controller: _scrollController,
              scrollCacheExtent: const ScrollCacheExtent.pixels(
                _lyricsScrollCache,
              ),
              // Let the sliver cull rows before painting their blur. The
              // content inside each row still has its own repaint boundary.
              addRepaintBoundaries: !widget.windowedDesktop,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 96),
              itemCount: lines.length + (showNerdStats ? 1 : 0),
              itemBuilder: (context, index) {
                if (showNerdStats && index == lines.length) {
                  final providerName = result?.source.isNotEmpty == true
                      ? result!.source
                      : 'Unknown';
                  final syncType = result?.hasWordSync == true
                      ? 'Word-synced'
                      : (result?.hasSyncedLyrics == true
                          ? 'Line-synced'
                          : 'Plain text');
                  return Padding(
                    padding: const EdgeInsets.only(top: 32, bottom: 48),
                    child: Center(
                      child: Text(
                        'Lyrics provided by $providerName ($syncType)',
                        style: TextStyle(
                          color: secondaryColor.withValues(alpha: 0.6),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  );
                }

                final line = lines[index];
                final isCurrentLine = index == currentIdx;
                final dist = currentIdx >= 0 ? (index - currentIdx).abs() : 999;
                final int nextStart = (index + 1 < lines.length)
                    ? lines[index + 1].timeInMs
                    : (line.timeInMs + 1000000);

                if (line.isGap) {
                  return _followHandover(index, RepaintBoundary(
                    child: _buildInstrumentalGapItem(
                      line: line,
                      index: index,
                      isCurrentLine: isCurrentLine,
                      dist: dist,
                      textColor: textColor,
                      accentColor: accentColor,
                      nextStart: nextStart,
                    ),
                  ));
                }

                if (line.hasWordSync) {
                  return _followHandover(index, RepaintBoundary(
                    child: _buildWordSyncLine(
                      line: line,
                      index: index,
                      isCurrentLine: isCurrentLine,
                      isSung: currentIdx >= 0 && index < currentIdx,
                      dist: dist,
                      textColor: textColor,
                      accentColor: accentColor,
                      nextStart: nextStart,
                    ),
                  ));
                }

                // Standard line-level animation (distance-based scaling)
                return _followHandover(index, RepaintBoundary(
                  child: _buildLineSyncRow(
                    line: line,
                    index: index,
                    isCurrentLine: isCurrentLine,
                    dist: dist,
                    textColor: textColor,
                    accentColor: accentColor,
                    nextStart: nextStart,
                  ),
                ));
              },
            ),
          ),
        ),

        // Floating auto-scroll sync button
        Positioned(
          bottom: 16,
          left: 0,
          right: 0,
          child: AnimatedSlide(
            offset: !_isAutoScrollEnabled ? Offset.zero : const Offset(0, 2),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutQuart,
            child: AnimatedOpacity(
              opacity: !_isAutoScrollEnabled ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              child: Center(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _resumeAutoScroll,
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Iconsax.refresh,
                            size: 18,
                            color: (accentColor.computeLuminance() > 0.60) ? Colors.black87 : Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Auto-scroll',
                            style: TextStyle(
                              color: (accentColor.computeLuminance() > 0.60) ? Colors.black87 : Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Options menu: always there, since it also holds the seek bar style,
        // refetch, copy and the sync offset.
          Positioned(
            top: 8,
            right: 16,
            child: IgnorePointer(
              ignoring: !widget.menuVisible,
              child: AnimatedOpacity(
                opacity: widget.menuVisible ? 1 : 0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                child: IconButton(
                  icon: const Icon(Iconsax.more),
                  color: textColor,
                  onPressed: () {
                    openOnce(
                      LyricsMenuSheet,
                      () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (context) => const LyricsMenuSheet(),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Lets a row trail the list during a handover (see [_staggerOffset]).
  /// Only rows that actually fan out read the animation each frame.
  Widget _followHandover(int index, Widget row) {
    // BitChord's depth: rows away from the one being sung go soft by their
    // distance, easing with the handover. None while reading by hand.
    final current = _currentLineIndex;
    final distance = current >= 0 ? (index - current).abs() : 0;
    final blurRadius = current < 0 || distance == 0 || !_isAutoScrollEnabled
        ? 0.0
        : _lineFalloffBlur[distance.clamp(0, _lineFalloffBlur.length - 1)] *
              widget.fontScale;
    row = TweenAnimationBuilder<double>(
      tween: Tween<double>(end: blurRadius),
      duration: _lyricSettle,
      curve: _lyricEase,
      builder: (context, radius, child) {
        // A Compose blur radius, as Skia turns it into a sigma.
        final sigma = radius > 0.01 ? radius * 0.57735 + 0.5 : 0.0;
        if (widget.windowedDesktop) {
          return _LyricRowBlur(sigma: sigma, child: child!);
        }
        return ImageFiltered(
          enabled: sigma > 0,
          imageFilter: ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.decal,
          ),
          child: child,
        );
      },
      child: row,
    );
    return AnimatedBuilder(
      animation: _handover,
      builder: (context, child) {
        final dy = _staggerOffset(index);
        if (dy == 0) return child!;
        return Transform.translate(offset: Offset(0, dy), child: child);
      },
      child: row,
    );
  }

  /// Instrumental gap line (musical pause) with animated glowing note icon, playful gap text, and seek-on-tap
  Widget _buildInstrumentalGapItem({
    required LyricLine line,
    required int index,
    required bool isCurrentLine,
    required int dist,
    required Color textColor,
    required Color accentColor,
    required int nextStart,
  }) {
    final displayText = (line.text.trim().isNotEmpty &&
            !LyricLine.isMusicalSymbol(line.text.trim()))
        ? line.text.trim()
        : (index == 0
            ? InstrumentalGapTexts.getIntroText(line.timeInMs)
            : InstrumentalGapTexts.getBreakText(line.timeInMs));

    final double iconSize = (isCurrentLine ? 24.0 : 18.0) * widget.fontScale;
    final opacity = isCurrentLine ? 1.0 : _falloffAlpha(dist);

    final noteColor = isCurrentLine
        ? accentColor
        : textColor.withValues(alpha: opacity);

    Widget content = AnimatedContainer(
      key: _lineKeys[index],
      duration: isCurrentLine ? _lyricSettle : Duration.zero,
      curve: _lyricEase,
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: isCurrentLine ? 14 : 8,
      ),
      child: AnimatedScale(
        scale: isCurrentLine ? 1.0 : _inactiveLineScale,
        duration: isCurrentLine ? _lyricSettle : Duration.zero,
        curve: _lyricEase,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.music_note_rounded,
              size: iconSize,
              color: noteColor,
              shadows: isCurrentLine
                  ? [
                      Shadow(
                        color: accentColor.withValues(alpha: 0.45),
                        blurRadius: 16,
                      ),
                    ]
                  : null,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                displayText,
                style: TextStyle(
                  fontFamily: desktopFontFamily,
                  fontFamilyFallback: desktopFontFamilyFallback,
                  fontStyle: FontStyle.italic,
                  fontSize: (isCurrentLine ? 20.0 : 16.0) * widget.fontScale,
                  fontWeight: isCurrentLine ? FontWeight.w600 : FontWeight.w400,
                  color: noteColor,
                  letterSpacing: 0.3,
                  shadows: isCurrentLine
                      ? [
                          Shadow(
                            color: accentColor.withValues(alpha: 0.35),
                            blurRadius: 12,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (isCurrentLine) {
      content = AnimatedBuilder(
        animation: _smoothPositionNotifier,
        builder: (context, child) {
          final pos = _smoothPositionNotifier.value;
          double gapAlpha = 1.0;
          final remaining = nextStart - pos;
          if (remaining < 350) {
            gapAlpha = (remaining / 350.0).clamp(0.0, 1.0);
          }
          final effectiveAlpha = (0.35 + (0.65 * gapAlpha)).clamp(0.35, 1.0);
          return Opacity(
            opacity: effectiveAlpha,
            child: child,
          );
        },
        child: content,
      );
    }

    return GestureDetector(
      onTap: () => _seekToLyric(line.timeInMs),
      child: AnimatedOpacity(
        opacity: isCurrentLine ? 1.0 : opacity,
        duration: isCurrentLine ? _lyricSettle : Duration.zero,
        curve: _lyricEase,
        child: content,
      ),
    );
  }

bool _isComplexScript(String text) {
  for (final unit in text.codeUnits) {
    if (unit >= 0x0900 && unit <= 0x0DFF) return true; // Indic (Tamil, etc.)
    if (unit >= 0x0590 && unit <= 0x08FF) return true; // Arabic, Hebrew
    if (unit >= 0x0E00 && unit <= 0x109F) return true; // Thai, Myanmar
    if (unit >= 0x2E80 && unit <= 0x9FFF) return true; // CJK
  }
  return false;
}

  /// Line-level synced row with distance attenuation and smooth fade transitions
  Widget _buildLineSyncRow({
    required LyricLine line,
    required int index,
    required bool isCurrentLine,
    required int dist,
    required Color textColor,
    required Color accentColor,
    required int nextStart,
  }) {
    final isBg = line.isBackground;
    // Every line shares one size and weight: the handover is carried by
    // scale and opacity only, so neighbouring rows never reflow.
    final fontSize = (isBg ? 18.0 : _syncedFontSize) * widget.fontScale;
    const fontWeight = FontWeight.w800;

    // Distance-based falloff (symmetric around the playing line)
    final opacity = isCurrentLine ? 1.0 : _falloffAlpha(dist);

    final targetOpacity = isBg ? 0.35 : opacity;
    final lyricColor = isCurrentLine ? accentColor : textColor;

    Widget content = AnimatedContainer(
      key: _lineKeys[index],
      duration: _lyricSettle,
      curve: _lyricEase,
      alignment: isBg ? Alignment.center : Alignment.centerLeft,
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: isBg ? 4 : 8,
      ),
      child: AnimatedDefaultTextStyle(
        duration: isCurrentLine ? _lyricSettle : Duration.zero,
        curve: _lyricEase,
        style: TextStyle(
          fontFamily: desktopFontFamily,
          fontFamilyFallback: desktopFontFamilyFallback,
          fontSize: fontSize,
          fontWeight: fontWeight,
          fontStyle: isBg ? FontStyle.italic : FontStyle.normal,
          color: lyricColor,
          height: 1.3,
          letterSpacing: _isComplexScript(line.text) ? 0.0 : -0.4,
          shadows: isCurrentLine
              ? [
                  Shadow(
                    color: accentColor.withValues(alpha: 0.35),
                    blurRadius: 14,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: isBg ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              line.text.isEmpty ? '♪' : line.text,
              softWrap: true,
            ),
            if (line.translatedText != null && line.translatedText!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: AnimatedDefaultTextStyle(
                  duration: _lyricSettle,
                  curve: _lyricEase,
                  style: TextStyle(
                    fontFamily: desktopFontFamily,
                    fontFamilyFallback: desktopFontFamilyFallback,
                    fontSize: fontSize * 0.75, // Smaller font for translation
                    fontWeight: FontWeight.w400,
                    color: textColor.withValues(alpha: 0.8), // Muted color
                    height: 1.2,
                  ),
                  child: Text(
                    line.translatedText!,
                    softWrap: true,
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (isCurrentLine) {
      content = AnimatedBuilder(
        animation: _smoothPositionNotifier,
        builder: (context, child) {
          final pos = _smoothPositionNotifier.value;
          double lineAlpha = 1.0;

          if (line.hasKnownEnd) {
            final vocalEnd = line.endMs;
            if (pos > vocalEnd) {
              final elapsed = pos - vocalEnd;
              lineAlpha = (1.0 - (elapsed / 350.0)).clamp(0.0, 1.0);
            }
            final remaining = nextStart - pos;
            if (remaining < 350) {
              final nextFade = (remaining / 350.0).clamp(0.0, 1.0);
              if (nextFade < lineAlpha) lineAlpha = nextFade;
            }
          } else if (nextStart > line.timeInMs) {
            final remaining = nextStart - pos;
            if (remaining < 350) {
              lineAlpha = (remaining / 350.0).clamp(0.0, 1.0);
            }
          }

          final effectiveAlpha = (0.40 + (0.60 * lineAlpha)).clamp(0.40, 1.0);

          return Opacity(
            opacity: effectiveAlpha,
            child: child,
          );
        },
        child: content,
      );
    }

    return GestureDetector(
      onTap: () => _seekToLyric(line.timeInMs),
      child: AnimatedScale(
        scale: isCurrentLine ? 1.0 : _inactiveLineScale,
        duration: _lyricSettle,
        curve: _lyricEase,
        alignment: isBg ? Alignment.center : Alignment.centerLeft,
        child: AnimatedOpacity(
          opacity: isCurrentLine ? 1.0 : targetOpacity,
          duration: isCurrentLine ? _lyricSettle : Duration.zero,
          curve: _lyricEase,
          child: content,
        ),
      ),
    );
  }

  /// Word-level synced line with bouncy karaoke animation, isolated word repaints, and smooth fade transitions
  Widget _buildWordSyncLine({
    required LyricLine line,
    required int index,
    required bool isCurrentLine,
    required bool isSung,
    required int dist,
    required Color textColor,
    required Color accentColor,
    required int nextStart,
  }) {
    final isBg = line.isBackground;
    // Same type for every line; the handover is scale + opacity only.
    final fontSize = (isBg ? 18.0 : _syncedFontSize) * widget.fontScale;

    // Distance attenuation for inactive lines (applied once, on the layer)
    final lineAlpha = isCurrentLine ? 1.0 : _falloffAlpha(dist);

    final targetOpacity = isBg ? 0.35 : lineAlpha;

    Widget content = AnimatedContainer(
      key: _lineKeys[index],
      duration: _lyricSettle,
      curve: _lyricEase,
      alignment: isBg ? Alignment.center : Alignment.centerLeft,
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: isBg ? 4 : 8,
      ),
      child: Column(
        crossAxisAlignment: isBg ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // BitChord's sweep: a dim copy with a lit one clipped to what has
          // been sung, the word being sung lifted and held notes swelling a
          // letter at a time. Every word-synced line goes through it, so a
          // finished line closes up to full brightness as it dims away.
          TweenAnimationBuilder<double>(
            tween: Tween<double>(end: isSung ? 1.0 : kSweptUnsungAlpha),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            builder: (context, dimAlpha, _) => TweenAnimationBuilder<double>(
              tween: Tween<double>(
                end: isCurrentLine && !isBg ? kSweptGlowAlpha : 0.0,
              ),
              duration: const Duration(milliseconds: 420),
              curve: Curves.fastOutSlowIn,
              builder: (context, glowAlpha, _) => SweptLyricLine(
                line: line,
                position: _smoothPositionNotifier,
                style: TextStyle(
                  fontFamily: desktopFontFamily,
                  fontFamilyFallback: desktopFontFamilyFallback,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w800,
                  fontStyle: isBg ? FontStyle.italic : FontStyle.normal,
                  height: 1.3,
                  letterSpacing: _isComplexScript(line.text) ? 0.0 : -0.4,
                ),
                color: textColor,
                dimAlpha: dimAlpha,
                glowAlpha: glowAlpha,
                feather: isCurrentLine,
                // Only the lead lifts; on the answering voice the movement
                // competes with the line being read.
                rise: !isBg,
                textAlign: isBg ? TextAlign.center : TextAlign.start,
              ),
            ),
          ),
          if (line.translatedText != null && line.translatedText!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6.0),
              child: Text(
                line.translatedText!,
                style: TextStyle(
                  fontFamily: desktopFontFamily,
                  fontFamilyFallback: desktopFontFamilyFallback,
                  fontSize: fontSize * 0.72,
                  fontWeight: FontWeight.w400,
                  color: isCurrentLine
                      ? accentColor.withValues(alpha: 0.75)
                      : textColor.withValues(alpha: 0.75),
                  height: 1.2,
                ),
              ),
            ),
        ],
      ),
    );

    if (isCurrentLine) {
      content = AnimatedBuilder(
        animation: _smoothPositionNotifier,
        builder: (context, child) {
          final pos = _smoothPositionNotifier.value;
          double vocalAlpha = 1.0;

          if (line.hasKnownEnd) {
            final vocalEnd = line.endMs;
            if (pos > vocalEnd) {
              final elapsed = pos - vocalEnd;
              vocalAlpha = (1.0 - (elapsed / 350.0)).clamp(0.0, 1.0);
            }
            final remaining = nextStart - pos;
            if (remaining < 350) {
              final nextFade = (remaining / 350.0).clamp(0.0, 1.0);
              if (nextFade < vocalAlpha) vocalAlpha = nextFade;
            }
          } else if (nextStart > line.timeInMs) {
            final remaining = nextStart - pos;
            if (remaining < 350) {
              vocalAlpha = (remaining / 350.0).clamp(0.0, 1.0);
            }
          }

          final effectiveAlpha = (0.45 + (0.55 * vocalAlpha)).clamp(0.45, 1.0);

          return Opacity(
            opacity: effectiveAlpha,
            child: child,
          );
        },
        child: content,
      );
    }

    return GestureDetector(
      onTap: () => _seekToLyric(line.timeInMs),
      child: AnimatedScale(
        scale: isCurrentLine ? 1.0 : _inactiveLineScale,
        duration: _lyricSettle,
        curve: _lyricEase,
        alignment: isBg ? Alignment.center : Alignment.centerLeft,
        child: AnimatedOpacity(
          opacity: isCurrentLine ? 1.0 : targetOpacity,
          duration: isCurrentLine ? _lyricSettle : Duration.zero,
          curve: _lyricEase,
          child: content,
        ),
      ),
    );
  }

  Widget _buildPlainLyrics(
    String lyrics,
    bool isDark,
    Color textColor, {
    bool showNerdStats = false,
    LyricResult? result,
  }) {
    final lines = lyrics
        .split('\n')
        .map((l) => l.trimRight())
        .toList(growable: false);

    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.white,
          Colors.white,
          Colors.transparent,
        ],
        stops: [0.0, 0.1, 0.9, 1.0],
      ).createShader(bounds),
      blendMode: BlendMode.dstIn,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
        itemCount: lines.length + (showNerdStats ? 1 : 0),
        itemBuilder: (context, index) {
          if (showNerdStats && index == lines.length) {
            final providerName = result?.source.isNotEmpty == true
                ? result!.source
                : 'Unknown';
            return Padding(
              padding: const EdgeInsets.only(top: 32, bottom: 48),
              child: Center(
                child: Text(
                  'Lyrics provided by $providerName',
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.35),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            );
          }

          final line = lines[index];

          if (line.isEmpty) {
            return const SizedBox(height: 18);
          }

          final isSection = line.startsWith('[') && line.endsWith(']');
          final displayLine = isSection
              ? line.replaceAll(RegExp(r'^[\[\(]+|[\]\)]+$'), '')
              : line;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                displayLine,
                style: TextStyle(
                  fontFamily: desktopFontFamily,
                  fontFamilyFallback: desktopFontFamilyFallback,
                  fontSize: (isSection ? 18 : 22) * widget.fontScale,
                  fontWeight: isSection ? FontWeight.w700 : FontWeight.w400,
                  letterSpacing: isSection ? 0.5 : 0.0,
                  color: textColor.withValues(alpha: isSection ? 0.75 : 0.95),
                  height: 1.35,
                ),
              ),
            ),
          );
        },
      ),
    );
  }






}

/// The sliver only paints rows intersecting the viewport. Keep the filter out
/// of the cached row's repaint boundary so offscreen rows own no blur layer.
class _LyricRowBlur extends SingleChildRenderObjectWidget {
  const _LyricRowBlur({required this.sigma, required Widget super.child});

  final double sigma;

  @override
  _RenderLyricRowBlur createRenderObject(BuildContext context) =>
      _RenderLyricRowBlur(sigma);

  @override
  void updateRenderObject(BuildContext context, _RenderLyricRowBlur renderObject) {
    renderObject.sigma = sigma;
  }
}

class _RenderLyricRowBlur extends RenderProxyBox {
  _RenderLyricRowBlur(this._sigma);

  double _sigma;

  set sigma(double value) {
    if (value == _sigma) return;
    final wasComposited = alwaysNeedsCompositing;
    _sigma = value;
    if (wasComposited != alwaysNeedsCompositing) {
      markNeedsCompositingBitsUpdate();
    }
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => child != null && _sigma > 0;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!alwaysNeedsCompositing) {
      super.paint(context, offset);
      return;
    }
    context.pushLayer(
      ImageFilterLayer(
        imageFilter: ImageFilter.blur(
          sigmaX: _sigma,
          sigmaY: _sigma,
          tileMode: TileMode.decal,
        ),
      ),
      super.paint,
      offset,
    );
  }
}

/// Compact lyrics display for mini player or controls area
class LyricsLine extends ConsumerWidget {
  final Duration currentPosition;

  const LyricsLine({super.key, required this.currentPosition});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyricsState = ref.watch(lyricsProvider);
    final albumColors = ref.watch(playerAlbumColorsProvider);
    final textColor = albumColors.onBackground;

    if (!lyricsState.hasLyrics) {
      return const SizedBox.shrink();
    }

    final result = lyricsState.currentLyrics!;

    if (!result.hasSyncedLyrics) {
      return const SizedBox.shrink();
    }

    // Find current line
    final offset = ref.read(lyricsSyncOffsetProvider);
    final positionMs = currentPosition.inMilliseconds + offset;
    String currentText = '';

    for (final line in result.lines!) {
      if (line.timeInMs <= positionMs) {
        currentText = line.text;
      } else {
        break;
      }
    }

    if (currentText.isEmpty) return const SizedBox.shrink();

    return Text(
      currentText,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: desktopFontFamily,
        fontFamilyFallback: desktopFontFamilyFallback,
        color: textColor.withValues(alpha: 0.7),
        fontSize: 13,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}
