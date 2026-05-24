import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../data/hijri_countries.dart';

/// Best-effort country detector for the Hybrid Hijri Calendar.
///
/// Returns an ISO 3166-1 alpha-2 code (`MA`, `SA`, `EG`, ...) that
/// downstream code passes to `HijriApiService` to fetch the
/// country's OFFICIAL Hijri calendar. The detector NEVER throws
/// and NEVER blocks the UI: every code path either returns a
/// concrete ISO code or a documented fallback ('XX' = Umm
/// al-Qura). The whole pipeline times out after 4 seconds.
///
/// Detection ladder (tried in order, first hit wins):
///
///   1. GPS reverse geocoding via the platform geocoder.
///      Reuses the same `geolocator` + `geocoding` packages the
///      Qibla screen already pulls in — zero additional native
///      deps. Skipped silently if location permission is denied
///      or services are off (the Qibla screen will surface that
///      to the user separately).
///
///   2. Device locale country tag (e.g. `fr_MA` → `MA`,
///      `ar_SA` → `SA`). Works fully offline and never requires
///      a permission prompt; ~90% accurate for users whose
///      device is configured in their home country.
///
///   3. Fallback to the universal `XX` code (Umm al-Qura). This
///      is intentionally not "guess from IP" — IP geolocation
///      adds a third-party dependency and surfaces tricky
///      privacy questions for not much gain over the locale
///      heuristic.
///
/// Caller responsibility
///   The caller decides what to DO with the returned code (cache
///   it, surface a "we detected your country is X" banner, etc.).
///   This service has no notion of state — call it whenever you
///   want a fresh read.
class CountryDetector {
  CountryDetector._();

  /// Overall ceiling for the whole detection pipeline. Past this
  /// we hand back the fallback so we don't strand a slow caller
  /// (typically the first-launch `AppProvider.init`) on a stuck
  /// geocoder.
  static const Duration _totalTimeout = Duration(seconds: 4);

  /// Detects the user's country. Returns a code from
  /// [kHijriCountries] — never null, never throws.
  ///
  /// `requestPermission` — when true, the GPS step asks for the
  /// location permission if not granted. Pass `false` on quiet
  /// background paths (e.g. cache refresh) so the user only sees
  /// the permission sheet from the Qibla screen, never as a
  /// surprise during app startup.
  static Future<String> detect({bool requestPermission = false}) async {
    try {
      final code = await _detectInternal(requestPermission: requestPermission)
          .timeout(_totalTimeout, onTimeout: () => null);
      if (code != null && isHijriCountrySupported(code)) return code;
    } catch (_) {
      // Swallow — fall through to the locale heuristic.
    }
    return _fromDeviceLocale() ?? 'XX';
  }

  // ── GPS reverse geocoding ─────────────────────────────────

  static Future<String?> _detectInternal({
    required bool requestPermission,
  }) async {
    // Step 1: ensure we *can* read GPS without blowing up.
    final servicesOn = await Geolocator.isLocationServiceEnabled();
    if (!servicesOn) return null;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      if (!requestPermission) return null;
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return null;
    }

    // Step 2: read a quick position. `LocationAccuracy.low` is
    // intentional — we want a country, not a building. Low
    // accuracy uses cell-tower / Wi-Fi triangulation, which
    // returns much faster than GPS-fix.
    //
    // API note: geolocator 11.0.0 uses the `desiredAccuracy` +
    // `timeLimit` named parameters on `getCurrentPosition`. The
    // `LocationSettings` wrapper landed in geolocator 13+ and is
    // intentionally avoided here so the package pin in
    // pubspec.yaml stays at ^11.
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.low,
      timeLimit: const Duration(seconds: 3),
    );

    // Step 3: reverse geocode to a Placemark. The platform
    // geocoder is the same one the Qibla screen uses for the
    // "City, Country" line, so the OS already has the data
    // cached if the user passed through the Qibla tab.
    final marks = await placemarkFromCoordinates(
      pos.latitude,
      pos.longitude,
    );
    if (marks.isEmpty) return null;

    final iso = marks.first.isoCountryCode;
    if (iso == null || iso.isEmpty) return null;
    return iso.toUpperCase();
  }

  // ── Device-locale fallback ────────────────────────────────

  /// Mines an ISO country code out of the OS-reported locale.
  /// Reads `Platform.localeName` on mobile (e.g. `fr_MA`,
  /// `ar_SA.UTF-8`) and `PlatformDispatcher.instance.locale` as
  /// a secondary source. Returns `null` if neither yields a
  /// recognised code.
  static String? _fromDeviceLocale() {
    // ─ Platform.localeName (most accurate on mobile) ──────
    try {
      final raw = Platform.localeName; // e.g. "fr_MA.UTF-8"
      final code = _isoFromLocaleTag(raw);
      if (code != null && isHijriCountrySupported(code)) return code;
    } catch (_) {
      // dart:io Platform may throw on the web target. Ignore.
    }

    // ─ Flutter's PlatformDispatcher (works everywhere) ────
    try {
      final l = PlatformDispatcher.instance.locale;
      final region = l.countryCode;
      if (region != null && region.isNotEmpty) {
        final upper = region.toUpperCase();
        if (isHijriCountrySupported(upper)) return upper;
      }
    } catch (_) {
      // Headless tests / very early init — ignore.
    }
    return null;
  }

  /// Extracts the country sub-tag from a POSIX or BCP-47 locale
  /// string. Handles all of:
  ///   `fr_MA`, `fr-MA`, `fr_MA.UTF-8`, `ar`, `ar_SA@calendar=hijri`
  ///
  /// Returns the uppercase 2-letter code, or `null` if no
  /// region sub-tag is present.
  static String? _isoFromLocaleTag(String tag) {
    if (tag.isEmpty) return null;
    // Normalise separators and strip charset / variant suffixes.
    final cleaned = tag
        .replaceAll('-', '_')
        .split('.')
        .first
        .split('@')
        .first;
    final parts = cleaned.split('_');
    if (parts.length < 2) return null;
    final region = parts[1];
    if (region.length != 2) return null;
    return region.toUpperCase();
  }
}
