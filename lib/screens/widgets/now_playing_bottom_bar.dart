import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design_system/design_system.dart';

/// Bottom row of every portrait Now Playing layout: a lyrics bubble on the
/// left, the output device in the middle and an Up Next bubble on the right,
/// all on one level.
class NowPlayingBottomBar extends StatelessWidget {
  const NowPlayingBottomBar({
    super.key,
    required this.textColor,
    required this.onOpenLyrics,
    required this.onOpenQueue,
    this.center,
  });

  final Color textColor;
  final VoidCallback onOpenLyrics;
  final VoidCallback onOpenQueue;

  /// Usually the output device pill; empty space when routing is hidden.
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 30),
      child: Row(
        children: [
          _BubbleButton(
            textColor: textColor,
            tooltip: 'Lyrics',
            onTap: onOpenLyrics,
            glyph: _LyricsGlyph(color: textColor.withValues(alpha: 0.9)),
          ),
          Expanded(child: Center(child: center ?? const SizedBox.shrink())),
          _BubbleButton(
            textColor: textColor,
            tooltip: 'Up next',
            onTap: onOpenQueue,
            glyph: _QueueGlyph(color: textColor.withValues(alpha: 0.9)),
          ),
        ],
      ),
    );
  }
}

class _BubbleButton extends StatelessWidget {
  const _BubbleButton({
    required this.textColor,
    required this.tooltip,
    required this.onTap,
    required this.glyph,
  });

  final Color textColor;
  final String tooltip;
  final VoidCallback onTap;
  final Widget glyph;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: BouncyTouch(
        style: BouncyStyle.button,
        customScale: 0.9,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: textColor.withValues(alpha: 0.10),
            border: Border.all(color: textColor.withValues(alpha: 0.12)),
          ),
          alignment: Alignment.center,
          child: SizedBox(width: 22, height: 22, child: glyph),
        ),
      ),
    );
  }
}

/// A rounded speech bubble holding a pair of closing quote marks.
class _LyricsGlyph extends StatelessWidget {
  const _LyricsGlyph({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _LyricsGlyphPainter(color));
}

class _LyricsGlyphPainter extends CustomPainter {
  _LyricsGlyphPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Bubble body with a tail at the lower left.
    final body = RRect.fromLTRBR(3 * s, 3.5 * s, 21 * s, 17.5 * s, Radius.circular(3.5 * s));
    final bubble = Path()
      ..addRRect(body)
      ..moveTo(7 * s, 17.5 * s)
      ..lineTo(6.5 * s, 21 * s)
      ..lineTo(10.5 * s, 17.5 * s);
    canvas.drawPath(bubble, stroke);

    // Two quote marks: a dot with a short tail curling down-left.
    final fill = Paint()..color = color;
    for (final cx in [9.5 * s, 14.5 * s]) {
      canvas.drawCircle(Offset(cx, 9.6 * s), 1.6 * s, fill);
      final tail = Path()
        ..moveTo(cx + 1.5 * s, 9.8 * s)
        ..quadraticBezierTo(cx + 1.3 * s, 12.6 * s, cx - 1.2 * s, 13.2 * s);
      canvas.drawPath(tail, stroke..strokeWidth = 1.7 * s);
      stroke.strokeWidth = 2 * s;
    }
  }

  @override
  bool shouldRepaint(covariant _LyricsGlyphPainter old) => old.color != color;
}

/// A bulleted list: three dots, three lines.
class _QueueGlyph extends StatelessWidget {
  const _QueueGlyph({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _QueueGlyphPainter(color));
}

class _QueueGlyphPainter extends CustomPainter {
  _QueueGlyphPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final line = Paint()
      ..color = color
      ..strokeWidth = 2 * s
      ..strokeCap = StrokeCap.round;
    final dot = Paint()..color = color;
    for (final y in [6.0, 12.0, 18.0]) {
      canvas.drawCircle(Offset(3.6 * s, y * s), 1.35 * s, dot);
      canvas.drawLine(Offset(8 * s, y * s), Offset(21 * s, y * s), line);
    }
  }

  @override
  bool shouldRepaint(covariant _QueueGlyphPainter old) => old.color != color;
}
