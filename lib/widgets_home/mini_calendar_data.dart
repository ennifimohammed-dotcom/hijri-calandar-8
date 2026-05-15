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
///
/// Per-day visual state is taken DIRECTLY from the in-app
/// `_DayCell` in lib/screens/calendar_screen.dart so the widget
/// matches the real calendar 1:1 within RemoteViews' limits:
///
///   * background priority (matches `_DayCell`):
///       today > selected > ayyam-al-bid > ramadan;
///   * Friday cells get accent-coloured text when not otherwise
///     overridden (same rule as `_DayCell`);
///   * each cell carries up to 3 event colours, exactly like the
///     dots painted in `_DayCell`. Daily adhkar (morning / evening /
///     sleep) are filtered out so they don't dot every single day.
///
/// The accent / accent-pale / gold-pale colours are sent on every
/// payload so the native side can recolour rounded highlights via
/// `ImageView.setColorFilter` and follow the user's chosen swatch
/// without having to know `AccentBus` exists.
class MiniCalendarData {
  MiniCalendarData._();

  /// 6 rows x 7 columns. The native layout has exactly this many
  /// cells; the 6th row is hidden when the month doesn't reach it.
  static const int _gridCells = 42;

  /// Shared-prefs key the native provider reads. MUST match the key
  /// used in MiniCalendarWidgetProvider.kt and WidgetSyncService.
  static const String dataKey = 'mini_calendar_data';

  /// Builds the JSON payload for the month containing today.
  static String buildJson(AppProvider p) {
    final nowH = p.today;
    final hy = nowH.hYear;
    final hm = nowH.hMonth;
    final loc = p.locale;

    final daysInMonth = p.getDaysInMonth(hy, hm);
    // getFirstWeekdayOfMonth: 1=Mon..7=Sun. The grid is Monday-based,
    // so column 0 = Monday — identical to `_MonthPage` in the app.
    final firstOffset = (p.getFirstWeekdayOfMonth(hy, hm) - 1) % 7;

    final isDark = p.themeMode == ThemeMode.dark ||
        (p.themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);

    final isRamadan = p.isRamadan(hm);

    // Selected day — only paint the highlight when the user's current
    // selection is in the month this widget is showing.
    final selHy = p.selectedDay?.hYear;
    final selHm = p.selectedDay?.hMonth;
    final selHd = p.selectedDay?.hDay;
    final hasSelectionThisMonth = selHy == hy && selHm == hm;

    final cells = <Map<String, dynamic>>[];
    for (int i = 0; i < _gridCells; i++) {
      final d = i - firstOffset + 1;
      if (d < 1 || d > daysInMonth) {
        cells.add(const {'d': 0}); // blank cell
        continue;
      }

      // Mirrors `_DayCell` exactly.
      final isTodayCell = p.isToday(d, hm, hy);
      final isSelected = hasSelectionThisMonth && selHd == d;
      final isAyyam = p.isAyyamAlBid(d);
      // Mon-based grid → column 4 is Friday. Avoids a Hijri→Gregorian
      // round-trip per cell.
      final isFri = (i % 7) == 4;

      // Same priority order as `_DayCell` so the widget can't ever
      // disagree with the app on which highlight wins.
      String? bg;
      if (isTodayCell) {
        bg = 'today';
      } else if (isSelected) {
        bg = 'selected';
      } else if (isAyyam) {
        bg = 'ayyam';
      } else if (isRamadan) {
        bg = 'ramadan';
      }

      // Up to 3 event dots — same `take(3)` as `_DayCell`. Each dot
      // keeps the event's actual `color`, so user-defined colours and
      // Islamic-event gold both come through faithfully. Daily adhkar
      // are filtered so they don't appear on every day.
      final dots = <String>[];
      try {
        final events = p
            .getEventsForDay(d, hm, hy)
            .where((e) => !p.isDailyAdhkar(e.id))
            .take(3);
        for (final e in events) {
          dots.add(_hex(e.color));
        }
      } catch (_) {
        // A query hiccup just means no dots for this day.
      }

      cells.add(<String, dynamic>{
        'd': d,
        if (bg != null) 'bg': bg,
        if (isFri) 'fri': true,
        if (dots.isNotEmpty) 'dots': dots,
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
      'isRamadan': isRamadan,
      // Palette — the native side recolours static white drawables
      // with these via setColorFilter so the widget tracks AccentBus.
      'accent': _hex(AppColors.green),
      'accentPale': _hex(AppColors.greenPale),
      'goldPale': _hex(AppColors.goldPale),
      'visibleRows': visibleRows,
      'cells': cells,
    });
  }

  static String _pad2(int n) => n.toString().padLeft(2, '0');

  /// Monday-based weekday header — byte-identical to the app's
  /// monthly grid header (`_buildWeekdayHeader`).
  static List<String> _weekdayHeader(String loc) => loc == 'ar'
      ? const ['إث', 'ث', 'أر', 'خ', 'ج', 'س', 'أح']
      : const ['Lu', 'Ma', 'Me', 'Je', 'Ve', 'Sa', 'Di'];

  /// Color → `#AARRGGBB` string for Android's `Color.parseColor`.
  static String _hex(Color c) {
    final v = c.value & 0xFFFFFFFF;
    return '#${v.toRadixString(16).padLeft(8, '0').toUpperCase()}';
  }
}
