import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/event_model.dart';
import '../providers/app_provider.dart';
import '../utils/hijri_utils.dart';
import '../theme.dart';

// ── Top-level constants ───────────────────────────────────
const _kColorPalette = [
  AppColors.green, AppColors.gold, AppColors.blue,
  AppColors.red, Color(0xFF9B59B6), AppColors.navy,
  Color(0xFFE67E22), Color(0xFF1ABC9C),
];

const _kCategories = [
  ('religious', '🕌'), ('personal', '👤'), ('family', '👨‍👩‍👧'),
  ('work', '💼'),      ('health', '🏥'),   ('social', '🎉'), ('education', '📚'),
];

const _kEmojiGrid = [
  '🕌','🌙','✨','🤲','📿','☪️','🌟','🎉','👨‍👩‍👧','💼',
  '🏥','📚','🎓','✈️','🍽','🏠','🌹','🕯','📅','🔔',
  '💪','🧠','❤️','🌿','🏔','🌊','🎵','🖊','📖','🏆',
];

const _kReminderMinutes = [0, 5, 10, 15, 30, 60, 120, 1440, 2880, 10080];

// ═══════════════════════════════════════════════════════════
class AddEventScreen extends StatefulWidget {
  final AppEvent? existingEvent;
  const AddEventScreen({super.key, this.existingEvent});
  @override
  State<AddEventScreen> createState() => _AddEventScreenState();
}

class _AddEventScreenState extends State<AddEventScreen> {
  final _titleCtrl    = TextEditingController();
  final _descCtrl     = TextEditingController();
  final _locationCtrl = TextEditingController();

  late DateTime _startDate;
  late DateTime _endDate;
  bool _isAllDay = true;

  Color  _color    = AppColors.green;
  String _emoji    = '';
  String _category = 'personal';
  EventPriority _priority = EventPriority.medium;
  RecurrenceRule? _recurrence;
  bool _isPrivate = false;

  List<EventReminder> _reminders = [
    EventReminder(id: 'r1', minutesBefore: 1440),
    EventReminder(id: 'r2', minutesBefore: 60),
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day, 9, 0);
    _endDate   = DateTime(now.year, now.month, now.day, 10, 0);

    final e = widget.existingEvent;
    if (e != null) {
      final loc = 'ar';
      _titleCtrl.text    = e.title(loc);
      _descCtrl.text     = e.description(loc);
      _locationCtrl.text = e.location;
      _startDate  = e.startDate;
      _endDate    = e.endDate;
      _isAllDay   = e.isAllDay;
      _color      = e.color;
      _emoji      = e.emoji;
      _category   = e.category;
      _priority   = e.priority;
      _recurrence = e.recurrenceRule;
      _isPrivate  = e.isPrivate;
      _reminders  = List.from(e.reminders);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose(); _descCtrl.dispose(); _locationCtrl.dispose();
    super.dispose();
  }

  String _autoEmoji(String text) {
    final t = text.toLowerCase();
    if (t.contains('صلا') || t.contains('prière')) return '🕌';
    if (t.contains('رمضان') || t.contains('ramadan')) return '🌙';
    if (t.contains('عيد') || t.contains('aïd') || t.contains('eid')) return '🎉';
    if (t.contains('طبيب') || t.contains('médecin')) return '🏥';
    if (t.contains('عمل') || t.contains('travail')) return '💼';
    if (t.contains('عائلة') || t.contains('famille')) return '👨‍👩‍👧';
    if (t.contains('مدرسة') || t.contains('école')) return '📚';
    if (t.contains('سفر') || t.contains('voyage')) return '✈️';
    return '';
  }

  void _save(AppProvider p) {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(p.locale == 'ar' ? 'أدخل عنوان الحدث'
            : p.locale == 'fr' ? 'Entrez un titre' : 'Enter a title'),
        backgroundColor: AppColors.red,
      ));
      return;
    }
    if (!_isAllDay && _endDate.isBefore(_startDate)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(p.locale == 'ar' ? 'وقت النهاية يجب أن يكون بعد البداية'
            : 'L\'heure de fin doit être après le début'),
        backgroundColor: AppColors.red,
      ));
      return;
    }

    // Convert start date to Hijri for reference
    HijriDate? hijri;
    try { hijri = HijriDate.fromGregorian(_startDate); } catch (_) {}

    final now = DateTime.now();
    final ev = AppEvent(
      id: widget.existingEvent?.id ?? const Uuid().v4(),
      titles: {'ar': title, 'fr': title, 'en': title, 'es': title},
      descriptions: {
        'ar': _descCtrl.text.trim(),
        'fr': _descCtrl.text.trim(),
        'en': _descCtrl.text.trim(),
        'es': _descCtrl.text.trim(),
      },
      startDate: _isAllDay
          ? DateTime(_startDate.year, _startDate.month, _startDate.day)
          : _startDate,
      endDate: _isAllDay
          ? DateTime(_startDate.year, _startDate.month, _startDate.day, 23, 59)
          : _endDate,
      isAllDay: _isAllDay,
      recurrenceRule: _recurrence,
      reminders: _reminders,
      type: EventType.personal,
      color: _color,
      emoji: _emoji,
      category: _category,
      location: _locationCtrl.text.trim(),
      priority: _priority,
      isPrivate: _isPrivate,
      isEnabled: true,
      createdAt: widget.existingEvent?.createdAt ?? now,
      updatedAt: now,
      hijriDay:   hijri?.hDay,
      hijriMonth: hijri?.hMonth,
      hijriYear:  hijri?.hYear,
    );

    if (widget.existingEvent != null) {
      p.updateEvent(ev);
    } else {
      p.addEvent(ev);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    final isDark = p.themeMode == ThemeMode.dark;
    final loc = p.locale;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.bg,
      appBar: _buildAppBar(p, isDark, loc),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Title
            _Card(isDark: isDark, child: TextField(
              controller: _titleCtrl,
              onChanged: (v) {
                final auto = _autoEmoji(v);
                if (auto.isNotEmpty && _emoji.isEmpty) setState(() => _emoji = auto);
              },
              style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.darkText : AppColors.text),
              decoration: InputDecoration(
                border: InputBorder.none, isDense: true,
                hintText: loc == 'ar' ? 'اسم الحدث...'
                    : loc == 'fr' ? 'Nom de l\'événement...' : 'Event name...',
                hintStyle: GoogleFonts.cairo(fontSize: 16, color: AppColors.text3)),
            )),
            const SizedBox(height: 10),
            // 2. Date & Time
            _DateTimeSection(
              startDate: _startDate, endDate: _endDate, isAllDay: _isAllDay,
              isDark: isDark, loc: loc,
              onStartTap: () => _pickDateTime(true),
              onEndTap:   () => _pickDateTime(false),
              onAllDayChanged: (v) => setState(() => _isAllDay = v),
              recurrence: _recurrence,
              onRepeatTap: () => _showRepeatSheet(p, isDark),
            ),
            const SizedBox(height: 10),
            // 3. Reminders
            _RemindersCard(
              reminders: _reminders, isDark: isDark, loc: loc,
              onAdd: () => _showReminderSheet(p, isDark),
              onRemove: (i) => setState(() => _reminders.removeAt(i)),
            ),
            const SizedBox(height: 10),
            // 4. Location
            _Card(isDark: isDark, child: Row(children: [
              const Text('📍', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(child: TextField(
                controller: _locationCtrl,
                style: GoogleFonts.cairo(fontSize: 13,
                    color: isDark ? AppColors.darkText : AppColors.text),
                decoration: InputDecoration(
                  border: InputBorder.none, isDense: true,
                  hintText: loc == 'ar' ? 'إضافة الموقع...'
                      : loc == 'fr' ? 'Ajouter un lieu...' : 'Add location...',
                  hintStyle: GoogleFonts.cairo(fontSize: 13, color: AppColors.text3)),
              )),
            ])),
            const SizedBox(height: 10),
            // 5. Category
            _CategoryCard(selected: _category, isDark: isDark, loc: loc,
                onSelected: (c) => setState(() => _category = c)),
            const SizedBox(height: 10),
            // 6. Color & Emoji
            _ColorEmojiCard(
              color: _color, emoji: _emoji, isDark: isDark, loc: loc,
              onColorSelected: (c) => setState(() => _color = c),
              onEmojiTap: () => _showEmojiSheet(isDark),
            ),
            const SizedBox(height: 10),
            // 7. Priority
            _PriorityCard(priority: _priority, isDark: isDark, loc: loc,
                onSelected: (p) => setState(() => _priority = p)),
            const SizedBox(height: 10),
            // 8. Notes
            _Card(isDark: isDark, child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Label(loc == 'ar' ? 'ملاحظات' : 'NOTES'),
                TextField(
                  controller: _descCtrl, maxLines: 3,
                  style: GoogleFonts.cairo(fontSize: 13,
                      color: isDark ? AppColors.darkText : AppColors.text),
                  decoration: InputDecoration(
                    border: InputBorder.none, isDense: true,
                    hintText: loc == 'ar' ? 'أضف ملاحظات...'
                        : loc == 'fr' ? 'Ajouter des notes...' : 'Add notes...',
                    hintStyle: GoogleFonts.cairo(fontSize: 13, color: AppColors.text3)),
                ),
              ],
            )),
            const SizedBox(height: 10),
            // 9. Privacy
            _Card(isDark: isDark,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                Container(width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: _isPrivate ? AppColors.navy : AppColors.greenPale,
                    borderRadius: BorderRadius.circular(10)),
                  child: Icon(_isPrivate ? Icons.lock_rounded : Icons.lock_open_rounded,
                      color: _isPrivate ? Colors.white : AppColors.green, size: 18)),
                const SizedBox(width: 12),
                Expanded(child: Text(
                  loc == 'ar' ? 'سري' : loc == 'fr' ? 'Privé' : 'Private',
                  style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w700,
                      color: isDark ? AppColors.darkText : AppColors.text))),
                _SmToggle(value: _isPrivate,
                    onChanged: (v) => setState(() => _isPrivate = v)),
              ]),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(AppProvider p, bool isDark, String loc) {
    return AppBar(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.close,
            color: isDark ? AppColors.darkText : AppColors.navy),
        onPressed: () => Navigator.pop(context)),
      title: Text(
        widget.existingEvent != null
            ? (loc == 'ar' ? 'تعديل الحدث' : 'Modifier')
            : (loc == 'ar' ? 'حدث جديد' : 'Nouvel événement'),
        style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w800,
            color: isDark ? AppColors.darkText : AppColors.navy)),
      centerTitle: true,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: GestureDetector(
            onTap: () => _save(p),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
              decoration: BoxDecoration(
                  color: AppColors.green, borderRadius: BorderRadius.circular(22)),
              child: Text(p.label('save'), style: GoogleFonts.cairo(
                  fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(height: 1,
            color: isDark ? AppColors.darkBorder : AppColors.border)),
    );
  }

  Future<void> _pickDateTime(bool isStart) async {
    final initial = isStart ? _startDate : _endDate;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(primary: AppColors.green)),
        child: child!),
    );
    if (date == null) return;
    if (_isAllDay) {
      setState(() {
        if (isStart) _startDate = date;
        else _endDate = date;
      });
      return;
    }
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null) return;
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() { isStart ? _startDate = dt : _endDate = dt; });
  }

  void _showRepeatSheet(AppProvider p, bool isDark) {
    final loc = p.locale;
    const opts = [
      (null, 'لا يتكرر', 'Une fois', 'No repeat'),
      ('daily', 'يومياً', 'Quotidien', 'Daily'),
      ('weekly', 'أسبوعياً', 'Hebdomadaire', 'Weekly'),
      ('monthly', 'شهرياً', 'Mensuel', 'Monthly'),
      ('yearly', 'سنوياً', 'Annuel', 'Yearly'),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: AppColors.border,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 8),
          ...opts.map((o) => ListTile(
            title: Text(loc == 'ar' ? o.$2 : loc == 'fr' ? o.$3 : o.$4,
                style: GoogleFonts.cairo(fontSize: 14,
                    color: isDark ? AppColors.darkText : AppColors.text)),
            trailing: _recurrence?.frequency.name == o.$1 || (o.$1 == null && _recurrence == null)
                ? const Icon(Icons.check_circle_rounded, color: AppColors.green) : null,
            onTap: () {
              setState(() {
                if (o.$1 == null) {
                  _recurrence = null;
                } else {
                  _recurrence = RecurrenceRule(
                    frequency: RecurrenceFrequency.values.firstWhere(
                        (e) => e.name == o.$1));
                }
              });
              Navigator.pop(context);
            },
          )),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showReminderSheet(AppProvider p, bool isDark) {
    if (_reminders.length >= 5) return;
    final loc = p.locale;
    final labels = {
      0: ['عند الحدث', 'Au moment', 'At time'],
      5: ['5 دقائق', '5 min', '5 min'],
      10: ['10 دقائق', '10 min', '10 min'],
      15: ['15 دقيقة', '15 min', '15 min'],
      30: ['30 دقيقة', '30 min', '30 min'],
      60: ['ساعة', '1 heure', '1 hour'],
      120: ['ساعتان', '2 heures', '2 hours'],
      1440: ['يوم', '1 jour', '1 day'],
      2880: ['يومان', '2 jours', '2 days'],
      10080: ['أسبوع', '1 semaine', '1 week'],
    };
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: AppColors.border,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 8),
          ..._kReminderMinutes.map((min) {
            final lbl = labels[min]!;
            return ListTile(
              title: Text(loc == 'ar' ? '${lbl[0]} قبل'
                  : loc == 'fr' ? '${lbl[1]} avant' : '${lbl[2]} before',
                style: GoogleFonts.cairo(fontSize: 14,
                    color: isDark ? AppColors.darkText : AppColors.text)),
              onTap: () {
                setState(() => _reminders.add(EventReminder(
                  id: '${DateTime.now().millisecondsSinceEpoch}',
                  minutesBefore: min)));
                Navigator.pop(context);
              },
            );
          }),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showEmojiSheet(bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: GridView.builder(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 8, mainAxisSpacing: 4, crossAxisSpacing: 4),
          itemCount: _kEmojiGrid.length,
          itemBuilder: (ctx, i) => GestureDetector(
            onTap: () { setState(() => _emoji = _kEmojiGrid[i]); Navigator.pop(context); },
            child: Container(
              decoration: BoxDecoration(
                color: _emoji == _kEmojiGrid[i] ? AppColors.greenPale : Colors.transparent,
                borderRadius: BorderRadius.circular(8)),
              child: Center(child: Text(_kEmojiGrid[i],
                  style: const TextStyle(fontSize: 22))),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// SUB-WIDGETS
// ═══════════════════════════════════════════════════════════
class _Card extends StatelessWidget {
  final Widget child;
  final bool isDark;
  final EdgeInsets? padding;
  const _Card({required this.child, required this.isDark, this.padding});
  @override
  Widget build(BuildContext context) => Container(
    padding: padding ?? const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: isDark ? AppColors.darkSurface : AppColors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)]),
    child: child,
  );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: GoogleFonts.cairo(fontSize: 9,
        fontWeight: FontWeight.w700, color: AppColors.text3, letterSpacing: 2)),
  );
}

class _SmToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SmToggle({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => onChanged(!value),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 36, height: 20, padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: value ? AppColors.green : Colors.grey.shade300,
        borderRadius: BorderRadius.circular(10)),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 200),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(width: 14, height: 14,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))),
    ),
  );
}

class _DateTimeSection extends StatelessWidget {
  final DateTime startDate, endDate;
  final bool isAllDay;
  final bool isDark;
  final String loc;
  final VoidCallback onStartTap, onEndTap, onRepeatTap;
  final ValueChanged<bool> onAllDayChanged;
  final RecurrenceRule? recurrence;
  const _DateTimeSection({
    required this.startDate, required this.endDate, required this.isAllDay,
    required this.isDark, required this.loc,
    required this.onStartTap, required this.onEndTap,
    required this.onAllDayChanged, required this.onRepeatTap,
    required this.recurrence,
  });

  String _repeatLabel() {
    if (recurrence == null) return loc == 'ar' ? 'لا يتكرر' : 'No repeat';
    switch (recurrence!.frequency) {
      case RecurrenceFrequency.daily:   return loc == 'ar' ? 'يومياً' : 'Daily';
      case RecurrenceFrequency.weekly:  return loc == 'ar' ? 'أسبوعياً' : 'Weekly';
      case RecurrenceFrequency.monthly: return loc == 'ar' ? 'شهرياً' : 'Monthly';
      case RecurrenceFrequency.yearly:  return loc == 'ar' ? 'سنوياً' : 'Yearly';
    }
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}'
      '${isAllDay ? '' : '  ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}'}';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          // All-day toggle
          Row(children: [
            Expanded(child: Text(loc == 'ar' ? 'طوال اليوم' : 'Toute la journée',
              style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w700,
                  color: Colors.white))),
            _SmToggle(value: isAllDay, onChanged: onAllDayChanged),
          ]),
          const SizedBox(height: 12),
          // Start
          GestureDetector(
            onTap: onStartTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.play_arrow_rounded, color: Colors.white70, size: 16),
                const SizedBox(width: 8),
                Text(loc == 'ar' ? 'البداية: ' : 'Début: ',
                  style: GoogleFonts.cairo(fontSize: 10, color: Colors.white54)),
                Text(_fmt(startDate), style: GoogleFonts.cairo(
                    fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          // End
          GestureDetector(
            onTap: onEndTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.stop_rounded, color: Colors.white70, size: 16),
                const SizedBox(width: 8),
                Text(loc == 'ar' ? 'النهاية: ' : 'Fin: ',
                  style: GoogleFonts.cairo(fontSize: 10, color: Colors.white54)),
                Text(_fmt(endDate), style: GoogleFonts.cairo(
                    fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          // Repeat
          GestureDetector(
            onTap: onRepeatTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: recurrence != null
                    ? AppColors.green.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: recurrence != null ? Border.all(color: AppColors.green) : null),
              child: Row(children: [
                const Icon(Icons.repeat_rounded, color: Colors.white70, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(_repeatLabel(), style: GoogleFonts.cairo(
                    fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white))),
                const Icon(Icons.chevron_left, color: Colors.white54, size: 16),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _RemindersCard extends StatelessWidget {
  final List<EventReminder> reminders;
  final bool isDark;
  final String loc;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  const _RemindersCard({required this.reminders, required this.isDark,
      required this.loc, required this.onAdd, required this.onRemove});
  @override
  Widget build(BuildContext context) {
    return _Card(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.notifications_rounded, size: 18, color: AppColors.green),
            const SizedBox(width: 10),
            Expanded(child: Text(
              loc == 'ar' ? 'التذكيرات' : 'Rappels',
              style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.darkText : AppColors.text))),
            GestureDetector(
              onTap: onAdd,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppColors.greenPale,
                    borderRadius: BorderRadius.circular(12)),
                child: Text(loc == 'ar' ? '+ إضافة' : '+ Ajouter',
                  style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.w700,
                      color: AppColors.green)))),
          ]),
          if (reminders.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...reminders.asMap().entries.map((e) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkBg : AppColors.bg,
                borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.alarm_rounded, size: 14, color: AppColors.gold),
                const SizedBox(width: 8),
                Expanded(child: Text(e.value.label(loc),
                  style: GoogleFonts.cairo(fontSize: 12,
                      color: isDark ? AppColors.darkText : AppColors.text))),
                GestureDetector(
                  onTap: () => onRemove(e.key),
                  child: const Icon(Icons.close_rounded, size: 16, color: AppColors.text3)),
              ]),
            )),
          ],
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final String selected, loc;
  final bool isDark;
  final ValueChanged<String> onSelected;
  const _CategoryCard({required this.selected, required this.isDark,
      required this.loc, required this.onSelected});
  String _catLabel(String id) {
    const l = {
      'religious': ['ديني','Religieux','Religious'],
      'personal':  ['شخصي','Personnel','Personal'],
      'family':    ['عائلي','Famille','Family'],
      'work':      ['عمل','Travail','Work'],
      'health':    ['صحة','Santé','Health'],
      'social':    ['اجتماعي','Social','Social'],
      'education': ['تعليم','Éducation','Education'],
    };
    final idx = loc == 'ar' ? 0 : loc == 'fr' ? 1 : 2;
    return l[id]?[idx] ?? id;
  }
  @override
  Widget build(BuildContext context) {
    return _Card(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label(loc == 'ar' ? 'الفئة' : 'CATÉGORIE'),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _kCategories.map((cat) {
                final active = selected == cat.$1;
                return GestureDetector(
                  onTap: () => onSelected(cat.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: active ? AppColors.navy
                          : (isDark ? AppColors.darkBg : AppColors.bg),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: active ? AppColors.navy
                              : (isDark ? AppColors.darkBorder : AppColors.border))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(cat.$2, style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 5),
                      Text(_catLabel(cat.$1), style: GoogleFonts.cairo(
                          fontSize: 10, fontWeight: FontWeight.w700,
                          color: active ? Colors.white
                              : (isDark ? AppColors.darkText2 : AppColors.text2))),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorEmojiCard extends StatelessWidget {
  final Color color;
  final String emoji, loc;
  final bool isDark;
  final ValueChanged<Color> onColorSelected;
  final VoidCallback onEmojiTap;
  const _ColorEmojiCard({required this.color, required this.emoji,
      required this.isDark, required this.loc,
      required this.onColorSelected, required this.onEmojiTap});
  @override
  Widget build(BuildContext context) {
    return _Card(isDark: isDark, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label(loc == 'ar' ? 'اللون والرمز' : 'COULEUR & EMOJI'),
        Row(children: [
          ..._kColorPalette.map((c) {
            final isSel = color == c;
            return GestureDetector(
              onTap: () => onColorSelected(c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: isSel ? 32 : 26, height: isSel ? 32 : 26,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(color: c, shape: BoxShape.circle,
                    boxShadow: isSel ? [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 8)] : null),
                child: isSel ? const Icon(Icons.check, color: Colors.white, size: 14) : null,
              ),
            );
          }),
          const Spacer(),
          GestureDetector(
            onTap: onEmojiTap,
            child: Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkBg : AppColors.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border)),
              child: Center(child: emoji.isNotEmpty
                  ? Text(emoji, style: const TextStyle(fontSize: 22))
                  : const Icon(Icons.emoji_emotions_outlined,
                      color: AppColors.text3, size: 20))),
          ),
        ]),
      ],
    ));
  }
}

class _PriorityCard extends StatelessWidget {
  final EventPriority priority;
  final bool isDark;
  final String loc;
  final ValueChanged<EventPriority> onSelected;
  const _PriorityCard({required this.priority, required this.isDark,
      required this.loc, required this.onSelected});
  String _label(EventPriority p) {
    const l = {'low': ['منخفض','Faible','Low'],
        'medium': ['متوسط','Moyen','Medium'], 'high': ['عالي','Élevé','High']};
    final idx = loc == 'ar' ? 0 : loc == 'fr' ? 1 : 2;
    return l[p.name]?[idx] ?? p.name;
  }
  Color _color(EventPriority p) {
    switch (p) {
      case EventPriority.low: return AppColors.blue;
      case EventPriority.medium: return AppColors.gold;
      case EventPriority.high: return AppColors.red;
    }
  }
  @override
  Widget build(BuildContext context) {
    return _Card(isDark: isDark, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label(loc == 'ar' ? 'الأولوية' : 'PRIORITÉ'),
        Row(children: EventPriority.values.map((p) {
          final active = priority == p;
          final c = _color(p);
          return Expanded(child: GestureDetector(
            onTap: () => onSelected(p),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: active ? c.withValues(alpha: 0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: active ? c : AppColors.border, width: active ? 1.5 : 1)),
              child: Column(children: [
                Icon(p == EventPriority.low ? Icons.arrow_downward_rounded
                    : p == EventPriority.medium ? Icons.remove_rounded
                    : Icons.arrow_upward_rounded,
                    color: active ? c : AppColors.text3, size: 16),
                const SizedBox(height: 4),
                Text(_label(p), style: GoogleFonts.cairo(fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: active ? c : AppColors.text3)),
              ]),
            ),
          ));
        }).toList()),
      ],
    ));
  }
}
