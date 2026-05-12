import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

/// Centralised logger for the CalendarHijri app.
///
/// This is the only sanctioned way to write diagnostics from the
/// app's code. Direct `print(...)` is forbidden by the linter
/// (`avoid_print: true`); `debugPrint(...)` is allowed inside the
/// Flutter framework but should not leak into our own modules
/// either — having one entry point makes it trivial to:
///
///   * route everything through `dart:developer.log`, which the
///     Flutter DevTools console understands natively (filter by
///     `name`, see the `level`-coloured output, follow stack
///     traces inline);
///   * silence non-error logs in release builds without touching
///     every call site;
///   * attach a real crash reporter later (Sentry, Firebase
///     Crashlytics, …) by editing this one file instead of
///     hunting down every `debugPrint` in the project.
///
/// Three levels are exposed:
///
///   * [info]  — high-signal lifecycle events ("Notifications
///                initialized", "Region changed to ma"). Visible
///                in DevTools, silent in release.
///   * [debug] — fine-grained traces ("EventRepository: added
///                <id>"). Visible in DevTools, silent in release.
///   * [error] — failures that should never be swallowed. Always
///                logged, in every build mode, with the original
///                exception + stack trace if available.
///
/// All methods accept an optional [tag] so logs can be filtered
/// per subsystem in DevTools.
class AppLogger {
  AppLogger._();

  /// Default subsystem name used when no [tag] is given.
  static const String _defaultTag = 'CalendarHijri';

  /// dart:developer log levels (rough mapping to syslog-ish
  /// severities). Lower numbers are less severe.
  static const int _kInfoLevel  = 800;
  static const int _kDebugLevel = 500;
  static const int _kErrorLevel = 1000;

  /// Lifecycle / high-signal events. Suppressed in release.
  static void info(String message, {String? tag}) {
    if (kReleaseMode) return;
    developer.log(
      message,
      name: tag ?? _defaultTag,
      level: _kInfoLevel,
    );
  }

  /// Verbose traces useful during development. Suppressed in
  /// release so they never appear in shipped APKs.
  static void debug(String message, {String? tag}) {
    if (kReleaseMode) return;
    developer.log(
      message,
      name: tag ?? _defaultTag,
      level: _kDebugLevel,
    );
  }

  /// Failures and caught exceptions. ALWAYS logged, including in
  /// release builds, so that downstream crash reporters can pick
  /// them up. Pass the original [error] and [stack] whenever they
  /// are in scope — they will be rendered in DevTools and forwarded
  /// to any reporter wired in later.
  static void error(
    String message, {
    Object? error,
    StackTrace? stack,
    String? tag,
  }) {
    developer.log(
      message,
      name: tag ?? _defaultTag,
      level: _kErrorLevel,
      error: error,
      stackTrace: stack,
    );
  }
}
