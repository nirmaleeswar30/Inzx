import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import 'signal_path_sheet.dart';

/// "Lossless" / "Hi-Res Lossless" under the progress bar, shown only while
/// a lossless stream plays, whatever the stats-for-nerds setting. Tapping
/// it opens the signal path.
class LosslessBadge extends ConsumerWidget {
  const LosslessBadge({super.key, required this.color, this.fontSize = 11});

  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tier = ref.watch(
      currentPlaybackDataProvider.select((d) => d?.format.losslessTier),
    );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: tier == null
          ? const SizedBox.shrink()
          : GestureDetector(
              key: ValueKey(tier),
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
                    _LosslessGlyph(color: color, size: fontSize + 2),
                    const SizedBox(width: 4),
                    Text(
                      tier,
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
