import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import 'signal_path_sheet.dart';

/// "Lossless" / "Hi-Res Lossless" under the progress bar, shown only while
/// a lossless stream plays, whatever the stats-for-nerds setting — and
/// "Upgrading" in its place while the song is being moved onto its lossless
/// copy mid-play. Tapping it opens the signal path.
class LosslessBadge extends ConsumerWidget {
  const LosslessBadge({super.key, required this.color, this.fontSize = 11});

  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tier = ref.watch(
      currentPlaybackDataProvider.select((d) => d?.format.losslessTier),
    );
    final upgrading =
        tier == null && (ref.watch(losslessUpgradingProvider).valueOrNull ?? false);
    final glyphSize = fontSize + 2;
    final Widget? glyph = tier != null
        ? _LosslessGlyph(color: color, size: glyphSize)
        : upgrading
        ? _UpgradingGlyph(color: color, size: glyphSize)
        : null;
    final label = tier ?? (upgrading ? 'Upgrading' : null);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: label == null || glyph == null
          ? const SizedBox.shrink()
          : GestureDetector(
              key: ValueKey(label),
              behavior: HitTestBehavior.opaque,
              onTap: () => SignalPathSheet.show(
                context,
                accentColor: ref.read(playerAlbumColorsProvider).accent,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    glyph,
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// An arrow that keeps rising out of a baseline: the stream moving up to
/// its lossless copy.
class _UpgradingGlyph extends StatefulWidget {
  const _UpgradingGlyph({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  State<_UpgradingGlyph> createState() => _UpgradingGlyphState();
}

class _UpgradingGlyphState extends State<_UpgradingGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rise = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _rise.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.size,
    height: widget.size,
    child: RepaintBoundary(
      child: CustomPaint(painter: _UpgradingPainter(widget.color, _rise)),
    ),
  );
}

class _UpgradingPainter extends CustomPainter {
  _UpgradingPainter(this.color, this.rise) : super(repaint: rise);
  final Color color;
  final Animation<double> rise;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = w * 0.14;
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // The baseline stays put.
    final base = h * 0.9;
    canvas.drawLine(Offset(w * 0.2, base), Offset(w * 0.8, base), paint);

    // The arrow travels up from the baseline and fades as it leaves the
    // top, while the next one follows it in.
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, w, base - stroke));
    final t = Curves.easeInOut.transform(rise.value);
    for (final lap in const [0.0, 1.0]) {
      final dy = h * 0.75 * (lap - t);
      final alpha = (1 - (t - lap).abs()).clamp(0.0, 1.0);
      final arrow = Paint()
        ..color = color.withValues(alpha: color.a * alpha)
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final tipY = h * 0.12 + dy;
      final cx = w * 0.5;
      canvas.drawLine(Offset(cx, tipY), Offset(cx, tipY + h * 0.62), arrow);
      canvas.drawPath(
        Path()
          ..moveTo(cx - w * 0.26, tipY + h * 0.26)
          ..lineTo(cx, tipY)
          ..lineTo(cx + w * 0.26, tipY + h * 0.26),
        arrow,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _UpgradingPainter old) => old.color != color;
}

/// A small waveform mark: three bars, taller in the middle, that bounce out
/// of step like a level meter while music plays and settle back to the
/// still mark when paused.
class _LosslessGlyph extends ConsumerStatefulWidget {
  const _LosslessGlyph({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  ConsumerState<_LosslessGlyph> createState() => _LosslessGlyphState();
}

class _LosslessGlyphState extends ConsumerState<_LosslessGlyph>
    with TickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  /// 0 = the still mark, 1 = fully animated; eases between them.
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );

  @override
  void initState() {
    super.initState();
    _motion.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) _clock.stop();
    });
  }

  @override
  void dispose() {
    _clock.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playing = ref.watch(isPlayingProvider);
    if (playing) {
      if (!_clock.isAnimating) _clock.repeat();
      _motion.forward();
    } else {
      _motion.reverse();
    }
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _GlyphPainter(widget.color, _clock, _motion),
        ),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.color, this.clock, this.motion)
    : super(repaint: Listenable.merge([clock, motion]));
  final Color color;
  final Animation<double> clock;
  final Animation<double> motion;

  /// Each bar: x position, resting length, and its own phase and speed, so
  /// the three never move together.
  static const _bars = [
    (x: 0.2, rest: 0.45, phase: 0.0, speed: 2.0),
    (x: 0.5, rest: 0.8, phase: 0.35, speed: 3.0),
    (x: 0.8, rest: 0.45, phase: 0.7, speed: 2.5),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.14
      ..strokeCap = StrokeCap.round;
    final h = size.height;
    final m = Curves.easeInOut.transform(motion.value);
    final t = clock.value;
    for (final bar in _bars) {
      // A bouncing length between 25% and 95% of the glyph's height.
      final wave = 0.5 + 0.5 * math.sin(2 * math.pi * (t * bar.speed + bar.phase));
      final moving = 0.25 + 0.7 * wave;
      final len = bar.rest + (moving - bar.rest) * m;
      final dx = size.width * bar.x;
      canvas.drawLine(
        Offset(dx, h * (0.5 - len / 2)),
        Offset(dx, h * (0.5 + len / 2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter old) => old.color != color;
}
