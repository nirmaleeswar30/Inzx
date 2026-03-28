import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import '../../core/l10n/app_localizations_x.dart';
import '../../providers/music_providers.dart';
import '../../providers/providers.dart';
import '../../services/lyrics/lyrics_service.dart';
import '../../services/lyrics/lyrics_models.dart';

/// Lyrics view widget for Now Playing screen
class LyricsView extends ConsumerStatefulWidget {
  final Duration currentPosition;

  const LyricsView({super.key, required this.currentPosition});

  @override
  ConsumerState<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<LyricsView> {
  final ScrollController _scrollController = ScrollController();
  int _currentLineIndex = -1;
  List<GlobalKey> _lineKeys = [];

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Seek to a specific position when a lyric line is tapped
  void _seekToLyric(int timeInMs) {
    ref.read(audioPlayerServiceProvider).seek(Duration(milliseconds: timeInMs));
  }

  @override
  Widget build(BuildContext context) {
    final lyricsState = ref.watch(lyricsProvider);
    final albumColors = ref.watch(albumColorsProvider);
    // Use dark text in light mode (pastel background), light text in dark mode
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = isDark ? albumColors : albumColors.toLightMode();
    final textColor = colors.onBackground;
    final secondaryColor = textColor.withValues(alpha: 0.5);

    return _buildLyricsContent(
      context,
      lyricsState,
      isDark,
      textColor,
      secondaryColor,
    );
  }

  Widget _buildLyricsContent(
    BuildContext context,
    LyricsState lyricsState,
    bool isDark,
    Color textColor,
    Color secondaryColor,
  ) {
    final l10n = context.l10n;
    final status = lyricsState.currentStatus;

    // Loading state
    if (status.state == LyricsProviderState.fetching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: textColor),
            const SizedBox(height: 16),
            Text(
              l10n.searchingForLyrics,
              style: TextStyle(color: secondaryColor),
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

    // Synced lyrics
    if (result.hasSyncedLyrics) {
      return _buildSyncedLyrics(
        result.lines!,
        isDark,
        textColor,
        secondaryColor,
      );
    }

    // Plain lyrics
    return _buildPlainLyrics(result.lyrics!, isDark, textColor);
  }

  Widget _buildSyncedLyrics(
    List<LyricLine> lines,
    bool isDark,
    Color textColor,
    Color secondaryColor,
  ) {
    if (_lineKeys.length != lines.length) {
      _lineKeys = List.generate(lines.length, (_) => GlobalKey());
    }

    // Find current line based on position
    final positionMs = widget.currentPosition.inMilliseconds;
    int currentIdx = -1;

    for (int i = 0; i < lines.length; i++) {
      if (lines[i].timeInMs <= positionMs) {
        currentIdx = i;
      } else {
        break;
      }
    }

    // Auto-scroll to keep current line centered
    if (currentIdx != _currentLineIndex && currentIdx >= 0) {
      _currentLineIndex = currentIdx;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients && currentIdx < _lineKeys.length) {
          final keyContext = _lineKeys[currentIdx].currentContext;
          if (keyContext != null) {
            Scrollable.ensureVisible(
              keyContext,
              alignment: 0.35,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
            );
          } else {
            final targetOffset = (currentIdx * 72.0).clamp(
              0.0,
              _scrollController.position.maxScrollExtent,
            );
            _scrollController.animateTo(
              targetOffset,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
            );
          }
        }
      });
    }

    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.white,
          Colors.white,
          Colors.transparent,
        ],
        stops: const [0.0, 0.1, 0.9, 1.0],
      ).createShader(bounds),
      blendMode: BlendMode.dstIn,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
        itemCount: lines.length,
        itemBuilder: (context, index) {
          final line = lines[index];
          final isCurrentLine = index == currentIdx;
          final isPastLine = index < currentIdx;

          // User preference: bigger fonts, LEFT aligned
          final opacity = isCurrentLine ? 1.0 : (isPastLine ? 0.35 : 0.5);
          final fontSize = isCurrentLine ? 28.0 : 22.0; // Bigger fonts
          final fontWeight = isCurrentLine ? FontWeight.bold : FontWeight.w400;

          return GestureDetector(
            onTap: () => _seekToLyric(line.timeInMs),
            child: AnimatedContainer(
              key: _lineKeys[index],
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              alignment: Alignment.centerLeft, // LEFT aligned
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: fontWeight,
                  color: textColor.withValues(alpha: opacity),
                  height: 1.3,
                ),
                child: Text(
                  line.text.isEmpty ? '♪' : line.text,
                  softWrap: true,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlainLyrics(String lyrics, bool isDark, Color textColor) {
    final lines = lyrics
        .split('\n')
        .map((l) => l.trimRight())
        .toList(growable: false);

    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.white,
          Colors.white,
          Colors.transparent,
        ],
        stops: const [0.0, 0.1, 0.9, 1.0],
      ).createShader(bounds),
      blendMode: BlendMode.dstIn,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
        itemCount: lines.length,
        itemBuilder: (context, index) {
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
    final albumColors = ref.watch(albumColorsProvider);
    // Use album colors since this is displayed on album-colored surfaces
    final textColor = albumColors.onBackground;

    if (!lyricsState.hasLyrics) {
      return const SizedBox.shrink();
    }

    final result = lyricsState.currentLyrics!;

    if (!result.hasSyncedLyrics) {
      return const SizedBox.shrink();
    }

    // Find current line
    final positionMs = currentPosition.inMilliseconds;
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
