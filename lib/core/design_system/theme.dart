import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'colors.dart';
import 'typography.dart';
import 'spacing.dart';

/// Mine app theme configuration
/// Creates the complete ThemeData with our calm design system
class MineTheme {
  MineTheme._();

  /// Light theme (primary theme for Mine)
  static ThemeData get light => lightWithAccent(MineColors.accent);
  
  /// Light theme with custom accent color
  static ThemeData lightWithAccent(Color accentColor) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      
      // Colors
      colorScheme: ColorScheme.light(
        primary: accentColor,
        onPrimary: Colors.white,
        primaryContainer: MineColors.surfaceVariant,
        onPrimaryContainer: MineColors.textPrimary,
        secondary: MineColors.accentSecondary,
        onSecondary: Colors.white,
        secondaryContainer: MineColors.surfaceVariant,
        onSecondaryContainer: MineColors.textPrimary,
        tertiary: MineColors.accentTertiary,
        onTertiary: Colors.white,
        surface: MineColors.surface,
        onSurface: MineColors.textPrimary,
        surfaceContainerHighest: MineColors.surfaceVariant,
        onSurfaceVariant: MineColors.textSecondary,
        error: MineColors.error,
        onError: Colors.white,
        outline: MineColors.border,
        outlineVariant: MineColors.divider,
        shadow: MineColors.shadow,
      ),
      
      // Background
      scaffoldBackgroundColor: MineColors.background,
      
      // Typography
      textTheme: createMineTextTheme().apply(
        bodyColor: MineColors.textPrimary,
        displayColor: MineColors.textPrimary,
      ),
      
      // AppBar
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: MineColors.textPrimary,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        titleTextStyle: MineTypography.titleLarge,
        centerTitle: false,
      ),
      
      // Cards
      cardTheme: CardThemeData(
        elevation: 0,
        color: MineColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: MineSpacing.cardRadius,
        ),
        margin: EdgeInsets.zero,
      ),
      
      // Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: accentColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(
            horizontal: MineSpacing.xl,
            vertical: MineSpacing.base,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: MineSpacing.buttonRadius,
          ),
          textStyle: MineTypography.labelLarge,
        ),
      ),
      
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentColor,
          padding: const EdgeInsets.symmetric(
            horizontal: MineSpacing.base,
            vertical: MineSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: MineSpacing.buttonRadius,
          ),
          textStyle: MineTypography.labelLarge,
        ),
      ),
      
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: MineColors.textPrimary,
          side: const BorderSide(color: MineColors.border),
          padding: const EdgeInsets.symmetric(
            horizontal: MineSpacing.xl,
            vertical: MineSpacing.base,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: MineSpacing.buttonRadius,
          ),
          textStyle: MineTypography.labelLarge,
        ),
      ),
      
      // Icon buttons
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: MineColors.textSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MineSpacing.radiusMd),
          ),
        ),
      ),
      
      // Floating Action Button
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        highlightElevation: 4,
        backgroundColor: accentColor,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MineSpacing.radiusBase),
        ),
      ),
      
      // Input fields
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: MineColors.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: MineSpacing.base,
          vertical: MineSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: MineSpacing.inputRadius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: MineSpacing.inputRadius,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: MineSpacing.inputRadius,
          borderSide: BorderSide(
            color: accentColor,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: MineSpacing.inputRadius,
          borderSide: const BorderSide(
            color: MineColors.error,
            width: 1,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: MineSpacing.inputRadius,
          borderSide: const BorderSide(
            color: MineColors.error,
            width: 1.5,
          ),
        ),
        hintStyle: MineTypography.bodyMedium.copyWith(
          color: MineColors.textTertiary,
        ),
        labelStyle: MineTypography.bodyMedium.copyWith(
          color: MineColors.textSecondary,
        ),
      ),
      
      // Bottom Navigation
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        elevation: 0,
        backgroundColor: MineColors.surface,
        selectedItemColor: accentColor,
        unselectedItemColor: MineColors.textTertiary,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        selectedLabelStyle: MineTypography.labelSmall,
        unselectedLabelStyle: MineTypography.labelSmall,
      ),
      
      // Navigation Bar (Material 3)
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: MineColors.surface,
        indicatorColor: accentColor.withValues(alpha: 0.12),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 80,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return MineTypography.labelSmall.copyWith(
              color: accentColor,
            );
          }
          return MineTypography.labelSmall.copyWith(
            color: MineColors.textTertiary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(
              color: accentColor,
              size: 24,
            );
          }
          return const IconThemeData(
            color: MineColors.textTertiary,
            size: 24,
          );
        }),
      ),
      
      // Divider
      dividerTheme: const DividerThemeData(
        color: MineColors.divider,
        thickness: 1,
        space: 1,
      ),
      
      // Bottom Sheet
      bottomSheetTheme: const BottomSheetThemeData(
        elevation: 0,
        backgroundColor: MineColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(MineSpacing.radiusXl),
          ),
        ),
        showDragHandle: true,
        dragHandleColor: MineColors.divider,
      ),
      
      // Dialog
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: MineColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MineSpacing.radiusLg),
        ),
        titleTextStyle: MineTypography.titleLarge,
        contentTextStyle: MineTypography.bodyMedium,
      ),
      
      // Snackbar
      snackBarTheme: SnackBarThemeData(
        elevation: 0,
        backgroundColor: MineColors.textPrimary,
        contentTextStyle: MineTypography.bodyMedium.copyWith(
          color: Colors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MineSpacing.radiusMd),
        ),
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.all(MineSpacing.base),
      ),
      
      // Chip
      chipTheme: ChipThemeData(
        elevation: 0,
        backgroundColor: MineColors.surfaceVariant,
        selectedColor: accentColor.withValues(alpha: 0.15),
        labelStyle: MineTypography.labelMedium,
        padding: const EdgeInsets.symmetric(
          horizontal: MineSpacing.md,
          vertical: MineSpacing.sm,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: MineSpacing.chipRadius,
        ),
      ),
      
      // Progress Indicator
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accentColor,
        linearTrackColor: MineColors.surfaceVariant,
        circularTrackColor: MineColors.surfaceVariant,
      ),
      
      // Slider
      sliderTheme: SliderThemeData(
        activeTrackColor: accentColor,
        inactiveTrackColor: MineColors.surfaceVariant,
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
          return MineColors.surfaceVariant;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return accentColor.withValues(alpha: 0.5);
          }
          return MineColors.border;
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
        side: const BorderSide(color: MineColors.border, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      
      // Radio
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return accentColor;
          }
          return MineColors.border;
        }),
      ),
      
      // ListTile
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(
          horizontal: MineSpacing.base,
          vertical: MineSpacing.sm,
        ),
        minVerticalPadding: MineSpacing.sm,
        horizontalTitleGap: MineSpacing.md,
        titleTextStyle: MineTypography.bodyLarge,
        subtitleTextStyle: MineTypography.bodySmall,
        iconColor: MineColors.textSecondary,
      ),
      
      // Tooltip
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: MineColors.textPrimary,
          borderRadius: BorderRadius.circular(MineSpacing.radiusSm),
        ),
        textStyle: MineTypography.bodySmall.copyWith(
          color: Colors.white,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: MineSpacing.md,
          vertical: MineSpacing.sm,
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
  static ThemeData get dark => darkWithAccent(MineColors.darkAccent);
  
  /// Dark theme with custom accent color
  static ThemeData darkWithAccent(Color accentColor) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      
      // Colors
      colorScheme: ColorScheme.dark(
        primary: accentColor,
        onPrimary: Colors.white,
        primaryContainer: MineColors.darkSurfaceVariant,
        onPrimaryContainer: MineColors.darkTextPrimary,
        secondary: MineColors.accentSecondary,
        onSecondary: Colors.white,
        secondaryContainer: MineColors.darkSurfaceVariant,
        onSecondaryContainer: MineColors.darkTextPrimary,
        tertiary: MineColors.accentTertiary,
        onTertiary: Colors.white,
        surface: MineColors.darkSurface,
        onSurface: MineColors.darkTextPrimary,
        surfaceContainerHighest: MineColors.darkSurfaceVariant,
        onSurfaceVariant: MineColors.darkTextSecondary,
        error: MineColors.error,
        onError: Colors.white,
        outline: MineColors.darkBorder,
        outlineVariant: MineColors.darkDivider,
        shadow: MineColors.darkShadow,
      ),
      
      // Background
      scaffoldBackgroundColor: MineColors.darkBackground,
      
      // Typography
      textTheme: createMineTextTheme().apply(
        bodyColor: MineColors.darkTextPrimary,
        displayColor: MineColors.darkTextPrimary,
      ),
      
      // AppBar
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: MineColors.darkTextPrimary,
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
          color: MineColors.darkTextPrimary,
        ),
        centerTitle: false,
      ),
      
      // Cards
      cardTheme: CardThemeData(
        elevation: 0,
        color: MineColors.darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: MineSpacing.cardRadius,
        ),
        margin: EdgeInsets.zero,
      ),
      
      // Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: accentColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(
            horizontal: MineSpacing.xl,
            vertical: MineSpacing.base,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: MineSpacing.buttonRadius,
          ),
          textStyle: MineTypography.labelLarge,
        ),
      ),
      
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentColor,
          padding: const EdgeInsets.symmetric(
            horizontal: MineSpacing.base,
            vertical: MineSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: MineSpacing.buttonRadius,
          ),
          textStyle: MineTypography.labelLarge,
        ),
      ),
      
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: MineColors.darkTextPrimary,
          side: const BorderSide(color: MineColors.darkBorder),
          padding: const EdgeInsets.symmetric(
            horizontal: MineSpacing.xl,
            vertical: MineSpacing.base,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: MineSpacing.buttonRadius,
          ),
          textStyle: MineTypography.labelLarge,
        ),
      ),
      
      // Icon buttons
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: MineColors.darkTextSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MineSpacing.radiusMd),
          ),
        ),
      ),
      
      // Floating Action Button
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        highlightElevation: 4,
        backgroundColor: accentColor,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MineSpacing.radiusBase),
        ),
      ),
      
      // Input fields
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: MineColors.darkSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: MineSpacing.base,
          vertical: MineSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: MineSpacing.inputRadius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: MineSpacing.inputRadius,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: MineSpacing.inputRadius,
          borderSide: BorderSide(
            color: accentColor,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: MineSpacing.inputRadius,
          borderSide: const BorderSide(
            color: MineColors.error,
            width: 1,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: MineSpacing.inputRadius,
          borderSide: const BorderSide(
            color: MineColors.error,
            width: 1.5,
          ),
        ),
        hintStyle: MineTypography.bodyMedium.copyWith(
          color: MineColors.darkTextTertiary,
        ),
        labelStyle: MineTypography.bodyMedium.copyWith(
          color: MineColors.darkTextSecondary,
        ),
      ),
      
      // Bottom Navigation
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        elevation: 0,
        backgroundColor: MineColors.darkSurface,
        selectedItemColor: accentColor,
        unselectedItemColor: MineColors.darkTextTertiary,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        selectedLabelStyle: MineTypography.labelSmall,
        unselectedLabelStyle: MineTypography.labelSmall,
      ),
      
      // Navigation Bar (Material 3)
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: MineColors.darkSurface,
        indicatorColor: accentColor.withValues(alpha: 0.2),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 80,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return MineTypography.labelSmall.copyWith(
              color: accentColor,
            );
          }
          return MineTypography.labelSmall.copyWith(
            color: MineColors.darkTextTertiary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(
              color: accentColor,
              size: 24,
            );
          }
          return const IconThemeData(
            color: MineColors.darkTextTertiary,
            size: 24,
          );
        }),
      ),
      
      // Divider
      dividerTheme: const DividerThemeData(
        color: MineColors.darkDivider,
        thickness: 1,
        space: 1,
      ),
      
      // Bottom Sheet
      bottomSheetTheme: const BottomSheetThemeData(
        elevation: 0,
        backgroundColor: MineColors.darkSurfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(MineSpacing.radiusXl),
          ),
        ),
        showDragHandle: true,
        dragHandleColor: MineColors.darkDivider,
      ),
      
      // Dialog
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: MineColors.darkSurfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MineSpacing.radiusLg),
        ),
        titleTextStyle: MineTypography.titleLarge.copyWith(
          color: MineColors.darkTextPrimary,
        ),
        contentTextStyle: MineTypography.bodyMedium.copyWith(
          color: MineColors.darkTextPrimary,
        ),
      ),
      
      // Snackbar
      snackBarTheme: SnackBarThemeData(
        elevation: 0,
        backgroundColor: MineColors.darkSurfaceElevated,
        contentTextStyle: MineTypography.bodyMedium.copyWith(
          color: MineColors.darkTextPrimary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MineSpacing.radiusMd),
        ),
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.all(MineSpacing.base),
      ),
      
      // Chip
      chipTheme: ChipThemeData(
        elevation: 0,
        backgroundColor: MineColors.darkSurfaceVariant,
        selectedColor: accentColor.withValues(alpha: 0.25),
        labelStyle: MineTypography.labelMedium.copyWith(
          color: MineColors.darkTextPrimary,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: MineSpacing.md,
          vertical: MineSpacing.sm,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: MineSpacing.chipRadius,
        ),
      ),
      
      // Progress Indicator
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accentColor,
        linearTrackColor: MineColors.darkSurfaceVariant,
        circularTrackColor: MineColors.darkSurfaceVariant,
      ),
      
      // Slider
      sliderTheme: SliderThemeData(
        activeTrackColor: accentColor,
        inactiveTrackColor: MineColors.darkSurfaceVariant,
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
          return MineColors.darkSurfaceVariant;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return accentColor.withValues(alpha: 0.5);
          }
          return MineColors.darkBorder;
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
        side: const BorderSide(color: MineColors.darkBorder, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      
      // Radio
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return accentColor;
          }
          return MineColors.darkBorder;
        }),
      ),
      
      // ListTile
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: MineSpacing.base,
          vertical: MineSpacing.sm,
        ),
        minVerticalPadding: MineSpacing.sm,
        horizontalTitleGap: MineSpacing.md,
        titleTextStyle: MineTypography.bodyLarge.copyWith(
          color: MineColors.darkTextPrimary,
        ),
        subtitleTextStyle: MineTypography.bodySmall.copyWith(
          color: MineColors.darkTextSecondary,
        ),
        iconColor: MineColors.darkTextSecondary,
      ),
      
      // Tooltip
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: MineColors.darkSurfaceElevated,
          borderRadius: BorderRadius.circular(MineSpacing.radiusSm),
        ),
        textStyle: MineTypography.bodySmall.copyWith(
          color: MineColors.darkTextPrimary,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: MineSpacing.md,
          vertical: MineSpacing.sm,
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
      scaffoldBackgroundColor: MineColors.windDownBackground,
      colorScheme: light.colorScheme.copyWith(
        surface: MineColors.windDownSurface,
        onSurface: MineColors.windDownText,
      ),
      cardTheme: light.cardTheme.copyWith(
        color: MineColors.windDownSurface,
      ),
    );
  }

  /// WindDown theme (warm grayscale for evening) - Dark
  static ThemeData get windDownDark {
    return dark.copyWith(
      scaffoldBackgroundColor: MineColors.darkWindDownBackground,
      colorScheme: dark.colorScheme.copyWith(
        surface: MineColors.darkWindDownSurface,
        onSurface: MineColors.darkWindDownText,
      ),
      cardTheme: dark.cardTheme.copyWith(
        color: MineColors.darkWindDownSurface,
      ),
    );
  }
}
