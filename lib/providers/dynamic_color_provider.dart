import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../services/audio_player_service.dart' as player;
import '../services/album_color_extractor.dart';

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
  /// Now uses AlbumColorExtractor which runs color extraction in an isolate
  /// for better performance (no main thread blocking)
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
      // Use AlbumColorExtractor which runs in an isolate
      // Import is already available through album_color_extractor.dart
      final albumColors = await _extractInIsolate(imageUrl);

      if (albumColors == null) {
        return null;
      }

      // Convert AlbumColors to DynamicColors
      final colors = _fromAlbumColors(albumColors, isDark);
      _colorCache[cacheKey] = colors;
      return colors;
    } catch (e) {
      if (kDebugMode) {
        print('Error extracting colors: $e');
      }
      return null;
    }
  }

  /// Extract colors using isolate-based AlbumColorExtractor
  Future<AlbumColors?> _extractInIsolate(String imageUrl) async {
    try {
      return await AlbumColorExtractor.extractFromUrl(imageUrl);
    } catch (e) {
      return null;
    }
  }

  /// Convert AlbumColors (from isolate) to DynamicColors
  DynamicColors _fromAlbumColors(AlbumColors albumColors, bool isDark) {
    final primary = isDark ? albumColors.accentLight : albumColors.accent;
    final onPrimary = _getContrastColor(primary);

    return DynamicColors(
      primary: primary,
      onPrimary: onPrimary,
      secondary: albumColors.accentDark,
      background: albumColors.backgroundPrimary,
      surface: albumColors.surface,
      accent: albumColors.accent,
      isDark: isDark,
      dominant: albumColors.backgroundPrimary,
      lightVibrant: albumColors.accentLight,
      darkVibrant: albumColors.accentDark,
      lightMuted: albumColors.surface,
      darkMuted: albumColors.backgroundSecondary,
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
