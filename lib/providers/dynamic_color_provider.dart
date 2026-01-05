import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/models.dart';
import '../services/audio_player_service.dart' as player;

/// Dynamic colors extracted from album art
class DynamicColors {
  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color background;
  final Color surface;
  final Color accent;
  final bool isDark;

  // Additional color variants for theme integration
  final Color? dominant;
  final Color? lightVibrant;
  final Color? darkVibrant;
  final Color? lightMuted;
  final Color? darkMuted;

  /// Whether dynamic colors are actively being used (music is playing)
  final bool isActive;

  const DynamicColors({
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.background,
    required this.surface,
    required this.accent,
    required this.isDark,
    this.dominant,
    this.lightVibrant,
    this.darkVibrant,
    this.lightMuted,
    this.darkMuted,
    this.isActive = false,
  });

  /// Default colors when no album art
  factory DynamicColors.defaultColors({
    bool isDark = false,
    bool isActive = false,
  }) {
    if (isDark) {
      return DynamicColors(
        primary: const Color(0xFF8FD4B6),
        onPrimary: Colors.black,
        secondary: const Color(0xFFB8B4DE),
        background: const Color(0xFF121212),
        surface: const Color(0xFF1E1E1E),
        accent: const Color(0xFF8FD4B6),
        isDark: true,
        isActive: isActive,
      );
    }
    return DynamicColors(
      primary: const Color(0xFF7BC4A8),
      onPrimary: Colors.white,
      secondary: const Color(0xFFA5A1CE),
      background: const Color(0xFFF8F9FA),
      surface: Colors.white,
      accent: const Color(0xFF7BC4A8),
      isDark: false,
      isActive: isActive,
    );
  }
}

/// Service for extracting colors from images
class DynamicColorService {
  static final DynamicColorService _instance = DynamicColorService._internal();
  factory DynamicColorService() => _instance;
  DynamicColorService._internal();

  /// Cache for extracted colors
  final Map<String, DynamicColors> _colorCache = {};

  /// Extract colors from an image URL
  /// Uses smaller image size for faster extraction (OuterTune approach)
  Future<DynamicColors?> extractColorsFromUrl(
    String imageUrl, {
    bool isDark = false,
  }) async {
    // Check cache first
    final cacheKey = '${imageUrl}_$isDark';
    if (_colorCache.containsKey(cacheKey)) {
      return _colorCache[cacheKey];
    }

    try {
      // Use smaller resolution URL if possible (YouTube thumbnails)
      final optimizedUrl = _getOptimizedThumbnailUrl(imageUrl);
      final imageProvider = CachedNetworkImageProvider(optimizedUrl);

      // Extract palette with minimal size for speed
      final paletteGenerator =
          await PaletteGenerator.fromImageProvider(
            imageProvider,
            size: const Size(48, 48), // Very small - 4x faster than 200x200
            maximumColorCount: 6, // Fewer colors = faster
          ).timeout(
            const Duration(seconds: 3),
            onTimeout: () => throw TimeoutException('Palette timeout'),
          );

      final colors = _buildColors(paletteGenerator, isDark);
      _colorCache[cacheKey] = colors;
      return colors;
    } catch (e) {
      if (kDebugMode) {
        print('Error extracting colors: $e');
      }
      return null;
    }
  }

  /// Get smaller thumbnail URL for faster loading
  String _getOptimizedThumbnailUrl(String url) {
    // YouTube thumbnails: replace maxresdefault/hqdefault with mqdefault (smaller)
    if (url.contains('ytimg.com') || url.contains('googleusercontent.com')) {
      return url
          .replaceAll('maxresdefault', 'default')
          .replaceAll('hqdefault', 'default')
          .replaceAll('sddefault', 'default');
    }
    return url;
  }

  /// Build DynamicColors from palette
  DynamicColors _buildColors(PaletteGenerator palette, bool isDark) {
    // Get dominant and vibrant colors
    final dominant = palette.dominantColor?.color;
    final vibrant = palette.vibrantColor?.color;
    final darkVibrant = palette.darkVibrantColor?.color;
    final lightVibrant = palette.lightVibrantColor?.color;
    final muted = palette.mutedColor?.color;
    final darkMuted = palette.darkMutedColor?.color;
    final lightMuted = palette.lightMutedColor?.color;

    Color primary;
    Color secondary;
    Color accent;
    Color background;
    Color surface;

    if (isDark) {
      // Dark theme: use lighter variants
      primary = lightVibrant ?? vibrant ?? dominant ?? const Color(0xFF8FD4B6);
      secondary = lightMuted ?? muted ?? primary.withValues(alpha: 0.7);
      accent = vibrant ?? primary;
      background = darkMuted?.withValues(alpha: 0.3) ?? const Color(0xFF121212);
      surface = darkVibrant?.withValues(alpha: 0.2) ?? const Color(0xFF1E1E1E);
    } else {
      // Light theme: use vibrant variants
      primary = vibrant ?? dominant ?? const Color(0xFF7BC4A8);
      secondary = muted ?? darkMuted ?? primary.withValues(alpha: 0.7);
      accent = darkVibrant ?? vibrant ?? primary;
      background =
          lightMuted?.withValues(alpha: 0.1) ?? const Color(0xFFF8F9FA);
      surface = lightVibrant?.withValues(alpha: 0.1) ?? Colors.white;
    }

    // Ensure good contrast for onPrimary
    final onPrimary = _getContrastColor(primary);

    return DynamicColors(
      primary: primary,
      onPrimary: onPrimary,
      secondary: secondary,
      background: background,
      surface: surface,
      accent: accent,
      isDark: isDark,
      dominant: dominant,
      lightVibrant: lightVibrant,
      darkVibrant: darkVibrant,
      lightMuted: lightMuted,
      darkMuted: darkMuted,
      isActive: true,
    );
  }

  /// Get contrasting text color (black or white)
  Color _getContrastColor(Color color) {
    // Calculate luminance
    final luminance = color.computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }

  /// Clear cache
  void clearCache() {
    _colorCache.clear();
  }
}

/// Provider for dynamic color service
final dynamicColorServiceProvider = Provider<DynamicColorService>((ref) {
  return DynamicColorService();
});

/// Provider for current dynamic colors based on playing track
final dynamicColorsProvider =
    StateNotifierProvider<DynamicColorsNotifier, DynamicColors?>((ref) {
      return DynamicColorsNotifier(ref);
    });

/// Notifier for managing dynamic colors
class DynamicColorsNotifier extends StateNotifier<DynamicColors?> {
  final DynamicColorService _colorService = DynamicColorService();
  StreamSubscription<String?>? _subscription;
  String? _lastTrackId;

  // Debounce to prevent rapid color extractions
  Timer? _debounceTimer;
  static const _debounceDelay = Duration(milliseconds: 300);

  DynamicColorsNotifier(Ref ref) : super(null) {
    _init();
  }

  void _init() {
    // Use the singleton AudioPlayerService, NOT create a new one
    final playerService = player.AudioPlayerService.instance;

    // Only listen to distinct states to reduce processing
    // We only care about track changes, not position updates
    _subscription = playerService.stateStream
        .map((state) => state.currentTrack?.id) // Extract only track ID
        .distinct() // Only emit when track ID changes
        .listen((trackId) {
          if (trackId != null && trackId != _lastTrackId) {
            _lastTrackId = trackId;
            // Get the current track from state
            final track = playerService.currentTrack;
            if (track != null) {
              // Debounce color extraction
              _debounceTimer?.cancel();
              _debounceTimer = Timer(_debounceDelay, () {
                _extractColors(track);
              });
            }
          } else if (trackId == null && _lastTrackId != null) {
            _lastTrackId = null;
            _debounceTimer?.cancel();
            state = null;
          }
        });
  }

  Future<void> _extractColors(Track track) async {
    final imageUrl = track.bestThumbnail;
    if (imageUrl == null) {
      state = null;
      return;
    }

    // TODO: Get actual theme brightness from context
    final isDark = false;

    final colors = await _colorService.extractColorsFromUrl(
      imageUrl,
      isDark: isDark,
    );
    if (mounted) {
      state = colors;
    }
  }

  /// Manually update colors for a track
  Future<void> updateColorsForTrack(Track track, {bool isDark = false}) async {
    final imageUrl = track.bestThumbnail;
    if (imageUrl == null) {
      state = null;
      return;
    }

    final colors = await _colorService.extractColorsFromUrl(
      imageUrl,
      isDark: isDark,
    );
    if (mounted) {
      state = colors;
    }
  }

  /// Clear current colors
  void clearColors() {
    _lastTrackId = null;
    _debounceTimer?.cancel();
    state = null;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }
}

/// Provider to check if dynamic theming is enabled
final dynamicThemingEnabledProvider = StateProvider<bool>((ref) => true);

/// Provider for the effective accent color (dynamic or user-selected)
final effectiveAccentColorProvider = Provider<Color>((ref) {
  final dynamicEnabled = ref.watch(dynamicThemingEnabledProvider);
  final dynamicColors = ref.watch(dynamicColorsProvider);

  if (dynamicEnabled && dynamicColors != null) {
    return dynamicColors.primary;
  }

  // Fall back to default sage green
  return const Color(0xFF7BC4A8);
});
