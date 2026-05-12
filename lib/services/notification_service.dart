import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../models/event_model.dart';
import '../models/notification_settings.dart';
import '../utils/app_logger.dart';
import 'notification_settings_service.dart';

/// Production-grade notification engine.
/// - Per-settings dynamic Android channels (sound × mode × visibility)
/// - Heads-up popup, custom sound, vibration, lock-screen visibility
/// - Smart 30-day rolling schedule, midnight rescheduling, boot recovery
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final NotificationSettingsService _settings = NotificationSettingsService();

  static const MethodChannel _volumeChannel =
      MethodChannel('hijri_calendar/notifications');

  bool _initialized = false;

  // ── Init ─────────────────────────────────────────────────
  Future<void> init() async {
    if (_initialized) return;
    try {
      tz_data.initializeTimeZones();

      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initSettings = InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      );

      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTap,
      );

      await _settings.load();

      _initialized = true;
      AppLogger.info('NotificationService: initialized');
    } catch (e) {
      AppLogger.error('NotificationService.init failed', error: e);
    }
  }

  void _onNotificationTap(NotificationResponse response) {
    AppLogger.debug('Notification tapped: ${response.payload}');
  }

  // ── Permissions ──────────────────────────────────────────
  Future<bool> requestPermissions() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        final notif = await android.requestNotificationsPermission();
        final exact = await android.requestExactAlarmsPermission();
        return (notif ?? false) && (exact ?? true);
      }
      return true;
    } catch (e) {
      AppLogger.error('requestPermissions failed', error: e);
      return false;
    }
  }

  // ── Settings ─────────────────────────────────────────────
  NotificationSettings get currentSettings => _settings.settings;

  Future<void> applySettings(NotificationSettings s) async {
    await _settings.save(s);
    await _applySystemVolume(s.volume);
  }

  Future<void> _applySystemVolume(double volume) async {
    try {
      await _volumeChannel.invokeMethod('setNotificationVolume', {
        'volume': volume.clamp(0.0, 1.0),
      });
    } catch (e) {
      AppLogger.error('setNotificationVolume not available', error: e);
    }
  }

  Future<void> previewSound() async {
    try {
      await _volumeChannel.invokeMethod('previewSound', {
        'sound': _settings.settings.sound.key,
        'customPath': _settings.settings.customSoundPath,
        'volume': _settings.settings.volume,
      });
    } catch (e) {
      AppLogger.error('previewSound not available', error: e);
    }
  }

  // ── Channel construction ─────────────────────────────────
  AndroidNotificationDetails _buildAndroidDetails(NotificationSettings s) {
    final channelId = 'hijri_${s.channelSignature}';
    final channelName = s.mode == NotificationMode.alert
        ? 'تقويم الهجري — Alerte'
        : 'تقويم الهجري — Discret';
    final channelDesc = s.mode == NotificationMode.alert
        ? 'High priority Hijri Calendar reminders with sound & vibration'
        : 'Silent Hijri Calendar reminders';

    final isAlert = s.mode == NotificationMode.alert;
    // Heads-up popup: requires Importance.max + Priority.max on the
    // channel and notification. When the user disables popup but
    // keeps mode = alert, we still play sound and vibrate but lower
    // the priority so the OS just posts a regular notification.
    final wantsHeadsUp = isAlert && s.popupEnabled;
    final importance = !isAlert
        ? Importance.low
        : (wantsHeadsUp ? Importance.max : Importance.defaultImportance);
    final priority = !isAlert
        ? Priority.low
        : (wantsHeadsUp ? Priority.max : Priority.defaultPriority);
    final visibility =
        s.lockScreenVisibility == LockScreenVisibility.doNotShow
            ? NotificationVisibility.secret
            : NotificationVisibility.private;

    AndroidNotificationSound? soundResource;
    bool playSound = false;
    if (isAlert) {
      switch (s.sound) {
        case NotificationSound.brightline:
          soundResource =
              const RawResourceAndroidNotificationSound('brightline');
          playSound = true;
          break;
        case NotificationSound.alpha:
          soundResource = const RawResourceAndroidNotificationSound('alpha');
          playSound = true;
          break;
        case NotificationSound.arrow:
          soundResource = const RawResourceAndroidNotificationSound('arrow');
          playSound = true;
          break;
        case NotificationSound.custom:
          if (s.customSoundPath != null && s.customSoundPath!.isNotEmpty) {
            soundResource = UriAndroidNotificationSound(s.customSoundPath!);
            playSound = true;
          } else {
            soundResource =
                const RawResourceAndroidNotificationSound('brightline');
            playSound = true;
          }
          break;
      }
    }

    final vibrationPattern = (isAlert && s.vibrationEnabled)
        ? Int64List.fromList(<int>[0, 250, 250, 250])
        : null;

    return AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDesc,
      importance: importance,
      priority: priority,
      playSound: playSound,
      sound: soundResource,
      enableVibration: isAlert && s.vibrationEnabled,
      vibrationPattern: vibrationPattern,
      visibility: visibility,
      fullScreenIntent: false,
      category: AndroidNotificationCategory.event,
      ticker: 'Hijri Calendar',
      styleInformation: const DefaultStyleInformation(true, true),
      channelShowBadge: true,
    );
  }

  NotificationDetails _buildDetails(NotificationSettings s) {
    final ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: s.mode == NotificationMode.alert,
      sound: s.mode == NotificationMode.alert ? null : null,
    );
    return NotificationDetails(
      android: _buildAndroidDetails(s),
      iOS: ios,
    );
  }

  // ── Schedule one event ───────────────────────────────────
  Future<void> scheduleEventReminders(AppEvent event) async {
    final s = _settings.settings;
    if (!s.enabled) return;
    // Per-event gates (notifications spec §10):
    //   1. event.isEnabled       → calendar visibility
    //   2. event.notificationsEnabled → reminders fire or not
    //   3. event.reminders        → must have at least one reminder
    if (!event.isEnabled) return;
    if (!event.notificationsEnabled) return;
    if (event.reminders.isEmpty) return;

    try {
      final now = DateTime.now();
      final limit = now.add(const Duration(days: 30));

      for (final reminder in event.reminders) {
        final notifTime = _computeTriggerTime(event, reminder);
        if (notifTime == null) continue;
        if (notifTime.isBefore(now) || notifTime.isAfter(limit)) continue;

        final id = _notifId(event.id, reminder.id);
        await _scheduleExact(
          id: id,
          title: event.title('ar'),
          body: _reminderBody(reminder, 'ar'),
          scheduledDate: notifTime,
          payload: event.id,
        );
      }
    } catch (e) {
      AppLogger.error('scheduleEventReminders failed', error: e);
    }
  }

  /// Computes the absolute trigger time for a reminder given its kind.
  ///
  /// For all-day events the canonical reference is the start *date* (midnight
  /// local), so a fixed-time reminder (Google Agenda all-day rule) lands at
  /// (start.date - daysBefore) at fixedHour:fixedMinute regardless of the
  /// stored start hour. For timed events we keep the relative offset rule.
  DateTime? _computeTriggerTime(AppEvent event, EventReminder reminder) {
    if (reminder.kind == ReminderTriggerKind.fixedTime) {
      final startDay = DateTime(
        event.startDate.year,
        event.startDate.month,
        event.startDate.day,
      );
      final triggerDay = startDay.subtract(Duration(days: reminder.daysBefore));
      return DateTime(
        triggerDay.year,
        triggerDay.month,
        triggerDay.day,
        reminder.fixedHour,
        reminder.fixedMinute,
      );
    }
    // relative
    return event.startDate.subtract(Duration(minutes: reminder.minutesBefore));
  }

  Future<void> cancelEventReminders(AppEvent event) async {
    try {
      for (final reminder in event.reminders) {
        final id = _notifId(event.id, reminder.id);
        await _plugin.cancel(id);
      }
    } catch (e) {
      AppLogger.error('cancelEventReminders failed', error: e);
    }
  }

  // ── Bulk reschedule ──────────────────────────────────────
  Future<void> rescheduleAll(List<AppEvent> events) async {
    try {
      await _plugin.cancelAll();
      final s = _settings.settings;
      if (!s.enabled) {
        AppLogger.info('NotificationService: notifications disabled, skipping');
        return;
      }
      for (final event in events) {
        await scheduleEventReminders(event);
      }
      AppLogger.info('NotificationService: rescheduled ${events.length} events');
    } catch (e) {
      AppLogger.error('rescheduleAll failed', error: e);
    }
  }

  // ── Daily summary / Ramadan / 29th-day helpers ──────────
  Future<void> scheduleDailySummary({
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
    if (!_settings.settings.enabled) return;
    try {
      final now = DateTime.now();
      var scheduled = DateTime(now.year, now.month, now.day, hour, minute);
      if (scheduled.isBefore(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }
      await _scheduleExact(
        id: 900000,
        title: title,
        body: body,
        scheduledDate: scheduled,
        payload: 'daily_summary',
      );
    } catch (e) {
      AppLogger.error('scheduleDailySummary failed', error: e);
    }
  }

  Future<void> schedule29thDayAlert({
    required DateTime scheduledDate,
    required String title,
    required String body,
  }) async {
    if (!_settings.settings.enabled) return;
    try {
      await _scheduleExact(
        id: 290000,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        payload: '29th_day',
      );
    } catch (e) {
      AppLogger.error('schedule29thDayAlert failed', error: e);
    }
  }

  Future<void> scheduleRamadanAlert({
    required DateTime ramadanStart,
    required int daysBefore,
    required String title,
    required String body,
  }) async {
    if (!_settings.settings.enabled) return;
    try {
      final alertDate = ramadanStart.subtract(Duration(days: daysBefore));
      if (alertDate.isAfter(DateTime.now())) {
        await _scheduleExact(
          id: 900001,
          title: title,
          body: body,
          scheduledDate: alertDate,
          payload: 'ramadan_alert',
        );
      }
    } catch (e) {
      AppLogger.error('scheduleRamadanAlert failed', error: e);
    }
  }

  // ── Islamic reminders ────────────────────────────────────
  /// Notification id range reserved for Islamic events. Keeps them
  /// separate from user-event reminder ids (which fall in 0..99 999)
  /// and from the system reminders (290000, 900000-900001, 999999).
  static const int _kIslamicIdMin = 1000000;
  static const int _kIslamicIdMax = 1999999;

  /// Stable, conflict-free id derived from (eventId, date).
  int _islamicNotifId(String eventId, DateTime date) {
    final key = '$eventId|${date.year}|${date.month}|${date.day}';
    return _kIslamicIdMin + (key.hashCode.abs() % (_kIslamicIdMax - _kIslamicIdMin));
  }

  /// Schedules a single Islamic-reminder notification at [scheduledDate].
  /// Body text is rendered with BigTextStyle so the full description +
  /// virtue text is shown in the notification drawer without
  /// truncation.
  Future<void> scheduleIslamicReminder({
    required String eventId,
    required DateTime date,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    if (!_settings.settings.enabled) return;
    if (!scheduledDate.isAfter(DateTime.now())) return;
    try {
      final id = _islamicNotifId(eventId, date);
      await _scheduleExact(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        payload: 'islamic_$eventId',
        bigText: true,
      );
    } catch (e) {
      AppLogger.error('scheduleIslamicReminder failed', error: e);
    }
  }

  /// Cancels every notification id in the Islamic range. Called
  /// before re-scheduling so the next 30 days are rebuilt cleanly.
  Future<void> cancelIslamicReminders() async {
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final req in pending) {
        if (req.id >= _kIslamicIdMin && req.id <= _kIslamicIdMax) {
          await _plugin.cancel(req.id);
        }
      }
    } catch (e) {
      AppLogger.error('cancelIslamicReminders failed', error: e);
    }
  }

  // ── Midnight self-reschedule ─────────────────────────────
  Future<void> scheduleMidnightReschedule() async {
    if (!_settings.settings.enabled) return;
    try {
      final now = DateTime.now();
      var scheduled = DateTime(now.year, now.month, now.day, 0, 1)
          .add(const Duration(days: 1));
      await _scheduleExact(
        id: 999999,
        title: '',
        body: '',
        scheduledDate: scheduled,
        payload: 'midnight_reschedule',
        silent: true,
      );
    } catch (e) {
      AppLogger.error('scheduleMidnightReschedule failed', error: e);
    }
  }

  // ── Immediate ────────────────────────────────────────────
  Future<void> showImmediate({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_settings.settings.enabled) return;
    try {
      await _plugin.show(
        id,
        title,
        body,
        _buildDetails(_settings.settings),
        payload: payload,
      );
    } catch (e) {
      AppLogger.error('showImmediate failed', error: e);
    }
  }

  Future<void> showTestNotification() async {
    await showImmediate(
      id: 777777,
      title: 'Test تقويم الهجري',
      body: 'Notification de test — ${DateTime.now()}',
      payload: 'test',
    );
  }

  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (e) {
      AppLogger.error('cancelAll failed', error: e);
    }
  }

  // ── Private helpers ─────────────────────────────────────
  Future<void> _scheduleExact({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
    bool silent = false,
    bool bigText = false,
  }) async {
    try {
      final tzDate = tz.TZDateTime.from(scheduledDate, tz.local);
      final s = _settings.settings;
      NotificationDetails details;
      if (silent) {
        details = const NotificationDetails(
          android: AndroidNotificationDetails(
            'hijri_silent_internal',
            'Internal',
            channelDescription: 'Internal scheduling channel',
            importance: Importance.min,
            priority: Priority.min,
            playSound: false,
            enableVibration: false,
            visibility: NotificationVisibility.secret,
            showWhen: false,
          ),
        );
      } else if (bigText) {
        // Re-decorate the user's chosen channel with BigTextStyle so
        // long Islamic-reminder bodies (full hadîth + virtue text)
        // expand cleanly in the notification drawer.
        final base = _buildAndroidDetails(s);
        details = NotificationDetails(
          android: AndroidNotificationDetails(
            base.channelId,
            base.channelName,
            channelDescription: base.channelDescription,
            importance: base.importance,
            priority: base.priority,
            playSound: base.playSound,
            sound: base.sound,
            enableVibration: base.enableVibration,
            vibrationPattern: base.vibrationPattern,
            visibility: base.visibility,
            fullScreenIntent: base.fullScreenIntent,
            category: base.category,
            ticker: base.ticker,
            channelShowBadge: base.channelShowBadge,
            styleInformation: BigTextStyleInformation(
              body,
              htmlFormatBigText: false,
              contentTitle: title,
              htmlFormatContentTitle: false,
              summaryText: '',
            ),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        );
      } else {
        details = _buildDetails(s);
      }

      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tzDate,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    } catch (e) {
      AppLogger.error('_scheduleExact id=$id failed', error: e);
    }
  }

  int _notifId(String eventId, String reminderId) {
    return (eventId + reminderId).hashCode.abs() % 100000;
  }

  String _reminderBody(EventReminder reminder, String locale) {
    // Use the locale-aware label which already covers both reminder kinds.
    return reminder.label(locale);
  }
}
