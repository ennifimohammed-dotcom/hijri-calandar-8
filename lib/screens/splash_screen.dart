import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/app_provider.dart';
import '../theme.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';

/// Luxurious launch experience for "بدر | badr".
///
/// Atmosphere: dark royal green → calm green gradient with a soft
/// golden glow at the centre, a barely-there crescent watermark, and
/// a faint Islamic geometric pattern. Everything is restrained — no
/// busy decoration — so the app icon and the name carry the eye.
///
/// Sequence (≈ 2.6 s total):
///   • icon fades + scales gently in (0.0 – 1.0 s)
///   • golden ring pulses behind the icon (1.0 – 1.6 s)
///   • app name + tagline fade in (1.0 – 1.6 s)
///   • association credit at the bottom fades in last (1.6 – 2.2 s)
///   • smooth cross-fade to onboarding / home (2.2 – 2.6 s)
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _master;
  // Curves carve four overlapping sub-windows out of [_master] so the
  // sequence above can be expressed as four Tweens against the same
  // 2.6-second timeline.
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _haloOpacity;
  late final Animation<double> _titleFade;
  late final Animation<double> _associationFade;

  @override
  void initState() {
    super.initState();
    // Mostly transparent system chrome so the gradient takes the
    // entire screen. Restored on dispose.
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF0E2E22),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    _master = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );

    _logoFade = CurvedAnimation(
      parent: _master,
      curve: const Interval(0.00, 0.40, curve: Curves.easeOutCubic),
    );
    _logoScale = CurvedAnimation(
      parent: _master,
      curve: const Interval(0.00, 0.55, curve: Curves.easeOutBack),
    );
    _haloOpacity = CurvedAnimation(
      parent: _master,
      curve: const Interval(0.35, 0.75, curve: Curves.easeInOut),
    );
    _titleFade = CurvedAnimation(
      parent: _master,
      curve: const Interval(0.40, 0.65, curve: Curves.easeOut),
    );
    _associationFade = CurvedAnimation(
      parent: _master,
      curve: const Interval(0.65, 0.90, curve: Curves.easeOut),
    );

    _master.forward();
    _master.addStatusListener((s) {
      if (s == AnimationStatus.completed) _navigateNext();
    });
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
        pageBuilder: (_, __, ___) => firstLaunch
            ? const OnboardingScreen()
            : const HomeScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _master.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: _master,
        builder: (context, _) => Stack(
          fit: StackFit.expand,
          children: [
            // ─── Background gradient: royal green → calm green ──
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF0A2519), // deep royal green
                    Color(0xFF0E4A2D), // mid forest green
                    Color(0xFF1A6B45), // calm green
                  ],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
              child: SizedBox.expand(),
            ),
            // ─── Subtle crescent watermark ──────────────────────
            Positioned(
              top: -120,
              right: -90,
              child: Opacity(
                opacity: 0.05,
                child: _CrescentWatermark(size: 360),
              ),
            ),
            // ─── Faint geometric pattern (octagram) ─────────────
            Positioned(
              bottom: -140,
              left: -80,
              child: Opacity(
                opacity: 0.04,
                child: _GeometricStar(size: 320),
              ),
            ),
            // ─── Centred soft golden glow ───────────────────────
            Center(
              child: Container(
                width: 360,
                height: 360,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFE9C46A).withValues(alpha: 0.28),
                      const Color(0xFFE9C46A).withValues(alpha: 0.06),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
            // ─── Main content (logo, name, tagline) ─────────────
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Animated golden halo + icon
                    SizedBox(
                      width: 200,
                      height: 200,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Pulsing golden halo
                          Opacity(
                            opacity: _haloOpacity.value * 0.85,
                            child: Container(
                              width: 200,
                              height: 200,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    const Color(0xFFF1D67E)
                                        .withValues(alpha: 0.45),
                                    const Color(0xFFF1D67E)
                                        .withValues(alpha: 0.08),
                                    Colors.transparent,
                                  ],
                                  stops: const [0.0, 0.55, 1.0],
                                ),
                              ),
                            ),
                          ),
                          // App icon — fade + subtle scale
                          Opacity(
                            opacity: _logoFade.value,
                            child: Transform.scale(
                              scale: 0.85 + 0.15 * _logoScale.value,
                              child: Container(
                                width: 140,
                                height: 140,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFE9C46A)
                                          .withValues(alpha: 0.35),
                                      blurRadius: 30,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: ClipOval(
                                  child: Image.asset(
                                    'assets/icon/icon.png',
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),
                    // App name
                    Opacity(
                      opacity: _titleFade.value,
                      child: const _AppNameRow(),
                    ),
                    const SizedBox(height: 14),
                    // Tagline — slightly transparent off-white
                    Opacity(
                      opacity: _titleFade.value * 0.85,
                      child: Text(
                        _tagline(context),
                        textAlign: TextAlign.center,
                        style: appFont(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.72),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ─── Production / association credit ────────────────
            Positioned(
              left: 0,
              right: 0,
              bottom: 36,
              child: Opacity(
                opacity: _associationFade.value,
                child: const _AssociationCredit(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _tagline(BuildContext context) {
    final loc = context.read<AppProvider>().locale;
    if (loc == 'ar') {
      return 'رفيقك في تذكّر مواسم الخير وأعمال العبادة';
    }
    if (loc == 'fr') {
      return 'Votre compagnon pour les saisons du bien et les actes d\'adoration';
    }
    if (loc == 'es') {
      return 'Tu compañero en las estaciones del bien y los actos de adoración';
    }
    return 'Your companion in the seasons of khayr and acts of worship';
  }
}

class _AppNameRow extends StatelessWidget {
  const _AppNameRow();

  @override
  Widget build(BuildContext context) {
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: appFont(
          fontSize: 38,
          fontWeight: FontWeight.bold,
          color: const Color(0xFFF6E5B5),
          height: 1.0,
          shadows: [
            Shadow(
              color: const Color(0xFFE9C46A).withValues(alpha: 0.55),
              blurRadius: 16,
            ),
          ],
        ),
        children: [
          const TextSpan(text: 'بدر  '),
          TextSpan(
            text: '|',
            style: appFont(
              fontSize: 30,
              fontWeight: FontWeight.w300,
              color: const Color(0xFFF6E5B5).withValues(alpha: 0.65),
            ),
          ),
          const TextSpan(text: '  badr'),
        ],
      ),
    );
  }
}

class _AssociationCredit extends StatelessWidget {
  const _AssociationCredit();

  @override
  Widget build(BuildContext context) {
    final loc = context.read<AppProvider>().locale;
    final producedBy = loc == 'ar'
        ? 'إنتاج'
        : loc == 'fr'
            ? 'Produit par'
            : loc == 'es'
                ? 'Producido por'
                : 'Produced by';
    final association = loc == 'ar'
        ? 'جمعية شباب الخير للتنمية والأنشطة الاجتماعية'
        : loc == 'fr'
            ? 'Association Chabab Al Khair pour le développement et les activités sociales'
            : loc == 'es'
                ? 'Asociación Chabab Al Khair para el desarrollo y las actividades sociales'
                : 'Association Chabab Al Khair for Development and Social Activities';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Small association logo
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Image.asset(
                'assets/icon/chabab_alkhair.jpg',
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            producedBy,
            style: appFont(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.6,
              color: const Color(0xFFE9C46A).withValues(alpha: 0.78),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            association,
            textAlign: TextAlign.center,
            style: appFont(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.72),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Decorative painters ─────────────────────────────────────────

class _CrescentWatermark extends StatelessWidget {
  final double size;
  const _CrescentWatermark({required this.size});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CrescentPainter(),
      ),
    );
  }
}

class _CrescentPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFF6E5B5)
      ..style = PaintingStyle.fill;
    // Outer disc
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.5),
      size.width * 0.45,
      paint,
    );
    // Cut-out disc — offset to produce a crescent
    final cutout = Paint()..blendMode = BlendMode.dstOut;
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.5),
      size.width * 0.45,
      paint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.62, size.height * 0.42),
      size.width * 0.40,
      cutout,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GeometricStar extends StatelessWidget {
  final double size;
  const _GeometricStar({required this.size});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _OctagramPainter()),
    );
  }
}

class _OctagramPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFF6E5B5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.42;
    // Two overlapping squares = traditional 8-pointed Islamic star
    for (final rotation in [0.0, math.pi / 4]) {
      final path = Path();
      for (var i = 0; i < 4; i++) {
        final a = rotation + i * math.pi / 2;
        final p = Offset(
          center.dx + r * math.cos(a),
          center.dy + r * math.sin(a),
        );
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
