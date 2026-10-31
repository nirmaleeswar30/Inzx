import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../services/lyrics/lyrics_models.dart';

/// Isolated karaoke word widget that repaints smoothly on frame ticks without
/// rebuilding the parent widget tree.
///
/// Every state (not yet sung, being sung, sung, inactive line) uses exactly
/// the same type — size, weight, spacing — so a word never changes width and
/// the line never re-wraps as the highlight moves. Everything that animates is
/// paint-only: the colour wipe, a small lift and the glow.
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

  /// How far the word being sung lifts off the line. Defaults to scale with
  /// the type (2px at BitChord's 34px lyrics).
  final double? rise;

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
    this.rise,
  });

  /// The words ahead of the highlight, held back.
  static const double _unsungAlpha = 0.45;

  /// The wipe's leading edge fades over this many pixels instead of ending on
  /// a cut, so it reads as words lighting up rather than a bar sliding along.
  static const double _wipeFeather = 30;

  double get _rise => rise ?? fontSize / 17;

  /// How long a sung word takes to settle back onto the line.
  static const int _settleMs = 300;

  /// Only held notes glow; quick syllables stay clean.
  static const int _glowMinDurationMs = 900;
  static const double _glowAlpha = 0.62;

  TextStyle _style(Color color, {List<Shadow>? shadows}) => TextStyle(
    fontSize: fontSize,
    fontWeight: FontWeight.w800,
    fontStyle: isBg ? FontStyle.italic : FontStyle.normal,
    height: 1.3,
    letterSpacing: -0.3,
    color: color,
    shadows: shadows,
  );

  @override
  Widget build(BuildContext context) {
    final wordText = isLastWord ? word.text : '${word.text} ';

    // Inactive line: static text, same metrics as the active one.
    if (!isCurrentLine) {
      return Text(wordText, style: _style(dimColor));
    }

    final start = word.startTimeMs;
    final end = word.endTimeMs;
    final duration = math.max(1, end - start);
    final unsung = textColor.withValues(alpha: _unsungAlpha);
    final holdsNote = duration >= _glowMinDurationMs;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: positionNotifier,
        builder: (context, _) {
          final pos = positionNotifier.value;

          if (pos < start) {
            return Text(wordText, style: _style(unsung));
          }

          if (pos >= end) {
            // Sung: full colour, easing back down onto the line.
            final settle = ((pos - end) / _settleMs).clamp(0.0, 1.0);
            final lift = _rise * (1 - Curves.easeOut.transform(settle));
            final text = Text(wordText, style: _style(accentColor));
            return lift <= 0.01
                ? text
                : Transform.translate(offset: Offset(0, -lift), child: text);
          }

          // Being sung: a feathered wipe moving at the word's own pace.
          final progress = (pos - start) / duration;
          final lift = _rise * Curves.easeOut.transform(
            (progress * 3).clamp(0.0, 1.0),
          );
          final glow = holdsNote ? _glowAlpha * progress : 0.0;

          return Transform.translate(
            offset: Offset(0, -lift),
            child: ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) {
                final width = math.max(1.0, bounds.width);
                final edge = progress * (width + _wipeFeather);
                final solidEnd = ((edge - _wipeFeather) / width).clamp(0.0, 1.0);
                final fadeEnd = (edge / width).clamp(0.0, 1.0);
                return LinearGradient(
                  colors: [accentColor, accentColor, unsung, unsung],
                  stops: [0.0, solidEnd, math.max(fadeEnd, solidEnd), 1.0],
                ).createShader(bounds);
              },
              child: Text(
                wordText,
                style: _style(
                  Colors.white,
                  shadows: glow > 0
                      ? [
                          Shadow(
                            color: accentColor.withValues(alpha: glow),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
