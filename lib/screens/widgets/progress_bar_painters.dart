import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The planned Automix window on a progress bar: a band whose ends dissolve on
/// a smoothstep (BitChord's feathered window).
@immutable
class AutomixWindowBand {
  const AutomixWindowBand({
    required this.start,
    required this.end,
    required this.alpha,
    required this.color,
  });

  /// Where the window runs, as 0..1 fractions of the bar.
  final double start;
  final double end;

  /// 0..1: the window's fade.
  final double alpha;
  final Color color;

  // BitChord: feather = 40% of the window, kept between 6 and 40 dp and never
  // more than half the span.
  static double _feather(double span) =>
      (span * 0.4).clamp(6.0, 40.0).clamp(0.0, span / 2);

  static double _smoothstep(double t) => t * t * (3 - 2 * t);

  /// Paints the band over [track].
  void paint(Canvas canvas, Rect track) {
    final from = track.left + track.width * start.clamp(0.0, 1.0);
    final to = track.left + track.width * end.clamp(0.0, 1.0);
    final span = to - from;
    if (span <= 0 || alpha <= 0) return;

    // Six smoothstep stops per end.
    final f = _feather(span) / span;
    final full = color.a * alpha;
    final colors = <Color>[];
    final stops = <double>[];
    for (var s = 0; s <= 6; s++) {
      final t = s / 6;
      colors.add(color.withValues(alpha: full * _smoothstep(t)));
      stops.add(f * t);
    }
    for (var s = 6; s >= 0; s--) {
      final t = s / 6;
      colors.add(color.withValues(alpha: full * _smoothstep(t)));
      stops.add(1 - f * t);
    }
    final band = Rect.fromLTRB(from, track.top, to, track.bottom);
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(track, Radius.circular(track.height / 2)),
    );
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          colors: colors,
          stops: stops,
        ).createShader(band),
    );
    canvas.restore();
  }

  /// 0..1: how strongly the band covers [x] on a bar [width] wide, for bars
  /// that have no continuous track to paint it over.
  double weightAt(double x, double width) {
    final from = width * start.clamp(0.0, 1.0);
    final to = width * end.clamp(0.0, 1.0);
    final span = to - from;
    final edge = math.min(x - from, to - x);
    if (span <= 0 || edge <= 0) return 0;
    return alpha * _smoothstep((edge / _feather(span)).clamp(0.0, 1.0));
  }

  @override
  bool operator ==(Object other) =>
      other is AutomixWindowBand &&
      other.start == start &&
      other.end == end &&
      other.alpha == alpha &&
      other.color == color;

  @override
  int get hashCode => Object.hash(start, end, alpha, color);
}

/// Custom painter for the animated wavy progress bar
class WavyProgressBarPainter extends CustomPainter {
  final double progress; // 0.0 to 1.0
  final double phase; // 0.0 to 2*pi
  final Color activeColor;
  final Color inactiveColor;
  final Color thumbColor;
  final double trackHeight;
  final double thumbRadius;
  final bool isSeeking;

  /// 0..1: the whole thumb's size, halo included. Shrinks away in a blend.
  final double thumbScale;

  /// The planned Automix window, if there is one.
  final AutomixWindowBand? window;

  WavyProgressBarPainter({
    required this.progress,
    required this.phase,
    required this.activeColor,
    required this.inactiveColor,
    required this.thumbColor,
    required this.trackHeight,
    required this.thumbRadius,
    required this.isSeeking,
    this.thumbScale = 1,
    this.window,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final progressWidth = (size.width * progress).clamp(0.0, size.width);
    const wavelength = 48.0;
    final baseAmplitude = (trackHeight * 1.25).clamp(3.0, 5.5);
    final effectiveAmplitude =
        baseAmplitude * (progressWidth / 32.0).clamp(0.0, 1.0);

    // 1. Draw inactive line from progress to total width
    if (progressWidth < size.width) {
      final inactivePaint = Paint()
        ..color = inactiveColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = trackHeight
        ..strokeCap = StrokeCap.round;

      final inactivePath = Path();
      inactivePath.moveTo(progressWidth, midY);
      inactivePath.lineTo(size.width, midY);
      canvas.drawPath(inactivePath, inactivePaint);

      // Only over the flat, unplayed line: behind the wave it would show as a
      // stray bar wherever the wave swings away from the middle.
      if (window != null) {
        canvas.save();
        canvas.clipRect(
          Rect.fromLTRB(progressWidth, 0, size.width, size.height),
        );
        window!.paint(
          canvas,
          Rect.fromLTRB(
            0,
            midY - trackHeight / 2,
            size.width,
            midY + trackHeight / 2,
          ),
        );
        canvas.restore();
      }
    }

    // 2. Draw active wavy path from 0 to progressWidth
    if (progressWidth > 0) {
      final activePaint = Paint()
        ..color = activeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = trackHeight
        ..strokeCap = StrokeCap.round;

      final activePath = Path();
      activePath.moveTo(0, midY);

      final steps = (progressWidth / 2.0).ceil().clamp(2, 400);
      for (int i = 1; i <= steps; i++) {
        final x = (i / steps) * progressWidth;
        final distanceFromStart = x;
        final distanceFromThumb = progressWidth - x;
        final startDamp = (distanceFromStart / 24.0).clamp(0.0, 1.0);
        final endDamp = (distanceFromThumb / 24.0).clamp(0.0, 1.0);
        final damp = startDamp * endDamp;
        final y =
            midY +
            math.sin((x / wavelength) * 2 * math.pi + phase) *
                effectiveAmplitude *
                damp;
        activePath.lineTo(x, y);
      }

      canvas.drawPath(activePath, activePaint);
    }

    // 3. Draw rolling soft-rounded square thumb at progressWidth
    if (thumbScale <= 0) return;
    final side = (isSeeking ? thumbRadius * 1.35 : thumbRadius) * 2.1;
    final cornerRadius = Radius.circular(side * 0.28);
    final rollAngle = isSeeking
        ? (progressWidth / (side * 3.5)) * math.pi
        : (phase * 0.75);

    canvas.save();
    canvas.translate(progressWidth, midY);
    canvas.rotate(rollAngle);
    canvas.scale(thumbScale);

    // Dynamic accent glow/halo (subtle ambient aura while playing, expanded when seeking)
    final haloSide = side + (isSeeking ? 10.0 : 4.0);
    final haloRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: haloSide, height: haloSide),
      Radius.circular(haloSide * 0.28),
    );
    final haloPaint = Paint()
      ..color = activeColor.withValues(alpha: isSeeking ? 0.35 : 0.16)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(haloRect, haloPaint);

    // Crisp white square scrubber body
    final thumbRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: side, height: side),
      cornerRadius,
    );
    final thumbPaint = Paint()
      ..color = thumbColor
      ..style = PaintingStyle.fill;
    canvas.drawRRect(thumbRect, thumbPaint);

    // Dynamic accent border
    final borderPaint = Paint()
      ..color = activeColor.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawRRect(thumbRect, borderPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(WavyProgressBarPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.phase != phase ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.thumbColor != thumbColor ||
        oldDelegate.trackHeight != trackHeight ||
        oldDelegate.thumbRadius != thumbRadius ||
        oldDelegate.isSeeking != isSeeking ||
        oldDelegate.thumbScale != thumbScale ||
        oldDelegate.window != window;
  }
}

/// Custom painter for the Spectrum vertical amplitude bars scrubber with zoom seek
class SpectrumBarPainter extends CustomPainter {
  final double progress;
  final List<double> amplitudes;
  final Color activeColor;
  final Color inactiveColor;
  final Color thumbColor;
  final double seekScale;
  final bool isSeeking;

  /// The planned Automix window, if there is one.
  final AutomixWindowBand? window;

  SpectrumBarPainter({
    required this.progress,
    required this.amplitudes,
    required this.activeColor,
    required this.inactiveColor,
    required this.thumbColor,
    required this.seekScale,
    required this.isSeeking,
    this.window,
  });

  /// Generates a high-sensitivity, dynamic audio spectrum profile customized per track
  static List<double> generateAmplitudes(int count, int seed) {
    final rand = math.Random(seed);
    final list = <double>[];
    double prev = 0.25;

    for (int i = 0; i < count; i++) {
      final t = (count > 1) ? i / (count - 1) : 0.5;

      // Sectional dynamics: intro, verse, chorus/drop, bridge, climax, outro
      final double sectionCurve;
      if (t < 0.12) {
        sectionCurve = 0.05 + 0.38 * (t / 0.12);
      } else if (t < 0.35) {
        sectionCurve = 0.40 + 0.32 * math.sin((t - 0.12) / 0.23 * math.pi);
      } else if (t < 0.55) {
        sectionCurve = 0.68 + 0.32 * math.sin((t - 0.35) / 0.20 * math.pi);
      } else if (t < 0.70) {
        sectionCurve = 0.18 + 0.30 * math.sin((t - 0.55) / 0.15 * math.pi);
      } else if (t < 0.90) {
        sectionCurve = 0.72 + 0.28 * math.sin((t - 0.70) / 0.20 * math.pi);
      } else {
        sectionCurve = (1.0 - (t - 0.90) / 0.10).clamp(0.02, 0.70);
      }

      // Multi-frequency harmonic spectrum waves
      final wave1 = math.sin(i * 0.38 + seed) * 0.28;
      final wave2 = math.cos(i * 0.95 + seed * 2) * 0.20;
      final wave3 = math.sin(i * 1.85 + seed * 3) * 0.15;

      // Rhythmic beat pulses (kick transients every ~4 bars)
      final isBeat = (i % 4 == 0) ? 0.28 : ((i % 2 == 0) ? 0.12 : -0.08);

      // Micro-variation noise for fine-grained spectrum detail
      final noise = (rand.nextDouble() - 0.5) * 0.35;

      // Target amplitude with wide dynamic range
      final target = (sectionCurve + wave1 + wave2 + wave3 + isBeat + noise)
          .clamp(0.04, 1.0);

      // Low damping (0.24 prev, 0.76 target) preserves crisp sensitivity to peaks and drops
      prev = (prev * 0.24 + target * 0.76).clamp(0.04, 1.0);
      list.add(prev);
    }
    return list;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (amplitudes.isEmpty || size.width <= 0 || size.height <= 0) return;

    final totalBars = amplitudes.length;
    final step = size.width / totalBars;
    // Slender, modern thin bars matching mockup
    final baseBarWidth = (step * 0.46).clamp(1.5, 2.4);
    final midY = size.height / 2;
    final cursorX = (progress * size.width).clamp(0.0, size.width);

    // Smoothly scale maximum bar height from resting (62% of container) to seeking (92% of container)
    final restMaxHeight = size.height * 0.62;
    final seekMaxHeight = size.height * 0.92;
    final currentMaxHeight =
        restMaxHeight + (seekMaxHeight - restMaxHeight) * seekScale;

    // Zoom window parameters during seek
    final zoomRadius = size.width * 0.16;

    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;

    final inactivePaint = Paint()
      ..color = inactiveColor
      ..style = PaintingStyle.fill;

    for (int i = 0; i < totalBars; i++) {
      final x = i * step + step / 2;
      final barFraction = (i + 0.5) / totalBars;
      final isActive = barFraction <= progress;

      // Localized magnification zoom around seek cursor
      final dist = (x - cursorX).abs();
      final double zoomFactor;
      if (seekScale > 0.0 && dist < zoomRadius) {
        zoomFactor = math.cos((dist / zoomRadius) * (math.pi / 2)) * seekScale;
      } else {
        zoomFactor = 0.0;
      }

      final amp = amplitudes[i];
      final currentBarWidth = (baseBarWidth * (1.0 + zoomFactor * 0.45)).clamp(
        1.5,
        3.2,
      );
      final rawHeight = amp * (1.0 + zoomFactor * 0.30) * currentMaxHeight;
      // When rawHeight is small, barHeight equals currentBarWidth -> becomes a perfect circular dot
      final barHeight = rawHeight < currentBarWidth
          ? currentBarWidth
          : rawHeight.clamp(currentBarWidth, size.height);
      final top = midY - barHeight / 2;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x - currentBarWidth / 2, top, currentBarWidth, barHeight),
        Radius.circular(currentBarWidth / 2),
      );
      canvas.drawRRect(rect, isActive ? activePaint : inactivePaint);

      // There's no track to lay the Automix window on, so it tints the
      // unplayed bars it covers instead.
      final band = window;
      if (band != null && !isActive) {
        final weight = band.weightAt(x, size.width);
        if (weight > 0) {
          canvas.drawRRect(
            rect,
            Paint()
              ..color = band.color.withValues(alpha: band.color.a * weight),
          );
        }
      }
    }

    // Draw animated seek playhead needle & glowing indicator when seeking
    if (seekScale > 0.0) {
      // 1. Luminous halo around cursor
      final haloWidth = 12.0 + 6.0 * seekScale;
      final haloPaint = Paint()
        ..color = activeColor.withValues(
          alpha: (0.35 * seekScale).clamp(0.0, 1.0),
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cursorX, midY),
            width: haloWidth,
            height: currentMaxHeight + 4.0,
          ),
          Radius.circular(haloWidth / 2),
        ),
        haloPaint,
      );

      // 2. Crisp refined needle playhead line
      final needleWidth = 2.2;
      final needleHeight = currentMaxHeight + 6.0;
      final needleRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cursorX, midY),
          width: needleWidth,
          height: needleHeight,
        ),
        const Radius.circular(1.1),
      );

      final needlePaint = Paint()
        ..color = thumbColor.withValues(
          alpha: (0.95 * seekScale).clamp(0.0, 1.0),
        )
        ..style = PaintingStyle.fill;
      canvas.drawRRect(needleRect, needlePaint);

      // 3. Top and bottom accent indicator diamonds
      final diamondSize = 5.0 * seekScale;
      final diamondPaint = Paint()
        ..color = activeColor
        ..style = PaintingStyle.fill;

      void drawDiamond(Offset center) {
        final path = Path()
          ..moveTo(center.dx, center.dy - diamondSize / 2)
          ..lineTo(center.dx + diamondSize / 2, center.dy)
          ..lineTo(center.dx, center.dy + diamondSize / 2)
          ..lineTo(center.dx - diamondSize / 2, center.dy)
          ..close();
        canvas.drawPath(path, diamondPaint);
      }

      drawDiamond(Offset(cursorX, midY - needleHeight / 2));
      drawDiamond(Offset(cursorX, midY + needleHeight / 2));
    }
  }

  @override
  bool shouldRepaint(SpectrumBarPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.amplitudes != amplitudes ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.thumbColor != thumbColor ||
        oldDelegate.seekScale != seekScale ||
        oldDelegate.isSeeking != isSeeking ||
        oldDelegate.window != window;
  }
}

/// The Default style drawn the way the slider looks at rest: a rounded track
/// and a round thumb. For places that show progress without seeking.
class LinearProgressBarPainter extends CustomPainter {
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final double trackHeight;
  final double thumbRadius;

  LinearProgressBarPainter({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.trackHeight,
    required this.thumbRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final x = (size.width * progress).clamp(0.0, size.width);
    final radius = Radius.circular(trackHeight / 2);
    final top = midY - trackHeight / 2;
    canvas.drawRRect(
      RRect.fromLTRBR(0, top, size.width, top + trackHeight, radius),
      Paint()..color = inactiveColor,
    );
    final active = Paint()..color = activeColor;
    canvas.drawRRect(
      RRect.fromLTRBR(0, top, x, top + trackHeight, radius),
      active,
    );
    canvas.drawCircle(
      Offset(x.clamp(thumbRadius, size.width - thumbRadius), midY),
      thumbRadius,
      active,
    );
  }

  @override
  bool shouldRepaint(LinearProgressBarPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.inactiveColor != inactiveColor ||
      oldDelegate.trackHeight != trackHeight ||
      oldDelegate.thumbRadius != thumbRadius;
}

/// A streak of light: the fill brightens along its last stretch to its tip,
/// and while the song plays a ray fans outward behind that tip like a comet's
/// tail. There's no thumb or dot; the end of the streak is the marker.
class CometProgressBarPainter extends CustomPainter {
  final double progress; // 0.0 to 1.0
  final Color activeColor;
  final Color inactiveColor;

  /// The bright end of the streak.
  final Color headColor;
  final double trackHeight;

  /// How far the ray reaches behind the tip, in logical pixels.
  final double tailLength;

  /// 0..1: how visible the ray is. Zero while paused.
  final double rayOpacity;

  /// 0..1: how lit up the ray is, for a slow breath while playing and a
  /// brighter one under the finger.
  final double intensity;

  /// The planned Automix window, if there is one.
  final AutomixWindowBand? window;

  CometProgressBarPainter({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.headColor,
    required this.trackHeight,
    this.tailLength = 110,
    this.rayOpacity = 1,
    this.intensity = 0.5,
    this.window,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final radius = Radius.circular(trackHeight / 2);
    final top = midY - trackHeight / 2;
    final bottom = midY + trackHeight / 2;
    final headX = (size.width * progress).clamp(0.0, size.width);

    canvas.drawRRect(
      RRect.fromLTRBR(0, top, size.width, bottom, radius),
      Paint()..color = inactiveColor,
    );
    window?.paint(canvas, Rect.fromLTRB(0, top, size.width, bottom));
    if (headX <= 0) return;

    final tail = math.min(tailLength, headX);
    final tailStart = Offset(headX - tail, midY);
    final head = Offset(headX, midY);

    final opacity = rayOpacity.clamp(0.0, 1.0);
    if (opacity > 0) {
      // Dark text on a light screen means a dark tip, and a dark ray would
      // read as a smudge, so the ray keeps the accent there.
      final glow = headColor.computeLuminance() > 0.5 ? headColor : activeColor;
      final strength = intensity.clamp(0.0, 1.0);
      // A wedge: a point at the tip, spreading outward as it goes back, and
      // fading away before it ends.
      final spread = tail * (0.15 + 0.05 * strength);
      final ray = Path()
        ..moveTo(headX, midY)
        ..lineTo(headX - tail, midY - spread)
        ..lineTo(headX - tail, midY + spread)
        ..close();
      // The blur leaves a faint vertical line a few pixels behind the wedge,
      // past where it has already faded to nothing, so that strip is cut off.
      canvas.save();
      canvas.clipRect(
        Rect.fromLTRB(
          tailStart.dx,
          midY - spread - 16,
          headX + 16,
          midY + spread + 16,
        ),
      );
      canvas.drawPath(
        ray,
        Paint()
          ..shader = ui.Gradient.linear(
            tailStart,
            head,
            [
              glow.withValues(alpha: 0),
              glow.withValues(alpha: (0.04 + 0.03 * strength) * opacity),
              glow.withValues(alpha: (0.18 + 0.1 * strength) * opacity),
              glow.withValues(alpha: (0.38 + 0.2 * strength) * opacity),
              glow.withValues(alpha: (0.6 + 0.25 * strength) * opacity),
            ],
            const [0, 0.25, 0.5, 0.75, 1],
          )
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.restore();
    }

    // The bar itself, brightening along the tail to its end.
    canvas.drawRRect(
      RRect.fromLTRBR(0, top, headX, bottom, radius),
      Paint()
        ..shader = ui.Gradient.linear(
          tailStart,
          head,
          [activeColor, Color.lerp(activeColor, headColor, 0.55)!, headColor],
          const [0, 0.65, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(CometProgressBarPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.inactiveColor != inactiveColor ||
      oldDelegate.headColor != headColor ||
      oldDelegate.trackHeight != trackHeight ||
      oldDelegate.tailLength != tailLength ||
      oldDelegate.rayOpacity != rayOpacity ||
      oldDelegate.intensity != intensity ||
      oldDelegate.window != window;
}
