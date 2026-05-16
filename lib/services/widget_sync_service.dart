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
///     for a Mini Calendar cell, to that exact day).
///
/// Performance & stability contract (matches the spec's "Forbidden"
/// list):
///   * Renders are DEBOUNCED — the provider notifies on nearly every
///     interaction; a 700 ms coalescing window collapses bursts into
///     a single render.
///   * Change-detection (the snapshot [WidgetSnapshot.signature] for
///     the bitmap widgets, a JSON diff for the Mini Calendar) skips
///     work when nothing a widget shows actually changed.
///   * A `_rendering` guard plus re-arm prevents overlapping renders
///     and guarantees the latest state still lands (no lost update,
///     no infinite loop).
///   * Every path is wrapped in try/catch and logged through
///     [AppLogger]: if `home_widget` or the platform misbehaves, the
///     host app keeps running exactly as before.
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
  /// listens to this to switch its bottom-nav back to the Calendar tab;
  /// the view mode (and, for a Mini Calendar cell, the selected day)
  /// is set on the provider.
  final ValueNotifier<int> openMonthlyTick = ValueNotifier<int>(0);

  /// Set to the prefilled start [DateTime] when a Mini Calendar day
  /// cell is DOUBLE-TAPPED. `HomeScreen` listens and pushes the
  /// `AddEventScreen(initialStart: ...)` route — mirrors the in-app
  /// `_DayCell.onDoubleTap` flow exactly. Reset to null by the
  /// listener after it consumes the value so a stale push can't
  /// re-fire.
  final ValueNotifier<DateTime?> openAddEventForDate =
      ValueNotifier<DateTime?>(null);

  /// How long after a single widget-day tap the green "selected"
  /// highlight stays visible on the Mini Calendar. Cleared earlier
  /// (via [handleAppPaused]) when the user leaves the launcher.
  static const Duration _selectionTtl = Duration(seconds: 8);

  /// Window inside which two widget-day taps on the SAME day count as
  /// a double tap. RemoteViews can't natively detect a double tap, so
  /// we detect it here on the Dart side from the URI delivery stream.
  static const Duration _doubleTapWindow = Duration(milliseconds: 400);

  AppProvider? _provider;
  Timer? _debounce;
  Timer? _selectionTimer;
  StreamSubscription<Uri?>? _clickSub;
  bool _rendering = false;
  String? _lastSignature;
  String? _lastMiniJson;
  /// Whether the Mini Calendar should render the user-selected day
  /// highlight on the current push. Off by default so the widget
  /// never persists a "selected day" between sessions; flipped on
  /// briefly after a widget-day tap and cleared by [handleAppPaused]
  /// or the [_selectionTimer].
  bool _showWidgetSelection = false;
  /// Last widget-day tap, for double-tap detection. Cleared after
  /// being consumed by the double-tap branch.
  ({DateTime time, int hy, int hm, int hd})? _lastDayTap;

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
    _selectionTimer?.cancel();
    _selectionTimer = null;
    _clickSub?.cancel();
    _clickSub = null;
  }

  /// Called from `main.dart`'s `AppLifecycleState.paused` handler so
  /// the Mini Calendar never holds a stale "selected day" highlight
  /// after the user leaves the launcher / opens any app. No-op when
  /// the highlight wasn't currently being shown.
  void handleAppPaused() {
    if (!_showWidgetSelection) return;
    _selectionTimer?.cancel();
    _selectionTimer = null;
    _showWidgetSelection = false;
    _lastDayTap = null;
    requestSync();
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
  /// Every widget opens the monthly calendar view. A Mini Calendar
  /// day cell additionally carries the exact Hijri date it represents
  /// (`?hy=&hm=&hd=`); when present:
  ///   * a SINGLE tap navigates the calendar to that month and
  ///     selects the day, and lights the widget's "selected"
  ///     highlight briefly (cleared on the [_selectionTimer] or by
  ///     [handleAppPaused]);
  ///   * a DOUBLE tap (a second URI delivery for the SAME day inside
  ///     [_doubleTapWindow]) ADDITIONALLY pushes the "New Event"
  ///     screen prefilled with that day — same flow as the in-app
  ///     `_DayCell.onDoubleTap` in lib/screens/calendar_screen.dart.
  ///
  /// RemoteViews can't report a double tap natively (each launcher
  /// tap fires its own PendingIntent), so detection lives here.
  void _onWidgetUri(Uri? uri) {
    if (uri == null) return;
    final p = _provider;
    if (p == null) return;
    try {
      p.setViewMode(CalendarViewMode.monthly);
      final hy = int.tryParse(uri.queryParameters['hy'] ?? '');
      final hm = int.tryParse(uri.queryParameters['hm'] ?? '');
      final hd = int.tryParse(uri.queryParameters['hd'] ?? '');

      if (hy != null && hm != null && hd != null) {
        final now = DateTime.now();
        final last = _lastDayTap;
        final isDoubleTap = last != null &&
            last.hy == hy &&
            last.hm == hm &&
            last.hd == hd &&
            now.difference(last.time) <= _doubleTapWindow;

        if (isDoubleTap) {
          // Consume so a third tap can't be read as another "double".
          _lastDayTap = null;
          // Same sequence as `_DayCell.onDoubleTap`: select the day
          // first, then push the new-event screen prefilled with the
          // Gregorian instant at 09:00 local on that day. The Hijri
          // → Gregorian conversion goes through the provider so it
          // honours the active region's day offset.
          p.selectDay(HijriDate(hy, hm, hd));
          DateTime g;
          try {
            g = p.hijriToGregorian(hy, hm, hd);
          } catch (_) {
            g = DateTime.now();
          }
          openAddEventForDate.value =
              DateTime(g.year, g.month, g.day, 9, 0);
        } else {
          _lastDayTap = (time: now, hy: hy, hm: hm, hd: hd);
          // Single-tap behaviour preserved exactly.
          p.setCurrentMonth(hy, hm);
          p.selectDay(HijriDate(hy, hm, hd));
          _activateWidgetSelection();
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

  /// Lights the Mini Calendar's "selected day" highlight for
  /// [_selectionTtl] (currently 8 s), then clears it. The clear is a
  /// safety net — in practice [handleAppPaused] kicks in first when
  /// the user leaves the launcher to look at the app they just
  /// opened.
  void _activateWidgetSelection() {
    _showWidgetSelection = true;
    _selectionTimer?.cancel();
    _selectionTimer = Timer(_selectionTtl, () {
      _selectionTimer = null;
      if (!_showWidgetSelection) return;
      _showWidgetSelection = false;
      requestSync();
    });
    requestSync();
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
      // The "selected day" highlight on the widget is opt-in per
      // render: off by default (so the widget never shows a stale
      // selection between sessions), flipped on briefly by
      // _activateWidgetSelection after a widget-day tap.
      miniJson = MiniCalendarData.buildJson(
        p,
        includeSelected: _showWidgetSelection,
      );
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
