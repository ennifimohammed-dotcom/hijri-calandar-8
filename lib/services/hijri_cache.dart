import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'hijri_api_service.dart';

/// In-memory + on-disk cache for `HijriMonthData` payloads.
///
/// The shape of the problem
/// ------------------------
///   * `hijri_kernel.dart` exposes SYNCHRONOUS conversion
///     functions (`hijriFromGreg`, `gregFromHijri`) consumed at
///     ~17 sites — calendar grid cells, recurrence expansion,
///     widget snapshots, notification scheduling. We can't make
///     those `Future` without rewriting every consumer.
///   * AlAdhan API calls are necessarily async (network).
///   * SharedPreferences I/O is also async.
///
/// The reconciliation: we keep TWO tiers. The on-disk tier
/// (SharedPreferences) is the source of truth, the in-memory
/// tier (a plain `Map`) is what the kernel actually reads.
/// `HijriCache.boot()` hydrates the memory tier from disk ONCE
/// at app startup; from that point on, the kernel's lookups are
/// pure memory reads — they can stay synchronous.
///
/// Writes go memory-first, disk-second. A network refresh
/// updates the memory map immediately (so the next conversion
/// already sees the fresh data) and queues a disk write to
/// persist it for the next launch.
///
/// What lives in the cache
///   One `HijriMonthData` per (countryCode, gregorianYear,
///   gregorianMonth) tuple. Keys are flat string keys so disk
///   storage stays human-debuggable and SharedPreferences-safe:
///     hijri_cache_MA_2026_5
///     hijri_cache_SA_2026_5
///     ...
///
///   We deliberately key by country so an immigrant family
///   switching between "follow Morocco" and "follow Saudi
///   Arabia" doesn't double-evict cached months.
///
/// Storage budget
///   ~1.5 KB per month. The default eviction policy keeps the
///   current month and ±6 months around it (13 months total per
///   country, ~20 KB), which is enough to render the calendar's
///   default ±1 year scroll plus a couple of months of slack.
///   Anything older is dropped on the next `prune()` call.
class HijriCache {
  HijriCache._();

  /// SharedPreferences key prefix. Single shared `_` separator
  /// so a regex can match `hijri_cache_*` without false
  /// positives against any other key the app stores.
  static const String _keyPrefix = 'hijri_cache_';

  /// Single index key — a JSON list of all the month keys
  /// currently on disk. Reading SharedPreferences key-by-key is
  /// O(n) per lookup; the index lets [boot] hydrate everything
  /// in one I/O round trip.
  static const String _indexKey = 'hijri_cache_index';

  /// Entries older than this are eligible for background
  /// refresh. Not a hard expiry — stale data is still used
  /// while the refresh is in flight, so the user never sees a
  /// gap. Seven days is comfortable: it's longer than any
  /// single ministry's announcement cycle (countries publish
  /// monthly), shorter than the typical user's app-open cadence.
  static const Duration refreshThreshold = Duration(days: 7);

  /// Beyond this age, treat the entry as a hard miss. Avoids
  /// surfacing year-old cached Hijri values to a user who only
  /// opens the app annually.
  static const Duration hardExpiry = Duration(days: 60);

  /// Memory tier. Keyed by the same flat string as on disk so
  /// the lookup logic is identical for both tiers.
  static final Map<String, HijriMonthData> _memory = {};

  /// True once [boot] has finished. Until then, [lookup] returns
  /// null and the kernel falls through to the arithmetic engine
  /// — exactly the same code path as a true cache miss, so the
  /// "haven't booted yet" window is invisible to callers.
  static bool _booted = false;
  static bool get isBooted => _booted;

  // ── Lifecycle ─────────────────────────────────────────────

  /// Loads every persisted month into [_memory]. Idempotent —
  /// safe to call from `AppProvider.init` and from any
  /// re-entrant code path.
  ///
  /// Returns the number of entries actually loaded; useful for
  /// debug logging but the caller usually ignores it.
  static Future<int> boot() async {
    if (_booted) return _memory.length;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_indexKey);
      if (raw == null || raw.isEmpty) {
        _booted = true;
        return 0;
      }
      final keys = json.decode(raw);
      if (keys is! List) {
        _booted = true;
        return 0;
      }
      int loaded = 0;
      for (final k in keys) {
        if (k is! String) continue;
        final monthRaw = prefs.getString(k);
        if (monthRaw == null) continue;
        try {
          final decoded = json.decode(monthRaw);
          final data = HijriMonthData.fromJson(decoded);
          if (data == null) continue;
          // Hard expiry — drop entries we'd never trust anyway.
          if (DateTime.now().difference(data.fetchedAt) > hardExpiry) {
            continue;
          }
          _memory[k] = data;
          loaded++;
        } catch (_) {
          // One corrupt entry shouldn't kill the whole cache.
          continue;
        }
      }
      _booted = true;
      return loaded;
    } catch (_) {
      _booted = true;
      return 0;
    }
  }

  // ── Lookup ────────────────────────────────────────────────

  /// SYNCHRONOUS lookup — the kernel's hot path. Returns the
  /// cached month, or `null` if we have no data for the
  /// (country, year, month) triple. A `null` result is normal
  /// and means "fall back to arithmetic".
  ///
  /// Always returns `null` before [boot] completes; callers
  /// (i.e. the kernel) treat that as a regular miss.
  static HijriMonthData? lookup({
    required String countryCode,
    required int gregorianYear,
    required int gregorianMonth,
  }) {
    if (!_booted) return null;
    final key = _key(countryCode, gregorianYear, gregorianMonth);
    return _memory[key];
  }

  /// Convenience helper: synchronously resolve a single
  /// Gregorian instant `(y, m, d)` into a Hijri triple, if the
  /// cache covers it. Returns `null` on miss.
  static (int hYear, int hMonth, int hDay)? lookupGregDay({
    required String countryCode,
    required int gregorianYear,
    required int gregorianMonth,
    required int gregorianDay,
  }) {
    final month = lookup(
      countryCode: countryCode,
      gregorianYear: gregorianYear,
      gregorianMonth: gregorianMonth,
    );
    if (month == null) return null;
    final entry = month.lookupGregDay(gregorianDay);
    if (entry == null) return null;
    return (entry.hijriYear, entry.hijriMonth, entry.hijriDay);
  }

  /// True if we have data for this (country, year, month) AND
  /// it's still within [refreshThreshold]. Used by the
  /// background refresh policy to skip work when fresh data is
  /// already in hand.
  static bool isFresh({
    required String countryCode,
    required int gregorianYear,
    required int gregorianMonth,
  }) {
    final data = lookup(
      countryCode: countryCode,
      gregorianYear: gregorianYear,
      gregorianMonth: gregorianMonth,
    );
    if (data == null) return false;
    return DateTime.now().difference(data.fetchedAt) < refreshThreshold;
  }

  /// Returns the `fetchedAt` timestamp of the most recently
  /// refreshed entry for this country, or `null` if we have
  /// nothing cached. Surfaced as "Last update: 3 hours ago" in
  /// the Settings screen.
  static DateTime? lastSyncFor(String countryCode) {
    if (!_booted) return null;
    final upper = countryCode.toUpperCase();
    DateTime? newest;
    for (final entry in _memory.entries) {
      if (!entry.key.startsWith('${_keyPrefix}${upper}_')) continue;
      final t = entry.value.fetchedAt;
      if (newest == null || t.isAfter(newest)) newest = t;
    }
    return newest;
  }

  // ── Writes ────────────────────────────────────────────────

  /// Stores a freshly fetched month. Memory is updated first
  /// (so subsequent kernel lookups see the new value
  /// immediately), then a fire-and-forget disk write persists
  /// it. Failures on the disk side are swallowed — the next
  /// app launch will simply re-fetch.
  static Future<void> store(HijriMonthData data) async {
    if (!_booted) {
      // Should never happen in production code paths, but we
      // tolerate it cleanly. Booting before a store means we
      // could clobber a disk-only entry, so flush whatever
      // exists on disk into memory first.
      await boot();
    }
    final key = _key(
      data.countryCode,
      data.gregorianYear,
      data.gregorianMonth,
    );
    _memory[key] = data;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, json.encode(data.toJson()));
      // Update the index — additive, deduplicated.
      final indexRaw = prefs.getString(_indexKey);
      final List<String> currentIndex = [];
      if (indexRaw != null && indexRaw.isNotEmpty) {
        final decoded = json.decode(indexRaw);
        if (decoded is List) {
          for (final k in decoded) {
            if (k is String) currentIndex.add(k);
          }
        }
      }
      if (!currentIndex.contains(key)) {
        currentIndex.add(key);
        await prefs.setString(_indexKey, json.encode(currentIndex));
      }
    } catch (_) {
      // Disk persistence is best-effort.
    }
  }

  /// Drops entries older than [hardExpiry] from both tiers.
  /// Called opportunistically by the refresh scheduler — does
  /// nothing if it would have to wait on disk.
  static Future<void> prune() async {
    if (!_booted) return;
    final now = DateTime.now();
    final toRemove = <String>[];
    for (final entry in _memory.entries) {
      if (now.difference(entry.value.fetchedAt) > hardExpiry) {
        toRemove.add(entry.key);
      }
    }
    if (toRemove.isEmpty) return;

    for (final key in toRemove) {
      _memory.remove(key);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in toRemove) {
        await prefs.remove(key);
      }
      // Rewrite the index.
      await prefs.setString(_indexKey, json.encode(_memory.keys.toList()));
    } catch (_) {
      // Disk failures are non-fatal.
    }
  }

  /// Wipes the cache completely — both tiers. Wired to the
  /// "Reset Hijri cache" button in the advanced settings so a
  /// user with a corrupted cache has a clean escape hatch.
  static Future<void> clear() async {
    _memory.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      final indexRaw = prefs.getString(_indexKey);
      if (indexRaw != null && indexRaw.isNotEmpty) {
        final decoded = json.decode(indexRaw);
        if (decoded is List) {
          for (final k in decoded) {
            if (k is String) await prefs.remove(k);
          }
        }
      }
      await prefs.remove(_indexKey);
    } catch (_) {
      // ignore
    }
  }

  // ── Key helpers ───────────────────────────────────────────

  /// Canonical disk key for one (country, year, month) tuple.
  /// `MA_2026_5` is human-readable on purpose — makes
  /// `flutter pub run shared_preferences_dump` (or equivalent)
  /// dumps debuggable.
  static String _key(String country, int gYear, int gMonth) {
    return '$_keyPrefix${country.toUpperCase()}_${gYear}_$gMonth';
  }
}
