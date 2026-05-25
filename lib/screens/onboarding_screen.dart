import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/hijri_countries.dart';
import '../providers/app_provider.dart';
import '../services/country_detector.dart';
import '../theme.dart';
import '../widgets/country_picker_sheet.dart';
import '../widgets/gps_rationale_dialog.dart';
import 'home_screen.dart';

/// First-launch picker mode for the Hijri calendar source.
/// Replaces the legacy 2-option region toggle.
enum _HijriSourceMode {
  /// Use GPS + timezone + locale to pick the country for the
  /// user. The actual detection runs at `_finish()` time
  /// (which may prompt for GPS permission); before that we
  /// show a "Suggested: 🇸🇦 Saudi Arabia" caption derived
  /// from a permission-free timezone read.
  auto,

  /// User explicitly picks a country from the full 30-entry
  /// list via the country picker sheet.
  manual,

  /// User skips the picker; the app defaults to the global
  /// Umm al-Qura calendar with no online sync attempts.
  skip,
}

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

  String _selectedLang = 'ar';

  // ── Hybrid Hijri source picker (Phase 7 improvement 2) ──
  //
  // Replaces the legacy `_selectedRegion = 'ma'` single-string
  // state with a three-mode enum + the country picked when the
  // user goes manual. Default is `auto` so the most common path
  // (one tap → done) becomes the natural one.
  _HijriSourceMode _sourceMode = _HijriSourceMode.auto;

  /// The country the user picked in the "Choose manually"
  /// bottom sheet. Empty when [_sourceMode] is not [manual].
  /// Stored as ISO 3166-1 alpha-2 uppercase.
  String _manualCountry = '';

  /// Best-effort no-permission country guess (timezone + locale,
  /// no GPS). Computed once at `initState` and surfaced in the
  /// "Auto-detect" card caption so the user sees what we'd
  /// pick BEFORE granting any permission. Empty string if even
  /// the quick guess found nothing recognised.
  String _suggestedCountry = '';

  /// Country actually detected after the user tapped "Allow" on
  /// the GPS rationale dialog. Different from `_suggestedCountry`
  /// — that's a no-permission heuristic; this one is the
  /// authoritative result of the full GPS+timezone+locale ladder
  /// and is already applied to the provider by the time it lands
  /// here. Empty until the user goes through the auto-detect
  /// flow successfully.
  String _autoDetectedCountry = '';

  /// True while the live detection is running. Drives a small
  /// spinner inside the "Auto-detect" card so the user knows the
  /// permission grant kicked off real work.
  bool _isDetecting = false;

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

  @override
  void initState() {
    super.initState();
    // Permission-free country guess (timezone → locale) used to
    // pre-fill the "Auto-detect" card caption. Synchronous and
    // cheap (~5 ms once the tz DB is initialized lazily).
    _suggestedCountry = CountryDetector.detectQuick();
  }

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

    // Apply the Hijri source according to the picker mode.
    // Each branch ends up calling `setCountry()` so the kernel,
    // notification scheduler, and cache all see a consistent
    // post-onboarding state.
    switch (_sourceMode) {
      case _HijriSourceMode.auto:
        // Detection ran LIVE during the card tap (via the GPS
        // rationale dialog + `_onAutoTapped`). If the user
        // granted permission and detection produced a real
        // country, the provider already has it set — no need
        // to re-call. If they declined or detection failed,
        // fall back to the no-permission `detectQuick` guess
        // so they still get something reasonable instead of
        // the global XX default.
        if (_autoDetectedCountry.isNotEmpty &&
            _autoDetectedCountry != 'XX') {
          // Already applied during the tap — no-op for
          // `setCountry` since the value matches. Kept for
          // clarity / safety against future refactors.
          await p.setCountry(_autoDetectedCountry);
        } else if (_suggestedCountry.isNotEmpty &&
            _suggestedCountry != 'XX') {
          await p.setCountry(_suggestedCountry);
        } else {
          await p.setCountry('XX');
        }
        break;
      case _HijriSourceMode.manual:
        if (_manualCountry.isNotEmpty) {
          await p.setCountry(_manualCountry);
        } else {
          // User picked "manual" but never tapped a country in
          // the sheet — treat as skip so they get a usable
          // default rather than the empty/legacy state.
          await p.setCountry('XX');
        }
        break;
      case _HijriSourceMode.skip:
        await p.setCountry('XX');
        break;
    }

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

  /// Handler for the "Auto-detect my country" card tap.
  ///
  /// Flow
  ///   1. Show the GPS rationale dialog so the user understands
  ///      why we're about to ask for location.
  ///   2. If they cancel: still mark the card as selected (we
  ///      respect their choice of mode), but leave detection
  ///      pending — `_finish` will fall back to the no-permission
  ///      quick guess.
  ///   3. If they allow: run `p.detectCountryAndApply()` (which
  ///      requests the actual OS permission, reads GPS, walks
  ///      the timezone/locale fallback ladder, and applies the
  ///      result via `setCountry`). The provider notifies, so
  ///      the calendar, header badge, and any other watcher
  ///      updates live.
  ///   4. Surface a snackbar with the detected flag + name so
  ///      the user sees confirmation that something happened.
  ///
  /// Re-runnable — tapping the card a second time re-shows the
  /// dialog and tries again, which is what a user who initially
  /// denied permission would want.
  Future<void> _onAutoTapped(AppProvider p) async {
    if (_isDetecting) return;

    // Always flip the mode to auto regardless of dialog outcome
    // — the user clearly wants this option, the dialog only
    // decides whether we actually run detection now.
    setState(() => _sourceMode = _HijriSourceMode.auto);

    final allowed = await showGpsRationaleDialog(
      context: context,
      locale: _selectedLang,
    );
    if (!mounted || !allowed) return;

    setState(() => _isDetecting = true);
    String iso = 'XX';
    try {
      iso = await p.detectCountryAndApply();
    } catch (_) {
      iso = 'XX';
    }
    if (!mounted) return;
    setState(() {
      _isDetecting = false;
      _autoDetectedCountry = iso;
    });

    // Feedback — green snackbar on success, red on graceful
    // failure (permission denied or no GPS fix).
    final ok = iso.isNotEmpty && iso != 'XX';
    final c = hijriCountryByCode(iso);
    final loc = _selectedLang;
    final successMsg = switch (loc) {
      'ar' => '✓ تم تحديد بلدك: ${c.flag} ${c.localizedName(loc)}',
      'fr' => '✓ Pays détecté : ${c.flag} ${c.localizedName(loc)}',
      'es' => '✓ País detectado: ${c.flag} ${c.localizedName(loc)}',
      _ => '✓ Country detected: ${c.flag} ${c.localizedName(loc)}',
    };
    final failMsg = switch (loc) {
      'ar' => 'تعذّر تحديد البلد — يمكنك الاختيار يدوياً',
      'fr' => 'Détection impossible — choisissez manuellement',
      'es' => 'No se pudo detectar — elige manualmente',
      _ => 'Detection failed — pick manually',
    };
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
          ok ? successMsg : failMsg,
          style: appFont(fontSize: 12.5, color: Colors.white),
        ),
        backgroundColor:
            ok ? AppColors.green : const Color(0xFFD94F4F),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 2400),
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ));
  }

  /// Opens the shared country picker sheet and stores the
  /// user's pick. Switches `_sourceMode` to `manual` so the
  /// chosen country wins at `_finish` time. Closing the sheet
  /// without picking anything leaves `_manualCountry` empty
  /// (handled in `_finish`).
  Future<void> _openManualPicker() async {
    final picked = await showHijriCountryPicker(
      context: context,
      activeCountryCode: _manualCountry.isEmpty ? 'XX' : _manualCountry,
      locale: _selectedLang,
      isDark: false, // onboarding always uses the gold-on-green theme.
    );
    if (!mounted || picked == null) return;
    setState(() {
      _sourceMode = _HijriSourceMode.manual;
      _manualCountry = picked.code;
    });
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
                        sourceMode: _sourceMode,
                        manualCountry: _manualCountry,
                        suggestedCountry: _suggestedCountry,
                        autoDetectedCountry: _autoDetectedCountry,
                        isDetecting: _isDetecting,
                        onLangSelected: (l) =>
                            setState(() => _selectedLang = l),
                        onSourceModeSelected: (m) =>
                            setState(() => _sourceMode = m),
                        onAutoRequested: () => _onAutoTapped(p),
                        onManualPickRequested: _openManualPicker,
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
  final _HijriSourceMode sourceMode;
  final String manualCountry;
  final String suggestedCountry;
  final String autoDetectedCountry;
  final bool isDetecting;
  final ValueChanged<String> onLangSelected;
  final ValueChanged<_HijriSourceMode> onSourceModeSelected;
  final VoidCallback onAutoRequested;
  final VoidCallback onManualPickRequested;
  const _LanguageRegionPage({
    required this.selectedLang,
    required this.sourceMode,
    required this.manualCountry,
    required this.suggestedCountry,
    required this.autoDetectedCountry,
    required this.isDetecting,
    required this.onLangSelected,
    required this.onSourceModeSelected,
    required this.onAutoRequested,
    required this.onManualPickRequested,
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
    final sourceTitle = loc == 'ar'
        ? 'مصدر التقويم الهجري'
        : loc == 'fr'
            ? 'Source du calendrier Hijri'
            : loc == 'es'
                ? 'Fuente del calendario Hijri'
                : 'Hijri calendar source';

    const langs = [
      ('ar', '🇲🇦', 'العربية'),
      ('fr', '🇫🇷', 'Français'),
      ('en', '🇬🇧', 'English'),
      ('es', '🇪🇸', 'Español'),
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
          _SectionHeading(text: sourceTitle),
          const SizedBox(height: 14),
          // ── Three source-mode cards ─────────────────────
          _SourceModeCard(
            mode: _HijriSourceMode.auto,
            active: sourceMode == _HijriSourceMode.auto,
            // Spinner takes over the icon slot while the GPS
            // permission grant + detection is in flight.
            icon: '📍',
            busy: isDetecting,
            title: _autoTitle(loc),
            subtitle: _autoSubtitle(
              loc,
              suggestedCountry,
              autoDetectedCountry,
              isDetecting,
            ),
            // Tap → rationale dialog → live detection. Routes
            // through the parent's `_onAutoTapped`, which also
            // handles the mode flip + snackbar feedback.
            onTap: onAutoRequested,
          ),
          const SizedBox(height: 10),
          _SourceModeCard(
            mode: _HijriSourceMode.manual,
            active: sourceMode == _HijriSourceMode.manual,
            icon: '🌍',
            title: _manualTitle(loc),
            subtitle: _manualSubtitle(loc, manualCountry),
            // Tap → open the picker. Picking a country flips
            // the parent state to `manual` automatically; we
            // don't also call `onSourceModeSelected` here to
            // avoid a flash of "manual selected with no
            // country" when the user dismisses the sheet.
            onTap: onManualPickRequested,
          ),
          const SizedBox(height: 10),
          _SourceModeCard(
            mode: _HijriSourceMode.skip,
            active: sourceMode == _HijriSourceMode.skip,
            icon: '⚙️',
            title: _skipTitle(loc),
            subtitle: _skipSubtitle(loc),
            onTap: () => onSourceModeSelected(_HijriSourceMode.skip),
          ),
        ],
      ),
    );
  }

  // ── Localized strings for the three source-mode cards ──

  String _autoTitle(String loc) => switch (loc) {
        'ar' => 'اكتشاف بلدي تلقائياً',
        'fr' => 'Détecter mon pays automatiquement',
        'es' => 'Detectar mi país automáticamente',
        _ => 'Auto-detect my country',
      };

  /// Subtitle for the "Auto-detect" card. Three states, in
  /// priority order:
  ///
  ///   1. `busy` → "Detecting your location..." with the
  ///      pulsing icon in the parent card slot. Highest
  ///      priority because it overrides the "what you'll get"
  ///      messaging.
  ///   2. `detected` set → "✓ Detected: 🇸🇦 Saudi Arabia".
  ///      Shown after a successful auto-detect; gives the
  ///      user immediate confirmation that the tap did real
  ///      work instead of waiting until `_finish`.
  ///   3. `suggested` set (no detection yet) → "Suggested:
  ///      🇸🇦 Saudi Arabia". Pre-grant hint computed from the
  ///      no-permission timezone+locale guess.
  ///   4. Neither → generic "Recommended" copy.
  String _autoSubtitle(
    String loc,
    String suggested,
    String detected,
    bool busy,
  ) {
    if (busy) {
      return switch (loc) {
        'ar' => 'جاري تحديد موقعك…',
        'fr' => 'Détection de votre position…',
        'es' => 'Detectando tu ubicación…',
        _ => 'Detecting your location…',
      };
    }
    if (detected.isNotEmpty && detected != 'XX') {
      final c = hijriCountryByCode(detected);
      final name = c.localizedName(loc);
      return switch (loc) {
        'ar' => '✓ تم: ${c.flag} $name',
        'fr' => '✓ Détecté : ${c.flag} $name',
        'es' => '✓ Detectado: ${c.flag} $name',
        _ => '✓ Detected: ${c.flag} $name',
      };
    }
    if (suggested.isEmpty || suggested == 'XX') {
      return switch (loc) {
        'ar' => 'مُستحسَن — يستعمل GPS والمنطقة الزمنية',
        'fr' => 'Recommandé — utilise le GPS et le fuseau horaire',
        'es' => 'Recomendado — usa GPS y zona horaria',
        _ => 'Recommended — uses GPS and timezone',
      };
    }
    final c = hijriCountryByCode(suggested);
    final name = c.localizedName(loc);
    return switch (loc) {
      'ar' => 'مُقترَح: ${c.flag} $name',
      'fr' => 'Suggéré : ${c.flag} $name',
      'es' => 'Sugerido: ${c.flag} $name',
      _ => 'Suggested: ${c.flag} $name',
    };
  }

  String _manualTitle(String loc) => switch (loc) {
        'ar' => 'اختيار يدوي من القائمة',
        'fr' => 'Choisir manuellement dans la liste',
        'es' => 'Elegir manualmente de la lista',
        _ => 'Choose manually from list',
      };

  String _manualSubtitle(String loc, String picked) {
    if (picked.isEmpty) {
      return switch (loc) {
        'ar' => 'أكثر من 30 دولة مع المرجع الرسمي لكل واحدة',
        'fr' => 'Plus de 30 pays avec leur autorité officielle',
        'es' => 'Más de 30 países con su autoridad oficial',
        _ => '30+ countries with their official authority',
      };
    }
    final c = hijriCountryByCode(picked);
    return '${c.flag} ${c.localizedName(loc)}';
  }

  String _skipTitle(String loc) => switch (loc) {
        'ar' => 'تخطي (استعمال أم القرى)',
        'fr' => 'Passer (utiliser Umm al-Qura)',
        'es' => 'Omitir (usar Umm al-Qura)',
        _ => 'Skip (use Umm al-Qura)',
      };

  String _skipSubtitle(String loc) => switch (loc) {
        'ar' => 'تقويم افتراضي بدون اتصال بالإنترنت',
        'fr' => 'Calendrier par défaut sans connexion',
        'es' => 'Calendario predeterminado sin conexión',
        _ => 'Default calendar with no internet sync',
      };
}

/// One of the three source-mode picker cards (auto / manual /
/// skip). Re-uses [_GlassCard]'s styling so the visual identity
/// matches the rest of the onboarding flow.
class _SourceModeCard extends StatelessWidget {
  final _HijriSourceMode mode;
  final bool active;
  final String icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Renders an in-line spinner in place of [icon] while the
  /// card's underlying action is running (e.g. live GPS
  /// detection on the "Auto-detect" card). Only the auto card
  /// ever passes `true`; the others stay static.
  final bool busy;

  const _SourceModeCard({
    required this.mode,
    required this.active,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      onTap: onTap,
      active: active,
      fullWidth: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            // Spinner takes the icon's slot during live work
            // (e.g. GPS detection). Same 24 px footprint so the
            // row layout doesn't reflow when the spinner appears.
            if (busy)
              SizedBox(
                width: 24,
                height: 24,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      active
                          ? const Color(0xFF0A2519)
                          : Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              )
            else
              Text(icon, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: appFont(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: active
                          ? const Color(0xFF0A2519)
                          : Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: appFont(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: active
                          ? const Color(0xFF0A2519).withValues(alpha: 0.75)
                          : Colors.white.withValues(alpha: 0.65),
                      height: 1.35,
                    ),
                  ),
                ],
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
    const activeBg = Color(0xFFE9C46A);
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

