import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// One swatch in the theme-color picker.
class AccentSwatch {
  final int index;
  final String id;

  /// The "main" (saturated) color used wherever the app would otherwise
  /// be green. This drives [AppColors.green] at runtime.
  final Color main;

  /// The matching "pale" tint, used wherever the app would otherwise
  /// be greenPale (event lists, chips, today-glow, etc.).
  final Color pale;

  const AccentSwatch({
    required this.index,
    required this.id,
    required this.main,
    required this.pale,
  });
}

/// 8 accent swatches — 4 "light" (softer hues) and 4 "main dark"
/// (saturated/serious hues). Picking any swatch swaps the app's
/// primary accent (green by default) project-wide via [AccentBus].
const List<AccentSwatch> kAccentPalette = <AccentSwatch>[
  // 4 main / dark
  AccentSwatch(
    index: 0,
    id: 'green',
    main: Color(0xFF2D7D5F),
    pale: Color(0xFFEAF4EF),
  ),
  AccentSwatch(
    index: 1,
    id: 'navy',
    main: Color(0xFF1B3B6F),
    pale: Color(0xFFE6ECF5),
  ),
  AccentSwatch(
    index: 2,
    id: 'maroon',
    main: Color(0xFF8E2A2A),
    pale: Color(0xFFF8E6E6),
  ),
  AccentSwatch(
    index: 3,
    id: 'plum',
    main: Color(0xFF5E2C7E),
    pale: Color(0xFFF1E7F8),
  ),
  // 4 light
  AccentSwatch(
    index: 4,
    id: 'teal',
    main: Color(0xFF26A69A),
    pale: Color(0xFFE0F5F3),
  ),
  AccentSwatch(
    index: 5,
    id: 'sky',
    main: Color(0xFF4FA3D1),
    pale: Color(0xFFE8F2FA),
  ),
  AccentSwatch(
    index: 6,
    id: 'rose',
    main: Color(0xFFE57373),
    pale: Color(0xFFFCEBEB),
  ),
  AccentSwatch(
    index: 7,
    id: 'amber',
    main: Color(0xFFE0A93B),
    pale: Color(0xFFFAF1DE),
  ),
];

/// Mutable global accent — read by [AppColors.green] / [AppColors.greenPale].
///
/// Kept as a static so non-const getters (`AppColors.green`) can stay a
/// drop-in replacement for the previous `static const Color`. When the
/// user picks a swatch in settings the AppProvider calls [AccentBus.set]
/// and notifies listeners — every widget that reads `AppColors.green`
/// then renders with the new color on its next build.
class AccentBus {
  AccentBus._();
  static int _index = 0;

  static int get index => _index;

  static AccentSwatch get current => kAccentPalette[_index];

  static Color get main => current.main;
  static Color get pale => current.pale;

  static void set(int idx) {
    if (idx < 0 || idx >= kAccentPalette.length) return;
    _index = idx;
  }
}

class AppColors {
  static const Color bg = Color(0xFFF5F3EF);
  static const Color white = Color(0xFFFFFFFF);
  static const Color navy = Color(0xFF1B2B3A);

  /// Runtime accent. Originally the static green const; now backed by
  /// [AccentBus] so swatch changes propagate without per-callsite edits.
  static Color get green => AccentBus.main;

  /// Runtime pale companion of the accent.
  static Color get greenPale => AccentBus.pale;

  /// Slightly lighter shade used in a few gradients. Derived from the
  /// active accent so it tracks the swatch.
  static Color get greenLight => Color.lerp(
        AccentBus.main,
        Colors.white,
        0.15,
      )!;

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

  /// Built fresh on every read so `AppColors.green` (now a runtime
  /// getter) flows into the ThemeData once the user picks a new
  /// accent swatch.
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
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
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
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
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
