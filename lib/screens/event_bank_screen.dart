import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/islamic_events.dart';
import '../providers/app_provider.dart';
import '../theme.dart';
import '../widgets/calendar_grid_picker.dart';

class EventBankScreen extends StatefulWidget {
  const EventBankScreen({super.key});
  @override
  State<EventBankScreen> createState() => _EventBankScreenState();
}

class _EventBankScreenState extends State<EventBankScreen> {
  String _search = '';

  List<IslamicEventConfig> _filtered(List<IslamicEventConfig> all, String loc) {
    if (_search.isEmpty) return all;
    final q = _search.toLowerCase();
    return all.where((e) =>
      e.name(loc).toLowerCase().contains(q) ||
      e.name('ar').toLowerCase().contains(q) ||
      e.name('fr').toLowerCase().contains(q)
    ).toList();
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
            _BankHeader(p: p, isDark: isDark,
              search: _search,
              onSearchChanged: (v) => setState(() => _search = v)),
            Expanded(child: _BankList(
              p: p, isDark: isDark,
              filtered: (all) => _filtered(all, p.locale))),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// HEADER
// ═══════════════════════════════════════════════════════════
class _BankHeader extends StatelessWidget {
  final AppProvider p;
  final bool isDark;
  final String search;
  final ValueChanged<String> onSearchChanged;
  const _BankHeader({required this.p, required this.isDark,
      required this.search, required this.onSearchChanged});

  @override
  Widget build(BuildContext context) {
    // Header tracks the active accent (AppColors.green is the runtime
    // accent backed by AccentBus); dark mode keeps the deeper surface.
    final bg = isDark ? AppColors.darkSurface : AppColors.green;
    final loc = p.locale;
    final title = loc == 'ar' ? 'فضائل إسلامية'
        : loc == 'es' ? 'Virtudes islámicas'
        : loc == 'en' ? 'Islamic Virtues'
        : 'Vertus islamiques';
    final subtitle = loc == 'ar' ? 'مجموعة من الأذكار والأيام والمواسم المباركة'
        : loc == 'es' ? 'Recolección de adhkâr, días y temporadas bendecidas'
        : loc == 'en' ? 'A collection of adhkâr, blessed days and seasons'
        : "Recueil d'adhkâr, jours et saisons bénis";
    return Container(
      color: bg,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                    style: appFont(fontSize: 20,
                        fontWeight: FontWeight.bold, color: Colors.white)),
                  Text(subtitle,
                    style: appFont(fontSize: 10, color: Colors.white70)),
                ],
              )),
              const Text('🕌', style: TextStyle(fontSize: 26)),
            ],
          ),
          const SizedBox(height: 10),
          // Activate all
          _ActivateAllRow(p: p),
          const SizedBox(height: 10),
          // Search bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, color: Colors.white60, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    onChanged: onSearchChanged,
                    style: appFont(fontSize: 13, color: Colors.white),
                    decoration: InputDecoration(
                      border: InputBorder.none, isDense: true,
                      hintText: loc == 'ar' ? 'بحث...'
                          : loc == 'fr' ? 'Rechercher...' : 'Search...',
                      hintStyle: appFont(color: Colors.white54, fontSize: 13),
                    ),
                  ),
                ),
                if (search.isNotEmpty)
                  GestureDetector(
                    onTap: () => onSearchChanged(''),
                    child: const Icon(Icons.close_rounded,
                        color: Colors.white60, size: 16)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivateAllRow extends StatelessWidget {
  final AppProvider p;
  const _ActivateAllRow({required this.p});
  @override
  Widget build(BuildContext context) {
    final all = p.allIslamicEventsEnabled;
    return GestureDetector(
      onTap: () => p.toggleAllIslamicEvents(!all),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Expanded(child: Text(p.label('activate_all'),
              style: appFont(fontSize: 12,
                  fontWeight: FontWeight.w700, color: Colors.white))),
            Text('${IslamicEventsData.events.length}',
              style: appFont(fontSize: 10, color: Colors.white54)),
            const SizedBox(width: 10),
            _Toggle(value: all, color: AppColors.green,
                onChanged: (v) => p.toggleAllIslamicEvents(v)),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// LIST
// ═══════════════════════════════════════════════════════════
class _BankList extends StatelessWidget {
  final AppProvider p;
  final bool isDark;
  final List<IslamicEventConfig> Function(List<IslamicEventConfig>) filtered;
  const _BankList({required this.p, required this.isDark, required this.filtered});

  @override
  Widget build(BuildContext context) {
    final loc = p.locale;
    final daily   = filtered(IslamicEventsData.events.where((e) => e.isDaily).toList());
    final weekly  = filtered(IslamicEventsData.events.where((e) => e.isWeekly).toList());
    final monthly = filtered(IslamicEventsData.events.where((e) => e.isMonthly).toList());
    final annual  = filtered(IslamicEventsData.events.where(
        (e) => !e.isDaily && !e.isMonthly && !e.isWeekly).toList());

    // Section order per spec: Daily → Weekly → Monthly → Annual.
    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        if (daily.isNotEmpty) ...[
          _SectionDivider(
            label: loc == 'ar' ? 'يومي'
                : loc == 'es' ? 'Diario'
                : loc == 'en' ? 'Daily'
                : 'Quotidien',
            icon: '🌅', isDark: isDark),
          ...daily.map((e) => _EventRow(cfg: e, p: p, isDark: isDark)),
        ],
        if (weekly.isNotEmpty) ...[
          _SectionDivider(
            label: loc == 'ar' ? 'أسبوعي'
                : loc == 'es' ? 'Semanal'
                : loc == 'en' ? 'Weekly'
                : 'Hebdomadaire',
            icon: '📿', isDark: isDark),
          ...weekly.map((e) => _EventRow(cfg: e, p: p, isDark: isDark)),
        ],
        if (monthly.isNotEmpty) ...[
          _SectionDivider(
            label: loc == 'ar' ? 'شهري'
                : loc == 'es' ? 'Mensual'
                : loc == 'en' ? 'Monthly'
                : 'Mensuel',
            icon: '📅', isDark: isDark),
          ...monthly.map((e) => _EventRow(cfg: e, p: p, isDark: isDark)),
        ],
        if (annual.isNotEmpty) ...[
          _SectionDivider(
            label: loc == 'ar' ? 'سنوي'
                : loc == 'es' ? 'Anual'
                : loc == 'en' ? 'Annual'
                : 'Annuel',
            icon: '🌙', isDark: isDark),
          ...annual.map((e) => _EventRow(cfg: e, p: p, isDark: isDark)),
        ],
      ],
    );
  }
}

class _SectionDivider extends StatelessWidget {
  final String label, icon;
  final bool isDark;
  const _SectionDivider({required this.label, required this.icon, required this.isDark});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        children: [
          Expanded(child: Divider(
              color: isDark ? AppColors.darkBorder : AppColors.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('$icon  $label',
              style: appFont(fontSize: 10, fontWeight: FontWeight.w700,
                  color: AppColors.text3, letterSpacing: 2)),
          ),
          Expanded(child: Divider(
              color: isDark ? AppColors.darkBorder : AppColors.border)),
        ],
      ),
    );
  }
}

// ── Event Row ─────────────────────────────────────────────
class _EventRow extends StatelessWidget {
  final IslamicEventConfig cfg;
  final AppProvider p;
  final bool isDark;
  const _EventRow({required this.cfg, required this.p, required this.isDark});

  Color get _iconBg {
    if (cfg.color == AppColors.gold)  return AppColors.goldPale;
    if (cfg.color == AppColors.blue)  return AppColors.bluePale;
    if (cfg.color == AppColors.red)   return const Color(0xFFFDEAEA);
    if (cfg.color == AppColors.navy)  return AppColors.bg;
    return AppColors.greenPale;
  }

  /// Days until the next ACTUAL occurrence of this event (uses the
  /// `actual*` fields, not the reminder fields). Region-aware via
  /// [AppProvider.today], which already accounts for the user's
  /// region offset.
  int? _daysUntilActual() {
    try {
      final today = p.today;
      // All conversions go through the provider so the regional
      // offset (Morocco = UAQ + 1) is applied consistently — the
      // computed "days until next occurrence" must match the
      // monthly / agenda view's understanding of today.
      final todayG = p.hijriToGregorian(today.hYear, today.hMonth, today.hDay);
      if (cfg.isDaily) return 0;
      if (cfg.isWeekly) {
        final wds = cfg.displayWeekdays;
        if (wds.isEmpty) return null;
        for (var i = 0; i <= 7; i++) {
          final candidate = todayG.add(Duration(days: i));
          if (wds.contains(candidate.weekday)) return i;
        }
      }
      if (cfg.isMonthly) {
        final days = cfg.displayMonthlyDays;
        if (days.isEmpty) return null;
        // Smallest day >= today.hDay in the current month, else first
        // day in the next month.
        final upcoming = days.where((d) => d >= today.hDay).toList()..sort();
        if (upcoming.isNotEmpty) {
          final target = upcoming.first;
          final g = p.hijriToGregorian(today.hYear, today.hMonth, target);
          return g.difference(todayG).inDays;
        }
        final firstNext = days.reduce((a, b) => a < b ? a : b);
        final g = p.hijriToGregorian(today.hYear, today.hMonth + 1, firstNext);
        return g.difference(todayG).inDays;
      }
      // Yearly — uses displayMonth + displayDay (the actual observance).
      if (cfg.displayMonth > 0) {
        var targetYear = today.hYear;
        var g = p.hijriToGregorian(targetYear, cfg.displayMonth, cfg.displayDay);
        if (g.isBefore(todayG)) {
          g = p.hijriToGregorian(targetYear + 1, cfg.displayMonth, cfg.displayDay);
        }
        final diff = g.difference(todayG).inDays;
        return diff <= 60 ? diff : null;
      }
    } catch (_) {}
    return null;
  }

  /// "اليوم" / "غدا" / "بعد X يوم" pill text.
  String? _statusPillText(String loc) {
    final d = _daysUntilActual();
    if (d == null) return null;
    if (d == 0) {
      return loc == 'ar' ? 'اليوم'
          : loc == 'es' ? 'Hoy'
          : loc == 'en' ? 'Today'
          : "Auj.";
    }
    if (d == 1) {
      return loc == 'ar' ? 'غداً'
          : loc == 'es' ? 'Mañana'
          : loc == 'en' ? 'Tomorrow'
          : 'Demain';
    }
    if (d > 30) return null;
    return loc == 'ar' ? 'بعد $d يوم'
        : loc == 'es' ? 'En $d d'
        : loc == 'en' ? 'In $d d'
        : 'Dans $d j';
  }

  @override
  Widget build(BuildContext context) {
    final enabled = p.islamicEventsEnabled[cfg.id] ?? cfg.defaultEnabled;
    final surf = isDark ? AppColors.darkSurface : AppColors.white;
    final pillText = _statusPillText(p.locale);

    return GestureDetector(
      onTap: () => _showDetailSheet(context),
      child: Opacity(
        opacity: enabled ? 1.0 : 0.55,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          decoration: BoxDecoration(
            color: surf,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05), blurRadius: 6),
            ],
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                // Colored leading bar — RTL: right edge of card.
                Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: cfg.color,
                    borderRadius: const BorderRadiusDirectional.only(
                      topStart: Radius.circular(18),
                      bottomStart: Radius.circular(18),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  child: Container(
                    width: 50, height: 50,
                    decoration: BoxDecoration(
                        color: _iconBg, shape: BoxShape.circle),
                    child: Center(
                      child: Text(cfg.emoji,
                          style: const TextStyle(fontSize: 24)),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          cfg.name(p.locale),
                          style: appFont(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppColors.darkText : AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _subtitle(),
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
                if (pillText != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.greenPale,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      pillText,
                      style: appFont(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.green,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 12),
                  child: _Toggle(
                    value: enabled,
                    color: AppColors.green,
                    onChanged: (v) => p.toggleIslamicEvent(cfg.id, v),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _subtitle() {
    final loc = p.locale;
    if (cfg.isZakat) {
      return loc == 'ar' ? 'موعد سنوي قابل للضبط'
          : loc == 'es' ? 'Vencimiento anual configurable'
          : loc == 'en' ? 'Configurable yearly due date'
          : "Date d'échéance annuelle configurable";
    }
    if (cfg.isDaily) {
      return loc == 'ar' ? 'كل يوم'
          : loc == 'es' ? 'Todos los días'
          : loc == 'en' ? 'Every day'
          : 'Tous les jours';
    }
    if (cfg.isWeekly) {
      // ACTUAL day(s) of the week the observance falls on (e.g.
      // Friday for jumu'ah even though the reminder fires Thursday).
      const dayNames = <int, List<String>>{
        1: ['الإثنين', 'lundi', 'Monday', 'lunes'],
        2: ['الثلاثاء', 'mardi', 'Tuesday', 'martes'],
        3: ['الأربعاء', 'mercredi', 'Wednesday', 'miércoles'],
        4: ['الخميس', 'jeudi', 'Thursday', 'jueves'],
        5: ['الجمعة', 'vendredi', 'Friday', 'viernes'],
        6: ['السبت', 'samedi', 'Saturday', 'sábado'],
        7: ['الأحد', 'dimanche', 'Sunday', 'domingo'],
      };
      final wds = cfg.displayWeekdays;
      final idx = loc == 'ar' ? 0 : loc == 'fr' ? 1 : loc == 'en' ? 2 : 3;
      final names = wds.map((d) => dayNames[d]?[idx] ?? '').toList();
      final joiner = loc == 'ar' ? ' و '
          : loc == 'es' ? ' y '
          : loc == 'en' ? ' & '
          : ' & ';
      final eachPrefix = loc == 'ar' ? 'كل '
          : loc == 'es' ? 'Cada '
          : loc == 'en' ? 'Every '
          : 'Chaque ';
      return '$eachPrefix${names.join(joiner)}';
    }
    if (cfg.isMonthly) {
      // ACTUAL Hijri days of the observance — e.g. 17/19/21 for
      // hijama, 13/14/15 for ayyam-al-bid.
      final days = cfg.displayMonthlyDays;
      final joined = days.join(' - ');
      return loc == 'ar' ? '$joined من كل شهر هجري'
          : loc == 'es' ? '$joined de cada mes hégira'
          : loc == 'en' ? '$joined of every Hijri month'
          : '$joined de chaque mois hégirien';
    }
    // Annual — actual day + canonical Hijri month name.
    if (cfg.displayMonth > 0 && cfg.displayMonth <= 12) {
      return '${cfg.displayDay} ${p.getHijriMonthName(cfg.displayMonth, loc)}';
    }
    return '';
  }

  void _showDetailSheet(BuildContext context) {
    final isDark = p.themeMode == ThemeMode.dark;
    final loc = p.locale;
    final enabled = p.islamicEventsEnabled[cfg.id] ?? cfg.defaultEnabled;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EventDetailSheet(
        cfg: cfg, p: p, isDark: isDark, loc: loc, enabled: enabled),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// DETAIL SHEET
// ═══════════════════════════════════════════════════════════
class _EventDetailSheet extends StatefulWidget {
  final IslamicEventConfig cfg;
  final AppProvider p;
  final bool isDark, enabled;
  final String loc;
  const _EventDetailSheet({required this.cfg, required this.p,
      required this.isDark, required this.enabled, required this.loc});
  @override
  State<_EventDetailSheet> createState() => _EventDetailSheetState();
}

class _EventDetailSheetState extends State<_EventDetailSheet> {
  late bool _enabled;
  @override
  void initState() { super.initState(); _enabled = widget.enabled; }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.cfg;
    final p = widget.p;
    final isDark = widget.isDark;
    final loc = widget.loc;
    final surf = isDark ? AppColors.darkSurface : AppColors.white;

    Color iconBg;
    if (cfg.color == AppColors.gold)  iconBg = AppColors.goldPale;
    else if (cfg.color == AppColors.blue)  iconBg = AppColors.bluePale;
    else if (cfg.color == AppColors.red)   iconBg = const Color(0xFFFDEAEA);
    else if (cfg.color == AppColors.navy)  iconBg = AppColors.bg;
    else iconBg = AppColors.greenPale;

    return Container(
      margin: const EdgeInsets.only(top: 60),
      decoration: BoxDecoration(
        color: surf, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.border,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            // Header
            Row(
              children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(color: iconBg,
                      borderRadius: BorderRadius.circular(16)),
                  child: Center(child: Text(cfg.emoji,
                      style: const TextStyle(fontSize: 28)))),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(cfg.name(loc),
                        style: appFont(fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppColors.darkText : AppColors.navy)),
                      Text(cfg.name('fr'),
                        style: appFont(fontSize: 11, color: AppColors.text3)),
                    ],
                  ),
                ),
                _Toggle(value: _enabled, color: cfg.color, onChanged: (v) {
                  setState(() => _enabled = v);
                  p.toggleIslamicEvent(cfg.id, v);
                }),
              ],
            ),
            const SizedBox(height: 20),
            if (cfg.isZakat)
              _ZakatConfigBlock(p: p, isDark: isDark, loc: loc)
            else
              _TimeRow(p: p, cfg: cfg, isDark: isDark, loc: loc),
            const SizedBox(height: 12),
            // Description
            _InfoBlock(
              title: loc == 'ar' ? 'الوصف' : loc == 'fr' ? 'Description' : 'Description',
              content: cfg.desc(loc), isDark: isDark, icon: Icons.info_outline_rounded),
            const SizedBox(height: 12),
            // Virtue / Hadith — full text, no truncation.
            _InfoBlock(
              title: loc == 'ar' ? 'الفضل' : loc == 'fr' ? 'Vertu / Hadith' : 'Virtue / Hadith',
              content: cfg.virt(loc), isDark: isDark,
              icon: Icons.format_quote_rounded, color: AppColors.gold),
            const SizedBox(height: 16),
            // Close button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _enabled ? AppColors.green : AppColors.text3,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(
                  _enabled
                      ? (loc == 'ar' ? 'مفعّل ✓' : loc == 'fr' ? 'Activé ✓' : 'Enabled ✓')
                      : (loc == 'ar' ? 'غير مفعّل' : loc == 'fr' ? 'Désactivé' : 'Disabled'),
                  style: appFont(fontSize: 14, fontWeight: FontWeight.w700,
                      color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  final String title, content;
  final bool isDark;
  final IconData icon;
  final Color? color;
  const _InfoBlock({required this.title, required this.content,
      required this.isDark, required this.icon, this.color});
  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.green;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBg : AppColors.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 14, color: c),
            const SizedBox(width: 6),
            Text(title, style: appFont(fontSize: 10,
                fontWeight: FontWeight.w700, color: c, letterSpacing: 1)),
          ]),
          const SizedBox(height: 8),
          Text(content, style: appFont(fontSize: 13,
              color: isDark ? AppColors.darkText : AppColors.text,
              height: 1.7)),
        ],
      ),
    );
  }
}

// ── Shared Toggle ─────────────────────────────────────────
class _Toggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  /// Active-state color. Null = follow the current accent
  /// (`AppColors.green`, which is now a runtime getter).
  final Color? color;
  const _Toggle({required this.value, required this.onChanged, this.color});
  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? AppColors.green;
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 36, height: 20, padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: value ? activeColor : Colors.grey.shade300,
          borderRadius: BorderRadius.circular(10)),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(width: 14, height: 14,
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle))),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Per-event notification time — tap to open showTimePicker.
// Drives provider.setIslamicEventTime, which persists and
// re-schedules the next 30 days of reminders for this event.
// ═══════════════════════════════════════════════════════════
class _TimeRow extends StatelessWidget {
  final AppProvider p;
  final IslamicEventConfig cfg;
  final bool isDark;
  final String loc;
  const _TimeRow({
    required this.p,
    required this.cfg,
    required this.isDark,
    required this.loc,
  });

  String _two(int n) => n.toString().padLeft(2, '0');

  Future<void> _pick(BuildContext ctx) async {
    final current = p.islamicEventTime(cfg.id);
    final picked = await showTimePicker(
      context: ctx,
      initialTime: current,
    );
    if (picked == null) return;
    await p.setIslamicEventTime(cfg.id, picked);
  }

  @override
  Widget build(BuildContext context) {
    final t = p.islamicEventTime(cfg.id);
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkBg : AppColors.bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.greenPale,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.alarm_rounded,
                  size: 18, color: AppColors.green),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loc == 'ar' ? 'وقت التذكير'
                        : loc == 'es' ? 'Hora del recordatorio'
                        : loc == 'en' ? 'Reminder time'
                        : 'Heure du rappel',
                    style: appFont(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppColors.darkText : AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    loc == 'ar'
                        ? 'انقر للتعديل'
                        : loc == 'es'
                            ? 'Toca para cambiar'
                            : loc == 'en'
                                ? 'Tap to change'
                                : 'Touchez pour modifier',
                    style: appFont(
                      fontSize: 9,
                      color: AppColors.text3,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.green,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_two(t.hour)}:${_two(t.minute)}',
                style: appFont(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Zakat configuration block — three pickable date+time slots
// (zakat due date, first reminder, second reminder). Each one
// opens showDatePicker then showTimePicker; the result is
// persisted via provider.setZakat* and reschedules notifications.
// ═══════════════════════════════════════════════════════════
class _ZakatConfigBlock extends StatelessWidget {
  final AppProvider p;
  final bool isDark;
  final String loc;
  const _ZakatConfigBlock({
    required this.p,
    required this.isDark,
    required this.loc,
  });

  String _two(int n) => n.toString().padLeft(2, '0');

  String _formatDate(DateTime d) =>
      '${d.day}/${_two(d.month)}/${d.year}  ${_two(d.hour)}:${_two(d.minute)}';

  Future<DateTime?> _pick(BuildContext ctx, DateTime? initial) async {
    final base = initial ?? DateTime.now().add(const Duration(days: 7));
    // Hijri-first calendar-grid picker — matches the monthly view.
    final date = await showCalendarGridPicker(
      context: ctx,
      initial: base,
      useHijri: true,
      locale: loc,
      provider: p,
    );
    if (date == null) return null;
    final time = await showTimePicker(
      context: ctx,
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Widget _row({
    required BuildContext context,
    required String label,
    required DateTime? value,
    required ValueChanged<DateTime?> onPicked,
  }) {
    final placeholder = loc == 'ar' ? 'انقر للضبط'
        : loc == 'es' ? 'Toca para configurar'
        : loc == 'en' ? 'Tap to configure'
        : 'Touchez pour configurer';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBg : AppColors.bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final picked = await _pick(context, value);
          if (picked == null) return;
          onPicked(picked);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppColors.greenPale,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.alarm_rounded,
                    size: 18, color: AppColors.green),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: appFont(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isDark ? AppColors.darkText : AppColors.text,
                        )),
                    const SizedBox(height: 2),
                    Text(
                      value == null ? placeholder : _formatDate(value),
                      style: appFont(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: value == null
                            ? AppColors.text3
                            : AppColors.green,
                      ),
                    ),
                  ],
                ),
              ),
              if (value != null)
                IconButton(
                  tooltip: loc == 'ar' ? 'حذف' : 'Effacer',
                  icon: const Icon(Icons.close_rounded,
                      size: 16, color: AppColors.text3),
                  onPressed: () => onPicked(null),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dueLabel = loc == 'ar' ? 'تاريخ استحقاق الزكاة'
        : loc == 'es' ? 'Fecha de vencimiento de la Zakat'
        : loc == 'en' ? 'Zakat due date'
        : "Date d'échéance de la Zakât";
    final r1Label = loc == 'ar' ? 'التذكير الأول'
        : loc == 'es' ? 'Primer recordatorio'
        : loc == 'en' ? 'First reminder'
        : 'Premier rappel';
    final r2Label = loc == 'ar' ? 'التذكير الثاني'
        : loc == 'es' ? 'Segundo recordatorio'
        : loc == 'en' ? 'Second reminder'
        : 'Deuxième rappel';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row(
          context: context,
          label: dueLabel,
          value: p.zakatDueDate,
          onPicked: p.setZakatDueDate,
        ),
        _row(
          context: context,
          label: r1Label,
          value: p.zakatReminder1,
          onPicked: p.setZakatReminder1,
        ),
        _row(
          context: context,
          label: r2Label,
          value: p.zakatReminder2,
          onPicked: p.setZakatReminder2,
        ),
      ],
    );
  }
}
