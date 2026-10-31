import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';

/// Ambient glow that follows the animated (video) album art — the same
/// technique as Nivio's player ambient mode.
///
/// It never runs a second video or blurs the live video full-screen. A few
/// times a second it renders the canvas video's layer (the [RepaintBoundary]
/// keyed [captureKey]) at ~48px on the GPU, reads those pixels back, softens
/// them with a tiny box blur and crossfades to the result. Drawn at screen
/// size, a sample that small is already a soft glow.
///
/// Until a frame has been captured (no canvas for this song, or the video
/// hasn't drawn yet) [fallback] — a still of the cover — is shown instead.
class CanvasAmbientGlow extends ConsumerStatefulWidget {
  const CanvasAmbientGlow({
    super.key,
    required this.captureKey,
    required this.fallback,
  });

  /// Key of the [RepaintBoundary] wrapping the canvas video.
  final GlobalKey captureKey;

  final Widget fallback;

  @override
  ConsumerState<CanvasAmbientGlow> createState() => _CanvasAmbientGlowState();
}

class _CanvasAmbientGlowState extends ConsumerState<CanvasAmbientGlow>
    with SingleTickerProviderStateMixin {
  // 1.5x Nivio's 48px with its blur: a little crisper than Nivio's glow.
  static const int _sampleWidth = 72;
  static const Duration _captureInterval = Duration(milliseconds: 350);
  static const Duration _idleInterval = Duration(milliseconds: 1000);

  /// Mean per-channel difference below which a new sample is ignored.
  static const double _changeThreshold = 2.0;

  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  Timer? _timer;
  bool _busy = false;
  bool _disposed = false;

  ui.Image? _previous;
  ui.Image? _current;
  Color _accentFrom = const Color(0xFF000000);
  Color _accentTo = const Color(0xFF000000);
  Uint8List? _lastSample;

  @override
  void initState() {
    super.initState();
    // First sample soon after the video's first frame.
    _schedule(const Duration(milliseconds: 600));
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _fade.dispose();
    _previous?.dispose();
    _current?.dispose();
    super.dispose();
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    if (_disposed) return;
    _timer = Timer(delay, _tick);
  }

  Future<void> _tick() async {
    if (_disposed || !mounted) return;
    final playing = ref.read(isPlayingProvider);
    final visible =
        SchedulerBinding.instance.lifecycleState == AppLifecycleState.resumed &&
        TickerMode.valuesOf(context).enabled;
    // While paused, keep the last glow and only sample if there is none yet.
    if (visible && (playing || _current == null)) {
      await _capture();
    }
    if (_disposed) return;
    _schedule(playing ? _captureInterval : _idleInterval);
  }

  Future<void> _capture() async {
    if (_busy) return;
    _busy = true;
    try {
      final sample = await _sampleFromLayer();
      if (_disposed || sample == null) return;
      await _apply(sample);
    } catch (e) {
      if (kDebugMode) debugPrint('CanvasAmbientGlow: capture failed: $e');
    } finally {
      _busy = false;
    }
  }

  /// Renders the canvas layer at a tiny size (GPU side) and reads it back.
  /// Null when there's nothing captured yet (no canvas, or still transparent).
  Future<_Sample?> _sampleFromLayer() async {
    await SchedulerBinding.instance.endOfFrame;
    final ro = widget.captureKey.currentContext?.findRenderObject();
    if (_disposed || ro is! RenderRepaintBoundary || !ro.hasSize) return null;
    if (ro.size.width < 1 || ro.size.height < 1) return null;
    if (kDebugMode && ro.debugNeedsPaint) return null;

    final image = await ro.toImage(pixelRatio: _sampleWidth / ro.size.width);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final w = image.width;
    final h = image.height;
    image.dispose();
    if (data == null || w == 0 || h == 0) return null;

    final src = data.buffer.asUint8List();
    final out = Uint8List(w * h * 4);
    var opaque = 0;
    for (var i = 0; i < w * h * 4; i += 4) {
      out[i] = src[i];
      out[i + 1] = src[i + 1];
      out[i + 2] = src[i + 2];
      out[i + 3] = 255;
      if (src[i + 3] > 8) opaque++;
    }
    // An uncaptured texture comes back transparent (a dark frame is opaque).
    if (opaque < (w * h) ~/ 4) return null;
    return _Sample(out, w, h);
  }

  Future<void> _apply(_Sample sample) async {
    final last = _lastSample;
    if (last != null && last.length == sample.rgba.length) {
      var diff = 0;
      for (var i = 0; i < last.length; i++) {
        diff += (last[i] - sample.rgba[i]).abs();
      }
      if (diff / last.length < _changeThreshold) return;
    }
    _lastSample = sample.rgba;

    final blurred = _boxBlur(sample.rgba, sample.width, sample.height, 2);
    final accent = _saturatedAccent(blurred);
    final image = await _decode(blurred, sample.width, sample.height);
    if (_disposed || !mounted) {
      image.dispose();
      return;
    }

    final t = _fade.value;
    setState(() {
      _accentFrom = Color.lerp(_accentFrom, _accentTo, t)!;
      _accentTo = accent;
      _previous?.dispose();
      _previous = _current;
      _current = image;
    });
    _fade.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final hasGlow = _current != null;
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedOpacity(
          opacity: hasGlow ? 0 : 1,
          duration: const Duration(milliseconds: 450),
          child: widget.fallback,
        ),
        if (hasGlow)
          IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _fade,
                builder: (context, _) => CustomPaint(
                  size: Size.infinite,
                  painter: _GlowPainter(
                    previous: _previous,
                    current: _current,
                    t: Curves.easeInOut.transform(_fade.value),
                    accent: Color.lerp(_accentFrom, _accentTo, _fade.value)!,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Sample {
  const _Sample(this.rgba, this.width, this.height);
  final Uint8List rgba;
  final int width;
  final int height;
}

/// Separable box blur (two passes) on a tiny RGBA buffer, so the upscaled
/// sample reads as a soft glow rather than blocks.
Uint8List _boxBlur(Uint8List src, int w, int h, int radius) {
  var a = Uint8List.fromList(src);
  var b = Uint8List(src.length);
  for (var pass = 0; pass < 2; pass++) {
    for (var horizontal = 0; horizontal < 2; horizontal++) {
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          var r = 0, g = 0, bl = 0, n = 0;
          for (var k = -radius; k <= radius; k++) {
            final sx = horizontal == 0 ? (x + k).clamp(0, w - 1) : x;
            final sy = horizontal == 0 ? y : (y + k).clamp(0, h - 1);
            final i = (sy * w + sx) * 4;
            r += a[i];
            g += a[i + 1];
            bl += a[i + 2];
            n++;
          }
          final o = (y * w + x) * 4;
          b[o] = r ~/ n;
          b[o + 1] = g ~/ n;
          b[o + 2] = bl ~/ n;
          b[o + 3] = 255;
        }
      }
      final tmp = a;
      a = b;
      b = tmp;
    }
  }
  return a;
}

/// Average of the most saturated tenth of the pixels, so a strong colour in
/// part of the frame still tints the glow.
Color _saturatedAccent(Uint8List rgba) {
  final count = rgba.length ~/ 4;
  final saturations = List<double>.filled(count, 0);
  for (var i = 0; i < count; i++) {
    final r = rgba[i * 4], g = rgba[i * 4 + 1], b = rgba[i * 4 + 2];
    final maxC = math.max(r, math.max(g, b));
    final minC = math.min(r, math.min(g, b));
    saturations[i] = maxC == 0 ? 0 : (maxC - minC) / maxC * (maxC / 255.0);
  }
  final sorted = List<double>.of(saturations)..sort();
  final cutoff = sorted[(count * 0.9).floor().clamp(0, count - 1)];
  var ar = 0, ag = 0, ab = 0, n = 0;
  for (var i = 0; i < count; i++) {
    if (saturations[i] < cutoff) continue;
    ar += rgba[i * 4];
    ag += rgba[i * 4 + 1];
    ab += rgba[i * 4 + 2];
    n++;
  }
  if (n == 0) return const Color(0xFF000000);
  return Color.fromARGB(255, ar ~/ n, ag ~/ n, ab ~/ n);
}

Future<ui.Image> _decode(Uint8List rgba, int w, int h) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    w,
    h,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

class _GlowPainter extends CustomPainter {
  _GlowPainter({
    required this.previous,
    required this.current,
    required this.t,
    required this.accent,
  });

  final ui.Image? previous;
  final ui.Image? current;
  final double t;
  final Color accent;

  static const double _accentAlpha = 0.18;

  @override
  void paint(Canvas canvas, Size size) {
    final image = current;
    if (image == null) return;
    final full = Offset.zero & size;

    final hasPrevious = previous != null && t < 1;
    if (hasPrevious) _drawCover(canvas, previous!, size, _paint(1));
    _drawCover(canvas, image, size, _paint(hasPrevious ? t : 1));
    canvas.drawRect(full, Paint()..color = accent.withValues(alpha: _accentAlpha));
  }

  static Paint _paint(double opacity) => Paint()
    ..filterQuality = FilterQuality.medium
    ..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0));

  /// Draws [image] covering [size] (cropped to keep its aspect ratio).
  void _drawCover(Canvas canvas, ui.Image image, Size size, Paint paint) {
    final src = Size(image.width.toDouble(), image.height.toDouble());
    final fitted = applyBoxFit(BoxFit.cover, src, size);
    final srcRect = Alignment.center.inscribe(fitted.source, Offset.zero & src);
    canvas.drawImageRect(image, srcRect, Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _GlowPainter old) =>
      old.previous != previous ||
      old.current != current ||
      old.t != t ||
      old.accent != accent;
}
