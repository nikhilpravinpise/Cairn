/// Cairn Material 3 design system — disaster-response-optimized theme.
///
/// Design principles:
///   1. "Stress-first" — high contrast, large touch targets (48dp+), clear hierarchy
///   2. Semantic color — red/orange/amber/green for triage bands
///   3. Professional authority — not flashy, conveys reliability
///   4. Outdoor-usable — works in bright sunlight (high contrast)
///   5. Night-operations — dark theme for low-light conditions
///
/// Usage:
///   MaterialApp(
///     theme: CairnTheme.light(),
///     darkTheme: CairnTheme.dark(),
///   )
library;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Semantic triage colors
// ---------------------------------------------------------------------------

/// Triage band colors used across the app for priority visualization.
///
/// These are NOT part of the Material [ColorScheme] — they are semantic
/// tokens accessed via [CairnColors] and used by triage cards, report
/// badges, and the priority score indicator.
class CairnColors {
  CairnColors._();

  /// Critical priority — immediate life-safety threat.
  static const critical = Color(0xFFD32F2F);

  /// High priority — significant structural concern.
  static const high = Color(0xFFE65100);

  /// Medium priority — moderate damage, needs monitoring.
  static const medium = Color(0xFFF9A825);

  /// Low priority — minor or no visible damage.
  static const low = Color(0xFF2E7D32);

  /// Hazard warning — falling hazards, ground failure.
  static const hazard = Color(0xFFFF6F00);

  /// Information / neutral.
  static const info = Color(0xFF1565C0);

  /// Returns the semantic triage color for a given [band] label.
  static Color forBand(String band) => switch (band) {
        'CRITICAL' => critical,
        'HIGH' => high,
        'MEDIUM' => medium,
        'LOW' => low,
        _ => info,
      };

  /// Returns a muted background variant for a given [band] label.
  static Color backgroundForBand(String band) =>
      forBand(band).withValues(alpha: 0.12);
}

// ---------------------------------------------------------------------------
// Color schemes
// ---------------------------------------------------------------------------

const _primaryColor = Color(0xFF0D47A1); // Deep navy — authority, trust
const _surfaceLight = Color(0xFFFAFAFA);
const _surfaceDark = Color(0xFF121212);
const _errorColor = Color(0xFFC62828);

final _lightColorScheme = ColorScheme.fromSeed(
  seedColor: _primaryColor,
  brightness: Brightness.light,
  surface: _surfaceLight,
  error: _errorColor,
);

final _darkColorScheme = ColorScheme.fromSeed(
  seedColor: _primaryColor,
  brightness: Brightness.dark,
  surface: _surfaceDark,
  error: const Color(0xFFEF5350),
);

// ---------------------------------------------------------------------------
// Typography
// ---------------------------------------------------------------------------

const _textTheme = TextTheme(
  // Display / hero text for triage results
  displayLarge: TextStyle(
    fontSize: 48,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.5,
  ),
  displayMedium: TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
  ),
  // Screen titles
  headlineLarge: TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w600,
  ),
  headlineMedium: TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
  ),
  // Section headers
  titleLarge: TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
  ),
  titleMedium: TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
  ),
  // Body
  bodyLarge: TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
  ),
  bodyMedium: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.4,
  ),
  bodySmall: TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.3,
  ),
  // Labels
  labelLarge: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  ),
  labelMedium: TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
  ),
);

// ---------------------------------------------------------------------------
// Component themes
// ---------------------------------------------------------------------------

/// Minimum touch target size for disaster-response (gloves, stress, tremor).
const _kMinTouchTarget = Size(48, 48);

FilledButtonThemeData _filledButtonTheme(ColorScheme cs) =>
    FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: _kMinTouchTarget,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );

OutlinedButtonThemeData _outlinedButtonTheme(ColorScheme cs) =>
    OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: _kMinTouchTarget,
        side: BorderSide(color: cs.outline, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

TextButtonThemeData _textButtonTheme(ColorScheme cs) => TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: _kMinTouchTarget,
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

CardThemeData _cardTheme(ColorScheme cs) => CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      color: cs.surfaceContainerLow,
      margin: EdgeInsets.zero,
    );

InputDecorationTheme _inputTheme(ColorScheme cs) => InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: cs.outline),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      filled: true,
      fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
    );

AppBarTheme _appBarTheme(ColorScheme cs) => AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 1,
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: cs.onSurface,
      ),
    );

ChipThemeData _chipTheme(ColorScheme cs) => ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: cs.outline.withValues(alpha: 0.3)),
      ),
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Cairn design system — provides light and dark [ThemeData] for the app.
///
/// Both themes are Material 3 with disaster-response-optimized tokens:
///   - 48dp minimum touch targets (glove-friendly)
///   - High-contrast color palette
///   - Semantic triage colors via [CairnColors]
///   - Flat cards with subtle borders (sun-glare resistant)
class CairnTheme {
  CairnTheme._();

  /// Light theme — high-contrast, outdoor-optimized.
  static ThemeData light() => _buildTheme(_lightColorScheme);

  /// Dark theme — for night operations / low-light conditions.
  static ThemeData dark() => _buildTheme(_darkColorScheme);

  static ThemeData _buildTheme(ColorScheme cs) => ThemeData(
        useMaterial3: true,
        colorScheme: cs,
        textTheme: _textTheme,
        filledButtonTheme: _filledButtonTheme(cs),
        outlinedButtonTheme: _outlinedButtonTheme(cs),
        textButtonTheme: _textButtonTheme(cs),
        cardTheme: _cardTheme(cs),
        inputDecorationTheme: _inputTheme(cs),
        appBarTheme: _appBarTheme(cs),
        chipTheme: _chipTheme(cs),
        scaffoldBackgroundColor: cs.surface,
        dividerTheme: DividerThemeData(
          color: cs.outlineVariant.withValues(alpha: 0.4),
          thickness: 1,
        ),
        progressIndicatorTheme: ProgressIndicatorThemeData(
          color: cs.primary,
          linearMinHeight: 4,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
}
