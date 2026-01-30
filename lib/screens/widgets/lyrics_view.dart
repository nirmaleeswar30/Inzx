import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import '../../providers/music_providers.dart';
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final secondaryColor = textColor.withValues(alpha: 0.5);

    return _buildLyricsContent(lyricsState, isDark, textColor, secondaryColor);
  }

  Widget _buildLyricsContent(
    LyricsState lyricsState,
    bool isDark,
    Color textColor,
    Color secondaryColor,
  ) {
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
              'Searching for lyrics...',
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
              'Failed to load lyrics',
              style: TextStyle(color: secondaryColor),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.read(lyricsProvider.notifier).nextProvider(),
              child: const Text('Try another provider'),
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
            Text('No lyrics found', style: TextStyle(color: secondaryColor)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.read(lyricsProvider.notifier).nextProvider(),
              child: const Text('Try another provider'),
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
        if (_scrollController.hasClients) {
          // Calculate offset to center the current line
          final lineHeight = 70.0; // Matches new taller rows
          final screenCenter = 200.0; // Approximate center offset
          final targetOffset = (currentIdx * lineHeight) - screenCenter;
          _scrollController.animateTo(
            targetOffset.clamp(0, _scrollController.position.maxScrollExtent),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
          );
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
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              height: 70, // Taller for bigger text
              alignment: Alignment.centerLeft, // LEFT aligned
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlainLyrics(String lyrics, bool isDark, Color textColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Text(
        lyrics,
        style: TextStyle(
          fontSize: 16,
          color: textColor.withValues(alpha: 0.9),
          height: 1.6,
        ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

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
