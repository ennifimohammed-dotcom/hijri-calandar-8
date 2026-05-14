import 'package:flutter/material.dart';

import '../theme.dart';
import 'widget_common.dart';
import 'widget_snapshot.dart';

/// The premium "Islamic Day" home-screen widget — a smart spiritual
/// overview of the current day: the day name + Hijri date in a
/// header, today's Islamic occasion as the hero line, and the next
/// upcoming occasion with a countdown beneath it.
///
/// Same self-contained constraints as the other widget views — it is
/// rendered to a PNG OUTSIDE the running app's tree. See
/// [WidgetCardShell]. All display strings are pre-resolved on the
/// app side in [WidgetSnapshot]; this view only lays them out.
class IslamicDayWidgetView extends StatelessWidget {
  final WidgetSnapshot snapshot;

  /// Logical canvas the parent renders this at. Kept here so the view
  /// and [WidgetSyncService] agree on one source of truth.
  static const Size canvasSize = Size(360, 168);

  const IslamicDayWidgetView({super.key, required this.snapshot});

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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: crescent + day name + compact Hijri date.
          Row(
            children: [
              const WidgetCrescent(size: 30),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  s.dayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: appFont(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: textMain,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                s.hijriLine,
                maxLines: 1,
                style: appFont(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: goldSoft,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          // Today's Islamic occasion — the hero line.
          Text(
            s.islamicToday,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: appFont(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: goldSoft,
              height: 1.15,
            ),
          ),
          // Next upcoming occasion + countdown. Hidden when there is
          // nothing enabled to look forward to.
          if (s.islamicUpcoming.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              s.islamicUpcoming,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: appFont(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: textSoft,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
