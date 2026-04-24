/// Pure Dart Hijri ↔ Gregorian conversion — no external package.
class HijriDate {
  final int hYear;
  final int hMonth;
  final int hDay;

  const HijriDate(this.hYear, this.hMonth, this.hDay);

  factory HijriDate.now() => HijriDate.fromGregorian(DateTime.now());

  factory HijriDate.fromGregorian(DateTime date) {
    final jdn = _gregorianToJDN(date.year, date.month, date.day);
    return _jdnToHijri(jdn);
  }

  factory HijriDate.fromYMD(int year, int month, int day) =>
      HijriDate(year, month, day);

  DateTime toGregorian() => _hijriToGregorian(hYear, hMonth, hDay);

  static DateTime hijriToGregorian(int year, int month, int day) =>
      _hijriToGregorian(year, month, day);

  static int daysInMonth(int year, int month) {
    if (month % 2 == 1) return 30;
    if (month == 12) return _isLeapYear(year) ? 30 : 29;
    return 29;
  }

  static bool _isLeapYear(int year) {
    const leapYears = [2, 5, 7, 10, 13, 15, 18, 21, 24, 26, 29];
    return leapYears.contains(year % 30);
  }

  /// Returns weekday of 1st day: 1=Mon..7=Sun (same as DateTime.weekday)
  static int firstWeekdayOfMonth(int year, int month) {
    try {
      final g = _hijriToGregorian(year, month, 1);
      return g.weekday; // 1=Mon..7=Sun
    } catch (_) {
      return 1;
    }
  }

  bool isSameDay(HijriDate other) =>
      hYear == other.hYear && hMonth == other.hMonth && hDay == other.hDay;

  bool isSameMonth(HijriDate other) =>
      hYear == other.hYear && hMonth == other.hMonth;

  HijriDate addMonths(int months) {
    var m = hMonth + months;
    var y = hYear;
    while (m > 12) { m -= 12; y++; }
    while (m < 1)  { m += 12; y--; }
    return HijriDate(y, m, 1);
  }

  static int _gregorianToJDN(int year, int month, int day) {
    final a = (14 - month) ~/ 12;
    final y = year + 4800 - a;
    final m = month + 12 * a - 3;
    return day + (153 * m + 2) ~/ 5 + 365 * y +
        y ~/ 4 - y ~/ 100 + y ~/ 400 - 32045;
  }

  static HijriDate _jdnToHijri(int jdn) {
    final l  = jdn - 1948440 + 10632;
    final n  = (l - 1) ~/ 10631;
    final l2 = l - 10631 * n + 354;
    final j  = ((10985 - l2) ~/ 5316) * ((50 * l2) ~/ 17719) +
               (l2 ~/ 5670) * ((43 * l2) ~/ 15238);
    final l3 = l2 - ((30 - j) ~/ 15) * ((17719 * j) ~/ 50) -
               (j ~/ 16) * ((15238 * j) ~/ 43) + 29;
    final month = (24 * l3) ~/ 709;
    final day   = l3 - (709 * month) ~/ 24;
    final year  = 30 * n + j - 30;
    return HijriDate(year, month, day);
  }

  static DateTime _hijriToGregorian(int year, int month, int day) {
    final jdn = (11 * year + 3) ~/ 30 + 354 * year + 30 * month -
                (month - 1) ~/ 2 + day + 1948440 - 385;
    final l  = jdn + 68569;
    final n  = (4 * l) ~/ 146097;
    final l2 = l - (146097 * n + 3) ~/ 4;
    final i  = (4000 * (l2 + 1)) ~/ 1461001;
    final l3 = l2 - (1461 * i) ~/ 4 + 31;
    final j  = (80 * l3) ~/ 2447;
    final gDay   = l3 - (2447 * j) ~/ 80;
    final l4     = j ~/ 11;
    final gMonth = j + 2 - 12 * l4;
    final gYear  = 100 * (n - 49) + i + l4;
    return DateTime(gYear, gMonth, gDay);
  }
}
