import 'dart:convert';

import 'package:flutter/material.dart';

import '../providers/app_provider.dart';
import '../theme.dart';

/// Builds the data payload for the native "Mini Calendar" home-screen
/// widget.
///
/// Unlike the Hijri Date / Islamic Day widgets — which are Flutter
/// widgets rendered to PNGs — the Mini Calendar is rendered NATIVELY
/// (a real grid of tappable cells) so every day can carry its own tap
/// target. The native side cannot run Dart, so this class projects
/// everything it needs out of [AppProvider] into a compact JSON
/// string, which `home_widget` stores and `MiniCalendarWidgetProvider`
/// reads back.
///
/// It only ever READS from the provider — no parallel state, no I/O.
class MiniCalendarData {
  MiniCalendarData._();

  /// 6 rows x 7 columns. The native layout has exactly this many
  /// cells; the 6th row is hidden when the month doesn't reach it.
  static const int _gridCells = 42;

  /// Shared-prefs key the native provider reads. MUST match the key
  /// used in MiniCalendarWidgetProvider.kt and WidgetSyncService.
  static const String dataKey = 'mini_calendar_data';

  /// Builds the JSON payload for the month containing today.
  ///
  /// Layout matches the app's own monthly grid exactly
  /// (lib/screens/calendar_screen.dart): a Monday-based week, the
  /// same weekday header labels, Friday highlighted with the accent.
  static String buildJson(AppProvider p) {
    final today = p.today;
    final hy = today.hYear;
    final hm = today.hMonth;
    final loc = p.locale;

    final daysInMonth = p.getDaysInMonth(hy, hm);
    // getFirstWeekdayOfMonth: 1=Mon..7=Sun. The grid is Monday-based,
    // so column 0 = Monday — identical to `_MonthPage` in the app.
    final firstOffset = (p.getFirstWeekdayOfMonth(hy, hm) - 1) % 7;

    final isDark = p.themeMode == ThemeMode.dark ||
        (p.themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);

    final cells = <Map<String, dynamic>>[];
    for (int i = 0; i < _gridCells; i++) {
      final d = i - firstOffset + 1;
      if (d < 1 || d > daysInMonth) {
        cells.add(const {'d': 0}); // blank cell
        continue;
      }
      bool isl = false;
      bool evt = false;
      try {
        // One query per day; `getEventsForDay` already merges Islamic
        // + user events, so we derive both dot flags from it. Daily
        // adhkar are excluded — they would dot every single day.
        final events = p.getEventsForDay(d, hm, hy);
        isl = events.any((e) => e.isIslamic && !p.isDailyAdhkar(e.id));
        evt = events.any((e) => !e.isIslamic);
      } catch (_) {
        // Leave both false — a query hiccup just means no dot.
      }
      cells.add(<String, dynamic>{
        'd': d,
        if (p.isToday(d, hm, hy)) 'today': true,
        if (isl) 'isl': true,
        if (evt) 'evt': true,
      });
    }

    // The 6th row is only needed when the month spills into it.
    final visibleRows = (firstOffset + daysInMonth) > 35 ? 6 : 5;

    // Gregorian secondary label — the civil month/year around the
    // middle of this Hijri month.
    final gregMid = p.hijriToGregorian(hy, hm, 15);

    return jsonEncode(<String, dynamic>{
      'hy': hy,
      'hm': hm,
      'title': '${p.getHijriMonthName(hm, loc)} $hy',
      'gregTitle': '${_pad2(gregMid.month)}/${gregMid.year}',
      'weekdays': _weekdayHeader(loc),
      'isDark': isDark,
      'isRtl': loc == 'ar',
      'accent': _hex(AppColors.green),
      'visibleRows': visibleRows,
      'cells': cells,
    });
  }

  static String _pad2(int n) => n.toString().padLeft(2, '0');

  /// Monday-based weekday header — byte-identical to the app's
  /// monthly grid header (`_buildWeekdayHeader`). The app uses the
  /// French abbreviations for every non-Arabic locale; we match that
  /// for consistency rather than introduce a new set.
  static List<String> _weekdayHeader(String loc) => loc == 'ar'
      ? const ['إث', 'ث', 'أر', 'خ', 'ج', 'س', 'أح']
      : const ['Lu', 'Ma', 'Me', 'Je', 'Ve', 'Sa', 'Di'];

  /// Color → `#AARRGGBB` string for Android's `Color.parseColor`.
  static String _hex(Color c) {
    final v = c.value & 0xFFFFFFFF;
    return '#${v.toRadixString(16).padLeft(8, '0').toUpperCase()}';
  }
}
