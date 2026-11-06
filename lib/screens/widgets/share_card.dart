import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../core/liquid_glass/liquid_glass_kit.dart';
import '../../core/providers/theme_provider.dart';
import 'progress_bar_painters.dart';

/// The card's own surface. Liquid is real shader glass over the backdrop.
enum ShareCardStyle { dark, liquid, light }

enum ShareCardMode { song, lyrics }

/// A story image's size, in the logical pixels the card is laid out in. The
/// exported file is this at 3x: 1080x1920.
const Size kShareCardSize = Size(360, 640);

/// Colours for one song's card, all derived from the cover's accent.
@immutable
class ShareCardPalette {
  ShareCardPalette.fromAccent(Color seed) : hue = HSLColor.fromColor(seed).hue, saturation = _usable(seed);

  final double hue;
  final double saturation;

  /// Greys stay grey: forcing saturation onto one invents a colour the cover
  /// doesn't have.
  static double _usable(Color seed) {
    final s = HSLColor.fromColor(seed).saturation;
    return s < 0.12 ? 0.06 : math.max(s, 0.42);
  }

  bool get _isGrey => saturation < 0.12;

  Color _hsl(double shift, double s, double l) => HSLColor.fromAHSL(
    1,
    (hue + shift) % 360,
    s.clamp(0.0, 1.0),
    l.clamp(0.0, 1.0),
  ).toColor();

  Color get vivid => _hsl(0, _isGrey ? saturation : math.max(saturation, 0.6), 0.46);
  Color get deep => _hsl(0, math.min(saturation, 0.55), 0.14);
  Color get deeper => _hsl(18, math.min(saturation, 0.5), 0.06);
  Color get soft => _hsl(0, math.min(saturation, 0.55), 0.86);
  Color get softer => _hsl(25, math.min(saturation, 0.45), 0.74);
  Color get glow => _hsl(0, math.min(saturation, 0.7), 0.32);
  Color get accent => _hsl(0, _isGrey ? 0.08 : math.max(saturation, 0.55), 0.72);
  Color get onAccent => _hsl(0, math.min(saturation, 0.6), 0.13);

  /// The sheet around the card.
  Color get sheet => _hsl(0, math.min(saturation, 0.14), 0.12);
  Color get raised => _hsl(0, math.min(saturation, 0.13), 0.19);
  Color get tint => _hsl(0, _isGrey ? saturation : math.max(saturation, 0.5), 0.78);
  Color get onTint => _hsl(0, math.min(saturation, 0.6), 0.12);

  Color card(ShareCardStyle style) => style == ShareCardStyle.light
      ? _hsl(0, math.min(saturation, 0.5), 0.91)
      : _hsl(0, math.min(saturation, 0.32), 0.14);
  Color text(ShareCardStyle style) => style == ShareCardStyle.light
      ? _hsl(0, 0.5, 0.12)
      : _hsl(0, 0.2, 0.95);
  Color subtext(ShareCardStyle style) => style == ShareCardStyle.light
      ? _hsl(0, 0.28, 0.32)
      : _hsl(0, 0.14, 0.72);
  Color bar(ShareCardStyle style) => style == ShareCardStyle.light
      ? _hsl(0, math.max(saturation, 0.1), 0.38)
      : _hsl(0, math.max(saturation, 0.1), 0.76);

  /// Number of backdrops [backdrop] offers. The first is the blurred cover.
  static const int themeCount = 5;

  /// The story background for a theme, or null for the blurred cover.
  Gradient? backdrop(int theme) => switch (theme) {
    1 => LinearGradient(
      begin: const Alignment(-0.3, -1),
      end: const Alignment(0.3, 1),
      colors: [deep, deeper],
    ),
    2 => LinearGradient(
      begin: const Alignment(-0.3, -1),
      end: const Alignment(0.3, 1),
      colors: [vivid, deep],
    ),
    3 => RadialGradient(
      radius: 0.9,
      colors: [glow, const Color(0xFF08080A)],
      stops: const [0, 0.75],
    ),
    4 => LinearGradient(
      begin: const Alignment(-0.3, -1),
      end: const Alignment(0.3, 1),
      colors: [soft, softer],
    ),
    _ => null,
  };
}

/// What a card shows. Built fresh for every frame of the preview and once more
/// for the export, so the two can't drift apart.
@immutable
class ShareCardData {
  const ShareCardData({
    required this.title,
    required this.artist,
    required this.palette,
    required this.style,
    required this.mode,
    required this.theme,
    required this.barStyle,
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.seed,
    this.art,
    this.logo,
    this.lyrics = const [],
    this.fontFamily,
  });

  final String title;
  final String artist;
  final ui.Image? art;
  final ui.Image? logo;
  final ShareCardPalette palette;
  final ShareCardStyle style;
  final ShareCardMode mode;
  final int theme;
  final ProgressBarStyle barStyle;
  final Duration position;
  final Duration duration;
  final bool isPlaying;

  /// Keeps a song's Spectrum bars the same as on its now playing screen.
  final int seed;
  final List<String> lyrics;
  final String? fontFamily;

  double get progress => duration.inMilliseconds <= 0
      ? 0
      : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
}

String _clock(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// One share card: the story background with the song or lyrics card on it.
/// Always [kShareCardSize]; the sheet scales it down to preview it.
class ShareCard extends StatelessWidget {
  const ShareCard({super.key, required this.data});

  final ShareCardData data;

  static const double _cardRadius = 22;

  @override
  Widget build(BuildContext context) {
    final card = data.mode == ShareCardMode.song
        ? _SongCard(data: data)
        : _LyricsCard(data: data);
    return SizedBox.fromSize(
      size: kShareCardSize,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // A story image has to be solid edge to edge: anything see-through
          // shows whatever the receiving app or viewer puts behind it.
          ColoredBox(color: data.palette.deeper),
          _Backdrop(data: data),
          Center(child: card),
        ],
      ),
    );
  }

  /// The card's surface. Dark and Light are solid. Liquid is the app's shader
  /// glass, and its edge is the lens itself: the rim bends and splits whatever
  /// is behind it. So what the card should show through the glass, its tint and
  /// [behindGlass], goes behind the surface. Painted as the glass's child it
  /// would sit on top of the lens and hide it.
  static Widget surface(
    ShareCardData data, {
    required double width,
    required Widget child,
    Widget? behindGlass,
  }) {
    final color = data.palette.card(data.style);
    final radius = BorderRadius.circular(_cardRadius);
    if (data.style != ShareCardStyle.liquid) {
      return Container(
        width: width,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: color, borderRadius: radius),
        child: child,
      );
    }
    return SizedBox(
      width: width,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: color.withValues(alpha: 0.62)),
                  ?behindGlass,
                ],
              ),
            ),
          ),
          LiquidGlass(
            borderRadius: radius,
            // Its own backdrop read: nothing else on the card shares it.
            shareBackdrop: false,
            // The bars' lens and rim (GlassStyle.bitChord), left clear: no
            // blur or tint, so the cover stays sharp behind the glass.
            style: const GlassStyle(
              refractionHeight: 24,
              refractionAmount: 28,
              depthEffect: true,
              chromaticAberration: true,
              highlight: GlassHighlight.directional,
              shadow: GlassShadow.standard,
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.data});

  final ShareCardData data;

  static const double _blurSigma = 30;
  static const double _blurOverscan = _blurSigma * 3 + 30;

  @override
  Widget build(BuildContext context) {
    final gradient = data.palette.backdrop(data.theme);
    if (gradient != null) {
      return DecoratedBox(decoration: BoxDecoration(gradient: gradient));
    }
    final art = data.art;
    if (art == null) {
      return DecoratedBox(
        decoration: BoxDecoration(gradient: data.palette.backdrop(1)),
      );
    }
    // A blur fades out near the edges of what it's given, and on the phone's
    // renderer it does so whatever tile mode it's asked for. So the cover is
    // laid out well past the story on every side, further than the blur
    // reaches (three sigmas), and that fade falls outside the image.
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: -_blurOverscan,
            right: -_blurOverscan,
            top: -_blurOverscan,
            bottom: -_blurOverscan,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: _blurSigma,
                sigmaY: _blurSigma,
                tileMode: TileMode.clamp,
              ),
              child: ColorFiltered(
                colorFilter: ColorFilter.matrix(_saturate(1.25)),
                child: RawImage(image: art, fit: BoxFit.cover),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static List<double> _saturate(double s) {
    final i = 1 - s;
    final r = 0.213 * i, g = 0.715 * i, b = 0.072 * i;
    return [r + s, g, b, 0, 0, r, g + s, b, 0, 0, r, g, b + s, 0, 0, 0, 0, 0, 1, 0];
  }
}

class _Art extends StatelessWidget {
  const _Art({required this.data, this.radius = 0});

  final ShareCardData data;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final art = data.art;
    final child = art != null
        ? RawImage(image: art, fit: BoxFit.cover)
        : ColoredBox(
            color: data.palette.glow,
            child: Center(
              child: Icon(Iconsax.music, color: data.palette.tint, size: 56),
            ),
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: child,
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.image});

  final ui.Image? image;

  static const double size = 27;

  @override
  Widget build(BuildContext context) {
    final logo = image;
    if (logo == null) return const SizedBox(width: size, height: size);
    return RawImage(
      image: logo,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }
}

class _SongCard extends StatelessWidget {
  const _SongCard({required this.data});

  final ShareCardData data;

  static const double _width = 259;
  static const double _padding = 11;

  @override
  Widget build(BuildContext context) {
    final style = data.style;
    final fg = data.palette.text(style);
    final sub = data.palette.subtext(style);
    final font = data.fontFamily;

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          data.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: font,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            height: 1.2,
            color: fg,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          data.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontFamily: font, fontSize: 12, color: sub),
        ),
        const SizedBox(height: 8),
        _ProgressBar(data: data),
        const SizedBox(height: 5),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _clock(data.position),
              style: TextStyle(
                fontFamily: font,
                fontSize: 10,
                color: sub,
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
            ),
            Text(
              _clock(data.duration),
              style: TextStyle(
                fontFamily: font,
                fontSize: 10,
                color: sub,
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        _Controls(data: data),
      ],
    );

    const artSide = _width;
    if (style == ShareCardStyle.liquid) {
      // The cover runs to the card's edges and melts away down the glass.
      return ShareCard.surface(
        data,
        width: _width,
        behindGlass: Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: artSide,
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white, Colors.white, Colors.transparent],
              stops: [0, 0.58, 0.98],
            ).createShader(rect),
            child: _Art(data: data),
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 16,
              right: 16,
              child: _Logo(image: data.logo),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                _padding,
                artSide - 32,
                _padding,
                _padding,
              ),
              child: details,
            ),
          ],
        ),
      );
    }

    return ShareCard.surface(
      data,
      width: _width,
      child: Padding(
        padding: const EdgeInsets.all(_padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Art(data: data, radius: 14),
                  Positioned(
                    top: 5,
                    right: 5,
                    child: _Logo(image: data.logo),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            details,
          ],
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.data});

  final ShareCardData data;

  @override
  Widget build(BuildContext context) {
    final style = data.style;
    final active = data.palette.bar(style);
    final inactive = data.palette.subtext(style).withValues(alpha: 0.32);
    final thumb = data.palette.text(style);
    final (double height, CustomPainter painter) = switch (data.barStyle) {
      ProgressBarStyle.defaultLinear => (
        12.0,
        LinearProgressBarPainter(
          progress: data.progress,
          activeColor: active,
          inactiveColor: inactive,
          trackHeight: 3,
          thumbRadius: 5,
        ),
      ),
      ProgressBarStyle.waveform => (
        14.0,
        WavyProgressBarPainter(
          progress: data.progress,
          // A still image gets the wave wherever the song has got to.
          phase: (data.position.inMilliseconds / 1000) % (2 * math.pi),
          activeColor: active,
          inactiveColor: inactive,
          thumbColor: thumb,
          trackHeight: 2.6,
          thumbRadius: 4,
          isSeeking: false,
        ),
      ),
      ProgressBarStyle.comet => (
        16.0,
        CometProgressBarPainter(
          progress: data.progress,
          activeColor: active,
          inactiveColor: inactive,
          headColor: thumb,
          trackHeight: 3,
          tailLength: 80,
          rayOpacity: data.isPlaying ? 1 : 0,
        ),
      ),
      ProgressBarStyle.spectrum => (
        30.0,
        SpectrumBarPainter(
          progress: data.progress,
          amplitudes: SpectrumBarPainter.generateAmplitudes(56, data.seed),
          activeColor: active,
          inactiveColor: inactive,
          thumbColor: thumb,
          seekScale: 0,
          isSeeking: false,
        ),
      ),
    };
    return SizedBox(
      height: height,
      child: CustomPaint(size: Size.infinite, painter: painter),
    );
  }
}

/// The now playing screen's controls: plain Iconsax skips either side of the
/// round accent play button.
class _Controls extends StatelessWidget {
  const _Controls({required this.data});

  final ShareCardData data;

  @override
  Widget build(BuildContext context) {
    final fg = data.palette.text(data.style);
    final accent = data.palette.accent;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Icon(Iconsax.previous, color: fg, size: 29),
        Container(
          width: 49,
          height: 49,
          decoration: BoxDecoration(
            color: accent,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.45),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            data.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: data.palette.onAccent,
            size: 29,
          ),
        ),
        Icon(Iconsax.next, color: fg, size: 29),
      ],
    );
  }
}

class _LyricsCard extends StatelessWidget {
  const _LyricsCard({required this.data});

  final ShareCardData data;

  static const double _width = 281;

  @override
  Widget build(BuildContext context) {
    final style = data.style;
    final fg = data.palette.text(style);
    final sub = data.palette.subtext(style);
    final font = data.fontFamily;

    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: _Art(data: data, radius: 9),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: font,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                    Text(
                      data.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: font,
                        fontSize: 10.5,
                        color: sub,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _Logo(image: data.logo),
            ],
          ),
          const SizedBox(height: 12),
          for (final (i, line) in data.lyrics.indexed) ...[
            if (i > 0) const SizedBox(height: 7),
            Text(
              line,
              style: TextStyle(
                fontFamily: font,
                fontSize: 18.5,
                fontWeight: FontWeight.w700,
                height: 1.28,
                color: fg,
              ),
            ),
          ],
        ],
      ),
    );

    if (style != ShareCardStyle.liquid) {
      return ShareCard.surface(data, width: _width, child: content);
    }
    return ShareCard.surface(
      data,
      width: _width,
      behindGlass: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x8CFFFFFF), Color(0x8CFFFFFF), Colors.transparent],
          stops: [0, 0.2, 0.8],
        ).createShader(rect),
        child: _Art(data: data),
      ),
      child: content,
    );
  }
}
