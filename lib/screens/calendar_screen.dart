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

// ─── Calendar-density helpers ───────────────────────────────────
// Map provider.calendarDensity → tunables for the monthly grid.
// Picked by `_MonthPage`'s GridView so the monthly view re-flows
// when the user picks a different density in settings.

EdgeInsets _gridPaddingForDensity(CalendarDensity d) {
  switch (d) {
    case CalendarDensity.compact:
      return const EdgeInsets.fromLTRB(8, 0, 8, 4);
    case CalendarDensity.normal:
      return const EdgeInsets.fromLTRB(12, 2, 12, 8);
    case CalendarDensity.wide:
      return const EdgeInsets.fromLTRB(14, 6, 14, 14);
  }
}

double _gridSpacingForDensity(CalendarDensity d) {
  switch (d) {
    case CalendarDensity.compact:
      return 0;
    case CalendarDensity.normal:
      return 2;
    case CalendarDensity.wide:
      return 6;
  }
}

double _gridAspectForDensity(CalendarDensity d) {
  switch (d) {
    case CalendarDensity.compact:
      return 1.15; // wider-than-tall → shorter cells
    case CalendarDensity.normal:
      return 1.0;
    case CalendarDensity.wide:
      return 0.9;  // taller cells with more breathing room
  }
}

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
    // Anchor _baseYear/_baseMonth to the provider's region-adjusted
    // today. We watch isLoading so that, if the first build ran while
    // AppProvider.init() was still loading prefs (and `today` was
    // therefore the wrong UAQ-default value), we re-anchor as soon as
    // loading flips false. This is what guarantees today's cell is
    // green on app restart with region = Morocco.
    final p = context.watch<AppProvider>();
    if (!_baseInitialized && !p.isLoading) {
      _baseYear = p.today.hYear;
      _baseMonth = p.today.hMonth;
      _baseInitialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageCtrl.hasClients) {
          _pageCtrl.jumpToPage(_kBaseIndex);
        }
      });
    } else if (!_baseInitialized) {
      // Provisional anchor while init() is still running, so the
      // very first frame doesn't crash on uninitialized fields.
      _baseYear = p.today.hYear;
      _baseMonth = p.today.hMonth;
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
          padding: _gridPaddingForDensity(p.calendarDensity),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: _gridAspectForDensity(p.calendarDensity),
              mainAxisSpacing: _gridSpacingForDensity(p.calendarDensity),
              crossAxisSpacing: _gridSpacingForDensity(p.calendarDensity),
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

    // Today gets a pronounced filled disc; other days no border box —
    // selection is conveyed by the soft greenPale background only.
    final cellRadius = isToday ? BorderRadius.circular(14) : BorderRadius.circular(10);
    return GestureDetector(
      onTap: () => p.selectDay(HijriDate(year, month, day)),
      onDoubleTap: () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => AddEventScreen())),
      child: Container(
        margin: isToday ? const EdgeInsets.all(2) : EdgeInsets.zero,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: cellRadius,
          boxShadow: isToday
              ? [
                  BoxShadow(
                      color: AppColors.green.withValues(alpha: 0.35),
                      blurRadius: 6),
                ]
              : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  TextFormat.toWesternDigits('$day'),
                  style: GoogleFonts.cairo(
                    fontSize: isToday ? 15 : 13,
                    fontWeight: isToday ? FontWeight.w900 : FontWeight.w600,
                    color: textColor,
                    height: 1,
                  ),
                ),
                if (gregDay > 0)
                  Text(
                    TextFormat.toWesternDigits('$gregDay'),
                    style: TextStyle(
                      fontSize: 7,
                      height: 1,
                      color: isToday ? Colors.white70 : AppColors.text3,
                    ),
                  ),
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
      // Tight bottom padding — used to be 80 to clear the old FAB.
      // Without the FAB the list can sit close to the nav bar so
      // there's more vertical room for events.
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
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
                  // Hoist the selected day into a non-nullable local —
                  // closures don't carry the outer null-check
                  // promotion. Falling back to provider.today keeps
                  // the card valid even in the (impossible) case where
                  // events were materialized without a selected day.
                  final hijri = s ?? p.today;
                  DateTime greg;
                  try {
                    greg = p.hijriToGregorian(
                        hijri.hYear, hijri.hMonth, hijri.hDay);
                  } catch (_) {
                    greg = DateTime.now();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _AgendaCard(
                      event: ev,
                      hijri: hijri,
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
          elevation: 2,
          shadowColor: AppColors.green.withValues(alpha: 0.4),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddEventScreen()),
            ),
            child: const SizedBox(
              width: 34,
              height: 34,
              child: Icon(Icons.add_rounded, color: Colors.white, size: 22),
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
// WEEKLY VIEW — Google-Calendar-style time grid.
//
//   * Top row: 7 day headers (weekday name + Hijri day big in a
//     today-circle + Gregorian day small).
//   * Optional all-day strip just below: 7 cells, each carrying
//     small colored chips for that day's all-day events.
//   * Below: vertically-scrollable time grid:
//       - Left gutter: hour labels 00:00 .. 23:00.
//       - 7 day columns, each column = 1 hour-tall cells stacked.
//       - Timed events drawn as positioned colored containers
//         within their day column at top = startHour * hourHeight,
//         height = duration in minutes / 60 * hourHeight.
//   * Horizontal swipe between weeks via a PageView.builder with
//     pure-index arithmetic (truly infinite, no fixed list of
//     weeks).
//   * Tap empty grid cell → AddEventScreen prefilled with that
//     day + that hour. Tap an event → showEventDetails.
//   * Each day links Hijri (region-adjusted via
//     provider.hijriDayOffset) + Gregorian (raw).
// ════════════════════════════════════════════════════════════
class _WeeklyView extends StatefulWidget {
  final AppProvider p;
  final bool isDark;
  const _WeeklyView({required this.p, required this.isDark});
  @override
  State<_WeeklyView> createState() => _WeeklyViewState();
}

class _WeeklyViewState extends State<_WeeklyView> {
  static const int _kBaseIndex = 100000;
  static const double _kHourHeight = 56.0;
  static const double _kGutterWidth = 50.0;

  late final PageController _weekCtrl;
  late DateTime _baseMonday;

  /// Last vertical scroll offset, kept across week swipes so the
  /// user doesn't lose their position when navigating.
  double _vOffset = 8 * _kHourHeight;

  @override
  void initState() {
    super.initState();
    _baseMonday = _mondayOf(DateTime.now());
    _weekCtrl = PageController(initialPage: _kBaseIndex);
  }

  @override
  void dispose() {
    _weekCtrl.dispose();
    super.dispose();
  }

  static DateTime _mondayOf(DateTime d) {
    final diff = d.weekday - 1;
    return DateTime(d.year, d.month, d.day).subtract(Duration(days: diff));
  }

  DateTime _mondayForIndex(int idx) =>
      _baseMonday.add(Duration(days: 7 * (idx - _kBaseIndex)));

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _weekCtrl,
      itemBuilder: (ctx, idx) {
        return _WeekPage(
          monday: _mondayForIndex(idx),
          p: widget.p,
          isDark: widget.isDark,
          hourHeight: _kHourHeight,
          gutterWidth: _kGutterWidth,
          initialVOffset: _vOffset,
          onVScroll: (off) => _vOffset = off,
        );
      },
    );
  }
}

class _WeekPage extends StatefulWidget {
  final DateTime monday;
  final AppProvider p;
  final bool isDark;
  final double hourHeight;
  final double gutterWidth;
  final double initialVOffset;
  final ValueChanged<double> onVScroll;
  const _WeekPage({
    required this.monday,
    required this.p,
    required this.isDark,
    required this.hourHeight,
    required this.gutterWidth,
    required this.initialVOffset,
    required this.onVScroll,
  });

  @override
  State<_WeekPage> createState() => _WeekPageState();
}

class _WeekPageState extends State<_WeekPage> {
  late ScrollController _vCtrl;

  @override
  void initState() {
    super.initState();
    _vCtrl = ScrollController(initialScrollOffset: widget.initialVOffset);
    _vCtrl.addListener(() {
      if (_vCtrl.hasClients) widget.onVScroll(_vCtrl.offset);
    });
  }

  @override
  void dispose() {
    _vCtrl.dispose();
    super.dispose();
  }

  /// Hijri reference for a Gregorian day in the user's region.
  HijriDate _hijriFor(DateTime greg) {
    final offset = widget.p.hijriDayOffset;
    return HijriDate.fromGregorian(greg.subtract(Duration(days: offset)));
  }

  List<AppEvent> _eventsFor(DateTime greg) {
    final h = _hijriFor(greg);
    return widget.p.getEventsForDay(h.hDay, h.hMonth, h.hYear);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final isDark = widget.isDark;
    final surf = isDark ? AppColors.darkSurface : AppColors.white;

    // Pre-compute per-day data once (used by header strip + grid).
    final days = List.generate(
        7, (i) => widget.monday.add(Duration(days: i)));
    final dayEvents = days.map(_eventsFor).toList();
    final allDayPerDay =
        dayEvents.map((evs) => evs.where((e) => e.isAllDay).toList()).toList();
    final timedPerDay =
        dayEvents.map((evs) => evs.where((e) => !e.isAllDay).toList()).toList();

    return Column(
      children: [
        Container(
          color: surf,
          child: _DayHeaderStrip(
            days: days,
            p: p,
            isDark: isDark,
            gutterWidth: widget.gutterWidth,
            hijriFor: _hijriFor,
          ),
        ),
        if (allDayPerDay.any((l) => l.isNotEmpty))
          Container(
            color: surf,
            child: _AllDayStrip(
              days: days,
              allDayPerDay: allDayPerDay,
              p: p,
              isDark: isDark,
              gutterWidth: widget.gutterWidth,
              hijriFor: _hijriFor,
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            controller: _vCtrl,
            child: SizedBox(
              height: 24 * widget.hourHeight,
              child: LayoutBuilder(
                builder: (ctx, constraints) {
                  final colWidth =
                      (constraints.maxWidth - widget.gutterWidth) / 7;
                  return Stack(
                    children: [
                      // Hour gutter + horizontal grid lines + tappable cells.
                      _GridBackground(
                        hourHeight: widget.hourHeight,
                        gutterWidth: widget.gutterWidth,
                        colWidth: colWidth,
                        days: days,
                        isDark: isDark,
                        onCellTap: (dayIdx, hour) async {
                          final greg = days[dayIdx];
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AddEventScreen(
                                initialStart: DateTime(
                                  greg.year,
                                  greg.month,
                                  greg.day,
                                  hour,
                                  0,
                                ),
                              ),
                            ),
                          );
                          if (mounted) setState(() {});
                        },
                      ),
                      // Timed events as positioned colored boxes.
                      for (var dayIdx = 0; dayIdx < 7; dayIdx++)
                        ..._eventBlocks(
                          context: ctx,
                          dayIdx: dayIdx,
                          dayGreg: days[dayIdx],
                          events: timedPerDay[dayIdx],
                          colWidth: colWidth,
                        ),
                      // Current-time red line.
                      if (_isThisWeekToday())
                        _CurrentTimeIndicator(
                          hourHeight: widget.hourHeight,
                          gutterWidth: widget.gutterWidth,
                          colWidth: colWidth,
                          dayIdx: DateTime.now().weekday - 1,
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  bool _isThisWeekToday() {
    final monday = _WeeklyViewState._mondayOf(DateTime.now());
    return monday.year == widget.monday.year &&
        monday.month == widget.monday.month &&
        monday.day == widget.monday.day;
  }

  List<Widget> _eventBlocks({
    required BuildContext context,
    required int dayIdx,
    required DateTime dayGreg,
    required List<AppEvent> events,
    required double colWidth,
  }) {
    final blocks = <Widget>[];
    for (final ev in events) {
      // Confine to the visible day: clip start / end to [00:00, 24:00).
      final dayStart = DateTime(dayGreg.year, dayGreg.month, dayGreg.day);
      final dayEnd = dayStart.add(const Duration(days: 1));
      final s = ev.startDate.isBefore(dayStart) ? dayStart : ev.startDate;
      final e = ev.endDate.isAfter(dayEnd) ? dayEnd : ev.endDate;
      if (!e.isAfter(s)) continue;

      final startMinutes =
          (s.hour * 60 + s.minute).toDouble();
      final endMinutes = (e.hour * 60 + e.minute).toDouble();
      final spanMinutes =
          endMinutes - startMinutes <= 0 ? 60.0 : endMinutes - startMinutes;
      final top = startMinutes / 60.0 * widget.hourHeight;
      final height = (spanMinutes / 60.0 * widget.hourHeight).clamp(22.0, 24 * widget.hourHeight);

      blocks.add(Positioned(
        top: top,
        left: widget.gutterWidth + dayIdx * colWidth + 2,
        width: colWidth - 4,
        height: height,
        child: GestureDetector(
          onTap: () => showEventDetails(
            context: context,
            event: ev,
            hijri: _hijriFor(dayGreg),
            gregorian: dayGreg,
            p: widget.p,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: ev.color.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(6),
              border: Border(
                left: BorderSide(color: ev.color.withValues(alpha: 1.0), width: 3),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ev.title(widget.p.locale),
                  maxLines: height < 36 ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),
                if (height >= 38)
                  Text(
                    TextFormat.toWesternDigits(
                      '${s.hour.toString().padLeft(2, '0')}:${s.minute.toString().padLeft(2, '0')}',
                    ),
                    style: GoogleFonts.cairo(
                      fontSize: 9,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ));
    }
    return blocks;
  }
}

class _DayHeaderStrip extends StatelessWidget {
  final List<DateTime> days;
  final AppProvider p;
  final bool isDark;
  final double gutterWidth;
  final HijriDate Function(DateTime) hijriFor;
  const _DayHeaderStrip({
    required this.days,
    required this.p,
    required this.isDark,
    required this.gutterWidth,
    required this.hijriFor,
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
    final now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 6, 4, 6),
      child: Row(
        children: [
          SizedBox(width: gutterWidth),
          ...List.generate(7, (i) {
            final greg = days[i];
            final hijri = hijriFor(greg);
            final isToday = greg.year == now.year &&
                greg.month == now.month &&
                greg.day == now.day;
            final isFri = greg.weekday == 5;
            return Expanded(
              child: Column(
                children: [
                  Text(
                    dayLabels[i],
                    style: GoogleFonts.cairo(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: isFri
                          ? AppColors.green
                          : (isDark ? AppColors.darkText3 : AppColors.text3),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isToday ? AppColors.green : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        TextFormat.toWesternDigits('${hijri.hDay}'),
                        style: GoogleFonts.amiri(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isToday
                              ? Colors.white
                              : (isDark ? AppColors.darkText : AppColors.navy),
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
        ],
      ),
    );
  }
}

class _AllDayStrip extends StatelessWidget {
  final List<DateTime> days;
  final List<List<AppEvent>> allDayPerDay;
  final AppProvider p;
  final bool isDark;
  final double gutterWidth;
  final HijriDate Function(DateTime) hijriFor;
  const _AllDayStrip({
    required this.days,
    required this.allDayPerDay,
    required this.p,
    required this.isDark,
    required this.gutterWidth,
    required this.hijriFor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: gutterWidth,
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                p.locale == 'ar'
                    ? 'كل اليوم'
                    : p.locale == 'es'
                        ? 'Todo el día'
                        : p.locale == 'en'
                            ? 'All day'
                            : 'Toute la j.',
                textAlign: TextAlign.right,
                style: GoogleFonts.cairo(
                    fontSize: 9, color: AppColors.text3),
              ),
            ),
          ),
          ...List.generate(7, (i) {
            final evs = allDayPerDay[i];
            return Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: evs.take(3).map((ev) {
                  return GestureDetector(
                    onTap: () => showEventDetails(
                      context: context,
                      event: ev,
                      hijri: hijriFor(days[i]),
                      gregorian: days[i],
                      p: p,
                    ),
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 2, vertical: 1),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: ev.color.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        ev.title(p.locale),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.cairo(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _GridBackground extends StatelessWidget {
  final double hourHeight;
  final double gutterWidth;
  final double colWidth;
  final List<DateTime> days;
  final bool isDark;
  final void Function(int dayIdx, int hour) onCellTap;
  const _GridBackground({
    required this.hourHeight,
    required this.gutterWidth,
    required this.colWidth,
    required this.days,
    required this.isDark,
    required this.onCellTap,
  });

  @override
  Widget build(BuildContext context) {
    final lineColor =
        isDark ? AppColors.darkBorder : AppColors.border;
    return Stack(
      children: [
        // Hour gutter + horizontal lines under each hour.
        Column(
          children: List.generate(24, (h) {
            return SizedBox(
              height: hourHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: gutterWidth,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6, top: 0),
                      child: Text(
                        TextFormat.toWesternDigits(
                          '${h.toString().padLeft(2, '0')}:00',
                        ),
                        textAlign: TextAlign.right,
                        style: GoogleFonts.cairo(
                          fontSize: 9,
                          color: AppColors.text3,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: lineColor, width: 0.5),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
        // 7 day columns: vertical separators + tappable cells.
        Positioned.fill(
          left: gutterWidth,
          child: Row(
            children: List.generate(7, (dayIdx) {
              return SizedBox(
                width: colWidth,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: lineColor, width: 0.5),
                    ),
                  ),
                  child: Column(
                    children: List.generate(24, (h) {
                      return SizedBox(
                        height: hourHeight,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () => onCellTap(dayIdx, h),
                        ),
                      );
                    }),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _CurrentTimeIndicator extends StatelessWidget {
  final double hourHeight;
  final double gutterWidth;
  final double colWidth;
  final int dayIdx;
  const _CurrentTimeIndicator({
    required this.hourHeight,
    required this.gutterWidth,
    required this.colWidth,
    required this.dayIdx,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final top = (now.hour * 60 + now.minute) / 60.0 * hourHeight;
    return Positioned(
      top: top - 1,
      left: gutterWidth + dayIdx * colWidth,
      width: colWidth,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.red,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Container(height: 1.5, color: AppColors.red),
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
