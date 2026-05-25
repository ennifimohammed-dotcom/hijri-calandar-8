import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/hijri_api_service.dart';
import '../services/hijri_cache.dart';
import 'hijri_utils.dart';

/// Hybrid Hijri Kernel — the single, authoritative entry point
/// for every Gregorian ↔ Hijri conversion in the app.
///
/// Public API
///   * [hijriFromGreg] — Gregorian → regional Hijri.
///   * [gregFromHijri] — regional Hijri → Gregorian.
///   * [HijriHybrid] — small state holder for the active
///     country, used by the kernel internally and by the
///     provider when wiring up country selection.
///
/// Why "hybrid"?
///   Behind the same SYNCHRONOUS signature the kernel has always
///   exposed, lookups now follow a 2-tier fallback:
///
///   1. HijriCache (in-memory mirror of SharedPreferences) —
///      O(1) probe, no I/O. Holds month payloads fetched from
///      AlAdhan API, which publishes each country's OFFICIAL
///      Hijri calendar (Saudi Umm al-Qura, Morocco Ministry of
///      Awqaf, Egypt Dar al-Iftaa, Turkey Diyanet, Indonesia
///      Kemenag, ...). On a hit, we return the OFFICIAL value
///      for the user's country.
///
///   2. Arithmetic engine (`HijriDate.fromGregorian`) — the
///      legacy tabular algorithm. Used when:
///        a) The cache is cold (first launch, no internet ever).
///        b) The user has selected the "Global / Umm al-Qura"
///           pseudo-country.
///        c) The API call to refresh the cache failed and the
///           cached entry has aged out.
///      This path is byte-identical to the kernel's behaviour
///      before the hybrid layer landed, so the worst-case
///      experience is no worse than today.
///
/// `offset` semantics — unchanged
///   The `offset` parameter on both public functions still means
///   "total day offset relative to AlAdhan default": it bundles
///   the country's official adjustment (1 for Maghreb, 0 for
///   Saudi-aligned states) PLUS the user's manual ±3-day
///   override from Settings. The kernel internally splits it
///   back into the two halves so the cache (which already
///   bakes in the country adjustment server-side) is consulted
///   correctly.
///
/// Refresh policy
///   On every conversion the kernel asks [HijriHybrid] whether
///   the requested month is "stale" (cache miss OR cached
///   payload older than seven days). If yes, a fire-and-forget
///   API fetch is enqueued — at most ONE pending fetch per
///   (country, year, month) tuple at a time so we never DoS
///   AlAdhan. The fetch updates the cache when it completes;
///   the in-flight conversion still returns the arithmetic
///   fallback so the UI is never blocked.

// ──────────────────────────────────────────────────────────
// Public hybrid-state holder
// ──────────────────────────────────────────────────────────

/// Singleton-style state for the hybrid layer. Only the
/// AppProvider should call the setters; everything else
/// (kernel internals, Settings UI) is a read-only consumer.
class HijriHybrid {
  HijriHybrid._();

  /// ISO 3166-1 alpha-2 of the country whose OFFICIAL calendar
  /// is currently being followed. Set by the AppProvider during
  /// init and on every country / region change. Empty string =
  /// "no country selected yet" → cache lookups are skipped and
  /// the arithmetic fallback runs (legacy behaviour).
  static String _countryCode = '';

  /// The country's official adjustment (in days) versus
  /// AlAdhan's default Hijri output. 0 for most, +1 for
  /// Maghreb. Lives here so the kernel can subtract it from
  /// the caller-supplied `offset` to isolate the user's manual
  /// portion when applying it on top of a cache hit.
  static int _countryAdjustment = 0;

  /// Read-only accessors for UI surfaces (Settings screen,
  /// "source" labels, etc.).
  static String get countryCode => _countryCode;
  static int get countryAdjustment => _countryAdjustment;
  static bool get hasCountry => _countryCode.isNotEmpty;

  /// Updates the active country. Called by the provider when:
  ///   * The user picks a country in Settings.
  ///   * The auto-detector resolves a fresh ISO code on init.
  ///   * The user toggles between auto-detect and manual.
  ///
  /// Doesn't trigger a refresh on its own — the caller does
  /// that explicitly (so a Settings-screen change can show a
  /// loading spinner if it wants to).
  static void setCountry({
    required String code,
    required int adjustment,
  }) {
    _countryCode = code.toUpperCase().trim();
    _countryAdjustment = adjustment;
  }

  /// Clears the active country — used when the user explicitly
  /// chooses "Global (Umm al-Qura)" or when boot fails to
  /// resolve any country.
  static void clearCountry() {
    _countryCode = '';
    _countryAdjustment = 0;
  }

  /// One-time bootstrap — hydrates [HijriCache] from
  /// SharedPreferences. Safe to call multiple times; second
  /// and later calls are no-ops.
  static Future<void> boot() => HijriCache.boot();

  // ── Refresh plumbing ──────────────────────────────────────

  /// Pending refresh tasks, keyed by `country_year_month`.
  /// Lets us coalesce duplicate refresh requests so a calendar
  /// grid asking for 42 cells in the same month fires ONE
  /// network call, not 42.
  static final Set<String> _refreshInFlight = <String>{};

  /// Schedules a background refresh for `(countryCode, year,
  /// month)` if the cache is missing or stale. Fire-and-forget;
  /// callers never await it.
  ///
  /// No-ops when:
  ///   * The country is empty (legacy mode).
  ///   * The cached entry is already fresh
  ///     ([HijriCache.refreshThreshold]).
  ///   * A refresh for the same key is already pending.
  static void scheduleRefresh({
    required int gregorianYear,
    required int gregorianMonth,
  }) {
    final country = _countryCode;
    if (country.isEmpty) return;
    if (HijriCache.isFresh(
      countryCode: country,
      gregorianYear: gregorianYear,
      gregorianMonth: gregorianMonth,
    )) {
      return;
    }
    final key = '${country}_${gregorianYear}_$gregorianMonth';
    if (_refreshInFlight.contains(key)) return;
    _refreshInFlight.add(key);

    // Use a microtask so the calling frame doesn't block on
    // the await machinery — the network call itself is awaited
    // inside the closure.
    Future.microtask(() async {
      try {
        final data = await HijriApiService.fetchGregorianMonth(
          gregorianYear: gregorianYear,
          gregorianMonth: gregorianMonth,
          countryCode: country,
          adjustment: _countryAdjustment,
        );
        if (data != null) {
          await HijriCache.store(data);
        }
      } catch (_) {
        // Silent — kernel already has the arithmetic fallback.
      } finally {
        _refreshInFlight.remove(key);
      }
    });
  }

  /// Force-refresh hook — wired to the "Refresh now" button in
  /// Settings. Always hits the network; success updates the
  /// cache, failure is silent.
  ///
  /// Returns true if the fetch succeeded and the cache was
  /// updated, false otherwise. The UI uses the return value to
  /// pick the right toast message.
  static Future<bool> forceRefresh({
    required int gregorianYear,
    required int gregorianMonth,
  }) async {
    final country = _countryCode;
    if (country.isEmpty) return false;
    try {
      final data = await HijriApiService.fetchGregorianMonth(
        gregorianYear: gregorianYear,
        gregorianMonth: gregorianMonth,
        countryCode: country,
        adjustment: _countryAdjustment,
      );
      if (data == null) return false;
      await HijriCache.store(data);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── History pre-warm (Smart-UX improvement 3) ────────────

  /// Whether a bulk fill is currently in flight. Prevents two
  /// fills from racing if [ensureHistoryFill] is called twice
  /// in quick succession (e.g. once at app init, once at
  /// country change).
  static bool _bulkFillRunning = false;

  /// One-time, country-scoped bulk fill of the cache covering
  /// ~7 years (5 past + 2 future). Designed so the user can
  /// scroll the calendar to any year in living memory and to
  /// any upcoming planned year (Hajj prep, etc.) without ever
  /// hitting an empty cell.
  ///
  /// Properties
  ///   * Idempotent — gated by the `hijri_bulk_done_<country>`
  ///     key in SharedPreferences. Once set, subsequent calls
  ///     are no-ops for that country.
  ///   * Polite — fetches sequentially with a 350 ms gap so we
  ///     never trip AlAdhan's rate limit (90 req/min).
  ///   * Background — `unawaited` Future so the caller is never
  ///     blocked on the ~30-second total fill time.
  ///   * Self-healing — any month that fails (network blip,
  ///     500) is silently skipped; the next `ensureHistoryFill`
  ///     call after the user changes country will retry only
  ///     the missing months because the cache already has the
  ///     successful ones.
  ///   * Past-month aware — past months are permanent (no TTL),
  ///     so they're only fetched once per country, ever.
  ///
  /// `pastYears` / `futureYears` default to 5 and 2 — covers
  /// the practical span for retrospection (zakat anchors, past
  /// Eid dates) and planning (Hajj, Ramadan two years out).
  static Future<void> ensureHistoryFill({
    int pastYears = 5,
    int futureYears = 2,
  }) async {
    final country = _countryCode;
    if (country.isEmpty || country == 'XX') return;
    if (_bulkFillRunning) return;
    _bulkFillRunning = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final flagKey = 'hijri_bulk_done_$country';
      if (prefs.getBool(flagKey) == true) return;

      final now = DateTime.now();
      final months = <(int, int)>[];
      // Walk Gregorian years inside-out (current → outward) so
      // the months the user is most likely to look at land in
      // the cache first.
      for (int delta = 0;
          delta <= pastYears || delta <= futureYears;
          delta++) {
        if (delta <= futureYears) {
          final y = now.year + delta;
          for (int m = 1; m <= 12; m++) {
            months.add((y, m));
          }
        }
        if (delta > 0 && delta <= pastYears) {
          final y = now.year - delta;
          for (int m = 1; m <= 12; m++) {
            months.add((y, m));
          }
        }
      }

      // Sequential fetch with throttling. Note we DO NOT use
      // `scheduleRefresh` here — that would queue all 84 in
      // parallel microtasks and stampede AlAdhan. The explicit
      // await + delay loop keeps us under their 90 req/min
      // limit with comfortable margin.
      for (final (year, month) in months) {
        if (HijriCache.isFresh(
          countryCode: country,
          gregorianYear: year,
          gregorianMonth: month,
        )) {
          continue;
        }
        try {
          final data = await HijriApiService.fetchGregorianMonth(
            gregorianYear: year,
            gregorianMonth: month,
            countryCode: country,
            adjustment: _countryAdjustment,
          );
          if (data != null) {
            await HijriCache.store(data);
          }
        } catch (_) {
          // One bad month doesn't poison the whole fill.
        }
        await Future.delayed(const Duration(milliseconds: 350));
      }

      await prefs.setBool(flagKey, true);
    } catch (_) {
      // ignore — silent failure is fine, will retry next launch
    } finally {
      _bulkFillRunning = false;
    }
  }

  // ── Sighting-night listener (Smart-UX improvement 4) ─────

  /// Last time we kicked off a sighting-night refresh, keyed by
  /// `country-greg_year-greg_month`. Used to throttle the
  /// aggressive 29th-night refresh so a user who opens the app
  /// six times that evening triggers ~6 attempts spread out by
  /// at least 30 minutes, not 6 in the same second.
  static final Map<String, DateTime> _lastSightingPing = {};

  /// Minimum gap between two sighting-night refresh attempts
  /// for the same month. Long enough to space out AlAdhan
  /// requests, short enough that opening the app every hour
  /// between Maghrib and Fajr produces a fresh attempt each
  /// time.
  static const Duration _sightingPingCooldown = Duration(minutes: 30);

  /// Fires an aggressive refresh if today is the 29th of a
  /// Hijri month (or the 30th — committees sometimes announce
  /// late). Called opportunistically from `AppProvider.init`
  /// and from the app-resume hook, so every time the user
  /// touches the app during a sighting window we re-check
  /// AlAdhan for the official announcement.
  ///
  /// `gregNow` is passed in so the caller (always the
  /// AppProvider) can use a consistent "now" across its own
  /// state mutations.
  static void tipOffForSighting({
    required DateTime gregNow,
    required int hijriDay,
    required int hijriMonth,
    required int hijriYear,
  }) {
    final country = _countryCode;
    if (country.isEmpty || country == 'XX') return;
    // Only fire on the days that matter — 29 (sighting night)
    // and 30 (post-sighting confirmation). On the 1st of a new
    // month the cache should already have the data from the
    // previous evening's refresh; we leave that alone to keep
    // the early-morning cold-start fast.
    if (hijriDay != 29 && hijriDay != 30) return;

    // Throttle by (country, current Greg month). Spreading by
    // Greg month means each calendar month gets at most one
    // refresh attempt per `_sightingPingCooldown`, regardless
    // of how many times the user opens the app.
    final key = '${country}_${gregNow.year}_${gregNow.month}';
    final last = _lastSightingPing[key];
    if (last != null &&
        gregNow.difference(last) < _sightingPingCooldown) {
      return;
    }
    _lastSightingPing[key] = gregNow;

    // Force a refresh of the CURRENT Greg month (announcement
    // for "tomorrow is 1 X" lands inside it) AND the next Greg
    // month (the announcement might bridge a Greg month
    // boundary — e.g. Hijri 29 falls on the last Greg day of a
    // month, the new Hijri month starts in the next Greg
    // month). Fire-and-forget: the await happens inside
    // `forceRefresh`; we don't block the caller.
    unawaited(forceRefresh(
      gregorianYear: gregNow.year,
      gregorianMonth: gregNow.month,
    ));
    final next = DateTime(gregNow.year, gregNow.month + 1, 1);
    unawaited(forceRefresh(
      gregorianYear: next.year,
      gregorianMonth: next.month,
    ));
  }

  /// Clears the bulk-done flag for a country. Called when the
  /// user explicitly clears the cache so the next app-open
  /// triggers a fresh bulk fill instead of relying on the now-
  /// empty cache + lazy backfill alone.
  static Future<void> resetBulkFillFlag(String countryCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('hijri_bulk_done_$countryCode');
    } catch (_) {
      // ignore
    }
  }
}

// ──────────────────────────────────────────────────────────
// Public conversion functions — SYNCHRONOUS by contract.
// All 17 callers (provider, recurrence engine, calendar screen,
// widget snapshots, search, converter, ...) call into these
// without awaiting. Don't change the signature without
// auditing every caller.
// ──────────────────────────────────────────────────────────

/// Converts a Gregorian instant into the user's regional Hijri
/// date.
///
/// `offset` semantics
///   Total day offset. Bundles both the country's official
///   adjustment (the legacy `_regionOffset` value) AND the
///   user's manual ±3-day override from Settings. The kernel
///   splits this back into the two halves internally — see the
///   class-level comment on [HijriHybrid].
///
/// Flow
///   1. If a country is set, probe [HijriCache] for the OFFICIAL
///      Hijri date that this country's ministry published for
///      this Gregorian day.
///        - HIT  → return cache value (with manual offset
///                 layered on top if non-zero).
///        - MISS → schedule a background refresh, fall through
///                 to step 2.
///   2. Arithmetic fallback — `HijriDate.fromGregorian(g -
///      offset days)`, byte-identical to pre-hybrid behaviour.
HijriDate hijriFromGreg(DateTime g, int offset) {
  final country = HijriHybrid._countryCode;

  // ── Cache path ────────────────────────────────────────────
  if (country.isNotEmpty) {
    HijriHybrid.scheduleRefresh(
      gregorianYear: g.year,
      gregorianMonth: g.month,
    );
    final cached = HijriCache.lookupGregDay(
      countryCode: country,
      gregorianYear: g.year,
      gregorianMonth: g.month,
      gregorianDay: g.day,
    );
    if (cached != null) {
      final (hY, hM, hD) = cached;
      // The cache value already includes the country's official
      // adjustment. The remaining piece of `offset` is the
      // user's manual override, which we layer on top by
      // round-tripping through the arithmetic engine.
      final manualOnly = offset - HijriHybrid._countryAdjustment;
      if (manualOnly == 0) {
        return HijriDate(hY, hM, hD);
      }
      final anchor = HijriDate.hijriToGregorian(hY, hM, hD);
      final shifted = anchor.subtract(Duration(days: manualOnly));
      return HijriDate.fromGregorian(shifted);
    }
  }

  // ── Arithmetic fallback (legacy) ──────────────────────────
  final shifted = g.subtract(Duration(days: offset));
  return HijriDate.fromGregorian(shifted);
}

/// Converts a regional Hijri date back into its paired Gregorian
/// civil date. Inverse of [hijriFromGreg].
///
/// `offset` semantics — identical to [hijriFromGreg]: total
/// offset bundling country + manual.
///
/// Flow
///   1. If a country is set, scan a 3-month window of cached
///      data (the arithmetic anchor's month ± 1) for an entry
///      whose Hijri tuple matches `h`. HIT → return that
///      entry's Gregorian date with the manual offset added.
///   2. Arithmetic fallback — canonical Hijri→Gregorian + full
///      offset (`+offset` days), byte-identical to pre-hybrid.
DateTime gregFromHijri(HijriDate h, int offset) {
  final country = HijriHybrid._countryCode;

  // ── Cache path ────────────────────────────────────────────
  if (country.isNotEmpty) {
    final manualOnly = offset - HijriHybrid._countryAdjustment;

    // The cache is keyed by GREGORIAN (year, month). To find a
    // Hijri tuple inside it, anchor on the arithmetic Greg for
    // that Hijri (offset by the country's adjustment, so we
    // land in the same Greg month the cache would have indexed
    // it under), then sweep ±1 month to catch boundary days.
    final arithmetic = HijriDate.hijriToGregorian(h.hYear, h.hMonth, h.hDay);
    final probeBase = arithmetic.add(Duration(
      days: HijriHybrid._countryAdjustment,
    ));

    HijriHybrid.scheduleRefresh(
      gregorianYear: probeBase.year,
      gregorianMonth: probeBase.month,
    );

    for (int dm = -1; dm <= 1; dm++) {
      // `DateTime` normalises out-of-range months automatically,
      // so `DateTime(2026, 13, 15)` becomes 2027-01-15. Cheap
      // and avoids a manual modulo dance.
      final probe = DateTime(probeBase.year, probeBase.month + dm, 15);
      final month = HijriCache.lookup(
        countryCode: country,
        gregorianYear: probe.year,
        gregorianMonth: probe.month,
      );
      if (month == null) continue;
      for (final entry in month.entries) {
        if (entry.hijriYear == h.hYear &&
            entry.hijriMonth == h.hMonth &&
            entry.hijriDay == h.hDay) {
          final entryGreg = DateTime(
            entry.gregYear,
            entry.gregMonth,
            entry.gregDay,
          );
          return entryGreg.add(Duration(days: manualOnly));
        }
      }
    }
  }

  // ── Arithmetic fallback (legacy) ──────────────────────────
  final base = HijriDate.hijriToGregorian(h.hYear, h.hMonth, h.hDay);
  return base.add(Duration(days: offset));
}
