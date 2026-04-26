/// Project-wide text formatting helpers.
///
/// Hard requirements (per product spec):
///   * Numbers MUST always render as Western digits (0-9), in every
///     locale, including Arabic. Arabic-Indic digits (٠-٩) are
///     forbidden in user-facing output.
///   * Gregorian month names follow the chosen UI locale.
class TextFormat {
  static const List<String> _arabicIndicDigits = [
    '٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩',
  ];

  /// Replaces any Arabic-Indic digits in [input] with their Western
  /// equivalents. Other characters are kept as-is.
  static String toWesternDigits(String input) {
    var s = input;
    for (var i = 0; i < _arabicIndicDigits.length; i++) {
      s = s.replaceAll(_arabicIndicDigits[i], i.toString());
    }
    return s;
  }

  // ── Gregorian short month names per locale ──────────────────
  static const List<String> _gregMonthsAr = [
    '', 'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];
  static const List<String> _gregMonthsFr = [
    '', 'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
  ];
  static const List<String> _gregMonthsEn = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const List<String> _gregMonthsEs = [
    '', 'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sept', 'oct', 'nov', 'dic',
  ];

  static String gregorianMonthShort(int month, String locale) {
    if (month < 1 || month > 12) return '';
    switch (locale) {
      case 'fr': return _gregMonthsFr[month];
      case 'es': return _gregMonthsEs[month];
      case 'en': return _gregMonthsEn[month];
      default:   return _gregMonthsAr[month];
    }
  }

  /// "15 Jan 2026" / "15 يناير 2026" / "15 janv. 2026" / "15 ene 2026".
  /// All digits are Western.
  static String formatGregorianFull(DateTime d, String locale) {
    final m = gregorianMonthShort(d.month, locale);
    return '${d.day} $m ${d.year}';
  }

  /// "Jan 2026" — short month + year. All digits Western.
  static String formatGregorianMonthYear(DateTime d, String locale) {
    final m = gregorianMonthShort(d.month, locale);
    return '$m ${d.year}';
  }

  /// "15/01/2026" — purely numeric. All digits Western.
  static String formatGregorianNumeric(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  /// "15 Jan 2026 · 09:30" / "15 Jan 2026" depending on [allDay].
  /// All digits Western.
  static String formatEventDateTime(
    DateTime d,
    String locale, {
    required bool allDay,
  }) {
    final base = formatGregorianFull(d, locale);
    if (allDay) return base;
    String two(int n) => n.toString().padLeft(2, '0');
    return '$base · ${two(d.hour)}:${two(d.minute)}';
  }
}
