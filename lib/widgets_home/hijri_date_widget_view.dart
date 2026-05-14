import 'package:flutter/material.dart';

import '../theme.dart';
import 'widget_snapshot.dart';

/// The premium "Hijri Date" home-screen widget — as a pure Flutter
/// widget.
///
/// `home_widget` renders this to a PNG via `renderFlutterWidget`, and
/// the native `HijriDateWidgetProvider` shows that PNG with
/// `centerCrop`. It therefore renders OUTSIDE the running app's tree,
/// so it must be fully self-contained:
///   * it reads everything from [WidgetSnapshot] — no `Provider`,
///     no `Theme.of`, no `MediaQuery.of`;
///   * it supplies its own [Directionality];
///   * it gives every `Text` an explicit style via [appFont], so it
///     needs no `DefaultTextStyle` / `Material` ancestor.
///
/// Visual language: a full-bleed gradient whose endpoints are BOTH
/// derived from the app's live accent colour — so the card always
/// follows the colour picked in Settings, in light AND dark mode —
/// with a soft gold glow, a light glassmorphism sheen, a hand-drawn
/// gold crescent and gold-accented typography.
///
/// It renders edge-to-edge (no rounded corners, no border, no
/// transparent margin) so the native side can `centerCrop` it to
/// fill the whole widget with nothing showing through behind it.
class HijriDateWidgetView extends StatelessWidget {
  final WidgetSnapshot snapshot;

  /// Logical canvas the parent renders this at. Kept here so the view
  /// and [WidgetSyncService] agree on one source of truth.
  static const Size canvasSize = Size(360, 168);

  const HijriDateWidgetView({super.key, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final s = snapshot;

    // Gradient endpoints, BOTH derived from the live accent so the
    // card always follows the app's chosen colour. Nothing here is
    // hard-coded — switch the accent (or the theme) and the whole
    // card recolours.
    final Color deep = s.isDark
        ? _mix(s.accent, Colors.black, 0.72)
        : _mix(s.accent, Colors.black, 0.62);
    final Color mid = s.isDark
        ? _mix(s.accent, Colors.black, 0.52)
        : _mix(s.accent, Colors.black, 0.28);

    const Color goldSoft = Color(0xFFF0D89A);
    const Color textMain = Color(0xFFF6F1E4);
    const Color textSoft = Color(0xFFCBD8CF);

    return Directionality(
      textDirection: s.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        width: canvasSize.width,
        height: canvasSize.height,
        // Full-bleed: edge-to-edge gradient, no rounded corners, no
        // border — so `centerCrop` on the native side leaves no gap
        // and nothing behind the card to show through.
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [deep, mid],
          ),
        ),
        child: Stack(
          children: [
            // Soft gold glow behind the date — clipped to the card by
            // the Stack's default hard-edge clip.
            Positioned(
              top: -34,
              left: s.isRtl ? -34 : null,
              right: s.isRtl ? null : -34,
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
            // Content. Generous padding keeps it inside the safe zone
            // that survives `centerCrop` on non-2:1 widget sizes.
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
              child: Row(
                children: [
                  const _Crescent(size: 40),
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
                            _RegionChip(label: s.regionLabel),
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
                            color: goldSoft,
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
          ],
        ),
      ),
    );
  }

  static Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;
}

/// Small gold pill showing the current region.
class _RegionChip extends StatelessWidget {
  final String label;

  const _RegionChip({required this.label});

  @override
  Widget build(BuildContext context) {
    const Color gold = Color(0xFFD9B45A);
    const Color goldSoft = Color(0xFFF0D89A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: gold.withOpacity(0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: gold.withOpacity(0.45), width: 0.8),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: appFont(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: goldSoft,
        ),
      ),
    );
  }
}

/// A hand-drawn gold crescent — the brand mark, kept lightweight so
/// the off-tree render stays cheap.
class _Crescent extends StatelessWidget {
  final double size;

  const _Crescent({required this.size});

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
