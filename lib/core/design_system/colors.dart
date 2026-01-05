import 'package:flutter/material.dart';

/// Mine app color palette
/// Calm, minimal, premium aesthetic with soft whites and muted accents
class MineColors {
  MineColors._();

  // ─────────────────────────────────────────────────────────────────
  // BASE COLORS
  // ─────────────────────────────────────────────────────────────────

  /// Soft white background - the primary canvas
  static const Color background = Color(0xFFFAFAFA);
  
  /// Pure white for cards and elevated surfaces
  static const Color surface = Color(0xFFFFFFFF);
  
  /// Slightly warm white for secondary surfaces
  static const Color surfaceVariant = Color(0xFFF5F5F5);

  // ─────────────────────────────────────────────────────────────────
  // TEXT COLORS
  // ─────────────────────────────────────────────────────────────────

  /// Primary text - soft black, not harsh
  static const Color textPrimary = Color(0xFF1A1A1A);
  
  /// Secondary text - muted gray
  static const Color textSecondary = Color(0xFF6B6B6B);
  
  /// Tertiary text - very subtle
  static const Color textTertiary = Color(0xFF9E9E9E);
  
  /// Disabled text
  static const Color textDisabled = Color(0xFFBDBDBD);

  // ─────────────────────────────────────────────────────────────────
  // ACCENT COLORS - Muted, calm tones
  // ─────────────────────────────────────────────────────────────────

  /// Primary accent - calm sage green
  static const Color accent = Color(0xFF7CB69D);
  
  /// Accent variant - slightly darker sage
  static const Color accentVariant = Color(0xFF5A9E7E);
  
  /// Secondary accent - soft lavender
  static const Color accentSecondary = Color(0xFFA8A4CE);
  
  /// Tertiary accent - warm peach
  static const Color accentTertiary = Color(0xFFE8B4A0);

  // ─────────────────────────────────────────────────────────────────
  // MODULE ACCENT COLORS
  // ─────────────────────────────────────────────────────────────────

  /// Home - warm neutral
  static const Color homeAccent = Color(0xFFE8DCD0);
  
  /// Money - calm green
  static const Color moneyAccent = Color(0xFF7CB69D);
  
  /// Water - soft blue
  static const Color waterAccent = Color(0xFF89B4D4);
  
  /// Papers - warm gray
  static const Color papersAccent = Color(0xFFB8AFA6);
  
  /// Wardrobe - soft rose
  static const Color wardrobeAccent = Color(0xFFD4A5A5);
  
  /// SleepStop - warm amber
  static const Color sleepStopAccent = Color(0xFFE8C07D);
  
  /// Dates - soft coral
  static const Color datesAccent = Color(0xFFE8B4A0);
  
  /// Rain - muted blue
  static const Color rainAccent = Color(0xFF8BA6C1);
  
  /// WindDown - deep lavender
  static const Color windDownAccent = Color(0xFFA8A4CE);

  // ─────────────────────────────────────────────────────────────────
  // SEMANTIC COLORS
  // ─────────────────────────────────────────────────────────────────

  /// Success - calm green
  static const Color success = Color(0xFF7CB69D);
  
  /// Warning - soft amber
  static const Color warning = Color(0xFFE8C07D);
  
  /// Error - muted coral (not harsh red)
  static const Color error = Color(0xFFD4847C);
  
  /// Info - soft blue
  static const Color info = Color(0xFF89B4D4);

  // ─────────────────────────────────────────────────────────────────
  // UTILITY COLORS
  // ─────────────────────────────────────────────────────────────────

  /// Divider - very subtle
  static const Color divider = Color(0xFFEEEEEE);
  
  /// Border - soft gray
  static const Color border = Color(0xFFE0E0E0);
  
  /// Overlay - for modals and sheets
  static const Color overlay = Color(0x1A000000);
  
  /// Shadow color
  static const Color shadow = Color(0x0A000000);

  // ─────────────────────────────────────────────────────────────────
  // WINDDOWN / GRAYSCALE MODE (for evening)
  // ─────────────────────────────────────────────────────────────────

  /// Warm grayscale background
  static const Color windDownBackground = Color(0xFFF5F0EB);
  
  /// Warm grayscale surface
  static const Color windDownSurface = Color(0xFFFAF7F4);
  
  /// Warm grayscale text
  static const Color windDownText = Color(0xFF4A4540);

  // ─────────────────────────────────────────────────────────────────
  // DARK THEME COLORS - TRUE AMOLED BLACK
  // ─────────────────────────────────────────────────────────────────

  /// Dark background - pure AMOLED black
  static const Color darkBackground = Color(0xFF000000);
  
  /// Dark surface - very subtle elevation
  static const Color darkSurface = Color(0xFF0A0A0A);
  
  /// Dark surface variant - for cards and containers
  static const Color darkSurfaceVariant = Color(0xFF141414);
  
  /// Dark elevated surface - for modal sheets
  static const Color darkSurfaceElevated = Color(0xFF1A1A1A);

  /// Dark text primary - pure white for contrast
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  
  /// Dark text secondary - softer white
  static const Color darkTextSecondary = Color(0xFFB3B3B3);
  
  /// Dark text tertiary
  static const Color darkTextTertiary = Color(0xFF666666);
  
  /// Dark text disabled
  static const Color darkTextDisabled = Color(0xFF404040);

  /// Dark divider - very subtle
  static const Color darkDivider = Color(0xFF1A1A1A);
  
  /// Dark border - subtle edge
  static const Color darkBorder = Color(0xFF262626);
  
  /// Dark overlay
  static const Color darkOverlay = Color(0x80000000);
  
  /// Dark shadow
  static const Color darkShadow = Color(0x00000000);

  // ─────────────────────────────────────────────────────────────────
  // DARK THEME ACCENT COLORS - Brighter for dark backgrounds
  // ─────────────────────────────────────────────────────────────────

  /// Dark mode primary accent - brighter sage green
  static const Color darkAccent = Color(0xFF8FD4B6);
  
  /// Dark mode money accent - brighter green
  static const Color darkMoneyAccent = Color(0xFF8FD4B6);
  
  /// Dark mode water accent - brighter blue
  static const Color darkWaterAccent = Color(0xFF7BC4E8);
  
  /// Dark mode papers accent - brighter warm gray
  static const Color darkPapersAccent = Color(0xFFD4C9BE);
  
  /// Dark mode wardrobe accent - brighter rose
  static const Color darkWardrobeAccent = Color(0xFFE8B8B8);
  
  /// Dark mode sleepstop accent - brighter amber
  static const Color darkSleepStopAccent = Color(0xFFF5D490);
  
  /// Dark mode dates accent - brighter coral
  static const Color darkDatesAccent = Color(0xFFF5C9B8);
  
  /// Dark mode rain accent - brighter blue
  static const Color darkRainAccent = Color(0xFFA3C4E0);
  
  /// Dark mode winddown accent - brighter lavender
  static const Color darkWindDownAccent = Color(0xFFC4C0E8);

  // ─────────────────────────────────────────────────────────────────
  // DARK WINDDOWN / GRAYSCALE MODE (for evening)
  // ─────────────────────────────────────────────────────────────────

  /// Dark warm grayscale background
  static const Color darkWindDownBackground = Color(0xFF080604);
  
  /// Dark warm grayscale surface
  static const Color darkWindDownSurface = Color(0xFF121008);
  
  /// Dark warm grayscale text
  static const Color darkWindDownText = Color(0xFFE8E0D8);
}

/// Extension to easily access colors from BuildContext
extension MineColorsExtension on BuildContext {
  MineColors get colors => MineColors._();
}
