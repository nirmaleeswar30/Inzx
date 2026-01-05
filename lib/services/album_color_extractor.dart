import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

/// OuterTune-style album color extractor
/// Uses image scaling approach like OuterTune for accurate colors
class AlbumColorExtractor {
  /// Cache of extracted colors by URL
  static final Map<String, AlbumColors> _cache = {};

  /// Extract colors from album art URL using OuterTune's approach
  /// 1. Download image
  /// 2. Scale to tiny size (16x16) to get dominant colors
  /// 3. Sample key regions for color analysis
  static Future<AlbumColors> extractFromUrl(String? imageUrl) async {
    if (imageUrl == null || imageUrl.isEmpty) {
      return AlbumColors.defaultColors();
    }

    // Check cache
    if (_cache.containsKey(imageUrl)) {
      return _cache[imageUrl]!;
    }

    try {
      // Download image bytes
      final response = await http
          .get(Uri.parse(imageUrl))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        return AlbumColors.defaultColors();
      }

      // Process in isolate and convert back to AlbumColors
      final rawColors = await compute(
        _extractColorsIsolate,
        response.bodyBytes,
      );
      final colors = _rawColorsToAlbumColors(rawColors);

      // Cache result
      _cache[imageUrl] = colors;

      // Limit cache size
      if (_cache.length > 30) {
        _cache.remove(_cache.keys.first);
      }

      return colors;
    } catch (e) {
      return AlbumColors.defaultColors();
    }
  }

  /// Extract colors using image library (like OuterTune does with Bitmap)
  static Future<AlbumColors> _extractColorsFromBytes(Uint8List bytes) async {
    try {
      // Decode image
      final image = img.decodeImage(bytes);
      if (image == null) return AlbumColors.defaultColors();

      // Scale down to 16x16 (OuterTune approach - small sample for dominant colors)
      final scaled = img.copyResize(image, width: 16, height: 16);

      // Collect all colors from scaled image
      final colorCounts = <int, int>{};

      for (int y = 0; y < scaled.height; y++) {
        for (int x = 0; x < scaled.width; x++) {
          final pixel = scaled.getPixel(x, y);
          final r = pixel.r.toInt();
          final g = pixel.g.toInt();
          final b = pixel.b.toInt();

          // Quantize colors to reduce noise (group similar colors)
          final quantized = _quantizeColor(r, g, b);
          colorCounts[quantized] = (colorCounts[quantized] ?? 0) + 1;
        }
      }

      // Sort by frequency
      final sortedColors = colorCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      // Get dominant colors
      Color? dominantColor;
      Color? accentColor;

      for (final entry in sortedColors) {
        final color = Color(entry.key | 0xFF000000);

        if (dominantColor == null) {
          // First valid color is dominant
          if (_isValidDominant(color)) {
            dominantColor = color;
          }
        } else if (accentColor == null) {
          // Second color should be different enough for accent
          if (_isValidAccent(color) &&
              _colorDifference(dominantColor, color) > 0.15) {
            accentColor = color;
            break;
          }
        }
      }

      // Fallbacks
      dominantColor ??= const Color(0xFF1A1A2E);
      accentColor ??= const Color(0xFF6366F1);

      // Create final colors based on dominant/accent
      return _createAlbumColors(dominantColor, accentColor);
    } catch (e) {
      return AlbumColors.defaultColors();
    }
  }

  /// Quantize color to 32 levels per channel (reduces noise)
  static int _quantizeColor(int r, int g, int b) {
    final qr = (r ~/ 8) * 8;
    final qg = (g ~/ 8) * 8;
    final qb = (b ~/ 8) * 8;
    return (qr << 16) | (qg << 8) | qb;
  }

  /// Check if color is valid as dominant (not too gray/white/black)
  static bool _isValidDominant(Color color) {
    final hsl = HSLColor.fromColor(color);
    // Allow darker colors for background
    return hsl.lightness > 0.05 && hsl.lightness < 0.85;
  }

  /// Check if color is valid as accent (needs saturation)
  static bool _isValidAccent(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl.saturation > 0.2 && hsl.lightness > 0.15 && hsl.lightness < 0.8;
  }

  /// Calculate color difference (0-1)
  static double _colorDifference(Color a, Color b) {
    final dr = (a.red - b.red).abs() / 255;
    final dg = (a.green - b.green).abs() / 255;
    final db = (a.blue - b.blue).abs() / 255;
    return (dr + dg + db) / 3;
  }

  /// Create album colors from dominant and accent
  static AlbumColors _createAlbumColors(Color dominant, Color accent) {
    final dominantHsl = HSLColor.fromColor(dominant);
    final accentHsl = HSLColor.fromColor(accent);

    // Background: Use dominant but make it DARK (like OuterTune)
    // Lightness clamped to 0.08-0.15 for proper dark background
    final bgLightness = dominantHsl.lightness.clamp(0.05, 0.12);
    final bgSaturation = (dominantHsl.saturation * 0.6).clamp(0.1, 0.4);

    final backgroundPrimary = HSLColor.fromAHSL(
      1,
      dominantHsl.hue,
      bgSaturation,
      bgLightness,
    ).toColor();

    final backgroundSecondary = HSLColor.fromAHSL(
      1,
      dominantHsl.hue,
      bgSaturation * 0.5,
      (bgLightness - 0.03).clamp(0.02, 0.08),
    ).toColor();

    // Accent: Boost saturation and ensure visibility
    final accentLightness = accentHsl.lightness.clamp(0.4, 0.65);
    final accentSaturation = accentHsl.saturation.clamp(0.4, 0.85);

    final finalAccent = HSLColor.fromAHSL(
      1,
      accentHsl.hue,
      accentSaturation,
      accentLightness,
    ).toColor();

    // Surface: Slightly lighter than background with hint of color
    final surface = HSLColor.fromAHSL(
      1,
      dominantHsl.hue,
      bgSaturation * 0.3,
      (bgLightness + 0.05).clamp(0.1, 0.18),
    ).toColor();

    return AlbumColors(
      accent: finalAccent,
      accentLight: HSLColor.fromAHSL(
        1,
        accentHsl.hue,
        accentSaturation * 0.8,
        (accentLightness + 0.15).clamp(0, 0.8),
      ).toColor(),
      accentDark: HSLColor.fromAHSL(
        1,
        accentHsl.hue,
        accentSaturation,
        (accentLightness - 0.15).clamp(0.2, 1),
      ).toColor(),
      backgroundPrimary: backgroundPrimary,
      backgroundSecondary: backgroundSecondary,
      surface: surface,
      onBackground: Colors.white,
      onSurface: Colors.white,
      isDefault: false,
    );
  }

  /// Clear the cache
  static void clearCache() {
    _cache.clear();
  }
}

/// Album-derived colors for UI styling
class AlbumColors {
  final Color accent;
  final Color accentLight;
  final Color accentDark;
  final Color backgroundPrimary;
  final Color backgroundSecondary;
  final Color surface;
  final Color onBackground;
  final Color onSurface;
  final bool isDefault;

  const AlbumColors({
    required this.accent,
    required this.accentLight,
    required this.accentDark,
    required this.backgroundPrimary,
    required this.backgroundSecondary,
    required this.surface,
    required this.onBackground,
    required this.onSurface,
    required this.isDefault,
  });

  /// Default fallback colors (dark indigo theme)
  factory AlbumColors.defaultColors() => const AlbumColors(
    accent: Color(0xFF6366F1),
    accentLight: Color(0xFF818CF8),
    accentDark: Color(0xFF4F46E5),
    backgroundPrimary: Color(0xFF0D0D14),
    backgroundSecondary: Color(0xFF050508),
    surface: Color(0xFF16161F),
    onBackground: Colors.white,
    onSurface: Colors.white,
    isDefault: true,
  );

  /// Lerp between two AlbumColors for smooth animation
  static AlbumColors lerp(AlbumColors a, AlbumColors b, double t) {
    return AlbumColors(
      accent: Color.lerp(a.accent, b.accent, t)!,
      accentLight: Color.lerp(a.accentLight, b.accentLight, t)!,
      accentDark: Color.lerp(a.accentDark, b.accentDark, t)!,
      backgroundPrimary: Color.lerp(
        a.backgroundPrimary,
        b.backgroundPrimary,
        t,
      )!,
      backgroundSecondary: Color.lerp(
        a.backgroundSecondary,
        b.backgroundSecondary,
        t,
      )!,
      surface: Color.lerp(a.surface, b.surface, t)!,
      onBackground: Color.lerp(a.onBackground, b.onBackground, t)!,
      onSurface: Color.lerp(a.onSurface, b.onSurface, t)!,
      isDefault: t < 0.5 ? a.isDefault : b.isDefault,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AlbumColors &&
        other.accent == accent &&
        other.backgroundPrimary == backgroundPrimary;
  }

  @override
  int get hashCode => accent.hashCode ^ backgroundPrimary.hashCode;
}

/// Raw color data returned from isolate (can't use Color class in isolate)
class _RawColorData {
  final int dominantColor;
  final int accentColor;

  _RawColorData(this.dominantColor, this.accentColor);
}

/// Top-level function for compute() - extracts dominant colors from image bytes
/// Must be top-level to work with compute()
/// Returns raw int colors since Color class can't be used in isolate
_RawColorData _extractColorsIsolate(Uint8List bytes) {
  try {
    // Decode image
    final image = img.decodeImage(bytes);
    if (image == null) return _RawColorData(0xFF1A1A2E, 0xFF6366F1);

    // Scale down to 16x16 (OuterTune approach - small sample for dominant colors)
    final scaled = img.copyResize(image, width: 16, height: 16);

    // Collect all colors from scaled image
    final colorCounts = <int, int>{};

    for (int y = 0; y < scaled.height; y++) {
      for (int x = 0; x < scaled.width; x++) {
        final pixel = scaled.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();

        // Quantize colors to reduce noise (group similar colors)
        final qr = (r ~/ 8) * 8;
        final qg = (g ~/ 8) * 8;
        final qb = (b ~/ 8) * 8;
        final quantized = (qr << 16) | (qg << 8) | qb;
        colorCounts[quantized] = (colorCounts[quantized] ?? 0) + 1;
      }
    }

    // Sort by frequency
    final sortedColors = colorCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Get dominant colors using simple heuristics (no Color/HSL classes)
    int? dominantColor;
    int? accentColor;

    for (final entry in sortedColors) {
      final rgb = entry.key;
      final r = (rgb >> 16) & 0xFF;
      final g = (rgb >> 8) & 0xFF;
      final b = rgb & 0xFF;

      // Simple lightness check: (max + min) / 2 / 255
      final maxC = [r, g, b].reduce((a, b) => a > b ? a : b);
      final minC = [r, g, b].reduce((a, b) => a < b ? a : b);
      final lightness = (maxC + minC) / 510.0;

      // Saturation check
      final chroma = (maxC - minC) / 255.0;
      final saturation = lightness > 0 && lightness < 1
          ? chroma / (1 - (2 * lightness - 1).abs())
          : 0.0;

      if (dominantColor == null) {
        // First valid color is dominant (not too dark or light)
        if (lightness > 0.05 && lightness < 0.85) {
          dominantColor = rgb;
        }
      } else if (accentColor == null) {
        // Second color needs saturation and difference
        if (saturation > 0.2 && lightness > 0.15 && lightness < 0.8) {
          // Check color difference
          final dr = ((dominantColor >> 16) & 0xFF) - r;
          final dg = ((dominantColor >> 8) & 0xFF) - g;
          final db = (dominantColor & 0xFF) - b;
          final diff = (dr.abs() + dg.abs() + db.abs()) / 765.0;

          if (diff > 0.15) {
            accentColor = rgb;
            break;
          }
        }
      }
    }

    // Fallbacks
    dominantColor ??= 0x1A1A2E;
    accentColor ??= 0x6366F1;

    return _RawColorData(dominantColor, accentColor);
  } catch (e) {
    return _RawColorData(0x1A1A2E, 0x6366F1);
  }
}

/// Convert raw color data from isolate to AlbumColors
AlbumColors _rawColorsToAlbumColors(_RawColorData raw) {
  final dominant = Color(raw.dominantColor | 0xFF000000);
  final accent = Color(raw.accentColor | 0xFF000000);
  return AlbumColorExtractor._createAlbumColors(dominant, accent);
}
