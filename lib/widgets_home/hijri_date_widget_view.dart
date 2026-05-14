import 'package:flutter/material.dart';

import '../theme.dart';
import 'widget_snapshot.dart';

/// The "Hijri Date" home-screen widget — a pure, self-contained
/// Flutter widget rendered to a PNG by `home_widget` and displayed by
/// the native AppWidget.
///
/// It renders OUTSIDE the running app's tree, so it reads everything
/// from [WidgetSnapshot] and supplies its own [Directionality]; every
/// `Text` carries an explicit [appFont] style.
///
/// Design: a single, flat, theme-following surface — the app's light
/// card colour in light mode, its dark card colour in dark mode — with
/// the active accent colour used for the Hijri date and the crescent.
/// There is no fixed background and nothing that ignores the active
/// theme: switch the app between light and dark and the widget follows.
class HijriDateWidgetView extends StatelessWidget {
  final WidgetSnapshot snapshot;

  /// Logical canvas the parent renders this at. Kept here so the view
  /// and [WidgetSyncService] agree on one source of truth.
  static const Size canvasSize = Size(360, 168);

  static const double _radius = 28;

  const HijriDateWidgetView({super.key, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    final bool dark = s.isDark;

    // One flat surface colour, taken straight from the app's theme —
    // the same colours its in-app cards use. No gradient, no fixed
    // brand background.
    final Color surface = dark ? AppColors.darkSurface : AppColors.white;
    final Color border = dark ? AppColors.darkBorder : AppColors.border;
    final Color textMain = dark ? AppColors.darkText : AppColors.text;
    final Color textSoft = dark ? AppColors.darkText2 : AppColors.text2;
    final Color accent = s.accent;

    return Directionality(
      textDirection: s.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        width: canvasSize.width,
        height: canvasSize.height,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(_radius),
          border: Border.all(color: border, width: 1),
        ),
        child: Row(
          children: [
            _Crescent(size: 40, color: accent),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          s.dayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: appFont(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: textMain,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _RegionChip(label: s.regionLabel, accent: accent),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    s.hijriLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appFont(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      color: accent,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.gregorianLine,
                    maxLines: 1,
                    style: appFont(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: textSoft,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small accent-tinted pill showing the current region.
class _RegionChip extends StatelessWidget {
  final String label;
  final Color accent;

  const _RegionChip({required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withOpacity(0.40), width: 0.8),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: appFont(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: accent,
        ),
      ),
    );
  }
}

/// A hand-drawn crescent in the active accent colour — the brand mark,
/// kept lightweight so the off-tree render stays cheap.
class _Crescent extends StatelessWidget {
  final double size;
  final Color color;

  const _Crescent({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _CrescentPainter(color)),
    );
  }
}

class _CrescentPainter extends CustomPainter {
  final Color color;

  const _CrescentPainter(this.color);

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
    canvas.drawPath(
      crescent,
      Paint()
        ..isAntiAlias = true
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _CrescentPainter oldDelegate) =>
      oldDelegate.color != color;
}
