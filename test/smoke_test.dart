import 'package:flutter_test/flutter_test.dart';

import 'package:hijri_calendar/utils/app_logger.dart';

/// Phase 1 — Safety Net smoke test.
///
/// This file exists so `flutter test` has at least one passing test
/// to run in CI from day one. Real unit-test coverage lands in
/// Phase 3 (Hijri kernel, Islamic-event matching, agenda range).
///
/// What is checked here:
///   * `flutter test` is wired up and the test binary builds.
///   * `AppLogger` symbols compile and don't throw at runtime —
///     this guards against a future refactor accidentally turning
///     the logger into something that crashes on import.
void main() {
  group('Phase 1 — Safety Net smoke', () {
    test('AppLogger methods are callable without throwing', () {
      expect(() => AppLogger.info('smoke: info'), returnsNormally);
      expect(() => AppLogger.debug('smoke: debug'), returnsNormally);
      expect(
        () => AppLogger.error('smoke: error',
            error: StateError('synthetic'),
            stack: StackTrace.current),
        returnsNormally,
      );
    });

    test('arithmetic baseline (sanity)', () {
      expect(1 + 1, 2);
    });
  });
}
