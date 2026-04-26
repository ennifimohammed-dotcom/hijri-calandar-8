import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/event_model.dart';
import '../providers/app_provider.dart';
import '../utils/hijri_utils.dart';
import '../utils/text_format.dart';
import '../theme.dart';
import 'add_event_screen.dart';
import 'search_screen.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late PageController _pageCtrl;
  int _pageIndex = 1000;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(initialPage: _pageIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    final isDark = p.themeMode == ThemeMode.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(p, isDark),
            _buildViewToggle(p, isDark),
            Expanded(child: _buildCurrentView(p, isDark)),
          ],
        ),
      ),
    );
  }

  // ── Top bar ─────────────────────────────────────────────────
  Widget _buildTopBar(AppProvider p, bool isDark) {
    final surf = isDark ? AppColors.darkSurface : AppColors.white;
    final m = p.currentMonth;
    final monthName = '${p.getHijriMonthName(m.hMonth, p.locale)} ${m.hYear}';
    // Bridge to Gregorian so we can show the corresponding month/year
    // beneath the Hijri header (small font, Western digits enforced).
    DateTime gregFirst;
    try {
      gregFirst = HijriDate.hijriToGregorian(m.hYear, m.hMonth, 1);
    } catch (_) {
      gregFirst = DateTime.now();
    }
    final gregLabel = TextFormat.toWesternDigits(
      TextFormat.formatGregorianMonthYear(gregFirst, p.locale),
    );
    return Container(
      color: surf,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  TextFormat.toWesternDigits(monthName),
                  style: GoogleFonts.amiri(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkText : AppColors.navy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  gregLabel,
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.darkText3 : AppColors.text3,
                  ),
                ),
              ],
            ),
          ),
          _TodayButton(p: p, isDark: isDark, onTap: () {
            p.goToToday();
            _pageCtrl.jumpToPage(_pageIndex);
          }),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SearchScreen())),
            child: Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                border: Border.all(
                    color: isDark ? AppColors.darkBorder : AppColors.border),
                borderRadius: BorderRadius.circular(17)),
              child: Icon(Icons.search_rounded, size: 16,
                  color: isDark ? AppColors.darkText2 : AppColors.text2),
            ),
          ),
        ],
      ),
    );
  }

  // ── View toggle ─────────────────────────────────────────────
  Widget _buildViewToggle(AppProvider p, bool isDark) {
    final surf = isDark ? AppColors.darkSurface : AppColors.white;
    final modes = [
      (CalendarViewMode.monthly,  Icons.calendar_month_rounded,  p.label('monthly')),
      (CalendarViewMode.weekly,   Icons.view_week_rounded,        p.label('weekly')),
      (CalendarViewMode.agenda,   Icons.view_agenda_rounded,      p.label('agenda')),
    ];
    return Container(
      color: surf,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: modes.map((m) {
          final active = p.viewMode == m.$1;
          return Expanded(
            child: GestureDetector(
              onTap: () => p.setViewMode(m.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: active ? AppColors.green : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Icon(m.$2, size: 16,
                      color: active ? Colors.white : (isDark ? AppColors.darkText3 : AppColors.text3)),
                    const SizedBox(height: 2),
                    Text(m.$3,
                      style: GoogleFonts.cairo(
                        fontSize: 9, fontWeight: FontWeight.w700,
                        color: active ? Colors.white : (isDark ? AppColors.darkText3 : AppColors.text3)),
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

  Widget _buildCurrentView(AppProvider p, bool isDark) {
    switch (p.viewMode) {
      case CalendarViewMode.monthly:
        return _MonthlyView(pageCtrl: _pageCtrl, baseIndex: _pageIndex, p: p, isDark: isDark);
      case CalendarViewMode.weekly:
        return _WeeklyView(p: p, isDark: isDark);
      case CalendarViewMode.agenda:
        return _AgendaView(p: p, isDark: isDark);
    }
  }
}

// ════════════════════════════════════════════════════════════
// TODAY BUTTON
// ════════════════════════════════════════════════════════════
class _TodayButton extends StatelessWidget {
  final AppProvider p;
  final bool isDark;
  final VoidCallback onTap;
  const _TodayButton({required this.p, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.green, width: 1.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          p.label('today'),
          style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.green),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// MONTHLY VIEW
// ════════════════════════════════════════════════════════════
class _MonthlyView extends StatelessWidget {
  final PageController pageCtrl;
  final int baseIndex;
  final AppProvider p;
  final bool isDark;
  const _MonthlyView({required this.pageCtrl, required this.baseIndex,
      required this.p, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final surf = isDark ? AppColors.darkSurface : AppColors.white;
    return Column(
      children: [
        // Weekday header (Mon–Sun)
        Container(
          color: surf,
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
          child: _buildWeekdayHeader(),
        ),
        // PageView for months
        Expanded(
          child: PageView.builder(
            controller: pageCtrl,
            onPageChanged: (idx) {
              final diff = idx - baseIndex;
              if (diff > 0) {
                for (int i = 0; i < diff; i++) p.goToNextMonth();
              } else {
                for (int i = 0; i < -diff; i++) p.goToPreviousMonth();
              }
            },
            itemBuilder: (ctx, idx) {
              return _MonthPage(p: p, isDark: isDark);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWeekdayHeader() {
    // Mon to Sun
    final days = p.locale == 'ar'
        ? ['إث', 'ث', 'أر', 'خ', 'ج', 'س', 'أح']
        : ['Lu', 'Ma', 'Me', 'Je', 'Ve', 'Sa', 'Di'];
    return Row(
      children: List.generate(7, (i) {
        final isFri = i == 4; // Friday is index 4 in Mon-based week
        return Expanded(
          child: Center(
            child: Text(days[i],
              style: GoogleFonts.cairo(
                fontSize: 10, fontWeight: FontWeight.w700,
                color: isFri ? AppColors.green
                    : (isDark ? AppColors.darkText3 : AppColors.text3),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _MonthPage extends StatelessWidget {
  final AppProvider p;
  final bool isDark;
  const _MonthPage({required this.p, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final surf = isDark ? AppColors.darkSurface : AppColors.white;
    final year = p.currentMonth.hYear;
    final month = p.currentMonth.hMonth;
    final daysInMonth = p.getDaysInMonth(year, month);
    // firstWeekdayOfMonth returns 1=Mon..7=Sun
    // For Mon-based grid: Mon=0..Sun=6
    final rawFirst = p.getFirstWeekdayOfMonth(year, month); // 1=Mon..7=Sun
    final firstOffset = (rawFirst - 1) % 7; // 0=Mon..6=Sun
    final total = firstOffset + daysInMonth;

    return Column(
      children: [
        Container(
          color: surf,
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.0,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            itemCount: total,
            itemBuilder: (ctx, idx) {
              if (idx < firstOffset) return const SizedBox();
              final day = idx - firstOffset + 1;
              return _DayCell(day: day, month: month, year: year,
                  p: p, isDark: isDark);
            },
          ),
        ),
        // Events list
        Expanded(
          child: _EventsList(p: p, isDark: isDark),
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  final int day, month, year;
  final AppProvider p;
  final bool isDark;
  const _DayCell({required this.day, required this.month, required this.year,
      required this.p, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final isToday   = p.isToday(day, month, year);
    final isSelected = p.isSelected(day, month, year);
    final isAyyam   = p.isAyyamAlBid(day);
    final isRamadan = p.isRamadan(month);
    final events    = p.getEventsForDay(day, month, year);

    int weekday = 1;
    int gregDay = 0;
    try {
      final g = p.hijriToGregorian(year, month, day);
      weekday = g.weekday;
      gregDay = g.day;
    } catch (_) {}
    final isFriday = weekday == 5;

    Color bg = Colors.transparent;
    Color textColor = isDark ? AppColors.darkText : AppColors.text;

    if (isToday) {
      bg = AppColors.green;
      textColor = Colors.white;
    } else if (isSelected) {
      bg = AppColors.greenPale;
      textColor = AppColors.green;
    } else if (isAyyam) {
      bg = AppColors.greenPale;
      textColor = AppColors.green;
    } else if (isRamadan) {
      bg = const Color(0xFFFDF8F0);
    }
    if (isFriday && !isToday && !isSelected) textColor = AppColors.green;

    return GestureDetector(
      onTap: () => p.selectDay(HijriDate(year, month, day)),
      onDoubleTap: () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => AddEventScreen())),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: isSelected && !isToday
              ? Border.all(color: AppColors.green, width: 1.5) : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$day',
                  style: GoogleFonts.cairo(
                    fontSize: 13,
                    fontWeight: isToday ? FontWeight.w900 : FontWeight.w600,
                    color: textColor, height: 1,
                  ),
                ),
                if (gregDay > 0)
                  Text('$gregDay',
                    style: TextStyle(fontSize: 7, height: 1,
                      color: isToday ? Colors.white70 : AppColors.text3)),
              ],
            ),
            if (events.isNotEmpty)
              Positioned(
                bottom: 2,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: events.take(3).map((e) => Container(
                    width: 5, height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: isToday ? Colors.white70 : e.color,
                      shape: BoxShape.circle,
                    ),
                  )).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// EVENTS LIST (below monthly grid)
// ════════════════════════════════════════════════════════════
class _EventsList extends StatelessWidget {
  final AppProvider p;
  final bool isDark;
  const _EventsList({required this.p, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final events = p.getEventsForSelectedDay();
    final s = p.selectedDay;
    return Container(
      color: isDark ? AppColors.darkBg : AppColors.bg,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (s != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                '${s.hDay} ${p.getHijriMonthName(s.hMonth, p.locale)} ${s.hYear}',
                style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w700,
                    color: AppColors.text3, letterSpacing: 1),
              ),
            ),
          if (events.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.event_available, size: 40,
                        color: isDark ? AppColors.darkText3 : AppColors.text3),
                    const SizedBox(height: 8),
                    Text(p.label('no_events'),
                        style: GoogleFonts.cairo(fontSize: 12,
                            color: isDark ? AppColors.darkText3 : AppColors.text3)),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: events.length,
                itemBuilder: (ctx, i) => _EventCard(
                  event: events[i], p: p, isDark: isDark,
                  onTap: events[i].isIslamic ? null : () => Navigator.push(ctx,
                    MaterialPageRoute(builder: (_) => AddEventScreen(existingEvent: events[i]))),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final AppEvent event;
  final AppProvider p;
  final bool isDark;
  final VoidCallback? onTap;
  const _EventCard({required this.event, required this.p,
      required this.isDark, this.onTap});

  @override
  Widget build(BuildContext context) {
    final surf = isDark ? AppColors.darkSurface : AppColors.white;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: surf,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: event.color,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14), bottomLeft: Radius.circular(14)),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(event.title(p.locale),
                              style: GoogleFonts.cairo(fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? AppColors.darkText : AppColors.text)),
                            Text(
                              !event.isAllDay
                                  ? '${event.startDate.hour.toString().padLeft(2,'0')}:${event.startDate.minute.toString().padLeft(2,'0')}'
                                  : p.label('all_day'),
                              style: GoogleFonts.cairo(fontSize: 10, color: AppColors.text3)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: event.isIslamic ? AppColors.goldPale : AppColors.greenPale,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          event.isIslamic ? p.label('islamic') : p.label('personal'),
                          style: GoogleFonts.cairo(fontSize: 8, fontWeight: FontWeight.w700,
                            color: event.isIslamic ? AppColors.gold : AppColors.green)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// WEEKLY VIEW
// ════════════════════════════════════════════════════════════
class _WeeklyView extends StatefulWidget {
  final AppProvider p;
  final bool isDark;
  const _WeeklyView({required this.p, required this.isDark});
  @override
  State<_WeeklyView> createState() => _WeeklyViewState();
}

class _WeeklyViewState extends State<_WeeklyView> {
  late ScrollController _timelineCtrl;
  late DateTime _weekStart; // always Monday

  @override
  void initState() {
    super.initState();
    _weekStart = _getMonday(DateTime.now());
    _timelineCtrl = ScrollController(initialScrollOffset: 8 * 60.0);
  }

  @override
  void dispose() { _timelineCtrl.dispose(); super.dispose(); }

  DateTime _getMonday(DateTime d) {
    final diff = d.weekday - 1;
    return DateTime(d.year, d.month, d.day).subtract(Duration(days: diff));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final isDark = widget.isDark;
    final surf = isDark ? AppColors.darkSurface : AppColors.white;

    return Column(
      children: [
        // Week header
        Container(
          color: surf,
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 6),
          child: _buildWeekHeader(p, isDark, surf),
        ),
        // Timeline
        Expanded(
          child: SingleChildScrollView(
            controller: _timelineCtrl,
            child: _buildTimeline(p, isDark, surf),
          ),
        ),
      ],
    );
  }

  Widget _buildWeekHeader(AppProvider p, bool isDark, Color surf) {
    final days = p.locale == 'ar'
        ? ['إث','ث','أر','خ','ج','س','أح']
        : ['Lu','Ma','Me','Je','Ve','Sa','Di'];
    final now = DateTime.now();

    return Row(
      children: [
        // Time gutter
        const SizedBox(width: 48),
        // Days
        ...List.generate(7, (i) {
          final d = _weekStart.add(Duration(days: i));
          final h = HijriDate.fromGregorian(d);
          final isToday = d.year == now.year && d.month == now.month && d.day == now.day;
          final isFri = d.weekday == 5;
          return Expanded(
            child: Column(
              children: [
                Text(days[i],
                  style: GoogleFonts.cairo(
                    fontSize: 9, fontWeight: FontWeight.w700,
                    color: isFri ? AppColors.green
                        : (isDark ? AppColors.darkText3 : AppColors.text3)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    color: isToday ? AppColors.green : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('${d.day}',
                        style: GoogleFonts.cairo(
                          fontSize: 12, fontWeight: FontWeight.w700,
                          color: isToday ? Colors.white
                              : isFri ? AppColors.green
                              : (isDark ? AppColors.darkText : AppColors.text)),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                Text('${h.hDay}',
                  style: GoogleFonts.cairo(fontSize: 8, color: AppColors.text3),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTimeline(AppProvider p, bool isDark, Color surf) {
    final now = DateTime.now();
    const hourHeight = 60.0;
    const totalHeight = 24 * hourHeight;

    return SizedBox(
      height: totalHeight,
      child: Stack(
        children: [
          // Hour lines + labels
          Column(
            children: List.generate(24, (h) {
              final label = '${h.toString().padLeft(2,'0')}:00';
              return SizedBox(
                height: hourHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 48,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 0, right: 6),
                        child: Text(label,
                          style: GoogleFonts.cairo(fontSize: 9,
                              color: isDark ? AppColors.darkText3 : AppColors.text3),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: isDark ? AppColors.darkBorder : AppColors.border,
                              width: 0.5),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
          // Events blocks — built as flat list then added to Stack
          ..._buildEventBlocks(context, p),
          // Current time red line
          if (_isCurrentWeek())
            Positioned(
              top: now.hour * hourHeight + now.minute.toDouble(),
              left: 48 + (MediaQuery.of(context).size.width - 48) / 7 *
                  (now.weekday - 1).toDouble(),
              width: (MediaQuery.of(context).size.width - 48) / 7,
              child: Row(
                children: [
                  Container(width: 8, height: 8,
                      decoration: const BoxDecoration(
                          color: AppColors.red, shape: BoxShape.circle)),
                  Expanded(child: Container(height: 1.5,
                      color: AppColors.red)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildEventBlocks(BuildContext context, AppProvider p) {
    final result = <Widget>[];
    final screenW = MediaQuery.of(context).size.width;
    const hourHeight = 60.0;
    final colW = (screenW - 48) / 7;
    for (int dayIdx = 0; dayIdx < 7; dayIdx++) {
      final d = _weekStart.add(Duration(days: dayIdx));
      final h = HijriDate.fromGregorian(d);
      final events = p.getEventsForDay(h.hDay, h.hMonth, h.hYear)
          .where((e) => !e.isAllDay).toList();
      for (final ev in events) {
        final top = ev.startDate.hour * hourHeight + ev.startDate.minute.toDouble();
        result.add(Positioned(
          top: top,
          left: 48 + colW * dayIdx,
          width: colW - 2,
          height: 50,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: ev.color.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(6),
            ),
            padding: const EdgeInsets.all(4),
            child: Text(ev.title(p.locale),
              style: GoogleFonts.cairo(fontSize: 9, color: Colors.white,
                  fontWeight: FontWeight.w700),
              maxLines: 2, overflow: TextOverflow.ellipsis,
            ),
          ),
        ));
      }
    }
    return result;
  }

    bool _isCurrentWeek() {
    final now = DateTime.now();
    final monday = _getMonday(now);
    return _weekStart.year == monday.year &&
        _weekStart.month == monday.month &&
        _weekStart.day == monday.day;
  }
}

// ════════════════════════════════════════════════════════════
// AGENDA VIEW
// ════════════════════════════════════════════════════════════
class _AgendaView extends StatefulWidget {
  final AppProvider p;
  final bool isDark;
  const _AgendaView({required this.p, required this.isDark});
  @override
  State<_AgendaView> createState() => _AgendaViewState();
}

class _AgendaViewState extends State<_AgendaView> {
  int _days = 60;

  Future<void> _onRefresh() async {
    setState(() => _days = 60);
    await Future.delayed(const Duration(milliseconds: 500));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final isDark = widget.isDark;
    final items = p.getAgendaEvents(days: _days);

    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _onRefresh,
        child: ListView(
          children: [
            SizedBox(
              height: 300,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.event_note, size: 64,
                        color: isDark ? AppColors.darkText3 : AppColors.text3),
                    const SizedBox(height: 12),
                    Text(p.label('no_events'),
                        style: GoogleFonts.cairo(fontSize: 14,
                            color: isDark ? AppColors.darkText3 : AppColors.text3)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.green,
      onRefresh: _onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: items.length + 1,
        itemBuilder: (ctx, idx) {
          if (idx == items.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: TextButton(
                onPressed: () => setState(() => _days += 30),
                child: Text(
                  p.locale == 'ar' ? 'تحميل المزيد' : 'Charger plus',
                  style: GoogleFonts.cairo(color: AppColors.green,
                      fontWeight: FontWeight.w700),
                ),
              ),
            );
          }
          final entry = items[idx];
          return _AgendaGroup(
              date: entry.key, events: entry.value, p: p, isDark: isDark);
        },
      ),
    );
  }
}

class _AgendaGroup extends StatelessWidget {
  final HijriDate date;
  final List<AppEvent> events;
  final AppProvider p;
  final bool isDark;
  const _AgendaGroup({required this.date, required this.events,
      required this.p, required this.isDark});

  @override
  Widget build(BuildContext context) {
    String gregStr = '';
    try {
      final g = date.toGregorian();
      const ms = ['Jan','Fév','Mar','Avr','Mai','Jun','Jul','Aoû','Sep','Oct','Nov','Déc'];
      gregStr = '${g.day} ${ms[g.month-1]}';
    } catch (_) {}

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sticky date header
        Container(
          color: isDark ? AppColors.darkBg : AppColors.bg,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.navy,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${date.hDay} ${p.getHijriMonthName(date.hMonth, p.locale)}',
                  style: GoogleFonts.amiri(fontSize: 13,
                      fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              const SizedBox(width: 8),
              Text(gregStr,
                  style: GoogleFonts.cairo(fontSize: 11, color: AppColors.text3)),
            ],
          ),
        ),
        // Events
        ...events.map((ev) => _AgendaEventRow(event: ev, p: p, isDark: isDark)),
      ],
    );
  }
}

class _AgendaEventRow extends StatelessWidget {
  final AppEvent event;
  final AppProvider p;
  final bool isDark;
  const _AgendaEventRow({required this.event, required this.p, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final surf = isDark ? AppColors.darkSurface : AppColors.white;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      decoration: BoxDecoration(
        color: surf,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: event.color,
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14), bottomLeft: Radius.circular(14)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(event.title(p.locale),
                            style: GoogleFonts.cairo(fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isDark ? AppColors.darkText : AppColors.text)),
                          if (!event.isAllDay)
                            Text(
                              '${event.startDate.hour.toString().padLeft(2,'0')}:${event.startDate.minute.toString().padLeft(2,'0')}',
                              style: GoogleFonts.cairo(fontSize: 10, color: AppColors.text3)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: event.isIslamic ? AppColors.goldPale : AppColors.greenPale,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        event.isIslamic ? p.label('islamic') : p.label('personal'),
                        style: GoogleFonts.cairo(fontSize: 8, fontWeight: FontWeight.w700,
                          color: event.isIslamic ? AppColors.gold : AppColors.green)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
