import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/event_model.dart';
import '../theme.dart';

/// Add / Edit Event screen — structural layout + Time input.
///
/// Step 2 of the staged Google-Agenda-style rewrite. Adds the Time
/// section behavior bound to a temporary [_EventDraft]:
///   * All-day Switch
///   * Date picker for all-day events
///   * Date + Time picker for timed events
///   * Shape normalization when toggling all-day on/off
///
/// Recurrence and Notifications are still placeholders. No services,
/// no validation beyond minimal start/end ordering inside the draft.
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
              onAllDayChanged: (v) =>
                  setState(() => _draft.toggleAllDay(v)),
              onStartTap: _pickStart,
              onEndTap: _pickEnd,
            ),
            const SizedBox(height: 12),
            const _SectionPlaceholder(
              icon: Icons.repeat_rounded,
              title: 'Recurrence',
            ),
            const SizedBox(height: 12),
            const _SectionPlaceholder(
              icon: Icons.notifications_outlined,
              title: 'Notifications',
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

class _EventDraft {
  bool isAllDay;
  DateTime start;

  /// For all-day events this is the **inclusive** last day shown to the
  /// user. The exclusive-end conversion required by the model spec
  /// happens when the draft is serialized to an [AppEvent], which is
  /// the responsibility of a later step.
  DateTime end;

  _EventDraft({
    required this.isAllDay,
    required this.start,
    required this.end,
  });

  factory _EventDraft.now() {
    final now = DateTime.now();
    return _EventDraft(
      isAllDay: false,
      start: DateTime(now.year, now.month, now.day, 9, 0),
      end: DateTime(now.year, now.month, now.day, 10, 0),
    );
  }

  void toggleAllDay(bool value) {
    if (value == isAllDay) return;
    if (value) {
      // timed → all-day: drop clock fields, end defaults to start.
      final s = DateTime(start.year, start.month, start.day);
      isAllDay = true;
      start = s;
      end = s;
    } else {
      // all-day → timed: assign default times (09:00 / 10:00) on the
      // existing date.
      final s = DateTime(start.year, start.month, start.day, 9, 0);
      isAllDay = false;
      start = s;
      end = DateTime(s.year, s.month, s.day, 10, 0);
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
  final ValueChanged<bool> onAllDayChanged;
  final VoidCallback onStartTap;
  final VoidCallback onEndTap;
  const _TimeSection({
    required this.draft,
    required this.onAllDayChanged,
    required this.onStartTap,
    required this.onEndTap,
  });

  String _format(DateTime d) {
    return draft.isAllDay
        ? DateFormat.yMMMd().format(d)
        : DateFormat.yMMMd().add_Hm().format(d);
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

class _SectionPlaceholder extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionPlaceholder({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.greenPale,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppColors.green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.cairo(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.text3,
          ),
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
