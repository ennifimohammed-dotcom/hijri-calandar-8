import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/event_model.dart';
import '../providers/app_provider.dart';
import '../utils/hijri_utils.dart';
import '../theme.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  String _query = '';
  String _filterType = 'all'; // all / islamic / personal
  List<String> _recentSearches = [];

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() => _recentSearches =
          prefs.getStringList('recent_searches') ?? []);
    } catch (_) {}
  }

  Future<void> _saveRecent(String q) async {
    if (q.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = [q, ..._recentSearches.where((s) => s != q)].take(5).toList();
      await prefs.setStringList('recent_searches', list);
      setState(() => _recentSearches = list);
    } catch (_) {}
  }

  List<AppEvent> _search(AppProvider p) {
    if (_query.length < 2) return [];
    final q = _query.toLowerCase();
    final all = <AppEvent>[];

    // User events
    for (final ev in p.userEvents) {
      final match = ev.titles.values.any((t) => t.toLowerCase().contains(q)) ||
          ev.description('ar').toLowerCase().contains(q);
      if (!match) continue;
      if (_filterType == 'islamic' && !ev.isIslamic) continue;
      if (_filterType == 'personal' && ev.isIslamic) continue;
      all.add(ev);
    }

    // Islamic events (from bank). Region-aware: use the provider's
    // today so search dates land on the same Hijri days the calendar
    // is showing.
    final today = p.today;
    for (int monthOffset = 0; monthOffset < 12; monthOffset++) {
      final m = today.addMonths(monthOffset);
      final days = HijriDate.daysInMonth(m.hYear, m.hMonth);
      for (int d = 1; d <= days; d++) {
        final evs = p.getEventsForDay(d, m.hMonth, m.hYear);
        for (final ev in evs) {
          if (!ev.isIslamic) continue;
          final match = ev.titles.values.any((t) => t.toLowerCase().contains(q));
          if (!match) continue;
          if (_filterType == 'personal') continue;
          if (!all.any((e) => e.id == ev.id)) all.add(ev);
        }
      }
    }

    return all.take(30).toList();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    final isDark = p.themeMode == ThemeMode.dark;
    final loc = p.locale;
    final results = _search(p);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.bg,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded,
              color: isDark ? AppColors.darkText : AppColors.navy),
          onPressed: () => Navigator.pop(context)),
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          onChanged: (v) => setState(() => _query = v),
          onSubmitted: (v) => _saveRecent(v),
          style: appFont(fontSize: 15,
              color: isDark ? AppColors.darkText : AppColors.text),
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: loc == 'ar' ? 'بحث في الأحداث...'
                : loc == 'fr' ? 'Rechercher des événements...'
                : 'Search events...',
            hintStyle: appFont(color: AppColors.text3)),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_rounded, color: AppColors.text3),
              onPressed: () { _ctrl.clear(); setState(() => _query = ''); }),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: _FilterRow(
            selected: _filterType, isDark: isDark, loc: loc,
            onChanged: (v) => setState(() => _filterType = v)),
        ),
      ),
      body: _query.isEmpty
          ? _RecentSearches(
              recent: _recentSearches,
              isDark: isDark, loc: loc,
              onTap: (s) { _ctrl.text = s; setState(() => _query = s); })
          : results.isEmpty
              ? _EmptyState(isDark: isDark, loc: loc)
              : _ResultsList(results: results, p: p, isDark: isDark,
                  onTap: (ev) {
                    _saveRecent(_query);
                    p.selectDay(HijriDate(
                      ev.hijriYear ?? p.today.hYear,
                      ev.hijriMonth ?? p.today.hMonth,
                      ev.hijriDay ?? p.today.hDay));
                    Navigator.pop(context);
                  }),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final String selected, loc;
  final bool isDark;
  final ValueChanged<String> onChanged;
  const _FilterRow({required this.selected, required this.isDark,
      required this.loc, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final opts = [
      ('all', loc == 'ar' ? 'الكل' : loc == 'fr' ? 'Tout' : 'All'),
      ('islamic', loc == 'ar' ? 'إسلامي' : 'Islamique'),
      ('personal', loc == 'ar' ? 'شخصي' : 'Personnel'),
    ];
    return Container(
      color: isDark ? AppColors.darkSurface : AppColors.white,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: opts.map((o) {
          final active = selected == o.$1;
          return GestureDetector(
            onTap: () => onChanged(o.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: active ? AppColors.green : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: active ? AppColors.green : AppColors.border)),
              child: Text(o.$2, style: appFont(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: active ? Colors.white
                      : (isDark ? AppColors.darkText3 : AppColors.text3))),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _RecentSearches extends StatelessWidget {
  final List<String> recent;
  final bool isDark;
  final String loc;
  final ValueChanged<String> onTap;
  const _RecentSearches({required this.recent, required this.isDark,
      required this.loc, required this.onTap});
  @override
  Widget build(BuildContext context) {
    if (recent.isEmpty) return _EmptyHint(isDark: isDark, loc: loc);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(loc == 'ar' ? 'عمليات البحث الأخيرة'
            : loc == 'fr' ? 'Recherches récentes' : 'Recent searches',
          style: appFont(fontSize: 11, fontWeight: FontWeight.w700,
              color: AppColors.text3, letterSpacing: 2)),
        const SizedBox(height: 8),
        ...recent.map((s) => ListTile(
          leading: const Icon(Icons.history_rounded, color: AppColors.text3, size: 18),
          title: Text(s, style: appFont(fontSize: 13,
              color: isDark ? AppColors.darkText : AppColors.text)),
          onTap: () => onTap(s),
        )),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final bool isDark;
  final String loc;
  const _EmptyHint({required this.isDark, required this.loc});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.search_rounded, size: 64,
            color: isDark ? AppColors.darkText3 : AppColors.text3),
        const SizedBox(height: 12),
        Text(loc == 'ar' ? 'ابحث عن أحداثك'
            : loc == 'fr' ? 'Recherchez vos événements' : 'Search your events',
          style: appFont(fontSize: 14, color: AppColors.text3)),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  final bool isDark;
  final String loc;
  const _EmptyState({required this.isDark, required this.loc});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.search_off_rounded, size: 64,
            color: isDark ? AppColors.darkText3 : AppColors.text3),
        const SizedBox(height: 12),
        Text(loc == 'ar' ? 'لا توجد نتائج'
            : loc == 'fr' ? 'Aucun résultat' : 'No results',
          style: appFont(fontSize: 14, color: AppColors.text3)),
      ],
    ),
  );
}

class _ResultsList extends StatelessWidget {
  final List<AppEvent> results;
  final AppProvider p;
  final bool isDark;
  final ValueChanged<AppEvent> onTap;
  const _ResultsList({required this.results, required this.p,
      required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: results.length,
      itemBuilder: (ctx, i) {
        final ev = results[i];
        final surf = isDark ? AppColors.darkSurface : AppColors.white;
        String dateStr = '';
        try {
          // Route through the provider so the displayed civil date
          // matches the region-aware mapping used everywhere else.
          final g = p.hijriToGregorian(ev.hijriYear ?? DateTime.now().year, ev.hijriMonth ?? DateTime.now().month, ev.hijriDay ?? DateTime.now().day);
          dateStr = '${ev.hijriDay ?? ''} ${p.getHijriMonthName(ev.hijriMonth ?? 1, p.locale)} — ${g.day}/${g.month}/${g.year}';
        } catch (_) {
          dateStr = '${ev.hijriDay ?? ''} ${p.getHijriMonthName(ev.hijriMonth ?? 1, p.locale)}';
        }
        return GestureDetector(
          onTap: () => onTap(ev),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(color: surf,
                borderRadius: BorderRadius.circular(14)),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Container(width: 4,
                    decoration: BoxDecoration(color: ev.color,
                      borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(14),
                          bottomLeft: Radius.circular(14)))),
                  Expanded(child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(ev.title(p.locale), style: appFont(
                            fontSize: 13, fontWeight: FontWeight.w700,
                            color: isDark ? AppColors.darkText : AppColors.text)),
                        Text(dateStr, style: appFont(
                            fontSize: 10, color: AppColors.text3)),
                      ],
                    ),
                  )),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: ev.isIslamic ? AppColors.goldPale : AppColors.greenPale,
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(ev.isIslamic ? p.label('islamic') : p.label('personal'),
                        style: appFont(fontSize: 8, fontWeight: FontWeight.w700,
                            color: ev.isIslamic ? AppColors.gold : AppColors.green)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
