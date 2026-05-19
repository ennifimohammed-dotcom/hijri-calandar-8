import 'package:flutter/material.dart';

import '../theme.dart';
import 'widget_common.dart';
import 'widget_snapshot.dart';

/// The premium "Islamic Day" home-screen widget — a calm, glanceable
/// spiritual companion. Visual hierarchy is deliberately strong:
///
///   * Hero line: today's Islamic occasion (large, bold) — the
///     reason this widget exists. It is the FIRST thing the eye
///     lands on when the user looks at their home screen.
///   * Quiet header above it: the crescent, the day name, and the
///     compact Hijri date — small, muted, in one line so they don't
///     compete with the hero.
///   * Soft gold badge below: the next upcoming occasion's name +
///     a localised countdown (e.g. "غدًا" / "بعد 3 أيام") in a
///     premium pill that reads as a subtle reminder, not a CTA.
///
/// Card background ([WidgetCardShell]) layers a deep accent gradient,
/// a warm gold radial glow, and a barely-visible Islamic geometric
/// pattern (tessellating 8-point stars at ~3 % opacity) — depth
/// without clutter. The shell also subtly adapts its ambience to the
/// day's [WidgetSnapshot.spiritualMode] (Ramadan / Eid / Friday /
/// night), all driven from snapshot fields so this view stays a
/// pure layout function.
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
    // Brand palette — same gold family used elsewhere in the
    // widget set so the two home-screen widgets feel like siblings.
    const Color goldSoft = Color(0xFFF0D89A);
    const Color goldDeep = Color(0xFFC8943A);
    const Color textHero = Color(0xFFFAF5E8);
    const Color textSoft = Color(0xFFCBD8CF);
    const Color textMuted = Color(0xFFA9B7AD);

    // Hero size scales DOWN very slightly when the title runs long,
    // so a 30-character Arabic phrase like "أيام عشر ذي الحجة" never
    // ellipses awkwardly on the second line.
    final double heroSize = s.islamicToday.length > 24 ? 19 : 22;

    return WidgetCardShell(
      accent: s.accent,
      isDark: s.isDark,
      isRtl: s.isRtl,
      size: canvasSize,
      spiritualMode: s.spiritualMode,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Quiet header ────────────────────────────────────
          // Crescent + day name + compact Hijri date in ONE
          // muted line so the hero owns the visual weight.
          Row(
            children: [
              const WidgetCrescent(size: 22),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  '${s.dayName}  ·  ${s.hijriLine}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: appFont(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w400,
                    color: textMuted,
                    letterSpacing: 0.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Hero: today's Islamic occasion ──────────────────
          Text(
            s.islamicToday,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: appFont(
              fontSize: heroSize,
              fontWeight: FontWeight.w800,
              color: textHero,
              height: 1.18,
              letterSpacing: 0.15,
            ),
          ),

          // ── Upcoming + countdown badge ──────────────────────
          if (s.islamicUpcomingName.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    s.islamicUpcomingName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appFont(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: textSoft,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                if (s.islamicUpcomingCountdown.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _CountdownBadge(
                    text: s.islamicUpcomingCountdown,
                    goldSoft: goldSoft,
                    goldDeep: goldDeep,
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Premium "countdown" pill — soft gold gradient + a hairline gold
/// border, calm and reflective. Subtle on purpose so it reads as a
/// gentle reminder rather than a CTA button.
class _CountdownBadge extends StatelessWidget {
  final String text;
  final Color goldSoft;
  final Color goldDeep;

  const _CountdownBadge({
    required this.text,
    required this.goldSoft,
    required this.goldDeep,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            goldSoft.withOpacity(0.22),
            goldDeep.withOpacity(0.12),
          ],
        ),
        border: Border.all(
          color: goldSoft.withOpacity(0.30),
          width: 0.6,
        ),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: appFont(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: goldSoft,
          letterSpacing: 0.45,
        ),
      ),
    );
  }
}
