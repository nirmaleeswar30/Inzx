import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import '../core/services/cache/hive_service.dart';
import '../data/entities/color_cache_entity.dart';

/// OuterTune-style album color extractor
/// Uses image scaling approach like OuterTune for accurate colors
class AlbumColorExtractor {
  /// Cache version prefix to ensure updated accurate palettes are loaded
  static const String _cachePrefix = 'v3_';

  /// Cache of extracted colors by URL
  static final Map<String, AlbumColors> _cache = {};

  /// Normalize URL to share cache keys and standard resolutions across variations of the same artwork
  static String? normalizeUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    var normalized = url.trim();
    if (normalized.contains('googleusercontent.com') ||
        normalized.contains('ggpht.com')) {
      normalized = normalized.replaceAll(
        RegExp(r'=w\d+-h\d+[^?#]*'),
        '=w544-h544-l90-rj',
      );
      normalized = normalized.replaceAll(
        RegExp(r'=s\d+[^?#]*'),
        '=s544-c',
      );
    }
    return normalized;
  }

  /// Synchronously retrieve cached colors if available (in-memory or Hive RAM box)
  static AlbumColors? getFast(String? imageUrl) {
    final normalized = normalizeUrl(imageUrl);
    if (normalized == null) return null;
    final key = '$_cachePrefix$normalized';

    // 1. Check in-memory cache
    if (_cache.containsKey(key)) {
      return _cache[key]!;
    }

    // 2. Check Hive cache (instant RAM lookup for opened Hive box)
    try {
      final cached = HiveService.colorsBox.get(key);
      if (cached != null) {
        final colors = AlbumColors(
          accent: Color(cached.accent),
          accentLight: Color(cached.accentLight),
          accentDark: Color(cached.accentDark),
          backgroundPrimary: Color(cached.backgroundPrimary),
          backgroundSecondary: Color(cached.backgroundSecondary),
          surface: Color(cached.surface),
          onBackground: Color(cached.onBackground),
          onSurface: Color(cached.onSurface),
          isDefault: false,
        );
        _cache[key] = colors;
        return colors;
      }
    } catch (e) {
      if (kDebugMode) {
        print('AlbumColorExtractor: Hive getFast error: $e');
      }
    }

    return null;
  }

  /// Extract colors from album art URL or local file path using OuterTune's approach
  /// 1. Check fast cache (memory + Hive)
  /// 2. Try loading cached image bytes from disk (DefaultCacheManager or local File)
  /// 3. Download image bytes if remote and not on disk
  /// 4. Scale to 64x64 in isolate and extract via Median Cut color quantization
  /// 5. Save to memory and Hive caches
  static Future<AlbumColors> extractFromUrl(String? imageUrl) async {
    final normalizedUrl = normalizeUrl(imageUrl);
    if (normalizedUrl == null) {
      return AlbumColors.defaultColors();
    }

    // Check fast cache first (0ms delay)
    final fast = getFast(normalizedUrl);
    if (fast != null) {
      return fast;
    }

    try {
      Uint8List? bytes;

      final isRemote =
          normalizedUrl.startsWith('http://') ||
          normalizedUrl.startsWith('https://');

      if (isRemote) {
        // Try local disk cache from CachedNetworkImage / DefaultCacheManager
        // Check both original and normalized in case disk cached under raw URL
        try {
          var fileInfo =
              await DefaultCacheManager().getFileFromCache(imageUrl ?? normalizedUrl);
          fileInfo ??=
              await DefaultCacheManager().getFileFromCache(normalizedUrl);
          if (fileInfo != null && await fileInfo.file.exists()) {
            bytes = await fileInfo.file.readAsBytes();
          }
        } catch (_) {}

        // Fallback to HTTP download if not in disk cache
        if (bytes == null || bytes.isEmpty) {
          final response = await http
              .get(Uri.parse(normalizedUrl))
              .timeout(const Duration(seconds: 3));

          if (response.statusCode == 200) {
            bytes = response.bodyBytes;
          }
        }
      } else {
        // Local file path
        try {
          final file = File(normalizedUrl);
          if (await file.exists()) {
            bytes = await file.readAsBytes();
          }
        } catch (_) {}
      }

      if (bytes == null || bytes.isEmpty) {
        return AlbumColors.defaultColors();
      }

      return await extractFromBytes(bytes, cacheKey: normalizedUrl);
    } catch (e) {
      return AlbumColors.defaultColors();
    }
  }

  /// Extract colors directly from image bytes with optional cache key
  static Future<AlbumColors> extractFromBytes(Uint8List bytes, {String? cacheKey}) async {
    if (bytes.isEmpty) return AlbumColors.defaultColors();

    if (cacheKey != null && cacheKey.isNotEmpty) {
      final fast = getFast(cacheKey);
      if (fast != null) return fast;
    }

    try {
      // Process in isolate and convert back to AlbumColors
      final rawColors = await compute(
        _extractColorsIsolate,
        bytes,
      );
      final colors = _rawColorsToAlbumColors(rawColors);

      if (cacheKey != null && cacheKey.isNotEmpty) {
        final key = '$_cachePrefix$cacheKey';
        // Cache result in memory
        _cache[key] = colors;

        // Save to Hive for instant access in future sessions
        _saveToHive(cacheKey, colors);

        // Limit in-memory cache size
        if (_cache.length > 50) {
          _cache.remove(_cache.keys.first);
        }
      }

      return colors;
    } catch (e) {
      return AlbumColors.defaultColors();
    }
  }

  /// Save extracted colors to Hive database
  static void _saveToHive(String imageUrl, AlbumColors colors) {
    try {
      final key = '$_cachePrefix$imageUrl';
      HiveService.colorsBox.put(
        key,
        ColorCacheEntity(
          imageUrl: key,
          accent: colors.accent.toARGB32(),
          accentLight: colors.accentLight.toARGB32(),
          accentDark: colors.accentDark.toARGB32(),
          backgroundPrimary: colors.backgroundPrimary.toARGB32(),
          backgroundSecondary: colors.backgroundSecondary.toARGB32(),
          surface: colors.surface.toARGB32(),
          onBackground: colors.onBackground.toARGB32(),
          onSurface: colors.onSurface.toARGB32(),
          cachedAt: DateTime.now(),
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        print('AlbumColorExtractor: Error saving to Hive: $e');
      }
    }
  }

  /// Create album colors from dominant and accent
  static AlbumColors _createAlbumColors(Color dominant, Color accent) {
    final dominantHsl = HSLColor.fromColor(dominant);
    final accentHsl = HSLColor.fromColor(accent);

    // Background: Use dominant but make it deep and rich (not dull or muddy)
    final bgLightness = dominantHsl.lightness.clamp(0.06, 0.13);
    // If dominant has color, give the dark background true hue depth
    final bgSaturation = dominantHsl.saturation > 0.15
        ? (dominantHsl.saturation * 0.75).clamp(0.18, 0.55)
        : (dominantHsl.saturation * 0.5).clamp(0.05, 0.20);

    final backgroundPrimary = HSLColor.fromAHSL(
      1,
      dominantHsl.hue,
      bgSaturation,
      bgLightness,
    ).toColor();

    final backgroundSecondary = HSLColor.fromAHSL(
      1,
      dominantHsl.hue,
      bgSaturation * 0.7,
      (bgLightness - 0.03).clamp(0.03, 0.09),
    ).toColor();

    // Detect if the album art is essentially black/dark or grayscale
    // This prevents extracting false colors (like brown or purple) from noise in dark pixels
    final bool isGrayscale = dominantHsl.saturation < 0.12 && accentHsl.saturation < 0.15;
    final bool isVeryDark = dominantHsl.lightness < 0.15 && accentHsl.lightness < 0.22;
    final bool useWhiteAccent = isGrayscale || isVeryDark;

    Color finalAccent;
    Color finalAccentLight;
    Color finalAccentDark;

    if (useWhiteAccent) {
      finalAccent = Colors.white;
      finalAccentLight = Colors.white;
      finalAccentDark = Colors.grey.shade400;
    } else {
      // Accent: Boost saturation and ensure vivid visibility for UI controls
      final accentLightness = accentHsl.lightness.clamp(0.45, 0.68);
      final accentSaturation = (accentHsl.saturation * 1.1).clamp(0.50, 0.95);

      finalAccent = HSLColor.fromAHSL(
        1,
        accentHsl.hue,
        accentSaturation,
        accentLightness,
      ).toColor();

      finalAccentLight = HSLColor.fromAHSL(
        1,
        accentHsl.hue,
        (accentSaturation * 0.85).clamp(0.4, 0.9),
        (accentLightness + 0.14).clamp(0.55, 0.85),
      ).toColor();

      finalAccentDark = HSLColor.fromAHSL(
        1,
        accentHsl.hue,
        accentSaturation,
        (accentLightness - 0.14).clamp(0.25, 0.55),
      ).toColor();
    }

    // Surface: Slightly lighter than background with hint of color
    final surface = HSLColor.fromAHSL(
      1,
      dominantHsl.hue,
      (bgSaturation * 0.5).clamp(0.08, 0.30),
      (bgLightness + 0.06).clamp(0.12, 0.20),
    ).toColor();

    return AlbumColors(
      accent: finalAccent,
      accentLight: finalAccentLight,
      accentDark: finalAccentDark,
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

  /// Create light mode variant with pastel backgrounds and dark text
  AlbumColors toLightMode() {
    final accentHsl = HSLColor.fromColor(accent);
    final bgHsl = HSLColor.fromColor(backgroundPrimary);

    // Light pastel background from album hue
    final lightBgPrimary = HSLColor.fromAHSL(
      1,
      bgHsl.hue,
      (bgHsl.saturation * 0.3).clamp(0.05, 0.2),
      0.92,
    ).toColor();

    final lightBgSecondary = HSLColor.fromAHSL(
      1,
      bgHsl.hue,
      (bgHsl.saturation * 0.25).clamp(0.03, 0.15),
      0.88,
    ).toColor();

    final lightSurface = HSLColor.fromAHSL(
      1,
      bgHsl.hue,
      (bgHsl.saturation * 0.15).clamp(0.02, 0.1),
      0.96,
    ).toColor();

    // Darker accent for light mode contrast
    final darkAccent = HSLColor.fromAHSL(
      1,
      accentHsl.hue,
      accentHsl.saturation.clamp(0.5, 0.9),
      accentHsl.lightness.clamp(0.35, 0.5),
    ).toColor();

    return AlbumColors(
      accent: darkAccent,
      accentLight: accent, // Original becomes the light variant
      accentDark: accentDark,
      backgroundPrimary: lightBgPrimary,
      backgroundSecondary: lightBgSecondary,
      surface: lightSurface,
      onBackground: const Color(0xFF1A1A1A), // Dark text
      onSurface: const Color(0xFF1A1A1A),
      isDefault: isDefault,
    );
  }
}

/// Raw color data returned from isolate (can't use Color class in isolate)
class _RawColorData {
  final int dominantColor;
  final int accentColor;

  _RawColorData(this.dominantColor, this.accentColor);
}

class _ColorPoint {
  final int r;
  final int g;
  final int b;
  final int count;

  _ColorPoint(this.r, this.g, this.b, this.count);
}

class _VBox {
  final List<_ColorPoint> points;
  int minR = 255, maxR = 0;
  int minG = 255, maxG = 0;
  int minB = 255, maxB = 0;
  int totalCount = 0;

  _VBox(this.points) {
    for (final p in points) {
      if (p.r < minR) minR = p.r;
      if (p.r > maxR) maxR = p.r;
      if (p.g < minG) minG = p.g;
      if (p.g > maxG) maxG = p.g;
      if (p.b < minB) minB = p.b;
      if (p.b > maxB) maxB = p.b;
      totalCount += p.count;
    }
  }

  int get rangeR => maxR - minR;
  int get rangeG => maxG - minG;
  int get rangeB => maxB - minB;
  int get maxRange => max(rangeR, max(rangeG, rangeB));

  int get avgR {
    if (totalCount == 0) return 0;
    int sum = 0;
    for (final p in points) {
      sum += p.r * p.count;
    }
    return (sum / totalCount).round().clamp(0, 255);
  }

  int get avgG {
    if (totalCount == 0) return 0;
    int sum = 0;
    for (final p in points) {
      sum += p.g * p.count;
    }
    return (sum / totalCount).round().clamp(0, 255);
  }

  int get avgB {
    if (totalCount == 0) return 0;
    int sum = 0;
    for (final p in points) {
      sum += p.b * p.count;
    }
    return (sum / totalCount).round().clamp(0, 255);
  }
}

class _ColorSwatch {
  final int r, g, b, count;
  final double population;
  final double hue, saturation, lightness;

  _ColorSwatch({
    required this.r,
    required this.g,
    required this.b,
    required this.count,
    required this.population,
    required this.hue,
    required this.saturation,
    required this.lightness,
  });

  int get rgb => (r << 16) | (g << 8) | b;
}

_ColorSwatch _createSwatch(int r, int g, int b, int count, int totalPixels) {
  final rf = r / 255.0;
  final gf = g / 255.0;
  final bf = b / 255.0;

  final maxC = max(rf, max(gf, bf));
  final minC = min(rf, min(gf, bf));
  final delta = maxC - minC;

  final l = (maxC + minC) / 2.0;
  double s = 0.0;
  if (delta != 0.0) {
    s = l > 0.5 ? delta / (2.0 - maxC - minC) : delta / (maxC + minC);
  }

  double h = 0.0;
  if (delta != 0.0) {
    if (maxC == rf) {
      h = ((gf - bf) / delta) % 6;
    } else if (maxC == gf) {
      h = (bf - rf) / delta + 2;
    } else {
      h = (rf - gf) / delta + 4;
    }
    h *= 60.0;
    if (h < 0) h += 360.0;
  }

  return _ColorSwatch(
    r: r,
    g: g,
    b: b,
    count: count,
    population: totalPixels > 0 ? count / totalPixels : 0.0,
    hue: h,
    saturation: s,
    lightness: l,
  );
}

/// Top-level function for compute() - extracts dominant and accent colors
/// Uses Median Cut (MMCQ) on a 64x64 downsampled image
_RawColorData _extractColorsIsolate(Uint8List bytes) {
  try {
    // Decode image
    final image = img.decodeImage(bytes);
    if (image == null) return _RawColorData(0x1A1A2E, 0x6366F1);

    // If the image is rectangular (e.g. 16:9 or 4:3 YouTube video thumbnail),
    // crop to the center square so black pillarboxes/letterboxes don't distort album art colors.
    img.Image squareImage = image;
    if (image.width > image.height) {
      final cropSize = image.height;
      final xOffset = (image.width - cropSize) ~/ 2;
      squareImage = img.copyCrop(
        image,
        x: xOffset,
        y: 0,
        width: cropSize,
        height: cropSize,
      );
    } else if (image.height > image.width) {
      final cropSize = image.width;
      final yOffset = (image.height - cropSize) ~/ 2;
      squareImage = img.copyCrop(
        image,
        x: 0,
        y: yOffset,
        width: cropSize,
        height: cropSize,
      );
    }

    // 64x64 gives 4,096 pixels - high resolution color sampling executed in an isolate
    final scaled = img.copyResize(squareImage, width: 64, height: 64);

    // 15-bit color map: 5 bits per channel (0..31)
    final hist = <int, int>{};
    final allHist = <int, int>{};
    int totalValid = 0;
    int totalAll = 0;

    for (int y = 0; y < scaled.height; y++) {
      for (int x = 0; x < scaled.width; x++) {
        final pixel = scaled.getPixel(x, y);
        if (pixel.a < 128) continue;

        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();

        // 5-bit quantization
        final r5 = r >> 3;
        final g5 = g >> 3;
        final b5 = b >> 3;
        final key = (r5 << 10) | (g5 << 5) | b5;

        allHist[key] = (allHist[key] ?? 0) + 1;
        totalAll++;

        // Filter out near-black padding/border pixels unless whole image is dark
        if (r < 8 && g < 8 && b < 8) continue;

        hist[key] = (hist[key] ?? 0) + 1;
        totalValid++;
      }
    }

    // Fall back to all pixels if the artwork itself is predominantly dark
    final activeHist = (hist.length >= 4 && totalValid >= 50) ? hist : allHist;
    final activeTotal = (hist.length >= 4 && totalValid >= 50) ? totalValid : totalAll;

    if (activeHist.isEmpty) return _RawColorData(0x1A1A2E, 0x6366F1);

    final points = <_ColorPoint>[];
    for (final entry in activeHist.entries) {
      final key = entry.key;
      final r = ((key >> 10) & 0x1F) << 3;
      final g = ((key >> 5) & 0x1F) << 3;
      final b = (key & 0x1F) << 3;
      points.add(_ColorPoint(r, g, b, entry.value));
    }

    // Median Cut algorithm to find up to 16 dominant color clusters
    final boxes = <_VBox>[_VBox(points)];
    const targetClusters = 16;

    while (boxes.length < targetClusters) {
      int bestIdx = -1;
      int maxRange = -1;

      for (int i = 0; i < boxes.length; i++) {
        final b = boxes[i];
        if (b.points.length > 1 && b.maxRange > maxRange) {
          maxRange = b.maxRange;
          bestIdx = i;
        }
      }

      if (bestIdx == -1 || maxRange <= 0) break;

      final boxToSplit = boxes.removeAt(bestIdx);
      final rangeR = boxToSplit.rangeR;
      final rangeG = boxToSplit.rangeG;
      final rangeB = boxToSplit.rangeB;

      // Sort along channel with greatest variance
      if (rangeR >= rangeG && rangeR >= rangeB) {
        boxToSplit.points.sort((a, b) => a.r.compareTo(b.r));
      } else if (rangeG >= rangeR && rangeG >= rangeB) {
        boxToSplit.points.sort((a, b) => a.g.compareTo(b.g));
      } else {
        boxToSplit.points.sort((a, b) => a.b.compareTo(b.b));
      }

      // Split at median of pixel counts
      final medianCount = boxToSplit.totalCount ~/ 2;
      int runningCount = 0;
      int splitIdx = 0;

      for (int i = 0; i < boxToSplit.points.length; i++) {
        runningCount += boxToSplit.points[i].count;
        if (runningCount >= medianCount) {
          splitIdx = max(1, i);
          break;
        }
      }

      if (splitIdx >= boxToSplit.points.length) {
        splitIdx = boxToSplit.points.length - 1;
      }

      boxes.add(_VBox(boxToSplit.points.sublist(0, splitIdx)));
      boxes.add(_VBox(boxToSplit.points.sublist(splitIdx)));
    }

    // Create swatches from color clusters
    final swatches = <_ColorSwatch>[];
    for (final box in boxes) {
      if (box.totalCount == 0) continue;
      swatches.add(_createSwatch(
        box.avgR,
        box.avgG,
        box.avgB,
        box.totalCount,
        activeTotal,
      ));
    }

    if (swatches.isEmpty) return _RawColorData(0x1A1A2E, 0x6366F1);

    // Pick Dominant Swatch:
    // Balances population with meaningful saturation (avoiding pure black/white)
    _ColorSwatch? bestDominant;
    double bestDomScore = -99999.0;

    for (final s in swatches) {
      double penalty = 0.0;
      if (s.lightness < 0.06) penalty += 0.5;
      if (s.lightness > 0.94) penalty += 0.5;

      final score = (s.population * 2.0) + (s.saturation * 0.8) - penalty;
      if (score > bestDomScore) {
        bestDomScore = score;
        bestDominant = s;
      }
    }
    bestDominant ??= swatches.first;

    // Pick Accent Swatch:
    // High saturation, pleasant lightness (0.4-0.7), and distinct hue from dominant
    _ColorSwatch? bestAccent;
    double bestAccentScore = -99999.0;

    for (final s in swatches) {
      if (s.lightness < 0.15 || s.lightness > 0.85) continue;

      final hueDiff = (s.hue - bestDominant.hue).abs();
      final circularHueDiff = min(hueDiff, 360.0 - hueDiff);

      double distinctBonus = 0.0;
      if (circularHueDiff > 25.0) {
        distinctBonus = 0.5;
      } else if (bestDominant.saturation < 0.20 && s.saturation > 0.35) {
        distinctBonus = 0.6;
      }

      final lightnessScore = 1.0 - (s.lightness - 0.55).abs() * 2.0;

      final score = (s.saturation * 2.5) +
          (lightnessScore * 1.0) +
          (sqrt(s.population) * 0.5) +
          distinctBonus;

      if (score > bestAccentScore) {
        bestAccentScore = score;
        bestAccent = s;
      }
    }

    bestAccent ??= bestDominant;

    return _RawColorData(bestDominant.rgb, bestAccent.rgb);
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
