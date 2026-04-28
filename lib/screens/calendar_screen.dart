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
  // ── Infinite PageView state ─────────────────────────────────
  //
  // The monthly view is paginated by [PageView.builder] and acts as a
  // truly infinite horizontal scroll: there is no itemCount, and each
  // page index maps deterministically to a Hijri (year, month) tuple
  // via the formula in [_hijriForIndex] using nothing but [monthIndex]
  // arithmetic — never string sorting, never Gregorian DateTime
  // arithmetic.
  //
  // _baseIndex is placed deep into the page space so the user can
  // swipe back tens of thousands of months before the controller would
  // ever clamp.
  static const int _kBaseIndex = 100000;

  late final PageController _pageCtrl;
  late int _baseYear;
  late int _baseMonth;
  bool _baseInitialized = false;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(initialPage: _kBaseIndex);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Region offset is loaded asynchronously by AppProvider.init(). We
    // wait until the provider is available, then anchor _baseYear /
    // _baseMonth to the provider's region-adjusted today so the page
    // at _kBaseIndex truly represents "today" in the user's region —
    // including across app restarts.
    if (!_baseInitialized) {
      final p = context.read<AppProvider>();
      _baseYear = p.today.hYear;
      _baseMonth = p.today.hMonth;
      _baseInitialized = true;
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  /// Pure index-based mapping. Given any [pageIndex] return the Hijri
  /// (year, monthIndex) it represents.
  ///
  /// Algorithm (per spec):
  ///   offset      = pageIndex - baseIndex
  ///   m0          = baseMonth + offset - 1            // 0-based
  ///   yearOffset  = floor(m0 / 12)                    // floor div, not trunc
  ///   year        = baseYear + yearOffset
  ///   month       = (m0 mod 12) + 1                   // 1..12
  ///
  /// Dart's `%` is mathematical (always non-negative when divisor
  /// is positive) so `(-1) % 12 == 11` — exactly what we want for
  /// going one month before Muharram.
  ///
  /// Dart's `~/` truncates toward zero, which would break negative
  /// offsets. We deliberately use `(m0 / 12).floor()` instead.
  ({int year, int month}) _hijriForIndex(int pageIndex) {
    final offset = pageIndex - _kBaseIndex;
    final m0 = _baseMonth + offset - 1;
    final yearOffset = (m0 / 12).floor();
    final year = _baseYear + yearOffset;
    final month = (m0 % 12) + 1;
    return (year: year, month: month);
  }

  void _onPageChanged(int idx, AppProvider p) {
    final hm = _hijriForIndex(idx);
    p.setCurrentMonth(hm.year, hm.month);
  }

  void _jumpToToday(AppProvider p) {
    p.goToToday();
    // Re-anchor the base in case the region offset moved today's
    // (year, month) tuple; otherwise the baseIndex page would still
    // map to the old base and the visible page would be off by N.
    _baseYear = p.today.hYear;
    _baseMonth = p.today.hMonth;
    if (_pageCtrl.hasClients) {
      _pageCtrl.jumpToPage(_kBaseIndex);
    }
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
          _TodayButton(p: p, isDark: isDark, onTap: () => _jumpToToday(p)),
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
        return _MonthlyView(
          pageCtrl: _pageCtrl,
          hijriForIndex: _hijriForIndex,
          onPageChanged: (idx) => _onPageChanged(idx, p),
          p: p,
          isDark: isDark,
        );
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
    // Match the converter screen's pill style: today-icon + label.
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.green, width: 1.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.today_rounded,
                size: 14, color: AppColors.green),
            const SizedBox(width: 5),
            Text(
              p.label('today'),
              style: GoogleFonts.cairo(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.green,
              ),
            ),
          ],
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

  /// Pure-index → Hijri month mapping. Provided by the parent so the
  /// PageView itself never has to know about months — it only knows
  /// about indices.
  final ({int year, int month}) Function(int pageIndex) hijriForIndex;
  final ValueChanged<int> onPageChanged;

  final AppProvider p;
  final bool isDark;
  const _MonthlyView({
    required this.pageCtrl,
    required this.hijriForIndex,
    required this.onPageChanged,
    required this.p,
    required this.isDark,
  });

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
        // Truly infinite PageView. No itemCount, no fixed list of months.
        // Each itemBuilder call computes its own (year, month) from the
        // index via Hijri month-arithmetic — no Gregorian DateTime, no
        // string sort, no shared mutable provider state on the page
        // itself.
        Expanded(
          child: PageView.builder(
            controller: pageCtrl,
            onPageChanged: onPageChanged,
            itemBuilder: (ctx, idx) {
              final hm = hijriForIndex(idx);
              return _MonthPage(
                year: hm.year,
                month: hm.month,
                p: p,
                isDark: isDark,
              );
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
  /// Hijri month rendered by THIS page. Computed by the parent from
  /// the page index via index arithmetic — never read from the
  /// provider's currentMonth, so each page in the infinite PageView
  /// is self-consistent regardless of swipe order.
  final int year;
  final int month;
  final AppProvider p;
  final bool isDark;
  const _MonthPage({
    required this.year,
    required this.month,
    required this.p,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final surf = isDark ? AppColors.darkSurface : AppColors.white;
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
    // Daily adhkar (morning / evening / sleep) appear on every single
    // day. Showing dots for them would clutter the entire month grid,
    // so they're hidden from the monthly view's day cells. They still
    // show up normally in the events list below the grid.
    final events = p
        .getEventsForDay(day, month, year)
        .where((e) =>
            e.id != 'adhkar_sabah_${year}_$month' &&
            e.id != 'adhkar_masaa_${year}_$month' &&
            e.id != 'adhkar_nawm_${year}_$month' &&
            !e.id.startsWith('adhkar_sabah') &&
            !e.id.startsWith('adhkar_masaa') &&
            !e.id.startsWith('adhkar_nawm'))
        .toList();

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
              child: _SelectedDayHeader(p: p, isDark: isDark, day: s),
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
                itemBuilder: (ctx, i) {
                  final ev = events[i];
                  // Always tap-to-show details. The details sheet hosts
                  // the Edit button (and shows it only for non-Islamic).
                  DateTime greg;
                  try {
                    greg = p.hijriToGregorian(s.hYear, s.hMonth, s.hDay);
                  } catch (_) {
                    greg = DateTime.now();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _AgendaCard(
                      event: ev,
                      hijri: s,
                      gregorian: greg,
                      p: p,
                      isDark: isDark,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Header shown above the events list in the monthly view.
/// Layout: "11 ذو القعدة 1447 ▪ 28/4/2026" on the right (RTL-aware), with
/// a small + button on the far left that opens the new-event screen
/// (replacing the old global FAB).
class _SelectedDayHeader extends StatelessWidget {
  final AppProvider p;
  final bool isDark;
  final HijriDate day;
  const _SelectedDayHeader({
    required this.p,
    required this.isDark,
    required this.day,
  });

  @override
  Widget build(BuildContext context) {
    final loc = p.locale;
    DateTime g;
    try {
      g = p.hijriToGregorian(day.hYear, day.hMonth, day.hDay);
    } catch (_) {
      g = DateTime.now();
    }
    final hijriPart = TextFormat.toWesternDigits(
      '${day.hDay} ${p.getHijriMonthName(day.hMonth, loc)} ${day.hYear}',
    );
    final gregPart = TextFormat.formatGregorianNumeric(g);
    return Row(
      children: [
        // Inline "+" — replaces the old floating FAB.
        Material(
          color: AppColors.green,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddEventScreen()),
            ),
            child: const SizedBox(
              width: 26,
              height: 26,
              child: Icon(Icons.add_rounded, color: Colors.white, size: 18),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.green,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$hijriPart  ▪  $gregPart',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ],
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
  late DateTime _weekStart; // always Monday in Gregorian terms

  @override
  void initState() {
    super.initState();
    _weekStart = _getMonday(DateTime.now());
  }

  DateTime _getMonday(DateTime d) {
    final diff = d.weekday - 1;
    return DateTime(d.year, d.month, d.day).subtract(Duration(days: diff));
  }

  void _shiftWeek(int weeks) {
    setState(() => _weekStart = _weekStart.add(Duration(days: 7 * weeks)));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final isDark = widget.isDark;
    return Column(
      children: [
        _WeekStrip(
          weekStart: _weekStart,
          p: p,
          isDark: isDark,
          onPrev: () => _shiftWeek(-1),
          onNext: () => _shiftWeek(1),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 6, bottom: 80),
            itemCount: 7,
            itemBuilder: (ctx, i) {
              final greg = _weekStart.add(Duration(days: i));
              final hijri = HijriDate.fromGregorian(
                  greg.subtract(Duration(days: p.hijriDayOffset)));
              final events =
                  p.getEventsForDay(hijri.hDay, hijri.hMonth, hijri.hYear);
              return _DaySection(
                hijri: hijri,
                gregorian: greg,
                events: events,
                p: p,
                isDark: isDark,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Top mini-strip: 7 day pills with weekday name + Hijri day big +
/// Gregorian day small. Today's pill is filled green.
class _WeekStrip extends StatelessWidget {
  final DateTime weekStart;
  final AppProvider p;
  final bool isDark;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _WeekStrip({
    required this.weekStart,
    required this.p,
    required this.isDark,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final loc = p.locale;
    final dayLabels = loc == 'ar'
        ? ['إث', 'ث', 'أر', 'خ', 'ج', 'س', 'أح']
        : loc == 'fr'
            ? ['Lu', 'Ma', 'Me', 'Je', 'Ve', 'Sa', 'Di']
            : loc == 'es'
                ? ['Lu', 'Ma', 'Mi', 'Ju', 'Vi', 'Sá', 'Do']
                : ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
    final surf = isDark ? AppColors.darkSurface : AppColors.white;
    final now = DateTime.now();
    return Container(
      color: surf,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded,
                color: AppColors.text3, size: 20),
            onPressed: onPrev,
            visualDensity: VisualDensity.compact,
          ),
          ...List.generate(7, (i) {
            final greg = weekStart.add(Duration(days: i));
            final hijri = HijriDate.fromGregorian(
                greg.subtract(Duration(days: p.hijriDayOffset)));
            final isToday = greg.year == now.year &&
                greg.month == now.month &&
                greg.day == now.day;
            return Expanded(
              child: Column(
                children: [
                  Text(
                    dayLabels[i],
                    style: GoogleFonts.cairo(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppColors.darkText3
                          : AppColors.text3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isToday ? AppColors.green : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        TextFormat.toWesternDigits('${hijri.hDay}'),
                        style: GoogleFonts.amiri(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isToday
                              ? Colors.white
                              : (isDark
                                  ? AppColors.darkText
                                  : AppColors.navy),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    TextFormat.toWesternDigits('${greg.day}'),
                    style: GoogleFonts.cairo(
                      fontSize: 9,
                      color: AppColors.text3,
                    ),
                  ),
                ],
              ),
            );
          }),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded,
                color: AppColors.text3, size: 20),
            onPressed: onNext,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

/// One day section in the weekly list: a green date pill (Hijri ▪
/// Gregorian) + agenda-style colored event cards.
class _DaySection extends StatelessWidget {
  final HijriDate hijri;
  final DateTime gregorian;
  final List<AppEvent> events;
  final AppProvider p;
  final bool isDark;
  const _DaySection({
    required this.hijri,
    required this.gregorian,
    required this.events,
    required this.p,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DateBadge(hijri: hijri, gregorian: gregorian, p: p),
          const SizedBox(height: 8),
          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
              child: Text(
                p.label('no_events'),
                style: GoogleFonts.cairo(
                    fontSize: 11, color: AppColors.text3),
              ),
            )
          else
            ...events.map(
              (ev) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _AgendaCard(
                  event: ev,
                  hijri: hijri,
                  gregorian: gregorian,
                  p: p,
                  isDark: isDark,
                ),
              ),
            ),
        ],
      ),
    );
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

// ════════════════════════════════════════════════════════════
// AGENDA PRIMITIVES (date badge + card) — shared between weekly
// and agenda views. Matches the design in the attached screenshot:
//   - Green pill at the top: "11 ذو القعدة 1447 ▪ 28/4/2026"
//   - White rounded cards with a coloured leading bar (event color),
//     centered title + emoji, time below, and a category chip on
//     the trailing side.
// ════════════════════════════════════════════════════════════

class _DateBadge extends StatelessWidget {
  final HijriDate hijri;
  final DateTime gregorian;
  final AppProvider p;
  const _DateBadge({
    required this.hijri,
    required this.gregorian,
    required this.p,
  });

  @override
  Widget build(BuildContext context) {
    final loc = p.locale;
    final hijriPart = TextFormat.toWesternDigits(
      '${hijri.hDay} ${p.getHijriMonthName(hijri.hMonth, loc)} ${hijri.hYear}',
    );
    final gregPart = TextFormat.formatGregorianNumeric(gregorian);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.green,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '$hijriPart  ▪  $gregPart',
          style: GoogleFonts.cairo(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

class _AgendaCard extends StatelessWidget {
  final AppEvent event;
  final HijriDate hijri;
  final DateTime gregorian;
  final AppProvider p;
  final bool isDark;
  const _AgendaCard({
    required this.event,
    required this.hijri,
    required this.gregorian,
    required this.p,
    required this.isDark,
  });

  String _timeLabel(String loc) {
    if (event.isAllDay) {
      return loc == 'ar' ? 'طوال اليوم'
          : loc == 'es' ? 'Todo el día'
          : loc == 'en' ? 'All day'
          : 'Toute la journée';
    }
    String two(int n) => n.toString().padLeft(2, '0');
    return TextFormat.toWesternDigits(
      '${two(event.startDate.hour)}:${two(event.startDate.minute)}',
    );
  }

  String _categoryLabel(String loc) {
    if (event.isIslamic) {
      return loc == 'ar' ? 'إسلامي'
          : loc == 'es' ? 'Islámico'
          : loc == 'en' ? 'Islamic'
          : 'Islamique';
    }
    const map = <String, List<String>>{
      'personal':  ['شخصي',  'Personnel', 'Personal',  'Personal'],
      'family':    ['عائلي',  'Famille',   'Family',    'Familia'],
      'social':    ['اجتماعي','Social',    'Social',    'Social'],
      'work':      ['عمل',    'Travail',   'Work',      'Trabajo'],
      'health':    ['صحة',    'Santé',     'Health',    'Salud'],
      'religious': ['ديني',   'Religieux', 'Religious', 'Religioso'],
    };
    final entry = map[event.category];
    if (entry == null) return '';
    final idx = loc == 'ar' ? 0 : loc == 'fr' ? 1 : loc == 'en' ? 2 : 3;
    return entry[idx];
  }

  Color get _chipBg => event.isIslamic
      ? AppColors.greenPale
      : (event.color.value == AppColors.gold.value
          ? AppColors.goldPale
          : event.color.value == AppColors.red.value
              ? const Color(0xFFFDEAEA)
              : AppColors.bluePale);

  Color get _chipFg => event.isIslamic ? AppColors.green : event.color;

  @override
  Widget build(BuildContext context) {
    final loc = p.locale;
    final surf = isDark ? AppColors.darkSurface : AppColors.white;
    return GestureDetector(
      onTap: () => showEventDetails(
        context: context,
        event: event,
        hijri: hijri,
        gregorian: gregorian,
        p: p,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: surf,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05), blurRadius: 6),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Leading colored bar — under RTL the start side is the
              // right edge, which matches the screenshot.
              Container(
                width: 5,
                decoration: BoxDecoration(
                  color: event.color,
                  borderRadius: const BorderRadiusDirectional.only(
                    topStart: Radius.circular(14),
                    bottomStart: Radius.circular(14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (event.emoji.isNotEmpty) ...[
                            Text(event.emoji,
                                style: const TextStyle(fontSize: 18)),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Text(
                              event.title(loc),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.cairo(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? AppColors.darkText
                                    : AppColors.text,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _timeLabel(loc),
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _chipBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _categoryLabel(loc),
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _chipFg,
                    ),
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
// EVENT DETAILS BOTTOM SHEET
// ════════════════════════════════════════════════════════════

void showEventDetails({
  required BuildContext context,
  required AppEvent event,
  required HijriDate hijri,
  required DateTime gregorian,
  required AppProvider p,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _EventDetailsSheet(
      event: event,
      hijri: hijri,
      gregorian: gregorian,
      p: p,
    ),
  );
}

class _EventDetailsSheet extends StatelessWidget {
  final AppEvent event;
  final HijriDate hijri;
  final DateTime gregorian;
  final AppProvider p;
  const _EventDetailsSheet({
    required this.event,
    required this.hijri,
    required this.gregorian,
    required this.p,
  });

  String _editLabel(String loc) {
    return loc == 'ar' ? 'تعديل'
        : loc == 'es' ? 'Editar'
        : loc == 'en' ? 'Edit'
        : 'Modifier';
  }

  String _closeLabel(String loc) {
    return loc == 'ar' ? 'إغلاق'
        : loc == 'es' ? 'Cerrar'
        : loc == 'en' ? 'Close'
        : 'Fermer';
  }

  String _timeLabel(String loc) {
    if (event.isAllDay) {
      return loc == 'ar' ? 'طوال اليوم'
          : loc == 'es' ? 'Todo el día'
          : loc == 'en' ? 'All day'
          : 'Toute la journée';
    }
    String two(int n) => n.toString().padLeft(2, '0');
    return TextFormat.toWesternDigits(
      '${two(event.startDate.hour)}:${two(event.startDate.minute)} '
      '— ${two(event.endDate.hour)}:${two(event.endDate.minute)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = p.locale;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (event.emoji.isNotEmpty) ...[
                  Text(event.emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    event.title(loc),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cairo(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _DateBadge(hijri: hijri, gregorian: gregorian, p: p),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.schedule_rounded,
                    size: 18, color: AppColors.text3),
                const SizedBox(width: 6),
                Text(
                  _timeLabel(loc),
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding:
                          const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      _closeLabel(loc),
                      style: GoogleFonts.cairo(
                        color: AppColors.text2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                if (!event.isIslamic) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.green,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                AddEventScreen(existingEvent: event),
                          ),
                        );
                      },
                      icon: const Icon(Icons.edit_rounded, size: 16),
                      label: Text(
                        _editLabel(loc),
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AgendaGroup extends StatelessWidget {
  final HijriDate date;
  final List<AppEvent> events;
  final AppProvider p;
  final bool isDark;
  const _AgendaGroup({
    required this.date,
    required this.events,
    required this.p,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    DateTime greg;
    try {
      greg = p.hijriToGregorian(date.hYear, date.hMonth, date.hDay);
    } catch (_) {
      greg = DateTime.now();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DateBadge(hijri: date, gregorian: greg, p: p),
          const SizedBox(height: 10),
          ...events.map(
            (ev) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _AgendaCard(
                event: ev,
                hijri: date,
                gregorian: greg,
                p: p,
                isDark: isDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
