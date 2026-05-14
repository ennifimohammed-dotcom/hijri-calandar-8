import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../providers/app_provider.dart';
import '../theme.dart';
import '../utils/app_logger.dart';
import '../widgets_home/hijri_date_widget_view.dart';
import '../widgets_home/islamic_day_widget_view.dart';
import '../widgets_home/widget_snapshot.dart';

/// Home-screen widget sync layer.
///
/// Bridges the in-app [AppProvider] (the single source of truth for
/// calendar + theme + region + font + locale + Islamic events) to the
/// native Android home-screen widgets ("Hijri Date" and "Islamic
/// Day") — WITHOUT creating a parallel settings system:
///
///   * it only ever READS from the provider;
///   * it renders the premium widget views to PNGs via
///     `home_widget`'s `renderFlutterWidget`;
///   * it asks the native AppWidgets to reload those PNGs;
///   * it routes a widget tap to the monthly calendar view.
///
/// Performance & stability contract (matches the spec's "Forbidden"
/// list):
///   * Renders are DEBOUNCED — the provider notifies on nearly every
///     interaction; a 700 ms coalescing window collapses bursts into
///     a single render.
///   * A [WidgetSnapshot.signature] check skips the render entirely
///     when nothing the widget shows actually changed.
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

  /// Shared-prefs keys the native providers read to locate their
  /// rendered PNGs. MUST match the keys used in the *WidgetProvider.kt
  /// files.
  static const String _hijriDateImageKey = 'hijri_date_widget_image';
  static const String _islamicDayImageKey = 'islamic_day_widget_image';

  /// Coalescing window for rapid-fire provider notifications.
  static const Duration _debounceWindow = Duration(milliseconds: 700);

  /// Bumped every time a widget tap asks for the monthly view.
  /// `HomeScreen` listens to this to switch its bottom-nav back to
  /// the Calendar tab; the view mode itself is set on the provider.
  final ValueNotifier<int> openMonthlyTick = ValueNotifier<int>(0);

  AppProvider? _provider;
  Timer? _debounce;
  StreamSubscription<Uri?>? _clickSub;
  bool _rendering = false;
  String? _lastSignature;

  /// Wires the service to the live provider. Safe to call once, from
  /// `main.dart`'s `initState` (post-frame). Adds a listener, triggers
  /// an initial sync, and starts handling widget taps.
  void bind(AppProvider provider) {
    if (_provider != null) return;
    _provider = provider;
    provider.addListener(_onProviderChanged);
    requestSync();

    // Warm-start taps: the app is already running and the widget is
    // tapped. `home_widget` delivers the launch URI on this stream.
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

  // ── Widget tap → monthly view ────────────────────────────────

  Future<void> _checkColdLaunch() async {
    try {
      _onWidgetUri(await HomeWidget.initiallyLaunchedFromHomeWidget());
    } catch (e, s) {
      AppLogger.error('WidgetSyncService: cold-launch check failed',
          error: e, stack: s);
    }
  }

  /// Handles a launch/click URI coming from the home-screen widget.
  /// There is one widget and one action, so any non-null URI means
  /// "open the monthly calendar view".
  void _onWidgetUri(Uri? uri) {
    if (uri == null) return;
    final p = _provider;
    if (p == null) return;
    try {
      p.setViewMode(CalendarViewMode.monthly);
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
    // the re-render no-ops via the signature check if unchanged).
    if (_rendering) {
      requestSync();
      return;
    }

    WidgetSnapshot snap;
    try {
      snap = WidgetSnapshot.fromProvider(p);
    } catch (e, s) {
      AppLogger.error('WidgetSyncService: snapshot build failed',
          error: e, stack: s);
      return;
    }

    // Nothing the widget displays changed — skip the render.
    if (snap.signature == _lastSignature) return;

    _rendering = true;
    try {
      // Keep the off-tree render on the user's chosen font, exactly
      // as main.dart does for the in-app tree.
      AppTheme.setActiveFontFamily(snap.fontFamily);

      // Both widgets are driven by the same snapshot, so they render
      // and refresh together.
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
    } catch (e, s) {
      AppLogger.error('WidgetSyncService: render/update failed',
          error: e, stack: s);
    } finally {
      _rendering = false;
    }
  }
}
