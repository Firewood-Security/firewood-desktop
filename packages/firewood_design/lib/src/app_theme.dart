// Shared Material theme, derived from tokens. Mirrors the mobile app's theme
// so both platforms share colour, shape and typography language.

import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_tokens.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme => getDarkTheme(AppColors.orangeAccent);

  static ThemeData getDarkTheme([Color accentColor = AppColors.orangeAccent]) {
    final hsl = HSLColor.fromColor(accentColor);
    final primaryContainer =
        hsl.withLightness(0.14).withSaturation(0.65).toColor();
    final primaryOnContainer = hsl.withLightness(0.85).toColor();
    final isLightAccent = hsl.lightness > 0.65;
    final onPrimaryText =
        isLightAccent ? const Color(0xFF140C08) : Colors.white;

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.borderZinc),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.backgroundZinc,
      colorScheme: ColorScheme.dark(
        primary: accentColor,
        onPrimary: onPrimaryText,
        primaryContainer: primaryContainer,
        onPrimaryContainer: primaryOnContainer,
        error: AppColors.roseAccent,
        onError: Colors.white,
        errorContainer: AppColors.roseContainer,
        onErrorContainer: AppColors.roseOnContainer,
        surface: AppColors.surfaceZinc,
        onSurface: AppColors.offWhite,
        onSurfaceVariant: AppColors.textMuted,
        surfaceContainerHighest: AppColors.cardZinc,
        outline: AppColors.borderZinc,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surfaceZinc,
        foregroundColor: AppColors.offWhite,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardZinc,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.lgAll,
          side: const BorderSide(color: AppColors.borderZinc),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: AppColors.inputZinc,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: AppColors.orangeAccent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.roseAccent),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.orangeAccent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(
              vertical: 14, horizontal: AppSpacing.xl),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.surfaceZinc,
          foregroundColor: AppColors.offWhite,
          side: const BorderSide(color: AppColors.borderZinc),
          padding: const EdgeInsets.symmetric(
              vertical: 14, horizontal: AppSpacing.xl),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.orangeAccent,
          padding: const EdgeInsets.symmetric(
              vertical: 10, horizontal: AppSpacing.lg),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceZinc,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.borderZinc),
        ),
      ),
    );
  }

  static ThemeData get lightTheme => darkTheme;
}
