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

  /// "Islamic Day" widget — today's Islamic occasion. Two halves
  /// stored separately so the view can render the title with its
  /// full Arabic typography while putting the emoji in its own
  /// fixed-size container (consistent sizing across rows, never
  /// crashed against the widget's RTL edge).
  ///
  /// `islamicTodayTitle` is the localised name (e.g. "يوم الجمعة").
  /// `islamicTodayEmoji` is just the emoji code-point (e.g. "🕌"),
  /// or empty if the event has none.
  /// `islamicToday` is the legacy joined string — still emitted
  /// for the signature so a same-string day doesn't re-render.
  final String islamicToday;
  final String islamicTodayTitle;
  final String islamicTodayEmoji;

  /// "Islamic Day" widget — the next THREE upcoming occasions, each
  /// with its own emoji, localised name and localised countdown
  /// (e.g. "غدًا" / "بعد 3 يومًا"). Forward-scan dedupes weekly
  /// repeats by event id, so a single Friday won't fill every slot.
  /// May contain fewer than three entries (or be empty) when no
  /// further Islamic events are enabled or scheduled.
  final List<({String emoji, String title, String countdown})>
      islamicUpcomingList;

  /// Spiritual-mode hint for the card shell — lets it pick a subtle
  /// mood adjustment (slightly warmer gold for Ramadan, dimmer
  /// ambience at night, etc.) without changing the overall palette.
  /// One of `ramadan` / `eid` / `friday` / `night` / `default`.
  final String spiritualMode;

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
    required this.islamicTodayTitle,
    required this.islamicTodayEmoji,
    required this.islamicUpcomingList,
    required this.spiritualMode,
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
    String islamicTodayTitle = _blessedDay(loc);
    String islamicTodayEmoji = '';
    final upcomingList = <({String emoji, String title, String countdown})>[];
    try {
      final todayHits = p
          .islamicEventsForDay(t.hDay, t.hMonth, t.hYear)
          .where((e) => !p.isDailyAdhkar(e.id))
          .toList();
      if (todayHits.isNotEmpty) {
        final e = todayHits.first;
        islamicTodayTitle = e.title(loc);
        islamicTodayEmoji = e.emoji;
        islamicToday = _fmtOccasion(e.emoji, e.title(loc));
      }
      // Forward-scan for the next THREE upcoming Islamic occasions.
      // Weekly events (Jumu'ah, Mon/Thu fasting) repeat — dedupe by
      // event id so a single Friday can't fill every slot. 60 days
      // is comfortably enough to find three distinct events when
      // any reasonable set is enabled.
      final seenIds = <String>{};
      for (int d = 1; d <= 60 && upcomingList.length < 3; d++) {
        final h = p.gregorianToHijri(greg.add(Duration(days: d)));
        final hits = p
            .islamicEventsForDay(h.hDay, h.hMonth, h.hYear)
            .where((e) => !p.isDailyAdhkar(e.id))
            .toList();
        for (final e in hits) {
          if (upcomingList.length >= 3) break;
          if (!seenIds.add(e.id)) continue;
          upcomingList.add((
            emoji: e.emoji,
            title: e.title(loc),
            countdown: _inDays(d, loc),
          ));
        }
      }
    } catch (_) {
      // Leave the defaults; the views handle empty / default strings.
    }

    // Subtle "mood" hint for the card shell — picked from the Hijri
    // date / Gregorian weekday / wall-clock hour so the widget can
    // shift its ambience a touch on important Islamic moments
    // (Ramadan, Eid, Friday) and at night, without changing the
    // overall palette. Priority: Eid > Ramadan > Friday > Night.
    final spiritualMode = _spiritualMode(t.hMonth, t.hDay, greg.weekday);

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
      islamicTodayTitle: islamicTodayTitle,
      islamicTodayEmoji: islamicTodayEmoji,
      islamicUpcomingList: upcomingList,
      spiritualMode: spiritualMode,
    );
  }

  /// Picks a "mood" tag for the card shell. Pure date / weekday /
  /// clock math — no provider state or persistent settings — so it
  /// can't drift from what the user actually sees on the lock
  /// screen.
  ///
  /// `eid`     — Eid al-Fitr (1-3 Shawwal) or Eid al-Adha (10-13
  ///             Dhu al-Hijjah).
  /// `ramadan` — anywhere in month 9.
  /// `friday`  — Gregorian weekday 5 (Friday).
  /// `night`   — local wall-clock hour outside 05:00..18:59.
  /// `default` — everything else.
  static String _spiritualMode(int hMonth, int hDay, int gregWeekday) {
    if (hMonth == 10 && hDay >= 1 && hDay <= 3) return 'eid';
    if (hMonth == 12 && hDay >= 10 && hDay <= 13) return 'eid';
    if (hMonth == 9) return 'ramadan';
    if (gregWeekday == 5) return 'friday';
    final hour = DateTime.now().hour;
    if (hour >= 19 || hour < 5) return 'night';
    return 'default';
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
        // Fold the upcoming list into one joined string for the
        // fingerprint — order-sensitive, so reordering picks up
        // re-renders too.
        islamicUpcomingList
            .map((e) => '${e.emoji}|${e.title}|${e.countdown}')
            .join('//'),
        // Include the mood mode explicitly so a sunset / Ramadan-
        // start moment triggers a re-render even if every visible
        // string happens to be unchanged.
        spiritualMode,
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
