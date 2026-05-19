import 'package:flutter/material.dart';

import '../theme.dart';
import 'widget_common.dart';
import 'widget_snapshot.dart';

/// The premium "Islamic Day" home-screen widget — a calm, glanceable
/// spiritual companion sized for a 4 x 2 launcher footprint.
///
/// Layout
/// ======
/// Top half — the FOCAL POINT:
///   * a hand-drawn gold crescent;
///   * today's Islamic occasion title rendered in large bold type
///     (the eye lands here first);
///   * a quiet sub-line with the weekday + Hijri date.
///
/// A hair-thin gold divider separates the focal point from the
/// "what's next" half.
///
/// Bottom half — the next THREE upcoming Islamic occasions, one per
/// row. Each row carries:
///   * a fixed-size emoji box (consistent visual weight across all
///     three rows, with proper start-side padding so the glyph can
///     never touch the widget's right edge in RTL);
///   * the localised event title;
///   * a soft gold countdown pill ("غدًا" / "بعد 3 يومًا" / …).
///
/// All four text levels (hero / sub-line / event title / countdown)
/// have distinct sizes and weights so the hierarchy reads at a
/// glance, but the palette stays inside the brand's royal-green +
/// soft-gold range so the widget feels spiritual rather than busy.
///
/// Same self-contained constraints as the other widget views — it
/// is rendered to a PNG OUTSIDE the running app's tree. See
/// [WidgetCardShell]. All display strings are pre-resolved on the
/// app side in [WidgetSnapshot]; this view only lays them out.
class IslamicDayWidgetView extends StatelessWidget {
  final WidgetSnapshot snapshot;

  /// Logical canvas the parent renders this at. 2:1 ratio matches
  /// the new 4 x 2 launcher footprint exactly — Android scales the
  /// PNG to fit without ever having to centerCrop content away.
  static const Size canvasSize = Size(360, 180);

  const IslamicDayWidgetView({super.key, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final s = snapshot;

    // Brand palette — same gold family used elsewhere in the widget
    // set so the two home-screen widgets feel like siblings.
    const Color goldSoft = Color(0xFFF0D89A);
    const Color goldDeep = Color(0xFFC8943A);
    const Color textHero = Color(0xFFFAF5E8);
    const Color textSoft = Color(0xFFD7E0D9);
    const Color textMuted = Color(0xFFA9B7AD);

    // Hero auto-scales DOWN when the title is unusually long so a
    // phrase like "أيام عشر ذي الحجة" never ellipses the second
    // line away.
    final double heroSize = s.islamicTodayTitle.length > 22 ? 18 : 21;

    return WidgetCardShell(
      accent: s.accent,
      isDark: s.isDark,
      isRtl: s.isRtl,
      size: canvasSize,
      spiritualMode: s.spiritualMode,
      // Slightly tighter vertical padding than the default so all
      // three upcoming rows + the hero can breathe comfortably
      // inside the 4 x 2 footprint.
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Focal point: crescent + (optional hero) + dates ──
          //
          // When today carries an Islamic occasion, the title sits
          // at the top of the column in hero type. When nothing
          // applies today the row stays just crescent + dates (no
          // "Blessed day" placeholder) and the dates themselves
          // become the focal point.
          //
          // The Hijri date deliberately renders SLIGHTLY larger
          // than the events list below (14 sp vs the rows' 12.5
          // sp body text), with the corresponding Gregorian date
          // tucked just underneath in a smaller, muted line.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const WidgetCrescent(size: 26),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (s.islamicTodayTitle.isNotEmpty) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          // Hero emoji — separate box so its visual
                          // weight matches the upcoming rows' emoji
                          // boxes.
                          if (s.islamicTodayEmoji.isNotEmpty) ...[
                            _EmojiBox(
                              emoji: s.islamicTodayEmoji,
                              fontSize: heroSize * 0.85,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              s.islamicTodayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: appFont(
                                fontSize: heroSize,
                                fontWeight: FontWeight.w800,
                                color: textHero,
                                height: 1.05,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
                    // Hijri date — slightly larger than the
                    // events list ("أكبر قليلا من خط الأحداث").
                    Text(
                      s.hijriLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: appFont(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: goldSoft,
                        height: 1.1,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 1),
                    // Corresponding Gregorian date — smaller, muted.
                    Text(
                      s.gregorianPretty,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: appFont(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w400,
                        color: textMuted,
                        height: 1.1,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),

          // ── Hair-thin gold divider between focal point and list ──
          Container(
            height: 0.8,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  goldSoft.withOpacity(0.0),
                  goldSoft.withOpacity(0.22),
                  goldSoft.withOpacity(0.0),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ── Up to THREE upcoming events ───────────────────
          // We don't pad the list with placeholders when fewer
          // than three are enabled — empty rows would feel
          // unfinished. The card just settles into a shorter
          // composition.
          for (int i = 0; i < s.islamicUpcomingList.length && i < 3; i++) ...[
            if (i > 0) const SizedBox(height: 5),
            _UpcomingRow(
              emoji: s.islamicUpcomingList[i].emoji,
              title: s.islamicUpcomingList[i].title,
              countdown: s.islamicUpcomingList[i].countdown,
              textSoft: textSoft,
              goldSoft: goldSoft,
              goldDeep: goldDeep,
            ),
          ],
        ],
      ),
    );
  }
}

/// Fixed-size emoji slot — every emoji on the card renders inside
/// a box the same width / height, with centered alignment, so a
/// short emoji like "✨" and a tall one like "🕌" sit at the same
/// visual position relative to the row's text. The box also gives
/// the emoji a built-in margin away from the widget's start edge
/// so the glyph can't crash against the card border in RTL.
class _EmojiBox extends StatelessWidget {
  final String emoji;
  final double fontSize;

  const _EmojiBox({required this.emoji, required this.fontSize});

  @override
  Widget build(BuildContext context) {
    // Keep the box slightly taller than wide so the emoji has a
    // touch of vertical breathing room without changing the
    // row's overall line height.
    return SizedBox(
      width: fontSize + 6,
      height: fontSize + 4,
      child: Center(
        child: Text(
          emoji,
          // No appFont() here — we want the platform's emoji font
          // to be picked, not the app's Arabic family.
          style: TextStyle(
            fontSize: fontSize,
            height: 1.0,
            // textBaseline declared by the parent Row.
          ),
        ),
      ),
    );
  }
}

/// One row in the "upcoming" list — fixed emoji box on the start
/// side, event title in the middle, gold countdown pill on the
/// end side. Keeps every row visually identical regardless of
/// emoji width or title length.
class _UpcomingRow extends StatelessWidget {
  final String emoji;
  final String title;
  final String countdown;
  final Color textSoft;
  final Color goldSoft;
  final Color goldDeep;

  const _UpcomingRow({
    required this.emoji,
    required this.title,
    required this.countdown,
    required this.textSoft,
    required this.goldSoft,
    required this.goldDeep,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _EmojiBox(emoji: emoji, fontSize: 13.5),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: appFont(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: textSoft,
              letterSpacing: 0.15,
              height: 1.1,
            ),
          ),
        ),
        const SizedBox(width: 6),
        _CountdownBadge(
          text: countdown,
          goldSoft: goldSoft,
          goldDeep: goldDeep,
        ),
      ],
    );
  }
}

/// Premium "countdown" pill — soft gold gradient + a hairline gold
/// border, calm and reflective. Identical visual weight to the
/// pill used in the previous design so a user upgrading mid-week
/// recognises it immediately.
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
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
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: goldSoft,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
