import 'package:flutter/material.dart';

// Same palette as the web dashboard so the product reads as one system.
const brandBlue = Color(0xFF3B82F6);
const liveGreen = Color(0xFF22C55E);
const warnAmber = Color(0xFFF59E0B);
const failRed = Color(0xFFEF4444);

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: brandBlue, brightness: brightness).copyWith(
    // Set explicitly: seeding alone mutes the brand blue to slate. The light
    // shade keeps white button text above 4.5:1 contrast.
    primary: dark ? brandBlue : const Color(0xFF2563EB),
    onPrimary: Colors.white,
  );
  final surface = dark ? const Color(0xFF151B24) : Colors.white;
  final line = dark ? Colors.white12 : const Color(0x1A000000);

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: dark ? const Color(0xFF0B0F14) : const Color(0xFFF4F6F9),
    appBarTheme: const AppBarTheme(centerTitle: false, scrolledUnderElevation: 0),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: line)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: line)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    ),
  );
}
