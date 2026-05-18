import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/widget_sync_service.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';

/// Launch experience for "بدر | badr".
///
/// The previous version composed the splash programmatically — a
/// custom radial gradient, hand-drawn crescent watermark, animated
/// halo, runtime-rendered app-name and tagline, and a bottom
/// association credit assembled out of widgets. Per the latest
/// brand spec the splash must reproduce the supplied mockup
/// **exactly**, so we now display the mockup as a single full-bleed
/// asset (`assets/icon/splash_artwork.png`) and only layer the
/// animation and navigation logic on top of it.
///
/// What ships with the artwork:
///   • Dark royal-green gradient background with soft golden glow.
///   • The official app icon (calendar with crescent + star) at the
///     centre — same asset that's used for the Android launcher
///     icon (`assets/icon/icon.png`), so splash and launcher stay
///     visually identical.
///   • The "بدر | badr" wordmark, the bilingual tagline, and the
///     Shabab Al Khair association credit at the bottom — all
///     rasterised into the mockup so kerning and weight match the
///     brand exactly.
///
/// On top of the artwork the screen only does three things:
///   1. fade the artwork in from 0 → 1 opacity over the first
///      ~1.1 s (eases the entry);
///   2. scale-in from 0.96 → 1.0 in the same window (premium feel);
///   3. once the master animation completes (~2.6 s total), routes
///      to the OnboardingScreen on first launch or directly to the
///      HomeScreen otherwise.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _master;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  /// Background colour painted UNDER the artwork so cropping on
  /// tall phones (or letterboxing on wide tablets) reads as part
  /// of the same dark-green palette. Sampled from the mockup's
  /// darkest top corner so the seam is invisible.
  static const Color _bgFill = Color(0xFF0A2A1F);

  @override
  void initState() {
    super.initState();

    // System chrome lifted off the artwork so the gradient runs
    // edge to edge. Status-bar icons stay light because the
    // background is dark in every mode.
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: _bgFill,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    _master = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );

    // The artwork fades and slightly scales in during the first
    // ~45 % of the timeline; the rest of the timeline is a
    // breath-hold before navigating, so the brand has a moment
    // to register before the screen transitions.
    _fade = CurvedAnimation(
      parent: _master,
      curve: const Interval(0.00, 0.45, curve: Curves.easeOutCubic),
    );
    _scale = CurvedAnimation(
      parent: _master,
      curve: const Interval(0.00, 0.45, curve: Curves.easeOutCubic),
    );

    _master.forward();
    _master.addStatusListener((s) {
      if (s == AnimationStatus.completed) _navigateNext();
    });

    // Cold-launch shortcut: when the user double-tapped a Mini
    // Calendar widget cell with the app fully closed, we want
    // AddEventScreen to appear DIRECTLY rather than waiting out
    // the full 2.6 s splash animation. WidgetSyncService picks
    // up the launch URI from its own post-frame callback in
    // main.dart and exposes the prefilled start [DateTime] via
    // `openAddEventForDate`; as soon as it's set we short-
    // circuit the splash. HomeScreen's catch-up in initState
    // takes care of actually pushing AddEventScreen once it
    // mounts.
    WidgetSyncService.instance.openAddEventForDate
        .addListener(_onWidgetColdLaunch);
  }

  void _onWidgetColdLaunch() {
    if (!mounted) return;
    if (WidgetSyncService.instance.openAddEventForDate.value == null) return;
    // Detach immediately so we can't double-navigate if the
    // listener fires again before dispose.
    WidgetSyncService.instance.openAddEventForDate
        .removeListener(_onWidgetColdLaunch);
    _master.stop();
    _navigateNext();
  }

  Future<void> _navigateNext() async {
    if (!mounted) return;
    bool firstLaunch = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      firstLaunch = !(prefs.getBool('onboarding_complete') ?? false);
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, __, ___) =>
            firstLaunch ? const OnboardingScreen() : const HomeScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    WidgetSyncService.instance.openAddEventForDate
        .removeListener(_onWidgetColdLaunch);
    _master.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgFill,
      body: AnimatedBuilder(
        animation: _master,
        builder: (context, _) {
          return Stack(
            fit: StackFit.expand,
            children: [
              // The full-bleed splash artwork. `BoxFit.cover`
              // guarantees the gradient reaches every edge on any
              // aspect ratio; the [_bgFill] backdrop hides any
              // sliver the cover crop has to discard at the very
              // top/bottom on extra-tall phones so the seam stays
              // invisible.
              Positioned.fill(
                child: Opacity(
                  opacity: _fade.value,
                  child: Transform.scale(
                    // 0.96 → 1.00 — subtle, premium. Anything larger
                    // feels like an explosion on a brand surface.
                    scale: 0.96 + 0.04 * _scale.value,
                    child: Image.asset(
                      'assets/icon/splash_artwork.png',
                      fit: BoxFit.cover,
                      // Cache it once so the splash doesn't
                      // flicker if the system rebuilds between
                      // frames during navigation.
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
