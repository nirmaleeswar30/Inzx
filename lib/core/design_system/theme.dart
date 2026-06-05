import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/services.dart';
import 'colors.dart';
import 'typography.dart';
import 'spacing.dart';

/// Inzx app theme configuration
/// Creates the complete ThemeData with our calm design system
class InzxTheme {
  InzxTheme._();

  /// Light theme (primary theme for Inzx)
  static ThemeData get light => lightWithAccent(InzxColors.accent);

  /// Light theme with custom accent color
  static ThemeData lightWithAccent(Color accentColor) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,

      // Colors
      colorScheme: ColorScheme.light(
        primary: accentColor,
        onPrimary: Colors.white,
        primaryContainer: InzxColors.surfaceVariant,
        onPrimaryContainer: InzxColors.textPrimary,
        secondary: InzxColors.accentSecondary,
        onSecondary: Colors.white,
        secondaryContainer: InzxColors.surfaceVariant,
        onSecondaryContainer: InzxColors.textPrimary,
        tertiary: InzxColors.accentTertiary,
        onTertiary: Colors.white,
        surface: InzxColors.surface,
        onSurface: InzxColors.textPrimary,
        surfaceContainerHighest: InzxColors.surfaceVariant,
        onSurfaceVariant: InzxColors.textSecondary,
        error: InzxColors.error,
        onError: Colors.white,
        outline: InzxColors.border,
        outlineVariant: InzxColors.divider,
        shadow: InzxColors.shadow,
      ),

      // Background
      scaffoldBackgroundColor: InzxColors.background,

      // Typography
      textTheme: createMineTextTheme().apply(
        bodyColor: InzxColors.textPrimary,
        displayColor: InzxColors.textPrimary,
      ),

      // AppBar
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: InzxColors.textPrimary,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        titleTextStyle: InzxTypography.titleLarge,
        centerTitle: false,
      ),

      // Cards
      cardTheme: CardThemeData(
        elevation: 0,
        color: InzxColors.surface,
        shape: RoundedRectangleBorder(borderRadius: InzxSpacing.cardRadius),
        margin: EdgeInsets.zero,
      ),

      // Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: accentColor,
          foregroundColor: InzxColors.contrastTextOn(accentColor),
          padding: const EdgeInsets.symmetric(
            horizontal: InzxSpacing.xl,
            vertical: InzxSpacing.base,
          ),
          shape: RoundedRectangleBorder(borderRadius: InzxSpacing.buttonRadius),
          textStyle: InzxTypography.labelLarge,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentColor,
          padding: const EdgeInsets.symmetric(
            horizontal: InzxSpacing.base,
            vertical: InzxSpacing.sm,
          ),
          shape: RoundedRectangleBorder(borderRadius: InzxSpacing.buttonRadius),
          textStyle: InzxTypography.labelLarge,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: InzxColors.textPrimary,
          side: const BorderSide(color: InzxColors.border),
          padding: const EdgeInsets.symmetric(
            horizontal: InzxSpacing.xl,
            vertical: InzxSpacing.base,
          ),
          shape: RoundedRectangleBorder(borderRadius: InzxSpacing.buttonRadius),
          textStyle: InzxTypography.labelLarge,
        ),
      ),

      // Icon buttons
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: InzxColors.textSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(InzxSpacing.radiusMd),
          ),
        ),
      ),

      // Floating Action Button
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        highlightElevation: 4,
        backgroundColor: accentColor,
        foregroundColor: InzxColors.contrastTextOn(accentColor),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(InzxSpacing.radiusBase),
        ),
      ),

      // Input fields
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: InzxColors.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: InzxSpacing.base,
          vertical: InzxSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: InzxSpacing.inputRadius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: InzxSpacing.inputRadius,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: InzxSpacing.inputRadius,
          borderSide: BorderSide(color: accentColor, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: InzxSpacing.inputRadius,
          borderSide: const BorderSide(color: InzxColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: InzxSpacing.inputRadius,
          borderSide: const BorderSide(color: InzxColors.error, width: 1.5),
        ),
        hintStyle: InzxTypography.bodyMedium.copyWith(
          color: InzxColors.textTertiary,
        ),
        labelStyle: InzxTypography.bodyMedium.copyWith(
          color: InzxColors.textSecondary,
        ),
      ),

      // Bottom Navigation
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        elevation: 0,
        backgroundColor: InzxColors.surface,
        selectedItemColor: accentColor,
        unselectedItemColor: InzxColors.textTertiary,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        selectedLabelStyle: InzxTypography.labelSmall,
        unselectedLabelStyle: InzxTypography.labelSmall,
      ),

      // Navigation Bar (Material 3)
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: InzxColors.surface,
        indicatorColor: accentColor.withValues(alpha: 0.12),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 80,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return InzxTypography.labelSmall.copyWith(color: accentColor);
          }
          return InzxTypography.labelSmall.copyWith(
            color: InzxColors.textTertiary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: accentColor, size: 24);
          }
          return const IconThemeData(color: InzxColors.textTertiary, size: 24);
        }),
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: InzxColors.divider,
        thickness: 1,
        space: 1,
      ),

      // Bottom Sheet
      bottomSheetTheme: const BottomSheetThemeData(
        elevation: 0,
        backgroundColor: InzxColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(InzxSpacing.radiusXl),
          ),
        ),
        showDragHandle: true,
        dragHandleColor: InzxColors.divider,
      ),

      // Dialog
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: InzxColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(InzxSpacing.radiusLg),
        ),
        titleTextStyle: InzxTypography.titleLarge,
        contentTextStyle: InzxTypography.bodyMedium,
      ),

      // Snackbar
      snackBarTheme: SnackBarThemeData(
        elevation: 0,
        backgroundColor: InzxColors.textPrimary,
        contentTextStyle: InzxTypography.bodyMedium.copyWith(
          color: Colors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(InzxSpacing.radiusMd),
        ),
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.all(InzxSpacing.base),
      ),

      // Chip
      chipTheme: ChipThemeData(
        elevation: 0,
        backgroundColor: InzxColors.surfaceVariant,
        selectedColor: accentColor.withValues(alpha: 0.15),
        labelStyle: InzxTypography.labelMedium,
        padding: const EdgeInsets.symmetric(
          horizontal: InzxSpacing.md,
          vertical: InzxSpacing.sm,
        ),
        shape: RoundedRectangleBorder(borderRadius: InzxSpacing.chipRadius),
      ),

      // Progress Indicator
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accentColor,
        linearTrackColor: InzxColors.surfaceVariant,
        circularTrackColor: InzxColors.surfaceVariant,
      ),

      // Slider
      sliderTheme: SliderThemeData(
        activeTrackColor: accentColor,
        inactiveTrackColor: InzxColors.surfaceVariant,
        thumbColor: accentColor,
        overlayColor: accentColor.withValues(alpha: 0.12),
        trackHeight: 4,
      ),

      // Switch
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return accentColor;
          }
          return InzxColors.surfaceVariant;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return accentColor.withValues(alpha: 0.5);
          }
          return InzxColors.border;
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),

      // Checkbox
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return accentColor;
          }
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(Colors.white),
        side: const BorderSide(color: InzxColors.border, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),

      // Radio
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return accentColor;
          }
          return InzxColors.border;
        }),
      ),

      // ListTile
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(
          horizontal: InzxSpacing.base,
          vertical: InzxSpacing.sm,
        ),
        minVerticalPadding: InzxSpacing.sm,
        horizontalTitleGap: InzxSpacing.md,
        titleTextStyle: InzxTypography.bodyLarge,
        subtitleTextStyle: InzxTypography.bodySmall,
        iconColor: InzxColors.textSecondary,
      ),

      // Tooltip
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: InzxColors.textPrimary,
          borderRadius: BorderRadius.circular(InzxSpacing.radiusSm),
        ),
        textStyle: InzxTypography.bodySmall.copyWith(color: Colors.white),
        padding: const EdgeInsets.symmetric(
          horizontal: InzxSpacing.md,
          vertical: InzxSpacing.sm,
        ),
      ),

      // Page transitions
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        },
      ),

      // Visual density
      visualDensity: VisualDensity.standard,

      // Splash
      splashFactory: InkRipple.splashFactory,
    );
  }

  /// Dark theme - calm, easy on the eyes
  static ThemeData get dark => darkWithAccent(InzxColors.darkAccent);

  /// Dark theme with custom accent color
  static ThemeData darkWithAccent(Color accentColor) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,

      // Colors
      colorScheme: ColorScheme.dark(
        primary: accentColor,
        onPrimary: Colors.white,
        primaryContainer: InzxColors.darkSurfaceVariant,
        onPrimaryContainer: InzxColors.darkTextPrimary,
        secondary: InzxColors.accentSecondary,
        onSecondary: Colors.white,
        secondaryContainer: InzxColors.darkSurfaceVariant,
        onSecondaryContainer: InzxColors.darkTextPrimary,
        tertiary: InzxColors.accentTertiary,
        onTertiary: Colors.white,
        surface: InzxColors.darkSurface,
        onSurface: InzxColors.darkTextPrimary,
        surfaceContainerHighest: InzxColors.darkSurfaceVariant,
        onSurfaceVariant: InzxColors.darkTextSecondary,
        error: InzxColors.error,
        onError: Colors.white,
        outline: InzxColors.darkBorder,
        outlineVariant: InzxColors.darkDivider,
        shadow: InzxColors.darkShadow,
      ),

      // Background
      scaffoldBackgroundColor: InzxColors.darkBackground,

      // Typography
      textTheme: createMineTextTheme().apply(
        bodyColor: InzxColors.darkTextPrimary,
        displayColor: InzxColors.darkTextPrimary,
      ),

      // AppBar
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: InzxColors.darkTextPrimary,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
          height: 1.27,
          color: InzxColors.darkTextPrimary,
        ),
        centerTitle: false,
      ),

      // Cards
      cardTheme: CardThemeData(
        elevation: 0,
        color: InzxColors.darkSurface,
        shape: RoundedRectangleBorder(borderRadius: InzxSpacing.cardRadius),
        margin: EdgeInsets.zero,
      ),

      // Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: accentColor,
          foregroundColor: InzxColors.contrastTextOn(accentColor),
          padding: const EdgeInsets.symmetric(
            horizontal: InzxSpacing.xl,
            vertical: InzxSpacing.base,
          ),
          shape: RoundedRectangleBorder(borderRadius: InzxSpacing.buttonRadius),
          textStyle: InzxTypography.labelLarge,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentColor,
          padding: const EdgeInsets.symmetric(
            horizontal: InzxSpacing.base,
            vertical: InzxSpacing.sm,
          ),
          shape: RoundedRectangleBorder(borderRadius: InzxSpacing.buttonRadius),
          textStyle: InzxTypography.labelLarge,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: InzxColors.darkTextPrimary,
          side: const BorderSide(color: InzxColors.darkBorder),
          padding: const EdgeInsets.symmetric(
            horizontal: InzxSpacing.xl,
            vertical: InzxSpacing.base,
          ),
          shape: RoundedRectangleBorder(borderRadius: InzxSpacing.buttonRadius),
          textStyle: InzxTypography.labelLarge,
        ),
      ),

      // Icon buttons
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: InzxColors.darkTextSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(InzxSpacing.radiusMd),
          ),
        ),
      ),

      // Floating Action Button
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        highlightElevation: 4,
        backgroundColor: accentColor,
        foregroundColor: InzxColors.contrastTextOn(accentColor),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(InzxSpacing.radiusBase),
        ),
      ),

      // Input fields
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: InzxColors.darkSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: InzxSpacing.base,
          vertical: InzxSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: InzxSpacing.inputRadius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: InzxSpacing.inputRadius,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: InzxSpacing.inputRadius,
          borderSide: BorderSide(color: accentColor, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: InzxSpacing.inputRadius,
          borderSide: const BorderSide(color: InzxColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: InzxSpacing.inputRadius,
          borderSide: const BorderSide(color: InzxColors.error, width: 1.5),
        ),
        hintStyle: InzxTypography.bodyMedium.copyWith(
          color: InzxColors.darkTextTertiary,
        ),
        labelStyle: InzxTypography.bodyMedium.copyWith(
          color: InzxColors.darkTextSecondary,
        ),
      ),

      // Bottom Navigation
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        elevation: 0,
        backgroundColor: InzxColors.darkSurface,
        selectedItemColor: accentColor,
        unselectedItemColor: InzxColors.darkTextTertiary,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        selectedLabelStyle: InzxTypography.labelSmall,
        unselectedLabelStyle: InzxTypography.labelSmall,
      ),

      // Navigation Bar (Material 3)
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: InzxColors.darkSurface,
        indicatorColor: accentColor.withValues(alpha: 0.2),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 80,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return InzxTypography.labelSmall.copyWith(color: accentColor);
          }
          return InzxTypography.labelSmall.copyWith(
            color: InzxColors.darkTextTertiary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: accentColor, size: 24);
          }
          return const IconThemeData(
            color: InzxColors.darkTextTertiary,
            size: 24,
          );
        }),
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: InzxColors.darkDivider,
        thickness: 1,
        space: 1,
      ),

      // Bottom Sheet
      bottomSheetTheme: const BottomSheetThemeData(
        elevation: 0,
        backgroundColor: InzxColors.darkSurfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(InzxSpacing.radiusXl),
          ),
        ),
        showDragHandle: true,
        dragHandleColor: InzxColors.darkDivider,
      ),

      // Dialog
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: InzxColors.darkSurfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(InzxSpacing.radiusLg),
        ),
        titleTextStyle: InzxTypography.titleLarge.copyWith(
          color: InzxColors.darkTextPrimary,
        ),
        contentTextStyle: InzxTypography.bodyMedium.copyWith(
          color: InzxColors.darkTextPrimary,
        ),
      ),

      // Snackbar
      snackBarTheme: SnackBarThemeData(
        elevation: 0,
        backgroundColor: InzxColors.darkSurfaceElevated,
        contentTextStyle: InzxTypography.bodyMedium.copyWith(
          color: InzxColors.darkTextPrimary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(InzxSpacing.radiusMd),
        ),
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.all(InzxSpacing.base),
      ),

      // Chip
      chipTheme: ChipThemeData(
        elevation: 0,
        backgroundColor: InzxColors.darkSurfaceVariant,
        selectedColor: accentColor.withValues(alpha: 0.25),
        labelStyle: InzxTypography.labelMedium.copyWith(
          color: InzxColors.darkTextPrimary,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: InzxSpacing.md,
          vertical: InzxSpacing.sm,
        ),
        shape: RoundedRectangleBorder(borderRadius: InzxSpacing.chipRadius),
      ),

      // Progress Indicator
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accentColor,
        linearTrackColor: InzxColors.darkSurfaceVariant,
        circularTrackColor: InzxColors.darkSurfaceVariant,
      ),

      // Slider
      sliderTheme: SliderThemeData(
        activeTrackColor: accentColor,
        inactiveTrackColor: InzxColors.darkSurfaceVariant,
        thumbColor: accentColor,
        overlayColor: accentColor.withValues(alpha: 0.2),
        trackHeight: 4,
      ),

      // Switch
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return accentColor;
          }
          return InzxColors.darkSurfaceVariant;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return accentColor.withValues(alpha: 0.5);
          }
          return InzxColors.darkBorder;
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),

      // Checkbox
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return accentColor;
          }
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(Colors.white),
        side: const BorderSide(color: InzxColors.darkBorder, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),

      // Radio
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return accentColor;
          }
          return InzxColors.darkBorder;
        }),
      ),

      // ListTile
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: InzxSpacing.base,
          vertical: InzxSpacing.sm,
        ),
        minVerticalPadding: InzxSpacing.sm,
        horizontalTitleGap: InzxSpacing.md,
        titleTextStyle: InzxTypography.bodyLarge.copyWith(
          color: InzxColors.darkTextPrimary,
        ),
        subtitleTextStyle: InzxTypography.bodySmall.copyWith(
          color: InzxColors.darkTextSecondary,
        ),
        iconColor: InzxColors.darkTextSecondary,
      ),

      // Tooltip
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: InzxColors.darkSurfaceElevated,
          borderRadius: BorderRadius.circular(InzxSpacing.radiusSm),
        ),
        textStyle: InzxTypography.bodySmall.copyWith(
          color: InzxColors.darkTextPrimary,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: InzxSpacing.md,
          vertical: InzxSpacing.sm,
        ),
      ),

      // Page transitions
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        },
      ),

      // Visual density
      visualDensity: VisualDensity.standard,

      // Splash
      splashFactory: InkRipple.splashFactory,
    );
  }

  /// WindDown theme (warm grayscale for evening) - Light
  static ThemeData get windDown {
    return light.copyWith(
      scaffoldBackgroundColor: InzxColors.windDownBackground,
      colorScheme: light.colorScheme.copyWith(
        surface: InzxColors.windDownSurface,
        onSurface: InzxColors.windDownText,
      ),
      cardTheme: light.cardTheme.copyWith(color: InzxColors.windDownSurface),
    );
  }

  /// WindDown theme (warm grayscale for evening) - Dark
  static ThemeData get windDownDark {
    return dark.copyWith(
      scaffoldBackgroundColor: InzxColors.darkWindDownBackground,
      colorScheme: dark.colorScheme.copyWith(
        surface: InzxColors.darkWindDownSurface,
        onSurface: InzxColors.darkWindDownText,
      ),
      cardTheme: dark.cardTheme.copyWith(color: InzxColors.darkWindDownSurface),
    );
  }
}
