import 'dart:ui';

import 'package:flutter/foundation.dart';

/// How a rim highlight is coloured — Kyant0/backdrop's `HighlightStyle`.
enum GlassHighlightMode {
  /// White light along the edges facing [GlassHighlight.angle] and its
  /// opposite, added onto the glass (`HighlightStyle.Default`).
  directional,

  /// Light on the edges facing the light, shade on the far ones, painted
  /// over the glass (`HighlightStyle.Ambient`).
  ambient,

  /// An even rim all the way round (`HighlightStyle.Plain`).
  plain,
}

/// The thin light-catching rim of a glass surface — `Highlight` upstream.
@immutable
class GlassHighlight {
  const GlassHighlight({
    this.width = 0.5,
    double? blurRadius,
    this.alpha = 1,
    this.mode = GlassHighlightMode.directional,
    this.color = const Color(0x80FFFFFF),
    this.angle = 45,
    this.falloff = 1,
  }) : blurRadius = blurRadius ?? width / 2;

  /// Rim width in logical pixels.
  final double width;

  /// Softness of the rim's inner edge, in logical pixels.
  final double blurRadius;

  /// Overall opacity, 0..1.
  final double alpha;

  final GlassHighlightMode mode;

  /// Rim colour; its alpha is the paint alpha upstream applies.
  final Color color;

  /// Light direction in degrees, 0 pointing right, 90 down.
  final double angle;

  final double falloff;

  /// `Highlight.Default`.
  static const GlassHighlight directional = GlassHighlight();

  /// `Highlight.Ambient`.
  static const GlassHighlight ambient = GlassHighlight(
    mode: GlassHighlightMode.ambient,
    color: Color(0x61FFFFFF),
  );

  /// `Highlight.Plain`.
  static const GlassHighlight plain = GlassHighlight(
    mode: GlassHighlightMode.plain,
    color: Color(0x61FFFFFF),
  );

  BlendMode get blendMode =>
      mode == GlassHighlightMode.ambient ? BlendMode.srcOver : BlendMode.plus;

  GlassHighlight copyWith({double? width, double? alpha, double? angle}) {
    return GlassHighlight(
      width: width ?? this.width,
      blurRadius: width != null ? width / 2 : blurRadius,
      alpha: alpha ?? this.alpha,
      mode: mode,
      color: color,
      angle: angle ?? this.angle,
      falloff: falloff,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassHighlight &&
      other.width == width &&
      other.blurRadius == blurRadius &&
      other.alpha == alpha &&
      other.mode == mode &&
      other.color == color &&
      other.angle == angle &&
      other.falloff == falloff;

  @override
  int get hashCode =>
      Object.hash(width, blurRadius, alpha, mode, color, angle, falloff);
}

/// The soft drop shadow under a glass surface, drawn only outside the shape
/// so it never darkens the glass itself — `Shadow` upstream.
@immutable
class GlassShadow {
  const GlassShadow({
    this.radius = 24,
    Offset? offset,
    this.color = const Color(0x1A000000),
    this.alpha = 1,
  }) : _offset = offset;

  /// Blur radius in logical pixels (Android blur-radius semantics).
  final double radius;
  final Offset? _offset;

  /// Defaults to a sixth of the radius straight down.
  Offset get offset => _offset ?? Offset(0, radius / 6);
  final Color color;
  final double alpha;

  /// `Shadow.Default`.
  static const GlassShadow standard = GlassShadow();

  GlassShadow copyWith({double? alpha}) => GlassShadow(
        radius: radius,
        offset: _offset,
        color: color,
        alpha: alpha ?? this.alpha,
      );

  @override
  bool operator ==(Object other) =>
      other is GlassShadow &&
      other.radius == radius &&
      other.offset == offset &&
      other.color == color &&
      other.alpha == alpha;

  @override
  int get hashCode => Object.hash(radius, offset, color, alpha);
}

/// Everything that decides how one glass surface renders: the effect chain
/// applied to what is behind it (colour controls → blur → lens, in the same
/// order as the Kotlin `effects {}` block), then the tint, rim and shadow.
@immutable
class GlassStyle {
  const GlassStyle({
    this.blurRadius = 0,
    this.saturation = 1,
    this.brightness = 0,
    this.contrast = 1,
    this.refractionHeight = 0,
    this.refractionAmount = 0,
    this.refractionHeightFactor = 0,
    this.refractionAmountFactor = 0,
    this.depthEffect = false,
    this.chromaticAberration = false,
    this.surfaceColor = const Color(0x00000000),
    this.highlight = GlassHighlight.directional,
    this.shadow = GlassShadow.standard,
    this.edgeColor,
    this.edgeWidth = 0.5,
    this.pressBlur = 0,
    this.pressRefraction = 0,
    this.pressGlow = 0,
  });

  /// Backdrop blur radius in logical pixels, with Android's RenderEffect
  /// radius semantics (converted to a Gaussian sigma when applied).
  final double blurRadius;

  final double saturation;
  final double brightness;
  final double contrast;

  /// Width of the refracting band along the rim, logical pixels.
  final double refractionHeight;

  /// How far the rim pulls the backdrop inward, logical pixels.
  final double refractionAmount;

  /// Added to [refractionHeight] as a fraction of the shorter side.
  final double refractionHeightFactor;

  /// Added to [refractionAmount] as a fraction of the shorter side.
  final double refractionAmountFactor;

  /// Bends the refraction toward the centre, so the surface reads domed.
  final bool depthEffect;

  /// Splits the refracted rim into a seven-band spectrum.
  final bool chromaticAberration;

  /// Drawn over the processed backdrop, under the content.
  final Color surfaceColor;

  final GlassHighlight? highlight;
  final GlassShadow? shadow;

  /// Optional hairline border over everything.
  final Color? edgeColor;
  final double edgeWidth;

  /// Extra blur at full press (LastWave's GlassInteraction).
  final double pressBlur;

  /// Extra refraction height at full press.
  final double pressRefraction;

  /// Opacity of the additive glow under the finger at full press.
  final double pressGlow;

  bool get hasBackdropEffect =>
      blurRadius > 0 ||
      saturation != 1 ||
      brightness != 0 ||
      contrast != 1 ||
      refractionHeight > 0 ||
      refractionHeightFactor > 0 ||
      pressBlur > 0;

  /// BitChord's `Modifier.liquidGlass`: vibrancy 1.5, 8dp blur, a 24dp
  /// domed lens with chromatic aberration, a 40% theme tint, the default
  /// rim and shadow, and (on the bars) a 0.5dp white hairline.
  factory GlassStyle.bitChord({
    required bool dark,
    Color? surfaceTint,
    bool edge = true,
    bool chromaticAberration = true,
  }) {
    final themeTint = dark ? const Color(0xFF121212) : const Color(0xFFFAFAFA);
    return GlassStyle(
      saturation: 1.5,
      blurRadius: 8,
      refractionHeight: 24,
      refractionAmount: 24,
      depthEffect: true,
      chromaticAberration: chromaticAberration,
      surfaceColor: surfaceTint ?? themeTint.withValues(alpha: 0.4),
      highlight: GlassHighlight.directional,
      shadow: GlassShadow.standard,
      edgeColor: edge ? const Color(0x1AFFFFFF) : null,
    );
  }

  /// BitChord's nav bar tint: a faint white in dark theme so the bar reads
  /// as frosted grey over black, and the default tint in light theme.
  static Color? bitChordBarTint({required bool dark}) =>
      dark ? const Color(0x17FFFFFF) : null;

  GlassStyle copyWith({
    double? blurRadius,
    double? refractionHeight,
    double? refractionAmount,
    bool? chromaticAberration,
    Color? surfaceColor,
    GlassHighlight? highlight,
    bool clearHighlight = false,
    GlassShadow? shadow,
    bool clearShadow = false,
  }) {
    return GlassStyle(
      blurRadius: blurRadius ?? this.blurRadius,
      saturation: saturation,
      brightness: brightness,
      contrast: contrast,
      refractionHeight: refractionHeight ?? this.refractionHeight,
      refractionAmount: refractionAmount ?? this.refractionAmount,
      refractionHeightFactor: refractionHeightFactor,
      refractionAmountFactor: refractionAmountFactor,
      depthEffect: depthEffect,
      chromaticAberration: chromaticAberration ?? this.chromaticAberration,
      surfaceColor: surfaceColor ?? this.surfaceColor,
      highlight: clearHighlight ? null : (highlight ?? this.highlight),
      shadow: clearShadow ? null : (shadow ?? this.shadow),
      edgeColor: edgeColor,
      edgeWidth: edgeWidth,
      pressBlur: pressBlur,
      pressRefraction: pressRefraction,
      pressGlow: pressGlow,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassStyle &&
      other.blurRadius == blurRadius &&
      other.saturation == saturation &&
      other.brightness == brightness &&
      other.contrast == contrast &&
      other.refractionHeight == refractionHeight &&
      other.refractionAmount == refractionAmount &&
      other.refractionHeightFactor == refractionHeightFactor &&
      other.refractionAmountFactor == refractionAmountFactor &&
      other.depthEffect == depthEffect &&
      other.chromaticAberration == chromaticAberration &&
      other.surfaceColor == surfaceColor &&
      other.highlight == highlight &&
      other.shadow == shadow &&
      other.edgeColor == edgeColor &&
      other.edgeWidth == edgeWidth &&
      other.pressBlur == pressBlur &&
      other.pressRefraction == pressRefraction &&
      other.pressGlow == pressGlow;

  @override
  int get hashCode => Object.hashAll([
        blurRadius,
        saturation,
        brightness,
        contrast,
        refractionHeight,
        refractionAmount,
        refractionHeightFactor,
        refractionAmountFactor,
        depthEffect,
        chromaticAberration,
        surfaceColor,
        highlight,
        shadow,
        edgeColor,
        edgeWidth,
        pressBlur,
        pressRefraction,
        pressGlow,
      ]);
}
