import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design system Konfeti "Night Confetti": dark theme + palet Color Hunt (#006199 · #8ACFF8 · #F4EB6C · #FFD444).
/// Nama token lama dipertahankan agar layar lain tidak error; token baru hanya ditambahkan.
class AppColors {
  static const Color primary = Color(0xFF006199); // biru brand -> border sorot, glow, gradien poster
  static const Color card = Color(0xFF006199);
  static const Color sky = Color(0xFF8ACFF8); // teks sekunder, icon pasif, border
  static const Color butter = Color(0xFFF4EB6C); // Secondary accent: tag, badge
  static const Color sun = Color(0xFFFFD444); // Primary accent: tombol utama, icon aktif, harga
  static const Color ink = Color(0xFF0B1B2B); // teks gelap di atas kuning
  static const Color bg = Color(0xFF0A192F); // Deep Navy
  static const Color bgAlt = Color(0xFF0E2340); // input, panel
  static const Color success = Color(0xFF2ECC71);
  static const Color skyDim = Color(0x998ACFF8);
  static const Color skyFaint = Color(0x338ACFF8);
  static const Color whiteFaint = Color(0x1FFFFFFF);

  // ---- Token kaca (Night Confetti) ----
  // Semua diturunkan dari warna palet yang sudah ada (bgAlt, sky, primary): hanya transparansinya yang diatur.
  static const Color glass = Color(0x8C0E2340); // bgAlt 55%: isi kartu kaca
  static const Color glassHigh = Color(0xCC0E2340); // bgAlt 80%: nav melayang, panel CTA
  static const Color glassSheen = Color(0x268ACFF8); // sky 15%: kilau sudut kiri-atas kartu kaca
  static const Color glassBorder = Color(0x388ACFF8); // sky 22%: border tipis kartu kaca
  static const Color glow = Color(0x8C006199); // primary 55%: border + bayangan kartu sorot
  static const Color danger = Color(0xFFFF6B6B); // error, LIVE
}

/// Gaya teks khusus. Seluruh app memakai satu font: Plus Jakarta Sans (tanpa italic/serif).
class AppText {
  /// Display: Plus Jakarta Sans tebal untuk sapaan, judul hero, nama artis.
  /// Nama fungsi dipertahankan agar semua layar yang memakainya otomatis ikut berubah.
  static TextStyle display({
    double size = 28,
    FontWeight weight = FontWeight.w800,
    Color color = Colors.white,
    double? height,
  }) =>
      GoogleFonts.plusJakartaSans(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: size >= 24 ? -0.3 : 0,
      );
}

OutlineInputBorder _border(Color c, [double w = 1.2]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
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
    error: AppColors.danger,
    errorContainer: const Color(0xFF5C1F28),
    onErrorContainer: const Color(0xFFFFD9DC),
  );

  // Font dasar app: Plus Jakarta Sans. Sengaja TIDAK memakai GoogleFonts.xxxTextTheme() karena
  // google_fonts 9 memakai tipe TextTheme dari paket lain; di sini hanya TextStyle biasa yang dipakai.
  final TextTheme base = ThemeData.dark().textTheme;
  TextStyle? jakarta(TextStyle? s) => s == null ? null : GoogleFonts.plusJakartaSans(textStyle: s);
  final TextTheme textTheme = base.copyWith(
    displayLarge: jakarta(base.displayLarge),
    displayMedium: jakarta(base.displayMedium),
    displaySmall: jakarta(base.displaySmall),
    headlineLarge: jakarta(base.headlineLarge),
    headlineMedium: jakarta(base.headlineMedium),
    headlineSmall: jakarta(base.headlineSmall),
    titleLarge: jakarta(base.titleLarge),
    titleMedium: jakarta(base.titleMedium),
    titleSmall: jakarta(base.titleSmall),
    bodyLarge: jakarta(base.bodyLarge),
    bodyMedium: jakarta(base.bodyMedium),
    bodySmall: jakarta(base.bodySmall),
    labelLarge: jakarta(base.labelLarge),
    labelMedium: jakarta(base.labelMedium),
    labelSmall: jakarta(base.labelSmall),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: AppColors.bg,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
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
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: const StadiumBorder(),
        textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.sky,
        side: const BorderSide(color: AppColors.sky),
        minimumSize: const Size(64, 48),
        shape: const StadiumBorder(),
        textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: AppColors.sky)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.bgAlt,
      labelStyle: const TextStyle(color: AppColors.sky),
      hintStyle: const TextStyle(color: AppColors.skyDim),
      helperStyle: const TextStyle(color: AppColors.sky),
      border: _border(AppColors.glassBorder),
      enabledBorder: _border(AppColors.glassBorder),
      focusedBorder: _border(AppColors.sun, 1.6),
      errorBorder: _border(AppColors.danger),
      focusedErrorBorder: _border(AppColors.danger, 1.6),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.skyFaint),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.sun),
    listTileTheme: const ListTileThemeData(iconColor: AppColors.sky, textColor: Colors.white),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.bgAlt,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppColors.glassBorder),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.bgAlt,
      contentTextStyle: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 14),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.glassBorder),
      ),
    ),
  );
}