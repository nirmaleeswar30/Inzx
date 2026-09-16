import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../design_system/colors.dart';
import '../../services/deep_link_handler.dart';
import '../../services/audio_player_service.dart';

/// Theme mode options for the app
enum InzxThemeMode { system, light, dark }

/// Available accent color options
enum InzxAccentColor {
  purple, // Purple/Violet/Lilac #6B46C1 - default
  red, // AMOLED red
  sage, // Sage green
  lavender, // Soft lavender
  peach, // Warm peach
  ocean, // Ocean blue
  rose, // Soft rose
  amber, // Warm amber
  mint, // Fresh mint
  coral, // Soft coral
  custom, // Custom user chosen color
}

/// Get the Color value for an accent color option
Color getAccentColor(InzxAccentColor accent, {bool isDark = false, Color? customColor}) {
  switch (accent) {
    case InzxAccentColor.purple:
      return isDark ? const Color(0xFF9F7AEA) : const Color(0xFF6B46C1);
    case InzxAccentColor.red:
      return isDark ? const Color(0xFFE53935) : const Color(0xFFD32F2F);
    case InzxAccentColor.sage:
      return isDark ? const Color(0xFF8FD4B6) : InzxColors.accent;
    case InzxAccentColor.lavender:
      return isDark ? const Color(0xFFB8B4DE) : InzxColors.accentSecondary;
    case InzxAccentColor.peach:
      return isDark ? const Color(0xFFF8C4B0) : InzxColors.accentTertiary;
    case InzxAccentColor.ocean:
      return isDark ? const Color(0xFF7BC4E8) : const Color(0xFF7BC4E8);
    case InzxAccentColor.rose:
      return isDark ? const Color(0xFFE4B5B5) : const Color(0xFFE4B5B5);
    case InzxAccentColor.amber:
      return isDark ? const Color(0xFFF8D08D) : const Color(0xFFF8D08D);
    case InzxAccentColor.mint:
      return isDark ? const Color(0xFF8FE4C8) : const Color(0xFF7DD4B8);
    case InzxAccentColor.coral:
      return isDark ? const Color(0xFFF8C4B0) : const Color(0xFFF8C4B0);
    case InzxAccentColor.custom:
      return customColor ?? (isDark ? const Color(0xFF9F7AEA) : const Color(0xFF6B46C1));
  }
}

/// Get the display name for an accent color
String getAccentColorName(InzxAccentColor accent) {
  switch (accent) {
    case InzxAccentColor.purple:
      return 'Purple';
    case InzxAccentColor.red:
      return 'Red';
    case InzxAccentColor.sage:
      return 'Sage Green';
    case InzxAccentColor.lavender:
      return 'Lavender';
    case InzxAccentColor.peach:
      return 'Peach';
    case InzxAccentColor.ocean:
      return 'Ocean Blue';
    case InzxAccentColor.rose:
      return 'Rose';
    case InzxAccentColor.amber:
      return 'Amber';
    case InzxAccentColor.mint:
      return 'Mint';
    case InzxAccentColor.coral:
      return 'Coral';
    case InzxAccentColor.custom:
      return 'Custom';
  }
}

/// Provider for the custom accent color
final customAccentColorProvider =
    StateNotifierProvider<CustomAccentColorNotifier, Color>((ref) {
      return CustomAccentColorNotifier();
    });

/// Notifier to manage custom accent color
class CustomAccentColorNotifier extends StateNotifier<Color> {
  static const String customAccentPrefKey = 'inzx_custom_accent_color_int';

  CustomAccentColorNotifier() : super(const Color(0xFF9F7AEA)) {
    _loadCustomColor();
  }

  Future<void> _loadCustomColor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final colorInt = prefs.getInt(customAccentPrefKey);
      if (colorInt != null) {
        state = Color(colorInt);
      }
    } catch (_) {}
  }

  Future<void> setCustomColor(Color color) async {
    state = color;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(customAccentPrefKey, color.toARGB32());
    } catch (_) {}
  }
}

/// Provider for the current accent color
final accentColorProvider =
    StateNotifierProvider<AccentColorNotifier, InzxAccentColor>((ref) {
      return AccentColorNotifier();
    });

/// Notifier to manage accent color state
class AccentColorNotifier extends StateNotifier<InzxAccentColor> {
  static const String accentColorPrefKey = 'inzx_accent_color_enum';

  AccentColorNotifier() : super(InzxAccentColor.purple) {
    _loadAccentColor();
  }

  Future<void> _loadAccentColor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final index = prefs.getInt(accentColorPrefKey);
      if (index != null && index >= 0 && index < InzxAccentColor.values.length) {
        state = InzxAccentColor.values[index];
      }
    } catch (_) {}
  }

  Future<void> setAccentColor(InzxAccentColor color) async {
    state = color;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(accentColorPrefKey, color.index);
    } catch (_) {}
  }
}

/// Provider for the current theme mode
final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, InzxThemeMode>((ref) {
      return ThemeModeNotifier();
    });

/// Notifier to manage theme mode state
class ThemeModeNotifier extends StateNotifier<InzxThemeMode> {
  static const String themeModePrefKey = 'inzx_theme_mode';
  static const String _legacyThemeModePrefKey = 'inzx_theme_mode';

  ThemeModeNotifier() : super(InzxThemeMode.dark) {
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      int? index = prefs.getInt(themeModePrefKey);
      if (index == null) {
        index = prefs.getInt(_legacyThemeModePrefKey);
        if (index != null) {
          await prefs.setInt(themeModePrefKey, index);
          await prefs.remove(_legacyThemeModePrefKey);
        }
      }
      if (index == null || index < 0 || index >= InzxThemeMode.values.length) {
        return;
      }
      state = InzxThemeMode.values[index];
    } catch (_) {
      // Keep default theme if preference loading fails.
    }
  }

  Future<void> _saveThemeMode(InzxThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(themeModePrefKey, mode.index);
    } catch (_) {
      // Non-fatal: theme still updates in memory.
    }
  }

  void setThemeMode(InzxThemeMode mode) {
    state = mode;
    _saveThemeMode(mode);
  }

  void toggleTheme() {
    switch (state) {
      case InzxThemeMode.system:
        state = InzxThemeMode.light;
        break;
      case InzxThemeMode.light:
        state = InzxThemeMode.dark;
        break;
      case InzxThemeMode.dark:
        state = InzxThemeMode.system;
        break;
    }
  }
}

/// Convert InzxThemeMode to Flutter's ThemeMode
ThemeMode toFlutterThemeMode(InzxThemeMode mode) {
  switch (mode) {
    case InzxThemeMode.system:
      return ThemeMode.system;
    case InzxThemeMode.light:
      return ThemeMode.light;
    case InzxThemeMode.dark:
      return ThemeMode.dark;
  }
}

/// Provider for the user's display name (for personalization)
final userNameProvider = StateNotifierProvider<UserNameNotifier, String>((ref) {
  return UserNameNotifier();
});

/// Notifier to manage user name state
class UserNameNotifier extends StateNotifier<String> {
  UserNameNotifier() : super('Music Lover');

  void setName(String name) {
    state = name.trim().isEmpty ? 'Music Lover' : name.trim();
  }
}

/// Provider for whether the liquid glass navigation bar is enabled
final liquidGlassNavProvider =
    StateNotifierProvider<LiquidGlassNavNotifier, bool>((ref) {
      return LiquidGlassNavNotifier();
    });

/// Notifier to manage the liquid glass navigation bar preference.
/// Default: false (off by default, uses normal navbar from commit 6ee4ad9).
class LiquidGlassNavNotifier extends StateNotifier<bool> {
  static const String liquidGlassNavPrefKey = 'inzx_liquid_glass_nav_enabled';

  LiquidGlassNavNotifier() : super(false) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(liquidGlassNavPrefKey);
      if (enabled != null) {
        state = enabled;
      }
    } catch (_) {}
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(liquidGlassNavPrefKey, enabled);
    } catch (_) {}
  }

  Future<void> toggle() => setEnabled(!state);
}

/// Provider for whether rotating miniplayer album art is enabled
final rotatingMiniPlayerArtProvider =
    StateNotifierProvider<RotatingMiniPlayerArtNotifier, bool>((ref) {
      return RotatingMiniPlayerArtNotifier();
    });

/// Notifier to manage the rotating miniplayer album art preference.
/// Default: true (enabled by default).
class RotatingMiniPlayerArtNotifier extends StateNotifier<bool> {
  static const String rotatingArtPrefKey =
      'inzx_rotating_mini_player_art_enabled';

  RotatingMiniPlayerArtNotifier() : super(true) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(rotatingArtPrefKey);
      if (enabled != null) {
        state = enabled;
      }
    } catch (_) {}
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(rotatingArtPrefKey, enabled);
    } catch (_) {}
  }

  Future<void> toggle() => setEnabled(!state);
}

/// Provider for whether animated album art (Canvas video) is enabled.
final animatedAlbumArtProvider =
    StateNotifierProvider<AnimatedAlbumArtNotifier, bool>((ref) {
  return AnimatedAlbumArtNotifier();
});

/// Notifier to manage the animated album art preference.
/// Default: true (enabled by default).
class AnimatedAlbumArtNotifier extends StateNotifier<bool> {
  static const String animatedArtPrefKey = 'inzx_animated_album_art_enabled';

  AnimatedAlbumArtNotifier() : super(true) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(animatedArtPrefKey);
      if (enabled != null) {
        state = enabled;
      }
    } catch (_) {}
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(animatedArtPrefKey, enabled);
    } catch (_) {}
  }

  Future<void> toggle() => setEnabled(!state);
}

/// Style options for the Now Playing player screen
enum NowPlayingStyle {
  defaultStyle, // Standard YouTube Music style
  ripple, // Wavy 8-petal artwork with circular seek ring & minimalist layout
  edge, // Full-bleed edge-to-edge artwork spanning the top half
  og, // Classic Inzx layout with left-aligned title & quick action buttons
}

String getNowPlayingStyleName(NowPlayingStyle style) {
  switch (style) {
    case NowPlayingStyle.defaultStyle:
      return 'Default';
    case NowPlayingStyle.ripple:
      return 'Ripple';
    case NowPlayingStyle.edge:
      return 'Cinematic';
    case NowPlayingStyle.og:
      return 'OG';
  }
}

String getNowPlayingStyleDescription(NowPlayingStyle style) {
  switch (style) {
    case NowPlayingStyle.defaultStyle:
      return 'Classic YouTube Music style with full artwork, linear progress bar, and slide-up queue';
    case NowPlayingStyle.ripple:
      return 'Fluid 8-petal wavy cover art with circular perimeter scrubber and sleek minimalist layout';
    case NowPlayingStyle.edge:
      return 'Full-width cover art with seamless fade into playback controls';
    case NowPlayingStyle.og:
      return 'The original Inzx layout with left-aligned track info, quick actions, and classic controls';
  }
}

/// Provider for Now Playing screen style
final nowPlayingStyleProvider =
    StateNotifierProvider<NowPlayingStyleNotifier, NowPlayingStyle>((ref) {
  return NowPlayingStyleNotifier();
});

/// Notifier to manage Now Playing screen style
class NowPlayingStyleNotifier extends StateNotifier<NowPlayingStyle> {
  static const String nowPlayingStylePrefKey = 'inzx_now_playing_style_v1';

  NowPlayingStyleNotifier() : super(NowPlayingStyle.defaultStyle) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final index = prefs.getInt(nowPlayingStylePrefKey);
      if (index != null && index >= 0 && index < NowPlayingStyle.values.length) {
        state = NowPlayingStyle.values[index];
      }
    } catch (_) {}
  }

  Future<void> setStyle(NowPlayingStyle style) async {
    state = style;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(nowPlayingStylePrefKey, style.index);
    } catch (_) {}
  }
}

/// Provider for whether the synced lyric preview line below album art is enabled
final showLyricsBelowAlbumArtProvider =
    StateNotifierProvider<ShowLyricsBelowAlbumArtNotifier, bool>((ref) {
  return ShowLyricsBelowAlbumArtNotifier();
});

/// Notifier to manage the synced lyric preview preference below album art.
/// Default: true (enabled by default).
class ShowLyricsBelowAlbumArtNotifier extends StateNotifier<bool> {
  static const String showLyricsBelowArtPrefKey =
      'inzx_show_lyrics_below_album_art';

  ShowLyricsBelowAlbumArtNotifier() : super(true) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(showLyricsBelowArtPrefKey);
      if (enabled != null) {
        state = enabled;
      }
    } catch (_) {}
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(showLyricsBelowArtPrefKey, value);
    state = value;
  }

  Future<void> toggle() => setEnabled(!state);
}

/// Provider for whether the smart audio routing pill is shown
final showSmartAudioRoutingProvider =
    StateNotifierProvider<ShowSmartAudioRoutingNotifier, bool>((ref) {
  return ShowSmartAudioRoutingNotifier();
});

/// Notifier to manage the smart audio routing visibility preference.
/// Default: true (enabled by default).
class ShowSmartAudioRoutingNotifier extends StateNotifier<bool> {
  static const String _prefKey = 'inzx_show_smart_audio_routing';

  ShowSmartAudioRoutingNotifier() : super(true) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_prefKey)) {
      state = prefs.getBool(_prefKey) ?? true;
    }
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
    state = value;
  }

  Future<void> toggle() => setEnabled(!state);
}

/// Provider for whether the app should prefer audio versions of tracks
final preferAudioVersionsProvider =
    StateNotifierProvider<PreferAudioVersionsNotifier, bool>((ref) {
  return PreferAudioVersionsNotifier();
});

/// Notifier to manage the prefer audio versions preference.
/// Default: true (enabled by default).
class PreferAudioVersionsNotifier extends StateNotifier<bool> {
  static const String _prefKey = 'inzx_prefer_audio_versions';

  PreferAudioVersionsNotifier() : super(true) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_prefKey)) {
      state = prefs.getBool(_prefKey) ?? true;
      AudioPlayerService.instance.setPreferAudioVersions(state);
    }
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
    state = value;
    AudioPlayerService.instance.setPreferAudioVersions(value);
  }

  Future<void> toggle() => setEnabled(!state);
}

/// Provider for whether the cinematic ambient reflection is only shown for animated artwork
final cinematicAmbientOnlyForAnimatedArtProvider =
    StateNotifierProvider<CinematicAmbientOnlyForAnimatedArtNotifier, bool>((ref) {
  return CinematicAmbientOnlyForAnimatedArtNotifier();
});

class CinematicAmbientOnlyForAnimatedArtNotifier extends StateNotifier<bool> {
  static const String cinematicAmbientOnlyPrefKey = 'inzx_cinematic_ambient_only_animated';

  CinematicAmbientOnlyForAnimatedArtNotifier() : super(true) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(cinematicAmbientOnlyPrefKey) ?? true; // Default to true
    } catch (_) {}
  }

  Future<void> toggle() async {
    state = !state;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(cinematicAmbientOnlyPrefKey, state);
    } catch (_) {}
  }
}

/// Provider for whether shares use native YouTube Music links instead of Inzx
/// deep links. Default: false (share Inzx links).
final shareNativeLinksProvider =
    StateNotifierProvider<ShareNativeLinksNotifier, bool>((ref) {
  return ShareNativeLinksNotifier();
});

/// Notifier for the "share YouTube Music links" preference. Mirrors the value
/// into [DeepLinkHandler.useNativeYtMusicLinks] so the static share-URL builder
/// picks it up without threading the provider through every call site.
class ShareNativeLinksNotifier extends StateNotifier<bool> {
  ShareNativeLinksNotifier() : super(false) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(DeepLinkHandler.shareNativeLinksPrefKey);
      if (enabled != null) {
        state = enabled;
        DeepLinkHandler.useNativeYtMusicLinks = enabled;
      }
    } catch (_) {}
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    DeepLinkHandler.useNativeYtMusicLinks = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(DeepLinkHandler.shareNativeLinksPrefKey, enabled);
    } catch (_) {}
  }

  Future<void> toggle() => setEnabled(!state);
}

/// Progress bar style options for the Now Playing screen
enum ProgressBarStyle {
  defaultLinear, // Classic linear slider
  waveform, // Fluid oscillating wavy progress line (Android media style)
  spectrum, // Dynamic vertical audio spectrum bars with zoom seek
}

String getProgressBarStyleName(ProgressBarStyle style) {
  switch (style) {
    case ProgressBarStyle.defaultLinear:
      return 'Default';
    case ProgressBarStyle.waveform:
      return 'Waveform';
    case ProgressBarStyle.spectrum:
      return 'Spectrum';
  }
}

String getProgressBarStyleDescription(ProgressBarStyle style) {
  switch (style) {
    case ProgressBarStyle.defaultLinear:
      return 'Classic linear slider with smooth seek knob';
    case ProgressBarStyle.waveform:
      return 'Fluid oscillating wavy line with animated playback motion';
    case ProgressBarStyle.spectrum:
      return 'Dynamic vertical audio spectrum bars with zoom seek';
  }
}

/// Provider for Progress Bar style
final progressBarStyleProvider =
    StateNotifierProvider<ProgressBarStyleNotifier, ProgressBarStyle>((ref) {
  return ProgressBarStyleNotifier();
});

/// Notifier to manage Progress Bar style
class ProgressBarStyleNotifier extends StateNotifier<ProgressBarStyle> {
  static const String progressBarStylePrefKey = 'inzx_progress_bar_style_v1';

  ProgressBarStyleNotifier() : super(ProgressBarStyle.defaultLinear) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final index = prefs.getInt(progressBarStylePrefKey);
      if (index != null &&
          index >= 0 &&
          index < ProgressBarStyle.values.length) {
        state = ProgressBarStyle.values[index];
      }
    } catch (_) {}
  }

  Future<void> setStyle(ProgressBarStyle style) async {
    state = style;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(progressBarStylePrefKey, style.index);
    } catch (_) {}
  }
}

