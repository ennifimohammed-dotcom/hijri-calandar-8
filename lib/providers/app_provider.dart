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
import '../services/notification_settings_service.dart';
import '../theme.dart';
import '../utils/hijri_utils.dart';

enum CalendarViewMode { monthly, weekly, agenda }

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

  // ── Calendar state ────────────────────────────────────────
  late HijriDate _currentMonth;
  late HijriDate _today;
  HijriDate? _selectedDay;
  CalendarViewMode _viewMode = CalendarViewMode.monthly;
  bool _isLoading = true;

  // ── Settings state ────────────────────────────────────────
  ThemeMode _themeMode = ThemeMode.light;
  String _locale = 'ar';
  Map<String, bool> _islamicEventsEnabled = {};
  NotificationSettings _notificationSettings = const NotificationSettings();

  /// Index into [kAccentPalette] (theme.dart). Default 0 = green.
  /// Drives [AccentBus] which backs `AppColors.green` / `greenPale`.
  int _accentIndex = 0;

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
  String _region = 'global';
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
      await _notifs.scheduleMidnightReschedule();
    } catch (e) {
      debugPrint('AppProvider.init error: $e');
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
  /// ONE DAY LATER than Umm al-Qura. The date the user sees today is
  /// therefore `UAQ.fromGregorian(now − offset)`.
  HijriDate _todayForRegion() {
    final now = DateTime.now();
    final shifted = now.subtract(Duration(days: hijriDayOffset));
    return HijriDate.fromGregorian(shifted);
  }

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
      debugPrint('getEventsForDay error: $e');
      return [];
    }
  }

  List<AppEvent> getEventsForSelectedDay() {
    final s = _selectedDay;
    if (s == null) return [];
    return getEventsForDay(s.hDay, s.hMonth, s.hYear);
  }

  /// Agenda: returns date → events map for next [days] days
  List<MapEntry<HijriDate, List<AppEvent>>> getAgendaEvents({int days = 60}) {
    final result = <MapEntry<HijriDate, List<AppEvent>>>[];
    var greg = DateTime.now();
    for (int i = 0; i < days; i++) {
      try {
        final h = HijriDate.fromGregorian(greg);
        final evs = getEventsForDay(h.hDay, h.hMonth, h.hYear);
        if (evs.isNotEmpty) result.add(MapEntry(h, evs));
      } catch (_) {}
      greg = greg.add(const Duration(days: 1));
    }
    return result;
  }

  // ── Islamic events ────────────────────────────────────────
  List<AppEvent> _getIslamicEventsForDay(int day, int month, int year) {
    final result = <AppEvent>[];
    for (final cfg in IslamicEventsData.events) {
      if (_islamicEventsEnabled[cfg.id] != true) continue;
      bool matches = false;

      if (cfg.isDaily) {
        matches = true;
      } else if (cfg.isWeekly) {
        try {
          final g = hijriToGregorian(year, month, day);
          if (cfg.weekday != null && g.weekday == cfg.weekday) matches = true;
          if (cfg.id == 'sawm_ithnayn_khamis' &&
              (g.weekday == 1 || g.weekday == 4)) matches = true;
        } catch (_) {}
      } else if (cfg.isMonthly) {
        if (cfg.id == 'ayyam_albid' && (day == 13 || day == 14 || day == 15)) matches = true;
        else if (cfg.id == 'hijama' && (day == 17 || day == 19 || day == 21)) matches = true;
        else if (cfg.id != 'ayyam_albid' && cfg.id != 'hijama' && cfg.day == day) matches = true;
      } else {
        if (cfg.day == day && cfg.month == month) matches = true;
      }

      if (matches) result.add(_islamicConfigToEvent(cfg, day, month, year));
    }
    return result;
  }

  AppEvent _islamicConfigToEvent(
      IslamicEventConfig cfg, int day, int month, int year) {
    final now = DateTime.now();
    DateTime greg = now;
    try { greg = hijriToGregorian(year, month, day); } catch (_) {}
    return AppEvent(
      id: '${cfg.id}_${year}_$month',
      titles: cfg.names,
      descriptions: cfg.description,
      startDate: greg,
      endDate: greg,
      isAllDay: true,
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

  void toggleIslamicEvent(String id, bool value) {
    _islamicEventsEnabled[id] = value;
    _savePrefs();
    notifyListeners();
  }

  void toggleAllIslamicEvents(bool value) {
    for (final k in _islamicEventsEnabled.keys) {
      _islamicEventsEnabled[k] = value;
    }
    _savePrefs();
    notifyListeners();
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

  /// First weekday of a Hijri month, in the user's regional calendar.
  /// Applies [hijriDayOffset] so the calendar grid lines up with the
  /// region's actual moon-sighting / calculation practice.
  int getFirstWeekdayOfMonth(int year, int month) {
    final base = HijriDate.hijriToGregorian(year, month, 1);
    return base.add(Duration(days: hijriDayOffset)).weekday;
  }

  /// Hijri → Gregorian, applying the region offset.
  DateTime hijriToGregorian(int year, int month, int day) {
    final base = HijriDate.hijriToGregorian(year, month, day);
    return base.add(Duration(days: hijriDayOffset));
  }

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
      await prefs.setString('islamic_events', jsonEncode(_islamicEventsEnabled));
    } catch (e) {
      debugPrint('_savePrefs error: $e');
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
      final ieJson = prefs.getString('islamic_events');
      if (ieJson != null && ieJson.isNotEmpty) {
        final saved = Map<String, dynamic>.from(jsonDecode(ieJson) as Map);
        for (final k in saved.keys) {
          if (_islamicEventsEnabled.containsKey(k)) {
            _islamicEventsEnabled[k] = saved[k] as bool;
          }
        }
      }
    } catch (e) {
      debugPrint('_loadPrefs error: $e');
    }
  }
}
