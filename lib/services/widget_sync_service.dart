import 'dart:async';

import 'package:home_widget/home_widget.dart';

import '../providers/app_provider.dart';
import '../theme.dart';
import '../utils/app_logger.dart';
import '../widgets_home/hijri_date_widget_view.dart';
import '../widgets_home/widget_snapshot.dart';

/// Phase 0 + 1 — home-screen widget sync layer.
///
/// Bridges the in-app [AppProvider] (the single source of truth for
/// calendar + theme + region + font + locale) to the native Android
/// "Hijri Date" home-screen widget — WITHOUT creating a parallel
/// settings system:
///
///   * it only ever READS from the provider;
///   * it renders the premium [HijriDateWidgetView] to a PNG via
///     `home_widget`'s `renderFlutterWidget`;
///   * it asks the native AppWidget to reload that PNG.
///
/// Performance & stability contract (matches the spec's "Forbidden"
/// list):
///   * Renders are DEBOUNCED — the provider notifies on nearly every
///     interaction (month swipes, day taps, ...); a 700 ms coalescing
///     window collapses bursts into a single render.
///   * A [signature] check skips the render entirely when nothing the
///     widget shows actually changed (no duplicate work).
///   * A `_rendering` guard plus re-arm prevents overlapping renders
///     and guarantees the latest state still lands (no lost update,
///     no infinite loop).
///   * Every path is wrapped in try/catch and logged through
///     [AppLogger]: if `home_widget` or the platform misbehaves, the
///     host app keeps running exactly as before. Widget sync is never
///     on a critical path.
class WidgetSyncService {
  WidgetSyncService._();

  /// Process-wide singleton — bound once from `main.dart`.
  static final WidgetSyncService instance = WidgetSyncService._();

  /// Fully-qualified native provider class. MUST match the
  /// `<receiver android:name=".HijriDateWidgetProvider">` entry in
  /// android_patches/AndroidManifest.xml.
  static const String _androidProvider =
      'com.hijricalendar.hijri_calendar.HijriDateWidgetProvider';

  /// Shared-prefs key the native provider reads to locate the
  /// rendered PNG. MUST match the key used in HijriDateWidgetProvider.kt.
  static const String _imageKey = 'hijri_date_widget_image';

  /// Coalescing window for rapid-fire provider notifications.
  static const Duration _debounceWindow = Duration(milliseconds: 700);

  AppProvider? _provider;
  Timer? _debounce;
  bool _rendering = false;
  String? _lastSignature;

  /// Wires the service to the live provider. Safe to call once, from
  /// `main.dart`'s `initState` (post-frame). Adds a listener and
  /// triggers an initial sync.
  void bind(AppProvider provider) {
    if (_provider != null) return;
    _provider = provider;
    provider.addListener(_onProviderChanged);
    requestSync();
  }

  /// Detaches the service — called from `main.dart`'s `dispose`.
  void unbind() {
    _provider?.removeListener(_onProviderChanged);
    _provider = null;
    _debounce?.cancel();
    _debounce = null;
  }

  void _onProviderChanged() => requestSync();

  /// Requests a (debounced) widget refresh. Also called directly from
  /// `main.dart` on `AppLifecycleState.resumed` so a date rollover or
  /// a settings change made while backgrounded is picked up.
  void requestSync() {
    _debounce?.cancel();
    _debounce = Timer(_debounceWindow, _render);
  }

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

      await HomeWidget.renderFlutterWidget(
        HijriDateWidgetView(snapshot: snap),
        key: _imageKey,
        logicalSize: HijriDateWidgetView.canvasSize,
        pixelRatio: 3.0,
      );
      await HomeWidget.updateWidget(qualifiedAndroidName: _androidProvider);
      _lastSignature = snap.signature;
    } catch (e, s) {
      AppLogger.error('WidgetSyncService: render/update failed',
          error: e, stack: s);
    } finally {
      _rendering = false;
    }
  }
}
