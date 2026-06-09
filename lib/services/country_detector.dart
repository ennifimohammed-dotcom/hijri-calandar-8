import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

import '../data/hijri_countries.dart';

/// How the detection ended. Surfaced via [CountryDetectionResult]
/// so the UI can react beyond "we got a country / we didn't" —
/// distinguishing e.g. "GPS service is OFF on the device" from
/// "permission is permanently denied" lets the Auto-detect button
/// guide the user to the right corrective action.
enum CountryDetectionStatus {
  /// Country resolved from a fresh or cached GPS fix.
  gpsOk,

  /// GPS failed (off, denied, no signal, timeout) but the
  /// device's IANA timezone was a recognised
  /// [kHijriCountries] entry — quietly used as the result.
  timezoneOk,

  /// GPS + timezone both failed; the device locale's region
  /// sub-tag landed us a recognised country.
  localeOk,

  /// The device's master "Location" switch is OFF. Granting
  /// the app permission won't help — the user has to flip
  /// the toggle in system settings first. UI should route to
  /// [CountryDetector.openLocationSettings].
  serviceDisabled,

  /// The user denied the location permission for this app.
  /// A subsequent permission request CAN re-prompt the system
  /// dialog (Android resets the "don't ask" counter after a
  /// while).
  permissionDenied,

  /// The user picked "Don't ask again" on the system dialog,
  /// OR the OS enforces a permanent denial (e.g. work profile
  /// policy). `requestPermission()` is a no-op — only opening
  /// the per-app settings page can flip this back. UI should
  /// route to [CountryDetector.openAppSettings].
  permissionDeniedForever,

  /// We had permission and the service was on, but the GPS
  /// chip did not return a fix within the overall budget.
  /// Typically: indoors with no Wi-Fi, or first-launch
  /// cold-start on a phone that hasn't warmed up its GPS yet.
  timeout,

  /// We got a fix but the reverse geocode returned nothing,
  /// OR returned a country code we don't support in
  /// [kHijriCountries].
  noSignal,

  /// All ladder rungs failed. UI defaults to the global
  /// Umm al-Qura option and offers the manual picker.
  unsupported,
}

/// Bundle of [CountryDetectionStatus] + a usable country code.
/// The code is ALWAYS populated — `'XX'` (global Umm al-Qura)
/// is used when no rung produced a real country — so callers
/// can just `setCountry(result.code)` without a null check.
class CountryDetectionResult {
  final String code;
  final CountryDetectionStatus status;
  const CountryDetectionResult({
    required this.code,
    required this.status,
  });

  /// Convenience — true if [status] reflects an actual win
  /// (vs. a fallback or error). Drives the green-vs-red snackbar
  /// color in the Auto-detect UI.
  bool get isSuccess =>
      status == CountryDetectionStatus.gpsOk ||
      status == CountryDetectionStatus.timezoneOk ||
      status == CountryDetectionStatus.localeOk;
}

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
  ///
  /// Bumped from 4 s → 20 s after field testing — a cold-start
  /// GPS fix on a real phone routinely takes 10-15 s, especially
  /// indoors or in the user's first launch of the app when the
  /// GPS chip hasn't been warmed up yet. The previous 4-second
  /// budget made the "needs several attempts" experience the
  /// user reported: the first detect timed out, the second
  /// detect (after GPS had silently warmed up) succeeded.
  static const Duration _totalTimeout = Duration(seconds: 20);

  /// Detects the user's country. Returns a code from
  /// [kHijriCountries] — never null, never throws.
  ///
  /// For UI flows that need to distinguish WHY detection failed
  /// (so they can guide the user to enable GPS or pick manually),
  /// prefer [detectWithStatus] which returns a status enum.
  ///
  /// `requestPermission` — when true, the GPS step asks for the
  /// location permission if not granted. Pass `false` on quiet
  /// background paths (e.g. cache refresh) so the user only sees
  /// the permission sheet from the Qibla screen, never as a
  /// surprise during app startup.
  static Future<String> detect({bool requestPermission = false}) async {
    final result =
        await detectWithStatus(requestPermission: requestPermission);
    return result.code;
  }

  /// Detect-with-diagnosis variant. Returns BOTH the ISO code
  /// (always usable — never empty) AND a status enum the caller
  /// can react to: "GPS service is off", "permission denied
  /// forever", "no signal", "fell back to timezone", etc.
  ///
  /// The UI surfaces (Onboarding + Settings Auto-detect button)
  /// use the status to:
  ///   * Pop a "please enable GPS in Settings" sheet when
  ///     `serviceDisabled` is returned.
  ///   * Pop the platform's app-settings page when
  ///     `permissionDeniedForever` is returned (only the user
  ///     can flip that flag back).
  ///   * Show a green snackbar with the detected flag + name on
  ///     `gpsOk` / `timezoneOk`.
  ///   * Show a red snackbar with a "pick manually" hint on
  ///     `noSignal` / `unsupported`.
  static Future<CountryDetectionResult> detectWithStatus({
    bool requestPermission = false,
  }) async {
    // 1) GPS — gold standard when permission is already granted.
    CountryDetectionResult? gpsResult;
    try {
      gpsResult = await _detectInternal(requestPermission: requestPermission)
          .timeout(
        _totalTimeout,
        onTimeout: () => const CountryDetectionResult(
          code: '',
          status: CountryDetectionStatus.timeout,
        ),
      );
      if (gpsResult.code.isNotEmpty &&
          isHijriCountrySupported(gpsResult.code)) {
        return gpsResult;
      }
    } catch (_) {
      // Swallow — fall through to the next rung. Keep
      // `gpsResult` (if non-null) so we can surface a precise
      // status when both GPS and the secondary rungs fail.
    }

    // 2) Timezone — strongest signal that requires no permission.
    //    Asia/Riyadh → SA, Africa/Casablanca → MA, ...
    final tzCode = _fromTimezone();
    if (tzCode != null && isHijriCountrySupported(tzCode)) {
      return CountryDetectionResult(
        code: tzCode,
        status: CountryDetectionStatus.timezoneOk,
      );
    }

    // 3) Device locale region — backup for users who set their
    //    regional preference even when the timezone is generic
    //    (e.g. UTC).
    final localeCode = _fromDeviceLocale();
    if (localeCode != null && isHijriCountrySupported(localeCode)) {
      return CountryDetectionResult(
        code: localeCode,
        status: CountryDetectionStatus.localeOk,
      );
    }

    // 4) Universal fallback. Propagate the GPS-specific status
    //    if we have one so the caller can still surface
    //    "please enable GPS" instead of just "unsupported".
    return CountryDetectionResult(
      code: 'XX',
      status: gpsResult?.status != null &&
              gpsResult!.status != CountryDetectionStatus.gpsOk
          ? gpsResult.status
          : CountryDetectionStatus.unsupported,
    );
  }

  /// True iff the device's location services switch is ON.
  /// Exposed so the UI can pre-check and route the user to the
  /// Android location-settings page BEFORE the rationale dialog
  /// when the switch is off (otherwise even `Allow` would do
  /// nothing — the permission grant doesn't turn on a globally
  /// disabled radio).
  static Future<bool> isLocationServiceEnabled() async {
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (_) {
      return false;
    }
  }

  /// Opens the OS-level location settings page so the user can
  /// flip the master GPS switch on. Companion to
  /// [isLocationServiceEnabled]. Best-effort — returns silently
  /// if the platform doesn't support deep-linking to that
  /// screen.
  static Future<void> openLocationSettings() async {
    try {
      await Geolocator.openLocationSettings();
    } catch (_) {
      // ignore — the user will have to navigate manually
    }
  }

  /// Opens the per-app settings page so the user can flip the
  /// location permission back from `Don't allow` / `Denied`.
  /// Only meaningful after a `permissionDeniedForever` status,
  /// where re-requesting via `requestPermission()` is a no-op
  /// because Android remembers the "Don't ask again" flag.
  static Future<void> openAppSettings() async {
    try {
      await Geolocator.openAppSettings();
    } catch (_) {
      // ignore
    }
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

  static Future<CountryDetectionResult> _detectInternal({
    required bool requestPermission,
  }) async {
    // Step 1: GPS service master switch. If the OS-level
    // location toggle is off, no amount of permission grant
    // will produce a fix — surface that as a distinct status
    // so the UI can route the user to the system settings.
    final servicesOn = await Geolocator.isLocationServiceEnabled();
    if (!servicesOn) {
      return const CountryDetectionResult(
        code: '',
        status: CountryDetectionStatus.serviceDisabled,
      );
    }

    // Step 2: app-level permission. Three terminal states map to
    // three distinct statuses so the UI can react meaningfully.
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      if (!requestPermission) {
        return const CountryDetectionResult(
          code: '',
          status: CountryDetectionStatus.permissionDenied,
        );
      }
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      return const CountryDetectionResult(
        code: '',
        status: CountryDetectionStatus.permissionDenied,
      );
    }
    if (perm == LocationPermission.deniedForever) {
      return const CountryDetectionResult(
        code: '',
        status: CountryDetectionStatus.permissionDeniedForever,
      );
    }

    // Step 3: try `getLastKnownPosition` FIRST. This is the
    // critical fix for the "needs several attempts" bug: a
    // cold-start GPS fix routinely takes 10-15 s, but a phone
    // that has used location recently (Maps, Qibla, ...) has a
    // sub-millisecond last-known fix sitting in cache. Reading
    // it gives the user instant feedback in the common case;
    // we only fall through to `getCurrentPosition` when the
    // cache is empty.
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        final iso = await _geocodeIso(last);
        if (iso != null) {
          return CountryDetectionResult(
            code: iso,
            status: CountryDetectionStatus.gpsOk,
          );
        }
      }
    } catch (_) {
      // ignore — fall through to a fresh fix
    }

    // Step 4: fresh GPS fix. `LocationAccuracy.medium` is the
    // sweet spot: ~100 m accuracy, uses GPS chip + cellular +
    // Wi-Fi triangulation, returns within ~5-10 s on a normal
    // device. The old `LocationAccuracy.low` skipped the GPS
    // chip entirely on some Android variants, which made
    // detection fail on devices without an active SIM. The
    // 18-second `timeLimit` matches the `_totalTimeout` ceiling
    // minus a 2-second safety margin so the outer `Future.timeout`
    // doesn't kill the inner call before its own deadline.
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 18),
      );
      final iso = await _geocodeIso(pos);
      if (iso != null) {
        return CountryDetectionResult(
          code: iso,
          status: CountryDetectionStatus.gpsOk,
        );
      }
      return const CountryDetectionResult(
        code: '',
        status: CountryDetectionStatus.noSignal,
      );
    } on TimeoutException {
      return const CountryDetectionResult(
        code: '',
        status: CountryDetectionStatus.timeout,
      );
    } catch (_) {
      return const CountryDetectionResult(
        code: '',
        status: CountryDetectionStatus.noSignal,
      );
    }
  }

  /// Reverse-geocodes a position to its ISO country code.
  /// Returns `null` only if BOTH the online geocoder AND the
  /// offline bounding-box fallback fail.
  ///
  /// Two-tier strategy:
  ///   1. ONLINE — `placemarkFromCoordinates` (Android Geocoder
  ///      / iOS CLGeocoder). Most accurate, but requires network
  ///      on Android because the platform geocoder hits Google
  ///      servers. If the user has GPS on but no internet, this
  ///      step fails silently.
  ///   2. OFFLINE — bounding-box lookup against the 30 supported
  ///      Muslim-majority countries (see [_offlineCountryFromLatLng]).
  ///      Country-level accuracy only (no city, no postal code),
  ///      but that's all we need — we're picking a calendar
  ///      authority, not an address. Works fully offline.
  ///
  /// This two-tier path is what makes "Detect country" usable on
  /// a plane / train / countryside without coverage — GPS reads
  /// the position, our bounding-box table classifies it.
  static Future<String?> _geocodeIso(Position pos) async {
    // Tier 1 — online platform geocoder. Most accurate.
    try {
      final marks = await placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      );
      if (marks.isNotEmpty) {
        final iso = marks.first.isoCountryCode;
        if (iso != null && iso.isNotEmpty) {
          return iso.toUpperCase();
        }
      }
    } catch (_) {
      // ignore — fall through to offline
    }
    // Tier 2 — offline bounding-box lookup. Returns one of the
    // 30 supported ISO codes or `null` if the position is
    // outside every known Muslim-majority country.
    return _offlineCountryFromLatLng(pos.latitude, pos.longitude);
  }

  /// Offline GPS → ISO country code lookup using approximate
  /// bounding boxes for the 30 [kHijriCountries] supported by
  /// the hybrid Hijri calendar.
  ///
  /// Why bounding boxes and not polygons?
  ///   * One country = four floats. 30 countries = 120 floats =
  ///     ~480 bytes. Polygon data for the same set would be
  ///     ~200 KB.
  ///   * Country-level accuracy is enough for our use case (we
  ///     pick a calendar authority, not a city / district).
  ///   * Order matters: smaller countries are listed FIRST so
  ///     they match before being subsumed by a neighbour's
  ///     larger box. The Gulf is the densest cluster; Bahrain
  ///     (≈1 250 km²) sits inside Saudi Arabia's box if you go
  ///     by lat/lng alone, so BH must be checked before SA.
  ///
  /// Returns `null` for positions outside every box (e.g. the
  /// user is in Europe / Africa-south-of-Sahara / Americas /
  /// East Asia / Oceania) — the caller then falls through to
  /// the timezone / locale rungs.
  static String? _offlineCountryFromLatLng(double lat, double lng) {
    // Each tuple: (ISO code, minLat, maxLat, minLng, maxLng).
    // Sourced from public country-bbox tables; numbers are
    // slightly inflated outward so the bbox doesn't reject a
    // legitimate fix that's 5 km offshore.
    //
    // Order: smallest area first, largest last.
    const boxes = <(String, double, double, double, double)>[
      // ── Tiny city-states / islands ──
      ('SG', 1.1, 1.5, 103.6, 104.1),     // Singapore
      ('BH', 25.5, 26.4, 50.3, 50.9),     // Bahrain
      ('BN', 4.0, 5.1, 114.0, 115.4),     // Brunei
      // ── Small Gulf states ──
      ('QA', 24.4, 26.2, 50.7, 51.7),     // Qatar
      ('KW', 28.5, 30.1, 46.5, 48.5),     // Kuwait
      ('AE', 22.6, 26.1, 51.5, 56.4),     // UAE
      ('OM', 16.6, 26.4, 51.9, 59.9),     // Oman
      // ── Small Levant ──
      ('PS', 31.2, 32.6, 34.2, 35.6),     // Palestine
      ('LB', 33.0, 34.7, 35.1, 36.7),     // Lebanon
      ('JO', 29.1, 33.4, 34.9, 39.4),     // Jordan
      ('YE', 12.1, 19.0, 41.8, 54.5),     // Yemen
      ('TN', 30.2, 37.6, 7.5, 11.6),      // Tunisia
      ('SY', 32.3, 37.4, 35.7, 42.4),     // Syria
      ('IQ', 29.0, 37.4, 38.8, 48.6),     // Iraq
      ('AF', 29.4, 38.5, 60.5, 74.9),     // Afghanistan
      ('BD', 20.6, 26.7, 88.0, 92.7),     // Bangladesh
      ('MY', 0.8, 7.5, 99.6, 119.3),      // Malaysia
      ('SN', 12.3, 16.7, -17.6, -11.3),   // Senegal
      ('MR', 14.7, 27.3, -17.1, -4.8),    // Mauritania
      ('MA', 21.3, 36.0, -17.1, -1.0),    // Morocco (incl. Western Sahara)
      ('LY', 19.5, 33.2, 9.4, 25.2),      // Libya
      ('DZ', 18.9, 37.1, -8.7, 12.0),     // Algeria
      ('EG', 21.7, 31.7, 24.7, 36.9),     // Egypt
      ('SD', 8.6, 23.1, 21.8, 38.6),      // Sudan
      ('TR', 35.8, 42.1, 25.7, 44.8),     // Türkiye
      ('PK', 23.6, 37.1, 60.9, 77.0),     // Pakistan
      ('SA', 16.4, 32.2, 34.5, 55.7),     // Saudi Arabia
      ('IN', 6.7, 35.5, 68.1, 97.5),      // India
      ('ID', -11.1, 6.1, 95.0, 141.1),    // Indonesia
    ];
    for (final box in boxes) {
      final (code, minLat, maxLat, minLng, maxLng) = box;
      if (lat >= minLat && lat <= maxLat &&
          lng >= minLng && lng <= maxLng) {
        return code;
      }
    }
    return null;
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
      'Africa/Dakar' => 'SN',
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
      // ── Mesopotamia ──
      'Asia/Baghdad' => 'IQ',
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
