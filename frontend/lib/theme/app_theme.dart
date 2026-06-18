import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_spacing.dart';

/// Builds the R2V light & dark themes from the design tokens.
///
/// The app defaults to dark (see `themeNotifier` in main.dart). Brand colors,
/// typography (Poppins) and component shapes are centralized here so individual
/// screens don't need to re-declare them.
class AppTheme {
  AppTheme._();

  static const String fontFamily = 'Poppins';

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: AppColors.brandPurple,
      onPrimary: Colors.white,
      secondary: AppColors.brandCyan,
      onSecondary: Color(0xFF06222B),
      tertiary: AppColors.brandPink,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
      outline: AppColors.borderStrong,
    );

    return _base(
      scheme: scheme,
      scaffoldBg: AppColors.bg,
      appBarTitle: Colors.white,
      hintColor: AppColors.textMuted,
      cardColor: AppColors.surface,
      // Premium glass fields: transparent white wash instead of a heavy dark box.
      inputFill: Colors.white.withValues(alpha: 0.05),
      inputBorder: Colors.white.withValues(alpha: 0.10),
    );
  }

  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: AppColors.brandPurple,
      onPrimary: Colors.white,
      secondary: AppColors.brandCyan,
      onSecondary: Color(0xFF06222B),
      tertiary: AppColors.brandPink,
      surface: AppColors.lightSurface,
      onSurface: AppColors.lightTextPrimary,
      error: AppColors.danger,
      outline: Color(0x22000000),
    );

    return _base(
      scheme: scheme,
      scaffoldBg: AppColors.lightBg,
      appBarTitle: Colors.black87,
      hintColor: AppColors.lightTextSecondary,
      cardColor: AppColors.lightSurface,
      inputFill: Colors.black.withValues(alpha: 0.03),
      inputBorder: Colors.black.withValues(alpha: 0.08),
    );
  }

  static ThemeData _base({
    required ColorScheme scheme,
    required Color scaffoldBg,
    required Color appBarTitle,
    required Color hintColor,
    required Color cardColor,
    required Color inputFill,
    required Color inputBorder,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: scaffoldBg,
      primaryColor: scheme.primary,
      splashFactory: InkSparkle.splashFactory,
    );

    final textTheme = base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
      fontFamily: fontFamily,
    );

    return base.copyWith(
      textTheme: textTheme.copyWith(
        headlineMedium: textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium:
            textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        labelLarge: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: scheme.primary),
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: appBarTitle,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
        clipBehavior: Clip.antiAlias,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outline.withValues(alpha: 0.5),
        thickness: 1,
        space: AppSpacing.lg,
      ),
      // Premium glass input style applied app-wide: a subtle translucent wash
      // with a soft border instead of a heavy filled rectangle. The brand
      // accent only shows on focus.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        hintStyle: TextStyle(color: hintColor),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: scheme.error, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w600,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.brSm),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w600,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.brSm),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.primary.withValues(alpha: 0.6)),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w600,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.brSm),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surface,
        side: BorderSide(color: scheme.outline),
        labelStyle: TextStyle(color: scheme.onSurface, fontFamily: fontFamily),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brPill),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardColor,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: scheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle:
            const TextStyle(color: AppColors.textPrimary, fontFamily: fontFamily),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brSm),
      ),
      progressIndicatorTheme:
          ProgressIndicatorThemeData(color: scheme.primary),
      tooltipTheme: const TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: AppRadius.brSm,
        ),
        textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 12),
      ),
    );
  }
}
