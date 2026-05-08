import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/app_provider.dart';
import '../utils/hijri_utils.dart';
import '../theme.dart';
import '../widgets/calendar_grid_picker.dart';

class ConverterScreen extends StatefulWidget {
  const ConverterScreen({super.key});
  @override
  State<ConverterScreen> createState() => _ConverterScreenState();
}

class _ConverterScreenState extends State<ConverterScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  // Hijri → Greg state
  late int _hDay, _hMonth, _hYear;
  DateTime? _gregResult;

  // Greg → Hijri state
  DateTime _gregInput = DateTime.now();
  HijriDate? _hijriResult;

  /// Region-aware Hijri offset, applied to every conversion below so
  /// the converter is consistent with the rest of the app's calendar
  /// (Morocco/Algeria run +1 day relative to Umm al-Qura, etc.).
  /// Uses listen:false because the value is read at conversion time
  /// rather than during build; the build method below also calls
  /// [context.watch] so the screen still rebuilds on region change.
  int get _offset {
    final p = Provider.of<AppProvider>(context, listen: false);
    return p.hijriDayOffset;
  }

  /// Today in the user's regional Hijri calendar — mirrors
  /// [AppProvider._todayForRegion].
  HijriDate _regionalToday() {
    final shifted = DateTime.now().subtract(Duration(days: _offset));
    return HijriDate.fromGregorian(shifted);
  }

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    // Provisional defaults — overwritten in the first
    // [didChangeDependencies] once the provider is reachable.
    _hDay = 1; _hMonth = 1; _hYear = 1446;
  }

  // Tracks the last region offset we used. When the user changes
  // region in Settings the provider notifies, [didChangeDependencies]
  // fires here, and we re-run the conversions so the displayed
  // Hijri/Gregorian pair stays synchronized with the active region.
  int? _lastOffset;
  bool _seededFromRegion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final off = Provider.of<AppProvider>(context, listen: true).hijriDayOffset;
    if (_lastOffset == off) return;
    _lastOffset = off;
    if (!_seededFromRegion) {
      final shifted = DateTime.now().subtract(Duration(days: off));
      final today = HijriDate.fromGregorian(shifted);
      _hDay = today.hDay;
      _hMonth = today.hMonth;
      _hYear = today.hYear;
      _gregInput = DateTime.now();
      _seededFromRegion = true;
    }
    _convertHijriToGreg();
    _convertGregToHijri();
  }

  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  void _convertHijriToGreg() {
    try {
      // Region offset reverses the regional shift: a regional Hijri
      // date d corresponds to UAQ.toGregorian(d) + offset days.
      final base = HijriDate.hijriToGregorian(_hYear, _hMonth, _hDay);
      final g = base.add(Duration(days: _offset));
      setState(() => _gregResult = g);
    } catch (_) { setState(() => _gregResult = null); }
  }

  void _convertGregToHijri() {
    try {
      final shifted = _gregInput.subtract(Duration(days: _offset));
      final h = HijriDate.fromGregorian(shifted);
      setState(() => _hijriResult = h);
    } catch (_) { setState(() => _hijriResult = null); }
  }

  void _goToToday() {
    final now = _regionalToday();
    setState(() {
      _hDay = now.hDay; _hMonth = now.hMonth; _hYear = now.hYear;
      _gregInput = DateTime.now();
    });
    _convertHijriToGreg();
    _convertGregToHijri();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    final isDark = p.themeMode == ThemeMode.dark;
    final loc = p.locale;
    // Conversions follow the active region; see
    // [didChangeDependencies] which re-runs them when the provider
    // notifies of a region change.

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.bg,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
        elevation: 0,
        title: Text(
          loc == 'ar' ? 'محوّل التواريخ'
              : loc == 'fr' ? 'Convertisseur de dates' : 'Date Converter',
          style: appFont(fontSize: 20, fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkText : AppColors.navy)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.today_rounded, color: AppColors.green),
            tooltip: loc == 'ar' ? 'اليوم' : "Aujourd'hui",
            onPressed: _goToToday),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: isDark ? AppColors.darkSurface : AppColors.white,
            child: TabBar(
              controller: _tabCtrl,
              indicatorColor: AppColors.green,
              labelColor: AppColors.green,
              unselectedLabelColor: AppColors.text3,
              labelStyle: appFont(fontSize: 12, fontWeight: FontWeight.w700),
              tabs: [
                Tab(text: loc == 'ar' ? 'هجري ← ميلادي' : 'Hijri → Grégorien'),
                Tab(text: loc == 'ar' ? 'ميلادي ← هجري' : 'Grégorien → Hijri'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _HijriToGregTab(
            hDay: _hDay, hMonth: _hMonth, hYear: _hYear,
            result: _gregResult, p: p, isDark: isDark,
            onDayChanged: (v) { setState(() => _hDay = v); _convertHijriToGreg(); },
            onMonthChanged: (v) { setState(() => _hMonth = v); _convertHijriToGreg(); },
            onYearChanged: (v) { setState(() => _hYear = v); _convertHijriToGreg(); },
          ),
          _GregToHijriTab(
            gregInput: _gregInput, result: _hijriResult,
            p: p, isDark: isDark,
            onDateChanged: (d) { setState(() => _gregInput = d); _convertGregToHijri(); },
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// TAB 1: HIJRI → GREGORIAN
// ═══════════════════════════════════════════════════════════
class _HijriToGregTab extends StatelessWidget {
  final int hDay, hMonth, hYear;
  final DateTime? result;
  final AppProvider p;
  final bool isDark;
  final ValueChanged<int> onDayChanged, onMonthChanged, onYearChanged;

  const _HijriToGregTab({
    required this.hDay, required this.hMonth, required this.hYear,
    required this.result, required this.p, required this.isDark,
    required this.onDayChanged, required this.onMonthChanged,
    required this.onYearChanged,
  });

  @override
  Widget build(BuildContext context) {
    final loc = p.locale;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 8),
          // Pickers row
          _PickerCard(isDark: isDark, child: Row(
            children: [
              // Day
              Expanded(child: _NumberPicker(
                label: loc == 'ar' ? 'اليوم' : 'Jour',
                value: hDay, min: 1, max: 30, isDark: isDark,
                onChanged: onDayChanged)),
              _Divider(isDark: isDark),
              // Month
              Expanded(child: _MonthPicker(
                value: hMonth, p: p, isDark: isDark,
                onChanged: onMonthChanged)),
              _Divider(isDark: isDark),
              // Year
              Expanded(child: _NumberPicker(
                label: loc == 'ar' ? 'السنة' : 'Année',
                value: hYear, min: 1300, max: 1500, isDark: isDark,
                onChanged: onYearChanged)),
            ],
          )),
          const SizedBox(height: 20),
          // Arrow
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: AppColors.green, shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: AppColors.green.withValues(alpha: 0.4),
                  blurRadius: 12)]),
            child: const Icon(Icons.arrow_downward_rounded,
                color: Colors.white, size: 24)),
          const SizedBox(height: 20),
          // Result
          if (result != null)
            _HijriToGregResult(date: result!, hDay: hDay, hMonth: hMonth,
                hYear: hYear, p: p, isDark: isDark),
        ],
      ),
    );
  }
}

class _HijriToGregResult extends StatelessWidget {
  final DateTime date;
  final int hDay, hMonth, hYear;
  final AppProvider p;
  final bool isDark;
  const _HijriToGregResult({required this.date, required this.hDay,
      required this.hMonth, required this.hYear, required this.p,
      required this.isDark});

  String _weekdayName(int wd, String loc) {
    const ar = ['','الاثنين','الثلاثاء','الأربعاء','الخميس','الجمعة','السبت','الأحد'];
    const fr = ['','Lundi','Mardi','Mercredi','Jeudi','Vendredi','Samedi','Dimanche'];
    const en = ['','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
    switch (loc) {
      case 'fr': return fr[wd];
      case 'en': case 'es': return en[wd];
      default: return ar[wd];
    }
  }

  String _monthName(int m, String loc) {
    const fr = ['','Janvier','Février','Mars','Avril','Mai','Juin',
        'Juillet','Août','Septembre','Octobre','Novembre','Décembre'];
    const en = ['','January','February','March','April','May','June',
        'July','August','September','October','November','December'];
    const ar = ['','يناير','فبراير','مارس','أبريل','مايو','يونيو',
        'يوليو','أغسطس','سبتمبر','أكتوبر','نوفمبر','ديسمبر'];
    switch (loc) {
      case 'fr': return fr[m];
      case 'ar': return ar[m];
      default: return en[m];
    }
  }

  String _shareText(String loc) {
    final wd = _weekdayName(date.weekday, loc);
    final mn = p.getHijriMonthName(hMonth, loc);
    final gMon = _monthName(date.month, loc);
    if (loc == 'ar') {
      return '$wd $hDay $mn $hYear هـ — الموافق ${date.day} $gMon ${date.year}';
    }
    return '$wd $hDay $mn $hYear AH — ${date.day} $gMon ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final loc = p.locale;
    final surf = isDark ? AppColors.darkSurface : AppColors.white;
    final wd = _weekdayName(date.weekday, loc);
    final gMon = _monthName(date.month, loc);

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: surf,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12)],
          ),
          child: Column(
            children: [
              Text(wd, style: appFont(fontSize: 13,
                  fontWeight: FontWeight.w700, color: AppColors.green)),
              const SizedBox(height: 8),
              Text(
                '${date.day} $gMon ${date.year}',
                style: appFont(fontSize: 32, fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkText : AppColors.navy),
                textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(
                '$hDay ${p.getHijriMonthName(hMonth, loc)} $hYear هـ',
                style: appFont(fontSize: 14,
                    color: isDark ? AppColors.darkText2 : AppColors.text2),
                textAlign: TextAlign.center),
              const SizedBox(height: 16),
              // Share + Copy
              Row(
                children: [
                  Expanded(child: _ActionBtn(
                    icon: Icons.share_rounded,
                    label: loc == 'ar' ? 'مشاركة' : 'Partager',
                    color: AppColors.green,
                    onTap: () => Share.share(_shareText(loc)),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: _ActionBtn(
                    icon: Icons.copy_rounded,
                    label: loc == 'ar' ? 'نسخ' : 'Copier',
                    color: AppColors.navy,
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: _shareText(loc)));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(loc == 'ar' ? 'تم النسخ' : 'Copié !'),
                        duration: const Duration(seconds: 1)));
                    },
                  )),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
// TAB 2: GREGORIAN → HIJRI
// ═══════════════════════════════════════════════════════════
class _GregToHijriTab extends StatelessWidget {
  final DateTime gregInput;
  final HijriDate? result;
  final AppProvider p;
  final bool isDark;
  final ValueChanged<DateTime> onDateChanged;

  const _GregToHijriTab({required this.gregInput, required this.result,
      required this.p, required this.isDark, required this.onDateChanged});

  @override
  Widget build(BuildContext context) {
    final loc = p.locale;
    final surf = isDark ? AppColors.darkSurface : AppColors.white;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 8),
          // Date picker button — uses the shared calendar-grid dialog
          // so the picker matches the monthly view and stays
          // synchronized with the active region.
          GestureDetector(
            onTap: () async {
              final picked = await showCalendarGridPicker(
                context: context,
                initial: gregInput,
                useHijri: false,
                locale: p.locale,
                provider: p,
              );
              if (picked != null) onDateChanged(picked);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.navy,
                borderRadius: BorderRadius.circular(20)),
              child: Column(
                children: [
                  Text(loc == 'ar' ? 'التاريخ الميلادي'
                      : loc == 'fr' ? 'Date grégorienne' : 'Gregorian Date',
                    style: appFont(fontSize: 10, color: Colors.white54,
                        letterSpacing: 2, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(
                    '${gregInput.day} / ${gregInput.month} / ${gregInput.year}',
                    style: appFont(fontSize: 30, fontWeight: FontWeight.bold,
                        color: Colors.white)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.green,
                      borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today_rounded,
                            color: Colors.white, size: 14),
                        const SizedBox(width: 6),
                        Text(loc == 'ar' ? 'اختر تاريخاً'
                            : loc == 'fr' ? 'Choisir une date' : 'Pick a date',
                          style: appFont(fontSize: 12, color: Colors.white,
                              fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: AppColors.green, shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: AppColors.green.withValues(alpha: 0.4),
                  blurRadius: 12)]),
            child: const Icon(Icons.arrow_downward_rounded,
                color: Colors.white, size: 24)),
          const SizedBox(height: 20),
          if (result != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: surf,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12)]),
              child: Column(
                children: [
                  Text(
                    '${result!.hDay} ${p.getHijriMonthName(result!.hMonth, loc)} ${result!.hYear}',
                    style: appFont(fontSize: 30, fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkText : AppColors.navy),
                    textAlign: TextAlign.center),
                  const SizedBox(height: 4),
                  Text(
                    '${result!.hYear} ${loc == "ar" ? "هـ" : "AH"}',
                    style: appFont(fontSize: 13, color: AppColors.green,
                        fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  _ActionBtn(
                    icon: Icons.share_rounded,
                    label: loc == 'ar' ? 'مشاركة' : 'Partager',
                    color: AppColors.green,
                    onTap: () {
                      final text = '${gregInput.day}/${gregInput.month}/${gregInput.year} '
                          '= ${result!.hDay} ${p.getHijriMonthName(result!.hMonth, loc)} ${result!.hYear} هـ';
                      Share.share(text);
                    }),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────

class _PickerCard extends StatelessWidget {
  final Widget child;
  final bool isDark;
  const _PickerCard({required this.child, required this.isDark});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: isDark ? AppColors.darkSurface : AppColors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10)]),
    child: child,
  );
}

class _Divider extends StatelessWidget {
  final bool isDark;
  const _Divider({required this.isDark});
  @override
  Widget build(BuildContext context) => Container(
    width: 1, height: 80,
    color: isDark ? AppColors.darkBorder : AppColors.border);
}

class _NumberPicker extends StatelessWidget {
  final String label;
  final int value, min, max;
  final bool isDark;
  final ValueChanged<int> onChanged;
  const _NumberPicker({required this.label, required this.value,
      required this.min, required this.max, required this.isDark,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: appFont(fontSize: 9,
            color: AppColors.text3, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => onChanged((value + 1).clamp(min, max)),
          child: Icon(Icons.keyboard_arrow_up_rounded,
              color: AppColors.green, size: 22)),
        Text('$value', style: appFont(fontSize: 22,
            fontWeight: FontWeight.bold,
            color: isDark ? AppColors.darkText : AppColors.navy)),
        GestureDetector(
          onTap: () => onChanged((value - 1).clamp(min, max)),
          child: Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.green, size: 22)),
      ],
    );
  }
}

class _MonthPicker extends StatelessWidget {
  final int value;
  final AppProvider p;
  final bool isDark;
  final ValueChanged<int> onChanged;
  const _MonthPicker({required this.value, required this.p,
      required this.isDark, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final loc = p.locale;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(loc == 'ar' ? 'الشهر' : loc == 'fr' ? 'Mois' : 'Month',
          style: appFont(fontSize: 9,
              color: AppColors.text3, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => onChanged(value % 12 + 1),
          child: Icon(Icons.keyboard_arrow_up_rounded,
              color: AppColors.green, size: 22)),
        SizedBox(
          width: 80,
          child: Text(p.getHijriMonthName(value, loc),
            style: appFont(fontSize: 14, fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkText : AppColors.navy),
            textAlign: TextAlign.center,
            maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        GestureDetector(
          onTap: () => onChanged((value - 2) % 12 + 1),
          child: Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.green, size: 22)),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.label,
      required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(label, style: appFont(fontSize: 12,
              fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    ),
  );
}
