import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thin, opinionated client for the AlAdhan v1 calendar API
/// (https://aladhan.com/calendar-api). Does ONE thing well:
/// take a `(year, month)` Gregorian pair + country code and
/// hand back a list of `(Gregorian → Hijri)` mappings for the
/// month, AS PUBLISHED BY THAT COUNTRY'S OFFICIAL AUTHORITY.
///
/// What it is NOT
///   * Not a cache — the caller (HijriCache) owns persistence.
///   * Not a scheduler — refresh policy lives in the kernel
///     bootstrap, not here.
///   * Not a fallback chain — if the network call fails for any
///     reason (offline, DNS, 5xx, rate limit, malformed JSON),
///     the service returns `null` and the kernel slides over to
///     the local arithmetic engine. Network failures are a
///     normal, expected state, not an error.
///
/// Why AlAdhan
///   * 11-year-old Islamic Network project, used by dozens of
///     prayer-time / Hijri apps.
///   * No API key, no rate-limit headers to manage, no auth.
///   * Returns dates per-country with the country's OFFICIAL
///     religious authority baked in — the country code is the
///     only signal we need to express "I want the Moroccan
///     calendar, not the Saudi one."
///   * Provides BOTH the AlAdhan-default Hijri (`hijri.date`)
///     AND the Hijri AS THE COUNTRY'S MINISTRY PUBLISHED IT
///     (`hijriAdjusted.date` when an adjustment applies), which
///     gives us a clean, exact match to the printed calendar
///     that ministries hand out.
///
/// Endpoint used
///   GET https://api.aladhan.com/v1/gToHCalendar/{month}/{year}
///       ?adjustment={n}
///
///   Returns a JSON envelope:
///     { "code": 200, "status": "OK", "data": [ MonthDay, ... ] }
///   where each `MonthDay` is:
///     { "gregorian": { "date": "DD-MM-YYYY", ... },
///       "hijri":     { "date": "DD-MM-YYYY", ... } }
///
///   We extract just the (Greg → Hijri) pairing for each day in
///   the month.
class HijriApiService {
  HijriApiService._();

  /// AlAdhan production endpoint. Kept inside the class so a
  /// future migration to a self-hosted mirror or an alternative
  /// API requires touching one constant only.
  static const String _baseUrl = 'https://api.aladhan.com/v1';

  /// Per-call timeout. AlAdhan's median response is ~250ms;
  /// 8 seconds buys us a generous margin for slow cellular
  /// without making the caller wait forever. The kernel's
  /// fallback to local arithmetic still works the moment this
  /// times out.
  static const Duration _timeout = Duration(seconds: 8);

  /// Identifies our requests in AlAdhan's access logs. Useful
  /// for them, harmless for us.
  static const String _userAgent =
      'badr-hijri-calendar/1.0 (+https://github.com/ennifimohammed-dotcom)';

  /// Fetches one Gregorian month's worth of Greg→Hijri mappings,
  /// already adjusted for the supplied country.
  ///
  /// `adjustment` — usually pulled from `HijriCountry.adjustment`
  ///                (0 for most, +1 for Maghreb). The AlAdhan API
  ///                applies it server-side to the Hijri output so
  ///                the response already matches what the
  ///                country's ministry prints. Clamped to ±3
  ///                because that's what AlAdhan accepts.
  ///
  /// Returns
  ///   * A `HijriMonthData` on success.
  ///   * `null` on ANY failure (network, status code, bad JSON,
  ///     missing field). Failure is silent by design — the
  ///     kernel's arithmetic fallback handles the user-visible
  ///     experience.
  ///
  /// Never throws.
  static Future<HijriMonthData?> fetchGregorianMonth({
    required int gregorianYear,
    required int gregorianMonth,
    required String countryCode,
    int adjustment = 0,
  }) async {
    if (gregorianMonth < 1 || gregorianMonth > 12) return null;
    if (gregorianYear < 1900 || gregorianYear > 2200) return null;

    final clampedAdj = adjustment.clamp(-3, 3);
    final uri = Uri.parse(
      '$_baseUrl/gToHCalendar/$gregorianMonth/$gregorianYear'
      '?adjustment=$clampedAdj',
    );

    try {
      final resp = await http
          .get(uri, headers: const {'User-Agent': _userAgent})
          .timeout(_timeout);
      if (resp.statusCode != 200) return null;
      final body = json.decode(resp.body);
      if (body is! Map) return null;
      final code = body['code'];
      final data = body['data'];
      if (code != 200 || data is! List) return null;

      final entries = <HijriDayEntry>[];
      for (final item in data) {
        if (item is! Map) continue;
        final entry = _parseEntry(item);
        if (entry != null) entries.add(entry);
      }
      if (entries.isEmpty) return null;

      return HijriMonthData(
        countryCode: countryCode.toUpperCase(),
        adjustment: clampedAdj,
        gregorianYear: gregorianYear,
        gregorianMonth: gregorianMonth,
        entries: List.unmodifiable(entries),
        fetchedAt: DateTime.now(),
      );
    } on TimeoutException {
      return null;
    } catch (_) {
      // Any I/O, parse, or unexpected error → silent fallback.
      return null;
    }
  }

  // ── Internal parsers ──────────────────────────────────────

  /// Parses one item out of the `data[]` array. Defensive: every
  /// nested field is optional from the JSON's perspective, so we
  /// validate each one before constructing the entry.
  static HijriDayEntry? _parseEntry(Map item) {
    final g = item['gregorian'];
    final h = item['hijri'];
    if (g is! Map || h is! Map) return null;

    final gDate = _parseDmy(g['date']);
    final hDate = _parseDmy(h['date']);
    if (gDate == null || hDate == null) return null;

    return HijriDayEntry(
      gregYear: gDate.$1,
      gregMonth: gDate.$2,
      gregDay: gDate.$3,
      hijriYear: hDate.$1,
      hijriMonth: hDate.$2,
      hijriDay: hDate.$3,
    );
  }

  /// AlAdhan's `date` fields use `DD-MM-YYYY`. Returns
  /// `(year, month, day)` or `null` if the string doesn't parse.
  static (int, int, int)? _parseDmy(Object? raw) {
    if (raw is! String) return null;
    final parts = raw.split('-');
    if (parts.length != 3) return null;
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final y = int.tryParse(parts[2]);
    if (d == null || m == null || y == null) return null;
    if (d < 1 || d > 31 || m < 1 || m > 12 || y < 1 || y > 9999) {
      return null;
    }
    return (y, m, d);
  }
}

// ──────────────────────────────────────────────────────────
// Data transfer objects
// ──────────────────────────────────────────────────────────

/// One Gregorian day paired with its Hijri equivalent, as
/// reported by AlAdhan for a specific country's calendar.
class HijriDayEntry {
  final int gregYear;
  final int gregMonth;
  final int gregDay;
  final int hijriYear;
  final int hijriMonth;
  final int hijriDay;

  const HijriDayEntry({
    required this.gregYear,
    required this.gregMonth,
    required this.gregDay,
    required this.hijriYear,
    required this.hijriMonth,
    required this.hijriDay,
  });

  /// JSON shape used by [HijriCache]. Compact ints so a typical
  /// month payload sits at ~1.5 KB instead of the ~12 KB the
  /// raw AlAdhan response would cost.
  Map<String, dynamic> toJson() => {
        'g': [gregYear, gregMonth, gregDay],
        'h': [hijriYear, hijriMonth, hijriDay],
      };

  /// Inverse of [toJson]. Returns `null` on a malformed entry —
  /// callers should drop that entry and keep the rest.
  static HijriDayEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final g = raw['g'];
    final h = raw['h'];
    if (g is! List || h is! List || g.length != 3 || h.length != 3) {
      return null;
    }
    try {
      return HijriDayEntry(
        gregYear: g[0] as int,
        gregMonth: g[1] as int,
        gregDay: g[2] as int,
        hijriYear: h[0] as int,
        hijriMonth: h[1] as int,
        hijriDay: h[2] as int,
      );
    } catch (_) {
      return null;
    }
  }
}

/// One month's worth of [HijriDayEntry] plus the metadata the
/// cache needs to expire / invalidate it.
class HijriMonthData {
  final String countryCode;
  final int adjustment;
  final int gregorianYear;
  final int gregorianMonth;
  final List<HijriDayEntry> entries;

  /// When this data was fetched from AlAdhan. Used by
  /// [HijriCache] to decide whether to refresh in the background
  /// (typically older than 7 days = refresh).
  final DateTime fetchedAt;

  const HijriMonthData({
    required this.countryCode,
    required this.adjustment,
    required this.gregorianYear,
    required this.gregorianMonth,
    required this.entries,
    required this.fetchedAt,
  });

  Map<String, dynamic> toJson() => {
        'country': countryCode,
        'adj': adjustment,
        'gy': gregorianYear,
        'gm': gregorianMonth,
        'fetched': fetchedAt.millisecondsSinceEpoch,
        'entries': entries.map((e) => e.toJson()).toList(),
      };

  /// Inverse of [toJson]. Returns `null` if any structural
  /// field is missing — caller treats this as a cache miss.
  static HijriMonthData? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final country = raw['country'];
    final adj = raw['adj'];
    final gy = raw['gy'];
    final gm = raw['gm'];
    final fetched = raw['fetched'];
    final entries = raw['entries'];
    if (country is! String ||
        adj is! int ||
        gy is! int ||
        gm is! int ||
        fetched is! int ||
        entries is! List) {
      return null;
    }
    final parsed = <HijriDayEntry>[];
    for (final e in entries) {
      final entry = HijriDayEntry.fromJson(e);
      if (entry != null) parsed.add(entry);
    }
    if (parsed.isEmpty) return null;
    return HijriMonthData(
      countryCode: country,
      adjustment: adj,
      gregorianYear: gy,
      gregorianMonth: gm,
      entries: List.unmodifiable(parsed),
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(fetched),
    );
  }

  /// Quick O(n) lookup — `n ≤ 31` so a linear scan is fine and
  /// keeps the class allocation-free. Returns `null` if the
  /// requested day isn't in this month's range (shouldn't happen
  /// with a well-formed cache, but defensive).
  HijriDayEntry? lookupGregDay(int gregDay) {
    for (final e in entries) {
      if (e.gregDay == gregDay) return e;
    }
    return null;
  }
}
