import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/hijri_countries.dart';
import '../providers/app_provider.dart';
import '../theme.dart';

/// Small "where this Hijri date came from" badge.
///
/// Designed to slot under the Hijri month header on the
/// calendar screen and under the today's-date line on the
/// Settings profile card. One short line:
///
///     🇲🇦 وزارة الأوقاف · قبل ساعتين  ›
///
/// Two visual cues encode the source quality:
///
///   * A small dot (green = data came from the live AlAdhan
///     cache, gold = arithmetic fallback). Gives an instant,
///     glanceable hint without making the user open the sheet.
///   * Tapping the whole badge opens a bottom sheet with the
///     full authority name, country, "last update" timestamp,
///     a "refresh now" button, and a "change source" shortcut
///     to the Settings section the user already knows.
///
/// Why a bottom sheet and not a tooltip?
///   The badge needs to be readable to a beginner who isn't
///   familiar with Islamic calendar mechanics. A sheet lets us
///   spell out "Source: Moroccan Ministry of Awqaf" in full
///   without crowding the calendar header — and the same sheet
///   can host the "refresh now" action so the user doesn't
///   have to navigate to Settings for a manual sync.
class HijriSourceBadge extends StatelessWidget {
  /// Heavier styling for the calendar header (slightly larger
  /// text, more padding). The profile card uses the compact
  /// variant.
  final bool compact;

  /// Optional override for the bg surface so the badge can sit
  /// on dark cards or the scaffold equally cleanly.
  final bool? darkOverride;

  const HijriSourceBadge({
    super.key,
    this.compact = false,
    this.darkOverride,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    final isDark = darkOverride ??
        (Theme.of(context).brightness == Brightness.dark);
    final live = p.hijriSourceIsLive;
    final dotColor =
        live ? AppColors.green : const Color(0xFFC8943A);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(context, p),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10,
            vertical: compact ? 3 : 4,
          ),
          decoration: BoxDecoration(
            color: (isDark ? AppColors.darkBg : AppColors.bg)
                .withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: dotColor.withValues(alpha: 0.35),
              width: 0.7,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotColor,
                  boxShadow: [
                    BoxShadow(
                      color: dotColor.withValues(alpha: 0.55),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  p.hijriSourceLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: appFont(
                    fontSize: compact ? 10 : 10.5,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.darkText2
                        : AppColors.text2,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.info_outline_rounded,
                size: compact ? 11 : 12,
                color: isDark ? AppColors.darkText3 : AppColors.text3,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, AppProvider p) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider.value(
        value: p,
        // Need a fresh `BuildContext` inside the sheet so the
        // provider lookups + Theme inheritance work as if the
        // sheet were a child of the screen that opened it.
        child: const _SourceInfoSheet(),
      ),
    );
  }
}

class _SourceInfoSheet extends StatefulWidget {
  const _SourceInfoSheet();

  @override
  State<_SourceInfoSheet> createState() => _SourceInfoSheetState();
}

class _SourceInfoSheetState extends State<_SourceInfoSheet> {
  bool _refreshing = false;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final loc = p.locale;
    final country = hijriCountryByCode(p.country);
    final ts = p.hijriLastSync;
    final live = p.hijriSourceIsLive;

    final lastSyncText = ts == null
        ? p.label('hijri_source_never_synced')
        : '${p.label('hijri_source_last_sync')}: ${_formatAgo(p, ts)}';

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.white,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(22),
        ),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Grab handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 14),
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.text3.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Title + close
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    p.label('hijri_source'),
                    style: appFont(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: isDark ? AppColors.darkText : AppColors.text,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: isDark
                        ? AppColors.darkText3
                        : AppColors.text3,
                  ),
                ),
              ],
            ),
          ),
          // Country + authority hero block.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkBg : AppColors.bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.green.withValues(alpha: 0.30),
                  width: 1.2,
                ),
              ),
              child: Row(
                children: [
                  Text(country.flag, style: const TextStyle(fontSize: 36)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          country.localizedName(loc),
                          style: appFont(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? AppColors.darkText
                                : AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          country.localizedAuthority(loc),
                          maxLines: 3,
                          style: appFont(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: AppColors.text3,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Status line: live cache vs arithmetic.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: live
                        ? AppColors.green
                        : const Color(0xFFC8943A),
                    boxShadow: [
                      BoxShadow(
                        color: (live
                                ? AppColors.green
                                : const Color(0xFFC8943A))
                            .withValues(alpha: 0.55),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    lastSyncText,
                    style: appFont(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? AppColors.darkText2
                          : AppColors.text2,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Single primary action: refresh. Picking a different
          // country lives in the Settings → "Hijri source"
          // section so we don't duplicate that picker here.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: _SheetButton(
              icon: Icons.refresh_rounded,
              label: _refreshing
                  ? p.label('hijri_source_refreshing')
                  : p.label('hijri_source_refresh'),
              busy: _refreshing,
              primary: true,
              isDark: isDark,
              onTap: _refreshing ? null : () => _onRefresh(p),
            ),
          ),
          // Soft hint pointing power-users to the full picker.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Text(
              loc == 'ar'
                  ? 'لتغيير المصدر، افتح الإعدادات → مصدر التقويم الهجري'
                  : loc == 'fr'
                      ? 'Pour changer la source, allez dans Paramètres → Source du calendrier Hijri'
                      : loc == 'es'
                          ? 'Para cambiar la fuente, abre Ajustes → Fuente del calendario Hijri'
                          : 'To change the source, open Settings → Hijri calendar source',
              textAlign: TextAlign.center,
              style: appFont(
                fontSize: 10.5,
                fontWeight: FontWeight.w400,
                color: isDark ? AppColors.darkText3 : AppColors.text3,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
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
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
          p.label(ok ? 'hijri_source_sync_ok' : 'hijri_source_sync_fail'),
          style: appFont(fontSize: 12.5, color: Colors.white),
        ),
        backgroundColor:
            ok ? AppColors.green : const Color(0xFFD94F4F),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 2200),
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ));
  }
}

/// Humanises a timestamp into a localized "Nh ago" string.
/// Mirror of the helper in `settings_screen.dart` — duplicated
/// (rather than extracted to a shared utility) because the
/// formatter is intimately tied to the four label keys
/// `hijri_source_just_now / _minutes_ago / _hours_ago /
/// _days_ago` and pulling it out to its own file would just
/// add an indirection for a 12-line function.
String _formatAgo(AppProvider p, DateTime ts) {
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

class _SheetButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool busy;
  final bool primary;
  final bool isDark;
  final VoidCallback? onTap;
  const _SheetButton({
    required this.icon,
    required this.label,
    required this.busy,
    required this.primary,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final bg = primary
        ? AppColors.green
        : (isDark ? AppColors.darkBg : AppColors.bg);
    final fg = primary
        ? Colors.white
        : (isDark ? AppColors.darkText : AppColors.text);
    final borderColor = primary
        ? AppColors.green
        : (isDark ? AppColors.darkBorder : AppColors.border);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 120),
      opacity: enabled ? 1.0 : 0.55,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      valueColor: AlwaysStoppedAnimation<Color>(fg),
                    ),
                  )
                else
                  Icon(icon, size: 16, color: fg),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appFont(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Phase-7 Improvement 5 — minimal source indicator.
///
/// Replacement for the verbose [HijriSourceBadge] in places
/// where screen real estate is precious (calendar header,
/// profile card). One small icon, one tap → same info sheet.
///
/// Three visual states:
///   * ✓ (cloud-done, green) — live cache, country-official
///     Hijri value is on screen.
///   * 📐 (calculate, gold) — arithmetic fallback, either
///     offline + cache cold or the safety toggle is off.
///
/// Why a separate widget vs. extending [HijriSourceBadge]?
///   The badge has its own pill chrome (rounded border, dot,
///   flag emoji, authority text, info chevron). Adding an
///   "icon-only" mode to it would gut most of those properties
///   and make the code harder to read for both call sites. A
///   sibling widget with a tight, single-purpose API is
///   cleaner — and the existing badge stays available for any
///   future surface where the full caption matters.
class HijriSourceDot extends StatelessWidget {
  /// Icon size in logical pixels. Defaults to 16 so it sits
  /// comfortably next to a 14-16 sp body text.
  final double size;

  /// Optional dark-mode override. When null, we read it from
  /// the ambient theme.
  final bool? darkOverride;

  const HijriSourceDot({
    super.key,
    this.size = 16,
    this.darkOverride,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    final live = p.hijriSourceIsLive;

    // Two states cover every realistic situation. A third
    // ("refreshing") would need provider-level tracking of
    // in-flight fetches; not worth the wiring for a momentary
    // ~250 ms transition the user will rarely see.
    final IconData icon = live
        ? Icons.cloud_done_rounded
        : Icons.calculate_rounded;
    final Color color = live
        ? AppColors.green
        : const Color(0xFFC8943A);

    return Material(
      color: Colors.transparent,
      child: InkResponse(
        onTap: () => _openSheet(context, p),
        radius: size * 1.4,
        // Larger hit area than the visual so a thumb tap
        // doesn't miss; matches Material's recommended ≥48 dp
        // target even though the icon itself is only 16 dp.
        containedInkWell: false,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: size, color: color),
        ),
      ),
    );
  }

  /// Opens the same info sheet the verbose badge uses, so
  /// nothing the user can do via the old badge is lost. The
  /// sheet hosts the refresh button, the last-sync timestamp,
  /// and the "open Settings to change source" hint.
  Future<void> _openSheet(BuildContext context, AppProvider p) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useRootNavigator: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: p,
        child: const _SourceInfoSheet(),
      ),
    );
  }
}
