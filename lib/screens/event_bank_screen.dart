import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../data/islamic_events.dart';
import '../providers/app_provider.dart';
import '../utils/hijri_utils.dart';
import '../theme.dart';

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
    final bg = isDark ? AppColors.darkSurface : AppColors.navy;
    final loc = p.locale;
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
                  Text(p.label('islamic_events_bank'),
                    style: GoogleFonts.amiri(fontSize: 20,
                        fontWeight: FontWeight.bold, color: Colors.white)),
                  Text(loc == 'fr' ? "Banque d'événements islamiques"
                      : loc == 'en' ? 'Islamic Events Bank'
                      : "Banque d'événements islamiques",
                    style: GoogleFonts.cairo(fontSize: 10, color: Colors.white54)),
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
                    style: GoogleFonts.cairo(fontSize: 13, color: Colors.white),
                    decoration: InputDecoration(
                      border: InputBorder.none, isDense: true,
                      hintText: loc == 'ar' ? 'بحث...'
                          : loc == 'fr' ? 'Rechercher...' : 'Search...',
                      hintStyle: GoogleFonts.cairo(color: Colors.white54, fontSize: 13),
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
              style: GoogleFonts.cairo(fontSize: 12,
                  fontWeight: FontWeight.w700, color: Colors.white))),
            Text('${IslamicEventsData.events.length}',
              style: GoogleFonts.cairo(fontSize: 10, color: Colors.white54)),
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
    final monthly = filtered(IslamicEventsData.events.where((e) => e.isMonthly).toList());
    final annual  = filtered(IslamicEventsData.events.where(
        (e) => !e.isDaily && !e.isMonthly && !e.isWeekly).toList());
    final weekly  = filtered(IslamicEventsData.events.where((e) => e.isWeekly).toList());

    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        if (daily.isNotEmpty) ...[
          _SectionDivider(
            label: loc == 'ar' ? 'يومي' : loc == 'fr' ? 'Quotidien' : 'Daily',
            icon: '🌅', isDark: isDark),
          ...daily.map((e) => _EventRow(cfg: e, p: p, isDark: isDark)),
        ],
        if (monthly.isNotEmpty) ...[
          _SectionDivider(
            label: loc == 'ar' ? 'شهري' : loc == 'fr' ? 'Mensuel' : 'Monthly',
            icon: '📅', isDark: isDark),
          ...monthly.map((e) => _EventRow(cfg: e, p: p, isDark: isDark)),
        ],
        if (annual.isNotEmpty) ...[
          _SectionDivider(
            label: loc == 'ar' ? 'سنوي' : loc == 'fr' ? 'Annuel' : 'Annual',
            icon: '🌙', isDark: isDark),
          ...annual.map((e) => _EventRow(cfg: e, p: p, isDark: isDark)),
        ],
        if (weekly.isNotEmpty) ...[
          _SectionDivider(
            label: loc == 'ar' ? 'أسبوعي' : loc == 'fr' ? 'Hebdomadaire' : 'Weekly',
            icon: '📿', isDark: isDark),
          ...weekly.map((e) => _EventRow(cfg: e, p: p, isDark: isDark)),
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
              style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.w700,
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

  int? _daysUntil() {
    try {
      final today = HijriDate.now();
      final todayG = today.toGregorian();
      // For monthly events, find next occurrence
      if (cfg.isMonthly) {
        int targetDay = cfg.day;
        // For Ayyam Al-Bid, show days until 13th
        if (cfg.id == 'ayyam_albid') targetDay = 13;
        if (cfg.id == 'hijama') targetDay = 17;
        final g = HijriDate.hijriToGregorian(today.hYear, today.hMonth, targetDay);
        final diff = g.difference(todayG).inDays;
        if (diff < 0) {
          final next = HijriDate(today.hYear, today.hMonth + 1, targetDay);
          final gNext = next.toGregorian();
          return gNext.difference(todayG).inDays;
        }
        return diff;
      }
      // Annual
      if (!cfg.isWeekly && !cfg.isDaily && cfg.month > 0) {
        var targetYear = today.hYear;
        var g = HijriDate.hijriToGregorian(targetYear, cfg.month, cfg.day);
        if (g.isBefore(todayG)) {
          g = HijriDate.hijriToGregorian(targetYear + 1, cfg.month, cfg.day);
        }
        final diff = g.difference(todayG).inDays;
        return diff <= 30 ? diff : null;
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = p.islamicEventsEnabled[cfg.id] ?? cfg.defaultEnabled;
    final surf = isDark ? AppColors.darkSurface : AppColors.white;
    final daysUntil = _daysUntil();

    return GestureDetector(
      onTap: () => _showDetailSheet(context),
      child: Opacity(
        opacity: enabled ? 1.0 : 0.5,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          decoration: BoxDecoration(
            color: surf,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4)],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                      color: _iconBg, borderRadius: BorderRadius.circular(12)),
                  child: Center(child: Text(cfg.emoji,
                      style: const TextStyle(fontSize: 18))),
                ),
                const SizedBox(width: 12),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(cfg.name(p.locale),
                        style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w700,
                            color: isDark ? AppColors.darkText : AppColors.text)),
                      Text(_subtitle(),
                        style: GoogleFonts.cairo(fontSize: 9, color: AppColors.text3)),
                    ],
                  ),
                ),
                // Days-until badge
                if (daysUntil != null && daysUntil <= 30) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: daysUntil <= 3 ? AppColors.goldPale : AppColors.greenPale,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      daysUntil == 0
                          ? (p.locale == 'ar' ? 'اليوم' : p.locale == 'fr' ? "Auj." : 'Today')
                          : (p.locale == 'ar' ? 'بعد $daysUntil' : 'J-$daysUntil'),
                      style: GoogleFonts.cairo(fontSize: 8, fontWeight: FontWeight.w700,
                          color: daysUntil <= 3 ? AppColors.gold : AppColors.green)),
                  ),
                  const SizedBox(width: 8),
                ],
                // Toggle
                _Toggle(
                  value: enabled, color: cfg.color,
                  onChanged: (v) => p.toggleIslamicEvent(cfg.id, v)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _subtitle() {
    final loc = p.locale;
    if (cfg.isDaily) {
      return loc == 'ar' ? 'كل يوم' : loc == 'fr' ? 'Tous les jours' : 'Every day';
    }
    if (cfg.isWeekly) {
      if (cfg.weekday == 5) {
        return loc == 'ar' ? 'كل جمعة' : loc == 'fr' ? 'Chaque vendredi' : 'Every Friday';
      }
      return loc == 'ar' ? 'كل اثنين وخميس'
          : loc == 'fr' ? 'Chaque lundi et jeudi'
          : 'Every Mon & Thu';
    }
    if (cfg.isMonthly) {
      // Per spec: numbers must always be Western digits (0-9) in
      // every locale, including Arabic.
      if (cfg.id == 'ayyam_albid') {
        return loc == 'ar' ? '13 · 14 · 15 كل شهر'
            : loc == 'fr' ? '13 · 14 · 15 chaque mois'
            : loc == 'es' ? '13 · 14 · 15 cada mes'
            : '13 · 14 · 15 each month';
      }
      if (cfg.id == 'hijama') {
        return loc == 'ar' ? '17 · 19 · 21 كل شهر'
            : loc == 'fr' ? '17 · 19 · 21 chaque mois'
            : loc == 'es' ? '17 · 19 · 21 cada mes'
            : '17 · 19 · 21 each month';
      }
      return loc == 'ar' ? 'كل شهر'
          : loc == 'fr' ? 'Mensuel'
          : loc == 'es' ? 'Mensual'
          : 'Monthly';
    }
    // Annual: reuse the canonical month list from the provider so
    // spellings stay consistent across the whole app.
    if (cfg.month > 0 && cfg.month <= 12) {
      return '${cfg.day} ${p.getHijriMonthName(cfg.month, loc)}';
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
                        style: GoogleFonts.amiri(fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppColors.darkText : AppColors.navy)),
                      Text(cfg.name('fr'),
                        style: GoogleFonts.cairo(fontSize: 11, color: AppColors.text3)),
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
            // Description
            _InfoBlock(
              title: loc == 'ar' ? 'الوصف' : loc == 'fr' ? 'Description' : 'Description',
              content: cfg.desc(loc), isDark: isDark, icon: Icons.info_outline_rounded),
            const SizedBox(height: 12),
            // Virtue / Hadith
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
                  style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w700,
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
            Text(title, style: GoogleFonts.cairo(fontSize: 10,
                fontWeight: FontWeight.w700, color: c, letterSpacing: 1)),
          ]),
          const SizedBox(height: 8),
          Text(content, style: GoogleFonts.cairo(fontSize: 13,
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
  final Color color;
  const _Toggle({required this.value, required this.onChanged, this.color = AppColors.green});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 36, height: 20, padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: value ? color : Colors.grey.shade300,
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
