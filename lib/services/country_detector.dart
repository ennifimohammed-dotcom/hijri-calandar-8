import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

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
///   2. System timezone (NEW — strongest signal that requires
///      no permission). Maps IANA names like `Asia/Riyadh` to
///      `SA`, `Africa/Casablanca` to `MA`, etc. The OS-reported
///      timezone is the user's lived clock — practically nobody
///      runs `Asia/Riyadh` while physically in Canada, so this
///      is a far more reliable proxy than the device language
///      (which is just a UI preference). Covers every one of
///      the 30 supported `kHijriCountries` plus their
///      sub-timezones (e.g. `Asia/Pontianak` → `ID`,
///      `Africa/El_Aaiun` → `MA`).
///
///   3. Device locale REGION tag (e.g. `fr_MA` → `MA`,
///      `ar_SA` → `SA`). Note: only the REGION sub-tag is read;
///      the language part is ignored because it's a UI
///      preference and not a reliable location signal (a Saudi
///      using an English UI would be `en_SA`, not `en_GB`).
///      Falls through silently if the device locale lacks a
///      region tag.
///
///   4. Fallback to the universal `XX` code (Umm al-Qura). This
///      is intentionally not "guess from IP" — IP geolocation
///      adds a third-party dependency and surfaces tricky
///      privacy questions for not much gain over the layered
///      timezone + locale heuristic.
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
    // 1) GPS — gold standard when permission is already granted.
    try {
      final code = await _detectInternal(requestPermission: requestPermission)
          .timeout(_totalTimeout, onTimeout: () => null);
      if (code != null && isHijriCountrySupported(code)) return code;
    } catch (_) {
      // Swallow — fall through to the next rung.
    }
    // 2) Timezone — strongest signal that requires no permission.
    //    Asia/Riyadh → SA, Africa/Casablanca → MA, ...
    final tzCode = _fromTimezone();
    if (tzCode != null && isHijriCountrySupported(tzCode)) return tzCode;
    // 3) Device locale region — backup for users who set their
    //    regional preference even when the timezone is generic
    //    (e.g. UTC).
    final localeCode = _fromDeviceLocale();
    if (localeCode != null && isHijriCountrySupported(localeCode)) {
      return localeCode;
    }
    // 4) Universal fallback.
    return 'XX';
  }

  /// Returns the country code we'd guess WITHOUT touching GPS.
  /// Used by the Onboarding screen to pre-fill the suggested
  /// country in the "Auto-detect" button label before the user
  /// has granted any location permission — so the suggestion
  /// reads "Auto-detect (likely 🇸🇦 Saudi Arabia)" even on a
  /// pristine install. Never throws; returns `'XX'` if nothing
  /// matched.
  static String detectQuick() {
    final tzCode = _fromTimezone();
    if (tzCode != null && isHijriCountrySupported(tzCode)) return tzCode;
    final localeCode = _fromDeviceLocale();
    if (localeCode != null && isHijriCountrySupported(localeCode)) {
      return localeCode;
    }
    return 'XX';
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

  // ── Timezone-based detection ──────────────────────────────

  /// Whether `tz_data.initializeTimeZones()` has been called.
  /// Lazy-initialized so the detector works whether or not the
  /// caller (typically `AppProvider.init`) has already brought
  /// up the notification service's timezone database. The init
  /// itself is ~50 ms (one-shot load of the IANA tz tables) so
  /// running it from this code path is harmless if the
  /// notification service hasn't booted yet.
  static bool _tzInitialized = false;

  static void _ensureTzInit() {
    if (_tzInitialized) return;
    try {
      tz_data.initializeTimeZones();
      _tzInitialized = true;
    } catch (_) {
      // If the tz DB fails to load for any reason, the
      // [_fromTimezone] caller will simply return null and the
      // detection ladder will fall through to the next rung.
    }
  }

  /// Reads the OS-reported IANA timezone name (`Asia/Riyadh`,
  /// `Africa/Casablanca`, ...) and maps it to the user's
  /// country. Returns `null` if the timezone is generic (UTC,
  /// Etc/GMT+3) or not in the lookup table — falls through to
  /// the locale heuristic in that case.
  static String? _fromTimezone() {
    _ensureTzInit();
    try {
      final name = tz.local.name;
      return _timezoneToCountry(name);
    } catch (_) {
      return null;
    }
  }

  /// IANA timezone → ISO 3166-1 alpha-2 country code.
  ///
  /// Covers every entry in [kHijriCountries], plus the sub-timezones
  /// each country uses internally (Indonesia spans four zones,
  /// Malaysia two, the Levant several). Names follow the canonical
  /// IANA tz database as shipped by the `timezone` package — the
  /// same name format the `tz.local.name` getter returns.
  ///
  /// Returns `null` for timezones that don't belong to a
  /// `kHijriCountries` entry (e.g. `America/Toronto` —
  /// the caller falls through to the next detection rung in
  /// that case, eventually landing on the global `XX` fallback).
  static String? _timezoneToCountry(String tzName) {
    return switch (tzName) {
      // ── Maghreb ──
      'Africa/Casablanca' => 'MA',
      'Africa/El_Aaiun' => 'MA',
      'Africa/Algiers' => 'DZ',
      'Africa/Tunis' => 'TN',
      'Africa/Tripoli' => 'LY',
      'Africa/Nouakchott' => 'MR',
      // ── Gulf & Arabian peninsula ──
      'Asia/Riyadh' => 'SA',
      'Asia/Mecca' => 'SA',
      'Asia/Dubai' => 'AE',
      'Asia/Qatar' => 'QA',
      'Asia/Kuwait' => 'KW',
      'Asia/Bahrain' => 'BH',
      'Asia/Muscat' => 'OM',
      'Asia/Aden' => 'YE',
      // ── Nile & Sudan ──
      'Africa/Cairo' => 'EG',
      'Africa/Khartoum' => 'SD',
      // ── Levant ──
      'Asia/Amman' => 'JO',
      'Asia/Hebron' => 'PS',
      'Asia/Gaza' => 'PS',
      'Asia/Jerusalem' => 'PS', // best-effort for Palestinian users.
      'Asia/Beirut' => 'LB',
      'Asia/Damascus' => 'SY',
      // ── Mesopotamia & Iran ──
      'Asia/Baghdad' => 'IQ',
      'Asia/Tehran' => 'IR',
      // ── Turkey ──
      'Europe/Istanbul' => 'TR',
      // ── South Asia ──
      'Asia/Karachi' => 'PK',
      'Asia/Dhaka' => 'BD',
      'Asia/Kolkata' => 'IN',
      'Asia/Calcutta' => 'IN', // historic name still emitted on some devices.
      'Asia/Kabul' => 'AF',
      // ── South-East Asia ──
      'Asia/Jakarta' => 'ID',
      'Asia/Pontianak' => 'ID',
      'Asia/Makassar' => 'ID',
      'Asia/Jayapura' => 'ID',
      'Asia/Kuala_Lumpur' => 'MY',
      'Asia/Kuching' => 'MY',
      'Asia/Brunei' => 'BN',
      'Asia/Singapore' => 'SG',
      _ => null,
    };
  }
}
