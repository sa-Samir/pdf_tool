import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Spacing scale. Multiples of 4; named so layout code never invents numbers.
abstract final class Insets {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  /// Requirements.md 18.2: minimum 44/48dp touch targets.
  static const minTouchTarget = 48.0;

  /// Requirements.md 18.4 breakpoints.
  static const tabletBreakpoint = 700.0;
  static const largePhoneBreakpoint = 480.0;
}

abstract final class Corners {
  static const card = 16.0;
  static const chip = 8.0;
  static const iconTile = 12.0;
}

abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      brightness: brightness,
    ).copyWith(
      surface: isDark ? AppColors.darkSurface : AppColors.lightSurface,
    );

    return ThemeData(
      colorScheme: scheme,
      // Explicit background so the first Flutter frame matches the native
      // launch background exactly (requirements.md 3.0).
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Corners.card),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Corners.card),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Corners.card),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Insets.lg,
          vertical: Insets.md,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        minVerticalPadding: Insets.md,
      ),
    );
  }
}
