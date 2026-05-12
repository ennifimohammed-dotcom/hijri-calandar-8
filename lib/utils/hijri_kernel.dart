import 'hijri_utils.dart';

/// Phase 2 — Hijri Kernel.
///
/// Single, authoritative entry point for every Gregorian ↔ Hijri
/// conversion in the app. Two pure top-level functions, nothing
/// else. The contract is deliberately minimal so callers can't
/// invent half-correct variants:
///
///   * [hijriFromGreg] — given a Gregorian instant and the user's
///     regional `hijriDayOffset`, returns the Hijri date the user
///     actually perceives in their region.
///
///   * [gregFromHijri] — inverse of the above. Given a Hijri date
///     in the user's regional calendar (the date displayed on the
///     monthly grid, the agenda badge, the converter), returns the
///     Gregorian civil date that pairs with it.
///
/// `offset` semantics
///   `offset = 0`  → Umm al-Qura (default).
///   `offset = +1` → regional calendar runs ONE DAY LATER than
///                    Umm al-Qura (typical for the Maghreb).
///   `offset = -1` → regional calendar runs ONE DAY EARLIER than
///                    Umm al-Qura.
///
/// Why this exists
///   Before Phase 2 the offset was applied (or, more dangerously,
///   forgotten) at ~17 call sites scattered across the provider,
///   the recurrence engine, and four screens. A handful of those
///   sites skipped the offset entirely — that asymmetry was the
///   root cause of the "today section duplicated" / "today section
///   has no events" agenda bugs. Routing every conversion through
///   this kernel makes that family of mistakes impossible by
///   construction.
///
/// Rule of thumb
///   Direct calls to `HijriDate.fromGregorian` / `.hijriToGregorian`
///   / `.toGregorian()` are forbidden anywhere outside this file.
///   If you need a conversion, call one of the two functions below.

/// Converts a Gregorian instant into the regional Hijri date.
///
/// Implementation note: we shift the Gregorian input by `-offset`
/// days BEFORE the raw canonical conversion. That matches the
/// region-aware convention used everywhere else in the app — see
/// [AppProvider.hijriDayOffset] and the long-form comment on
/// [AppProvider._todayForRegion].
HijriDate hijriFromGreg(DateTime g, int offset) {
  final shifted = g.subtract(Duration(days: offset));
  return HijriDate.fromGregorian(shifted);
}

/// Converts a regional Hijri date back into its paired Gregorian
/// civil date. Inverse of [hijriFromGreg].
///
/// Implementation note: canonical Umm-al-Qura conversion first,
/// then shift the result by `+offset` days so that, for the user,
/// `gregFromHijri(hijriFromGreg(g, off), off) == g` for any valid
/// `g` in range.
DateTime gregFromHijri(HijriDate h, int offset) {
  final base = HijriDate.hijriToGregorian(h.hYear, h.hMonth, h.hDay);
  return base.add(Duration(days: offset));
}
