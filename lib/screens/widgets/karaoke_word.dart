import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../services/lyrics/lyrics_models.dart';

/// Isolated karaoke word widget that repaints smoothly on frame ticks without rebuilding the parent widget tree
class KaraokeWord extends StatelessWidget {
  final LyricWord word;
  final bool isLastWord;
  final bool isCurrentLine;
  final ValueNotifier<int> positionNotifier;
  final double fontSize;
  final bool isBg;
  final Color textColor;
  final Color accentColor;
  final Color dimColor;

  const KaraokeWord({
    super.key,
    required this.word,
    required this.isLastWord,
    required this.isCurrentLine,
    required this.positionNotifier,
    required this.fontSize,
    required this.isBg,
    required this.textColor,
    required this.accentColor,
    required this.dimColor,
  });

  @override
  Widget build(BuildContext context) {
    final wordText = isLastWord ? word.text : '${word.text} ';
    final duration = (word.endTimeMs - word.startTimeMs).toDouble();

    // Inactive line: render simple static text with zero overhead
    if (!isCurrentLine) {
      return Text(
        wordText,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w400,
          fontStyle: isBg ? FontStyle.italic : FontStyle.normal,
          color: dimColor,
          height: 1.3,
        ),
      );
    }

    // Active line: listen to positionNotifier and repaint only this word boundary
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: positionNotifier,
        builder: (context, _) {
          final pos = positionNotifier.value;
          final isWordActive =
              pos >= word.startTimeMs && pos < word.endTimeMs;
          final isWordSung = pos >= word.endTimeMs;

          if (isWordActive && duration > 0) {
            final raw = ((pos - word.startTimeMs) / duration).clamp(0.0, 1.0);
            // Smooth Hermite cubic interpolation
            final fillProgress = raw * raw * (3.0 - 2.0 * raw);
            final glowIntensity = fillProgress * fillProgress;
            final scalePop =
                1.0 + (0.04 * math.sin(fillProgress * math.pi));
            final shadowBlur = fontSize < 20
                ? (4.0 + (6.0 * glowIntensity))
                : (10.0 + (14.0 * glowIntensity));

            return Transform.scale(
              scale: scalePop,
              alignment: Alignment.centerLeft,
              child: ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) {
                  return LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      accentColor,
                      accentColor,
                      accentColor.withValues(alpha: 0.90),
                      textColor.withValues(alpha: 0.35),
                      textColor.withValues(alpha: 0.35),
                    ],
                    stops: [
                      0.0,
                      (fillProgress * 0.92).clamp(0.0, 1.0),
                      fillProgress,
                      (fillProgress + 0.08).clamp(0.0, 1.0),
                      1.0,
                    ],
                  ).createShader(bounds);
                },
                child: Text(
                  wordText,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w800,
                    fontStyle: isBg ? FontStyle.italic : FontStyle.normal,
                    height: 1.3,
                    letterSpacing: -0.3,
                    shadows: [
                      Shadow(
                        color: accentColor.withValues(
                          alpha: 0.30 + (0.35 * glowIntensity),
                        ),
                        blurRadius: shadowBlur,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          if (isWordSung) {
            final sungShadowBlur = fontSize < 20 ? 4.0 : 8.0;
            return Text(
              wordText,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                fontStyle: isBg ? FontStyle.italic : FontStyle.normal,
                color: accentColor,
                height: 1.3,
                letterSpacing: -0.3,
                shadows: [
                  Shadow(
                    color: accentColor.withValues(alpha: 0.25),
                    blurRadius: sungShadowBlur,
                  ),
                ],
              ),
            );
          }

          // Upcoming words in active line: rendered dimmer so sung words pop out
          return Text(
            wordText,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              fontStyle: isBg ? FontStyle.italic : FontStyle.normal,
              color: textColor.withValues(alpha: 0.35),
              height: 1.3,
              letterSpacing: -0.2,
            ),
          );
        },
      ),
    );
  }
}
