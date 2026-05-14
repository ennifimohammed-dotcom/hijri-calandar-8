import 'package:flutter/material.dart';

import '../theme.dart';
import 'widget_common.dart';
import 'widget_snapshot.dart';

/// The premium "Hijri Date" home-screen widget — a pure Flutter
/// widget rendered to a PNG by `home_widget` and shown by the native
/// `HijriDateWidgetProvider` with `centerCrop`.
///
/// It renders OUTSIDE the running app's tree, so it is fully
/// self-contained — see [WidgetCardShell]. It reads everything from
/// [WidgetSnapshot] and gives every `Text` an explicit [appFont]
/// style.
///
/// Content: the day name, the Hijri date (the gold hero line), the
/// Gregorian date and a region pill.
class HijriDateWidgetView extends StatelessWidget {
  final WidgetSnapshot snapshot;

  /// Logical canvas the parent renders this at. Kept here so the view
  /// and [WidgetSyncService] agree on one source of truth.
  static const Size canvasSize = Size(360, 168);

  const HijriDateWidgetView({super.key, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    const Color goldSoft = Color(0xFFF0D89A);
    const Color textMain = Color(0xFFF6F1E4);
    const Color textSoft = Color(0xFFCBD8CF);

    return WidgetCardShell(
      accent: s.accent,
      isDark: s.isDark,
      isRtl: s.isRtl,
      size: canvasSize,
      child: Row(
        children: [
          const WidgetCrescent(size: 40),
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
    );
  }
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
