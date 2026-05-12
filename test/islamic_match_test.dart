import 'package:flutter_test/flutter_test.dart';

import 'package:hijri_calendar/data/islamic_events.dart';

/// Phase 3 — Islamic-event matching unit tests.
///
/// Locks in the contract between the two matchers exposed by
/// `IslamicEventConfig`:
///
///   * `matchesDay`        — used by the NOTIFICATION scheduler;
///                            fires on the REMINDER day(s).
///   * `matchesDisplayDay` — used by the calendar / agenda VIEW;
///                            fires on the ACTUAL observance day(s).
///
/// The product spec deliberately decouples the two: Jumu'ah is
/// reminded Thursday but observed Friday, Mon/Thu fasting is
/// reminded Sun/Wed but observed Mon/Thu, Ayyam al-Bid is reminded
/// on day 12 but observed on 13/14/15. Any code change that
/// re-couples them will break the user's intentional reminder
/// flow — these tests catch it.
void main() {
  IslamicEventConfig configFor(String id) =>
      IslamicEventsData.events.firstWhere((e) => e.id == id);

  // ── Helpers — anchor weekday-bearing Gregorian dates ────────
  //
  // Dart's `DateTime.weekday`: 1=Mon ... 7=Sun. Pick a known week
  // (2026-01-05 = Monday) and let the test verify the weekday at
  // runtime, so a wrong assumption fails loudly instead of silently
  // testing the wrong day.
  final monday    = DateTime(2026, 1, 5);
  final tuesday   = DateTime(2026, 1, 6);
  final wednesday = DateTime(2026, 1, 7);
  final thursday  = DateTime(2026, 1, 8);
  final friday    = DateTime(2026, 1, 9);
  final saturday  = DateTime(2026, 1, 10);
  final sunday    = DateTime(2026, 1, 11);

  setUpAll(() {
    expect(monday.weekday,    1, reason: 'weekday-anchor for Monday is wrong');
    expect(tuesday.weekday,   2);
    expect(wednesday.weekday, 3);
    expect(thursday.weekday,  4);
    expect(friday.weekday,    5);
    expect(saturday.weekday,  6);
    expect(sunday.weekday,    7);
  });

  // ── Jumu'ah ─────────────────────────────────────────────────
  group('Jumu\'ah — reminder Thursday, display Friday', () {
    final cfg = configFor('jumuah');

    test('matchesDay fires on Thursday, not Friday', () {
      expect(
        cfg.matchesDay(hijriDay: 1, hijriMonth: 1, greg: thursday),
        isTrue,
        reason: 'Jumu\'ah reminder must fire Thursday',
      );
      expect(
        cfg.matchesDay(hijriDay: 1, hijriMonth: 1, greg: friday),
        isFalse,
        reason: 'Jumu\'ah reminder must NOT fire Friday',
      );
      // Quick scan: only weekday 4 fires.
      for (final d in [monday, tuesday, wednesday, friday, saturday, sunday]) {
        expect(
          cfg.matchesDay(hijriDay: 1, hijriMonth: 1, greg: d),
          isFalse,
          reason: 'Jumu\'ah reminder must NOT fire on weekday ${d.weekday}',
        );
      }
    });

    test('matchesDisplayDay fires on Friday, not Thursday', () {
      expect(
        cfg.matchesDisplayDay(hijriDay: 1, hijriMonth: 1, greg: friday),
        isTrue,
        reason: 'Jumu\'ah card must show on Friday',
      );
      expect(
        cfg.matchesDisplayDay(hijriDay: 1, hijriMonth: 1, greg: thursday),
        isFalse,
        reason: 'Jumu\'ah card must NOT show on Thursday',
      );
      // Quick scan: only weekday 5 fires.
      for (final d in [monday, tuesday, wednesday, thursday, saturday, sunday]) {
        expect(
          cfg.matchesDisplayDay(hijriDay: 1, hijriMonth: 1, greg: d),
          isFalse,
        );
      }
    });
  });

  // ── Monday & Thursday fasting ──────────────────────────────
  group('Mon/Thu fasting — reminder Sun + Wed, display Mon + Thu', () {
    final cfg = configFor('sawm_ithnayn_khamis');

    test('matchesDay fires on Sunday and Wednesday only', () {
      expect(cfg.matchesDay(hijriDay: 1, hijriMonth: 1, greg: sunday),    isTrue);
      expect(cfg.matchesDay(hijriDay: 1, hijriMonth: 1, greg: wednesday), isTrue);
      // None of the others fire.
      for (final d in [monday, tuesday, thursday, friday, saturday]) {
        expect(
          cfg.matchesDay(hijriDay: 1, hijriMonth: 1, greg: d),
          isFalse,
          reason: 'reminder must NOT fire on weekday ${d.weekday}',
        );
      }
    });

    test('matchesDisplayDay fires on Monday and Thursday only', () {
      expect(cfg.matchesDisplayDay(hijriDay: 1, hijriMonth: 1, greg: monday),
          isTrue);
      expect(cfg.matchesDisplayDay(hijriDay: 1, hijriMonth: 1, greg: thursday),
          isTrue);
      for (final d in [tuesday, wednesday, friday, saturday, sunday]) {
        expect(
          cfg.matchesDisplayDay(hijriDay: 1, hijriMonth: 1, greg: d),
          isFalse,
          reason: 'fasting card must NOT show on weekday ${d.weekday}',
        );
      }
    });
  });

  // ── Ayyam al-Bid ────────────────────────────────────────────
  group('Ayyam al-Bid — reminder day 12, display days 13/14/15', () {
    final cfg = configFor('ayyam_albid');

    // Monthly matchers ignore `greg` — they key off `hijriDay` —
    // so any plausible Gregorian moment works as a placeholder.
    final any = DateTime(2026, 5, 1);

    test('matchesDay fires on Hijri day 12 only', () {
      expect(cfg.matchesDay(hijriDay: 12, hijriMonth: 11, greg: any), isTrue);
      for (final d in [10, 11, 13, 14, 15, 16, 20, 30]) {
        expect(
          cfg.matchesDay(hijriDay: d, hijriMonth: 11, greg: any),
          isFalse,
          reason: 'Ayyam reminder must NOT fire on Hijri day $d',
        );
      }
    });

    test('matchesDisplayDay fires on Hijri days 13, 14, 15', () {
      for (final d in [13, 14, 15]) {
        expect(
          cfg.matchesDisplayDay(hijriDay: d, hijriMonth: 11, greg: any),
          isTrue,
          reason: 'Ayyam card must show on Hijri day $d',
        );
      }
      for (final d in [11, 12, 16, 17, 30]) {
        expect(
          cfg.matchesDisplayDay(hijriDay: d, hijriMonth: 11, greg: any),
          isFalse,
          reason: 'Ayyam card must NOT show on Hijri day $d',
        );
      }
    });
  });

  // ── Daily adhkar — sanity-check the daily branch ────────────
  group('Daily adhkar — always match', () {
    test('matchesDay and matchesDisplayDay always return true', () {
      for (final id in ['adhkar_sabah', 'adhkar_masaa', 'adhkar_nawm']) {
        final cfg = configFor(id);
        for (final d in [monday, tuesday, wednesday, thursday,
                         friday, saturday, sunday]) {
          expect(
            cfg.matchesDay(hijriDay: 1, hijriMonth: 1, greg: d),
            isTrue,
            reason: 'daily $id should fire every day (failed on ${d.weekday})',
          );
          expect(
            cfg.matchesDisplayDay(hijriDay: 1, hijriMonth: 1, greg: d),
            isTrue,
            reason: 'daily $id should display every day (failed on ${d.weekday})',
          );
        }
      }
    });
  });
}
