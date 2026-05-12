import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/event_model.dart';
import '../services/notification_service.dart';
import '../utils/app_logger.dart';

/// Offline-first event repository.
/// All events stored in SharedPreferences (JSON).
/// Every write triggers notification reschedule.
class EventRepository {
  static const _kEventsKey = 'app_events_v2';

  final NotificationService _notifs;
  List<AppEvent> _cache = [];
  bool _loaded = false;

  EventRepository({NotificationService? notificationService})
      : _notifs = notificationService ?? NotificationService();

  // ── Load ─────────────────────────────────────────────────
  Future<List<AppEvent>> loadAll() async {
    if (_loaded) return List.unmodifiable(_cache);
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_kEventsKey);
      if (json != null && json.isNotEmpty) {
        _cache = AppEvent.decodeList(json);
      }
    } catch (e) {
      AppLogger.error('EventRepository.loadAll failed', error: e);
      _cache = [];
    }
    _loaded = true;
    return List.unmodifiable(_cache);
  }

  List<AppEvent> getCached() => List.unmodifiable(_cache);

  // ── Save ─────────────────────────────────────────────────
  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kEventsKey, AppEvent.encodeList(_cache));
    } catch (e) {
      AppLogger.error('EventRepository._persist failed', error: e);
    }
  }

  // ── CRUD ─────────────────────────────────────────────────
  Future<void> add(AppEvent event) async {
    _cache.removeWhere((e) => e.id == event.id);
    _cache.add(event);
    await _persist();
    await _notifs.scheduleEventReminders(event);
    AppLogger.debug('EventRepository: added ${event.id}');
  }

  Future<void> update(AppEvent event) async {
    final idx = _cache.indexWhere((e) => e.id == event.id);
    if (idx < 0) return;
    final old = _cache[idx];
    await _notifs.cancelEventReminders(old);
    _cache[idx] = event;
    await _persist();
    await _notifs.scheduleEventReminders(event);
    AppLogger.debug('EventRepository: updated ${event.id}');
  }

  Future<void> delete(String id) async {
    final idx = _cache.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    final ev = _cache[idx];
    await _notifs.cancelEventReminders(ev);
    _cache.removeAt(idx);
    await _persist();
    AppLogger.debug('EventRepository: deleted $id');
  }

  Future<void> toggle(String id, bool enabled) async {
    final idx = _cache.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    final updated = _cache[idx].copyWith(isEnabled: enabled,
        updatedAt: DateTime.now());
    _cache[idx] = updated;
    await _persist();
    if (enabled) {
      await _notifs.scheduleEventReminders(updated);
    } else {
      await _notifs.cancelEventReminders(updated);
    }
  }

  Future<void> deleteAll() async {
    _cache.clear();
    await _persist();
    await _notifs.cancelAll();
  }

  /// Full reschedule — called on app start and midnight.
  Future<void> rescheduleAllNotifications() async {
    await _notifs.rescheduleAll(_cache);
  }

  // ── Search / filter ───────────────────────────────────────
  List<AppEvent> search(String query) {
    if (query.isEmpty) return [];
    final q = query.toLowerCase();
    return _cache.where((e) =>
      e.titles.values.any((t) => t.toLowerCase().contains(q)) ||
      e.descriptions.values.any((d) => d.toLowerCase().contains(q)) ||
      e.location.toLowerCase().contains(q)
    ).toList();
  }

  List<AppEvent> filterByType(EventType type) =>
      _cache.where((e) => e.type == type).toList();

  List<AppEvent> filterByDateRange(DateTime from, DateTime to) =>
      _cache.where((e) =>
          !e.startDate.isAfter(to) && !e.endDate.isBefore(from)).toList();

  List<AppEvent> filterByColor(Color color) =>
      _cache.where((e) => e.color == color).toList();
}
