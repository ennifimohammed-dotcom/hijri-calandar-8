import 'package:flutter_test/flutter_test.dart';

import 'package:hijri_calendar/utils/hijri_kernel.dart' as kernel;
import 'package:hijri_calendar/utils/hijri_utils.dart';

/// Phase 3 — Hijri Kernel unit tests.
///
/// These tests lock in the two public functions of
/// `lib/utils/hijri_kernel.dart`:
///
///   * `hijriFromGreg(DateTime g, int offset) → HijriDate`
///   * `gregFromHijri(HijriDate h, int offset) → DateTime`
///
/// The bug family Phase 2 was meant to fix (the duplicate-today
/// agenda regression in Morocco, the silent off-by-one in the
/// converter, the events-missing-on-first-paint agenda case) all
/// share the same root cause — the offset being applied
/// inconsistently. Locking in these invariants means any future
/// refactor that breaks the kernel breaks the test, not the user.
void main() {
  // Stable reference points used across multiple groups. Mid-month
  // dates keep us away from accidental month-rollover noise.
  final referenceDates = <DateTime>[
    DateTime(2024, 1, 15),
    DateTime(2024, 6, 30),
    DateTime(2025, 3, 21),
    DateTime(2026, 5,  9), // the date from the original Morocco bug report
    DateTime(2026, 12, 31),
    DateTime(2030, 7,  4),
  ];

  group('Round-trip identity', () {
    test('UAQ (offset = 0) — gregFromHijri ∘ hijriFromGreg == identity', () {
      for (final g in referenceDates) {
        final h = kernel.hijriFromGreg(g, 0);
        final back = kernel.gregFromHijri(h, 0);
        expect(back, equals(g),
            reason: 'UAQ round-trip failed for $g (got $h → $back)');
      }
    });

    test('Morocco (offset = +1) — gregFromHijri ∘ hijriFromGreg == identity',
        () {
      for (final g in referenceDates) {
        final h = kernel.hijriFromGreg(g, 1);
        final back = kernel.gregFromHijri(h, 1);
        expect(back, equals(g),
            reason: 'Morocco round-trip failed for $g (got $h → $back)');
      }
    });

    test('Reverse offset (offset = −1) — round-trip is still identity', () {
      for (final g in referenceDates) {
        final h = kernel.hijriFromGreg(g, -1);
        final back = kernel.gregFromHijri(h, -1);
        expect(back, equals(g), reason: 'offset=-1 round-trip failed for $g');
      }
    });
  });

  group('Offset semantics — Morocco runs 1 day later than UAQ', () {
    test(
        'hijriFromGreg(g, +1) == hijriFromGreg(g − 1 day, 0) for every g',
        () {
      for (final g in referenceDates) {
        final morocco = kernel.hijriFromGreg(g, 1);
        final uaqYesterday =
            kernel.hijriFromGreg(g.subtract(const Duration(days: 1)), 0);
        expect(morocco.hYear,  uaqYesterday.hYear,  reason: 'year for $g');
        expect(morocco.hMonth, uaqYesterday.hMonth, reason: 'month for $g');
        expect(morocco.hDay,   uaqYesterday.hDay,   reason: 'day for $g');
      }
    });

    test('Morocco Hijri lags UAQ by exactly one calendar day at any moment',
        () {
      for (final g in referenceDates) {
        final morocco = kernel.gregFromHijri(kernel.hijriFromGreg(g, 1), 0);
        final uaq     = kernel.gregFromHijri(kernel.hijriFromGreg(g, 0), 0);
        expect(uaq.difference(morocco).inDays, 1,
            reason: 'UAQ should be 1 Greg day ahead of Morocco at $g');
      }
    });
  });

  group('Kernel agrees with raw HijriDate when offset = 0', () {
    test('hijriFromGreg(g, 0) equals HijriDate.fromGregorian(g)', () {
      for (final g in referenceDates) {
        final fromKernel = kernel.hijriFromGreg(g, 0);
        final fromRaw    = HijriDate.fromGregorian(g);
        expect(fromKernel.hYear,  fromRaw.hYear);
        expect(fromKernel.hMonth, fromRaw.hMonth);
        expect(fromKernel.hDay,   fromRaw.hDay);
      }
    });

    test('gregFromHijri(h, 0) equals HijriDate.hijriToGregorian(...)', () {
      // Use the same Hijri tuples produced by the round-trip above
      // so we cover real-world Hijri dates, not arbitrary integers.
      for (final g in referenceDates) {
        final h = HijriDate.fromGregorian(g);
        final fromKernel = kernel.gregFromHijri(h, 0);
        final fromRaw    = HijriDate.hijriToGregorian(h.hYear, h.hMonth, h.hDay);
        expect(fromKernel, equals(fromRaw));
      }
    });
  });

  group('Sequential days produce monotonic, unique Hijri tuples', () {
    String key(HijriDate h) => '${h.hYear}-${h.hMonth}-${h.hDay}';

    test('UAQ — walking 365 consecutive days produces 365 distinct tuples',
        () {
      final start = DateTime(2026, 1, 1);
      final seen  = <String>{};
      for (var i = 0; i < 365; i++) {
        final greg = start.add(Duration(days: i));
        final h = kernel.hijriFromGreg(greg, 0);
        expect(seen.add(key(h)), isTrue,
            reason: 'duplicate Hijri tuple at i=$i (greg=$greg, hijri=$h)');
      }
      expect(seen.length, 365);
    });

    test(
        'Morocco — walking a 90-day window centred on the Morocco bug date '
        'produces 90 distinct Hijri tuples', () {
      final centre = DateTime(2026, 5, 9);
      final start  = centre.subtract(const Duration(days: 30));
      final seen   = <String>{};
      for (var i = 0; i < 90; i++) {
        final greg = start.add(Duration(days: i));
        final h = kernel.hijriFromGreg(greg, 1);
        expect(seen.add(key(h)), isTrue,
            reason: 'Morocco duplicate at i=$i (greg=$greg, hijri=$h)');
      }
      expect(seen.length, 90);
    });
  });

  group('Edge — Hijri month boundary rolls over by exactly one day', () {
    test('day-of-month is monotonic within a Hijri month, then resets to 1',
        () {
      // Walk 60 consecutive Greg days; whenever the Hijri month
      // changes, the new month's first day must be 1, not 0 or 30.
      final start = DateTime(2026, 1, 1);
      HijriDate prev = kernel.hijriFromGreg(start, 0);
      for (var i = 1; i < 60; i++) {
        final greg = start.add(Duration(days: i));
        final cur = kernel.hijriFromGreg(greg, 0);
        if (cur.hMonth == prev.hMonth && cur.hYear == prev.hYear) {
          // Same month: day must increase by exactly 1.
          expect(cur.hDay, prev.hDay + 1,
              reason: 'non-monotonic day inside Hijri month at $greg');
        } else {
          // Month boundary: new month starts at day 1.
          expect(cur.hDay, 1,
              reason: 'Hijri month $cur should start at day 1 (was $prev)');
        }
        prev = cur;
      }
    });

    test('Hijri 30 → next month day 1 is exactly one Gregorian day later',
        () {
      // Find the first Hijri day-30 in 2026 and verify the day after
      // is day-1 of the next month, exactly one Greg day later.
      final start = DateTime(2026, 1, 1);
      for (var i = 0; i < 180; i++) {
        final greg = start.add(Duration(days: i));
        final h = kernel.hijriFromGreg(greg, 0);
        if (h.hDay != 30) continue;
        final next = kernel.hijriFromGreg(
            greg.add(const Duration(days: 1)), 0);
        expect(next.hDay, 1,
            reason: 'day after Hijri 30 should be day 1 (got $next)');
        expect(next.hMonth != h.hMonth || next.hYear != h.hYear, isTrue,
            reason: 'month/year did not advance after day 30');
        return; // first occurrence is enough
      }
      // It is fine if no Hijri-30 was hit in the window — the test
      // is a smoke check, not a hard requirement.
    });
  });
}
