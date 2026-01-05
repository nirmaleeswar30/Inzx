import 'package:flutter/material.dart';

/// Mine app typography system
/// Clean, readable, with generous line heights for a calm reading experience
class MineTypography {
  MineTypography._();

  // ─────────────────────────────────────────────────────────────────
  // FONT FAMILY
  // ─────────────────────────────────────────────────────────────────

  /// Primary font - using system font for now
  /// Can be replaced with Inter or SF Pro when added as assets
  static const String fontFamily = 'Inter';

  // ─────────────────────────────────────────────────────────────────
  // DISPLAY STYLES - For big hero numbers (safe-to-spend, water %)
  // ─────────────────────────────────────────────────────────────────

  static const TextStyle displayLarge = TextStyle(
    fontSize: 57,
    fontWeight: FontWeight.w300,
    letterSpacing: -0.5,
    height: 1.12,
  );

  static const TextStyle displayMedium = TextStyle(
    fontSize: 45,
    fontWeight: FontWeight.w300,
    letterSpacing: -0.25,
    height: 1.16,
  );

  static const TextStyle displaySmall = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.22,
  );

  // ─────────────────────────────────────────────────────────────────
  // HEADLINE STYLES - For section titles
  // ─────────────────────────────────────────────────────────────────

  static const TextStyle headlineLarge = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    height: 1.25,
  );

  static const TextStyle headlineMedium = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    height: 1.29,
  );

  static const TextStyle headlineSmall = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    height: 1.33,
  );

  // ─────────────────────────────────────────────────────────────────
  // TITLE STYLES - For card titles and list headers
  // ─────────────────────────────────────────────────────────────────

  static const TextStyle titleLarge = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    height: 1.27,
  );

  static const TextStyle titleMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.15,
    height: 1.5,
  );

  static const TextStyle titleSmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    height: 1.43,
  );

  // ─────────────────────────────────────────────────────────────────
  // BODY STYLES - For regular content
  // ─────────────────────────────────────────────────────────────────

  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.15,
    height: 1.5,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.25,
    height: 1.43,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.4,
    height: 1.33,
  );

  // ─────────────────────────────────────────────────────────────────
  // LABEL STYLES - For buttons, chips, and small UI elements
  // ─────────────────────────────────────────────────────────────────

  static const TextStyle labelLarge = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    height: 1.43,
  );

  static const TextStyle labelMedium = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
    height: 1.33,
  );

  static const TextStyle labelSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
    height: 1.45,
  );

  // ─────────────────────────────────────────────────────────────────
  // SPECIAL STYLES
  // ─────────────────────────────────────────────────────────────────

  /// Big friendly number (e.g., safe-to-spend amount)
  static const TextStyle bigNumber = TextStyle(
    fontSize: 64,
    fontWeight: FontWeight.w200,
    letterSpacing: -1,
    height: 1.1,
  );

  /// Module card title on home screen
  static const TextStyle cardTitle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
    height: 1.4,
  );

  /// Countdown timer style
  static const TextStyle countdown = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w300,
    letterSpacing: 2,
    height: 1.2,
  );

  /// Greeting text (Good morning, etc.)
  static const TextStyle greeting = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w300,
    letterSpacing: 0,
    height: 1.3,
  );
}

/// Creates the TextTheme for the app
TextTheme createMineTextTheme() {
  return const TextTheme(
    displayLarge: MineTypography.displayLarge,
    displayMedium: MineTypography.displayMedium,
    displaySmall: MineTypography.displaySmall,
    headlineLarge: MineTypography.headlineLarge,
    headlineMedium: MineTypography.headlineMedium,
    headlineSmall: MineTypography.headlineSmall,
    titleLarge: MineTypography.titleLarge,
    titleMedium: MineTypography.titleMedium,
    titleSmall: MineTypography.titleSmall,
    bodyLarge: MineTypography.bodyLarge,
    bodyMedium: MineTypography.bodyMedium,
    bodySmall: MineTypography.bodySmall,
    labelLarge: MineTypography.labelLarge,
    labelMedium: MineTypography.labelMedium,
    labelSmall: MineTypography.labelSmall,
  );
}
