import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';
import '../data/hijri_months.dart';
import '../models/event_model.dart';
import '../providers/app_provider.dart';
import '../utils/hijri_utils.dart';
import '../utils/text_format.dart';
import '../theme.dart';

/// Add / Edit Event screen — Time + Recurrence + Notifications input.
///
/// Step 4 of the staged Google-Agenda-style rewrite. Adds the
/// Notifications section bound to the temporary [_EventDraft]:
///   * Per-event notifications enable/disable Switch
///   * Reminder list bound to [EventReminder] objects
///   * Preset picker that adapts to the all-day flag:
///       - timed events  -> relative presets (Reminder.relative)
///       - all-day events -> fixed-time presets (Reminder.fixed)
///   * Reminder list capped at 5 (per docs/event_notifications.md R-N-5)
///   * Conversion of existing reminders when the user toggles all-day
///     (per R-N-3)
///
/// No service or scheduling code. UI only — choices map directly to
/// the [EventReminder] model.
class AddEventScreen extends StatefulWidget {
  final AppEvent? existingEvent;

  /// Optional prefilled start time. Set by callers like the weekly
  /// time-grid that taps an empty cell — the new draft is then
  /// initialized as a 1-hour timed event starting at that instant
  /// (instead of the default 09:00–10:00 today). Ignored when
  /// [existingEvent] is provided.
  final DateTime? initialStart;

  const AddEventScreen({
    super.key,
    this.existingEvent,
    this.initialStart,
  });

  @override
  State<AddEventScreen> createState() => _AddEventScreenState();
}

class _AddEventScreenState extends State<AddEventScreen> {
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();

  /// Color shown on the agenda for this event. Defaults to the first
  /// entry of [_kEventColors].
  Color _color = _kEventColors.first;

  /// Category id (`personal` / `family` / `social` / `work` /
  /// `health` / `religious`). Maps to the [AppEvent.category] field.
  String _category = 'personal';

  /// When `true` the start/end date pickers open the Hijri spinner;
  /// otherwise the standard Gregorian [showDatePicker] is shown.
  bool _useHijriPicker = false;

  late _EventDraft _draft;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingEvent;
    if (existing != null) {
      _titleCtrl.text = existing.title('ar');
      _descCtrl.text = existing.description('ar');
      _color = existing.color;
      if (_kEventColors.every((c) => c.value != _color.value)) {
        // Persisted color may have been a custom one from an older
        // build — snap back to the closest preset to keep the picker
        // selection coherent.
        _color = _kEventColors.first;
      }
      _category = existing.category.isEmpty ? 'personal' : existing.category;
      _draft = _EventDraft.fromExisting(existing);
    } else if (widget.initialStart != null) {
      _draft = _EventDraft.atHour(widget.initialStart!);
    } else {
      _draft = _EventDraft.now();
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  // ── Pickers ─────────────────────────────────────────────────────
  Future<void> _pickStart(String locale) async {
    final picked = await _pickDateMaybeTime(
      initial: _draft.start,
      locale: locale,
    );
    if (picked == null) return;
    setState(() => _draft.setStart(picked));
  }

  Future<void> _pickEnd(String locale) async {
    final picked = await _pickDateMaybeTime(
      initial: _draft.end,
      locale: locale,
    );
    if (picked == null) return;
    setState(() => _draft.setEnd(picked));
  }

  /// Picks a date (Hijri or Gregorian per [_useHijriPicker]). When the
  /// event is timed, an additional time picker is shown afterwards.
  Future<DateTime?> _pickDateMaybeTime({
    required DateTime initial,
    required String locale,
  }) async {
    DateTime? date;
    if (_useHijriPicker) {
      final picked = await _showHijriDatePicker(
        context: context,
        initial: HijriDate.fromGregorian(initial),
        locale: locale,
      );
      if (picked == null) return null;
      date = HijriDate.hijriToGregorian(picked.hYear, picked.hMonth, picked.hDay);
    } else {
      date = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(1970),
        lastDate: DateTime(2200),
      );
    }
    if (date == null) return null;
    if (_draft.isAllDay) {
      return DateTime(date.year, date.month, date.day);
    }
    if (!mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  // ── Save ────────────────────────────────────────────────────────
  Future<void> _save(AppProvider provider, String locale) async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_Tr.titleRequired.value(locale)),
          backgroundColor: AppColors.red,
        ),
      );
      return;
    }
    if (!_draft.isAllDay && _draft.end.isBefore(_draft.start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_Tr.invalidRange.value(locale)),
          backgroundColor: AppColors.red,
        ),
      );
      return;
    }

    // End-exclusive storage for all-day (per docs/event_time_behavior.md):
    // the user picks the inclusive last day, we persist next-day midnight.
    final startStorage = _draft.isAllDay
        ? DateTime(_draft.start.year, _draft.start.month, _draft.start.day)
        : _draft.start;
    final endStorage = _draft.isAllDay
        ? DateTime(_draft.end.year, _draft.end.month, _draft.end.day)
            .add(const Duration(days: 1))
        : _draft.end;

    // Hijri reference for the start date (used by Hijri-aware queries
    // and the Islamic events bank).
    HijriDate? hijri;
    try {
      hijri = HijriDate.fromGregorian(startStorage);
    } catch (_) {}

    final desc = _descCtrl.text.trim();
    final now = DateTime.now();
    final id = widget.existingEvent?.id ?? const Uuid().v4();
    final timeZone = _draft.isAllDay ? null : tz.local.name;

    final event = AppEvent(
      id: id,
      titles: {
        'ar': title,
        'fr': title,
        'en': title,
        'es': title,
      },
      descriptions: {
        'ar': desc,
        'fr': desc,
        'en': desc,
        'es': desc,
      },
      startDate: startStorage,
      endDate: endStorage,
      isAllDay: _draft.isAllDay,
      recurrenceRule: _toRecurrenceRule(_draft.recurrence),
      reminders: _draft.reminders,
      type: EventType.personal,
      color: _color,
      emoji: '',
      category: _category,
      location: '',
      priority: EventPriority.medium,
      isEnabled: true,
      isPrivate: false,
      createdAt: widget.existingEvent?.createdAt ?? now,
      updatedAt: now,
      hijriDay: hijri?.hDay,
      hijriMonth: hijri?.hMonth,
      hijriYear: hijri?.hYear,
      isIslamic: false,
      kind: EventKind.event,
      timeZone: timeZone,
      notificationsEnabled: _draft.notificationsEnabled,
    );

    if (widget.existingEvent != null) {
      await provider.updateEvent(event);
    } else {
      await provider.addEvent(event);
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  RecurrenceRule? _toRecurrenceRule(_RecurrenceChoice c) {
    switch (c) {
      case _RecurrenceChoice.none:
        return null;
      case _RecurrenceChoice.daily:
        return const RecurrenceRule(frequency: RecurrenceFrequency.daily);
      case _RecurrenceChoice.weekly:
        return const RecurrenceRule(frequency: RecurrenceFrequency.weekly);
      case _RecurrenceChoice.monthly:
        return const RecurrenceRule(frequency: RecurrenceFrequency.monthly);
      case _RecurrenceChoice.yearly:
        return const RecurrenceRule(frequency: RecurrenceFrequency.yearly);
    }
  }

  bool get _isEditingRecurringEvent =>
      widget.existingEvent?.recurrenceRule != null;

  // ── Recurrence sheets ───────────────────────────────────────────
  Future<void> _openRecurrenceSheet(String locale) async {
    final picked = await showModalBottomSheet<_RecurrenceChoice>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          _RecurrenceSheet(selected: _draft.recurrence, locale: locale),
    );
    if (picked == null) return;
    setState(() => _draft.setRecurrence(picked));
  }

  Future<void> _openEditScopeSheet(String locale) async {
    final picked = await showModalBottomSheet<_EditScope>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          _EditScopeSheet(selected: _draft.editScope, locale: locale),
    );
    if (picked == null) return;
    setState(() => _draft.setEditScope(picked));
  }

  // ── Notifications sheet ─────────────────────────────────────────
  Future<void> _openAddReminderSheet(String locale) async {
    if (!_draft.canAddReminder) return;
    final picked = await showModalBottomSheet<EventReminder>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddReminderSheet(
        isAllDay: _draft.isAllDay,
        locale: locale,
        idGenerator: _EventDraft._newReminderId,
      ),
    );
    if (picked == null) return;
    setState(() => _draft.addReminder(picked));
  }

  // ── Build ───────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final locale = provider.locale;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: _buildAppBar(locale),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TitleField(controller: _titleCtrl, locale: locale),
            const SizedBox(height: 12),
            _DescriptionField(controller: _descCtrl, locale: locale),
            const SizedBox(height: 12),
            _TimeSection(
              draft: _draft,
              locale: locale,
              useHijriPicker: _useHijriPicker,
              onAllDayChanged: (v) =>
                  setState(() => _draft.toggleAllDay(v)),
              onCalendarSystemChanged: (v) =>
                  setState(() => _useHijriPicker = v),
              onStartTap: () => _pickStart(locale),
              onEndTap: () => _pickEnd(locale),
            ),
            const SizedBox(height: 12),
            _RecurrenceSection(
              draft: _draft,
              locale: locale,
              showEditScope: _isEditingRecurringEvent,
              onRecurrenceTap: () => _openRecurrenceSheet(locale),
              onEditScopeTap: () => _openEditScopeSheet(locale),
            ),
            const SizedBox(height: 12),
            _CategoryPicker(
              selected: _category,
              locale: locale,
              onSelected: (c) => setState(() => _category = c),
            ),
            const SizedBox(height: 12),
            _ColorPicker(
              selected: _color,
              locale: locale,
              onSelected: (c) => setState(() => _color = c),
            ),
            const SizedBox(height: 12),
            _NotificationsSection(
              draft: _draft,
              locale: locale,
              onEnabledChanged: (v) =>
                  setState(() => _draft.setNotificationsEnabled(v)),
              onAddReminder: () => _openAddReminderSheet(locale),
              onRemoveReminder: (id) =>
                  setState(() => _draft.removeReminder(id)),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _SaveBar(
        locale: locale,
        onPressed: () => _save(provider, locale),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(String locale) {
    return AppBar(
      backgroundColor: AppColors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded, color: AppColors.navy),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        widget.existingEvent != null
            ? _Tr.editEvent.value(locale)
            : _Tr.addEvent.value(locale),
        style: appFont(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: AppColors.navy,
        ),
      ),
      centerTitle: true,
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, color: AppColors.border),
      ),
    );
  }
}

// ─── Draft ──────────────────────────────────────────────────────────
//
// Lightweight in-memory state for the Time section. Subsequent steps
// will extend this object with title, kind, recurrence, reminders, etc.

/// User-visible recurrence choice. Maps to a single
/// [RecurrenceFrequency] (or `null` for None). Interval, byWeekday,
/// count, until, and other rule fields are out of scope for this step.
enum _RecurrenceChoice { none, daily, weekly, monthly, yearly }

extension _RecurrenceChoiceX on _RecurrenceChoice {
  String label(String locale) {
    switch (this) {
      case _RecurrenceChoice.none:
        return _Tr.repeatNone.value(locale);
      case _RecurrenceChoice.daily:
        return _Tr.repeatDaily.value(locale);
      case _RecurrenceChoice.weekly:
        return _Tr.repeatWeekly.value(locale);
      case _RecurrenceChoice.monthly:
        return _Tr.repeatMonthly.value(locale);
      case _RecurrenceChoice.yearly:
        return _Tr.repeatYearly.value(locale);
    }
  }
}

/// Editing scope picked when modifying an existing recurring event.
/// The actual SPLIT / EXDATE / OVERRIDE logic lives in a later step.
enum _EditScope { thisOccurrence, thisAndFollowing, allOccurrences }

extension _EditScopeX on _EditScope {
  String label(String locale) {
    switch (this) {
      case _EditScope.thisOccurrence:
        return _Tr.scopeThis.value(locale);
      case _EditScope.thisAndFollowing:
        return _Tr.scopeThisAndFollowing.value(locale);
      case _EditScope.allOccurrences:
        return _Tr.scopeAll.value(locale);
    }
  }
}

class _EventDraft {
  bool isAllDay;
  DateTime start;

  /// For all-day events this is the **inclusive** last day shown to the
  /// user. The exclusive-end conversion required by the model spec
  /// happens when the draft is serialized to an [AppEvent], which is
  /// the responsibility of a later step.
  DateTime end;

  _RecurrenceChoice recurrence;
  _EditScope editScope;

  /// Per-event notifications switch. Independent of the global
  /// notifications setting and of [AppEvent.isEnabled]. See
  /// docs/event_notifications.md §10.
  bool notificationsEnabled;

  /// Reminders attached to this event. Capped at 5 (R-N-5). Each entry
  /// is a real [EventReminder]; UI choices map 1:1 to the model.
  List<EventReminder> reminders;

  _EventDraft({
    required this.isAllDay,
    required this.start,
    required this.end,
    this.recurrence = _RecurrenceChoice.none,
    this.editScope = _EditScope.thisOccurrence,
    this.notificationsEnabled = true,
    List<EventReminder>? reminders,
  }) : reminders = reminders ?? <EventReminder>[];

  factory _EventDraft.now() {
    final now = DateTime.now();
    return _EventDraft(
      isAllDay: false,
      start: DateTime(now.year, now.month, now.day, 9, 0),
      end: DateTime(now.year, now.month, now.day, 10, 0),
      reminders: [
        // Default for a freshly created timed event:
        // a single 30-minutes-before reminder (notifications spec §4.1).
        EventReminder.relative(
          id: _newReminderId(),
          minutesBefore: 30,
        ),
      ],
    );
  }

  /// Hydrates a draft from an existing [AppEvent]. Restores the
  /// inclusive-end date for all-day events (see
  /// docs/event_time_behavior.md §1.4).
  /// Used by the weekly time-grid: tap an empty cell at hour H on
  /// day D and the new event opens already pinned to that slot,
  /// with a 1-hour duration and the standard 30-min reminder.
  factory _EventDraft.atHour(DateTime start) {
    final s = DateTime(
        start.year, start.month, start.day, start.hour, start.minute);
    final e = s.add(const Duration(hours: 1));
    return _EventDraft(
      isAllDay: false,
      start: s,
      end: e,
      reminders: [
        EventReminder.relative(id: _newReminderId(), minutesBefore: 30),
      ],
    );
  }

  factory _EventDraft.fromExisting(AppEvent e) {
    final allDay = e.isAllDay;
    final start = allDay
        ? DateTime(e.startDate.year, e.startDate.month, e.startDate.day)
        : e.startDate;
    final end = allDay
        ? e.inclusiveEndDate
        : e.endDate;
    return _EventDraft(
      isAllDay: allDay,
      start: start,
      end: end,
      recurrence: _recurrenceFromRule(e.recurrenceRule),
      notificationsEnabled: e.notificationsEnabled,
      reminders: List.of(e.reminders),
    );
  }

  static _RecurrenceChoice _recurrenceFromRule(RecurrenceRule? rule) {
    if (rule == null) return _RecurrenceChoice.none;
    switch (rule.frequency) {
      case RecurrenceFrequency.daily:
        return _RecurrenceChoice.daily;
      case RecurrenceFrequency.weekly:
        return _RecurrenceChoice.weekly;
      case RecurrenceFrequency.monthly:
        return _RecurrenceChoice.monthly;
      case RecurrenceFrequency.yearly:
        return _RecurrenceChoice.yearly;
    }
  }

  static int _reminderSeq = 0;
  static String _newReminderId() {
    _reminderSeq++;
    return 'r_${DateTime.now().microsecondsSinceEpoch}_$_reminderSeq';
  }

  void setRecurrence(_RecurrenceChoice value) {
    recurrence = value;
  }

  void setEditScope(_EditScope value) {
    editScope = value;
  }

  void setNotificationsEnabled(bool value) {
    notificationsEnabled = value;
  }

  bool get canAddReminder => reminders.length < 5;

  void addReminder(EventReminder reminder) {
    if (!canAddReminder) return;
    reminders.add(reminder);
  }

  void removeReminder(String id) {
    reminders.removeWhere((r) => r.id == id);
  }

  void toggleAllDay(bool value) {
    if (value == isAllDay) return;
    if (value) {
      // timed → all-day: drop clock fields, end defaults to start.
      final s = DateTime(start.year, start.month, start.day);
      isAllDay = true;
      start = s;
      end = s;
      _convertRemindersForAllDay();
    } else {
      // all-day → timed: assign default times (09:00 / 10:00) on the
      // existing date.
      final s = DateTime(start.year, start.month, start.day, 9, 0);
      isAllDay = false;
      start = s;
      end = DateTime(s.year, s.month, s.day, 10, 0);
      _convertRemindersForTimed();
    }
  }

  /// docs/event_notifications.md §3 R-N-3 (timed → all-day).
  /// Best-effort mapping; reminders that cannot be expressed as a
  /// fixed-time preset are dropped silently in this UI step.
  void _convertRemindersForAllDay() {
    final converted = <EventReminder>[];
    for (final r in reminders) {
      if (r.kind == ReminderTriggerKind.fixedTime) {
        converted.add(r);
        continue;
      }
      final m = r.minutesBefore;
      if (m <= 1440) {
        converted.add(EventReminder.fixed(
            id: r.id, daysBefore: 0, hour: 9, minute: 0));
      } else if (m <= 2 * 1440) {
        converted.add(EventReminder.fixed(
            id: r.id, daysBefore: 1, hour: 9, minute: 0));
      } else if (m <= 7 * 1440) {
        converted.add(EventReminder.fixed(
            id: r.id, daysBefore: 7, hour: 9, minute: 0));
      }
      // else: drop
    }
    reminders = converted;
  }

  /// docs/event_notifications.md §3 R-N-3 (all-day → timed).
  /// Fixed-time reminders are dropped; if nothing remains a single
  /// default 30-min relative reminder is inserted.
  void _convertRemindersForTimed() {
    reminders = reminders
        .where((r) => r.kind == ReminderTriggerKind.relative)
        .toList();
    if (reminders.isEmpty) {
      reminders = [
        EventReminder.relative(id: _newReminderId(), minutesBefore: 30),
      ];
    }
  }

  void setStart(DateTime value) {
    start = value;
    _enforceOrdering();
  }

  void setEnd(DateTime value) {
    end = value;
    _enforceOrdering();
  }

  void _enforceOrdering() {
    if (isAllDay) {
      final endDate = DateTime(end.year, end.month, end.day);
      final startDate = DateTime(start.year, start.month, start.day);
      if (endDate.isBefore(startDate)) end = startDate;
    } else {
      if (end.isBefore(start)) end = start.add(const Duration(hours: 1));
    }
  }
}

// ─── Section widgets ────────────────────────────────────────────────

class _TitleField extends StatelessWidget {
  final TextEditingController controller;
  final String locale;
  const _TitleField({required this.controller, required this.locale});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: TextField(
        controller: controller,
        style: appFont(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.text,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          isDense: true,
          hintText: _Tr.titleHint.value(locale),
          hintStyle: appFont(
            fontSize: 16,
            color: AppColors.text3,
          ),
        ),
      ),
    );
  }
}

// ─── Description ────────────────────────────────────────────────────

class _DescriptionField extends StatelessWidget {
  final TextEditingController controller;
  final String locale;
  const _DescriptionField({required this.controller, required this.locale});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: TextField(
        controller: controller,
        maxLines: 3,
        minLines: 1,
        textInputAction: TextInputAction.newline,
        style: appFont(
          fontSize: 14,
          color: AppColors.text,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          isDense: true,
          icon: const Icon(
            Icons.notes_rounded,
            color: AppColors.text3,
            size: 20,
          ),
          hintText: _Tr.descriptionHint.value(locale),
          hintStyle: appFont(
            fontSize: 14,
            color: AppColors.text3,
          ),
        ),
      ),
    );
  }
}

// ─── Color picker (10 Google-Calendar-style colors) ─────────────────

const List<Color> _kEventColors = <Color>[
  Color(0xFFD50000), // tomato
  Color(0xFFE67C73), // flamingo
  Color(0xFFF4511E), // tangerine
  Color(0xFFF6BF26), // banana
  Color(0xFF33B679), // sage
  Color(0xFF0B8043), // basil
  Color(0xFF039BE5), // peacock
  Color(0xFF3F51B5), // blueberry
  Color(0xFF7986CB), // lavender
  Color(0xFF8E24AA), // grape
];

class _ColorPicker extends StatelessWidget {
  final Color selected;
  final String locale;
  final ValueChanged<Color> onSelected;
  const _ColorPicker({
    required this.selected,
    required this.locale,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.palette_rounded,
                  size: 20, color: AppColors.text3),
              const SizedBox(width: 12),
              Text(
                _Tr.color.value(locale),
                style: appFont(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _kEventColors.map((c) {
              final isSelected = c.value == selected.value;
              return GestureDetector(
                onTap: () => onSelected(c),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: isSelected ? 36 : 30,
                  height: isSelected ? 36 : 30,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: c.withValues(alpha: 0.4),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                  child: isSelected
                      ? const Icon(Icons.check_rounded,
                          color: Colors.white, size: 18)
                      : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ─── Category picker ────────────────────────────────────────────────

const List<(String, String, _Tr)> _kCategories = <(String, String, _Tr)>[
  ('personal', '👤', _Tr.catPersonal),
  ('family', '👨‍👩‍👧', _Tr.catFamily),
  ('social', '🎉', _Tr.catSocial),
  ('work', '💼', _Tr.catWork),
  ('health', '🏥', _Tr.catHealth),
  ('religious', '🕌', _Tr.catReligious),
];

class _CategoryPicker extends StatelessWidget {
  final String selected;
  final String locale;
  final ValueChanged<String> onSelected;
  const _CategoryPicker({
    required this.selected,
    required this.locale,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.label_outline_rounded,
                  size: 20, color: AppColors.text3),
              const SizedBox(width: 12),
              Text(
                _Tr.category.value(locale),
                style: appFont(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kCategories.map((c) {
              final isSelected = c.$1 == selected;
              return GestureDetector(
                onTap: () => onSelected(c.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.green : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: isSelected
                            ? AppColors.green
                            : AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(c.$2, style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 6),
                      Text(
                        c.$3.value(locale),
                        style: appFont(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isSelected
                              ? Colors.white
                              : AppColors.text2,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _TimeSection extends StatelessWidget {
  final _EventDraft draft;
  final String locale;
  final bool useHijriPicker;
  final ValueChanged<bool> onAllDayChanged;
  final ValueChanged<bool> onCalendarSystemChanged;
  final VoidCallback onStartTap;
  final VoidCallback onEndTap;
  const _TimeSection({
    required this.draft,
    required this.locale,
    required this.useHijriPicker,
    required this.onAllDayChanged,
    required this.onCalendarSystemChanged,
    required this.onStartTap,
    required this.onEndTap,
  });

  String _format(DateTime d) {
    if (useHijriPicker) {
      // Hijri rendering — month name from kHijriMonths (canonical),
      // digits forced Western per the global text-format rule.
      final h = HijriDate.fromGregorian(d);
      final hijri = TextFormat.toWesternDigits(
        '${h.hDay} ${hijriMonthName(h.hMonth, locale)} ${h.hYear}',
      );
      if (draft.isAllDay) return hijri;
      String two(int n) => n.toString().padLeft(2, '0');
      return TextFormat.toWesternDigits(
        '$hijri · ${two(d.hour)}:${two(d.minute)}',
      );
    }
    // Gregorian rendering with strict Western digits.
    return TextFormat.toWesternDigits(
      TextFormat.formatEventDateTime(d, locale, allDay: draft.isAllDay),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.greenPale,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.schedule_rounded,
                    size: 18,
                    color: AppColors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _Tr.sectionTime.value(locale),
                    style: appFont(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          // All-day toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _Tr.allDay.value(locale),
                    style: appFont(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: draft.isAllDay,
                  onChanged: onAllDayChanged,
                  activeColor: AppColors.green,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border, indent: 14),
          // Calendar system toggle (Hijri ↔ Gregorian for the date pickers)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _Tr.calendarSystem.value(locale),
                    style: appFont(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                ),
                _CalendarSystemToggle(
                  useHijri: useHijriPicker,
                  locale: locale,
                  onChanged: onCalendarSystemChanged,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border, indent: 14),
          _TimeRow(
            label: _Tr.start.value(locale),
            value: _format(draft.start),
            onTap: onStartTap,
          ),
          const Divider(height: 1, color: AppColors.border, indent: 14),
          _TimeRow(
            label: _Tr.end.value(locale),
            value: _format(draft.end),
            onTap: onEndTap,
            last: true,
          ),
        ],
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  final bool last;
  const _TimeRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, 12, 14, last ? 14 : 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: appFont(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ),
            Text(
              value,
              style: appFont(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.green,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.text3,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecurrenceSection extends StatelessWidget {
  final _EventDraft draft;
  final String locale;
  final bool showEditScope;
  final VoidCallback onRecurrenceTap;
  final VoidCallback onEditScopeTap;
  const _RecurrenceSection({
    required this.draft,
    required this.locale,
    required this.showEditScope,
    required this.onRecurrenceTap,
    required this.onEditScopeTap,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.greenPale,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.repeat_rounded,
                    size: 18,
                    color: AppColors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _Tr.sectionRecurrence.value(locale),
                    style: appFont(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          _PropertyRow(
            label: _Tr.repeats.value(locale),
            value: draft.recurrence.label(locale),
            onTap: onRecurrenceTap,
            last: !showEditScope,
          ),
          if (showEditScope) ...[
            const Divider(height: 1, color: AppColors.border, indent: 14),
            _PropertyRow(
              label: _Tr.editScope.value(locale),
              value: draft.editScope.label(locale),
              onTap: onEditScopeTap,
              last: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _PropertyRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  final bool last;
  const _PropertyRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, 12, 14, last ? 14 : 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: appFont(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: appFont(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.green,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.text3,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecurrenceSheet extends StatelessWidget {
  final _RecurrenceChoice selected;
  final String locale;
  const _RecurrenceSheet({required this.selected, required this.locale});

  @override
  Widget build(BuildContext context) {
    return _OptionsSheet<_RecurrenceChoice>(
      title: _Tr.repeats.value(locale),
      options: _RecurrenceChoice.values,
      selected: selected,
      labelOf: (c) => c.label(locale),
    );
  }
}

class _EditScopeSheet extends StatelessWidget {
  final _EditScope selected;
  final String locale;
  const _EditScopeSheet({required this.selected, required this.locale});

  @override
  Widget build(BuildContext context) {
    return _OptionsSheet<_EditScope>(
      title: _Tr.applyChangesTo.value(locale),
      options: _EditScope.values,
      selected: selected,
      labelOf: (c) => c.label(locale),
    );
  }
}

class _OptionsSheet<T> extends StatelessWidget {
  final String title;
  final List<T> options;
  final T selected;
  final String Function(T) labelOf;
  const _OptionsSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.labelOf,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Row(
              children: [
                Text(
                  title,
                  style: appFont(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          for (final option in options)
            InkWell(
              onTap: () => Navigator.of(context).pop(option),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        labelOf(option),
                        style: appFont(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    if (option == selected)
                      Icon(
                        Icons.check_rounded,
                        color: AppColors.green,
                        size: 20,
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─── Notifications ──────────────────────────────────────────────────

/// Standard relative-reminder presets (timed events).
/// Source: docs/event_notifications.md §4.1.
///
/// Labels are derived from [EventReminder.label] which already
/// supports ar/fr/en/es, so they automatically match the chosen UI
/// locale.
const List<int> _kRelativePresetMinutes = [
  0, 5, 10, 15, 30, 60, 120, 1440, 2880, 10080,
];

/// Standard fixed-time-reminder presets (all-day events).
/// Source: docs/event_notifications.md §4.2.
/// Tuple = (daysBefore, hour, minute). Labels come from
/// [EventReminder.fixed(...).label(locale)].
const List<(int, int, int)> _kFixedPresetSpecs = [
  (0, 9, 0),
  (1, 9, 0),
  (1, 11, 0),
  (1, 17, 0),
  (2, 9, 0),
  (7, 9, 0),
];

// ─── Calendar system toggle (Hijri ↔ Gregorian) ─────────────────────

class _CalendarSystemToggle extends StatelessWidget {
  final bool useHijri;
  final String locale;
  final ValueChanged<bool> onChanged;
  const _CalendarSystemToggle({
    required this.useHijri,
    required this.locale,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(_Tr.gregorian.value(locale), !useHijri, () => onChanged(false)),
          _segment(_Tr.hijri.value(locale), useHijri, () => onChanged(true)),
        ],
      ),
    );
  }

  Widget _segment(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.green : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: appFont(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.text2,
          ),
        ),
      ),
    );
  }
}

// ─── Hijri date picker dialog ───────────────────────────────────────

Future<HijriDate?> _showHijriDatePicker({
  required BuildContext context,
  required HijriDate initial,
  required String locale,
}) {
  return showDialog<HijriDate>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _HijriDatePickerDialog(initial: initial, locale: locale),
  );
}

class _HijriDatePickerDialog extends StatefulWidget {
  final HijriDate initial;
  final String locale;
  const _HijriDatePickerDialog({required this.initial, required this.locale});

  @override
  State<_HijriDatePickerDialog> createState() => _HijriDatePickerDialogState();
}

class _HijriDatePickerDialogState extends State<_HijriDatePickerDialog> {
  late int _year;
  late int _month;
  late int _day;

  @override
  void initState() {
    super.initState();
    _year = widget.initial.hYear;
    _month = widget.initial.hMonth;
    _day = widget.initial.hDay;
  }

  void _setMonth(int m) {
    setState(() {
      // wrap year if month rolls over
      if (m < 1) {
        _month = 12;
        _year -= 1;
      } else if (m > 12) {
        _month = 1;
        _year += 1;
      } else {
        _month = m;
      }
      _day = _day.clamp(1, HijriDate.daysInMonth(_year, _month));
    });
  }

  void _setYear(int y) {
    setState(() {
      _year = y.clamp(1300, 1700);
      _day = _day.clamp(1, HijriDate.daysInMonth(_year, _month));
    });
  }

  void _setDay(int d) {
    final max = HijriDate.daysInMonth(_year, _month);
    setState(() {
      if (d < 1) {
        d = max;
      } else if (d > max) {
        d = 1;
      }
      _day = d;
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = widget.locale;
    return Dialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _Tr.hijriDateTitle.value(loc),
              style: appFont(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Spinner(
                  label: _Tr.hijriDay.value(loc),
                  value: TextFormat.toWesternDigits('$_day'),
                  onUp: () => _setDay(_day + 1),
                  onDown: () => _setDay(_day - 1),
                ),
                _Spinner(
                  label: _Tr.hijriMonth.value(loc),
                  value: hijriMonthName(_month, loc),
                  big: true,
                  onUp: () => _setMonth(_month + 1),
                  onDown: () => _setMonth(_month - 1),
                ),
                _Spinner(
                  label: _Tr.hijriYear.value(loc),
                  value: TextFormat.toWesternDigits('$_year'),
                  onUp: () => _setYear(_year + 1),
                  onDown: () => _setYear(_year - 1),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    _Tr.cancel.value(loc),
                    style: appFont(
                      color: AppColors.text2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.green,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => Navigator.pop(
                    context,
                    HijriDate(_year, _month, _day),
                  ),
                  child: Text(
                    _Tr.ok.value(loc),
                    style: appFont(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  final String label;
  final String value;
  final bool big;
  final VoidCallback onUp;
  final VoidCallback onDown;
  const _Spinner({
    required this.label,
    required this.value,
    required this.onUp,
    required this.onDown,
    this.big = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: appFont(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppColors.text3,
          ),
        ),
        const SizedBox(height: 4),
        IconButton(
          icon: Icon(Icons.keyboard_arrow_up_rounded,
              color: AppColors.green, size: 26),
          onPressed: onUp,
        ),
        SizedBox(
          width: big ? 110 : 60,
          child: Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: appFont(
              fontSize: big ? 16 : 18,
              fontWeight: FontWeight.bold,
              color: AppColors.navy,
            ),
          ),
        ),
        IconButton(
          icon: Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.green, size: 26),
          onPressed: onDown,
        ),
      ],
    );
  }
}

class _NotificationsSection extends StatelessWidget {
  final _EventDraft draft;
  final String locale;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onAddReminder;
  final ValueChanged<String> onRemoveReminder;
  const _NotificationsSection({
    required this.draft,
    required this.locale,
    required this.onEnabledChanged,
    required this.onAddReminder,
    required this.onRemoveReminder,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = draft.notificationsEnabled;
    final canAdd = draft.canAddReminder;
    return _Card(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.greenPale,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.notifications_outlined,
                    size: 18,
                    color: AppColors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _Tr.sectionNotifications.value(locale),
                    style: appFont(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          // Enable / disable
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _Tr.enableNotifications.value(locale),
                    style: appFont(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: enabled,
                  onChanged: onEnabledChanged,
                  activeColor: AppColors.green,
                ),
              ],
            ),
          ),
          if (enabled) ...[
            const Divider(height: 1, color: AppColors.border, indent: 14),
            // Reminder list
            for (final r in draft.reminders) ...[
              _ReminderRow(
                reminder: r,
                locale: locale,
                onRemove: () => onRemoveReminder(r.id),
              ),
              const Divider(height: 1, color: AppColors.border, indent: 14),
            ],
            // Add reminder
            InkWell(
              onTap: canAdd ? onAddReminder : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Row(
                  children: [
                    Icon(
                      Icons.add_alert_outlined,
                      size: 18,
                      color: canAdd ? AppColors.green : AppColors.text3,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        canAdd
                            ? _Tr.addReminder.value(locale)
                            : _Tr.reminderLimit.value(locale),
                        style: appFont(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color:
                              canAdd ? AppColors.green : AppColors.text3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else
            const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _ReminderRow extends StatelessWidget {
  final EventReminder reminder;
  final String locale;
  final VoidCallback onRemove;
  const _ReminderRow({
    required this.reminder,
    required this.locale,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          const Icon(
            Icons.notifications_active_outlined,
            size: 16,
            color: AppColors.gold,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              reminder.label(locale),
              style: appFont(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
          ),
          IconButton(
            tooltip: _Tr.remove.value(locale),
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: AppColors.text3,
            ),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _AddReminderSheet extends StatelessWidget {
  final bool isAllDay;
  final String locale;
  final String Function() idGenerator;
  const _AddReminderSheet({
    required this.isAllDay,
    required this.locale,
    required this.idGenerator,
  });

  @override
  Widget build(BuildContext context) {
    // Each preset is materialized as a real EventReminder. Its label
    // already follows the chosen locale via EventReminder.label(loc).
    final entries = isAllDay
        ? _kFixedPresetSpecs
            .map((p) => EventReminder.fixed(
                  id: idGenerator(),
                  daysBefore: p.$1,
                  hour: p.$2,
                  minute: p.$3,
                ))
            .map((r) => (r, r.label(locale)))
            .toList()
        : _kRelativePresetMinutes
            .map((m) => EventReminder.relative(
                  id: idGenerator(),
                  minutesBefore: m,
                ))
            .map((r) => (r, r.label(locale)))
            .toList();

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Row(
              children: [
                Text(
                  _Tr.addReminder.value(locale),
                  style: appFont(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.greenPale,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isAllDay
                        ? _Tr.allDayPresets.value(locale)
                        : _Tr.timedPresets.value(locale),
                    style: appFont(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.green,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: entries.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: AppColors.border),
              itemBuilder: (_, i) {
                final (reminder, label) = entries[i];
                return InkWell(
                  onTap: () => Navigator.of(context).pop(reminder),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: appFont(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.add_rounded,
                          color: AppColors.green,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SaveBar extends StatelessWidget {
  final String locale;
  final VoidCallback onPressed;
  const _SaveBar({required this.locale, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: const BoxDecoration(
          color: AppColors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.green,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text(
            _Tr.save.value(locale),
            style: appFont(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Shared primitives ──────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const _Card({
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ─── Localization keys ──────────────────────────────────────────────
//
// All user-facing strings in this screen route through _Tr so the UI
// follows the language chosen in app settings (ar / fr / en / es).
// Brand-style date numbers stay Western per the global text-format
// rule (lib/utils/text_format.dart).
enum _Tr {
  addEvent,
  editEvent,
  titleHint,
  descriptionHint,
  sectionTime,
  allDay,
  calendarSystem,
  hijri,
  gregorian,
  hijriDateTitle,
  hijriDay,
  hijriMonth,
  hijriYear,
  ok,
  cancel,
  start,
  end,
  sectionRecurrence,
  repeats,
  editScope,
  applyChangesTo,
  repeatNone,
  repeatDaily,
  repeatWeekly,
  repeatMonthly,
  repeatYearly,
  scopeThis,
  scopeThisAndFollowing,
  scopeAll,
  category,
  catPersonal,
  catFamily,
  catSocial,
  catWork,
  catHealth,
  catReligious,
  color,
  sectionNotifications,
  enableNotifications,
  addReminder,
  reminderLimit,
  remove,
  allDayPresets,
  timedPresets,
  save,
  titleRequired,
  invalidRange,
}

extension _TrX on _Tr {
  String value(String loc) {
    switch (this) {
      case _Tr.addEvent:
        return loc == 'ar' ? 'حدث جديد'
            : loc == 'es' ? 'Nuevo evento'
            : loc == 'en' ? 'New event'
            : 'Nouvel événement';
      case _Tr.editEvent:
        return loc == 'ar' ? 'تعديل الحدث'
            : loc == 'es' ? 'Editar evento'
            : loc == 'en' ? 'Edit event'
            : 'Modifier l\'événement';
      case _Tr.titleHint:
        return loc == 'ar' ? 'عنوان الحدث'
            : loc == 'es' ? 'Título del evento'
            : loc == 'en' ? 'Event title'
            : "Titre de l'événement";
      case _Tr.descriptionHint:
        return loc == 'ar' ? 'وصف الحدث'
            : loc == 'es' ? 'Descripción del evento'
            : loc == 'en' ? 'Event description'
            : "Description de l'événement";
      case _Tr.sectionTime:
        return loc == 'ar' ? 'الوقت'
            : loc == 'es' ? 'Hora'
            : loc == 'en' ? 'Time'
            : 'Heure';
      case _Tr.allDay:
        return loc == 'ar' ? 'طوال اليوم'
            : loc == 'es' ? 'Todo el día'
            : loc == 'en' ? 'All day'
            : 'Toute la journée';
      case _Tr.calendarSystem:
        return loc == 'ar' ? 'نظام التقويم'
            : loc == 'es' ? 'Sistema de calendario'
            : loc == 'en' ? 'Calendar system'
            : 'Système de calendrier';
      case _Tr.hijri:
        return loc == 'ar' ? 'هجري'
            : loc == 'es' ? 'Hijri'
            : loc == 'en' ? 'Hijri'
            : 'Hégirien';
      case _Tr.gregorian:
        return loc == 'ar' ? 'ميلادي'
            : loc == 'es' ? 'Gregoriano'
            : loc == 'en' ? 'Gregorian'
            : 'Grégorien';
      case _Tr.hijriDateTitle:
        return loc == 'ar' ? 'اختر التاريخ الهجري'
            : loc == 'es' ? 'Elige fecha Hijri'
            : loc == 'en' ? 'Pick Hijri date'
            : 'Choisir la date hégirienne';
      case _Tr.hijriDay:
        return loc == 'ar' ? 'اليوم'
            : loc == 'es' ? 'Día'
            : loc == 'en' ? 'Day'
            : 'Jour';
      case _Tr.hijriMonth:
        return loc == 'ar' ? 'الشهر'
            : loc == 'es' ? 'Mes'
            : loc == 'en' ? 'Month'
            : 'Mois';
      case _Tr.hijriYear:
        return loc == 'ar' ? 'السنة'
            : loc == 'es' ? 'Año'
            : loc == 'en' ? 'Year'
            : 'Année';
      case _Tr.ok:
        return loc == 'ar' ? 'موافق'
            : loc == 'es' ? 'Aceptar'
            : loc == 'en' ? 'OK'
            : 'OK';
      case _Tr.cancel:
        return loc == 'ar' ? 'إلغاء'
            : loc == 'es' ? 'Cancelar'
            : loc == 'en' ? 'Cancel'
            : 'Annuler';
      case _Tr.start:
        return loc == 'ar' ? 'البداية'
            : loc == 'es' ? 'Inicio'
            : loc == 'en' ? 'Start'
            : 'Début';
      case _Tr.end:
        return loc == 'ar' ? 'النهاية'
            : loc == 'es' ? 'Fin'
            : loc == 'en' ? 'End'
            : 'Fin';
      case _Tr.sectionRecurrence:
        return loc == 'ar' ? 'التكرار'
            : loc == 'es' ? 'Repetición'
            : loc == 'en' ? 'Recurrence'
            : 'Récurrence';
      case _Tr.repeats:
        return loc == 'ar' ? 'يتكرر'
            : loc == 'es' ? 'Se repite'
            : loc == 'en' ? 'Repeats'
            : 'Se répète';
      case _Tr.editScope:
        return loc == 'ar' ? 'نطاق التعديل'
            : loc == 'es' ? 'Alcance de edición'
            : loc == 'en' ? 'Edit scope'
            : 'Portée de modification';
      case _Tr.applyChangesTo:
        return loc == 'ar' ? 'تطبيق التغييرات على'
            : loc == 'es' ? 'Aplicar cambios a'
            : loc == 'en' ? 'Apply changes to'
            : 'Appliquer les changements à';
      case _Tr.repeatNone:
        return loc == 'ar' ? 'لا يتكرر'
            : loc == 'es' ? 'No se repite'
            : loc == 'en' ? 'Does not repeat'
            : 'Ne se répète pas';
      case _Tr.repeatDaily:
        return loc == 'ar' ? 'يومياً'
            : loc == 'es' ? 'Diario'
            : loc == 'en' ? 'Daily'
            : 'Quotidien';
      case _Tr.repeatWeekly:
        return loc == 'ar' ? 'أسبوعياً'
            : loc == 'es' ? 'Semanal'
            : loc == 'en' ? 'Weekly'
            : 'Hebdomadaire';
      case _Tr.repeatMonthly:
        return loc == 'ar' ? 'شهرياً'
            : loc == 'es' ? 'Mensual'
            : loc == 'en' ? 'Monthly'
            : 'Mensuel';
      case _Tr.repeatYearly:
        return loc == 'ar' ? 'سنوياً'
            : loc == 'es' ? 'Anual'
            : loc == 'en' ? 'Yearly'
            : 'Annuel';
      case _Tr.scopeThis:
        return loc == 'ar' ? 'هذا الحدث فقط'
            : loc == 'es' ? 'Este evento'
            : loc == 'en' ? 'This event'
            : 'Cet événement';
      case _Tr.scopeThisAndFollowing:
        return loc == 'ar' ? 'هذا الحدث وما يليه'
            : loc == 'es' ? 'Este evento y los siguientes'
            : loc == 'en' ? 'This and following events'
            : 'Cet événement et les suivants';
      case _Tr.scopeAll:
        return loc == 'ar' ? 'جميع الأحداث'
            : loc == 'es' ? 'Todos los eventos'
            : loc == 'en' ? 'All events'
            : 'Tous les événements';
      case _Tr.category:
        return loc == 'ar' ? 'الفئة'
            : loc == 'es' ? 'Categoría'
            : loc == 'en' ? 'Category'
            : 'Catégorie';
      case _Tr.catPersonal:
        return loc == 'ar' ? 'شخصي'
            : loc == 'es' ? 'Personal'
            : loc == 'en' ? 'Personal'
            : 'Personnel';
      case _Tr.catFamily:
        return loc == 'ar' ? 'عائلي'
            : loc == 'es' ? 'Familia'
            : loc == 'en' ? 'Family'
            : 'Famille';
      case _Tr.catSocial:
        return loc == 'ar' ? 'اجتماعي'
            : loc == 'es' ? 'Social'
            : loc == 'en' ? 'Social'
            : 'Social';
      case _Tr.catWork:
        return loc == 'ar' ? 'عمل'
            : loc == 'es' ? 'Trabajo'
            : loc == 'en' ? 'Work'
            : 'Travail';
      case _Tr.catHealth:
        return loc == 'ar' ? 'صحة'
            : loc == 'es' ? 'Salud'
            : loc == 'en' ? 'Health'
            : 'Santé';
      case _Tr.catReligious:
        return loc == 'ar' ? 'ديني'
            : loc == 'es' ? 'Religioso'
            : loc == 'en' ? 'Religious'
            : 'Religieux';
      case _Tr.color:
        return loc == 'ar' ? 'اللون'
            : loc == 'es' ? 'Color'
            : loc == 'en' ? 'Color'
            : 'Couleur';
      case _Tr.sectionNotifications:
        return loc == 'ar' ? 'الإشعارات'
            : loc == 'es' ? 'Notificaciones'
            : loc == 'en' ? 'Notifications'
            : 'Notifications';
      case _Tr.enableNotifications:
        return loc == 'ar' ? 'تفعيل الإشعارات'
            : loc == 'es' ? 'Activar notificaciones'
            : loc == 'en' ? 'Enable notifications'
            : 'Activer les notifications';
      case _Tr.addReminder:
        return loc == 'ar' ? 'إضافة تذكير'
            : loc == 'es' ? 'Añadir recordatorio'
            : loc == 'en' ? 'Add reminder'
            : 'Ajouter un rappel';
      case _Tr.reminderLimit:
        return loc == 'ar' ? 'تم بلوغ الحد الأقصى للتذكيرات (5)'
            : loc == 'es' ? 'Límite de recordatorios alcanzado (5)'
            : loc == 'en' ? 'Reminder limit reached (5)'
            : 'Limite de rappels atteinte (5)';
      case _Tr.remove:
        return loc == 'ar' ? 'حذف'
            : loc == 'es' ? 'Eliminar'
            : loc == 'en' ? 'Remove'
            : 'Supprimer';
      case _Tr.allDayPresets:
        return loc == 'ar' ? 'إعدادات لأحداث طوال اليوم'
            : loc == 'es' ? 'Predefinidos de todo el día'
            : loc == 'en' ? 'All-day presets'
            : 'Préréglages "toute la journée"';
      case _Tr.timedPresets:
        return loc == 'ar' ? 'إعدادات لأحداث موقوتة'
            : loc == 'es' ? 'Predefinidos con hora'
            : loc == 'en' ? 'Timed presets'
            : 'Préréglages horaires';
      case _Tr.save:
        return loc == 'ar' ? 'حفظ'
            : loc == 'es' ? 'Guardar'
            : loc == 'en' ? 'Save'
            : 'Enregistrer';
      case _Tr.titleRequired:
        return loc == 'ar' ? 'يرجى إدخال عنوان للحدث'
            : loc == 'es' ? 'Introduce un título'
            : loc == 'en' ? 'Please enter a title'
            : 'Veuillez saisir un titre';
      case _Tr.invalidRange:
        return loc == 'ar' ? 'وقت النهاية يجب أن يكون بعد البداية'
            : loc == 'es' ? 'La hora de fin debe ser posterior al inicio'
            : loc == 'en' ? 'End time must be after start'
            : 'L\'heure de fin doit être après le début';
    }
  }
}
