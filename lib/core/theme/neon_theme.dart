import 'package:flutter/material.dart';

/// Jilake Speedo's neon theme: deep-black surfaces with an emerald primary
/// accent and ocean-blue secondary, both with a glow-friendly brightness.
abstract final class NeonTheme {
  /// Deep near-black background (racing base).
  static const Color background = Color(0xFF05070A);

  /// Slightly raised surface (cards, bars).
  static const Color surface = Color(0xFF0B1016);

  /// Neon emerald — the primary accent.
  static const Color emerald = Color(0xFF00FFA3);

  /// Neon ocean blue — the secondary accent.
  static const Color ocean = Color(0xFF00E5FF);

  /// Danger / record / stop (kept hot for contrast against the cool neon).
  static const Color danger = Color(0xFFFF3B6B);

  /// Primary text.
  static const Color onSurface = Color(0xFFE8FFF7);

  /// Muted text.
  static const Color muted = Color(0xFF6E8894);

  /// A soft glow shadow for neon elements.
  static List<Shadow> glow(Color color, {double blur = 18}) => [
        Shadow(color: color.withValues(alpha: 0.75), blurRadius: blur),
      ];

  static ThemeData theme() {
    final scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: emerald,
      onPrimary: background,
      secondary: ocean,
      onSecondary: background,
      error: danger,
      onError: background,
      surface: surface,
      onSurface: onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      cardColor: surface,
      splashColor: emerald.withValues(alpha: 0.12),
      highlightColor: emerald.withValues(alpha: 0.08),
      textTheme: const TextTheme().apply(
        bodyColor: onSurface,
        displayColor: onSurface,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: emerald,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: emerald.withValues(alpha: 0.18)),
        ),
        margin: const EdgeInsets.symmetric(vertical: 6),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF070B0F),
        indicatorColor: emerald.withValues(alpha: 0.16),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? emerald : muted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? emerald : muted,
          );
        }),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: emerald,
        foregroundColor: background,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: emerald.withValues(alpha: 0.22),
        side: BorderSide(color: emerald.withValues(alpha: 0.25)),
        labelStyle: const TextStyle(color: onSurface, fontSize: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      dividerColor: emerald.withValues(alpha: 0.12),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: emerald,
        linearTrackColor: Color(0xFF14202A),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Color(0xFF10201C),
        contentTextStyle: TextStyle(color: onSurface),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return selected ? background : onSurface;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return selected ? emerald : surface;
          }),
          side: WidgetStatePropertyAll(
            BorderSide(color: emerald.withValues(alpha: 0.35)),
          ),
        ),
      ),
    );
  }
}
