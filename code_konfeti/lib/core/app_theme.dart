import 'package:flutter/material.dart';
 
/// Design system Konfeti: dark theme + palet Color Hunt (#006199 · #8ACFF8 · #F4EB6C · #FFD444).
class AppColors {
  static const Color primary = Color(0xFF006199); // Primary Brand (dark blue) -> kartu, header
  static const Color card = Color(0xFF006199);
  static const Color sky = Color(0xFF8ACFF8); // teks sekunder, icon pasif, border
  static const Color butter = Color(0xFFF4EB6C); // Secondary accent: tag, badge
  static const Color sun = Color(0xFFFFD444); // Primary accent: tombol utama, icon aktif
  static const Color ink = Color(0xFF0B1B2B); // teks gelap di atas kuning
  static const Color bg = Color(0xFF0A192F); // Deep Navy
  static const Color bgAlt = Color(0xFF0E2340); // nav bar, input, panel
  static const Color success = Color(0xFF2ECC71);
  static const Color skyDim = Color(0x998ACFF8);
  static const Color skyFaint = Color(0x338ACFF8);
  static const Color whiteFaint = Color(0x1FFFFFFF);
}
 
OutlineInputBorder _border(Color c, [double w = 1.2]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: c, width: w),
    );
 
ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.primary, brightness: Brightness.dark).copyWith(
    primary: AppColors.sun,
    onPrimary: AppColors.ink,
    primaryContainer: AppColors.primary,
    onPrimaryContainer: Colors.white,
    secondary: AppColors.butter,
    onSecondary: AppColors.ink,
    secondaryContainer: AppColors.primary,
    onSecondaryContainer: Colors.white,
    tertiary: AppColors.sky,
    onTertiary: AppColors.ink,
    surface: AppColors.bg,
    onSurface: Colors.white,
    onSurfaceVariant: AppColors.sky,
    outline: AppColors.sky,
    outlineVariant: AppColors.skyFaint,
    error: const Color(0xFFFF6B6B),
    errorContainer: const Color(0xFF5C1F28),
    onErrorContainer: const Color(0xFFFFD9DC),
  );
 
 
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.bgAlt,
      indicatorColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: states.contains(WidgetState.selected) ? AppColors.sun : AppColors.sky,
          )),
      iconTheme: WidgetStateProperty.resolveWith((states) =>
          IconThemeData(color: states.contains(WidgetState.selected) ? AppColors.sun : AppColors.sky)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.sun,
        foregroundColor: AppColors.ink,
        disabledBackgroundColor: const Color(0x33FFD444),
        disabledForegroundColor: const Color(0x66FFFFFF),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.sky,
        side: const BorderSide(color: AppColors.sky),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: AppColors.sky)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.bgAlt,
      labelStyle: const TextStyle(color: AppColors.sky),
      hintStyle: const TextStyle(color: AppColors.skyDim),
      helperStyle: const TextStyle(color: AppColors.sky),
      border: _border(AppColors.primary),
      enabledBorder: _border(AppColors.primary),
      focusedBorder: _border(AppColors.sun, 1.6),
      errorBorder: _border(const Color(0xFFFF6B6B)),
      focusedErrorBorder: _border(const Color(0xFFFF6B6B), 1.6),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.skyFaint),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.sun),
    listTileTheme: const ListTileThemeData(iconColor: AppColors.sky, textColor: Colors.white),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.card,
      contentTextStyle: TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
 