import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/event_model.dart';
import '../providers/app_provider.dart';
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
  const AddEventScreen({super.key, this.existingEvent});

  @override
  State<AddEventScreen> createState() => _AddEventScreenState();
}

class _AddEventScreenState extends State<AddEventScreen> {
  final TextEditingController _titleCtrl = TextEditingController();
  EventKind _kind = EventKind.event;
  late _EventDraft _draft;

  @override
  void initState() {
    super.initState();
    _draft = _EventDraft.now();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  // ── Pickers ─────────────────────────────────────────────────────
  Future<void> _pickStart() async {
    final picked = await _pickDateMaybeTime(initial: _draft.start);
    if (picked == null) return;
    setState(() => _draft.setStart(picked));
  }

  Future<void> _pickEnd() async {
    final picked = await _pickDateMaybeTime(initial: _draft.end);
    if (picked == null) return;
    setState(() => _draft.setEnd(picked));
  }

  Future<DateTime?> _pickDateMaybeTime({required DateTime initial}) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1970),
      lastDate: DateTime(2200),
    );
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
    final locale = context.watch<AppProvider>().locale;
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
            _KindSelector(
              selected: _kind,
              locale: locale,
              onChanged: (k) => setState(() => _kind = k),
            ),
            const SizedBox(height: 12),
            _TimeSection(
              draft: _draft,
              locale: locale,
              onAllDayChanged: (v) =>
                  setState(() => _draft.toggleAllDay(v)),
              onStartTap: _pickStart,
              onEndTap: _pickEnd,
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
      bottomNavigationBar: _SaveBar(locale: locale),
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
        style: GoogleFonts.cairo(
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
        style: GoogleFonts.cairo(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.text,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          isDense: true,
          hintText: _Tr.titleHint.value(locale),
          hintStyle: GoogleFonts.cairo(
            fontSize: 16,
            color: AppColors.text3,
          ),
        ),
      ),
    );
  }
}

class _KindSelector extends StatelessWidget {
  final EventKind selected;
  final String locale;
  final ValueChanged<EventKind> onChanged;
  const _KindSelector({
    required this.selected,
    required this.locale,
    required this.onChanged,
  });

  static const _options = <(EventKind, _Tr, IconData)>[
    (EventKind.event, _Tr.kindEvent, Icons.event_rounded),
    (EventKind.task, _Tr.kindTask, Icons.check_circle_outline_rounded),
    (EventKind.birthday, _Tr.kindBirthday, Icons.cake_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: _options.map((o) {
          final isSelected = selected == o.$1;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(o.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.green : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? AppColors.green : AppColors.border,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      o.$3,
                      size: 18,
                      color: isSelected ? Colors.white : AppColors.text2,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      o.$2.value(locale),
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? Colors.white : AppColors.text2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _TimeSection extends StatelessWidget {
  final _EventDraft draft;
  final String locale;
  final ValueChanged<bool> onAllDayChanged;
  final VoidCallback onStartTap;
  final VoidCallback onEndTap;
  const _TimeSection({
    required this.draft,
    required this.locale,
    required this.onAllDayChanged,
    required this.onStartTap,
    required this.onEndTap,
  });

  String _format(DateTime d) {
    // Locale-aware date string with strict Western digits.
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
                  child: const Icon(
                    Icons.schedule_rounded,
                    size: 18,
                    color: AppColors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _Tr.sectionTime.value(locale),
                    style: GoogleFonts.cairo(
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
                    style: GoogleFonts.cairo(
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
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ),
            Text(
              value,
              style: GoogleFonts.cairo(
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
                  child: const Icon(
                    Icons.repeat_rounded,
                    size: 18,
                    color: AppColors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _Tr.sectionRecurrence.value(locale),
                    style: GoogleFonts.cairo(
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
                style: GoogleFonts.cairo(
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
                style: GoogleFonts.cairo(
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
                  style: GoogleFonts.cairo(
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
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    if (option == selected)
                      const Icon(
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
                  child: const Icon(
                    Icons.notifications_outlined,
                    size: 18,
                    color: AppColors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _Tr.sectionNotifications.value(locale),
                    style: GoogleFonts.cairo(
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
                    style: GoogleFonts.cairo(
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
                        style: GoogleFonts.cairo(
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
              style: GoogleFonts.cairo(
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
                  style: GoogleFonts.cairo(
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
                    style: GoogleFonts.cairo(
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
                            style: GoogleFonts.cairo(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                        const Icon(
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
  const _SaveBar({required this.locale});

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
          onPressed: () {},
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
            style: GoogleFonts.cairo(
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
  kindEvent,
  kindTask,
  kindBirthday,
  sectionTime,
  allDay,
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
  sectionNotifications,
  enableNotifications,
  addReminder,
  reminderLimit,
  remove,
  allDayPresets,
  timedPresets,
  save,
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
      case _Tr.kindEvent:
        return loc == 'ar' ? 'حدث'
            : loc == 'es' ? 'Evento'
            : loc == 'en' ? 'Event'
            : 'Événement';
      case _Tr.kindTask:
        return loc == 'ar' ? 'مهمّة'
            : loc == 'es' ? 'Tarea'
            : loc == 'en' ? 'Task'
            : 'Tâche';
      case _Tr.kindBirthday:
        return loc == 'ar' ? 'عيد ميلاد'
            : loc == 'es' ? 'Cumpleaños'
            : loc == 'en' ? 'Birthday'
            : 'Anniversaire';
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
    }
  }
}
