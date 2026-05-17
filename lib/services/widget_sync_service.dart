import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../providers/app_provider.dart';
import '../theme.dart';
import '../utils/app_logger.dart';
import '../utils/hijri_utils.dart';
import '../widgets_home/hijri_date_widget_view.dart';
import '../widgets_home/islamic_day_widget_view.dart';
import '../widgets_home/mini_calendar_data.dart';
import '../widgets_home/widget_snapshot.dart';

/// Home-screen widget sync layer.
///
/// Bridges the in-app [AppProvider] (the single source of truth for
/// calendar + theme + region + font + locale + Islamic events) to the
/// native Android home-screen widgets — WITHOUT creating a parallel
/// settings system:
///
///   * it only ever READS from the provider;
///   * the "Hijri Date" and "Islamic Day" widgets are Flutter widgets
///     rendered to PNGs via `home_widget`'s `renderFlutterWidget`;
///   * the "Mini Calendar" widget is rendered NATIVELY from a JSON
///     data payload (so every day cell can be tapped individually) —
///     see [MiniCalendarData];
///   * it asks the native AppWidgets to reload;
///   * it routes a widget tap to the calendar (the monthly view, and
///     for a Mini Calendar double-tap, additionally pushes the New
///     Event screen for the tapped day).
///
/// Single-tap on a Mini Calendar day cell is now handled ENTIRELY
/// natively — the Kotlin renderer maintains the transient "selected
/// day" highlight in its own SharedPreferences (TTL + AlarmManager
/// driven clear). Dart only sees double-tap URIs (carry `ne=1`) and
/// month-only URIs (out-of-window nav arrows).
///
/// Performance & stability contract:
///   * Renders are DEBOUNCED — the provider notifies on nearly every
///     interaction; a 700 ms coalescing window collapses bursts.
///   * Change-detection (snapshot signature + JSON diff) skips work
///     when nothing displayed actually changed.
///   * A `_rendering` guard plus re-arm prevents overlapping renders.
///   * Every path is wrapped in try/catch and logged.
class WidgetSyncService {
  WidgetSyncService._();

  /// Process-wide singleton — bound once from `main.dart`.
  static final WidgetSyncService instance = WidgetSyncService._();

  /// Fully-qualified native provider classes. MUST match the
  /// `<receiver android:name=".*WidgetProvider">` entries in
  /// android_patches/AndroidManifest.xml.
  static const String _hijriDateProvider =
      'com.hijricalendar.hijri_calendar.HijriDateWidgetProvider';
  static const String _islamicDayProvider =
      'com.hijricalendar.hijri_calendar.IslamicDayWidgetProvider';
  static const String _miniCalendarProvider =
      'com.hijricalendar.hijri_calendar.MiniCalendarWidgetProvider';

  /// Shared-prefs keys the native providers read. MUST match the keys
  /// used in the *WidgetProvider.kt files.
  static const String _hijriDateImageKey = 'hijri_date_widget_image';
  static const String _islamicDayImageKey = 'islamic_day_widget_image';

  /// Coalescing window for rapid-fire provider notifications.
  static const Duration _debounceWindow = Duration(milliseconds: 700);

  /// Bumped every time a widget tap asks for the calendar. `HomeScreen`
  /// listens to this to switch its bottom-nav back to the Calendar tab.
  final ValueNotifier<int> openMonthlyTick = ValueNotifier<int>(0);

  /// Set to the prefilled start [DateTime] when a Mini Calendar day
  /// cell is DOUBLE-TAPPED. `HomeScreen` listens and pushes the
  /// `AddEventScreen(initialStart: ...)` route — mirrors the in-app
  /// `_DayCell.onDoubleTap` flow exactly. Reset to null by the
  /// listener after it consumes the value so a stale push can't
  /// re-fire.
  final ValueNotifier<DateTime?> openAddEventForDate =
      ValueNotifier<DateTime?>(null);

  AppProvider? _provider;
  Timer? _debounce;
  StreamSubscription<Uri?>? _clickSub;
  bool _rendering = false;
  String? _lastSignature;
  String? _lastMiniJson;

  /// Wires the service to the live provider. Safe to call once, from
  /// `main.dart`'s `initState` (post-frame). Adds a listener, triggers
  /// an initial sync, and starts handling widget taps.
  void bind(AppProvider provider) {
    if (_provider != null) return;
    _provider = provider;
    provider.addListener(_onProviderChanged);
    requestSync();

    // Warm-start taps: the app is already running and a widget (or a
    // Mini Calendar day cell) is tapped. `home_widget` delivers the
    // launch URI on this stream.
    _clickSub = HomeWidget.widgetClicked.listen(
      _onWidgetUri,
      onError: (Object e, StackTrace s) => AppLogger.error(
        'WidgetSyncService: widgetClicked stream error',
        error: e,
        stack: s,
      ),
    );
    // Cold-start taps: the app was launched BY the widget tap.
    unawaited(_checkColdLaunch());
  }

  /// Detaches the service — called from `main.dart`'s `dispose`.
  void unbind() {
    _provider?.removeListener(_onProviderChanged);
    _provider = null;
    _debounce?.cancel();
    _debounce = null;
    _clickSub?.cancel();
    _clickSub = null;
  }

  void _onProviderChanged() => requestSync();

  /// Requests a (debounced) widget refresh. Also called directly from
  /// `main.dart` on `AppLifecycleState.resumed` so a date rollover or
  /// a settings change made while backgrounded is picked up.
  void requestSync() {
    _debounce?.cancel();
    _debounce = Timer(_debounceWindow, _render);
  }

  // ── Widget tap → calendar ────────────────────────────────────

  Future<void> _checkColdLaunch() async {
    try {
      _onWidgetUri(await HomeWidget.initiallyLaunchedFromHomeWidget());
    } catch (e, s) {
      AppLogger.error('WidgetSyncService: cold-launch check failed',
          error: e, stack: s);
    }
  }

  /// Handles a launch/click URI coming from a home-screen widget.
  ///
  /// Reaches Dart in only three situations now:
  ///   * a SINGLE tap on the Hijri Date / Islamic Day widget — opens
  ///     the monthly view, no query params;
  ///   * a Mini Calendar DOUBLE tap — URI carries `?hy=&hm=&hd=&ne=1`
  ///     (the `ne=1` flag is set by Kotlin's double-tap branch); we
  ///     mirror `_DayCell.onDoubleTap` and push AddEventScreen
  ///     prefilled with that day at 09:00 local;
  ///   * a Mini Calendar OUT-OF-WINDOW arrow — URI carries `?hy=&hm=`
  ///     (no day, no `ne` flag); we just navigate the in-app calendar
  ///     to that month so the user can continue inside the app's
  ///     truly-infinite PageView.
  ///
  /// Mini Calendar SINGLE taps never reach this method — they are
  /// handled entirely natively (Kotlin's `MINI_CAL_DAY_TAP`
  /// broadcast), so a single tap only paints the transient selection
  /// highlight on the widget without opening the app or touching the
  /// in-app selection.
  void _onWidgetUri(Uri? uri) {
    if (uri == null) return;
    final p = _provider;
    if (p == null) return;
    try {
      p.setViewMode(CalendarViewMode.monthly);
      final hy = int.tryParse(uri.queryParameters['hy'] ?? '');
      final hm = int.tryParse(uri.queryParameters['hm'] ?? '');
      final hd = int.tryParse(uri.queryParameters['hd'] ?? '');
      final isNewEvent = uri.queryParameters['ne'] == '1';

      if (isNewEvent && hy != null && hm != null && hd != null) {
        // Mini Calendar double-tap. Mirrors `_DayCell.onDoubleTap`:
        // select the day, then push the new-event screen prefilled
        // with the Gregorian instant at 09:00 local on that day.
        // Hijri → Gregorian goes through the provider so it honours
        // the active region's day offset.
        p.selectDay(HijriDate(hy, hm, hd));
        DateTime g;
        try {
          g = p.hijriToGregorian(hy, hm, hd);
        } catch (_) {
          g = DateTime.now();
        }
        openAddEventForDate.value = DateTime(g.year, g.month, g.day, 9, 0);
      } else if (hy != null && hm != null) {
        // Month / day navigation from a widget — either an
        // out-of-window arrow (no `hd`) or any other URI that
        // happens to carry a day. Mini Calendar single taps DO
        // NOT reach here — they're handled natively.
        p.setCurrentMonth(hy, hm);
        if (hd != null) {
          p.selectDay(HijriDate(hy, hm, hd));
        }
      }
      // Nudge HomeScreen back to the Calendar tab (covers the
      // warm-start case where another tab was open).
      openMonthlyTick.value++;
    } catch (e, s) {
      AppLogger.error('WidgetSyncService: handling widget tap failed',
          error: e, stack: s);
    }
  }

  // ── Render → push ────────────────────────────────────────────

  Future<void> _render() async {
    final p = _provider;
    if (p == null) return;

    // Provider still booting — `today` and friends aren't ready yet.
    // AppProvider.init() ends with notifyListeners(), which re-arms
    // this through _onProviderChanged.
    if (p.isLoading) return;

    // A render is already in flight — re-arm so the latest state
    // still lands once it finishes (eventual consistency, no loop:
    // the re-render no-ops via the change checks if unchanged).
    if (_rendering) {
      requestSync();
      return;
    }

    WidgetSnapshot snap;
    String miniJson;
    try {
      snap = WidgetSnapshot.fromProvider(p);
      // buildJson is async — it yields the event loop per month so
      // the 25-month window doesn't freeze UI animations during a
      // sync. Selection is owned natively now, so no flag to pass.
      miniJson = await MiniCalendarData.buildJson(p);
    } catch (e, s) {
      AppLogger.error('WidgetSyncService: snapshot build failed',
          error: e, stack: s);
      return;
    }

    final bool snapChanged = snap.signature != _lastSignature;
    final bool miniChanged = miniJson != _lastMiniJson;
    // Nothing any widget displays changed — skip all work.
    if (!snapChanged && !miniChanged) return;

    _rendering = true;
    try {
      // Keep the off-tree render on the user's chosen font, exactly
      // as main.dart does for the in-app tree.
      AppTheme.setActiveFontFamily(snap.fontFamily);

      // The two bitmap widgets are driven by the same snapshot, so
      // they render and refresh together.
      if (snapChanged) {
        await HomeWidget.renderFlutterWidget(
          HijriDateWidgetView(snapshot: snap),
          key: _hijriDateImageKey,
          logicalSize: HijriDateWidgetView.canvasSize,
          pixelRatio: 3.0,
        );
        await HomeWidget.renderFlutterWidget(
          IslamicDayWidgetView(snapshot: snap),
          key: _islamicDayImageKey,
          logicalSize: IslamicDayWidgetView.canvasSize,
          pixelRatio: 3.0,
        );
        await HomeWidget.updateWidget(qualifiedAndroidName: _hijriDateProvider);
        await HomeWidget.updateWidget(qualifiedAndroidName: _islamicDayProvider);
        _lastSignature = snap.signature;
      }

      // The Mini Calendar is native-rendered: push the JSON data and
      // let the native provider rebuild its grid.
      if (miniChanged) {
        await HomeWidget.saveWidgetData<String>(
            MiniCalendarData.dataKey, miniJson);
        await HomeWidget.updateWidget(
            qualifiedAndroidName: _miniCalendarProvider);
        _lastMiniJson = miniJson;
      }
    } catch (e, s) {
      AppLogger.error('WidgetSyncService: render/update failed',
          error: e, stack: s);
    } finally {
      _rendering = false;
    }
  }
}
