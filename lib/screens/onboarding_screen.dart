import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/app_provider.dart';
import '../theme.dart';
import 'home_screen.dart';

/// First-launch onboarding experience.
///
/// Three pages:
///   1. Welcome — crescent / Hijri / soft golden stars, "Get Started".
///   2. Language + region — glassmorphism cards, AR + MA selected by
///      default.
///   3. Islamic virtues — toggleable list (Ramadan, Ayyam Al-Bid,
///      Day of Arafah, Friday, Morning & Evening Adhkar).
///
/// All three pages share the same royal-green / gold ambient
/// background as the splash screen so the transition stays calm.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _ctrl = PageController();
  int _page = 0;

  // Page-2 picks. Defaults per spec: AR + Morocco.
  String _selectedLang = 'ar';
  String _selectedRegion = 'ma';

  // Page-3 virtues. Mirrors the IslamicEventsData ids that the
  // provider's `toggleIslamicEvent` already understands. The set of
  // ids below is intentionally a small, sensible default — the full
  // catalog stays available in Settings.
  final Map<String, bool> _virtues = {
    'ramadan_start': true,
    'ayyam_albid': true,
    'arafat': true,
    'friday': true,
    'adhkar_sabah': true,
  };

  void _next(AppProvider p) {
    if (_page < 2) {
      _ctrl.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _finish(p);
    }
  }

  Future<void> _finish(AppProvider p) async {
    p.setLocale(_selectedLang);
    await p.setRegion(_selectedRegion);
    for (final entry in _virtues.entries) {
      p.toggleIslamicEvent(entry.key, entry.value);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _ctaLabel(int page) {
    if (page < 2) {
      switch (_selectedLang) {
        case 'ar': return 'متابعة';
        case 'fr': return 'Suivant';
        case 'es': return 'Siguiente';
        default:   return 'Next';
      }
    }
    // Page 3 — final CTA
    switch (_selectedLang) {
      case 'ar': return 'لِنَبدأ';
      case 'fr': return 'Commencer';
      case 'es': return 'Comenzar';
      default:   return 'Get Started';
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Same atmospheric backdrop as the splash so the cross-fade
          // is seamless.
          const _AmbientBackdrop(),
          SafeArea(
            child: Column(
              children: [
                // Progress dots
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(3, (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: _page == i ? 28 : 8,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: _page == i
                            ? const Color(0xFFE9C46A)
                            : Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    )),
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _ctrl,
                    onPageChanged: (i) => setState(() => _page = i),
                    children: [
                      _WelcomePage(locale: _selectedLang),
                      _LanguageRegionPage(
                        selectedLang: _selectedLang,
                        selectedRegion: _selectedRegion,
                        onLangSelected: (l) =>
                            setState(() => _selectedLang = l),
                        onRegionSelected: (r) =>
                            setState(() => _selectedRegion = r),
                      ),
                      _VirtuesPage(
                        locale: _selectedLang,
                        virtues: _virtues,
                        onChanged: (id, v) =>
                            setState(() => _virtues[id] = v),
                      ),
                    ],
                  ),
                ),
                // CTA
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                  child: GestureDetector(
                    onTap: () => _next(p),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFE9C46A),
                            Color(0xFFD4A93A),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFE9C46A)
                                .withValues(alpha: 0.32),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          _ctaLabel(_page),
                          style: appFont(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0A2519),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared atmospheric backdrop ────────────────────────────────────

class _AmbientBackdrop extends StatelessWidget {
  const _AmbientBackdrop();
  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF0A2519),
                Color(0xFF0E4A2D),
                Color(0xFF1A6B45),
              ],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
        ),
        // Soft golden centre-glow
        IgnorePointer(
          child: Center(
            child: Container(
              width: 480,
              height: 480,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFE9C46A).withValues(alpha: 0.16),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 1.0],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Page 1 — Welcome ────────────────────────────────────────────────

class _WelcomePage extends StatelessWidget {
  final String locale;
  const _WelcomePage({required this.locale});

  @override
  Widget build(BuildContext context) {
    final title = locale == 'ar'
        ? 'مرحباً بك في بدر'
        : locale == 'fr'
            ? 'Bienvenue dans Badr'
            : locale == 'es'
                ? 'Bienvenido a Badr'
                : 'Welcome to Badr';
    final body = locale == 'ar'
        ? 'رفيقك في تذكّر مواسم الخير وأعمال العبادة'
        : locale == 'fr'
            ? 'Votre compagnon pour les saisons du bien et les actes d\'adoration'
            : locale == 'es'
                ? 'Tu compañero en las estaciones del bien y los actos de adoración'
                : 'Your companion in the seasons of khayr and acts of worship';

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Hero — crescent + Hijri + golden stars on a glass tile.
          SizedBox(
            width: 240,
            height: 240,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Soft halo
                Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFFE9C46A).withValues(alpha: 0.22),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                // Stars
                CustomPaint(
                  size: const Size(240, 240),
                  painter: _StarsPainter(),
                ),
                // Crescent
                CustomPaint(
                  size: const Size(150, 150),
                  painter: _CrescentPainter(
                    fill: const Color(0xFFF6E5B5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 36),
          Text(
            title,
            textAlign: TextAlign.center,
            style: appFont(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: const Color(0xFFF6E5B5),
              shadows: [
                Shadow(
                  color: const Color(0xFFE9C46A).withValues(alpha: 0.4),
                  blurRadius: 14,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            body,
            textAlign: TextAlign.center,
            style: appFont(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.78),
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _StarsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFF6E5B5).withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    final positions = [
      const Offset(0.18, 0.20),
      const Offset(0.82, 0.30),
      const Offset(0.10, 0.75),
      const Offset(0.78, 0.78),
      const Offset(0.50, 0.14),
      const Offset(0.92, 0.55),
    ];
    final radii = [3.0, 2.2, 2.6, 1.8, 2.0, 2.4];
    for (var i = 0; i < positions.length; i++) {
      final p = Offset(
          positions[i].dx * size.width, positions[i].dy * size.height);
      canvas.drawCircle(p, radii[i], paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CrescentPainter extends CustomPainter {
  final Color fill;
  _CrescentPainter({required this.fill});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = fill;
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.5),
      size.width * 0.42,
      paint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.66, size.height * 0.42),
      size.width * 0.36,
      Paint()..blendMode = BlendMode.dstOut,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Page 2 — Language + Region (glassmorphism) ─────────────────────

class _LanguageRegionPage extends StatelessWidget {
  final String selectedLang;
  final String selectedRegion;
  final ValueChanged<String> onLangSelected;
  final ValueChanged<String> onRegionSelected;
  const _LanguageRegionPage({
    required this.selectedLang,
    required this.selectedRegion,
    required this.onLangSelected,
    required this.onRegionSelected,
  });

  @override
  Widget build(BuildContext context) {
    final loc = selectedLang;
    final langTitle = loc == 'ar'
        ? 'اختر لغتك'
        : loc == 'fr'
            ? 'Choisissez votre langue'
            : loc == 'es'
                ? 'Elige tu idioma'
                : 'Choose your language';
    final regionTitle = loc == 'ar'
        ? 'اختر منطقتك'
        : loc == 'fr'
            ? 'Choisissez votre région'
            : loc == 'es'
                ? 'Elige tu región'
                : 'Choose your region';

    final langs = const [
      ('ar', '🇲🇦', 'العربية'),
      ('fr', '🇫🇷', 'Français'),
      ('en', '🇬🇧', 'English'),
      ('es', '🇪🇸', 'Español'),
    ];
    final regions = [
      ('ma', '🇲🇦', loc == 'ar' ? 'المغرب' : loc == 'es' ? 'Marruecos' : loc == 'en' ? 'Morocco' : 'Maroc'),
      ('global', '🌍', loc == 'ar' ? 'أم القرى' : loc == 'es' ? 'Umm al-Qura' : loc == 'en' ? 'Umm al-Qura' : 'Umm al-Qura'),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeading(text: langTitle),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2.1,
            children: langs.map((l) {
              final active = selectedLang == l.$1;
              return _GlassCard(
                onTap: () => onLangSelected(l.$1),
                active: active,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(l.$2, style: const TextStyle(fontSize: 26)),
                    const SizedBox(height: 4),
                    Text(
                      l.$3,
                      style: appFont(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: active
                            ? const Color(0xFF0A2519)
                            : Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 26),
          _SectionHeading(text: regionTitle),
          const SizedBox(height: 14),
          Column(
            children: regions.map((r) {
              final active = selectedRegion == r.$1;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _GlassCard(
                  onTap: () => onRegionSelected(r.$1),
                  active: active,
                  fullWidth: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    child: Row(
                      children: [
                        Text(r.$2, style: const TextStyle(fontSize: 24)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            r.$3,
                            style: appFont(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: active
                                  ? const Color(0xFF0A2519)
                                  : Colors.white.withValues(alpha: 0.92),
                            ),
                          ),
                        ),
                        Icon(
                          active
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: active
                              ? const Color(0xFF0A2519)
                              : Colors.white.withValues(alpha: 0.55),
                          size: 22,
                        ),
                      ],
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

class _SectionHeading extends StatelessWidget {
  final String text;
  const _SectionHeading({required this.text});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        style: appFont(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: const Color(0xFFF6E5B5),
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool active;
  final bool fullWidth;
  const _GlassCard({
    required this.child,
    required this.onTap,
    required this.active,
    this.fullWidth = false,
  });
  @override
  Widget build(BuildContext context) {
    final activeBg = const Color(0xFFE9C46A);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        width: fullWidth ? double.infinity : null,
        decoration: BoxDecoration(
          color: active
              ? activeBg
              : Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active
                ? activeBg
                : Colors.white.withValues(alpha: 0.18),
            width: 1.2,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: activeBg.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: child,
      ),
    );
  }
}

// ─── Page 3 — Islamic virtues ───────────────────────────────────────

class _VirtuesPage extends StatelessWidget {
  final String locale;
  final Map<String, bool> virtues;
  final void Function(String id, bool value) onChanged;
  const _VirtuesPage({
    required this.locale,
    required this.virtues,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final title = locale == 'ar'
        ? 'فعّل فضائلك الإسلامية'
        : locale == 'fr'
            ? 'Activez vos vertus islamiques'
            : locale == 'es'
                ? 'Activa tus virtudes islámicas'
                : 'Enable your Islamic virtues';
    final hint = locale == 'ar'
        ? 'يمكنك تغيير هذه التذكيرات لاحقاً من الإعدادات.'
        : locale == 'fr'
            ? 'Vous pourrez changer ces rappels plus tard dans les réglages.'
            : locale == 'es'
                ? 'Podrás cambiar estos recordatorios más tarde en los ajustes.'
                : 'You can change these reminders later from Settings.';

    final items = <(String, String, String)>[
      ('ramadan_start', '🌙', _label(locale, ar: 'رمضان', fr: 'Ramadan',
          es: 'Ramadán', en: 'Ramadan')),
      ('ayyam_albid', '🌕', _label(locale, ar: 'الأيام البيض',
          fr: 'Ayyâm al-Bîd', es: 'Ayyam al-Bid', en: 'Ayyam Al-Bid')),
      ('arafat', '🏔', _label(locale, ar: 'يوم عرفة',
          fr: 'Jour de Arafah', es: 'Día de Arafa', en: 'Day of Arafah')),
      ('friday', '🕌', _label(locale, ar: 'يوم الجمعة',
          fr: 'Vendredi', es: 'Viernes', en: 'Friday')),
      ('adhkar_sabah', '📿', _label(locale, ar: 'أذكار الصباح والمساء',
          fr: 'Adhkâr du matin et du soir',
          es: 'Adhkâr de la mañana y la tarde',
          en: 'Morning and Evening Adhkar')),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeading(text: title),
          const SizedBox(height: 8),
          Text(
            hint,
            style: appFont(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.65),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          ...items.map((it) {
            final id = it.$1;
            final emoji = it.$2;
            final label = it.$3;
            final value = virtues[id] ?? false;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _VirtueRow(
                emoji: emoji,
                label: label,
                value: value,
                onChanged: (v) => onChanged(id, v),
              ),
            );
          }),
        ],
      ),
    );
  }

  String _label(String loc, {
    required String ar,
    required String fr,
    required String es,
    required String en,
  }) {
    switch (loc) {
      case 'ar': return ar;
      case 'fr': return fr;
      case 'es': return es;
      default:   return en;
    }
  }
}

class _VirtueRow extends StatelessWidget {
  final String emoji;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _VirtueRow({
    required this.emoji,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: value
              ? const Color(0xFFE9C46A).withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: value
                ? const Color(0xFFE9C46A).withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.15),
            width: 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: appFont(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ),
            ),
            _GoldToggle(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _GoldToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _GoldToggle({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 46,
        height: 26,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value
              ? const Color(0xFFE9C46A)
              : Colors.white.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(13),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

