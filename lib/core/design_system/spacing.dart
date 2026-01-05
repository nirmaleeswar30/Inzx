import 'package:flutter/material.dart';

/// Mine app spacing system
/// Generous spacing for a calm, breathable UI
class MineSpacing {
  MineSpacing._();

  // ─────────────────────────────────────────────────────────────────
  // BASE SPACING SCALE (4px base unit)
  // ─────────────────────────────────────────────────────────────────

  /// 4px - Minimal spacing
  static const double xs = 4;
  
  /// 8px - Tight spacing
  static const double sm = 8;
  
  /// 12px - Compact spacing
  static const double md = 12;
  
  /// 16px - Default spacing
  static const double base = 16;
  
  /// 20px - Comfortable spacing
  static const double lg = 20;
  
  /// 24px - Generous spacing
  static const double xl = 24;
  
  /// 32px - Extra generous
  static const double xxl = 32;
  
  /// 40px - Section spacing
  static const double xxxl = 40;
  
  /// 48px - Large section spacing
  static const double huge = 48;
  
  /// 64px - Hero spacing
  static const double hero = 64;

  // ─────────────────────────────────────────────────────────────────
  // SEMANTIC SPACING
  // ─────────────────────────────────────────────────────────────────

  /// Spacing between cards
  static const double cardGap = 16;
  
  /// Padding inside cards
  static const double cardPadding = 20;
  
  /// Screen horizontal padding
  static const double screenPaddingH = 24;
  
  /// Screen vertical padding
  static const double screenPaddingV = 16;
  
  /// Spacing between list items
  static const double listItemGap = 12;
  
  /// Spacing between sections
  static const double sectionGap = 32;
  
  /// Icon to text spacing
  static const double iconTextGap = 12;
  
  /// Button content padding
  static const double buttonPadding = 16;

  // ─────────────────────────────────────────────────────────────────
  // BORDER RADIUS (rounded corners 24dp as specified)
  // ─────────────────────────────────────────────────────────────────

  /// Small radius - for chips, tags
  static const double radiusSm = 8;
  
  /// Medium radius - for buttons
  static const double radiusMd = 12;
  
  /// Default radius - for most elements
  static const double radiusBase = 16;
  
  /// Large radius - for cards (as per spec)
  static const double radiusLg = 24;
  
  /// Extra large radius - for sheets and modals
  static const double radiusXl = 32;
  
  /// Full radius - for circular elements
  static const double radiusFull = 999;

  // ─────────────────────────────────────────────────────────────────
  // COMMONLY USED EDGE INSETS
  // ─────────────────────────────────────────────────────────────────

  /// Standard screen padding
  static const EdgeInsets screenPadding = EdgeInsets.symmetric(
    horizontal: screenPaddingH,
    vertical: screenPaddingV,
  );

  /// Standard card padding
  static const EdgeInsets cardPaddingAll = EdgeInsets.all(cardPadding);

  /// Horizontal only padding
  static const EdgeInsets horizontalPadding = EdgeInsets.symmetric(
    horizontal: screenPaddingH,
  );

  /// Small padding all around
  static const EdgeInsets smallPadding = EdgeInsets.all(sm);

  /// Medium padding all around
  static const EdgeInsets mediumPadding = EdgeInsets.all(base);

  // ─────────────────────────────────────────────────────────────────
  // COMMONLY USED BORDER RADIUS
  // ─────────────────────────────────────────────────────────────────

  /// Card border radius
  static BorderRadius cardRadius = BorderRadius.circular(radiusLg);

  /// Button border radius
  static BorderRadius buttonRadius = BorderRadius.circular(radiusMd);

  /// Chip border radius
  static BorderRadius chipRadius = BorderRadius.circular(radiusSm);

  /// Sheet border radius (top only)
  static BorderRadius sheetRadius = const BorderRadius.vertical(
    top: Radius.circular(radiusXl),
  );

  /// Input field border radius
  static BorderRadius inputRadius = BorderRadius.circular(radiusMd);
}

/// Extension for easy spacing access
extension MineSpacingExtension on num {
  /// Horizontal space
  SizedBox get w => SizedBox(width: toDouble());
  
  /// Vertical space
  SizedBox get h => SizedBox(height: toDouble());
}
