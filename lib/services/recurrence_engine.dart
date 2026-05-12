import '../models/event_model.dart';
import '../utils/hijri_utils.dart';
import '../utils/app_logger.dart';

/// Production-grade recurrence engine.
/// Expands recurring events lazily within a date range only.
/// Cached in memory per range.
class RecurrenceEngine {
  // Memory cache: rangeKey → list of instances
  final Map<String, List<EventInstance>> _cache = {};

  String _cacheKey(DateTime from, DateTime to) =>
      '${from.millisecondsSinceEpoch}_${to.millisecondsSinceEpoch}';

  void invalidate() => _cache.clear();

  /// Get all instances of [events] within [from]..[to].
  /// Results are sorted by date. Cached per range.
  List<EventInstance> getInstances(
      List<AppEvent> events, DateTime from, DateTime to) {
    final key = _cacheKey(from, to);
    if (_cache.containsKey(key)) return _cache[key]!;

    final result = <EventInstance>[];
    for (final event in events) {
      if (!event.isEnabled) continue;
      try {
        result.addAll(_expand(event, from, to));
      } catch (e) {
        AppLogger.error('RecurrenceEngine: error expanding ${event.id}', error: e);
      }
    }
    result.sort((a, b) => a.instanceDate.compareTo(b.instanceDate));
    _cache[key] = result;
    return result;
  }

  /// Get instances for a specific day only.
  List<EventInstance> getInstancesForDay(List<AppEvent> events, DateTime day) {
    final from = DateTime(day.year, day.month, day.day);
    final to   = DateTime(day.year, day.month, day.day, 23, 59, 59);
    return getInstances(events, from, to);
  }

  List<EventInstance> _expand(AppEvent event, DateTime from, DateTime to) {
    final rule = event.recurrenceRule;

    // Non-recurring: just check if it falls in range
    if (rule == null) {
      final d = event.startDate;
      if (_dateInRange(d, from, to)) {
        return [EventInstance(event: event, instanceDate: d)];
      }
      return [];
    }

    return _expandRecurring(event, rule, from, to);
  }

  List<EventInstance> _expandRecurring(
      AppEvent event, RecurrenceRule rule, DateTime from, DateTime to) {
    final instances = <EventInstance>[];
    var current = _normalizeDate(event.startDate);
    int count = 0;
    final maxCount = rule.count;
    final maxDate = rule.until;
    int safetyLimit = 1500; // prevent infinite loops

    while (safetyLimit-- > 0) {
      // Stop conditions
      if (current.isAfter(to)) break;
      if (maxDate != null && current.isAfter(maxDate)) break;
      if (maxCount != null && count >= maxCount) break;

      if (!current.isBefore(from) && !current.isAfter(to)) {
        instances.add(EventInstance(
          event: event,
          instanceDate: current,
          isFirstOccurrence: count == 0,
        ));
      }

      count++;
      final next = _nextOccurrence(current, rule);
      if (next == null || !next.isAfter(current)) break;
      current = next;
    }

    return instances;
  }

  DateTime? _nextOccurrence(DateTime current, RecurrenceRule rule) {
    switch (rule.frequency) {
      case RecurrenceFrequency.daily:
        return current.add(Duration(days: rule.interval));

      case RecurrenceFrequency.weekly:
        if (rule.weekdays.isEmpty) {
          return current.add(Duration(days: 7 * rule.interval));
        }
        // Find next valid weekday
        for (int i = 1; i <= 7 * rule.interval; i++) {
          final candidate = current.add(Duration(days: i));
          if (rule.weekdays.contains(candidate.weekday)) return candidate;
        }
        return current.add(Duration(days: 7 * rule.interval));

      case RecurrenceFrequency.monthly:
        var next = DateTime(
          current.year,
          current.month + rule.interval,
          rule.monthDay ?? current.day,
          current.hour, current.minute,
        );
        // Handle months with fewer days
        while (next.month != ((current.month + rule.interval - 1) % 12) + 1) {
          next = next.subtract(const Duration(days: 1));
        }
        return next;

      case RecurrenceFrequency.yearly:
        return DateTime(
          current.year + rule.interval,
          rule.month ?? current.month,
          rule.monthDay ?? current.day,
          current.hour, current.minute,
        );
    }
  }

  bool _dateInRange(DateTime d, DateTime from, DateTime to) {
    final norm = _normalizeDate(d);
    return !norm.isBefore(from) && !norm.isAfter(to);
  }

  DateTime _normalizeDate(DateTime d) =>
      DateTime(d.year, d.month, d.day, d.hour, d.minute);

  // ── Islamic (Hijri-based) event expansion ──────────────
  /// Expand an Islamic event (defined by Hijri day/month) into
  /// Gregorian dates within [from]..[to].
  List<EventInstance> expandIslamicEvent(
      AppEvent event, DateTime from, DateTime to) {
    if (event.hijriDay == null || event.hijriMonth == null) return [];
    final instances = <EventInstance>[];

    // Search ±2 Hijri years around the range
    final fromHijri = HijriDate.fromGregorian(from);
    final toHijri   = HijriDate.fromGregorian(to);

    for (int y = fromHijri.hYear - 1; y <= toHijri.hYear + 1; y++) {
      try {
        final maxDay = HijriDate.daysInMonth(y, event.hijriMonth!);
        final day = event.hijriDay!.clamp(1, maxDay);
        final greg = HijriDate.hijriToGregorian(y, event.hijriMonth!, day);
        if (!greg.isBefore(from) && !greg.isAfter(to)) {
          instances.add(EventInstance(event: event, instanceDate: greg));
        }
      } catch (e) {
        AppLogger.error('expandIslamicEvent year $y failed', error: e);
      }
    }
    return instances;
  }
}

