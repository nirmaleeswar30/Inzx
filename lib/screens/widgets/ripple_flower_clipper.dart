import 'dart:math';
import 'package:material_ui/material_ui.dart';

/// Custom clipper that produces an 8-petal harmonic wavy 'Ripple' shape.
/// Perfectly matches the organic wavy aesthetic with 8 smooth lobes and valleys.
class RippleFlowerClipper extends CustomClipper<Path> {
  final double waveAmplitudeRatio;
  final int lobes;
  final double inset;

  const RippleFlowerClipper({
    this.waveAmplitudeRatio = 0.065,
    this.lobes = 8,
    this.inset = 0.0,
  });

  /// Generate the mathematical harmonic path for a given size and inset
  static Path buildPath(
    Size size, {
    double waveAmplitudeRatio = 0.065,
    int lobes = 8,
    double inset = 0.0,
  }) {
    final path = Path();
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = (min(size.width, size.height) / 2) - inset;
    if (maxRadius <= 0) return path;

    final baseRadius = maxRadius / (1 + waveAmplitudeRatio);
    final amplitude = baseRadius * waveAmplitudeRatio;

    // 720 steps produces a silky-smooth anti-aliased contour on all high-DPI devices
    const int steps = 720;
    for (int i = 0; i <= steps; i++) {
      final theta = (i / steps) * 2 * pi;
      // Point / peak at 12 o'clock (-pi/2) and 6 o'clock
      final r = baseRadius + amplitude * cos(lobes * theta);
      final angle = theta - (pi / 2);
      final x = center.dx + r * cos(angle);
      final y = center.dy + r * sin(angle);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  Path getClip(Size size) {
    return buildPath(
      size,
      waveAmplitudeRatio: waveAmplitudeRatio,
      lobes: lobes,
      inset: inset,
    );
  }

  @override
  bool shouldReclip(RippleFlowerClipper oldClipper) =>
      oldClipper.waveAmplitudeRatio != waveAmplitudeRatio ||
      oldClipper.lobes != lobes ||
      oldClipper.inset != inset;
}

/// Painter that draws a subtle outline and ambient shadow around the Ripple flower
class RippleFlowerBorderPainter extends CustomPainter {
  final Color borderColor;
  final double strokeWidth;
  final double waveAmplitudeRatio;
  final int lobes;
  final double inset;

  RippleFlowerBorderPainter({
    required this.borderColor,
    this.strokeWidth = 1.5,
    this.waveAmplitudeRatio = 0.065,
    this.lobes = 8,
    this.inset = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = RippleFlowerClipper.buildPath(
      size,
      waveAmplitudeRatio: waveAmplitudeRatio,
      lobes: lobes,
      inset: inset,
    );

    // Subtle hairline stroke outline
    final strokePaint =
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;

    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(RippleFlowerBorderPainter oldDelegate) =>
      oldDelegate.borderColor != borderColor ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.waveAmplitudeRatio != waveAmplitudeRatio ||
      oldDelegate.lobes != lobes ||
      oldDelegate.inset != inset;
}
