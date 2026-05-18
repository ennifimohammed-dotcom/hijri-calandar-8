package com.hijricalendar.hijri_calendar

/**
 * Pure-Kotlin port of `lib/utils/hijri_utils.dart`. Same Umm al-Qura
 * algorithm, same integer maths — so dates computed natively match
 * the Dart side bit-for-bit and no calendar/timezone drift can ever
 * be introduced.
 *
 * Used by [MiniCalendarWidgetProvider] when the user navigates the
 * Mini Calendar widget BEYOND the JSON payload's pre-baked window
 * (currently +/-24 months around today, the "fast lane"). For any
 * month outside that range the provider asks this kernel for the
 * structural data — month length, first weekday, per-day Gregorian
 * number — and renders a "skeleton" month: real day numbers and
 * real Gregorian secondary dates, but no event dots / ayyam-al-bid
 * / ramadan tint (those require Dart-side state). This is what
 * unlocks the spec's "scroll like Google Calendar" requirement
 * without preloading hundreds of months of event data.
 *
 * Region offset (`hijriDayOffset`) is applied the same way as
 * `lib/utils/hijri_kernel.dart`: canonical Umm al-Qura conversion
 * first, then `+offset` days. The Dart side passes this value
 * through the widget payload (`hijriOffset` field) so the two
 * sides always agree.
 */
object HijriKernel {

    private val LEAP_REMAINDERS = intArrayOf(
        2, 5, 7, 10, 13, 15, 18, 21, 24, 26, 29,
    )

    /** Mirrors `HijriDate.daysInMonth` from hijri_utils.dart. */
    fun daysInMonth(year: Int, month: Int): Int {
        if (month % 2 == 1) return 30
        if (month == 12) return if (isLeapYear(year)) 30 else 29
        return 29
    }

    private fun isLeapYear(year: Int): Boolean =
        (year % 30) in LEAP_REMAINDERS

    /** Hijri (year, month, day) -> Julian Day Number. */
    private fun hijriToJdn(year: Int, month: Int, day: Int): Int =
        (11 * year + 3) / 30 + 354 * year + 30 * month -
            (month - 1) / 2 + day + 1948440 - 385

    /** Hijri date -> Gregorian (year, month, day), with [offsetDays]
     *  applied to the resulting JDN (the same way the Dart kernel
     *  does in `gregFromHijri`). */
    fun hijriToGregorian(
        year: Int,
        month: Int,
        day: Int,
        offsetDays: Int,
    ): GregDate {
        val jdn = hijriToJdn(year, month, day) + offsetDays
        val l = jdn + 68569
        val n = (4 * l) / 146097
        val l2 = l - (146097 * n + 3) / 4
        val i = (4000 * (l2 + 1)) / 1461001
        val l3 = l2 - (1461 * i) / 4 + 31
        val j = (80 * l3) / 2447
        val gDay = l3 - (2447 * j) / 80
        val l4 = j / 11
        val gMonth = j + 2 - 12 * l4
        val gYear = 100 * (n - 49) + i + l4
        return GregDate(gYear, gMonth, gDay)
    }

    /** First weekday of the Hijri month, 1=Mon..7=Sun.
     *
     *  Implemented via JDN mod 7 directly instead of `Calendar` so
     *  there's zero chance of a timezone / locale-week-start bug.
     *  JDN 0 was a Monday, so `(jdn % 7) + 1` gives 1=Mon..7=Sun. */
    fun firstWeekdayOfMonth(
        year: Int,
        month: Int,
        offsetDays: Int,
    ): Int {
        val jdn = hijriToJdn(year, month, 1) + offsetDays
        // jdn is always large+positive, so % 7 stays in 0..6.
        return (jdn % 7) + 1
    }

    /** Hijri month arithmetic with 12-month wrap. Mirrors the Dart
     *  `_MonthlyView.hijriForIndex` pattern. */
    fun addMonths(year: Int, month: Int, delta: Int): Pair<Int, Int> {
        var y = year
        var m = month + delta
        while (m < 1) { m += 12; y -= 1 }
        while (m > 12) { m -= 12; y += 1 }
        return Pair(y, m)
    }

    data class GregDate(val year: Int, val month: Int, val day: Int)
}
