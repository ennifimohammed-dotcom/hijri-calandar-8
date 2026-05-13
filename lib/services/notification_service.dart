import 'dart:typed_data';

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
    } catch (e, stack) {
      AppLogger.error('NotificationService.init failed', error: e, stack: stack);
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
    } catch (e, stack) {
      AppLogger.error('requestPermissions failed', error: e, stack: stack);
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
    } catch (e, stack) {
      AppLogger.error('setNotificationVolume not available', error: e, stack: stack);
    }
  }

  Future<void> previewSound() async {
    try {
      await _volumeChannel.invokeMethod('previewSound', {
        'sound': _settings.settings.sound.key,
        'customPath': _settings.settings.customSoundPath,
        'volume': _settings.settings.volume,
      });
    } catch (e, stack) {
      AppLogger.error('previewSound not available', error: e, stack: stack);
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
      if (s.sound == NotificationSound.custom) {
        // User-picked file. If the path is set we use it as a
        // `content://` URI; if it's missing for any reason (file
        // deleted, permissions revoked) we fall back to the
        // default built-in chime so the channel never ends up
        // silent when the user expected a sound.
        if (s.customSoundPath != null && s.customSoundPath!.isNotEmpty) {
          soundResource = UriAndroidNotificationSound(s.customSoundPath!);
        } else {
          soundResource =
              const RawResourceAndroidNotificationSound('brightline');
        }
        playSound = true;
      } else {
        // All 10 built-in sounds map 1:1 to their `key` (which
        // matches the .ogg filename generated in CI under
        // `android/app/src/main/res/raw/`).
        soundResource = RawResourceAndroidNotificationSound(s.sound.key);
        playSound = true;
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
    } catch (e, stack) {
      AppLogger.error('scheduleEventReminders failed', error: e, stack: stack);
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
    } catch (e, stack) {
      AppLogger.error('cancelEventReminders failed', error: e, stack: stack);
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
    } catch (e, stack) {
      AppLogger.error('rescheduleAll failed', error: e, stack: stack);
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
    } catch (e, stack) {
      AppLogger.error('scheduleDailySummary failed', error: e, stack: stack);
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
    } catch (e, stack) {
      AppLogger.error('schedule29thDayAlert failed', error: e, stack: stack);
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
    } catch (e, stack) {
      AppLogger.error('scheduleRamadanAlert failed', error: e, stack: stack);
    }
  }

  // ── Islamic reminders ────────────────────────────────────
  /// Notification id range reserved for Islamic events. Keeps them
  /// separate from user-event reminder ids (which fall in 0..99 999),
  /// the system reminders (290 000, 900 000–900 001, 999 998, 999 999)
  /// and any future bands. Wide range = effectively zero birthday-
  /// paradox collisions across the 30-day rolling window.
  static const int _kIslamicIdMin = 1000000;
  static const int _kIslamicIdMax = 0x7FFFFFFE; // 2_147_483_646

  /// Stable, conflict-free id derived from (eventId, date).
  ///
  /// Uses `Object.hash` (well-distributed 64-bit hash) instead of
  /// `String.hashCode` (poly-1 over UTF-16). With ~30 days × 13
  /// events = ~390 IDs/month and a ~2.1 G-slot range, the
  /// birthday-paradox collision probability drops from ~7 %/month
  /// (old code) to ~3 × 10⁻⁵ — effectively zero, which is what
  /// "prevent notification collisions" requires.
  int _islamicNotifId(String eventId, DateTime date) {
    final hash = Object.hash(eventId, date.year, date.month, date.day);
    final range = _kIslamicIdMax - _kIslamicIdMin;
    return _kIslamicIdMin + (hash.abs() % range);
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
    } catch (e, stack) {
      AppLogger.error('scheduleIslamicReminder failed', error: e, stack: stack);
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
    } catch (e, stack) {
      AppLogger.error('cancelIslamicReminders failed', error: e, stack: stack);
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
    } catch (e, stack) {
      AppLogger.error('scheduleMidnightReschedule failed',
          error: e, stack: stack);
    }
  }

  // ── Weekly renewal ───────────────────────────────────────
  /// Reserved system-id for the weekly renewal alarm. Lives in the
  /// same high band as the other system pings (290 000, 900 0xx,
  /// 999 999) so it never collides with user/Islamic reminders.
  static const int _kWeeklyRenewalId = 999998;

  /// Schedules a recurring weekly silent alarm — fires every 7 days
  /// at 03:00 local time. The alarm itself is a no-op (silent
  /// notification, importance low); its purpose is to keep the
  /// app's alarm pipeline alive so that, even if the user goes a
  /// month without opening the app, the OS-level [AlarmManager]
  /// retains a live reference to our notification channel and
  /// channels don't get pruned by aggressive battery savers.
  ///
  /// Combined with `init()` calling `_scheduleIslamicNotifications`
  /// on every app open, this is the best 7-day renewal guarantee
  /// achievable without a native Android `BroadcastReceiver` +
  /// Workmanager-style background isolate (out of Phase 4 scope).
  Future<void> scheduleWeeklyRenewal() async {
    if (!_settings.settings.enabled) return;
    try {
      final base = DateTime.now().add(const Duration(days: 7));
      final firstFire = DateTime(base.year, base.month, base.day, 3, 0);
      final tzDate = tz.TZDateTime.from(firstFire, tz.local);

      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'hijri_weekly_renewal',
          'Renewal',
          channelDescription: 'Internal weekly renewal alarm',
          importance: Importance.min,
          priority: Priority.min,
          playSound: false,
          enableVibration: false,
          enableLights: false,
          showWhen: false,
          channelShowBadge: false,
          silent: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: false,
          presentBadge: false,
          presentSound: false,
        ),
      );

      await _plugin.zonedSchedule(
        _kWeeklyRenewalId,
        '',
        '',
        tzDate,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: 'weekly_renewal',
      );
      AppLogger.info('NotificationService: weekly renewal scheduled '
          'for $firstFire (repeats every 7 days)');
    } catch (e, stack) {
      AppLogger.error('scheduleWeeklyRenewal failed',
          error: e, stack: stack);
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
    } catch (e, stack) {
      AppLogger.error('showImmediate failed', error: e, stack: stack);
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
    } catch (e, stack) {
      AppLogger.error('cancelAll failed', error: e, stack: stack);
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
    } catch (e, stack) {
      AppLogger.error('_scheduleExact id=$id failed', error: e, stack: stack);
    }
  }

  /// Stable, conflict-free id for a user event's reminder. Same
  /// rationale as [_islamicNotifId] — `Object.hash` over the two
  /// inputs gives a high-quality 64-bit hash; the modulo keeps us
  /// inside the user-event band [0, 100 000).
  int _notifId(String eventId, String reminderId) {
    return Object.hash(eventId, reminderId).abs() % 100000;
  }

  String _reminderBody(EventReminder reminder, String locale) {
    // Use the locale-aware label which already covers both reminder kinds.
    return reminder.label(locale);
  }
}
