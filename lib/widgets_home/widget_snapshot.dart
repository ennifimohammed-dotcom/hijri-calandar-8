import 'package:flutter/material.dart';

import '../providers/app_provider.dart';
import '../theme.dart';

/// Immutable value object carrying everything the home-screen widgets
/// need to draw themselves.
///
/// It is built once, on the app side, from [AppProvider] — the single
/// source of truth for the calendar, theme, region, font, locale and
/// Islamic events. It is then handed to the widget views
/// (`HijriDateWidgetView`, `IslamicDayWidgetView`), which `home_widget`
/// renders to PNGs OUTSIDE the running app's widget tree.
///
/// Because the render happens off-tree, the snapshot is deliberately a
/// plain data object: no `BuildContext`, no `Provider`, no inherited
/// `Theme` / `Directionality` / `MediaQuery`. Everything the views
/// could otherwise have looked up from context — including the
/// localised Islamic-occasion strings — is resolved here, up front.
///
/// This is NOT a parallel settings system — it never writes anything
/// and owns no state. It is a read-only projection of [AppProvider]
/// for one specific set of consumers (the widget process).
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

  /// "Islamic Day" widget — today's Islamic occasion, already
  /// localised and emoji-prefixed (e.g. "🕌  يوم الجمعة"). Falls back
  /// to a localised "blessed day" when nothing applies today.
  final String islamicToday;

  /// "Islamic Day" widget — the next upcoming Islamic occasion with a
  /// localised countdown (e.g. "🌙  رمضان · بعد 3 يومًا"). Empty when
  /// there is nothing enabled to look forward to.
  final String islamicUpcoming;

  const WidgetSnapshot({
    required this.dayName,
    required this.hijriLine,
    required this.gregorianLine,
    required this.regionLabel,
    required this.isDark,
    required this.isRtl,
    required this.fontFamily,
    required this.accent,
    required this.islamicToday,
    required this.islamicUpcoming,
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

    // ── Islamic Day widget data ──────────────────────────────────
    // Today's occasion + the next upcoming one. Wrapped so a
    // conversion hiccup yields the safe defaults rather than a failed
    // snapshot. Daily adhkar are excluded — they would be noise here
    // (every day "has" them), matching how the monthly view hides
    // them. Reuses AppProvider's own matching logic via
    // `islamicEventsForDay`; nothing is duplicated.
    String islamicToday = _blessedDay(loc);
    String islamicUpcoming = '';
    try {
      final todayHits = p
          .islamicEventsForDay(t.hDay, t.hMonth, t.hYear)
          .where((e) => !p.isDailyAdhkar(e.id))
          .toList();
      if (todayHits.isNotEmpty) {
        final e = todayHits.first;
        islamicToday = _fmtOccasion(e.emoji, e.title(loc));
      }
      // Forward scan for the next occasion. Weekly events (Jumu'ah,
      // Mon/Thu fasting) guarantee a hit within a week when anything
      // is enabled, so a 45-day cap is comfortably enough.
      for (int d = 1; d <= 45; d++) {
        final h = p.gregorianToHijri(greg.add(Duration(days: d)));
        final hits = p
            .islamicEventsForDay(h.hDay, h.hMonth, h.hYear)
            .where((e) => !p.isDailyAdhkar(e.id))
            .toList();
        if (hits.isNotEmpty) {
          final e = hits.first;
          islamicUpcoming =
              '${_fmtOccasion(e.emoji, e.title(loc))} · ${_inDays(d, loc)}';
          break;
        }
      }
    } catch (_) {
      // Leave the defaults; the views handle empty / default strings.
    }

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
      islamicToday: islamicToday,
      islamicUpcoming: islamicUpcoming,
    );
  }

  /// Compact fingerprint of everything the widgets actually show.
  /// [WidgetSyncService] compares it to skip re-rendering identical
  /// widgets when the provider notifies for an unrelated reason (a
  /// month swipe, a day tap, ...).
  String get signature => [
        dayName,
        hijriLine,
        gregorianLine,
        regionLabel,
        isDark,
        isRtl,
        fontFamily,
        accent.toString(),
        islamicToday,
        islamicUpcoming,
      ].join('|');

  static String _pad2(int n) => n.toString().padLeft(2, '0');

  /// Joins an event emoji and its localised name into one display
  /// string (gracefully drops the emoji when the event has none).
  static String _fmtOccasion(String emoji, String name) =>
      emoji.isNotEmpty ? '$emoji  $name' : name;

  /// Localised "blessed day" — the [islamicToday] fallback for a day
  /// with no specific Islamic occasion.
  static String _blessedDay(String loc) {
    switch (loc) {
      case 'fr':
        return 'Jour béni';
      case 'en':
        return 'Blessed day';
      case 'es':
        return 'Día bendito';
      case 'ar':
      default:
        return 'يوم مبارك';
    }
  }

  /// Localised "in N days" countdown for the upcoming occasion.
  static String _inDays(int n, String loc) {
    if (n == 1) {
      switch (loc) {
        case 'fr':
          return 'demain';
        case 'en':
          return 'tomorrow';
        case 'es':
          return 'mañana';
        case 'ar':
        default:
          return 'غدًا';
      }
    }
    switch (loc) {
      case 'fr':
        return 'dans $n jours';
      case 'en':
        return 'in $n days';
      case 'es':
        return 'en $n días';
      case 'ar':
      default:
        return 'بعد $n يومًا';
    }
  }

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
