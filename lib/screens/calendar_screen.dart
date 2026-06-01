import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/event_model.dart';
import '../providers/app_provider.dart';
import '../utils/hijri_utils.dart';
import '../utils/hijri_kernel.dart' as hijri_kernel;
import '../utils/text_format.dart';
import '../theme.dart';
import '../widgets/hijri_source_badge.dart';
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

  /// Tagged on the live [_AgendaView] so the "Today" button in the
  /// top bar can reach into its state and trigger a smooth scroll
  /// back to today without rebuilding the agenda.
  final GlobalKey<_AgendaViewState> _agendaKey =
      GlobalKey<_AgendaViewState>();

  /// Same idea for the weekly view — gives the "Today" button a
  /// handle to jump back to the current week AND scroll the
  /// timeline down to the current hour, instead of just
  /// re-anchoring the monthly view (which has no effect on the
  /// weekly PageView).
  final GlobalKey<_WeeklyViewState> _weeklyKey =
      GlobalKey<_WeeklyViewState>();

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
    // Smooth-scroll the agenda back to today when it's the active
    // view. Off-screen views (monthly / weekly) are unaffected; the
    // call is a no-op when the agenda's ScrollController hasn't
    // attached to a viewport yet.
    if (p.viewMode == CalendarViewMode.agenda) {
      _agendaKey.currentState?.scrollToToday();
    }
    // Phase 2/3 — weekly view's "Today" needs more than a page
    // reset: bring the visible PageView back to the current
    // week AND scroll the timeline to the current hour. The
    // monthly-view re-anchoring above (`_pageCtrl.jumpToPage`)
    // doesn't affect the weekly PageView, which lives inside
    // its own state.
    if (p.viewMode == CalendarViewMode.weekly) {
      _weeklyKey.currentState?.jumpToNowWeek();
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
      // Route through the provider so the top-bar Gregorian label
      // honours the active region offset (Morocco = UAQ + 1 day).
      gregFirst = p.hijriToGregorian(m.hYear, m.hMonth, 1);
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
                // Phase-7 improvement 5 — Hijri month name +
                // small source-status dot inline. Replaces the
                // separate verbose badge row that used to sit
                // below the Gregorian line, saving vertical
                // space and keeping the source signal next to
                // the date it qualifies. The dot opens the
                // same info sheet on tap.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        TextFormat.toWesternDigits(monthName),
                        style: appFont(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? AppColors.darkText
                              : AppColors.navy,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    HijriSourceDot(darkOverride: isDark),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  gregLabel,
                  style: appFont(
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
                      style: appFont(
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
        return _WeeklyView(key: _weeklyKey, p: p, isDark: isDark);
      case CalendarViewMode.agenda:
        return _AgendaView(key: _agendaKey, p: p, isDark: isDark);
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
            Icon(Icons.today_rounded,
                size: 14, color: AppColors.green),
            const SizedBox(width: 5),
            Text(
              p.label('today'),
              style: appFont(
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
              style: appFont(
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
    // day. Showing them here would clutter the entire monthly view —
    // both the dots inside this day cell and the per-day events list
    // below the grid — so we hide them from BOTH places. They still
    // continue to fire notifications and show up normally in the
    // Agenda view.
    final events = p
        .getEventsForDay(day, month, year)
        .where((e) => !p.isDailyAdhkar(e.id))
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
      onDoubleTap: () {
        // Double-tap on a monthly cell selects the day AND opens the
        // New Event screen prefilled with that day. The Hijri (year,
        // month, day) we tapped is converted via the provider so the
        // resulting Gregorian instant honours the active region's
        // offset (e.g. Morocco = UAQ + 1 day).
        p.selectDay(HijriDate(year, month, day));
        DateTime g;
        try {
          g = p.hijriToGregorian(year, month, day);
        } catch (_) {
          g = DateTime.now();
        }
        // Default time = 09:00 local on the picked day.
        final start = DateTime(g.year, g.month, g.day, 9, 0);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AddEventScreen(initialStart: start),
          ),
        );
      },
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
                  style: appFont(
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
    // Same exclusion as the day cells above the list: morning /
    // evening / sleep adhkar are intentionally hidden from the
    // monthly view to keep it uncluttered. They still fire
    // notifications and remain visible in the Agenda view.
    final events = p
        .getEventsForSelectedDay()
        .where((e) => !p.isDailyAdhkar(e.id))
        .toList();
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
                        style: appFont(fontSize: 12,
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
                    padding: const EdgeInsets.only(bottom: 10),
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
            // The selected-day header "+" prefills the New Event
            // screen with whichever day the user has currently
            // selected (falls back to the regional today). The
            // Hijri date is resolved via [hijriToGregorian] which
            // already accounts for the active region's offset.
            onTap: () {
              DateTime start;
              try {
                start = p.hijriToGregorian(
                    day.hYear, day.hMonth, day.hDay);
              } catch (_) {
                start = DateTime.now();
              }
              start = DateTime(start.year, start.month, start.day, 9, 0);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddEventScreen(initialStart: start),
                ),
              );
            },
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
              style: appFont(
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
  // Phase-1 task 5 — hour cell bumped from 56 → 64 dp. The
  // extra 8 dp per row gives events with a 30-40 min span room
  // to render their title + time on two lines without
  // truncation, and matches the density users expect from
  // Google Calendar's weekly view.
  static const double _kHourHeight = 64.0;
  static const double _kGutterWidth = 50.0;

  late final PageController _weekCtrl;
  late DateTime _baseMonday;

  /// Last vertical scroll offset, kept across week swipes so the
  /// user doesn't lose their position when navigating. Defaults
  /// to the "now" position computed in [initState] (Phase-1
  /// task 2) — `_nowOffset` puts the current hour 80 dp below
  /// the top of the timeline so the user lands on the timeline
  /// already showing what's happening right now instead of
  /// always at 8 AM.
  late double _vOffset;

  @override
  void initState() {
    super.initState();
    _baseMonday = _mondayOf(DateTime.now());
    _weekCtrl = PageController(initialPage: _kBaseIndex);
    _vOffset = _nowOffset();
  }

  /// Returns the initial scroll offset that lands the timeline
  /// on the current hour, with ~80 dp of context above it (so
  /// the user can see what JUST happened, not only what's next).
  /// Clamped to non-negative so very-early-morning launches
  /// (00:00-01:15) don't try to scroll above the top of the
  /// timeline.
  double _nowOffset() {
    final now = DateTime.now();
    final minutes = now.hour * 60 + now.minute;
    final raw = minutes / 60.0 * _kHourHeight - 80;
    return raw < 0 ? 0 : raw;
  }

  /// Phase 2/3 — public entry point for the "Today" button in
  /// the calendar top bar. Two effects:
  ///   1. Animates the PageView back to the current week.
  ///   2. Re-sets `_vOffset` to the "now" position so any
  ///      future page rebuilds land on the current hour.
  /// Calling from `_CalendarScreenState._jumpToToday`.
  ///
  /// Note: existing live `_WeekPage` instances have their own
  /// scroll controllers that were initialised at construction
  /// time. We can't reach them from here without an extra
  /// GlobalKey per page, so the immediate-visible page keeps
  /// its current vertical scroll until the user navigates away
  /// and back. The PageView jump is the most important effect
  /// (returns the user to "now's week"); the vertical scroll
  /// re-snap is a best-effort polish.
  void jumpToNowWeek() {
    _baseMonday = _mondayOf(DateTime.now());
    _vOffset = _nowOffset();
    if (_weekCtrl.hasClients) {
      _weekCtrl.animateToPage(
        _kBaseIndex,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
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
  /// Delegates to the kernel so the weekly view sees the same
  /// Greg↔Hijri mapping as the monthly / agenda views.
  HijriDate _hijriFor(DateTime greg) =>
      hijri_kernel.hijriFromGreg(greg, widget.p.hijriDayOffset);

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
                        onCellTap: (dayIdx, minutesFromMidnight) async {
                          // Phase-1 task 3 — the tap reports
                          // a 15-minute-snapped minutes value
                          // (e.g. 14:35 → 14:30). Split it back
                          // into hour + minute for the
                          // `AddEventScreen` initialStart.
                          final greg = days[dayIdx];
                          final h = minutesFromMidnight ~/ 60;
                          final m = minutesFromMidnight % 60;
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AddEventScreen(
                                initialStart: DateTime(
                                  greg.year,
                                  greg.month,
                                  greg.day,
                                  h,
                                  m,
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
    // Phase-1 task 1 — proper overlap handling.
    //
    // Old behaviour: every event got the full column width and
    // was positioned by start-time alone. Two events at the
    // same hour painted on top of each other — the upper one
    // ate the lower one's tap target and visually masked it
    // entirely. This was the most-reported pain point on the
    // weekly view.
    //
    // New behaviour: events that overlap in time get
    // side-by-side lanes within the day column, à la Google
    // Calendar / Outlook. The helper `_layoutEventLanes` runs a
    // greedy lane-assignment pass followed by a cluster
    // grouping pass; each event gets `(lane, totalLanes)` and
    // we render at `x = laneIdx * (colW / totalLanes)` with
    // width `colW / totalLanes`.
    final dayStart = DateTime(dayGreg.year, dayGreg.month, dayGreg.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final positioned = _layoutEventLanes(events, dayStart, dayEnd);

    final blocks = <Widget>[];
    for (final p in positioned) {
      final ev = p.event;
      final s = p.start;
      final e = p.end;

      final startMinutes = (s.hour * 60 + s.minute).toDouble();
      // If the clipped end landed exactly on `dayEnd` (i.e. the
      // event runs to-or-past midnight), express that as 24*60
      // minutes so the height calculation reaches the bottom of
      // the timeline instead of collapsing to 0.
      final endMinutes = e.isAtSameMomentAs(dayEnd)
          ? 24.0 * 60
          : (e.hour * 60 + e.minute).toDouble();
      final spanMinutes =
          endMinutes - startMinutes <= 0 ? 60.0 : endMinutes - startMinutes;
      final top = startMinutes / 60.0 * widget.hourHeight;
      final height = (spanMinutes / 60.0 * widget.hourHeight)
          .clamp(22.0, 24 * widget.hourHeight);

      // Lane-aware horizontal positioning. When `totalLanes ==
      // 1` (the common case — no overlap), the math reduces to
      // the previous `left = colStart + 2 / width = colW - 4`.
      final laneW = colWidth / p.totalLanes;
      final colStart = widget.gutterWidth + dayIdx * colWidth;
      final left = colStart + p.lane * laneW + 1;
      final width = laneW - 2;

      blocks.add(Positioned(
        top: top,
        left: left,
        width: width,
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
                left: BorderSide(
                  color: ev.color.withValues(alpha: 1.0),
                  width: 3,
                ),
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
                  style: appFont(
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
                    style: appFont(
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

/// One event positioned in the day column with its assigned
/// horizontal lane. Produced by [_layoutEventLanes] and
/// consumed by `_eventBlocks` in [_WeekPageState].
class _PositionedEvent {
  /// The original event (unmodified).
  final AppEvent event;

  /// Start instant clipped to the visible day.
  final DateTime start;

  /// End instant clipped to the visible day. Note this may be
  /// EQUAL to `dayEnd` (the next day's 00:00) for events that
  /// span the full day — callers should compare with
  /// `isAtSameMomentAs(dayEnd)` to render the height correctly
  /// instead of treating it as `00:00 -> hour 0`.
  final DateTime end;

  /// 0-based horizontal lane within the event's overlap
  /// cluster. `0` is the leftmost (or rightmost in RTL) lane.
  final int lane;

  /// Number of lanes the event's cluster uses. Same value for
  /// every event in the cluster, so dividing `colWidth` by it
  /// gives a width that lines up cleanly.
  ///
  /// For an event with no overlap at all, `totalLanes == 1`
  /// and the layout reduces to the pre-Phase-1 single-column
  /// behaviour.
  final int totalLanes;

  const _PositionedEvent(
    this.event,
    this.start,
    this.end,
    this.lane,
    this.totalLanes,
  );
}

/// Pure helper — given a day's events and the day's [00:00,
/// 24:00) window, returns each event positioned into a
/// horizontal lane so overlapping events render side-by-side
/// instead of stacked.
///
/// Algorithm (mirrors Google Calendar / Outlook):
///   1. CLIP each event to the visible day window; drop those
///      that don't intersect.
///   2. SORT by start (ties broken by end) so the greedy lane
///      assignment is deterministic.
///   3. LANE ASSIGNMENT: walk events in order; each one drops
///      into the first lane whose previous occupant ended
///      before this event starts. A new lane is allocated when
///      every existing lane is still busy.
///   4. CLUSTERING: BFS-group events whose time intervals
///      transitively overlap. Within a cluster, every event
///      gets `totalLanes = (max assigned lane + 1)` so each
///      member renders at the same width.
///
/// Complexity: O(n²) worst case for the clustering pass — n is
/// the number of events ON A SINGLE DAY, almost always < 20.
List<_PositionedEvent> _layoutEventLanes(
  List<AppEvent> events,
  DateTime dayStart,
  DateTime dayEnd,
) {
  // 1. Clip + filter.
  final clipped = <({AppEvent ev, DateTime s, DateTime e})>[];
  for (final ev in events) {
    final s = ev.startDate.isBefore(dayStart) ? dayStart : ev.startDate;
    final e = ev.endDate.isAfter(dayEnd) ? dayEnd : ev.endDate;
    if (!e.isAfter(s)) continue;
    clipped.add((ev: ev, s: s, e: e));
  }
  if (clipped.isEmpty) return const <_PositionedEvent>[];

  // 2. Sort.
  clipped.sort((a, b) {
    final cmp = a.s.compareTo(b.s);
    if (cmp != 0) return cmp;
    return a.e.compareTo(b.e);
  });

  // 3. Greedy lane assignment.
  final laneEnds = <DateTime>[]; // when each lane becomes free
  final lanes = List<int>.filled(clipped.length, -1);
  for (int i = 0; i < clipped.length; i++) {
    final c = clipped[i];
    int chosen = -1;
    for (int k = 0; k < laneEnds.length; k++) {
      if (!c.s.isBefore(laneEnds[k])) {
        // c starts at or after lane k's last end → lane is free.
        laneEnds[k] = c.e;
        chosen = k;
        break;
      }
    }
    if (chosen < 0) {
      chosen = laneEnds.length;
      laneEnds.add(c.e);
    }
    lanes[i] = chosen;
  }

  // 4. Cluster grouping via simple BFS over the overlap graph.
  final n = clipped.length;
  final cluster = List<int>.filled(n, -1);
  var nextCluster = 0;
  for (int i = 0; i < n; i++) {
    if (cluster[i] >= 0) continue;
    cluster[i] = nextCluster;
    final queue = <int>[i];
    while (queue.isNotEmpty) {
      final k = queue.removeLast();
      for (int j = 0; j < n; j++) {
        if (cluster[j] >= 0) continue;
        // Two events overlap iff a.s < b.e AND b.s < a.e.
        if (clipped[k].s.isBefore(clipped[j].e) &&
            clipped[j].s.isBefore(clipped[k].e)) {
          cluster[j] = nextCluster;
          queue.add(j);
        }
      }
    }
    nextCluster++;
  }

  // Max lane (and therefore lane count) per cluster.
  final clusterMaxLane = List<int>.filled(nextCluster, 0);
  for (int i = 0; i < n; i++) {
    if (lanes[i] > clusterMaxLane[cluster[i]]) {
      clusterMaxLane[cluster[i]] = lanes[i];
    }
  }

  // Build the result list.
  return [
    for (int i = 0; i < n; i++)
      _PositionedEvent(
        clipped[i].ev,
        clipped[i].s,
        clipped[i].e,
        lanes[i],
        clusterMaxLane[cluster[i]] + 1,
      ),
  ];
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
            // Phase-2 — small dot indicator above the day name
            // when the day is the FIRST of a Hijri month. Gives
            // the user a quiet "Hijri month flipped today" cue
            // without crowding the header — important on the
            // weekly view because the Hijri month is otherwise
            // implicit (we only show the day number).
            final isHijriFirst = hijri.hDay == 1;
            return Expanded(
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isHijriFirst)
                        Container(
                          margin: const EdgeInsetsDirectional.only(end: 3),
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                            color: AppColors.gold,
                            shape: BoxShape.circle,
                          ),
                        ),
                      Text(
                        dayLabels[i],
                        style: appFont(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: isFri
                              ? AppColors.green
                              : (isDark
                                  ? AppColors.darkText3
                                  : AppColors.text3),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      // Phase-2 — today's pill uses a subtle
                      // gradient and a soft glow. Same hue as
                      // the timeline-column tint so the eye
                      // connects header → column without effort.
                      gradient: isToday
                          ? LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppColors.green,
                                Color.lerp(
                                    AppColors.green, Colors.black, 0.15)!,
                              ],
                            )
                          : null,
                      color:
                          isToday ? null : Colors.transparent,
                      shape: BoxShape.circle,
                      boxShadow: isToday
                          ? [
                              BoxShadow(
                                color: AppColors.green
                                    .withValues(alpha: 0.40),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        TextFormat.toWesternDigits('${hijri.hDay}'),
                        style: appFont(
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
                    style: appFont(
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
              // Phase-1 task 6 — directional padding + textAlign
              // so the "All day" label hugs the inner edge of
              // the gutter in BOTH LTR and RTL. The previous
              // `right: 6` + `TextAlign.right` looked correct
              // in LTR but in Arabic (RTL) the gutter is on the
              // right side and the label was pushed AWAY from
              // the day columns. `end` swaps automatically.
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: Text(
                p.locale == 'ar'
                    ? 'كل اليوم'
                    : p.locale == 'es'
                        ? 'Todo el día'
                        : p.locale == 'en'
                            ? 'All day'
                            : 'Toute la j.',
                textAlign: TextAlign.end,
                style: appFont(
                    fontSize: 9, color: AppColors.text3),
              ),
            ),
          ),
          ...List.generate(7, (i) {
            final evs = allDayPerDay[i];
            // Phase-1 task 4 — surface a "+N" affordance when
            // the day has more all-day events than fit. We
            // show the first TWO inline; if there's a third+,
            // we collapse them into one tappable pill so the
            // user can see (a) that they exist and (b) opens a
            // bottom sheet with the full list. Before this,
            // events 4+ on a single day were silently dropped
            // by the old `evs.take(3)` slice.
            const inlineCap = 2;
            final extraCount =
                evs.length > inlineCap ? evs.length - inlineCap : 0;
            return Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...evs.take(inlineCap).map((ev) {
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
                          style: appFont(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    );
                  }),
                  if (extraCount > 0)
                    GestureDetector(
                      onTap: () => _showAllDayMore(
                        context: context,
                        events: evs,
                        day: days[i],
                        hijri: hijriFor(days[i]),
                        p: p,
                        isDark: isDark,
                      ),
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 2, vertical: 1),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.darkBorder
                              : AppColors.border,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          TextFormat.toWesternDigits('+$extraCount'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: appFont(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? AppColors.darkText
                                : AppColors.text2,
                          ),
                        ),
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

/// Bottom sheet that surfaces the full list of all-day events
/// on a single day, triggered by the "+N" pill rendered when
/// more all-day events fit than the inline cap allows. Each
/// row is tappable and routes through `showEventDetails` — the
/// same handler the inline pills already use, so editing /
/// deleting works the same way.
Future<void> _showAllDayMore({
  required BuildContext context,
  required List<AppEvent> events,
  required DateTime day,
  required HijriDate hijri,
  required AppProvider p,
  required bool isDark,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useRootNavigator: true,
    builder: (sheetCtx) {
      final loc = p.locale;
      final title = switch (loc) {
        'ar' => 'أحداث طوال اليوم',
        'fr' => 'Événements de toute la journée',
        'es' => 'Eventos de todo el día',
        _ => 'All-day events',
      };
      return DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.30,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.white,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(22),
            ),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 10),
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.text3.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: appFont(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? AppColors.darkText
                              : AppColors.text,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetCtx),
                      icon: Icon(
                        Icons.close_rounded,
                        size: 22,
                        color: isDark
                            ? AppColors.darkText3
                            : AppColors.text3,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  itemCount: events.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final ev = events[i];
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          // Pop the sheet first, then surface
                          // the per-event details modal so the
                          // navigation stack doesn't pile up.
                          Navigator.pop(sheetCtx);
                          showEventDetails(
                            context: context,
                            event: ev,
                            hijri: hijri,
                            gregorian: day,
                            p: p,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: ev.color.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            ev.title(loc),
                            style: appFont(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _GridBackground extends StatelessWidget {
  final double hourHeight;
  final double gutterWidth;
  final double colWidth;
  final List<DateTime> days;
  final bool isDark;

  /// Phase-1 task 3 — callback now reports the precise minutes
  /// from midnight (snapped to a 15-minute grid by the caller's
  /// dispatcher) instead of just the hour bucket. Lets a tap at
  /// 14:35 produce a new-event start at 14:30, matching the
  /// Google Calendar behaviour.
  final void Function(int dayIdx, int minutesFromMidnight) onCellTap;
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
    // Phase-2 — half-hour gridlines colour. ~50% transparency
    // of the full-hour line so the 30-minute marks read as a
    // subtle hint, not a competing horizontal rhythm.
    final halfHourColor = lineColor.withValues(alpha: 0.40);

    // Phase-2 — find today's column (if today falls in the
    // currently-visible week). `-1` means "today is not in this
    // week" → no tint and no current-time indicator.
    final now = DateTime.now();
    final todayIdx = () {
      for (int i = 0; i < days.length; i++) {
        if (days[i].year == now.year &&
            days[i].month == now.month &&
            days[i].day == now.day) {
          return i;
        }
      }
      return -1;
    }();

    return Stack(
      children: [
        // Phase-2 — today's column gets a very light green tint
        // (the accent's `greenPale` at low alpha) so the eye
        // immediately lands on "today" without obscuring any
        // event painted on top. Skipped when today isn't in the
        // visible week.
        if (todayIdx >= 0)
          Positioned(
            top: 0,
            bottom: 0,
            left: gutterWidth + todayIdx * colWidth,
            width: colWidth,
            child: Container(
              color: isDark
                  ? AppColors.green.withValues(alpha: 0.08)
                  : AppColors.greenPale.withValues(alpha: 0.55),
            ),
          ),
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
                      // Phase-1 task 6 — directional padding +
                      // textAlign so the hour label hugs the
                      // inner edge of the gutter in BOTH LTR
                      // and RTL. In Arabic the gutter is on the
                      // right side of the screen; the label has
                      // to nestle against the day-column
                      // divider, which is now on the LEFT of
                      // the gutter — `end` resolves to that
                      // automatically.
                      padding: const EdgeInsetsDirectional.only(
                        end: 6,
                        top: 0,
                      ),
                      child: Text(
                        TextFormat.toWesternDigits(
                          '${h.toString().padLeft(2, '0')}:00',
                        ),
                        textAlign: TextAlign.end,
                        style: appFont(
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
        // Phase-2 — half-hour gridlines. Subtle ticks at the
        // 30-min mark of every hour so the user has a visual
        // anchor halfway through. Rendered as a separate
        // overlay so they sit ABOVE the today-column tint but
        // BELOW the event blocks; events stay the dominant
        // visual element on the timeline.
        ...List.generate(24, (h) {
          return Positioned(
            top: h * hourHeight + hourHeight / 2,
            left: gutterWidth,
            right: 0,
            height: 0.5,
            child: Container(color: halfHourColor),
          );
        }),
        // 7 day columns: vertical separators + tappable column.
        //
        // Phase-1 task 3 — ONE `GestureDetector` per column (not
        // per hour-cell) with `onTapDown` reading the local Y
        // position. We then convert Y → minutes-from-midnight
        // and snap to the nearest 15-minute boundary. The old
        // 24-cells-per-column layout could only ever report the
        // hour bucket, so a tap at 14:55 created a 14:00 event
        // — confusing and a steady source of "wrong time" bugs
        // in user feedback.
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
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapDown: (details) {
                      // Y position inside the column maps to
                      // minutes-from-midnight: every `hourHeight`
                      // dp = 60 minutes.
                      final rawMinutes =
                          (details.localPosition.dy / hourHeight) * 60.0;
                      // Snap to nearest 15-minute boundary. Cap
                      // at 23:45 so a tap on the very last pixel
                      // doesn't produce a "24:00" timestamp that
                      // would roll into the next day.
                      var snapped =
                          (rawMinutes / 15.0).round() * 15;
                      if (snapped < 0) snapped = 0;
                      if (snapped > 23 * 60 + 45) {
                        snapped = 23 * 60 + 45;
                      }
                      onCellTap(dayIdx, snapped);
                    },
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

    // Phase-2 — current-time line spans ALL day columns now,
    // not just today's. A faint red line crosses the whole
    // timeline ("it's 14:30 right now everywhere"); a brighter
    // 2 px segment + the red dot anchor it on today's column
    // so the user can still see at a glance which day is
    // "today". The full-width line matches Google Calendar's
    // weekly view and helps when comparing events on the same
    // hour across the week.
    return Stack(
      children: [
        // Faint full-width line. Sits BELOW the brighter
        // today-column overlay so the today segment visually
        // wins on the intersection.
        Positioned(
          top: top - 0.5,
          left: gutterWidth,
          right: 0,
          height: 1,
          child: Container(
            color: AppColors.red.withValues(alpha: 0.30),
          ),
        ),
        // Today's column gets the brighter line + the dot.
        Positioned(
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
                child: Container(
                  height: 1.5,
                  color: AppColors.red,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
// AGENDA VIEW
// ════════════════════════════════════════════════════════════
class _AgendaView extends StatefulWidget {
  final AppProvider p;
  final bool isDark;
  const _AgendaView({super.key, required this.p, required this.isDark});
  @override
  State<_AgendaView> createState() => _AgendaViewState();
}

class _AgendaViewState extends State<_AgendaView> {
  // Bidirectional, anchored agenda.
  //
  // The list renders chronologically — past on top, today in the
  // middle, future at the bottom — but uses a [CustomScrollView]
  // with a `center:` key sliver so the user's scroll offset is
  // measured relative to *today*, not relative to the past edge.
  // That means appending more past days never shifts today, never
  // jumps the scroll position, and the "Today" button can simply
  // animate to offset 0 to land back on today.
  //
  //   _pastDays   — past Gregorian days included (above center).
  //   _futureDays — future days included (below + at center).
  //   _pageSize   — increment used by both auto-load and "Load More".
  int _pastDays = 0;
  int _futureDays = 60;
  static const int _pageSize = 30;

  /// Once-only auto-load: the spec asks for ONE automatic load when
  /// the user first scrolls into the past zone, then a button drives
  /// every subsequent expansion. Keeping this a one-shot keeps the
  /// UX predictable (no "what just happened?" auto-jumps deep into
  /// history) and keeps memory bounded.
  bool _autoLoadedPast = false;

  /// Lightweight reentrancy lock to swallow rapid-fire taps / scroll
  /// callbacks while a setState is already in flight.
  bool _busy = false;

  late final ScrollController _scrollCtrl;

  /// Sliver identity that [CustomScrollView.center] points at. Must
  /// be a stable, non-rebuilt key, hence the `final` field.
  final Key _centerKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_autoLoadedPast || _busy) return;
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    // The past sliver lives ABOVE the center: dragging content
    // downward walks `pixels` into negative territory. We trigger
    // the one-shot auto-load only after the user has actually
    // scrolled at least 40 px into the past zone — that confirms
    // intent (vs. an accidental over-scroll bounce on first paint,
    // when the empty past sliver is just the "Load More" button).
    if (pos.pixels < -40) {
      _autoLoadedPast = true;
      _busy = true;
      setState(() => _pastDays = _pageSize);
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted) _busy = false;
      });
    }
  }

  void _loadMorePast() {
    if (_busy) return;
    _busy = true;
    setState(() => _pastDays += _pageSize);
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) _busy = false;
    });
  }

  void _loadMoreFuture() => setState(() => _futureDays += _pageSize);

  /// Public — invoked by [_CalendarScreenState._jumpToToday] when the
  /// user taps the "Today" button while the agenda view is mounted.
  /// Animates back to offset 0 (top of the future sliver = today's
  /// group). No rebuild, no full reload.
  Future<void> scrollToToday() async {
    if (!_scrollCtrl.hasClients) return;
    await _scrollCtrl.animateTo(
      0.0,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOutCubic,
    );
  }

  String _loadMoreLabel(String locale) {
    switch (locale) {
      case 'ar': return 'تحميل المزيد';
      case 'es': return 'Cargar más';
      case 'en': return 'Load more';
      default:   return 'Charger plus';
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final isDark = widget.isDark;
    final today = p.today;

    // Walk the entire window in one pass and deduplicate by a Hijri
    // (year, month, day) key. The dedup is required because the
    // range walker maps Gregorian → Hijri using the canonical
    // converter, while `p.today` (and the date-badge inside
    // `_AgendaGroup`) apply the region offset (`hijriDayOffset`).
    // For some boundary pairs that mismatch makes two consecutive
    // Gregorian days resolve to the same Hijri (y, m, d) — which
    // showed up as the duplicate "21 ذو القعدة 1447 — 09/05/2026"
    // section reported in the field. Keying by Hijri (y, m, d) and
    // dropping repeats guarantees one section per Hijri day.
    String hijriKey(HijriDate h) => '${h.hYear}-${h.hMonth}-${h.hDay}';

    final allRaw = p.getAgendaEventsRange(
      pastDays: _pastDays,
      futureDays: _futureDays,
    );
    final seen = <String>{};
    final dedup = <MapEntry<HijriDate, List<AppEvent>>>[];
    for (final entry in allRaw) {
      if (seen.add(hijriKey(entry.key))) dedup.add(entry);
    }

    // Locate today inside the deduped list. If today already exists
    // (typical case — today has at least the daily-adhkar events),
    // we re-use it. Only when it's genuinely missing do we inject a
    // single placeholder, AND we attach today's actual events to it
    // so the very first frame already shows today's section
    // populated. The reason today can be missing on initial paint is
    // a region-offset asymmetry: `getAgendaEventsRange` walks
    // Gregorian dates and converts each via the canonical
    // `HijriDate.fromGregorian`, while `p.today` (and the date badge
    // inside `_AgendaGroup`) apply `hijriDayOffset`. With pastDays =
    // 0 the future walk's first Hijri value can be (today + 1) under
    // the canonical mapping, leaving today off the list. Fetching
    // today's events explicitly via `getEventsForDay(...)` —
    // identical to the call the walker would have made — guarantees
    // today renders with its events without any scroll, refresh, or
    // extra rebuild.
    final todayKey = hijriKey(today);
    int todayIdx = dedup.indexWhere((e) => hijriKey(e.key) == todayKey);
    if (todayIdx < 0) {
      DateTime todayGreg;
      try {
        todayGreg = p.hijriToGregorian(today.hYear, today.hMonth, today.hDay);
      } catch (_) {
        todayGreg = DateTime.now();
      }
      int insertAt = dedup.length;
      for (int i = 0; i < dedup.length; i++) {
        DateTime g;
        try {
          g = p.hijriToGregorian(
              dedup[i].key.hYear, dedup[i].key.hMonth, dedup[i].key.hDay);
        } catch (_) {
          g = DateTime.now();
        }
        if (!g.isBefore(todayGreg)) {
          insertAt = i;
          break;
        }
      }
      final todayEvents =
          p.getEventsForDay(today.hDay, today.hMonth, today.hYear);
      dedup.insert(insertAt, MapEntry(today, todayEvents));
      todayIdx = insertAt;
    }

    // Disjoint past / future partitions around today. Past is
    // reversed so the sliver-before-center sees `child(0) =
    // yesterday` (closest to today) and the oldest day at the
    // highest index — same semantics as before, just sourced from a
    // dedupe-clean unified list.
    final pastItems = dedup.sublist(0, todayIdx).reversed.toList();
    final futureItems = dedup.sublist(todayIdx);

    return CustomScrollView(
      controller: _scrollCtrl,
      center: _centerKey,
      slivers: [
        // ── PAST sliver (above center) ────────────────────────────
        // childCount = past_groups + 1 (Load-More button).
        // Sliver-before-center semantics: child(0) is closest to the
        // center (visually just above today), child(N-1) is at the
        // top of the past block — that's where the Load-More button
        // lives.
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (ctx, idx) {
              if (idx == pastItems.length) {
                return _LoadMorePastButton(
                  label: _loadMoreLabel(p.locale),
                  onTap: _loadMorePast,
                );
              }
              final e = pastItems[idx];
              return _AgendaGroup(
                date: e.key, events: e.value, p: p, isDark: isDark);
            },
            childCount: pastItems.length + 1,
          ),
        ),
        // ── Center anchor — empty, zero-height, identifies "today"
        // for the bidirectional scroll math.
        SliverToBoxAdapter(
          key: _centerKey,
          child: const SizedBox.shrink(),
        ),
        // ── FUTURE sliver (below center) ──────────────────────────
        // child(0) = today; last child = "Load more" future button;
        // a tail spacer keeps the bottom edge clear of the bottom
        // navigation chrome.
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (ctx, idx) {
              if (idx == futureItems.length) {
                return _LoadMoreFutureButton(
                  label: _loadMoreLabel(p.locale),
                  onTap: _loadMoreFuture,
                );
              }
              final e = futureItems[idx];
              return _AgendaGroup(
                date: e.key, events: e.value, p: p, isDark: isDark);
            },
            childCount: futureItems.length + 1,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }
}

class _LoadMorePastButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _LoadMorePastButton({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Center(
        child: TextButton.icon(
          onPressed: onTap,
          icon: Icon(Icons.history, size: 18, color: AppColors.green),
          label: Text(
            label,
            style: appFont(
              color: AppColors.green,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadMoreFutureButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _LoadMoreFutureButton({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextButton(
        onPressed: onTap,
        child: Text(
          label,
          style: appFont(
            color: AppColors.green,
            fontWeight: FontWeight.w700,
          ),
        ),
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
          style: appFont(
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

  /// Pale-tinted background for the round emoji disc, derived from
  /// the event color so each card hints at its category at a glance.
  Color get _iconBg {
    if (event.isIslamic) return AppColors.greenPale;
    if (event.color.value == AppColors.gold.value) return AppColors.goldPale;
    if (event.color.value == AppColors.red.value) return const Color(0xFFFDEAEA);
    if (event.color.value == AppColors.blue.value) return AppColors.bluePale;
    if (event.color.value == AppColors.navy.value) return AppColors.bg;
    return AppColors.greenPale;
  }

  Color get _chipBg => _iconBg;
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
        // Premium card: rounded 18 radius, soft shadow, generous
        // breathing room. Same visual language as the Islamic events
        // screen — colored bar on the start edge, pale circular
        // emoji disc, calm Amiri title + Cairo time, category chip
        // on the trailing side.
        decoration: BoxDecoration(
          color: surf,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // 1. Vertical colored bar — start edge (right in RTL).
              Container(
                width: 5,
                decoration: BoxDecoration(
                  color: event.color,
                  borderRadius: const BorderRadiusDirectional.only(
                    topStart: Radius.circular(18),
                    bottomStart: Radius.circular(18),
                  ),
                ),
              ),
              // 2. Pale circular emoji disc.
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 12),
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: _iconBg,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      event.emoji.isNotEmpty
                          ? event.emoji
                          : (event.isIslamic ? '🕌' : '📅'),
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                ),
              ),
              // 3. Centered title (Amiri) + time (Cairo).
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        event.title(loc),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: appFont(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color:
                              isDark ? AppColors.darkText : AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _timeLabel(loc),
                        style: appFont(
                          fontSize: 11,
                          color: isDark
                              ? AppColors.darkText3
                              : AppColors.text3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 4. Category pill on trailing edge.
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
                    style: appFont(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
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
                    style: appFont(
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
                  style: appFont(
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
                      style: appFont(
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
                        style: appFont(
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
              padding: const EdgeInsets.only(bottom: 10),
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
