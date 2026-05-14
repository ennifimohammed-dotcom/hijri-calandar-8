import 'package:flutter/material.dart';

import '../providers/app_provider.dart';
import '../theme.dart';

/// Immutable value object carrying everything the home-screen
/// "Hijri Date" widget needs to draw itself.
///
/// It is built once, on the app side, from [AppProvider] — the single
/// source of truth for the calendar, theme, region, font and locale.
/// It is then handed to `HijriDateWidgetView`, which `home_widget`
/// renders to a PNG OUTSIDE the running app's widget tree.
///
/// Because the render happens off-tree, the snapshot is deliberately a
/// plain data object: no `BuildContext`, no `Provider`, no inherited
/// `Theme` / `Directionality` / `MediaQuery`. Everything the view could
/// otherwise have looked up from context is resolved here, up front.
///
/// This is NOT a parallel settings system — it never writes anything
/// and owns no state. It is a read-only projection of [AppProvider]
/// for one specific consumer (the widget process).
@immutable
class WidgetSnapshot {
  /// Localised weekday name, e.g. "الجمعة" / "Friday".
  final String dayName;

  /// Hijri date line, e.g. "12 ذو القعدة 1447".
  final String hijriLine;

  /// Gregorian date line, always `dd/MM/yyyy`, e.g. "09/05/2026".
  final String gregorianLine;

  /// Localised region label, e.g. "المغرب" / "Morocco".
  final String regionLabel;

  /// Whether the app is currently in dark mode (covers `ThemeMode.dark`
  /// and `ThemeMode.system` resolving to dark).
  final bool isDark;

  /// Layout direction — `true` for Arabic.
  final bool isRtl;

  /// Active font-family id (`amiri` / `cairo` / `tajawal` / ...).
  final String fontFamily;

  /// The app's current accent colour (royal green by default).
  final Color accent;

  const WidgetSnapshot({
    required this.dayName,
    required this.hijriLine,
    required this.gregorianLine,
    required this.regionLabel,
    required this.isDark,
    required this.isRtl,
    required this.fontFamily,
    required this.accent,
  });

  /// Builds a snapshot from the live provider. Pure read — touches no
  /// I/O and mutates nothing.
  factory WidgetSnapshot.fromProvider(AppProvider p) {
    final t = p.today;
    final greg = p.hijriToGregorian(t.hYear, t.hMonth, t.hDay);
    final loc = p.locale;

    final isDark = p.themeMode == ThemeMode.dark ||
        (p.themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);

    return WidgetSnapshot(
      dayName: _weekdayName(greg.weekday, loc),
      hijriLine: '${t.hDay} ${p.getHijriMonthName(t.hMonth, loc)} ${t.hYear}',
      gregorianLine:
          '${_pad2(greg.day)}/${_pad2(greg.month)}/${greg.year}',
      regionLabel: _regionName(p.region, loc),
      isDark: isDark,
      isRtl: loc == 'ar',
      fontFamily: p.fontFamily,
      accent: AppColors.green,
    );
  }

  /// Compact fingerprint of everything the widget actually shows.
  /// [WidgetSyncService] compares it to skip re-rendering an
  /// identical widget when the provider notifies for an unrelated
  /// reason (a month swipe, a day tap, ...).
  String get signature => [
        dayName,
        hijriLine,
        gregorianLine,
        regionLabel,
        isDark,
        isRtl,
        fontFamily,
        accent.toString(),
      ].join('|');

  static String _pad2(int n) => n.toString().padLeft(2, '0');

  /// [weekday] is `DateTime.weekday`: 1 = Monday .. 7 = Sunday.
  /// Hand-rolled, like the rest of the app's localisation (see
  /// `AppProvider.label` and `hijriMonthName`), so the widget never
  /// depends on `intl` locale data being initialised.
  static String _weekdayName(int weekday, String loc) {
    const names = <String, List<String>>{
      'ar': [
        'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس',
        'الجمعة', 'السبت', 'الأحد',
      ],
      'fr': [
        'Lundi', 'Mardi', 'Mercredi', 'Jeudi',
        'Vendredi', 'Samedi', 'Dimanche',
      ],
      'en': [
        'Monday', 'Tuesday', 'Wednesday', 'Thursday',
        'Friday', 'Saturday', 'Sunday',
      ],
      'es': [
        'Lunes', 'Martes', 'Miércoles', 'Jueves',
        'Viernes', 'Sábado', 'Domingo',
      ],
    };
    final list = names[loc] ?? names['ar']!;
    final idx = (weekday - 1).clamp(0, 6);
    return list[idx];
  }

  /// Region code → localised display name. Covers every code
  /// [AppProvider] can persist, not just the two the settings UI
  /// currently exposes, so a future region addition can't make the
  /// widget show a raw code.
  static String _regionName(String code, String loc) {
    const names = <String, Map<String, String>>{
      'ma': {
        'ar': 'المغرب', 'fr': 'Maroc', 'en': 'Morocco', 'es': 'Marruecos',
      },
      'dz': {
        'ar': 'الجزائر', 'fr': 'Algérie', 'en': 'Algeria', 'es': 'Argelia',
      },
      'tn': {
        'ar': 'تونس', 'fr': 'Tunisie', 'en': 'Tunisia', 'es': 'Túnez',
      },
      'sa': {
        'ar': 'السعودية', 'fr': 'Arabie Saoudite',
        'en': 'Saudi Arabia', 'es': 'Arabia Saudí',
      },
      'tr': {
        'ar': 'تركيا', 'fr': 'Turquie', 'en': 'Turkey', 'es': 'Turquía',
      },
      'id': {
        'ar': 'إندونيسيا', 'fr': 'Indonésie',
        'en': 'Indonesia', 'es': 'Indonesia',
      },
      'global': {
        'ar': 'أم القرى', 'fr': 'Oumm al-Qoura',
        'en': 'Umm al-Qura', 'es': 'Umm al-Qura',
      },
    };
    final entry = names[code] ?? names['global']!;
    return entry[loc] ?? entry['ar']!;
  }
}
