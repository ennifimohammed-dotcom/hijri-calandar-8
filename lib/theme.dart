import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color bg = Color(0xFFF5F3EF);
  static const Color white = Color(0xFFFFFFFF);
  static const Color navy = Color(0xFF1B2B3A);
  static const Color green = Color(0xFF2D7D5F);
  static const Color greenLight = Color(0xFF3D9970);
  static const Color greenPale = Color(0xFFEAF4EF);
  static const Color gold = Color(0xFFC8943A);
  static const Color goldPale = Color(0xFFFDF5E8);
  static const Color red = Color(0xFFD94F4F);
  static const Color blue = Color(0xFF3A72C8);
  static const Color bluePale = Color(0xFFEBF0FC);
  static const Color text = Color(0xFF1A1A1A);
  static const Color text2 = Color(0xFF555555);
  static const Color text3 = Color(0xFF999999);
  static const Color border = Color(0xFFE8E4DC);

  // Dark
  static const Color darkBg = Color(0xFF121820);
  static const Color darkSurface = Color(0xFF1A2235);
  static const Color darkBorder = Color(0xFF2A3448);
  static const Color darkText = Color(0xFFF0EBE0);
  static const Color darkText2 = Color(0xFFAAB2C0);
  static const Color darkText3 = Color(0xFF6A7585);
}

class AppTheme {
  static TextTheme _textTheme(bool dark) {
    final c = dark ? AppColors.darkText : AppColors.text;
    return TextTheme(
      displayLarge: GoogleFonts.amiri(fontSize: 32, fontWeight: FontWeight.bold, color: c),
      displayMedium: GoogleFonts.amiri(fontSize: 26, fontWeight: FontWeight.bold, color: c),
      displaySmall: GoogleFonts.amiri(fontSize: 22, fontWeight: FontWeight.bold, color: c),
      headlineMedium: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w800, color: c),
      headlineSmall: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w700, color: c),
      titleLarge: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w700, color: c),
      bodyLarge: GoogleFonts.cairo(fontSize: 14, color: c),
      bodyMedium: GoogleFonts.cairo(fontSize: 12, color: c),
      bodySmall: GoogleFonts.cairo(fontSize: 10, color: dark ? AppColors.darkText3 : AppColors.text3),
    );
  }

  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.green).copyWith(
          primary: AppColors.green,
          secondary: AppColors.gold,
          surface: AppColors.white,
        ),
        scaffoldBackgroundColor: AppColors.bg,
        textTheme: _textTheme(false),
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.white,
          foregroundColor: AppColors.navy,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: GoogleFonts.amiri(
              fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.navy),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.white,
          selectedItemColor: AppColors.green,
          unselectedItemColor: AppColors.text3,
          type: BottomNavigationBarType.fixed,
          elevation: 8,
        ),
        cardTheme: CardThemeData(
          color: AppColors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        dividerColor: AppColors.border,
      );

  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
                seedColor: AppColors.green, brightness: Brightness.dark)
            .copyWith(
          primary: AppColors.green,
          secondary: AppColors.gold,
          surface: AppColors.darkSurface,
        ),
        scaffoldBackgroundColor: AppColors.darkBg,
        textTheme: _textTheme(true),
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.darkSurface,
          foregroundColor: AppColors.darkText,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: GoogleFonts.amiri(
              fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.darkText),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.darkSurface,
          selectedItemColor: AppColors.green,
          unselectedItemColor: AppColors.darkText3,
          type: BottomNavigationBarType.fixed,
          elevation: 8,
        ),
        cardTheme: CardThemeData(
          color: AppColors.darkSurface,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        dividerColor: AppColors.darkBorder,
      );
}
