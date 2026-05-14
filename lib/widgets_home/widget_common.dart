import 'package:flutter/material.dart';

/// Shared building blocks for the home-screen widget views
/// (`HijriDateWidgetView`, `IslamicDayWidgetView`).
///
/// Both views are rendered to a PNG by `home_widget` OUTSIDE the
/// running app's tree, so everything here is fully self-contained:
/// no `Provider`, no `Theme.of`, no `MediaQuery.of`. Each view passes
/// in the values it resolved from [WidgetSnapshot].

/// The premium card "shell": a full-bleed accent gradient with a soft
/// gold glow and a light glassmorphism sheen, its own [Directionality],
/// and a padded slot for [child].
///
/// Full-bleed on purpose — edge-to-edge, no rounded corners, no
/// border — so the native side can `centerCrop` it to fill the whole
/// widget with nothing showing through behind it. The gradient
/// endpoints are BOTH derived from the live accent, so every widget
/// follows the colour picked in Settings, in light AND dark mode.
class WidgetCardShell extends StatelessWidget {
  final Color accent;
  final bool isDark;
  final bool isRtl;
  final Size size;
  final EdgeInsets padding;
  final Widget child;

  const WidgetCardShell({
    super.key,
    required this.accent,
    required this.isDark,
    required this.isRtl,
    required this.size,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(22, 18, 22, 18),
  });

  @override
  Widget build(BuildContext context) {
    final Color deep = isDark
        ? _mix(accent, Colors.black, 0.72)
        : _mix(accent, Colors.black, 0.62);
    final Color mid = isDark
        ? _mix(accent, Colors.black, 0.52)
        : _mix(accent, Colors.black, 0.28);

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [deep, mid],
          ),
        ),
        child: Stack(
          children: [
            // Soft gold glow — clipped to the card by the Stack's
            // default hard-edge clip.
            Positioned(
              top: -34,
              left: isRtl ? -34 : null,
              right: isRtl ? null : -34,
              child: Container(
                width: 180,
                height: 180,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0x4FD9B45A), Color(0x00D9B45A)],
                  ),
                ),
              ),
            ),
            // Light glassmorphism sheen — a faint top-down highlight.
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withOpacity(0.10),
                      Colors.white.withOpacity(0.015),
                    ],
                  ),
                ),
              ),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }

  static Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;
}

/// A hand-drawn gold crescent — the shared brand mark for the
/// home-screen widget views. Kept lightweight so the off-tree render
/// stays cheap.
class WidgetCrescent extends StatelessWidget {
  final double size;

  const WidgetCrescent({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const CustomPaint(painter: _CrescentPainter()),
    );
  }
}

class _CrescentPainter extends CustomPainter {
  const _CrescentPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final outer = Path()
      ..addOval(Rect.fromCircle(center: Offset(r, r), radius: r));
    final inner = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(r + r * 0.40, r - r * 0.06),
          radius: r * 0.86,
        ),
      );
    final crescent = Path.combine(PathOperation.difference, outer, inner);
    final paint = Paint()
      ..isAntiAlias = true
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF0D89A), Color(0xFFC8943A)],
      ).createShader(Rect.fromCircle(center: Offset(r, r), radius: r));
    canvas.drawPath(crescent, paint);
  }

  @override
  bool shouldRepaint(covariant _CrescentPainter oldDelegate) => false;
}
