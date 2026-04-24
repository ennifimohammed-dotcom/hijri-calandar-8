import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../models/event_model.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  static const String _channelId   = 'hijri_calendar_channel';
  static const String _channelName = 'تقويم الهجري';
  static const String _channelDesc = 'Hijri Calendar Notifications';

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
          android: androidInit, iOS: iosInit);

      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTap,
      );

      await _createChannel();
      _initialized = true;
      debugPrint('NotificationService: initialized');
    } catch (e) {
      debugPrint('NotificationService.init error: $e');
    }
  }

  Future<void> _createChannel() async {
    const channel = AndroidNotificationChannel(
      _channelId, _channelName,
      description: _channelDesc,
      importance: Importance.high,
      enableVibration: true,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  void _onNotificationTap(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.payload}');
  }

  // ── Request permissions ───────────────────────────────────
  Future<bool> requestPermissions() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        final granted = await android.requestNotificationsPermission();
        return granted ?? false;
      }
      return true;
    } catch (e) {
      debugPrint('requestPermissions error: $e');
      return false;
    }
  }

  // ── Schedule event reminders ──────────────────────────────
  /// Schedule all reminders for [event] within the next 30 days.
  Future<void> scheduleEventReminders(AppEvent event) async {
    if (!event.isEnabled || event.reminders.isEmpty) return;
    try {
      final now = DateTime.now();
      final limit = now.add(const Duration(days: 30));

      for (final reminder in event.reminders) {
        final notifTime =
            event.startDate.subtract(Duration(minutes: reminder.minutesBefore));
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
      debugPrint('scheduleEventReminders error: $e');
    }
  }

  /// Cancel all reminders for [eventId].
  Future<void> cancelEventReminders(AppEvent event) async {
    try {
      for (final reminder in event.reminders) {
        final id = _notifId(event.id, reminder.id);
        await _plugin.cancel(id);
      }
    } catch (e) {
      debugPrint('cancelEventReminders error: $e');
    }
  }

  // ── Bulk reschedule ───────────────────────────────────────
  /// Cancel all and reschedule for the next 30 days.
  Future<void> rescheduleAll(List<AppEvent> events) async {
    try {
      await _plugin.cancelAll();
      for (final event in events) {
        await scheduleEventReminders(event);
      }
      debugPrint('NotificationService: rescheduled ${events.length} events');
    } catch (e) {
      debugPrint('rescheduleAll error: $e');
    }
  }

  // ── Daily summary ─────────────────────────────────────────
  Future<void> scheduleDailySummary({
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
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
      debugPrint('scheduleDailySummary error: $e');
    }
  }

  // ── 29th day alert ────────────────────────────────────────
  Future<void> schedule29thDayAlert({
    required DateTime scheduledDate,
    required String title,
    required String body,
  }) async {
    try {
      await _scheduleExact(
        id: 290000,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        payload: '29th_day',
      );
    } catch (e) {
      debugPrint('schedule29thDayAlert error: $e');
    }
  }

  // ── Ramadan approaching alert ─────────────────────────────
  Future<void> scheduleRamadanAlert({
    required DateTime ramadanStart,
    required int daysBefore,
    required String title,
    required String body,
  }) async {
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
      debugPrint('scheduleRamadanAlert error: $e');
    }
  }

  // ── Immediate notification ────────────────────────────────
  Future<void> showImmediate({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      await _plugin.show(
        id, title, body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId, _channelName,
            channelDescription: _channelDesc,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: payload,
      );
    } catch (e) {
      debugPrint('showImmediate error: $e');
    }
  }

  Future<void> cancelAll() async {
    try { await _plugin.cancelAll(); } catch (e) {
      debugPrint('cancelAll error: $e');
    }
  }

  // ── Private helpers ───────────────────────────────────────
  Future<void> _scheduleExact({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
  }) async {
    try {
      final tzDate = tz.TZDateTime.from(scheduledDate, tz.local);
      await _plugin.zonedSchedule(
        id, title, body, tzDate,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId, _channelName,
            channelDescription: _channelDesc,
            importance: Importance.high,
            priority: Priority.high,
            enableVibration: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    } catch (e) {
      debugPrint('_scheduleExact id=$id error: $e');
    }
  }

  int _notifId(String eventId, String reminderId) {
    return (eventId + reminderId).hashCode.abs() % 100000;
  }

  String _reminderBody(EventReminder reminder, String locale) {
    if (reminder.minutesBefore == 0) {
      return locale == 'ar' ? 'يبدأ الآن' : 'Starting now';
    }
    if (reminder.minutesBefore < 60) {
      return locale == 'ar'
          ? 'يبدأ خلال ${reminder.minutesBefore} دقيقة'
          : 'Starts in ${reminder.minutesBefore} minutes';
    }
    if (reminder.minutesBefore < 1440) {
      final h = reminder.minutesBefore ~/ 60;
      return locale == 'ar'
          ? 'يبدأ خلال $h ${h == 1 ? "ساعة" : "ساعات"}'
          : 'Starts in $h hour${h > 1 ? "s" : ""}';
    }
    final d = reminder.minutesBefore ~/ 1440;
    return locale == 'ar'
        ? 'يبدأ خلال $d ${d == 1 ? "يوم" : "أيام"}'
        : 'Starts in $d day${d > 1 ? "s" : ""}';
  }
}
