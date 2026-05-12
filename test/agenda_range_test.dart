import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hijri_calendar/providers/app_provider.dart';
import 'package:hijri_calendar/utils/hijri_kernel.dart' as kernel;

/// Phase 3 — Agenda range + per-day events unit tests.
///
/// This file protects the two AppProvider methods that drive the
/// agenda view:
///
///   * `getAgendaEventsRange({pastDays, futureDays})` — bidirectional
///     window walker; must NEVER produce the same Hijri (y, m, d)
///     twice, and today must always be reachable inside it.
///
///   * `getEventsForDay(day, month, year)` — must surface today's
///     events on first paint (no scroll required). With the default
///     enabled flags, today carries at least the 3 daily adhkar.
///
/// Two flavours of tests are bundled:
///   1. Pure kernel-level invariants — fast, deterministic, no
///      Flutter binding required.
///   2. Provider integration — initialises `AppProvider` with a
///      mocked SharedPreferences so the agenda walker runs against
///      real region offsets. Notification plugin calls fall back to
///      `MissingPluginException`, caught by each service's internal
///      try/catch.
void main() {
  // ──────────────────────────────────────────────────────────
  // (1) Pure kernel invariants — no Flutter binding needed.
  // ──────────────────────────────────────────────────────────
  group('Agenda window — kernel invariants', () {
    String key(int y, int m, int d) => '$y-$m-$d';

    test('UAQ — 90-day window has no duplicate Hijri tuples', () {
      final start = DateTime(2026, 4, 1).subtract(const Duration(days: 30));
      final seen  = <String>{};
      for (var i = 0; i < 90; i++) {
        final g = start.add(Duration(days: i));
        final h = kernel.hijriFromGreg(g, 0);
        expect(
          seen.add(key(h.hYear, h.hMonth, h.hDay)),
          isTrue,
          reason: 'UAQ duplicate at i=$i (greg=$g, hijri=$h)',
        );
      }
    });

    test('Morocco — 90-day window has no duplicate Hijri tuples', () {
      // Anchor around the original bug-report date so the test
      // covers the exact boundary that produced "21 ذو القعدة"
      // twice in the agenda.
      final centre = DateTime(2026, 5, 9);
      final start  = centre.subtract(const Duration(days: 30));
      final seen   = <String>{};
      for (var i = 0; i < 90; i++) {
        final g = start.add(Duration(days: i));
        final h = kernel.hijriFromGreg(g, 1);
        expect(
          seen.add(key(h.hYear, h.hMonth, h.hDay)),
          isTrue,
          reason: 'Morocco duplicate at i=$i (greg=$g, hijri=$h)',
        );
      }
    });

    test('Morocco — today is naturally reachable from the future-only walk',
        () {
      // This is the heart of the "today section was empty" bug:
      // historically the walker used raw `HijriDate.fromGregorian`
      // (no offset) and `p.today` used `hijriDayOffset = +1`, so the
      // walker's first Hijri tuple was (today + 1), and today was
      // missing entirely. The kernel fixes the misalignment.
      const offset = 1;
      final today  = DateTime(2026, 5, 9);
      final pToday = kernel.hijriFromGreg(today, offset);

      var hit = false;
      for (var i = 0; i < 60; i++) {
        final g = today.add(Duration(days: i));
        final h = kernel.hijriFromGreg(g, offset);
        if (h.hYear == pToday.hYear &&
            h.hMonth == pToday.hMonth &&
            h.hDay == pToday.hDay) {
          hit = true;
          break;
        }
      }
      expect(hit, isTrue,
          reason: 'today $pToday should be reachable in a 60-day '
                  'future-only walk with offset = +1');
    });
  });

  // ──────────────────────────────────────────────────────────
  // (2) Provider integration — boots a real AppProvider with a
  //     mocked SharedPreferences.
  //
  //     Notes:
  //       * The notification plugin is NOT mocked. Every notif call
  //         site is wrapped in a try/catch that logs and swallows
  //         MissingPluginException, so the provider still finishes
  //         init and the calendar state we care about (_today,
  //         _islamicEventsEnabled) is set correctly.
  //       * Each test calls `setMockInitialValues({...})` to
  //         pre-seed the user's region — that's the only knob that
  //         changes the kernel offset and thus the agenda output.
  // ──────────────────────────────────────────────────────────
  group('AppProvider integration', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    test('Morocco — today appears in the agenda window with events', () async {
      SharedPreferences.setMockInitialValues({'region': 'ma'});
      final p = AppProvider();
      await p.init();

      expect(p.isLoading, isFalse, reason: 'init did not complete');
      expect(p.hijriDayOffset, 1,
          reason: 'Morocco region must yield hijriDayOffset = +1');

      final today = p.today;
      final agenda = p.getAgendaEventsRange(pastDays: 0, futureDays: 60);
      expect(agenda, isNotEmpty);

      final todayKey = '${today.hYear}-${today.hMonth}-${today.hDay}';
      final todayEntry = agenda.where((e) =>
          '${e.key.hYear}-${e.key.hMonth}-${e.key.hDay}' == todayKey);
      expect(todayEntry, isNotEmpty,
          reason: 'today ($todayKey) is missing from the agenda window');
      expect(todayEntry.first.value, isNotEmpty,
          reason: 'today is in the agenda but has no events attached');
    });

    test('UAQ — today appears in the agenda window with events', () async {
      SharedPreferences.setMockInitialValues({'region': 'global'});
      final p = AppProvider();
      await p.init();

      expect(p.hijriDayOffset, 0,
          reason: 'UAQ region must yield hijriDayOffset = 0');

      final today = p.today;
      final agenda = p.getAgendaEventsRange(pastDays: 0, futureDays: 60);
      final todayKey = '${today.hYear}-${today.hMonth}-${today.hDay}';
      final hits = agenda.where((e) =>
          '${e.key.hYear}-${e.key.hMonth}-${e.key.hDay}' == todayKey);
      expect(hits, isNotEmpty);
      expect(hits.first.value, isNotEmpty);
    });

    test('Morocco — bidirectional window has no duplicate Hijri tuples',
        () async {
      SharedPreferences.setMockInitialValues({'region': 'ma'});
      final p = AppProvider();
      await p.init();

      final agenda =
          p.getAgendaEventsRange(pastDays: 30, futureDays: 60);
      final seen = <String>{};
      for (final entry in agenda) {
        final k =
            '${entry.key.hYear}-${entry.key.hMonth}-${entry.key.hDay}';
        expect(seen.add(k), isTrue,
            reason: 'duplicate Hijri key in agenda: $k');
      }
    });

    test('getEventsForDay(today) is non-empty in Morocco', () async {
      SharedPreferences.setMockInitialValues({'region': 'ma'});
      final p = AppProvider();
      await p.init();

      final today = p.today;
      final events = p.getEventsForDay(today.hDay, today.hMonth, today.hYear);
      expect(events, isNotEmpty,
          reason: 'today\'s events list should contain at least the '
                  'three daily adhkar (defaults enabled)');

      // Sanity: at least one of the three adhkar ids should appear,
      // since their defaults are all `defaultEnabled: true` and
      // their `matchesDisplayDay` returns `true` every day.
      final ids = events.map((e) => e.id).toList();
      final hasAdhkar = ids.any((id) =>
          id.startsWith('adhkar_sabah') ||
          id.startsWith('adhkar_masaa') ||
          id.startsWith('adhkar_nawm'));
      expect(hasAdhkar, isTrue,
          reason: 'expected a daily-adhkar event on today (ids: $ids)');
    });

    test('getEventsForDay(today) is non-empty in UAQ', () async {
      SharedPreferences.setMockInitialValues({'region': 'global'});
      final p = AppProvider();
      await p.init();

      final today = p.today;
      final events = p.getEventsForDay(today.hDay, today.hMonth, today.hYear);
      expect(events, isNotEmpty);
    });
  });
}
