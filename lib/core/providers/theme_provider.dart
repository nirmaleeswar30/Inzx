import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import '../design_system/colors.dart';

/// Theme mode options for the app
enum MineThemeMode { system, light, dark }

/// Available accent color options
enum MineAccentColor {
  red, // AMOLED red - default
  sage, // Sage green
  lavender, // Soft lavender
  peach, // Warm peach
  ocean, // Ocean blue
  rose, // Soft rose
  amber, // Warm amber
  mint, // Fresh mint
  coral, // Soft coral
}

/// Get the Color value for an accent color option
Color getAccentColor(MineAccentColor accent, {bool isDark = false}) {
  switch (accent) {
    case MineAccentColor.red:
      return isDark ? const Color(0xFFE53935) : const Color(0xFFD32F2F);
    case MineAccentColor.sage:
      return isDark ? const Color(0xFF8FD4B6) : MineColors.accent;
    case MineAccentColor.lavender:
      return isDark ? const Color(0xFFB8B4DE) : MineColors.accentSecondary;
    case MineAccentColor.peach:
      return isDark ? const Color(0xFFF8C4B0) : MineColors.accentTertiary;
    case MineAccentColor.ocean:
      return isDark ? const Color(0xFF7BC4E8) : const Color(0xFF7BC4E8);
    case MineAccentColor.rose:
      return isDark ? const Color(0xFFE4B5B5) : const Color(0xFFE4B5B5);
    case MineAccentColor.amber:
      return isDark ? const Color(0xFFF8D08D) : const Color(0xFFF8D08D);
    case MineAccentColor.mint:
      return isDark ? const Color(0xFF8FE4C8) : const Color(0xFF7DD4B8);
    case MineAccentColor.coral:
      return isDark ? const Color(0xFFF8C4B0) : const Color(0xFFF8C4B0);
  }
}

/// Get the display name for an accent color
String getAccentColorName(MineAccentColor accent) {
  switch (accent) {
    case MineAccentColor.red:
      return 'Red';
    case MineAccentColor.sage:
      return 'Sage Green';
    case MineAccentColor.lavender:
      return 'Lavender';
    case MineAccentColor.peach:
      return 'Peach';
    case MineAccentColor.ocean:
      return 'Ocean Blue';
    case MineAccentColor.rose:
      return 'Rose';
    case MineAccentColor.amber:
      return 'Amber';
    case MineAccentColor.mint:
      return 'Mint';
    case MineAccentColor.coral:
      return 'Coral';
  }
}

/// Provider for the current accent color
final accentColorProvider =
    StateNotifierProvider<AccentColorNotifier, MineAccentColor>((ref) {
      return AccentColorNotifier();
    });

/// Notifier to manage accent color state
class AccentColorNotifier extends StateNotifier<MineAccentColor> {
  AccentColorNotifier() : super(MineAccentColor.red); // Default to red

  void setAccentColor(MineAccentColor color) {
    state = color;
  }
}

/// Provider for the current theme mode
final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, MineThemeMode>((ref) {
      return ThemeModeNotifier();
    });

/// Notifier to manage theme mode state
class ThemeModeNotifier extends StateNotifier<MineThemeMode> {
  ThemeModeNotifier() : super(MineThemeMode.dark); // Default to dark mode

  void setThemeMode(MineThemeMode mode) {
    state = mode;
  }

  void toggleTheme() {
    switch (state) {
      case MineThemeMode.system:
        state = MineThemeMode.light;
        break;
      case MineThemeMode.light:
        state = MineThemeMode.dark;
        break;
      case MineThemeMode.dark:
        state = MineThemeMode.system;
        break;
    }
  }
}

/// Convert MineThemeMode to Flutter's ThemeMode
ThemeMode toFlutterThemeMode(MineThemeMode mode) {
  switch (mode) {
    case MineThemeMode.system:
      return ThemeMode.system;
    case MineThemeMode.light:
      return ThemeMode.light;
    case MineThemeMode.dark:
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
