import 'dart:convert';

import 'package:flutter/material.dart';

import '../providers/app_provider.dart';
import '../theme.dart';
import '../utils/text_format.dart';

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
/// The payload now carries a WINDOW of months (today ± [_windowRadius])
/// rather than just the current month, so that the in-widget month
/// navigation arrows (and the "Today" button) can switch months
/// PURELY natively — no Flutter callback, no app launch — by picking
/// a different month from the cached window. This keeps month
/// switching instant and avoids the cost of waking a Flutter isolate
/// from the launcher's process.
///
/// Per-day visual state inside each month is taken DIRECTLY from the
/// in-app `_DayCell` in lib/screens/calendar_screen.dart so the
/// widget matches the real calendar 1:1 within RemoteViews' limits:
///   * background priority: today > selected > ayyam-al-bid > ramadan;
///   * Friday cells get accent-coloured text when not otherwise
///     overridden;
///   * each cell carries up to 3 event colours, exactly like the dots
///     `_DayCell` paints. Daily adhkar (morning / evening / sleep)
///     are filtered out so they don't dot every single day;
///   * each cell carries its Hijri day number AND the Gregorian day
///     number — same dual-number layout as `_DayCell`.
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

  /// Window radius — the payload covers months [today - radius,
  /// today + radius] with FULL data (events, ayyam-al-bid,
  /// ramadan). Trade-off: bigger = more navigable but heavier to
  /// build (each extra month is one `getDaysInMonth` +
  /// `getFirstWeekdayOfMonth` + up to 30 `getEventsForDay` calls).
  ///
  /// 24 = two years either side of INSTANT, full-data navigation.
  static const int _windowRadius = 24;

  /// Hard navigation limit, in months, for "skeleton" navigation
  /// past the full-data window. The Kotlin renderer can synthesise
  /// any month inside this radius natively (own Hijri kernel —
  /// `android_patches/kotlin/HijriKernel.kt` — mirrors
  /// `lib/utils/hijri_utils.dart` 1:1) without needing a JSON
  /// pre-bake. 360 = 30 years past + 30 years future, which is
  /// the spec's "scroll like Google Calendar" target. Beyond this
  /// the widget falls through to opening the in-app calendar
  /// (which is truly infinite via PageView).
  static const int _maxNavRadius = 360;

  /// Shared-prefs key the native provider reads. MUST match the key
  /// used in MiniCalendarWidgetProvider.kt and WidgetSyncService.
  static const String dataKey = 'mini_calendar_data';

  /// Builds the JSON payload for the visible window of months
  /// centred on today's Hijri month.
  ///
  /// Async + per-month `await` so the 25-month build doesn't block
  /// the Flutter event loop in one shot — UI animations can still
  /// land between months. Total CPU cost is the same; perceived
  /// jank goes from ~750 ms to ~30 ms slices.
  ///
  /// The widget's "selected day" highlight is OWNED by the native
  /// side (MiniCalendarWidgetProvider holds it in its own
  /// SharedPreferences with a TTL), so this builder no longer
  /// emits a `bg = 'selected'` state — the Kotlin renderer
  /// overlays selection from its local state, completely
  /// decoupled from `p.selectedDay`. That separation is what lets
  /// a single tap on a widget cell select WITHOUT opening the app
  /// (and without polluting the in-app selection).
  static Future<String> buildJson(AppProvider p) async {
    final nowH = p.today;
    final loc = p.locale;

    final isDark = p.themeMode == ThemeMode.dark ||
        (p.themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);

    // Pre-compute every month in the window. The Kotlin side picks
    // one based on the user's saved view offset; having them all in
    // the payload means in-window navigation is purely native.
    // Yields the event loop between months so the 25-month build
    // doesn't freeze the UI in one shot.
    //
    // The "selected day" highlight is OWNED by the Kotlin renderer
    // (it has its own SharedPreferences + TTL + AlarmManager-driven
    // clear), so we don't pass any selection coordinates here.
    final months = <Map<String, dynamic>>[];
    for (int offset = -_windowRadius; offset <= _windowRadius; offset++) {
      months.add(_buildMonth(
        p: p,
        offset: offset,
        loc: loc,
        baseHy: nowH.hYear,
        baseHm: nowH.hMonth,
        todayHy: nowH.hYear,
        todayHm: nowH.hMonth,
        todayHd: nowH.hDay,
      ));
      // Yield to the event loop so a long build can't block
      // animations / gestures running on the UI isolate.
      await Future<void>.delayed(Duration.zero);
    }

    return jsonEncode(<String, dynamic>{
      'todayHy': nowH.hYear,
      'todayHm': nowH.hMonth,
      'todayHd': nowH.hDay,
      'isDark': isDark,
      'isRtl': loc == 'ar',
      // Palette — the native side recolours static white drawables
      // with these via setColorFilter so the widget tracks AccentBus.
      'accent': _hex(AppColors.green),
      'accentPale': _hex(AppColors.greenPale),
      'goldPale': _hex(AppColors.goldPale),
      'weekdays': _weekdayHeader(loc),
      // Region-aware Hijri day offset, mirroring what the in-app
      // calendar already uses (`AppProvider.hijriDayOffset`). The
      // Kotlin side passes this into HijriKernel.kt for any
      // skeleton month it synthesises so far-future / far-past
      // months on the widget agree with the in-app calendar
      // bit-for-bit.
      'hijriOffset': p.hijriDayOffset,
      // 12-entry locale-aware tables so the Kotlin skeleton
      // generator can produce titles without duplicating the
      // app's localisation data.
      'hijriMonthNames': List<String>.generate(
        12, (i) => p.getHijriMonthName(i + 1, loc),
      ),
      'gregMonthNames': List<String>.generate(
        12, (i) => TextFormat.gregorianMonthShort(i + 1, loc),
      ),
      'windowRadius': _windowRadius,
      'maxNavRadius': _maxNavRadius,
      'months': months,
    });
  }

  /// Builds one month's worth of cells + headings, [offset] months
  /// away from ([baseHy], [baseHm]). Mirrors `_DayCell` exactly —
  /// except for the `selected` background, which is overlaid by
  /// the Kotlin renderer from its own local state, not from here.
  static Map<String, dynamic> _buildMonth({
    required AppProvider p,
    required int offset,
    required String loc,
    required int baseHy,
    required int baseHm,
    required int todayHy,
    required int todayHm,
    required int todayHd,
  }) {
    // Hijri month arithmetic — same as the app's _MonthlyView /
    // `hijriForIndex` pattern (lib/screens/calendar_screen.dart).
    int hy = baseHy;
    int hm = baseHm + offset;
    while (hm < 1) {
      hm += 12;
      hy -= 1;
    }
    while (hm > 12) {
      hm -= 12;
      hy += 1;
    }

    final daysInMonth = p.getDaysInMonth(hy, hm);
    // getFirstWeekdayOfMonth: 1=Mon..7=Sun. The grid is Monday-based,
    // so column 0 = Monday — identical to `_MonthPage` in the app.
    final firstOffset = (p.getFirstWeekdayOfMonth(hy, hm) - 1) % 7;

    final isRamadan = p.isRamadan(hm);

    final cells = <Map<String, dynamic>>[];
    for (int i = 0; i < _gridCells; i++) {
      final d = i - firstOffset + 1;
      if (d < 1 || d > daysInMonth) {
        cells.add(const {'d': 0}); // blank cell
        continue;
      }

      final isTodayCell =
          todayHy == hy && todayHm == hm && todayHd == d;
      final isAyyam = p.isAyyamAlBid(d);
      final isFri = (i % 7) == 4;

      int g = 0;
      try {
        g = p.hijriToGregorian(hy, hm, d).day;
      } catch (_) {
        // Region/offset edge: leave 0 → the native side hides the
        // secondary line for this cell instead of showing nonsense.
      }

      // Selected is intentionally absent here: the Kotlin renderer
      // overlays the 'selected' state from its own SharedPreferences
      // (with a TTL + AlarmManager-driven clear), so a single tap
      // can select WITHOUT opening the app or polluting the in-app
      // selection. Priority on the Kotlin side stays: today >
      // selected > ayyam > ramadan, matching `_DayCell`.
      String? bg;
      if (isTodayCell) {
        bg = 'today';
      } else if (isAyyam) {
        bg = 'ayyam';
      } else if (isRamadan) {
        bg = 'ramadan';
      }

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
        if (g > 0) 'g': g,
        if (bg != null) 'bg': bg,
        if (isFri) 'fri': true,
        if (dots.isNotEmpty) 'dots': dots,
      });
    }

    final visibleRows = (firstOffset + daysInMonth) > 35 ? 6 : 5;
    final gregMid = p.hijriToGregorian(hy, hm, 15);

    return <String, dynamic>{
      'offset': offset,
      'hy': hy,
      'hm': hm,
      'title': '${p.getHijriMonthName(hm, loc)} $hy',
      'gregTitle': TextFormat.formatGregorianMonthYear(gregMid, loc),
      'visibleRows': visibleRows,
      'cells': cells,
    };
  }

  /// Monday-based weekday header, localised for each of the app's
  /// four supported locales (ar / fr / en / es). The Arabic row
  /// matches the in-app `_buildWeekdayHeader` exactly. The widget
  /// always renders Monday first; the layout file picked at
  /// runtime (LTR vs forced-RTL) handles visual mirroring so
  /// Arabic devices AND Arabic-app-on-LTR-devices both show
  /// Monday on the right.
  static List<String> _weekdayHeader(String loc) {
    switch (loc) {
      case 'ar':
        return const ['إث', 'ث', 'أر', 'خ', 'ج', 'س', 'أح'];
      case 'fr':
        return const ['Lu', 'Ma', 'Me', 'Je', 'Ve', 'Sa', 'Di'];
      case 'es':
        return const ['Lu', 'Ma', 'Mi', 'Ju', 'Vi', 'Sa', 'Do'];
      case 'en':
      default:
        return const ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
    }
  }

  /// Color → `#AARRGGBB` string for Android's `Color.parseColor`.
  static String _hex(Color c) {
    final v = c.value & 0xFFFFFFFF;
    return '#${v.toRadixString(16).padLeft(8, '0').toUpperCase()}';
  }
}
