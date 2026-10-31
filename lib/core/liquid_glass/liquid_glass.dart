import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'glass_shaders.dart';
import 'glass_style.dart';

/// A liquid glass surface: refracts, blurs and tints whatever is painted
/// behind it, then draws its [child] on top with a rim highlight and a
/// drop shadow.
///
/// This is the Flutter counterpart of Kyant0/backdrop's
/// `Modifier.drawBackdrop`. Everything runs on the GPU as part of the
/// normal frame: one backdrop read (shared between surfaces under a
/// [BackdropGroup]), Impeller's downsampling blur, and the lens shader,
/// which does real work only along the rim. Nothing is captured to an image
/// on the CPU and nothing animates unless a property changes.
///
/// The lens needs the surface's position in screen space. It is read at
/// paint time, and after every frame a surface with a lens checks that it
/// has not been carried somewhere else without repainting — by a route
/// transition or a scrolling list item, say — and repaints itself if it
/// has, which is what `onGloballyPositioned` does for the Kotlin version.
class LiquidGlass extends SingleChildRenderObjectWidget {
  const LiquidGlass({
    super.key,
    this.style = const GlassStyle(),
    this.borderRadius = pill,
    this.press = 0,
    this.touchPosition,
    this.shareBackdrop = true,
    super.child,
  });

  /// Radii large enough to round any surface into a capsule or circle.
  static const BorderRadius pill = BorderRadius.all(Radius.circular(10000));

  final GlassStyle style;
  final BorderRadius borderRadius;

  /// Press progress 0..1, for [GlassStyle.pressBlur] and friends.
  final double press;

  /// Where the finger is, in local coordinates, for the press glow.
  final Offset? touchPosition;

  /// Read the backdrop shared by the enclosing [BackdropGroup], if any.
  ///
  /// Sharing lets every surface in the group reuse one backdrop read, which
  /// is the cheap path. Glass stacked on other glass must opt out: a shared
  /// read is taken before the group's first surface, so it would not see
  /// the glass underneath.
  final bool shareBackdrop;

  @override
  RenderLiquidGlass createRenderObject(BuildContext context) {
    return RenderLiquidGlass(
      style: style,
      borderRadius: borderRadius,
      press: press,
      touchPosition: touchPosition,
      devicePixelRatio: _dpr(context),
      backdropKey: shareBackdrop ? BackdropGroup.of(context)?.backdropKey : null,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderLiquidGlass renderObject) {
    renderObject
      ..style = style
      ..borderRadius = borderRadius
      ..press = press
      ..touchPosition = touchPosition
      ..devicePixelRatio = _dpr(context)
      ..backdropKey =
          shareBackdrop ? BackdropGroup.of(context)?.backdropKey : null;
  }

  static double _dpr(BuildContext context) =>
      MediaQuery.maybeDevicePixelRatioOf(context) ??
      View.of(context).devicePixelRatio;
}

class RenderLiquidGlass extends RenderProxyBox {
  RenderLiquidGlass({
    required GlassStyle style,
    required BorderRadius borderRadius,
    double press = 0,
    Offset? touchPosition,
    required double devicePixelRatio,
    BackdropKey? backdropKey,
  })  : _style = style,
        _borderRadius = borderRadius,
        _press = press,
        _touchPosition = touchPosition,
        _dpr = devicePixelRatio,
        _backdropKey = backdropKey;

  GlassStyle _style;
  GlassStyle get style => _style;
  set style(GlassStyle value) {
    if (value == _style) return;
    _style = value;
    markNeedsPaint();
  }

  BorderRadius _borderRadius;
  set borderRadius(BorderRadius value) {
    if (value == _borderRadius) return;
    _borderRadius = value;
    markNeedsPaint();
  }

  double _press;
  set press(double value) {
    if (value == _press) return;
    _press = value;
    markNeedsPaint();
  }

  Offset? _touchPosition;
  set touchPosition(Offset? value) {
    if (value == _touchPosition) return;
    _touchPosition = value;
    if (_press > 0) markNeedsPaint();
  }

  double _dpr;
  set devicePixelRatio(double value) {
    if (value == _dpr) return;
    _dpr = value;
    markNeedsPaint();
  }

  BackdropKey? _backdropKey;
  set backdropKey(BackdropKey? value) {
    if (value == _backdropKey) return;
    _backdropKey = value;
    markNeedsPaint();
  }

  final LayerHandle<ClipRRectLayer> _clipLayer = LayerHandle<ClipRRectLayer>();
  final LayerHandle<BackdropFilterLayer> _backdropLayer =
      LayerHandle<BackdropFilterLayer>();

  ui.FragmentShader? _lensShader;
  ui.FragmentShader? _highlightShader;
  final Paint _paint = Paint();
  final Paint _shadowPaint = Paint();
  final Path _shadowPath = Path();

  @override
  bool get alwaysNeedsCompositing => true;

  /// Where the lens was last told the surface is.
  Rect? _lensRect;

  /// The lens rect last painted, in physical pixels; null without a lens.
  @visibleForTesting
  Rect? get debugLensRect => _lensRect;
  bool _positionCheckScheduled = false;

  void _schedulePositionCheck() {
    if (_positionCheckScheduled) return;
    _positionCheckScheduled = true;
    // Runs after a frame only when one happens: nothing at all while idle.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _positionCheckScheduled = false;
      if (!attached || _lensRect == null) return;
      if (_textureRect() != _lensRect) {
        markNeedsPaint();
      } else {
        _schedulePositionCheck();
      }
    });
  }

  @override
  void detach() {
    _lensRect = null;
    super.detach();
  }

  @override
  void dispose() {
    _clipLayer.layer = null;
    _backdropLayer.layer = null;
    _lensShader?.dispose();
    _highlightShader?.dispose();
    super.dispose();
  }

  /// Corner radii clamped to half the shorter side, clockwise from top-left.
  (double, double, double, double) _radii() {
    final max = size.shortestSide / 2;
    return (
      math.min(_borderRadius.topLeft.x, max),
      math.min(_borderRadius.topRight.x, max),
      math.min(_borderRadius.bottomRight.x, max),
      math.min(_borderRadius.bottomLeft.x, max),
    );
  }

  RRect _rrect(Offset offset) {
    final (tl, tr, br, bl) = _radii();
    return RRect.fromRectAndCorners(
      offset & size,
      topLeft: Radius.circular(tl),
      topRight: Radius.circular(tr),
      bottomRight: Radius.circular(br),
      bottomLeft: Radius.circular(bl),
    );
  }

  /// Android's blur radius → Gaussian sigma, in logical pixels.
  double _sigma(double radius) => radius * 0.57735 + 0.5 / _dpr;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty) return;

    final shadow = _style.shadow;
    if (shadow != null && shadow.alpha > 0 && shadow.color.a > 0) {
      _paintShadow(context.canvas, _rrect(offset), shadow);
    }

    _clipLayer.layer = context.pushClipRRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      _rrect(Offset.zero),
      _paintClipped,
      oldLayer: _clipLayer.layer,
    );
  }

  void _paintShadow(Canvas canvas, RRect rrect, GlassShadow shadow) {
    // Only outside the shape: the glass must not be darkened by its own
    // shadow (upstream clears the shape out of its shadow layer).
    final pad = shadow.radius * 2 + shadow.offset.distance;
    _shadowPath
      ..reset()
      // reset() also resets the fill type; the ring needs even-odd.
      ..fillType = PathFillType.evenOdd
      ..addRect(rrect.outerRect.inflate(pad))
      ..addRRect(rrect);
    _shadowPaint
      ..color = shadow.color.withValues(alpha: shadow.color.a * shadow.alpha)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, _sigma(shadow.radius));
    canvas
      ..save()
      ..clipPath(_shadowPath)
      ..drawRRect(rrect.shift(shadow.offset), _shadowPaint)
      ..restore();
  }

  void _paintClipped(PaintingContext context, Offset offset) {
    final filter = _buildFilter();
    if (filter == null) {
      _backdropLayer.layer = null;
      _paintSurface(context, offset);
      return;
    }
    final layer = _backdropLayer.layer ??= BackdropFilterLayer();
    layer
      ..filter = filter
      ..blendMode = BlendMode.srcOver
      ..backdropKey = _backdropKey;
    context.pushLayer(layer, _paintSurface, offset);
  }

  /// colour controls → blur → lens, composed innermost-first, in the order
  /// the Kotlin effect block chains its RenderEffects.
  ui.ImageFilter? _buildFilter() {
    final s = _style;
    ui.ImageFilter? filter;

    if (s.saturation != 1 || s.brightness != 0 || s.contrast != 1) {
      filter = ui.ColorFilter.matrix(
        _colorControls(s.brightness, s.contrast, s.saturation),
      );
    }

    final blur = s.blurRadius + s.pressBlur * _press;
    if (blur > 0) {
      final sigma = _sigma(blur);
      final b = ui.ImageFilter.blur(
        sigmaX: sigma,
        sigmaY: sigma,
        tileMode: TileMode.clamp,
      );
      filter = filter == null ? b : ui.ImageFilter.compose(outer: b, inner: filter);
    }

    _lensRect = null;
    final lens = _lensFilter();
    if (lens != null) {
      filter =
          filter == null ? lens : ui.ImageFilter.compose(outer: lens, inner: filter);
    }
    return filter;
  }

  ui.ImageFilter? _lensFilter() {
    final s = _style;
    final minSide = size.shortestSide;
    var height = s.refractionHeight +
        s.refractionHeightFactor * minSide +
        s.pressRefraction * _press;
    var amount = s.refractionAmount + s.refractionAmountFactor * minSide;
    if (height <= 0 || amount <= 0) return null;

    final shader = _lensShader ??= GlassShaders.createLens();
    if (shader == null) return null;

    final rect = _textureRect();
    _lensRect = rect;
    _schedulePositionCheck();
    final scale = rect.width / size.width;
    height = math.min(height, minSide / 2) * scale;
    amount *= scale;
    final (tl, tr, br, bl) = _radii();

    // Uniforms 0 and 1 are the input texture size, filled by the engine.
    var i = 2;
    shader
      ..setFloat(i++, rect.left)
      ..setFloat(i++, rect.top)
      ..setFloat(i++, rect.width)
      ..setFloat(i++, rect.height)
      ..setFloat(i++, tl * scale)
      ..setFloat(i++, tr * scale)
      ..setFloat(i++, br * scale)
      ..setFloat(i++, bl * scale)
      ..setFloat(i++, height)
      ..setFloat(i++, amount)
      ..setFloat(i++, s.depthEffect ? 1 : 0)
      ..setFloat(i++, s.chromaticAberration ? 1 : 0);
    return ui.ImageFilter.shader(shader);
  }

  /// This surface's bounds in the backdrop texture's pixel space: physical
  /// pixels from the top-left of the view.
  Rect _textureRect() {
    final transform = getTransformTo(null);
    final rect = MatrixUtils.transformRect(transform, Offset.zero & size);
    return Rect.fromLTRB(
      rect.left * _dpr,
      rect.top * _dpr,
      rect.right * _dpr,
      rect.bottom * _dpr,
    );
  }

  void _paintSurface(PaintingContext context, Offset offset) {
    final s = _style;
    var canvas = context.canvas;
    final rect = offset & size;

    if (s.surfaceColor.a > 0) {
      _paint
        ..shader = null
        ..blendMode = BlendMode.srcOver
        ..style = PaintingStyle.fill
        ..color = s.surfaceColor;
      canvas.drawRect(rect, _paint);
    }

    if (_press > 0 && s.pressGlow > 0) {
      final center = offset + (_touchPosition ?? size.center(Offset.zero));
      _paint
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.fill
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(center, size.shortestSide * 1.2, [
          Color.fromRGBO(255, 255, 255, s.pressGlow * _press),
          const Color(0x00FFFFFF),
        ]);
      canvas.drawRect(rect, _paint);
      _paint
        ..shader = null
        ..blendMode = BlendMode.srcOver;
    }

    final child = this.child;
    if (child != null) context.paintChild(child, offset);
    canvas = context.canvas;

    final highlight = s.highlight;
    if (highlight != null && highlight.alpha > 0 && highlight.width > 0) {
      _paintHighlight(canvas, offset, highlight);
    }

    final edge = s.edgeColor;
    if (edge != null && s.edgeWidth > 0) {
      _paint
        ..shader = null
        ..blendMode = BlendMode.srcOver
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.edgeWidth
        ..color = edge;
      canvas.drawRRect(_rrect(offset).deflate(s.edgeWidth / 2), _paint);
      _paint.style = PaintingStyle.fill;
    }
  }

  void _paintHighlight(Canvas canvas, Offset offset, GlassHighlight h) {
    final shader = _highlightShader ??= GlassShaders.createHighlight();
    final alpha = h.color.a * h.alpha;
    if (shader == null) {
      // No shader: an even hairline, Highlight.Plain's look.
      _paint
        ..shader = null
        ..blendMode = h.blendMode
        ..style = PaintingStyle.stroke
        ..strokeWidth = h.width
        ..color = h.color.withValues(alpha: alpha);
      canvas.drawRRect(_rrect(offset).deflate(h.width / 2), _paint);
      _paint
        ..style = PaintingStyle.fill
        ..blendMode = BlendMode.srcOver;
      return;
    }

    final (tl, tr, br, bl) = _radii();
    final mode = switch (h.mode) {
      GlassHighlightMode.directional => 0.0,
      GlassHighlightMode.ambient => 1.0,
      GlassHighlightMode.plain => 2.0,
    };
    var i = 0;
    shader
      ..setFloat(i++, size.width)
      ..setFloat(i++, size.height)
      ..setFloat(i++, tl)
      ..setFloat(i++, tr)
      ..setFloat(i++, br)
      ..setFloat(i++, bl)
      ..setFloat(i++, h.color.r)
      ..setFloat(i++, h.color.g)
      ..setFloat(i++, h.color.b)
      ..setFloat(i++, alpha)
      ..setFloat(i++, h.angle * math.pi / 180)
      ..setFloat(i++, h.falloff)
      ..setFloat(i++, (h.width * _dpr).ceilToDouble())
      ..setFloat(i++, h.blurRadius > 0 ? h.blurRadius * _dpr * 0.57735 + 0.5 : 0)
      ..setFloat(i++, _dpr)
      ..setFloat(i++, mode);
    _paint
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.fill
      ..blendMode = h.blendMode
      ..shader = shader;
    canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..drawRect(Offset.zero & size, _paint)
      ..restore();
    _paint
      ..shader = null
      ..blendMode = BlendMode.srcOver;
  }

  /// Kyant's `colorControls` matrix: saturation about Rec. 709 luma, then
  /// contrast about mid-grey, then a brightness offset.
  static List<double> _colorControls(
    double brightness,
    double contrast,
    double saturation,
  ) {
    final invSat = 1 - saturation;
    final r = 0.213 * invSat;
    final g = 0.715 * invSat;
    final b = 0.072 * invSat;
    final c = contrast;
    final t = (0.5 - c * 0.5 + brightness) * 255;
    final s = saturation;
    return <double>[
      c * r + c * s, c * g, c * b, 0, t, //
      c * r, c * g + c * s, c * b, 0, t, //
      c * r, c * g, c * b + c * s, 0, t, //
      0, 0, 0, 1, 0, //
    ];
  }
}
