import 'package:flutter/material.dart';

import 'brand.dart';

export 'brand.dart';

// Status colours, the same as the dashboard's.
const liveGreen = Color(0xFF10B981);
const warnAmber = liveAmber;
const failRed = Color(0xFFEF4444);
const dropoffPurple = Color(0xFFA855F7);

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final ground = dark ? nightInk : paper;
  final surface = dark ? const Color(0xFF131C2E) : Colors.white;
  final raised = dark ? const Color(0xFF1A2438) : const Color(0xFFEEF2F7);
  final line = dark ? const Color(0xFF263247) : const Color(0xFFDDE3EC);
  final fg = dark ? const Color(0xFFF3F6FA) : nightInk;
  final muted = dark ? const Color(0xFF9AA6B8) : const Color(0xFF4B5563);

  final scheme = ColorScheme.fromSeed(seedColor: radianBlue, brightness: brightness).copyWith(
    // Radian Blue keeps white button text above 4.5:1 on both grounds.
    primary: radianBlue,
    onPrimary: Colors.white,
    secondary: signalBlue,
    tertiary: liveAmber,
    surface: surface,
    onSurface: fg,
    onSurfaceVariant: muted,
    surfaceContainerHighest: raised,
    outline: muted,
    outlineVariant: line,
  );

  final base = ThemeData(brightness: brightness, fontFamily: 'Geist', useMaterial3: true);
  final text = base.textTheme.apply(bodyColor: fg, displayColor: fg).copyWith(
        headlineMedium: base.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.8, color: fg),
        titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.4, color: fg),
        titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: fg),
        labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      );

  return ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: 'Geist',
    textTheme: text,
    scaffoldBackgroundColor: ground,
    dividerColor: line,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      scrolledUnderElevation: 0,
      backgroundColor: ground,
      foregroundColor: fg,
      titleTextStyle: text.titleMedium,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: line)),
    ),
    listTileTheme: ListTileThemeData(iconColor: muted, subtitleTextStyle: text.bodyMedium?.copyWith(color: muted)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      labelStyle: TextStyle(color: muted),
      prefixIconColor: muted,
      suffixIconColor: muted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: line)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: dark ? signalBlue : radianBlue, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: radianBlue,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontFamily: 'Geist', fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: fg,
        minimumSize: const Size.fromHeight(52),
        side: BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontFamily: 'Geist', fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: dark ? signalBlue : radianBlue,
        textStyle: const TextStyle(fontFamily: 'Geist', fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF1A2438) : nightInk,
      contentTextStyle: const TextStyle(fontFamily: 'Geist', color: Color(0xFFF3F6FA)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: dark ? signalBlue : radianBlue),
  );
}

/// Monospace style for telemetry: plates, coordinates, speeds, counts.
TextStyle mono(TextStyle? base) => (base ?? const TextStyle()).copyWith(fontFamily: monoFamily, letterSpacing: -0.2);
