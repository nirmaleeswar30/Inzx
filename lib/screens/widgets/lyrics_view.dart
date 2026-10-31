import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import '../../core/l10n/app_localizations_x.dart';
import '../../providers/music_providers.dart';
import '../../providers/providers.dart';
import '../../services/lyrics/lyrics_service.dart';
import '../../services/lyrics/lyrics_models.dart';
import '../../services/lyrics/instrumental_gaps.dart';
import 'karaoke_word.dart';
import 'lyrics_menu_sheet.dart';

/// Preview duration before auto-scroll resumes after manual scrolling
const _lyricsPreviewTimeMs = 8000;
const _lyricsAnchorRatio = 0.35; // 35% from the top of the viewport

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
const List<double> _lineFalloffAlpha = [1.0, 0.74, 0.6, 0.48, 0.4, 0.34];
const double _syncedFontSize = 26.0;

double _falloffAlpha(int dist) =>
    _lineFalloffAlpha[dist.clamp(0, _lineFalloffAlpha.length - 1)];

/// Lyrics view widget for Now Playing screen with synced animations
class LyricsView extends ConsumerStatefulWidget {
  final Duration currentPosition;
  final bool isActive;

  const LyricsView({
    super.key,
    required this.currentPosition,
    this.isActive = true,
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
  int _lastAudioMs = 0;
  int _lastSyncEpochMs = 0;

  // Auto-scroll management
  bool _isAutoScrollEnabled = true;
  Timer? _autoScrollResumeTimer;
  bool _isUserScrolling = false;

  @override
  void initState() {
    super.initState();
    final offset = ref.read(lyricsSyncOffsetProvider);
    _lastAudioMs = widget.currentPosition.inMilliseconds + offset;
    _lastSyncEpochMs = DateTime.now().millisecondsSinceEpoch;
    _smoothPositionNotifier.value = _lastAudioMs;

    _handover = AnimationController(vsync: this);

    _ticker = createTicker((_) {
      final isPlaying = ref.read(isPlayingProvider);
      if (isPlaying) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final elapsed = now - _lastSyncEpochMs;
        final current = _lastAudioMs + elapsed;
        if (_smoothPositionNotifier.value != current) {
          _smoothPositionNotifier.value = current;
          _checkLineIndexChange(current);
        }
      } else if (_smoothPositionNotifier.value != _lastAudioMs) {
        _smoothPositionNotifier.value = _lastAudioMs;
        _checkLineIndexChange(_lastAudioMs);
      }
    });
    // Only run the per-frame clock while the lyrics are on screen and the
    // song is playing; otherwise it would tick (and wake the CPU) for nothing.
    ref.listenManual(isPlayingProvider, (_, _) => _syncTicker());
    _syncTicker();
  }

  void _syncTicker() {
    final shouldRun = widget.isActive && ref.read(isPlayingProvider);
    if (shouldRun && !_ticker.isActive) {
      _lastSyncEpochMs = DateTime.now().millisecondsSinceEpoch;
      _ticker.start();
    } else if (!shouldRun && _ticker.isActive) {
      _ticker.stop();
      _smoothPositionNotifier.value = _lastAudioMs;
      _checkLineIndexChange(_lastAudioMs);
    }
  }

  void _checkLineIndexChange(int currentPositionMs) {
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
      if (_isAutoScrollEnabled && widget.isActive) {
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

    final offset = ref.read(lyricsSyncOffsetProvider);
    final newMs = widget.currentPosition.inMilliseconds + offset;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Estimate where the clock would be now
    final estimatedCurrent = _lastAudioMs + (now - _lastSyncEpochMs);
    final drift = (newMs - estimatedCurrent).abs();

    // Only update sync anchor if there's significant drift (> 80ms) or a seek event
    if (drift > 80 || newMs < _lastAudioMs || newMs - _lastAudioMs > 1000) {
      _lastAudioMs = newMs;
      _lastSyncEpochMs = now;
      _smoothPositionNotifier.value = newMs;
      _checkLineIndexChange(newMs);
    }
  }

  @override
  void dispose() {
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
      final approxOffset = (target * 60.0).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.jumpTo(approxOffset);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            widget.isActive &&
            _scrollController.hasClients &&
            target < _lineKeys.length) {
          final newContext = _lineKeys[target].currentContext;
          if (newContext != null) {
            _ensureLineVisible(newContext, target, immediate: immediate);
          }
        }
      });
    }
  }

  void _ensureLineVisible(
    BuildContext keyContext,
    int lineIndex, {
    bool immediate = false,
  }) {
    if (!widget.isActive) return;
    final renderObject = keyContext.findRenderObject();
    if (renderObject == null || !renderObject.attached) return;

    if (!_scrollController.hasClients ||
        !_scrollController.position.hasContentDimensions) {
      return;
    }

    // Scroll ONLY the lyrics ScrollController position.
    // Never call Scrollable.ensureVisible(keyContext) because that bubbles up all
    // ancestor Scrollables including the parent horizontal PageView in NowPlayingScreen,
    // halting PageView transitions and forcefully switching tabs.
    final position = _scrollController.position;
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

    _scrollController.animateTo(
      targetOffset,
      duration: Duration(milliseconds: durationMs),
      curve: _lyricEase,
    );
  }

  /// Seek to a specific position when a lyric line is tapped
  void _seekToLyric(int timeInMs) {
    ref.read(audioPlayerServiceProvider).seek(Duration(milliseconds: timeInMs));
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
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
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
              scrollCacheExtent: const ScrollCacheExtent.pixels(1500.0),
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
        // Options Menu
        if (showNerdStats || ref.watch(aiLyricsTranslationEnabledProvider))
          Positioned(
            top: 8,
            right: 16,
            child: IconButton(
              icon: const Icon(Iconsax.more),
              color: textColor,
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => const LyricsMenuSheet(),
                );
              },
            ),
          ),
      ],
    );
  }

  /// Lets a row trail the list during a handover (see [_staggerOffset]).
  /// Only rows that actually fan out read the animation each frame.
  Widget _followHandover(int index, Widget row) {
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

    final double iconSize = isCurrentLine ? 24.0 : 18.0;
    final opacity = isCurrentLine ? 1.0 : _falloffAlpha(dist);

    final noteColor = isCurrentLine
        ? accentColor
        : textColor.withValues(alpha: opacity);

    Widget content = AnimatedContainer(
      key: _lineKeys[index],
      duration: _lyricSettle,
      curve: _lyricEase,
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: isCurrentLine ? 14 : 8,
      ),
      child: AnimatedScale(
        scale: isCurrentLine ? 1.0 : _inactiveLineScale,
        duration: _lyricSettle,
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
                  fontStyle: FontStyle.italic,
                  fontSize: isCurrentLine ? 20.0 : 16.0,
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
        duration: _lyricSettle,
        curve: _lyricEase,
        child: content,
      ),
    );
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
    final fontSize = isBg ? 18.0 : _syncedFontSize;
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
        duration: _lyricSettle,
        curve: _lyricEase,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          fontStyle: isBg ? FontStyle.italic : FontStyle.normal,
          color: lyricColor,
          height: 1.3,
          letterSpacing: -0.4,
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
          duration: _lyricSettle,
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
    required int dist,
    required Color textColor,
    required Color accentColor,
    required int nextStart,
  }) {
    final isBg = line.isBackground;
    // Same type for every line; the handover is scale + opacity only.
    final fontSize = isBg ? 18.0 : _syncedFontSize;

    // Distance attenuation for inactive lines (applied once, on the layer)
    final lineAlpha = isCurrentLine ? 1.0 : _falloffAlpha(dist);

    final targetOpacity = isBg ? 0.35 : lineAlpha;
    final dimColor = isBg ? textColor.withValues(alpha: 0.35) : textColor;

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
          Wrap(
            alignment: isBg ? WrapAlignment.center : WrapAlignment.start,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: line.words!.asMap().entries.map((entry) {
              final wordIdx = entry.key;
              final word = entry.value;
              final isLastWord = wordIdx == line.words!.length - 1;

              return KaraokeWord(
                word: word,
                isLastWord: isLastWord,
                isCurrentLine: isCurrentLine,
                positionNotifier: _smoothPositionNotifier,
                fontSize: fontSize,
                isBg: isBg,
                textColor: textColor,
                accentColor: accentColor,
                dimColor: dimColor,
              );
            }).toList(),
          ),
          if (line.translatedText != null && line.translatedText!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6.0),
              child: Text(
                line.translatedText!,
                style: TextStyle(
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
          duration: _lyricSettle,
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
                  fontSize: isSection ? 18 : 22,
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
        color: textColor.withValues(alpha: 0.7),
        fontSize: 13,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}
