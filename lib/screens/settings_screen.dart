import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/notification_settings.dart';
import '../providers/app_provider.dart';
import '../utils/hijri_utils.dart';
import '../utils/text_format.dart';
import '../theme.dart';
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
          ? GoogleFonts.amiri(fontSize: 26, fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkText : AppColors.navy)
          : GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.w700,
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
                Text(title, style: GoogleFonts.cairo(fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.darkText : AppColors.text)),
                if (sub.isNotEmpty) Text(sub, style: GoogleFonts.cairo(
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
    final today = HijriDate.now();
    final greg = DateTime.now();
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
                  Text(appTitle, style: GoogleFonts.amiri(
                      fontSize: 18, fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.darkText : AppColors.navy)),
                  Text(hijriLine,
                    style: GoogleFonts.cairo(fontSize: 11, color: AppColors.green,
                        fontWeight: FontWeight.w700)),
                  Text(gregStr, style: GoogleFonts.cairo(fontSize: 10, color: AppColors.text3)),
                ],
              )),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.greenPale, borderRadius: BorderRadius.circular(12)),
                child: Column(children: [
                  Text('${today.hYear}', style: GoogleFonts.amiri(
                      fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.green)),
                  Text(p.locale == 'ar' ? 'هـ' : 'AH',
                    style: GoogleFonts.cairo(fontSize: 8, color: AppColors.green)),
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
    // Two regions only: Umm al-Qura (the calendrical baseline used
    // by Saudi Arabia) and Morocco (Ministry of Habous and Islamic
    // Affairs — typically lags UAQ by one day via local sighting).
    final regions = [
      (
        'global',
        '🕋',
        loc == 'ar'
            ? 'أم القرى'
            : loc == 'es'
                ? 'Umm al-Qura'
                : loc == 'en'
                    ? 'Umm al-Qura'
                    : 'Oumm al-Qoura',
      ),
      (
        'ma',
        '🇲🇦',
        loc == 'ar'
            ? 'المغرب'
            : loc == 'es'
                ? 'Marruecos'
                : loc == 'en'
                    ? 'Morocco'
                    : 'Maroc',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          text: loc == 'ar' ? 'اللغة والمنطقة'
              : loc == 'fr' ? 'LANGUE & RÉGION' : 'LANGUAGE & REGION',
          isDark: isDark),
        _Card(
          isDark: isDark,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(loc == 'ar' ? 'اللغة' : 'Langue',
                style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.w700,
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
                        Text(l.$3, style: GoogleFonts.cairo(fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: active ? Colors.white
                                : (isDark ? AppColors.darkText3 : AppColors.text3))),
                      ]),
                    ),
                  ));
                }).toList(),
              ),
              const SizedBox(height: 14),
              Text(loc == 'ar' ? 'المنطقة'
                  : loc == 'fr' ? 'Région'
                  : loc == 'es' ? 'Región'
                  : 'Region',
                style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.w700,
                    color: AppColors.text3, letterSpacing: 2)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6, runSpacing: 6,
                children: regions.map((r) {
                  final active = p.region == r.$1;
                  return GestureDetector(
                    onTap: () => p.setRegion(r.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: active
                            ? AppColors.green
                            : (isDark ? AppColors.darkBg : AppColors.bg),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: active ? AppColors.green : AppColors.border)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(r.$2, style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 5),
                        Text(r.$3, style: GoogleFonts.cairo(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: active
                                ? Colors.white
                                : (isDark ? AppColors.darkText2 : AppColors.text2))),
                      ]),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              _HijriAdjustRow(p: p, isDark: isDark),
            ],
          ),
        ),
      ],
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
                  style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w700,
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

class _ChipRow extends StatelessWidget {
  final List<String> options;
  final String selected;
  final bool isDark;
  const _ChipRow({required this.options, required this.selected, required this.isDark});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: options.map((o) {
      final active = o == selected;
      return Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active ? AppColors.navy : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? AppColors.navy : AppColors.border)),
        child: Text(o, style: GoogleFonts.cairo(fontSize: 9, fontWeight: FontWeight.w700,
            color: active ? Colors.white : AppColors.text3)),
      );
    }).toList(),
  );
}

// ═══════════════════════════════════════════════════════════
// 4. CALENDAR SETTINGS
// ═══════════════════════════════════════════════════════════
class _CalendarSection extends StatefulWidget {
  final AppProvider p;
  final bool isDark;
  const _CalendarSection({required this.p, required this.isDark});
  @override
  State<_CalendarSection> createState() => _CalendarSectionState();
}

class _CalendarSectionState extends State<_CalendarSection> {
  bool showAyyam = true, showRamadan = true, showGreg = true,
       showDualHeader = true, showMonthNames = false, showFriday = true;

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final isDark = widget.isDark;
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
              // Default view — actually drives provider.viewMode and
              // is persisted in SharedPreferences.
              Text(loc == 'ar' ? 'العرض الافتراضي'
                  : loc == 'fr' ? 'Vue par défaut'
                  : loc == 'es' ? 'Vista por defecto'
                  : 'Default view',
                style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.w700,
                    color: AppColors.text3)),
              const SizedBox(height: 8),
              _ViewModePicker(p: p, isDark: isDark),
              const SizedBox(height: 14),
              Text(loc == 'ar' ? 'إظهار' : loc == 'fr' ? 'Afficher' : 'Show',
                style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.w700,
                    color: AppColors.text3)),
              const SizedBox(height: 8),
              ...[
                (loc == 'ar' ? 'الأيام البيض' : 'Ayyam Al-Bid', showAyyam,
                 (bool v) => setState(() => showAyyam = v)),
                (loc == 'ar' ? 'أيام رمضان' : 'Jours Ramadan', showRamadan,
                 (bool v) => setState(() => showRamadan = v)),
                (loc == 'ar' ? 'التاريخ الميلادي' : 'Date grégorienne', showGreg,
                 (bool v) => setState(() => showGreg = v)),
                (loc == 'ar' ? 'العنوان مزدوج' : 'En-tête double', showDualHeader,
                 (bool v) => setState(() => showDualHeader = v)),
                (loc == 'ar' ? 'تمييز الجمعة' : 'Marquer vendredi', showFriday,
                 (bool v) => setState(() => showFriday = v)),
              ].map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Expanded(child: Text(item.$1, style: GoogleFonts.cairo(
                      fontSize: 12, color: isDark ? AppColors.darkText : AppColors.text))),
                  _SmToggle(value: item.$2, onChanged: item.$3),
                ]),
              )),
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
            _SettRow(
              emoji: '🔔',
              bg: AppColors.greenPale,
              title: loc == 'ar'
                  ? 'إشعارات الأجندة'
                  : 'Notifications d\'Agenda',
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
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const NotificationSettingsScreen(),
                ),
              ),
            ),
            _SettRow(
              emoji: '🎚',
              bg: AppColors.bluePale,
              title: loc == 'ar' ? 'مستوى الصوت' : 'Volume',
              sub: '${(settings.volume * 100).round()} %',
              trailing: const Icon(
                Icons.tune_rounded,
                size: 16,
                color: AppColors.text3,
              ),
              isDark: isDark,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const NotificationSettingsScreen(),
                ),
              ),
            ),
            _SettRow(
              emoji: '🔒',
              bg: AppColors.goldPale,
              title: loc == 'ar'
                  ? 'إعدادات شاشة القفل'
                  : 'Écran de verrouillage',
              sub: settings.lockScreenVisibility ==
                      LockScreenVisibility.doNotShow
                  ? (loc == 'ar'
                      ? 'لا تُظهر الإشعارات'
                      : 'Ne pas afficher les notifications')
                  : (loc == 'ar' ? 'إخفاء المحتوى' : 'Masquer le contenu'),
              trailing: const SizedBox.shrink(),
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
          style: GoogleFonts.amiri(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version $_appVersion',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              loc == 'ar'
                  ? 'بدر — تقويم هجري بمنطقتين (المغرب وأم القرى)، أذكار، فضائل إسلامية وأحداث شخصية مع إشعارات قابلة للضبط.'
                  : loc == 'fr'
                      ? 'بدر — calendrier hégirien (régions Maroc et Umm al-Qura), adhkâr, vertus islamiques et événements personnels avec notifications configurables.'
                      : loc == 'es'
                          ? 'بدر — calendario hégira (Marruecos y Umm al-Qura), adhkâr, virtudes islámicas y eventos personales con notificaciones configurables.'
                          : 'بدر — Hijri calendar (Morocco and Umm al-Qura regions), adhkâr, Islamic virtues and personal events with fully configurable notifications.',
              style: GoogleFonts.cairo(fontSize: 12),
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
          style: GoogleFonts.amiri(fontWeight: FontWeight.bold),
        ),
        content: Text(
          loc == 'ar' ? 'لا يمكن التراجع عن هذا الإجراء.'
              : loc == 'fr' ? 'Cette action est irréversible.'
              : loc == 'es' ? 'Esta acción es irreversible.'
              : 'This action cannot be undone.',
          style: GoogleFonts.cairo(),
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
              trailing: Text(_appVersion, style: GoogleFonts.cairo(
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
        ? 'بالأيام (−2 إلى +2)'
        : loc == 'fr'
            ? 'En jours (−2 à +2)'
            : loc == 'es'
                ? 'En días (−2 a +2)'
                : 'In days (−2 to +2)';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: GoogleFonts.cairo(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppColors.darkText : AppColors.text)),
              Text(hint,
                  style: GoogleFonts.cairo(
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
              style: GoogleFonts.cairo(
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
// Default-view picker (wired to provider.setViewMode)
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
        final active = p.viewMode == m.$1;
        return GestureDetector(
          onTap: () => p.setViewMode(m.$1),
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
              style: GoogleFonts.cairo(
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
                  style: GoogleFonts.cairo(
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
              style: GoogleFonts.cairo(
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
                    style: GoogleFonts.cairo(
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
              style: GoogleFonts.cairo(
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
                    style: GoogleFonts.cairo(
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
                  style: GoogleFonts.cairo(
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
