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
  Future<void> _openRecurrenceSheet() async {
    final picked = await showModalBottomSheet<_RecurrenceChoice>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RecurrenceSheet(selected: _draft.recurrence),
    );
    if (picked == null) return;
    setState(() => _draft.setRecurrence(picked));
  }

  Future<void> _openEditScopeSheet() async {
    final picked = await showModalBottomSheet<_EditScope>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _EditScopeSheet(selected: _draft.editScope),
    );
    if (picked == null) return;
    setState(() => _draft.setEditScope(picked));
  }

  // ── Notifications sheet ─────────────────────────────────────────
  Future<void> _openAddReminderSheet() async {
    if (!_draft.canAddReminder) return;
    final picked = await showModalBottomSheet<EventReminder>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddReminderSheet(
        isAllDay: _draft.isAllDay,
        idGenerator: _EventDraft._newReminderId,
      ),
    );
    if (picked == null) return;
    setState(() => _draft.addReminder(picked));
  }

  // ── Build ───────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: _buildAppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TitleField(controller: _titleCtrl),
            const SizedBox(height: 12),
            _KindSelector(
              selected: _kind,
              onChanged: (k) => setState(() => _kind = k),
            ),
            const SizedBox(height: 12),
            _TimeSection(
              draft: _draft,
              locale: context.watch<AppProvider>().locale,
              onAllDayChanged: (v) =>
                  setState(() => _draft.toggleAllDay(v)),
              onStartTap: _pickStart,
              onEndTap: _pickEnd,
            ),
            const SizedBox(height: 12),
            _RecurrenceSection(
              draft: _draft,
              showEditScope: _isEditingRecurringEvent,
              onRecurrenceTap: _openRecurrenceSheet,
              onEditScopeTap: _openEditScopeSheet,
            ),
            const SizedBox(height: 12),
            _NotificationsSection(
              draft: _draft,
              onEnabledChanged: (v) =>
                  setState(() => _draft.setNotificationsEnabled(v)),
              onAddReminder: _openAddReminderSheet,
              onRemoveReminder: (id) =>
                  setState(() => _draft.removeReminder(id)),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const _SaveBar(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded, color: AppColors.navy),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        'Add Event',
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
  String get label {
    switch (this) {
      case _RecurrenceChoice.none:
        return 'Does not repeat';
      case _RecurrenceChoice.daily:
        return 'Daily';
      case _RecurrenceChoice.weekly:
        return 'Weekly';
      case _RecurrenceChoice.monthly:
        return 'Monthly';
      case _RecurrenceChoice.yearly:
        return 'Yearly';
    }
  }
}

/// Editing scope picked when modifying an existing recurring event.
/// The actual SPLIT / EXDATE / OVERRIDE logic lives in a later step.
enum _EditScope { thisOccurrence, thisAndFollowing, allOccurrences }

extension _EditScopeX on _EditScope {
  String get label {
    switch (this) {
      case _EditScope.thisOccurrence:
        return 'This event';
      case _EditScope.thisAndFollowing:
        return 'This and following events';
      case _EditScope.allOccurrences:
        return 'All events';
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
  const _TitleField({required this.controller});

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
          hintText: 'Event title',
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
  final ValueChanged<EventKind> onChanged;
  const _KindSelector({required this.selected, required this.onChanged});

  static const _options = <(EventKind, String, IconData)>[
    (EventKind.event, 'Event', Icons.event_rounded),
    (EventKind.task, 'Task', Icons.check_circle_outline_rounded),
    (EventKind.birthday, 'Birthday', Icons.cake_outlined),
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
                      o.$2,
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
                    'Time',
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
                    'All day',
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
            label: 'Start',
            value: _format(draft.start),
            onTap: onStartTap,
          ),
          const Divider(height: 1, color: AppColors.border, indent: 14),
          _TimeRow(
            label: 'End',
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
  final bool showEditScope;
  final VoidCallback onRecurrenceTap;
  final VoidCallback onEditScopeTap;
  const _RecurrenceSection({
    required this.draft,
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
                    'Recurrence',
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
            label: 'Repeats',
            value: draft.recurrence.label,
            onTap: onRecurrenceTap,
            last: !showEditScope,
          ),
          if (showEditScope) ...[
            const Divider(height: 1, color: AppColors.border, indent: 14),
            _PropertyRow(
              label: 'Edit scope',
              value: draft.editScope.label,
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
  const _RecurrenceSheet({required this.selected});

  @override
  Widget build(BuildContext context) {
    return _OptionsSheet<_RecurrenceChoice>(
      title: 'Repeats',
      options: _RecurrenceChoice.values,
      selected: selected,
      labelOf: (c) => c.label,
    );
  }
}

class _EditScopeSheet extends StatelessWidget {
  final _EditScope selected;
  const _EditScopeSheet({required this.selected});

  @override
  Widget build(BuildContext context) {
    return _OptionsSheet<_EditScope>(
      title: 'Apply changes to',
      options: _EditScope.values,
      selected: selected,
      labelOf: (c) => c.label,
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
const List<(int, String)> _kRelativePresets = [
  (0, 'At time'),
  (5, '5 minutes before'),
  (10, '10 minutes before'),
  (15, '15 minutes before'),
  (30, '30 minutes before'),
  (60, '1 hour before'),
  (120, '2 hours before'),
  (1440, '1 day before'),
  (2880, '2 days before'),
  (10080, '1 week before'),
];

/// Standard fixed-time-reminder presets (all-day events).
/// Source: docs/event_notifications.md §4.2. Tuple = (daysBefore, hour, minute, label).
const List<(int, int, int, String)> _kFixedPresets = [
  (0, 9, 0, 'Same day at 09:00'),
  (1, 9, 0, 'The day before at 09:00'),
  (1, 11, 0, 'The day before at 11:00'),
  (1, 17, 0, 'The day before at 17:00'),
  (2, 9, 0, '2 days before at 09:00'),
  (7, 9, 0, '1 week before at 09:00'),
];

class _NotificationsSection extends StatelessWidget {
  final _EventDraft draft;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onAddReminder;
  final ValueChanged<String> onRemoveReminder;
  const _NotificationsSection({
    required this.draft,
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
                    'Notifications',
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
                    'Enable notifications',
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
                            ? 'Add reminder'
                            : 'Reminder limit reached (5)',
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
  final VoidCallback onRemove;
  const _ReminderRow({required this.reminder, required this.onRemove});

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
              reminder.label('en'),
              style: GoogleFonts.cairo(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Remove',
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
  final String Function() idGenerator;
  const _AddReminderSheet({
    required this.isAllDay,
    required this.idGenerator,
  });

  @override
  Widget build(BuildContext context) {
    final title = isAllDay ? 'Add reminder' : 'Add reminder';
    final entries = isAllDay
        ? _kFixedPresets
            .map((p) => (
                  EventReminder.fixed(
                    id: idGenerator(),
                    daysBefore: p.$1,
                    hour: p.$2,
                    minute: p.$3,
                  ),
                  p.$4,
                ))
            .toList()
        : _kRelativePresets
            .map((p) => (
                  EventReminder.relative(
                    id: idGenerator(),
                    minutesBefore: p.$1,
                  ),
                  p.$2,
                ))
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
                  title,
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
                    isAllDay ? 'All-day presets' : 'Timed presets',
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
                final entry = entries[i];
                return InkWell(
                  onTap: () => Navigator.of(context).pop(entry.$1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.$2,
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
  const _SaveBar();

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
            'Save',
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
