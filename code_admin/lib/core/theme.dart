import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palet sama dengan app user (Night Confetti). Tidak ada gradient/blur/glow di app admin.
class C {
  static const Color bg = Color(0xFF0A192F);
  static const Color panel = Color(0xFF0E2340);
  static const Color primary = Color(0xFF006199);
  static const Color sky = Color(0xFF8ACFF8);
  static const Color sun = Color(0xFFFFD444);
  static const Color butter = Color(0xFFF4EB6C);
  static const Color ink = Color(0xFF0B1B2B);
  static const Color success = Color(0xFF2ECC71);
  static const Color danger = Color(0xFFFF6B6B);
  static const Color muted = Color(0xFF8A9BB0); // status netral (draft/pending)
  static const Color line = Color(0x388ACFF8); // sky 22%
  static const Color textSoft = Color(0xFFB9D6EA);
}

const List<FontFeature> tabular = <FontFeature>[FontFeature.tabularFigures()];

TextStyle t(double size, {FontWeight w = FontWeight.w400, Color color = Colors.white, bool nums = false}) =>
    GoogleFonts.plusJakartaSans(
      fontSize: size,
      fontWeight: w,
      color: color,
      fontFeatures: nums ? tabular : null,
    );

OutlineInputBorder _b(Color c, [double w = 1]) =>
    OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c, width: w));

/// Font Plus Jakarta Sans untuk semua gaya teks. Sengaja tidak memakai GoogleFonts.plusJakartaSansTextTheme()
/// karena google_fonts 9 memakai tipe TextTheme yang berbeda (sama seperti di code_konfeti).
TextTheme _jakartaTextTheme(TextTheme input) {
  final base = input.apply(bodyColor: Colors.white, displayColor: Colors.white);
  TextStyle? jk(TextStyle? s) => s == null ? null : GoogleFonts.plusJakartaSans(textStyle: s);
  return base.copyWith(
    displayLarge: jk(base.displayLarge),
    displayMedium: jk(base.displayMedium),
    displaySmall: jk(base.displaySmall),
    headlineLarge: jk(base.headlineLarge),
    headlineMedium: jk(base.headlineMedium),
    headlineSmall: jk(base.headlineSmall),
    titleLarge: jk(base.titleLarge),
    titleMedium: jk(base.titleMedium),
    titleSmall: jk(base.titleSmall),
    bodyLarge: jk(base.bodyLarge),
    bodyMedium: jk(base.bodyMedium),
    bodySmall: jk(base.bodySmall),
    labelLarge: jk(base.labelLarge),
    labelMedium: jk(base.labelMedium),
    labelSmall: jk(base.labelSmall),
  );
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: C.primary, brightness: Brightness.dark).copyWith(
    primary: C.sun,
    onPrimary: C.ink,
    secondary: C.butter,
    surface: C.panel,
    error: C.danger,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: Brightness.dark);
  return base.copyWith(
    scaffoldBackgroundColor: C.bg,
    canvasColor: C.bg,
    dividerColor: C.line,
    textTheme: _jakartaTextTheme(base.textTheme),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.panel,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      labelStyle: t(13, color: C.textSoft),
      hintStyle: t(13, color: C.muted),
      border: _b(C.line),
      enabledBorder: _b(C.line),
      focusedBorder: _b(C.sky, 1.5),
      errorBorder: _b(C.danger),
      focusedErrorBorder: _b(C.danger, 1.5),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.sun,
        foregroundColor: C.ink,
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: t(14, w: FontWeight.w700, color: C.ink),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: C.line),
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: t(14, w: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: C.sky, textStyle: t(13, w: FontWeight.w600)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: C.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: C.line)),
      titleTextStyle: t(16, w: FontWeight.w700),
      contentTextStyle: t(14, color: C.textSoft),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: C.panel,
      contentTextStyle: t(13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: C.line)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.ink : C.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.sun : C.panel),
      trackOutlineColor: WidgetStateProperty.all(C.line),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(textStyle: t(14)),
  );
}