import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/notification_settings.dart';
import '../providers/app_provider.dart';
import '../services/country_detector.dart';
import '../utils/text_format.dart';
import '../utils/app_logger.dart';
import '../theme.dart';
import '../data/hijri_countries.dart';
import '../widgets/gps_rationale_dialog.dart';
import '../widgets/hijri_source_badge.dart';
import 'notification_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    final isDark = p.themeMode == ThemeMode.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.bg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _SectionTitle(
              text: p.label('settings'), isDark: isDark, large: true)),
            SliverToBoxAdapter(child: _ProfileCard(isDark: isDark, p: p)),
            SliverToBoxAdapter(child: _LanguageSection(p: p, isDark: isDark)),
            SliverToBoxAdapter(child: _HijriSourceSection(p: p, isDark: isDark)),
            SliverToBoxAdapter(child: _AppearanceSection(p: p, isDark: isDark)),
            SliverToBoxAdapter(child: _CalendarSection(p: p, isDark: isDark)),
            SliverToBoxAdapter(child: _NotificationsSection(p: p, isDark: isDark)),
            SliverToBoxAdapter(child: _AboutSection(p: p, isDark: isDark)),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }
}

// ─── Shared helpers ───────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  final String text;
  final bool isDark, large;
  const _SectionTitle({required this.text, required this.isDark, this.large = false});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, large ? 12 : 16, 16, large ? 4 : 6),
      child: Text(text,
        style: large
          ? appFont(fontSize: 26, fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkText : AppColors.navy)
          : appFont(fontSize: 10, fontWeight: FontWeight.w700,
              color: AppColors.text3, letterSpacing: 2)),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  final bool isDark;
  final EdgeInsets? padding;
  const _Card({required this.child, required this.isDark, this.padding});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    decoration: BoxDecoration(
      color: isDark ? AppColors.darkSurface : AppColors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4)],
    ),
    child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
  );
}

class _SettRow extends StatelessWidget {
  final String emoji, title, sub;
  final Color bg;
  final Widget trailing;
  final VoidCallback? onTap;
  final bool isDark, last;
  const _SettRow({required this.emoji, required this.bg, required this.title,
      required this.sub, required this.trailing, this.onTap,
      required this.isDark, this.last = false});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: last ? null : BoxDecoration(
          border: Border(bottom: BorderSide(
              color: isDark ? AppColors.darkBorder : AppColors.border))),
        child: Row(
          children: [
            Container(width: 34, height: 34,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
              child: Center(child: Text(emoji, style: const TextStyle(fontSize: 16)))),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: appFont(fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.darkText : AppColors.text)),
                if (sub.isNotEmpty) Text(sub, style: appFont(
                    fontSize: 9, color: AppColors.text3)),
              ],
            )),
            trailing,
            const SizedBox(width: 4),
            Icon(Icons.chevron_left, size: 14, color: AppColors.text3),
          ],
        ),
      ),
    );
  }
}

class _SmToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SmToggle({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle))),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 1. PROFILE
// ═══════════════════════════════════════════════════════════
class _ProfileCard extends StatelessWidget {
  final bool isDark;
  final AppProvider p;
  const _ProfileCard({required this.isDark, required this.p});
  @override
  Widget build(BuildContext context) {
    // Region-aware: read today's Hijri from the provider so the card
    // follows the regional offset (Morocco = UAQ + 1 day, etc.). The
    // displayed Gregorian is the regional Hijri's matching civil
    // date so the two stay paired when the user switches region.
    final today = p.today;
    final greg = today.toGregorian();
    final loc = p.locale;
    final appTitle = loc == 'ar' ? 'بدر | badr' : 'بدر | badr';
    final hijriLine = TextFormat.toWesternDigits(
        '${today.hDay} ${p.getHijriMonthName(today.hMonth, loc)} ${today.hYear}');
    final gregStr = TextFormat.toWesternDigits(
        TextFormat.formatGregorianFull(greg, loc));

    return _Card(
      isDark: isDark,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.green,
                      Color.lerp(AppColors.green, Colors.black, 0.25)!,
                    ],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(18)),
                child: const Center(child: Text('🌙', style: TextStyle(fontSize: 28)))),
              const SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(appTitle, style: appFont(
                      fontSize: 18, fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.darkText : AppColors.navy)),
                  // Phase-7 improvement 5 — small source dot
                  // inline with the Hijri date instead of the
                  // full-width verbose badge that used to sit
                  // below. Same tap target (info sheet), less
                  // vertical real estate.
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          hijriLine,
                          style: appFont(
                            fontSize: 11,
                            color: AppColors.green,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      HijriSourceDot(
                        size: 12,
                        darkOverride: isDark,
                      ),
                    ],
                  ),
                  Text(gregStr, style: appFont(fontSize: 10, color: AppColors.text3)),
                ],
              )),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.greenPale, borderRadius: BorderRadius.circular(12)),
                child: Column(children: [
                  Text('${today.hYear}', style: appFont(
                      fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.green)),
                  Text(p.locale == 'ar' ? 'هـ' : 'AH',
                    style: appFont(fontSize: 8, color: AppColors.green)),
                ])),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 2. LANGUAGE & REGION
// ═══════════════════════════════════════════════════════════
class _LanguageSection extends StatelessWidget {
  final AppProvider p;
  final bool isDark;
  const _LanguageSection({required this.p, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final loc = p.locale;
    const langs = [
      ('ar', '🇲🇦', 'عربي'), ('fr', '🇫🇷', 'FR'),
      ('en', '🇬🇧', 'EN'),   ('es', '🇪🇸', 'ES'),
    ];
    // Region picker was extracted into its own
    // `_HijriSourceSection` (Phase 6) — it now offers all 30
    // AlAdhan-supported countries plus auto-detect / refresh /
    // manual adjustment in a single dedicated card.

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          text: loc == 'ar' ? 'اللغة'
              : loc == 'fr' ? 'LANGUE' : 'LANGUAGE',
          isDark: isDark),
        _Card(
          isDark: isDark,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(loc == 'ar' ? 'اللغة' : 'Langue',
                style: appFont(fontSize: 10, fontWeight: FontWeight.w700,
                    color: AppColors.text3, letterSpacing: 2)),
              const SizedBox(height: 8),
              Row(
                children: langs.map((l) {
                  final active = p.locale == l.$1;
                  return Expanded(child: GestureDetector(
                    onTap: () => p.setLocale(l.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: active ? AppColors.navy
                            : (isDark ? AppColors.darkBg : AppColors.bg),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: active ? AppColors.navy
                              : (isDark ? AppColors.darkBorder : AppColors.border),
                          width: active ? 1.5 : 1)),
                      child: Column(children: [
                        Text(l.$2, style: const TextStyle(fontSize: 16)),
                        const SizedBox(height: 2),
                        Text(l.$3, style: appFont(fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: active ? Colors.white
                                : (isDark ? AppColors.darkText3 : AppColors.text3))),
                      ]),
                    ),
                  ));
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 2b. HIJRI CALENDAR SOURCE — country, authority, sync, manual adj
// ═══════════════════════════════════════════════════════════
//
// The new picker for the Hybrid Hijri Calendar. Shows the
// active country + the religious authority whose calendar is
// being followed, exposes a 30-country picker bottom sheet, an
// auto-detect button (GPS + locale), a "refresh now" trigger
// with a "last sync" timestamp, and the manual ±3-day
// adjustment row. Replaces the old 2-region toggle that lived
// at the bottom of [_LanguageSection].
class _HijriSourceSection extends StatefulWidget {
  final AppProvider p;
  final bool isDark;
  const _HijriSourceSection({required this.p, required this.isDark});

  @override
  State<_HijriSourceSection> createState() => _HijriSourceSectionState();
}

class _HijriSourceSectionState extends State<_HijriSourceSection> {
  bool _refreshing = false;
  bool _detecting = false;

  /// Phase-7 improvement 6 — collapsible "advanced" subsection
  /// at the bottom of the card. False by default so a typical
  /// user sees only the four essentials (country picker, auto-
  /// detect, refresh, last sync). Power users tap "Advanced
  /// options" to reveal the manual ±3 adjuster, the hybrid
  /// safety toggle, and the clear-cache action.
  bool _advancedOpen = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final loc = p.locale;
    final isDark = widget.isDark;
    final activeCountry = hijriCountryByCode(p.country);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          text: p.label('hijri_source').toUpperCase(),
          isDark: isDark,
        ),
        _Card(
          isDark: isDark,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── Country picker tile ─────────────────────
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openCountryPicker(context, p),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkBg : AppColors.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.green.withValues(alpha: 0.35),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(activeCountry.flag,
                          style: const TextStyle(fontSize: 26)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              activeCountry.localizedName(loc),
                              style: appFont(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? AppColors.darkText
                                    : AppColors.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              activeCountry.localizedAuthority(loc),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: appFont(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                                color: AppColors.text3,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right_rounded,
                          color: AppColors.text3, size: 22),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // ─── Auto-detect + Refresh row ───────────────
              //
              // Both buttons disable themselves when the hybrid
              // engine is off — pressing them would do nothing
              // useful since the kernel ignores cache writes in
              // that mode anyway. The visual greying-out (handled
              // inside `_PillButton` via the `onTap: null` path)
              // is enough; no separate tooltip needed.
              Row(
                children: [
                  Expanded(
                    child: _PillButton(
                      icon: Icons.my_location_rounded,
                      label: _detecting
                          ? p.label('hijri_source_detecting')
                          : p.label('hijri_source_auto_detect'),
                      busy: _detecting,
                      isDark: isDark,
                      onTap: (_detecting || !p.useHybridHijri)
                          ? null
                          : () => _onDetect(p),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _PillButton(
                      icon: Icons.refresh_rounded,
                      label: _refreshing
                          ? p.label('hijri_source_refreshing')
                          : p.label('hijri_source_refresh'),
                      busy: _refreshing,
                      isDark: isDark,
                      onTap: (_refreshing || !p.useHybridHijri)
                          ? null
                          : () => _onRefresh(p),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ─── Last sync info ──────────────────────────
              _LastSyncRow(p: p, isDark: isDark),

              const SizedBox(height: 10),

              // ─── Phase-7 improvement 6 — collapsible advanced
              // subsection. The three power-user controls below
              // (±3 adjuster, online-toggle, cache reset) hide
              // by default so a typical user sees a clean card.
              const Divider(height: 18, thickness: 0.5),
              _AdvancedToggleHeader(
                p: p,
                isDark: isDark,
                open: _advancedOpen,
                onTap: () =>
                    setState(() => _advancedOpen = !_advancedOpen),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _advancedOpen
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ─── Manual ±3-day adjuster ──────
                            _HijriAdjustRow(p: p, isDark: isDark),
                            const Divider(
                                height: 18, thickness: 0.5),
                            // ─── Hybrid online/offline toggle ──
                            _HybridToggleRow(p: p, isDark: isDark),
                            const SizedBox(height: 8),
                            // ─── Clear local cache ─────────────
                            _ClearCacheLink(p: p, isDark: isDark),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _onDetect(AppProvider p) async {
    // Step 1 — rationale. Mirrors the Onboarding flow so the
    // user sees the same explanation in both places.
    final allowed = await showGpsRationaleDialog(
      context: context,
      locale: p.locale,
    );
    if (!mounted || !allowed) return;

    // Step 2 — pre-check the OS-level Location switch. If it's
    // off, route to system settings; granting the app
    // permission alone wouldn't help.
    final servicesOn = await CountryDetector.isLocationServiceEnabled();
    if (!mounted) return;
    if (!servicesOn) {
      final wantsToOpen = await showGpsServiceOffDialog(
        context: context,
        locale: p.locale,
      );
      if (!mounted) return;
      if (wantsToOpen) {
        await CountryDetector.openLocationSettings();
      }
      return;
    }

    // Step 3 — status-aware detect. Each terminal status gets a
    // specific UI affordance (open settings, retry hint, etc.)
    // so the user knows exactly what to do next.
    setState(() => _detecting = true);
    CountryDetectionResult result;
    try {
      result = await p.detectCountryWithStatus();
    } catch (e, st) {
      AppLogger.error('Settings auto-detect failed', error: e, stack: st);
      result = const CountryDetectionResult(
        code: 'XX',
        status: CountryDetectionStatus.noSignal,
      );
    }
    if (!mounted) return;
    setState(() => _detecting = false);

    final loc = p.locale;
    switch (result.status) {
      case CountryDetectionStatus.gpsOk:
      case CountryDetectionStatus.timezoneOk:
      case CountryDetectionStatus.localeOk:
        final c = hijriCountryByCode(result.code);
        _snack(
          context,
          '${p.label('hijri_source_detected')} — ${c.flag} ${c.localizedName(loc)}',
          success: true,
        );
        break;
      case CountryDetectionStatus.serviceDisabled:
        // Race: services were disabled between our pre-check
        // and the detect itself. Re-route to settings.
        final wantsToOpen = await showGpsServiceOffDialog(
          context: context,
          locale: loc,
        );
        if (mounted && wantsToOpen) {
          await CountryDetector.openLocationSettings();
        }
        break;
      case CountryDetectionStatus.permissionDeniedForever:
        _snack(
          context,
          switch (loc) {
            'ar' => 'الإذن مرفوض دائماً — فعّله من إعدادات التطبيق',
            'fr' => 'Permission refusée — activez-la dans les réglages',
            'es' => 'Permiso denegado — actívalo en ajustes',
            _ => 'Permission denied — enable it in app settings',
          },
          success: false,
          actionLabel: switch (loc) {
            'ar' => 'فتح',
            'fr' => 'Ouvrir',
            'es' => 'Abrir',
            _ => 'Open',
          },
          onAction: CountryDetector.openAppSettings,
        );
        break;
      case CountryDetectionStatus.permissionDenied:
        _snack(
          context,
          switch (loc) {
            'ar' => 'إذن الموقع لم يُمنح — اضغط مجدداً للمحاولة',
            'fr' => 'Permission refusée — touchez à nouveau pour réessayer',
            'es' => 'Permiso denegado — toca de nuevo para reintentar',
            _ => 'Permission denied — tap again to retry',
          },
          success: false,
        );
        break;
      case CountryDetectionStatus.timeout:
        _snack(
          context,
          switch (loc) {
            'ar' => 'انتهت المهلة — قد يستغرق GPS وقتاً، أعد المحاولة',
            'fr' => 'Délai dépassé — le GPS met du temps, réessayez',
            'es' => 'Tiempo agotado — el GPS tarda, reintenta',
            _ => 'Timed out — GPS can take a moment, try again',
          },
          success: false,
        );
        break;
      case CountryDetectionStatus.noSignal:
      case CountryDetectionStatus.unsupported:
        _snack(
          context,
          p.label('hijri_source_detect_fail'),
          success: false,
        );
        break;
    }
  }

  Future<void> _onRefresh(AppProvider p) async {
    setState(() => _refreshing = true);
    bool ok = false;
    try {
      ok = await p.refreshHijriCalendarNow();
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() => _refreshing = false);
    _snack(
      context,
      p.label(ok ? 'hijri_source_sync_ok' : 'hijri_source_sync_fail'),
      success: ok,
    );
  }

  void _snack(
    BuildContext context,
    String text, {
    required bool success,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text, style: appFont(fontSize: 12.5, color: Colors.white)),
        backgroundColor: success
            ? AppColors.green
            : const Color(0xFFD94F4F),
        behavior: SnackBarBehavior.floating,
        // Longer hold for error snacks so the user has time to
        // read the "what to do next" guidance + optional
        // action button.
        duration: Duration(milliseconds: success ? 2400 : 3600),
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        action: (actionLabel != null && onAction != null)
            ? SnackBarAction(
                label: actionLabel,
                textColor: Colors.white,
                onPressed: onAction,
              )
            : null,
      ));
  }

  Future<void> _openCountryPicker(BuildContext context, AppProvider p) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CountryPickerSheet(p: p, isDark: widget.isDark),
    );
  }
}

// ─── Pill button with optional loading spinner ──────────────
class _PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool busy;
  final bool isDark;
  final VoidCallback? onTap;
  const _PillButton({
    required this.icon,
    required this.label,
    required this.busy,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: enabled ? 1.0 : 0.55,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkBg : AppColors.bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFFC8943A)),
                  ),
                )
              else
                Icon(icon, size: 16, color: AppColors.green),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: appFont(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.darkText : AppColors.text,
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

// ─── "Last update: 3h ago" row ─────────────────────────────
class _LastSyncRow extends StatelessWidget {
  final AppProvider p;
  final bool isDark;
  const _LastSyncRow({required this.p, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final ts = p.hijriLastSync;
    final text = ts == null
        ? p.label('hijri_source_never_synced')
        : '${p.label('hijri_source_last_sync')}: ${_formatAgo(p, ts)}';
    final color = ts == null ? AppColors.text3 : AppColors.green;
    return Row(
      children: [
        Icon(
          ts == null
              ? Icons.cloud_off_rounded
              : Icons.cloud_done_rounded,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            style: appFont(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isDark ? AppColors.darkText2 : AppColors.text2,
              height: 1.35,
            ),
          ),
        ),
        if (ts != null) ...[
          const SizedBox(width: 6),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.55),
                  blurRadius: 5,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Humanises a timestamp into a localized "Nh ago" string.
  /// Uses the four pre-translated buckets in the provider's
  /// label map (`hijri_source_just_now`, `..._minutes_ago`,
  /// `..._hours_ago`, `..._days_ago`) with `{n}` substitution.
  static String _formatAgo(AppProvider p, DateTime ts) {
    final diff = DateTime.now().difference(ts);
    if (diff.inMinutes < 1) return p.label('hijri_source_just_now');
    if (diff.inHours < 1) {
      return p
          .label('hijri_source_minutes_ago')
          .replaceAll('{n}', '${diff.inMinutes}');
    }
    if (diff.inDays < 1) {
      return p
          .label('hijri_source_hours_ago')
          .replaceAll('{n}', '${diff.inHours}');
    }
    return p
        .label('hijri_source_days_ago')
        .replaceAll('{n}', '${diff.inDays}');
  }
}

// ─── Country picker modal bottom sheet ─────────────────────
class _CountryPickerSheet extends StatefulWidget {
  final AppProvider p;
  final bool isDark;
  const _CountryPickerSheet({required this.p, required this.isDark});

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final loc = p.locale;
    final isDark = widget.isDark;
    final media = MediaQuery.of(context);

    final filtered = _filter.isEmpty
        ? kHijriCountries
        : kHijriCountries.where((c) {
            final needle = _filter.toLowerCase();
            return c.localizedName(loc).toLowerCase().contains(needle) ||
                c.code.toLowerCase().contains(needle);
          }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.white,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(22),
          ),
        ),
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: Column(
          children: [
            // Grab handle
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
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      p.label('hijri_source_select_title'),
                      style: appFont(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: isDark ? AppColors.darkText : AppColors.text,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 22,
                      color: isDark ? AppColors.darkText3 : AppColors.text3,
                    ),
                  ),
                ],
              ),
            ),
            // ─── Search field ──────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                onChanged: (v) => setState(() => _filter = v),
                style: appFont(
                  fontSize: 13,
                  color: isDark ? AppColors.darkText : AppColors.text,
                ),
                decoration: InputDecoration(
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: AppColors.text3,
                  ),
                  hintText: loc == 'ar'
                      ? 'ابحث…'
                      : loc == 'fr'
                          ? 'Rechercher…'
                          : loc == 'es'
                              ? 'Buscar…'
                              : 'Search…',
                  hintStyle: appFont(fontSize: 13, color: AppColors.text3),
                  filled: true,
                  fillColor: isDark ? AppColors.darkBg : AppColors.bg,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDark
                          ? AppColors.darkBorder
                          : AppColors.border,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppColors.green,
                      width: 1.5,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDark
                          ? AppColors.darkBorder
                          : AppColors.border,
                    ),
                  ),
                ),
              ),
            ),
            // ─── Country list ──────────────────────────────
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 2),
                itemBuilder: (_, i) {
                  final c = filtered[i];
                  final active = p.country == c.code;
                  return _CountryRow(
                    country: c,
                    active: active,
                    locale: loc,
                    isDark: isDark,
                    onTap: () async {
                      await p.setCountry(c.code);
                      // `context.mounted` ties the guard directly
                      // to the BuildContext we're about to use,
                      // which silences the analyzer's
                      // `use_build_context_synchronously` warning.
                      if (!context.mounted) return;
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountryRow extends StatelessWidget {
  final HijriCountry country;
  final bool active;
  final String locale;
  final bool isDark;
  final VoidCallback onTap;
  const _CountryRow({
    required this.country,
    required this.active,
    required this.locale,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: active
                ? AppColors.green.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active
                  ? AppColors.green.withValues(alpha: 0.55)
                  : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              Text(country.flag, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      country.localizedName(locale),
                      style: appFont(
                        fontSize: 13.5,
                        fontWeight: active
                            ? FontWeight.w800
                            : FontWeight.w700,
                        color: isDark ? AppColors.darkText : AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      country.localizedAuthority(locale),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: appFont(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w400,
                        color: AppColors.text3,
                      ),
                    ),
                  ],
                ),
              ),
              if (active)
                Icon(
                  Icons.check_circle_rounded,
                  size: 20,
                  color: AppColors.green,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Phase 9 — hybrid on/off toggle row ─────────────────────
//
// Sits at the bottom of the Hijri-source card. When OFF, the
// kernel falls back to the local arithmetic engine for every
// conversion (pre-hybrid behaviour). The label + hint are
// localized into all four supported app languages.
class _HybridToggleRow extends StatelessWidget {
  final AppProvider p;
  final bool isDark;
  const _HybridToggleRow({required this.p, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.label('hijri_source_use_online'),
                style: appFont(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.darkText : AppColors.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                p.label('hijri_source_use_online_hint'),
                style: appFont(
                  fontSize: 10,
                  fontWeight: FontWeight.w400,
                  color: AppColors.text3,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Transform.scale(
          scale: 0.85,
          child: Switch.adaptive(
            value: p.useHybridHijri,
            onChanged: (v) => p.setUseHybridHijri(v),
            activeThumbColor: AppColors.green,
          ),
        ),
      ],
    );
  }
}

// ─── Phase 9 — clear-cache escape hatch ─────────────────────
//
// A tiny inline link rather than a button — feels like a safe
// "recovery action" and not something the user would tap by
// accident. Surfaces a SnackBar after the cache is wiped so
// the user sees confirmation that the action took effect.
//
// Phase-7 improvement 6 — this link is now hidden by default
// inside the collapsible "Advanced options" subsection in
// `_HijriSourceSection` so it doesn't draw eyes on first
// visit; the user has to consciously expand the section to
// reach it.
class _AdvancedToggleHeader extends StatelessWidget {
  final AppProvider p;
  final bool isDark;
  final bool open;
  final VoidCallback onTap;
  const _AdvancedToggleHeader({
    required this.p,
    required this.isDark,
    required this.open,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final loc = p.locale;
    final label = switch (loc) {
      'ar' => 'إعدادات متقدّمة',
      'fr' => 'Options avancées',
      'es' => 'Opciones avanzadas',
      _ => 'Advanced options',
    };
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: appFont(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text3,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            // Rotates 0° (closed) → 180° (open). Smooth wedge
            // animation so the user understands the section is
            // about to expand.
            AnimatedRotation(
              duration: const Duration(milliseconds: 200),
              turns: open ? 0.5 : 0,
              child: const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: AppColors.text3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClearCacheLink extends StatelessWidget {
  final AppProvider p;
  final bool isDark;
  const _ClearCacheLink({required this.p, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        onPressed: () async {
          await p.clearHijriCache();
          if (!context.mounted) return;
          ScaffoldMessenger.of(context)
            ..removeCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Text(
                p.label('hijri_source_cache_cleared'),
                style: appFont(fontSize: 12.5, color: Colors.white),
              ),
              backgroundColor: AppColors.green,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(milliseconds: 2000),
              margin: const EdgeInsets.all(12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ));
        },
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
          minimumSize: const Size(0, 28),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: AppColors.green,
        ),
        icon: const Icon(Icons.delete_sweep_outlined, size: 14),
        label: Text(
          p.label('hijri_source_clear_cache'),
          style: appFont(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.green,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 3. APPEARANCE
// ═══════════════════════════════════════════════════════════
class _AppearanceSection extends StatelessWidget {
  final AppProvider p;
  final bool isDark;
  const _AppearanceSection({required this.p, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final loc = p.locale;
    final themeLabel = p.themeMode == ThemeMode.dark
        ? p.label('dark') : p.label('light');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          text: loc == 'ar' ? 'المظهر' : loc == 'fr' ? 'APPARENCE' : 'APPEARANCE',
          isDark: isDark),
        _Card(
          isDark: isDark,
          child: Column(
            children: [
              // Theme
              _SettRow(
                emoji: p.themeMode == ThemeMode.dark ? '🌙' : '☀️',
                bg: AppColors.goldPale,
                title: p.label('theme'),
                sub: 'Thème de l\'application',
                trailing: Text(themeLabel,
                  style: appFont(fontSize: 11, fontWeight: FontWeight.w700,
                      color: AppColors.green)),
                isDark: isDark,
                onTap: () => p.setThemeMode(
                  p.themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark),
              ),
              // Accent color — functional 8-swatch picker.
              _AccentColorRow(p: p, isDark: isDark),
              // Font type — picks one of the localized fonts and
              // pushes it into Theme.of(context).textTheme.
              _FontFamilyRow(p: p, isDark: isDark),
              // Font size — wires to provider.setFontScale.
              _FontScaleRow(p: p, isDark: isDark),
              // Calendar density — wires to provider.setCalendarDensity.
              _CalendarDensityRow(p: p, isDark: isDark, last: true),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 4. CALENDAR SETTINGS
// ═══════════════════════════════════════════════════════════
//
// Note: the former "Show / Afficher / إظهار" subsection — which
// hosted toggles for Ayyam Al-Bid, Ramadan, Gregorian date, dual
// header and Friday highlight — was removed per spec. The Calendar
// card now contains only the default-view picker.
class _CalendarSection extends StatelessWidget {
  final AppProvider p;
  final bool isDark;
  const _CalendarSection({required this.p, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final loc = p.locale;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          text: loc == 'ar' ? 'إعدادات التقويم'
              : loc == 'fr' ? 'CALENDRIER' : 'CALENDAR',
          isDark: isDark),
        _Card(
          isDark: isDark,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Default view — drives provider.viewMode and is
              // persisted in SharedPreferences.
              Text(loc == 'ar' ? 'العرض الافتراضي'
                  : loc == 'fr' ? 'Vue par défaut'
                  : loc == 'es' ? 'Vista por defecto'
                  : 'Default view',
                style: appFont(fontSize: 10, fontWeight: FontWeight.w700,
                    color: AppColors.text3)),
              const SizedBox(height: 8),
              _ViewModePicker(p: p, isDark: isDark),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 5. NOTIFICATIONS
// ═══════════════════════════════════════════════════════════
class _NotificationsSection extends StatefulWidget {
  final AppProvider p;
  final bool isDark;
  const _NotificationsSection({required this.p, required this.isDark});
  @override
  State<_NotificationsSection> createState() => _NotificationsSectionState();
}

class _NotificationsSectionState extends State<_NotificationsSection> {
  String _modeLabel(NotificationMode m, String loc) {
    if (m == NotificationMode.alert) {
      return loc == 'ar' ? 'تنبيه' : 'Alerte';
    }
    return loc == 'ar' ? 'صامت' : 'Discret';
  }

  String _soundLabel(NotificationSettings s) {
    if (s.sound == NotificationSound.custom &&
        (s.customSoundPath?.isNotEmpty ?? false)) {
      final path = s.customSoundPath!;
      final i = path.lastIndexOf('/');
      return i < 0 ? path : path.substring(i + 1);
    }
    return s.sound.displayName;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final isDark = widget.isDark;
    final loc = p.locale;
    final settings = p.notificationSettings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          text: loc == 'ar'
              ? 'الإشعارات'
              : loc == 'fr'
                  ? 'NOTIFICATIONS'
                  : 'NOTIFICATIONS',
          isDark: isDark,
        ),
        _Card(
          isDark: isDark,
          child: Column(children: [
            // Single entry into the agenda notification screen.
            // Volume and lock-screen rows used to live here too —
            // they were moved out of the main Settings so this surface
            // stays focused. Both options remain available inside
            // the agenda notification settings screen and the
            // per-event reminder settings.
            _SettRow(
              emoji: '🔔',
              bg: AppColors.greenPale,
              title: loc == 'ar'
                  ? 'الإشعارات'
                  : loc == 'es'
                      ? 'Notificaciones'
                      : 'Notifications',
              sub: settings.enabled
                  ? '${_modeLabel(settings.mode, loc)} · ${_soundLabel(settings)}'
                  : (loc == 'ar' ? 'معطّلة' : 'Désactivées'),
              trailing: _SmToggle(
                value: settings.enabled,
                onChanged: (v) => p.updateNotificationSettings(
                  (cur) => cur.copyWith(enabled: v),
                ),
              ),
              isDark: isDark,
              last: true,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const NotificationSettingsScreen(),
                ),
              ),
            ),
          ]),
        ),
      ],
    );
  }
}

// (Section "Données & Sync" — Export JSON / Import / ICS / Google
//  Calendar — was removed per spec. The "Delete all events" action
//  was preserved by moving it into the About section as a danger
//  row so the user can still wipe their personal events.)

// ═══════════════════════════════════════════════════════════
// 7. ABOUT
// ═══════════════════════════════════════════════════════════
class _AboutSection extends StatelessWidget {
  final AppProvider p;
  final bool isDark;
  const _AboutSection({required this.p, required this.isDark});

  static const String _appVersion = '1.0.0';
  // Public-facing endpoints. Replace these with the real ones once
  // the Play Store / website are live.
  static const String _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.hijricalendar.hijri_calendar';
  static const String _privacyUrl =
      'https://hijricalendar.app/privacy';
  static const String _contactEmail = 'support@hijricalendar.app';

  Future<void> _openUrl(BuildContext ctx, String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && ctx.mounted) {
      _snack(ctx, ctx.localeArOrFallback(
        ar: 'تعذّر فتح الرابط',
        fr: "Impossible d'ouvrir le lien",
        en: 'Could not open the link',
        es: 'No se pudo abrir el enlace',
      ));
    }
  }

  Future<void> _share(BuildContext ctx, String loc) async {
    final text = loc == 'ar'
        ? 'بدر | badr — تقويم هجري وأذكار وفضائل إسلامية\n$_playStoreUrl'
        : loc == 'fr'
            ? 'بدر | badr — Calendrier hégirien, adhkâr et vertus islamiques\n$_playStoreUrl'
            : loc == 'es'
                ? 'بدر | badr — Calendario hégira, adhkâr y virtudes islámicas\n$_playStoreUrl'
                : 'بدر | badr — Hijri calendar, adhkâr and Islamic virtues\n$_playStoreUrl';
    await Share.share(text);
  }

  Future<void> _contact(BuildContext ctx, String loc) async {
    final subject = loc == 'ar' ? 'دعم بدر | badr'
        : loc == 'es' ? 'Soporte بدر | badr'
        : loc == 'en' ? 'بدر | badr support'
        : 'Support بدر | badr';
    final uri = Uri(
      scheme: 'mailto',
      path: _contactEmail,
      queryParameters: {'subject': subject},
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && ctx.mounted) _snack(ctx, _contactEmail);
  }

  void _snack(BuildContext ctx, String msg) =>
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));

  void _showVersionDialog(BuildContext context, String loc) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          loc == 'ar' ? 'حول بدر | badr' : 'À propos de بدر | badr',
          style: appFont(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version $_appVersion',
                style: appFont(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              loc == 'ar'
                  ? 'بدر — تقويم هجري بمنطقتين (المغرب وأم القرى)، أذكار، فضائل إسلامية وأحداث شخصية مع إشعارات قابلة للضبط.'
                  : loc == 'fr'
                      ? 'بدر — calendrier hégirien (régions Maroc et Umm al-Qura), adhkâr, vertus islamiques et événements personnels avec notifications configurables.'
                      : loc == 'es'
                          ? 'بدر — calendario hégira (Marruecos y Umm al-Qura), adhkâr, virtudes islámicas y eventos personales con notificaciones configurables.'
                          : 'بدر — Hijri calendar (Morocco and Umm al-Qura regions), adhkâr, Islamic virtues and personal events with fully configurable notifications.',
              style: appFont(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(p.label('cancel')),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAll(BuildContext context, String loc) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          loc == 'ar' ? 'حذف جميع الأحداث؟'
              : loc == 'fr' ? 'Effacer tous les événements ?'
              : loc == 'es' ? '¿Eliminar todos los eventos?'
              : 'Delete all events?',
          style: appFont(fontWeight: FontWeight.bold),
        ),
        content: Text(
          loc == 'ar' ? 'لا يمكن التراجع عن هذا الإجراء.'
              : loc == 'fr' ? 'Cette action est irréversible.'
              : loc == 'es' ? 'Esta acción es irreversible.'
              : 'This action cannot be undone.',
          style: appFont(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(p.label('cancel'),
                style: const TextStyle(color: AppColors.text3)),
          ),
          TextButton(
            onPressed: () {
              for (final ev in List.from(p.userEvents)) {
                p.deleteEvent(ev.id);
              }
              Navigator.pop(context);
            },
            child: Text(p.label('delete'),
                style: const TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = p.locale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          text: loc == 'ar' ? 'حول التطبيق'
              : loc == 'fr' ? 'À PROPOS'
              : loc == 'es' ? 'ACERCA DE'
              : 'ABOUT',
          isDark: isDark),
        _Card(
          isDark: isDark,
          child: Column(children: [
            _SettRow(
              emoji: 'ℹ️', bg: AppColors.bluePale,
              title: loc == 'ar' ? 'الإصدار'
                  : loc == 'fr' ? 'Version'
                  : loc == 'es' ? 'Versión'
                  : 'Version',
              sub: 'بدر | badr',
              trailing: Text(_appVersion, style: appFont(
                  fontSize: 11, color: AppColors.text3)),
              isDark: isDark,
              onTap: () => _showVersionDialog(context, loc),
            ),
            _SettRow(
              emoji: '⭐', bg: AppColors.goldPale,
              title: loc == 'ar' ? 'تقييم التطبيق'
                  : loc == 'fr' ? "Évaluer l'app"
                  : loc == 'es' ? 'Calificar la app'
                  : 'Rate the app',
              sub: '',
              trailing: const SizedBox(),
              isDark: isDark,
              onTap: () => _openUrl(context, _playStoreUrl),
            ),
            _SettRow(
              emoji: '🔗', bg: AppColors.greenPale,
              title: loc == 'ar' ? 'مشاركة التطبيق'
                  : loc == 'fr' ? "Partager l'app"
                  : loc == 'es' ? 'Compartir la app'
                  : 'Share the app',
              sub: '',
              trailing: const SizedBox(),
              isDark: isDark,
              onTap: () => _share(context, loc),
            ),
            _SettRow(
              emoji: '🔒', bg: AppColors.bg,
              title: loc == 'ar' ? 'سياسة الخصوصية'
                  : loc == 'fr' ? 'Politique de confidentialité'
                  : loc == 'es' ? 'Política de privacidad'
                  : 'Privacy policy',
              sub: '',
              trailing: const SizedBox(),
              isDark: isDark,
              onTap: () => _openUrl(context, _privacyUrl),
            ),
            _SettRow(
              emoji: '📧', bg: AppColors.bg,
              title: loc == 'ar' ? 'اتصل بنا'
                  : loc == 'fr' ? 'Nous contacter'
                  : loc == 'es' ? 'Contáctanos'
                  : 'Contact us',
              sub: '',
              trailing: const SizedBox(),
              isDark: isDark,
              onTap: () => _contact(context, loc),
            ),
            _SettRow(
              emoji: '🗑',
              bg: const Color(0xFFFDEAEA),
              title: loc == 'ar' ? 'حذف جميع الأحداث'
                  : loc == 'fr' ? 'Effacer tous les événements'
                  : loc == 'es' ? 'Eliminar todos los eventos'
                  : 'Delete all events',
              sub: '',
              trailing: const Icon(Icons.chevron_left,
                  size: 14, color: AppColors.red),
              isDark: isDark,
              last: true,
              onTap: () => _confirmDeleteAll(context, loc),
            ),
          ]),
        ),
      ],
    );
  }
}

// ── BuildContext locale helper used by _AboutSection ───────────
extension _CtxLocaleX on BuildContext {
  String localeArOrFallback({
    required String ar,
    required String fr,
    required String en,
    required String es,
  }) {
    final p = Provider.of<AppProvider>(this, listen: false);
    switch (p.locale) {
      case 'ar': return ar;
      case 'fr': return fr;
      case 'en': return en;
      case 'es': return es;
      default:   return ar;
    }
  }
}

// ═══════════════════════════════════════════════════════════
// HIJRI ADJUSTMENT ROW (shown under the region picker)
// ═══════════════════════════════════════════════════════════
class _HijriAdjustRow extends StatelessWidget {
  final AppProvider p;
  final bool isDark;
  const _HijriAdjustRow({required this.p, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final loc = p.locale;
    final adj = p.hijriManualAdjust;
    final label = loc == 'ar'
        ? 'تعديل يدوي للتاريخ الهجري'
        : loc == 'fr'
            ? 'Ajustement manuel du Hijri'
            : loc == 'es'
                ? 'Ajuste manual del Hijri'
                : 'Hijri manual adjustment';
    final hint = loc == 'ar'
        ? 'بالأيام (−3 إلى +3)'
        : loc == 'fr'
            ? 'En jours (−3 à +3)'
            : loc == 'es'
                ? 'En días (−3 a +3)'
                : 'In days (−3 to +3)';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: appFont(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppColors.darkText : AppColors.text)),
              Text(hint,
                  style: appFont(
                      fontSize: 9, color: AppColors.text3)),
            ],
          ),
        ),
        GestureDetector(
          onTap: () => p.setHijriManualAdjust(adj - 1),
          child: const Icon(Icons.remove_rounded,
              size: 18, color: AppColors.text3),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: AppColors.greenPale,
                borderRadius: BorderRadius.circular(10)),
            child: Text(
              adj == 0 ? '0' : (adj > 0 ? '+$adj' : '$adj'),
              style: appFont(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green),
            ),
          ),
        ),
        GestureDetector(
          onTap: () => p.setHijriManualAdjust(adj + 1),
          child: const Icon(Icons.add_rounded,
              size: 18, color: AppColors.text3),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Default-view picker (wired to provider.setDefaultViewMode).
// This is the ONE place that persists the user's default view
// — tapping a chip at the top of the calendar screen is now
// transient (per the user's "default view stays until I change
// it from settings" requirement).
// ═══════════════════════════════════════════════════════════
class _ViewModePicker extends StatelessWidget {
  final AppProvider p;
  final bool isDark;
  const _ViewModePicker({required this.p, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final modes = <(CalendarViewMode, String)>[
      (CalendarViewMode.monthly, p.label('monthly')),
      (CalendarViewMode.weekly,  p.label('weekly')),
      (CalendarViewMode.agenda,  p.label('agenda')),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: modes.map((m) {
        // Show the selection state of the DEFAULT view, not
        // the current transient view — this picker is about
        // "what opens on next launch", not "what's visible
        // right now".
        final active = p.defaultViewMode == m.$1;
        return GestureDetector(
          onTap: () => p.setDefaultViewMode(m.$1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: active ? AppColors.green : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: active ? AppColors.green : AppColors.border),
            ),
            child: Text(
              m.$2,
              style: appFont(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : AppColors.text2,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Accent color row — 8-swatch picker driving provider.setAccent.
// Tapping a swatch swaps the active accent everywhere in the app
// because AppColors.green is now backed by AccentBus.
// ═══════════════════════════════════════════════════════════
class _AccentColorRow extends StatelessWidget {
  final AppProvider p;
  final bool isDark;
  const _AccentColorRow({required this.p, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final loc = p.locale;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: isDark ? AppColors.darkBorder : AppColors.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.bluePale,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Text('🎨', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  loc == 'ar'
                      ? 'لون التطبيق'
                      : loc == 'es'
                          ? 'Color de la app'
                          : loc == 'en'
                              ? 'App color'
                              : "Couleur d'accent",
                  style: appFont(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.darkText : AppColors.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: kAccentPalette.map((s) {
              final selected = p.accentIndex == s.index;
              return GestureDetector(
                onTap: () => p.setAccent(s.index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: selected ? 32 : 26,
                  height: selected ? 32 : 26,
                  decoration: BoxDecoration(
                    color: s.main,
                    shape: BoxShape.circle,
                    boxShadow: selected
                        ? [
                            BoxShadow(
                                color: s.main.withValues(alpha: 0.4),
                                blurRadius: 6),
                          ]
                        : null,
                  ),
                  child: selected
                      ? const Icon(Icons.check_rounded,
                          color: Colors.white, size: 16)
                      : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Font scale picker — S / M / L / XL → 0.85 / 1.0 / 1.15 / 1.30.
// Drives provider.setFontScale, which is applied via MediaQuery in
// main.dart so every Text in the app rescales uniformly.
// ═══════════════════════════════════════════════════════════
class _FontScaleRow extends StatelessWidget {
  final AppProvider p;
  final bool isDark;
  const _FontScaleRow({required this.p, required this.isDark});

  static const _options = <(String, double)>[
    ('S', 0.85),
    ('M', 1.00),
    ('L', 1.15),
    ('XL', 1.30),
  ];

  @override
  Widget build(BuildContext context) {
    final loc = p.locale;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: isDark ? AppColors.darkBorder : AppColors.border),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: AppColors.greenPale,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: Text('🔤', style: TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              loc == 'ar' ? 'حجم الخط'
                  : loc == 'es' ? 'Tamaño de fuente'
                  : loc == 'en' ? 'Font size'
                  : 'Taille de police',
              style: appFont(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.darkText : AppColors.text,
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: _options.map((o) {
              final active = (p.fontScale - o.$2).abs() < 0.01;
              return GestureDetector(
                onTap: () => p.setFontScale(o.$2),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(right: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: active ? AppColors.green : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: active ? AppColors.green : AppColors.border),
                  ),
                  child: Text(
                    o.$1,
                    style: appFont(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: active ? Colors.white : AppColors.text2,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Calendar density picker — Compact / Normal / Wide.
// Drives provider.setCalendarDensity which is read by the monthly
// grid to choose its mainAxisSpacing / crossAxisSpacing.
// ═══════════════════════════════════════════════════════════
class _CalendarDensityRow extends StatelessWidget {
  final AppProvider p;
  final bool isDark;
  final bool last;
  const _CalendarDensityRow({
    required this.p,
    required this.isDark,
    this.last = false,
  });

  String _label(CalendarDensity d, String loc) {
    switch (d) {
      case CalendarDensity.compact:
        return loc == 'ar' ? 'مضغوط'
            : loc == 'es' ? 'Compacto'
            : loc == 'en' ? 'Compact'
            : 'Compact';
      case CalendarDensity.normal:
        return loc == 'ar' ? 'عادي'
            : loc == 'es' ? 'Normal'
            : loc == 'en' ? 'Normal'
            : 'Normal';
      case CalendarDensity.wide:
        return loc == 'ar' ? 'موسّع'
            : loc == 'es' ? 'Amplio'
            : loc == 'en' ? 'Wide'
            : 'Étendu';
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = p.locale;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: last
          ? null
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(
                    color: isDark ? AppColors.darkBorder : AppColors.border),
              ),
            ),
      child: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: Text('📐', style: TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              loc == 'ar' ? 'كثافة التقويم'
                  : loc == 'es' ? 'Densidad del calendario'
                  : loc == 'en' ? 'Calendar density'
                  : 'Densité du calendrier',
              style: appFont(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.darkText : AppColors.text,
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: CalendarDensity.values.map((d) {
              final active = p.calendarDensity == d;
              return GestureDetector(
                onTap: () => p.setCalendarDensity(d),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(right: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: active ? AppColors.green : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: active ? AppColors.green : AppColors.border),
                  ),
                  child: Text(
                    _label(d, loc),
                    style: appFont(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: active ? Colors.white : AppColors.text2,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Font-family picker — 3 fonts in Arabic mode, 2 in others.
// Drives provider.setFontFamily. Theme.of(context).textTheme
// follows automatically because main.dart pushes the chosen
// family into AppTheme.setActiveFontFamily on every rebuild.
// ═══════════════════════════════════════════════════════════
class _FontFamilyRow extends StatelessWidget {
  final AppProvider p;
  final bool isDark;
  const _FontFamilyRow({required this.p, required this.isDark});

  String _label(String key, String loc) {
    // Display labels — leave font names as-is for non-Arabic, give
    // a transliteration for Arabic so users see the option name in
    // their reading direction.
    switch (key) {
      case 'amiri':        return loc == 'ar' ? 'أميري'   : 'Amiri';
      case 'cairo':        return loc == 'ar' ? 'كايرو'   : 'Cairo';
      case 'tajawal':      return loc == 'ar' ? 'تجوّل'    : 'Tajawal';
      case 'roboto':       return 'Roboto';
      case 'merriweather': return 'Merriweather';
      default:             return key;
    }
  }

  // Each pill in the picker must render in its OWN font so the user
  // can preview the choice. These calls are the only place in the
  // app that intentionally bypasses [appFont] / [AppTheme] — every
  // other style point routes through [appFont] and therefore follows
  // the user's selection.
  TextStyle _previewStyle(String key) {
    switch (key) {
      case 'cairo':        return GoogleFonts.cairo(fontWeight: FontWeight.w800);
      case 'tajawal':      return GoogleFonts.tajawal(fontWeight: FontWeight.w800);
      case 'merriweather': return GoogleFonts.merriweather(fontWeight: FontWeight.w800);
      case 'roboto':       return GoogleFonts.roboto(fontWeight: FontWeight.w800);
      case 'amiri':
      default:             return GoogleFonts.amiri(fontWeight: FontWeight.bold);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = p.locale;
    final fonts = p.availableFonts;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: isDark ? AppColors.darkBorder : AppColors.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: AppColors.bluePale,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                    child: Text('🅰️', style: TextStyle(fontSize: 16))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  loc == 'ar' ? 'نوع الخط'
                      : loc == 'es' ? 'Tipo de fuente'
                      : loc == 'en' ? 'Font type'
                      : 'Type de police',
                  style: appFont(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.darkText : AppColors.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: fonts.map((key) {
              final active = p.fontFamily == key;
              return GestureDetector(
                onTap: () => p.setFontFamily(key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: active ? AppColors.green : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: active ? AppColors.green : AppColors.border),
                  ),
                  child: Text(
                    _label(key, loc),
                    style: _previewStyle(key).copyWith(
                      fontSize: 13,
                      color: active ? Colors.white : AppColors.text2,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
