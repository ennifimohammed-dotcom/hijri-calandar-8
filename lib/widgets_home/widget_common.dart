import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shared building blocks for the home-screen widget views
/// (`HijriDateWidgetView`, `IslamicDayWidgetView`).
///
/// Both views are rendered to a PNG by `home_widget` OUTSIDE the
/// running app's tree, so everything here is fully self-contained:
/// no `Provider`, no `Theme.of`, no `MediaQuery.of`. Each view passes
/// in the values it resolved from [WidgetSnapshot].

/// The premium card "shell": a full-bleed accent gradient with a soft
/// gold glow, a barely-visible Islamic geometric pattern, and a light
/// glassmorphism sheen, its own [Directionality], and a padded slot
/// for [child].
///
/// Full-bleed on purpose — edge-to-edge, no rounded corners, no
/// border — so the native side can `centerCrop` it to fill the whole
/// widget with nothing showing through behind it.
///
/// [spiritualMode] lets callers tag the snapshot's day with a soft
/// ambience hint — `ramadan` warms the glow, `eid` brightens it a
/// touch, `friday` deepens the green, `night` dims everything down,
/// `default` is the standard look. The differences are intentionally
/// subtle (a few percent of opacity, a few hex digits of warmth) so
/// the widget stays calm and on-brand.
class WidgetCardShell extends StatelessWidget {
  final Color accent;
  final bool isDark;
  final bool isRtl;
  final Size size;
  final EdgeInsets padding;
  final Widget child;

  /// One of `ramadan` / `eid` / `friday` / `night` / `default`.
  /// Anything else is treated as `default`.
  final String spiritualMode;

  const WidgetCardShell({
    super.key,
    required this.accent,
    required this.isDark,
    required this.isRtl,
    required this.size,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(22, 18, 22, 18),
    this.spiritualMode = 'default',
  });

  @override
  Widget build(BuildContext context) {
    // Base palette — mode-aware so the card subtly shifts on
    // important Islamic moments while always staying inside the
    // royal-green / soft-gold brand.
    final double darkenDeep = switch (spiritualMode) {
      'night' => isDark ? 0.85 : 0.74,
      'ramadan' => isDark ? 0.74 : 0.62,
      'eid' => isDark ? 0.68 : 0.58,
      'friday' => isDark ? 0.74 : 0.66,
      _ => isDark ? 0.72 : 0.62,
    };
    final double darkenMid = switch (spiritualMode) {
      'night' => isDark ? 0.62 : 0.45,
      'ramadan' => isDark ? 0.50 : 0.26,
      'eid' => isDark ? 0.46 : 0.24,
      'friday' => isDark ? 0.50 : 0.28,
      _ => isDark ? 0.52 : 0.28,
    };
    final Color deep = _mix(accent, Colors.black, darkenDeep);
    final Color mid = _mix(accent, Colors.black, darkenMid);

    // Gold glow — warmer + slightly stronger during Ramadan / Eid,
    // dimmer at night, otherwise the standard signature glow.
    final Color glowHot = switch (spiritualMode) {
      'ramadan' => const Color(0xFFE5B450),
      'eid' => const Color(0xFFEDC868),
      'night' => const Color(0xFFB9954A),
      _ => const Color(0xFFD9B45A),
    };
    final int glowAlpha = switch (spiritualMode) {
      'ramadan' => 0x66,
      'eid' => 0x60,
      'friday' => 0x55,
      'night' => 0x38,
      _ => 0x4F,
    };
    final Color glowCenter = glowHot.withAlpha(glowAlpha);
    final Color glowEdge = glowHot.withAlpha(0);

    // Sheen — a touch brighter at Eid (celebratory), a touch dimmer
    // at night.
    final double sheenTop = switch (spiritualMode) {
      'eid' => 0.13,
      'night' => 0.07,
      _ => 0.10,
    };

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
            // default hard-edge clip. Slightly larger than before
            // for a more premium "depth" feel.
            Positioned(
              top: -40,
              left: isRtl ? -40 : null,
              right: isRtl ? null : -40,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [glowCenter, glowEdge],
                  ),
                ),
              ),
            ),
            // Very subtle Islamic geometric pattern — tessellating
            // 8-point stars, drawn at ~3 % opacity so it reads as a
            // texture rather than a decoration. Painted ONCE per
            // off-tree render; lightweight (~18 stars, 16 segments
            // each).
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _IslamicPatternPainter(
                    color: Colors.white.withOpacity(0.035),
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
                      Colors.white.withOpacity(sheenTop),
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

/// Tessellating 8-point Islamic star pattern — drawn as a faint
/// texture across the card. The stars are tiled on a regular grid
/// so adjacent rows interlock; alpha is set by the caller via
/// [color] so the pattern reads as "depth" rather than decoration.
class _IslamicPatternPainter extends CustomPainter {
  final Color color;

  const _IslamicPatternPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.65
      ..isAntiAlias = true
      ..color = color;

    const double tile = 56;
    const double radius = tile * 0.34;

    // Stagger every other row by half a tile so the stars sit in
    // an Andalusian-style brick-grid arrangement rather than a
    // bare square grid.
    double y = -tile;
    int row = 0;
    while (y < size.height + tile) {
      final double xOffset = (row.isOdd) ? tile / 2 : 0.0;
      double x = -tile + xOffset;
      while (x < size.width + tile) {
        _draw8PointStar(canvas, Offset(x, y), radius, paint);
        x += tile;
      }
      y += tile * 0.85;
      row += 1;
    }
  }

  void _draw8PointStar(
    Canvas canvas,
    Offset center,
    double r,
    Paint paint,
  ) {
    final path = Path();
    // 16 points alternating outer-radius / inner-radius makes a
    // clean 8-point star. Inner-to-outer ratio of 0.50 gives a
    // recognisable "rub el hizb" silhouette without sharp spikes.
    const int points = 16;
    final double inner = r * 0.50;
    for (int i = 0; i < points; i++) {
      final angle = i * (math.pi / 8);
      final rad = (i.isEven) ? r : inner;
      final p = Offset(
        center.dx + rad * math.cos(angle),
        center.dy + rad * math.sin(angle),
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

  @override
  bool shouldRepaint(covariant _IslamicPatternPainter oldDelegate) =>
      oldDelegate.color != color;
}
