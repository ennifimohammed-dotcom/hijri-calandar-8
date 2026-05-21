import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/event_model.dart';
import '../models/notification_settings.dart';
import '../data/islamic_events.dart';
import '../data/hijri_months.dart';
import '../repositories/event_repository.dart';
import '../services/recurrence_engine.dart';
import '../services/notification_service.dart';
import '../utils/app_logger.dart';
import '../utils/hijri_kernel.dart' as kernel;
import '../services/notification_settings_service.dart';
import '../theme.dart';
import '../utils/hijri_utils.dart';

enum CalendarViewMode { monthly, weekly, agenda }

/// Visual density for the monthly calendar grid. Drives the
/// `mainAxisSpacing` / `crossAxisSpacing` of the day-cell grid.
enum CalendarDensity { compact, normal, wide }

class AppProvider extends ChangeNotifier {
  // ── Dependencies ─────────────────────────────────────────
  final EventRepository _repo;
  final RecurrenceEngine _engine;
  final NotificationService _notifs;
  final NotificationSettingsService _notifSettings;

  AppProvider({
    EventRepository? repository,
    RecurrenceEngine? engine,
    NotificationService? notifs,
    NotificationSettingsService? notifSettings,
  })  : _repo = repository ?? EventRepository(),
        _engine = engine ?? RecurrenceEngine(),
        _notifs = notifs ?? NotificationService(),
        _notifSettings = notifSettings ?? NotificationSettingsService();

  // ── Debounce for Islamic-notification rescheduling ──────
  //
  // [_scheduleIslamicNotifications] cancels and re-creates 30 days
  // of OS-level alarms — a heavy operation. Several settings paths
  // (region change, manual adjust, per-event time, toggling events,
  // zakat dates) all trigger it, and the UI lets users tap multiple
  // toggles in a row. Without debounce, that's N consecutive
  // full-window reschedules in a few hundred milliseconds, each
  // hammering AlarmManager. The 500 ms coalescing window batches
  // rapid-fire changes into a single reschedule.
  //
  // The timer is cancelled in [dispose] so the provider doesn't
  // leak a pending callback when the widget tree tears down.
  Timer? _islamicReschedTimer;

  /// Public-ish request to refresh Islamic notifications, debounced
  /// at 500 ms. Replaces every previous direct
  /// `_scheduleIslamicNotifications()` call site EXCEPT the one
  /// inside [init] — which runs once at startup and benefits from
  /// firing synchronously.
  void _requestIslamicReschedule() {
    _islamicReschedTimer?.cancel();
    _islamicReschedTimer = Timer(
      const Duration(milliseconds: 500),
      _scheduleIslamicNotifications,
    );
  }

  @override
  void dispose() {
    _islamicReschedTimer?.cancel();
    _islamicReschedTimer = null;
    super.dispose();
  }

  // ── Calendar state ────────────────────────────────────────
  late HijriDate _currentMonth;
  late HijriDate _today;
  HijriDate? _selectedDay;
  CalendarViewMode _viewMode = CalendarViewMode.monthly;
  bool _isLoading = true;

  // ── Settings state ────────────────────────────────────────
  ThemeMode _themeMode = ThemeMode.light;
  String _locale = 'ar';
  final Map<String, bool> _islamicEventsEnabled = {};

  /// Per-event configurable trigger time. Key = IslamicEventConfig.id.
  /// Missing entries fall back to the cfg's defaultHour/defaultMinute.
  final Map<String, TimeOfDay> _islamicEventTimes = {};

  // ── Zakat — user-configured annual due date + 2 reminders ──
  DateTime? _zakatDueDate;
  DateTime? _zakatReminder1;
  DateTime? _zakatReminder2;

  NotificationSettings _notificationSettings = const NotificationSettings();

  /// Index into [kAccentPalette] (theme.dart). Default 0 = green.
  /// Drives [AccentBus] which backs `AppColors.green` / `greenPale`.
  int _accentIndex = 0;

  /// Global text-scale multiplier applied via MediaQuery in main.dart.
  /// Picker choices: S = 0.85, M = 1.0, L = 1.15, XL = 1.30.
  double _fontScale = 1.0;

  /// Visual density for the monthly grid.
  CalendarDensity _calendarDensity = CalendarDensity.normal;

  /// Font-family identifier — picked from one of the lists below.
  ///   Arabic: 'amiri', 'cairo', 'tajawal'   (3 choices)
  ///   Other:  'roboto', 'merriweather'      (2 choices)
  /// Defaults align with the existing visual identity (Amiri for AR
  /// headings, Roboto otherwise).
  String _fontFamily = 'amiri';

  /// Region code for Hijri calendar synchronization. Each region has a
  /// default day-offset relative to the Umm al-Qura baseline (see
  /// [_regionOffset]). The user MAY further fine-tune via
  /// [_hijriManualAdjust].
  ///
  /// Defaults are sourced from the official calendrical practice in
  /// each country: Saudi Arabia & global use Umm al-Qura (offset 0);
  /// Morocco (Ministry of Habous and Islamic Affairs) and Algeria
  /// (Ministry of Religious Affairs) typically rely on local crescent
  /// sighting which lags Umm al-Qura by one day, so default offset
  /// = +1; Tunisia, Türkiye (Diyanet) and Indonesia normally align
  /// with Umm al-Qura calculation.
  ///
  /// First-run default = Morocco. The user can change it from the
  /// Language section in Settings; the choice is persisted under the
  /// `region` key in SharedPreferences so subsequent launches restore
  /// the user's pick.
  String _region = 'ma';
  int _hijriManualAdjust = 0;

  // ── Getters ───────────────────────────────────────────────
  HijriDate get currentMonth => _currentMonth;
  HijriDate get today => _today;
  HijriDate? get selectedDay => _selectedDay;
  CalendarViewMode get viewMode => _viewMode;
  bool get isLoading => _isLoading;
  ThemeMode get themeMode => _themeMode;
  String get locale => _locale;
  String get region => _region;
  int get hijriManualAdjust => _hijriManualAdjust;
  int get hijriDayOffset => _regionOffset(_region) + _hijriManualAdjust;
  List<AppEvent> get userEvents => _repo.getCached();
  Map<String, bool> get islamicEventsEnabled =>
      Map.unmodifiable(_islamicEventsEnabled);
  NotificationSettings get notificationSettings => _notificationSettings;

  bool get allIslamicEventsEnabled =>
      _islamicEventsEnabled.isNotEmpty &&
      _islamicEventsEnabled.values.every((v) => v);

  // ── Init ─────────────────────────────────────────────────
  Future<void> init() async {
    try {
      // Hard invariant: the canonical Hijri month list must remain
      // in chronological order (1..12). Throws if a future refactor
      // ever reorders it.
      assertHijriMonthOrder();

      await _notifs.init();

      for (final e in IslamicEventsData.events) {
        _islamicEventsEnabled[e.id] = e.defaultEnabled;
      }

      // CRITICAL ordering: load persisted prefs FIRST so the region
      // offset is in place before computing today. Otherwise restart
      // with region = Morocco (offset +1) would compute today using
      // the default region = global (offset 0), and the calendar
      // would highlight the wrong cell on startup until the user
      // manually tapped Today.
      await _loadPrefs();
      _notificationSettings = await _notifSettings.load();

      _today = _todayForRegion();
      _currentMonth = HijriDate(_today.hYear, _today.hMonth, 1);
      _selectedDay = _today;

      await _notifs.requestPermissions();
      await _repo.loadAll();
      await _repo.rescheduleAllNotifications();
      // Initial scheduling is synchronous and direct — the
      // debounce-via-`_requestIslamicReschedule` exists for the
      // rapid-fire settings paths (region change, toggles, zakat
      // dates) and would just delay the first user-visible
      // schedule by 500 ms at startup for no benefit.
      await _scheduleIslamicNotifications();
      await _notifs.scheduleMidnightReschedule();
      // Phase 4 — weekly self-rearming alarm. Fires every 7 days
      // even if the user doesn't open the app in between, keeping
      // the OS-level notification pipeline warm. Returns silently
      // if the platform refuses (caught inside the service).
      await _notifs.scheduleWeeklyRenewal();
    } catch (e, stack) {
      AppLogger.error('AppProvider.init failed', error: e, stack: stack);
    }
    _isLoading = false;
    notifyListeners();
  }

  // ── Calendar navigation ───────────────────────────────────
  void goToPreviousMonth() {
    _currentMonth = _currentMonth.addMonths(-1);
    _engine.invalidate();
    notifyListeners();
  }

  void goToNextMonth() {
    _currentMonth = _currentMonth.addMonths(1);
    _engine.invalidate();
    notifyListeners();
  }

  /// Jump the visible month directly. Used by the infinite PageView so
  /// header and grid stay synchronized after a swipe without iterating
  /// next/prev (which would drift if pages are skipped).
  void setCurrentMonth(int year, int monthIndex) {
    if (_currentMonth.hYear == year && _currentMonth.hMonth == monthIndex) {
      return;
    }
    _currentMonth = HijriDate(year, monthIndex, 1);
    _engine.invalidate();
    notifyListeners();
  }

  void selectDay(HijriDate day) {
    _selectedDay = day;
    notifyListeners();
  }

  void goToToday() {
    _today = _todayForRegion();
    _currentMonth = HijriDate(_today.hYear, _today.hMonth, 1);
    _selectedDay = _today;
    _engine.invalidate();
    notifyListeners();
  }

  // ── Region & Hijri offset ────────────────────────────────
  Future<void> setRegion(String code) async {
    if (_region == code) return;
    _region = code;
    _today = _todayForRegion();
    _currentMonth = HijriDate(_today.hYear, _today.hMonth, 1);
    _selectedDay = _today;
    _engine.invalidate();
    await _savePrefs();
    notifyListeners();
    await _repo.rescheduleAllNotifications();
    _requestIslamicReschedule();
  }

  Future<void> setHijriManualAdjust(int days) async {
    final clamped = days.clamp(-2, 2);
    if (_hijriManualAdjust == clamped) return;
    _hijriManualAdjust = clamped;
    _today = _todayForRegion();
    _currentMonth = HijriDate(_today.hYear, _today.hMonth, 1);
    _engine.invalidate();
    await _savePrefs();
    notifyListeners();
    await _repo.rescheduleAllNotifications();
    _requestIslamicReschedule();
  }

  /// Region → default day-offset relative to Umm al-Qura.
  /// Sources:
  ///   • Saudi Arabia: Umm al-Qura (official)
  ///   • Morocco: Ministry of Habous and Islamic Affairs (sighting,
  ///     typically +1 day vs UAQ)
  ///   • Algeria: Ministry of Religious Affairs (sighting, typically +1)
  ///   • Tunisia: Ministry of Religious Affairs (calculation, ≈ UAQ)
  ///   • Türkiye: Diyanet (calculation, aligned with UAQ)
  ///   • Indonesia: Kementerian Agama (mostly aligned with UAQ)
  ///   • Global: Umm al-Qura baseline
  static int _regionOffset(String code) {
    switch (code) {
      case 'ma': return 1;
      case 'dz': return 1;
      case 'tn': return 0;
      case 'sa': return 0;
      case 'tr': return 0;
      case 'id': return 0;
      case 'global':
      default:
        return 0;
    }
  }

  /// Today in the user's regional Hijri calendar.
  ///
  /// Convention: `offset = +1` means the regional Hijri month starts
  /// ONE DAY LATER than Umm al-Qura. Resolution is delegated to the
  /// Hijri kernel so the offset application is identical to every
  /// other Greg→Hijri conversion in the app.
  HijriDate _todayForRegion() =>
      kernel.hijriFromGreg(DateTime.now(), hijriDayOffset);

  void setViewMode(CalendarViewMode mode) {
    _viewMode = mode;
    _savePrefs();
    notifyListeners();
  }

  // ── Event CRUD ────────────────────────────────────────────
  Future<void> addEvent(AppEvent event) async {
    await _repo.add(event);
    _engine.invalidate();
    notifyListeners();
  }

  Future<void> updateEvent(AppEvent event) async {
    await _repo.update(event);
    _engine.invalidate();
    notifyListeners();
  }

  Future<void> deleteEvent(String id) async {
    await _repo.delete(id);
    _engine.invalidate();
    notifyListeners();
  }

  Future<void> toggleEvent(String id, bool enabled) async {
    await _repo.toggle(id, enabled);
    _engine.invalidate();
    notifyListeners();
  }

  Future<void> deleteAllEvents() async {
    await _repo.deleteAll();
    _engine.invalidate();
    notifyListeners();
  }

  // ── Event queries ─────────────────────────────────────────
  List<AppEvent> getEventsForDay(int day, int month, int year) {
    try {
      final greg = hijriToGregorian(year, month, day);
      final from = DateTime(greg.year, greg.month, greg.day);
      final to   = DateTime(greg.year, greg.month, greg.day, 23, 59, 59);

      // Get user events via engine
      final instances = _engine.getInstances(_repo.getCached(), from, to);

      // Get Islamic events
      final islamicInstances = _getIslamicEventsForDay(day, month, year);

      final all = <AppEvent>[
        ...instances.map((i) => i.event),
        ...islamicInstances,
      ];

      // Deduplicate by id
      final seen = <String>{};
      return all.where((e) => seen.add(e.id)).toList();
    } catch (e) {
      AppLogger.error('getEventsForDay failed', error: e);
      return [];
    }
  }

  List<AppEvent> getEventsForSelectedDay() {
    final s = _selectedDay;
    if (s == null) return [];
    return getEventsForDay(s.hDay, s.hMonth, s.hYear);
  }

  /// Public, read-only access to the Islamic-events-for-a-day
  /// resolver — used by the home-screen "Islamic Day" widget layer.
  /// A thin pass-through to the existing private logic: no new
  /// behaviour, and no duplication of the matching rules.
  List<AppEvent> islamicEventsForDay(int day, int month, int year) =>
      _getIslamicEventsForDay(day, month, year);

  /// Agenda: returns date → events map for next [days] days
  List<MapEntry<HijriDate, List<AppEvent>>> getAgendaEvents({int days = 60}) {
    return getAgendaEventsRange(pastDays: 0, futureDays: days);
  }

  /// Agenda — bidirectional range query.
  ///
  /// Walks Gregorian dates from `today - pastDays` (inclusive) to
  /// `today + futureDays - 1` (inclusive) and returns a chronological
  /// list of (HijriDate → events) entries for each day that has at
  /// least one event. Powers the agenda's pull-to-load-past + button
  /// load-more-future history navigation.
  List<MapEntry<HijriDate, List<AppEvent>>> getAgendaEventsRange({
    int pastDays = 0,
    int futureDays = 60,
  }) {
    final result = <MapEntry<HijriDate, List<AppEvent>>>[];
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: pastDays));
    final total = pastDays + futureDays;
    for (int i = 0; i < total; i++) {
      final greg = start.add(Duration(days: i));
      try {
        // Region-aware conversion via the kernel: this is what
        // makes today's Hijri tuple line up with `p.today`. Skipping
        // the offset here (the historical bug) was the root cause
        // of the duplicate-today and empty-today agenda regressions.
        final h = kernel.hijriFromGreg(greg, hijriDayOffset);
        final evs = getEventsForDay(h.hDay, h.hMonth, h.hYear);
        if (evs.isNotEmpty) result.add(MapEntry(h, evs));
      } catch (_) {}
    }
    return result;
  }

  // ── Islamic events ────────────────────────────────────────
  /// Resolves which Islamic-virtue events should be DISPLAYED on
  /// a given Hijri day inside the calendar/agenda. Uses the cfg's
  /// "actual occasion" date (Friday for Jumu'ah, Monday/Thursday for
  /// the fasting, 13/14/15 for Ayyam al-Bid, 17/19/21 for Hijama, …)
  /// — not the reminder day, which fires earlier per spec.
  ///
  /// The notification scheduler in [_scheduleIslamicNotifications]
  /// deliberately stays on [IslamicEventConfig.matchesDay] so reminder
  /// behaviour is unchanged.
  List<AppEvent> _getIslamicEventsForDay(int day, int month, int year) {
    final result = <AppEvent>[];
    DateTime greg;
    try {
      greg = hijriToGregorian(year, month, day);
    } catch (_) {
      greg = DateTime.now();
    }
    for (final cfg in IslamicEventsData.events) {
      if (_islamicEventsEnabled[cfg.id] != true) continue;
      if (!cfg.matchesDisplayDay(
          hijriDay: day, hijriMonth: month, greg: greg)) {
        continue;
      }
      result.add(_islamicConfigToEvent(cfg, day, month, year, greg));
    }
    return result;
  }

  /// Daily-adhkar ids (morning / evening / sleep). The monthly view
  /// hides these to keep the grid uncluttered, but they still appear
  /// in the Agenda view and continue to fire notifications.
  static const List<String> _dailyAdhkarIdPrefixes = [
    'adhkar_sabah',
    'adhkar_masaa',
    'adhkar_nawm',
  ];

  /// True when [eventId] belongs to one of the always-on daily adhkar
  /// (id is generated as `<prefix>_<year>_<month>_<day>`).
  bool isDailyAdhkar(String eventId) =>
      _dailyAdhkarIdPrefixes.any((p) => eventId.startsWith(p));

  AppEvent _islamicConfigToEvent(
      IslamicEventConfig cfg, int day, int month, int year, DateTime greg) {
    final now = DateTime.now();
    final time = islamicEventTime(cfg.id);
    final start = DateTime(
        greg.year, greg.month, greg.day, time.hour, time.minute);
    final end = start.add(const Duration(hours: 1));
    return AppEvent(
      id: '${cfg.id}_${year}_${month}_$day',
      titles: cfg.names,
      descriptions: cfg.description,
      startDate: start,
      endDate: end,
      isAllDay: false,
      type: EventType.islamic,
      color: cfg.color,
      emoji: cfg.emoji,
      category: 'religious',
      isIslamic: true,
      isEnabled: true,
      hijriDay: day, hijriMonth: month, hijriYear: year,
      createdAt: now, updatedAt: now,
    );
  }

  /// Per-event configurable trigger time (defaults to the cfg's
  /// `defaultHour:defaultMinute`).
  TimeOfDay islamicEventTime(String id) {
    final stored = _islamicEventTimes[id];
    if (stored != null) return stored;
    final cfg = IslamicEventsData.events
        .firstWhere((e) => e.id == id, orElse: () => IslamicEventsData.events.first);
    return TimeOfDay(hour: cfg.defaultHour, minute: cfg.defaultMinute);
  }

  Future<void> setIslamicEventTime(String id, TimeOfDay t) async {
    _islamicEventTimes[id] = t;
    await _savePrefs();
    notifyListeners();
    _requestIslamicReschedule();
  }

  // ── Zakat dates ─────────────────────────────────────────
  DateTime? get zakatDueDate => _zakatDueDate;
  DateTime? get zakatReminder1 => _zakatReminder1;
  DateTime? get zakatReminder2 => _zakatReminder2;

  Future<void> setZakatDueDate(DateTime? value) async {
    _zakatDueDate = value;
    await _savePrefs();
    notifyListeners();
    _requestIslamicReschedule();
  }

  Future<void> setZakatReminder1(DateTime? value) async {
    _zakatReminder1 = value;
    await _savePrefs();
    notifyListeners();
    _requestIslamicReschedule();
  }

  Future<void> setZakatReminder2(DateTime? value) async {
    _zakatReminder2 = value;
    await _savePrefs();
    notifyListeners();
    _requestIslamicReschedule();
  }

  void toggleIslamicEvent(String id, bool value) {
    _islamicEventsEnabled[id] = value;
    _savePrefs();
    notifyListeners();
    _requestIslamicReschedule();
  }

  void toggleAllIslamicEvents(bool value) {
    for (final k in _islamicEventsEnabled.keys) {
      _islamicEventsEnabled[k] = value;
    }
    _savePrefs();
    notifyListeners();
    _requestIslamicReschedule();
  }

  /// Re-builds the next 30 days of Islamic-event reminders from
  /// scratch. Called on app start, when the user toggles an event,
  /// changes a per-event time, switches region, or changes locale.
  Future<void> _scheduleIslamicNotifications() async {
    try {
      await _notifs.cancelIslamicReminders();
      final now = DateTime.now();
      for (int dayOffset = 0; dayOffset < 30; dayOffset++) {
        final greg = DateTime(now.year, now.month, now.day)
            .add(Duration(days: dayOffset));
        // Hijri date for this Greg date in the user's region —
        // delegated to the kernel so the reminder window and the
        // calendar/agenda use the exact same Greg↔Hijri mapping.
        final hShifted = kernel.hijriFromGreg(greg, hijriDayOffset);
        for (final cfg in IslamicEventsData.events) {
          if (_islamicEventsEnabled[cfg.id] != true) continue;
          if (cfg.isZakat) continue; // handled separately below
          if (!cfg.matchesDay(
            hijriDay: hShifted.hDay,
            hijriMonth: hShifted.hMonth,
            greg: greg,
          )) {
            continue;
          }
          final t = islamicEventTime(cfg.id);
          final fireAt =
              DateTime(greg.year, greg.month, greg.day, t.hour, t.minute);
          if (!fireAt.isAfter(now)) continue;
          final body =
              '${cfg.desc(_locale)}\n\n${cfg.virt(_locale)}';
          await _notifs.scheduleIslamicReminder(
            eventId: cfg.id,
            date: greg,
            title: '${cfg.emoji}  ${cfg.name(_locale)}',
            body: body,
            scheduledDate: fireAt,
          );
        }
      }
      await _scheduleZakatNotifications();
    } catch (e, stack) {
      AppLogger.error('_scheduleIslamicNotifications failed',
          error: e, stack: stack);
    }
  }

  /// Schedules the three zakat notifications (due date + 2 reminders).
  /// Each fires only if it's still in the future and the zakat event
  /// is enabled.
  Future<void> _scheduleZakatNotifications() async {
    if (_islamicEventsEnabled['zakat'] != true) return;
    final cfg = IslamicEventsData.events
        .firstWhere((e) => e.id == 'zakat', orElse: () => IslamicEventsData.events.first);
    final now = DateTime.now();
    final body = '${cfg.desc(_locale)}\n\n${cfg.virt(_locale)}';

    Future<void> scheduleOne(DateTime? when, String suffix) async {
      if (when == null) return;
      if (!when.isAfter(now)) return;
      // Far-future scheduling is fine — the OS keeps the alarm.
      await _notifs.scheduleIslamicReminder(
        eventId: 'zakat_$suffix',
        date: when,
        title: '${cfg.emoji}  ${cfg.name(_locale)}',
        body: body,
        scheduledDate: when,
      );
    }

    await scheduleOne(_zakatDueDate, 'due');
    await scheduleOne(_zakatReminder1, 'r1');
    await scheduleOne(_zakatReminder2, 'r2');
  }

  // ── Search ────────────────────────────────────────────────
  List<AppEvent> search(String query) => _repo.search(query);

  // ── Settings ──────────────────────────────────────────────
  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _savePrefs();
    notifyListeners();
  }

  void setLocale(String loc) {
    _locale = loc;
    _savePrefs();
    notifyListeners();
  }

  // ── Font scale ──────────────────────────────────────────
  double get fontScale => _fontScale;

  /// Picker choices: 0.85 / 1.0 / 1.15 / 1.30 (S / M / L / XL).
  /// Applied via a MediaQuery wrapper in main.dart so it scales the
  /// entire app's text uniformly.
  void setFontScale(double scale) {
    final clamped = scale.clamp(0.7, 1.5);
    if ((clamped - _fontScale).abs() < 0.001) return;
    _fontScale = clamped;
    _savePrefs();
    notifyListeners();
  }

  // ── Calendar density ────────────────────────────────────
  CalendarDensity get calendarDensity => _calendarDensity;

  void setCalendarDensity(CalendarDensity d) {
    if (_calendarDensity == d) return;
    _calendarDensity = d;
    _savePrefs();
    notifyListeners();
  }

  // ── Font family ─────────────────────────────────────────
  String get fontFamily => _fontFamily;

  /// Three fonts for Arabic (amiri / cairo / tajawal) and two for
  /// non-Arabic (roboto / merriweather). The values align with the
  /// `google_fonts` package's API names.
  List<String> get availableFonts =>
      _locale == 'ar'
          ? const ['amiri', 'cairo', 'tajawal']
          : const ['roboto', 'merriweather'];

  void setFontFamily(String f) {
    if (_fontFamily == f) return;
    _fontFamily = f;
    _savePrefs();
    notifyListeners();
  }

  // ── Accent / theme color ─────────────────────────────────
  int get accentIndex => _accentIndex;

  /// Selected swatch from [kAccentPalette]. Drops through to
  /// [AccentBus] which is what `AppColors.green` / `greenPale` read,
  /// and the [MaterialApp]'s ThemeData getters re-evaluate next
  /// frame. The whole tree restyles after [notifyListeners].
  void setAccent(int idx) {
    if (idx < 0 || idx >= kAccentPalette.length) return;
    if (_accentIndex == idx) return;
    _accentIndex = idx;
    AccentBus.set(idx);
    _savePrefs();
    notifyListeners();
  }

  // ── Notification settings ────────────────────────────────
  Future<void> updateNotificationSettings(
    NotificationSettings Function(NotificationSettings) updater, {
    bool previewSound = false,
  }) async {
    final next = updater(_notificationSettings);
    _notificationSettings = next;
    await _notifs.applySettings(next);
    notifyListeners();
    // Re-apply scheduling whenever the user changes notification behavior.
    await _repo.rescheduleAllNotifications();
    if (previewSound) {
      await _notifs.previewSound();
    }
  }

  // ── Hijri helpers ─────────────────────────────────────────
  int getDaysInMonth(int year, int month) => HijriDate.daysInMonth(year, month);

  /// First weekday of a Hijri month, in the user's regional
  /// calendar. Routed through the kernel.
  int getFirstWeekdayOfMonth(int year, int month) =>
      kernel.gregFromHijri(HijriDate(year, month, 1), hijriDayOffset).weekday;

  /// Hijri → Gregorian, applying the region offset. Thin wrapper
  /// around [kernel.gregFromHijri] kept on the provider for ergonomic
  /// reasons — every screen already has `p` in scope.
  DateTime hijriToGregorian(int year, int month, int day) =>
      kernel.gregFromHijri(HijriDate(year, month, day), hijriDayOffset);

  /// Gregorian → Hijri, applying the region offset (inverse of
  /// [hijriToGregorian]). Routed through the kernel.
  HijriDate gregorianToHijri(DateTime g) =>
      kernel.hijriFromGreg(g, hijriDayOffset);

  bool isToday(int day, int month, int year) =>
      day == _today.hDay && month == _today.hMonth && year == _today.hYear;
  bool isSelected(int day, int month, int year) {
    final s = _selectedDay;
    if (s == null) return false;
    return day == s.hDay && month == s.hMonth && year == s.hYear;
  }
  bool isAyyamAlBid(int day) => day == 13 || day == 14 || day == 15;
  bool isRamadan(int month) => month == 9;

  // ── Localization ──────────────────────────────────────────
  /// Hijri month name for the chosen UI locale.
  ///
  /// Thin delegation to the canonical source of truth in
  /// [kHijriMonths] (lib/data/hijri_months.dart). Do NOT reintroduce
  /// month-name arrays anywhere else — the order MUST come from
  /// [HijriMonth.index] and never from string sorting.
  String getHijriMonthName(int month, String loc) =>
      hijriMonthName(month, loc);

  String label(String key) {
    final map = <String, Map<String, String>>{
      'calendar':            {'ar':'التقويم','fr':'Calendrier','en':'Calendar','es':'Calendario'},
      'events':              {'ar':'الأحداث','fr':'Événements','en':'Events','es':'Eventos'},
      'notifications':       {'ar':'تنبيهات','fr':'Alertes','en':'Alerts','es':'Alertas'},
      'settings':            {'ar':'إعدادات','fr':'Paramètres','en':'Settings','es':'Ajustes'},
      'add_event':           {'ar':'حدث جديد','fr':'Nouvel événement','en':'New Event','es':'Nuevo evento'},
      'save':                {'ar':'حفظ','fr':'Enregistrer','en':'Save','es':'Guardar'},
      'cancel':              {'ar':'إلغاء','fr':'Annuler','en':'Cancel','es':'Cancelar'},
      'event_title':         {'ar':'عنوان الحدث','fr':'Titre','en':'Title','es':'Título'},
      'description':         {'ar':'الوصف','fr':'Description','en':'Description','es':'Descripción'},
      'hijri_date':          {'ar':'التاريخ الهجري','fr':'Date hégirien','en':'Hijri Date','es':'Fecha Hijri'},
      'time':                {'ar':'الوقت','fr':'Heure','en':'Time','es':'Hora'},
      'color':               {'ar':'اللون','fr':'Couleur','en':'Color','es':'Color'},
      'reminder':            {'ar':'التذكير','fr':'Rappel','en':'Reminder','es':'Recordatorio'},
      'islamic_events_bank': {'ar':'بنك الأحداث الإسلامية','fr':'Banque islamique','en':'Islamic Events','es':'Eventos Islámicos'},
      'activate_all':        {'ar':'تفعيل الكل دفعة واحدة','fr':'Tout activer','en':'Activate all','es':'Activar todo'},
      'today':               {'ar':'اليوم','fr':"Aujourd'hui",'en':'Today','es':'Hoy'},
      'theme':               {'ar':'المظهر','fr':'Thème','en':'Theme','es':'Tema'},
      'dark':                {'ar':'داكن','fr':'Sombre','en':'Dark','es':'Oscuro'},
      'light':               {'ar':'فاتح','fr':'Clair','en':'Light','es':'Claro'},
      'language':            {'ar':'اللغة','fr':'Langue','en':'Language','es':'Idioma'},
      'monthly':             {'ar':'شهري','fr':'Mensuel','en':'Monthly','es':'Mensual'},
      'weekly':              {'ar':'أسبوعي','fr':'Hebdomadaire','en':'Weekly','es':'Semanal'},
      'agenda':              {'ar':'أجندة','fr':'Agenda','en':'Agenda','es':'Agenda'},
      'annual':              {'ar':'سنوي','fr':'Annuel','en':'Annual','es':'Anual'},
      'islamic':             {'ar':'إسلامي','fr':'Islamique','en':'Islamic','es':'Islámico'},
      'personal':            {'ar':'شخصي','fr':'Personnel','en':'Personal','es':'Personal'},
      'all_day':             {'ar':'طوال اليوم','fr':'Toute la journée','en':'All day','es':'Todo el día'},
      'no_events':           {'ar':'لا توجد أحداث','fr':'Aucun événement','en':'No events','es':'Sin eventos'},
      'upcoming':            {'ar':'قريباً','fr':'Bientôt','en':'Upcoming','es':'Próximo'},
      'notification':        {'ar':'الإشعارات','fr':'Notifications','en':'Notifications','es':'Notificaciones'},
      'cloud_sync':          {'ar':'المزامنة السحابية','fr':'Synchro. cloud','en':'Cloud Sync','es':'Sincronización'},
      // Qibla screen — premium compass that points to the Kaaba.
      'qibla':                     {'ar':'القبلة','fr':'Qibla','en':'Qibla','es':'Qibla'},
      'qibla_aligned':             {'ar':'✓ تم التوجيه نحو القبلة','fr':'✓ Direction Qibla correcte','en':'✓ Correct Qibla direction','es':'✓ Dirección Qibla correcta'},
      'qibla_to_makkah':           {'ar':'إلى مكة','fr':'vers La Mecque','en':'to Makkah','es':'a La Meca'},
      'qibla_angle':               {'ar':'اتجاه القبلة','fr':'Angle Qibla','en':'Qibla angle','es':'Ángulo Qibla'},
      'qibla_accuracy_high':       {'ar':'دقة ممتازة','fr':'Précision excellente','en':'Excellent accuracy','es':'Excelente precisión'},
      'qibla_accuracy_medium':     {'ar':'دقة متوسطة','fr':'Précision moyenne','en':'Medium accuracy','es':'Precisión media'},
      'qibla_accuracy_low':        {'ar':'دقة ضعيفة','fr':'Faible précision','en':'Low accuracy','es':'Baja precisión'},
      'qibla_calibrate':           {'ar':'حرّك الهاتف على شكل الرقم 8 لتحسين دقة البوصلة','fr':'Bougez le téléphone en forme de 8 pour améliorer la boussole','en':'Move your phone in a figure-8 motion to improve compass accuracy','es':'Mueve el teléfono en forma de 8 para mejorar la brújula'},
      'qibla_calibrate_title':     {'ar':'معايرة البوصلة','fr':'Calibration de la boussole','en':'Compass calibration','es':'Calibración de la brújula'},
      'qibla_dismiss':             {'ar':'إغلاق','fr':'Fermer','en':'Dismiss','es':'Cerrar'},
      'qibla_locating':            {'ar':'جاري تحديد الموقع…','fr':'Localisation…','en':'Locating…','es':'Localizando…'},
      'qibla_location_title':      {'ar':'السماح بالوصول إلى الموقع','fr':'Autoriser la localisation','en':'Allow location access','es':'Permitir acceso a la ubicación'},
      'qibla_location_body':       {'ar':'لحساب اتجاه القبلة من مكانك بدقّة، نحتاج إلى موقعك. لا يُشارك مع أيّ خادم.','fr':'Pour calculer la Qibla depuis votre position, nous avons besoin de votre localisation. Aucune donnée n\'est partagée.','en':'To compute the Qibla direction from where you are, we need your location. Nothing is shared with any server.','es':'Para calcular la Qibla desde donde estás, necesitamos tu ubicación. No se comparte con ningún servidor.'},
      'qibla_enable_location':     {'ar':'تفعيل الموقع','fr':'Activer la localisation','en':'Enable location','es':'Activar ubicación'},
      'qibla_open_settings':       {'ar':'فتح إعدادات التطبيق','fr':'Ouvrir les réglages','en':'Open app settings','es':'Abrir ajustes de la app'},
      'qibla_location_disabled':   {'ar':'خدمة الموقع معطّلة على الجهاز','fr':'La localisation est désactivée sur l\'appareil','en':'Location services are off on this device','es':'Los servicios de ubicación están desactivados'},
      'qibla_retry':               {'ar':'إعادة المحاولة','fr':'Réessayer','en':'Retry','es':'Reintentar'},
      'qibla_view_on_map':         {'ar':'عرض على الخريطة','fr':'Voir sur la carte','en':'View on map','es':'Ver en el mapa'},
      'qibla_compass_unavailable': {'ar':'بوصلة الجهاز غير متوفّرة','fr':'Boussole indisponible','en':'Device compass unavailable','es':'Brújula no disponible'},
      'qibla_hint':                {'ar':'للحصول على أفضل دقّة فعّل الموقع، وحرّك الهاتف بشكل ٨ لمعايرة البوصلة.','fr':'Pour une meilleure précision, activez la localisation et bougez le téléphone en 8 pour calibrer la boussole.','en':'For best accuracy enable location and move the phone in a figure-8 to calibrate the compass.','es':'Para mayor precisión activa la ubicación y mueve el teléfono en 8 para calibrar la brújula.'},
      'region':              {'ar':'المنطقة / المذهب','fr':'Région / École','en':'Region','es':'Región'},
      'delete':              {'ar':'حذف','fr':'Supprimer','en':'Delete','es':'Eliminar'},
      'edit':                {'ar':'تعديل','fr':'Modifier','en':'Edit','es':'Editar'},
    };
    return map[key]?[_locale] ?? map[key]?['ar'] ?? key;
  }

  // ── Persistence ───────────────────────────────────────────
  Future<void> _savePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('theme', _themeMode.name);
      await prefs.setString('locale', _locale);
      await prefs.setString('region', _region);
      await prefs.setInt('hijri_manual_adjust', _hijriManualAdjust);
      await prefs.setString('view_mode', _viewMode.name);
      await prefs.setInt('accent_index', _accentIndex);
      await prefs.setDouble('font_scale', _fontScale);
      await prefs.setString('calendar_density', _calendarDensity.name);
      await prefs.setString('font_family', _fontFamily);
      await prefs.setString('islamic_events', jsonEncode(_islamicEventsEnabled));
      await prefs.setString('islamic_event_times', jsonEncode({
        for (final e in _islamicEventTimes.entries)
          e.key: '${e.value.hour}:${e.value.minute}',
      }));
      // Zakat — three nullable DateTimes stored as ISO-8601 strings.
      if (_zakatDueDate != null) {
        await prefs.setString('zakat_due', _zakatDueDate!.toIso8601String());
      } else {
        await prefs.remove('zakat_due');
      }
      if (_zakatReminder1 != null) {
        await prefs.setString('zakat_r1', _zakatReminder1!.toIso8601String());
      } else {
        await prefs.remove('zakat_r1');
      }
      if (_zakatReminder2 != null) {
        await prefs.setString('zakat_r2', _zakatReminder2!.toIso8601String());
      } else {
        await prefs.remove('zakat_r2');
      }
    } catch (e) {
      AppLogger.error('_savePrefs failed', error: e);
    }
  }

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final th = prefs.getString('theme');
      if (th == 'dark') _themeMode = ThemeMode.dark;
      if (th == 'light') _themeMode = ThemeMode.light;
      final loc = prefs.getString('locale');
      if (loc != null) _locale = loc;
      final reg = prefs.getString('region');
      if (reg != null && reg.isNotEmpty) _region = reg;
      final adj = prefs.getInt('hijri_manual_adjust');
      if (adj != null) _hijriManualAdjust = adj.clamp(-2, 2);
      final vm = prefs.getString('view_mode');
      if (vm != null) {
        _viewMode = CalendarViewMode.values.firstWhere(
          (e) => e.name == vm,
          orElse: () => CalendarViewMode.monthly,
        );
      }
      final acc = prefs.getInt('accent_index');
      if (acc != null && acc >= 0 && acc < kAccentPalette.length) {
        _accentIndex = acc;
        AccentBus.set(acc);
      }
      final fs = prefs.getDouble('font_scale');
      if (fs != null) _fontScale = fs.clamp(0.7, 1.5);
      final cd = prefs.getString('calendar_density');
      if (cd != null) {
        _calendarDensity = CalendarDensity.values.firstWhere(
          (e) => e.name == cd,
          orElse: () => CalendarDensity.normal,
        );
      }
      final ff = prefs.getString('font_family');
      if (ff != null && ff.isNotEmpty) {
        _fontFamily = ff;
      }
      final ieJson = prefs.getString('islamic_events');
      if (ieJson != null && ieJson.isNotEmpty) {
        final saved = Map<String, dynamic>.from(jsonDecode(ieJson) as Map);
        for (final k in saved.keys) {
          if (_islamicEventsEnabled.containsKey(k)) {
            _islamicEventsEnabled[k] = saved[k] as bool;
          }
        }
      }
      DateTime? readDate(String key) {
        final s = prefs.getString(key);
        if (s == null || s.isEmpty) return null;
        return DateTime.tryParse(s);
      }
      _zakatDueDate = readDate('zakat_due');
      _zakatReminder1 = readDate('zakat_r1');
      _zakatReminder2 = readDate('zakat_r2');
      final ietJson = prefs.getString('islamic_event_times');
      if (ietJson != null && ietJson.isNotEmpty) {
        final saved = Map<String, dynamic>.from(jsonDecode(ietJson) as Map);
        for (final entry in saved.entries) {
          final raw = entry.value as String;
          final parts = raw.split(':');
          if (parts.length == 2) {
            final h = int.tryParse(parts[0]);
            final m = int.tryParse(parts[1]);
            if (h != null && m != null && h >= 0 && h < 24 && m >= 0 && m < 60) {
              _islamicEventTimes[entry.key] = TimeOfDay(hour: h, minute: m);
            }
          }
        }
      }
    } catch (e) {
      AppLogger.error('_loadPrefs failed', error: e);
    }
  }
}
