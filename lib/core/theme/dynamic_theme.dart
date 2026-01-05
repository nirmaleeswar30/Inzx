import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Theme mode enum
enum AppThemeMode { system, light, dark }

/// Color scheme source
enum ColorSchemeSource {
  materialYou, // Dynamic from wallpaper
  custom, // User-selected accent
  albumArt, // From now playing album art
}

/// Theme settings state
class ThemeSettings {
  final AppThemeMode themeMode;
  final ColorSchemeSource colorSource;
  final Color? customAccentColor;
  final bool usePureBlack; // AMOLED black for dark theme
  final bool useHighContrast;

  const ThemeSettings({
    this.themeMode = AppThemeMode.dark, // Default to dark mode
    this.colorSource = ColorSchemeSource.custom, // Use custom accent
    this.customAccentColor = const Color(0xFFE53935), // Red accent
    this.usePureBlack = true, // AMOLED black by default
    this.useHighContrast = false,
  });

  ThemeSettings copyWith({
    AppThemeMode? themeMode,
    ColorSchemeSource? colorSource,
    Color? customAccentColor,
    bool? usePureBlack,
    bool? useHighContrast,
  }) => ThemeSettings(
    themeMode: themeMode ?? this.themeMode,
    colorSource: colorSource ?? this.colorSource,
    customAccentColor: customAccentColor ?? this.customAccentColor,
    usePureBlack: usePureBlack ?? this.usePureBlack,
    useHighContrast: useHighContrast ?? this.useHighContrast,
  );

  Map<String, dynamic> toJson() => {
    'themeMode': themeMode.index,
    'colorSource': colorSource.index,
    'customAccentColor': customAccentColor?.value,
    'usePureBlack': usePureBlack,
    'useHighContrast': useHighContrast,
  };

  factory ThemeSettings.fromJson(Map<String, dynamic> json) => ThemeSettings(
    themeMode: AppThemeMode.values[json['themeMode'] as int? ?? 0],
    colorSource: ColorSchemeSource.values[json['colorSource'] as int? ?? 0],
    customAccentColor: json['customAccentColor'] != null
        ? Color(json['customAccentColor'] as int)
        : null,
    usePureBlack: json['usePureBlack'] as bool? ?? false,
    useHighContrast: json['useHighContrast'] as bool? ?? false,
  );
}

/// Theme settings notifier
class ThemeSettingsNotifier extends StateNotifier<ThemeSettings> {
  ThemeSettingsNotifier() : super(const ThemeSettings()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('theme_settings');
    if (jsonStr != null) {
      try {
        state = ThemeSettings.fromJson(
          Map<String, dynamic>.from(jsonDecode(jsonStr)),
        );
      } catch (_) {}
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(state.toJson());
    await prefs.setString('theme_settings', jsonStr);
  }

  void setThemeMode(AppThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    _save();
  }

  void setColorSource(ColorSchemeSource source) {
    state = state.copyWith(colorSource: source);
    _save();
  }

  void setCustomAccentColor(Color color) {
    state = state.copyWith(
      colorSource: ColorSchemeSource.custom,
      customAccentColor: color,
    );
    _save();
  }

  void togglePureBlack() {
    state = state.copyWith(usePureBlack: !state.usePureBlack);
    _save();
  }

  void toggleHighContrast() {
    state = state.copyWith(useHighContrast: !state.useHighContrast);
    _save();
  }
}

/// Provider for theme settings
final themeSettingsProvider =
    StateNotifierProvider<ThemeSettingsNotifier, ThemeSettings>((ref) {
      return ThemeSettingsNotifier();
    });

/// Accent colors palette
const List<Color> accentColorPalette = [
  Colors.blue,
  Colors.purple,
  Colors.deepPurple,
  Colors.indigo,
  Colors.cyan,
  Colors.teal,
  Colors.green,
  Colors.lightGreen,
  Colors.lime,
  Colors.amber,
  Colors.orange,
  Colors.deepOrange,
  Colors.red,
  Colors.pink,
  Colors.brown,
  Colors.blueGrey,
];

/// Build theme data based on settings
ThemeData buildTheme({
  required ThemeSettings settings,
  required Brightness brightness,
  ColorScheme? dynamicColorScheme,
  Color? albumArtColor,
}) {
  final isDark = brightness == Brightness.dark;

  // Determine seed color
  Color seedColor;
  switch (settings.colorSource) {
    case ColorSchemeSource.materialYou:
      seedColor = dynamicColorScheme?.primary ?? Colors.blue;
      break;
    case ColorSchemeSource.custom:
      seedColor = settings.customAccentColor ?? Colors.blue;
      break;
    case ColorSchemeSource.albumArt:
      seedColor = albumArtColor ?? Colors.blue;
      break;
  }

  // Generate color scheme
  final colorScheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
  );

  // Background color
  Color backgroundColor;
  if (isDark) {
    backgroundColor = settings.usePureBlack
        ? Colors.black
        : const Color(0xFF121212);
  } else {
    backgroundColor = Colors.white;
  }

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme.copyWith(surface: backgroundColor),
    scaffoldBackgroundColor: backgroundColor,
    brightness: brightness,

    // App bar
    appBarTheme: AppBarTheme(
      backgroundColor: backgroundColor,
      foregroundColor: isDark ? Colors.white : Colors.black,
      elevation: 0,
      centerTitle: false,
    ),

    // Bottom navigation
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: backgroundColor,
      selectedItemColor: colorScheme.primary,
      unselectedItemColor: isDark ? Colors.white54 : Colors.black45,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),

    // Cards
    cardTheme: CardThemeData(
      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),

    // Chips
    chipTheme: ChipThemeData(
      backgroundColor: isDark
          ? Colors.white.withValues(alpha: 0.1)
          : Colors.grey.shade200,
      selectedColor: colorScheme.primary.withValues(alpha: 0.2),
      labelStyle: TextStyle(color: isDark ? Colors.white : Colors.black87),
    ),

    // Sliders
    sliderTheme: SliderThemeData(
      activeTrackColor: colorScheme.primary,
      inactiveTrackColor: isDark ? Colors.white24 : Colors.grey.shade300,
      thumbColor: colorScheme.primary,
      overlayColor: colorScheme.primary.withValues(alpha: 0.2),
      trackHeight: 4,
    ),

    // Buttons
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),

    // Text
    textTheme: TextTheme(
      displayLarge: TextStyle(
        fontWeight: FontWeight.bold,
        color: isDark ? Colors.white : Colors.black,
      ),
      headlineMedium: TextStyle(
        fontWeight: FontWeight.bold,
        color: isDark ? Colors.white : Colors.black,
      ),
      bodyLarge: TextStyle(color: isDark ? Colors.white : Colors.black87),
      bodyMedium: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
    ),

    // Icons
    iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black87),

    // Dividers
    dividerTheme: DividerThemeData(
      color: isDark ? Colors.white12 : Colors.grey.shade200,
      thickness: 1,
    ),

    // Dialogs
    dialogTheme: DialogThemeData(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),

    // Bottom sheets
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),

    // Snackbars
    snackBarTheme: SnackBarThemeData(
      backgroundColor: isDark ? Colors.white : Colors.grey.shade900,
      contentTextStyle: TextStyle(color: isDark ? Colors.black : Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
