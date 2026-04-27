/// Canonical Hijri-calendar month list — single source of truth.
///
/// All UI, logic and persistence in this app MUST go through
/// [kHijriMonths] (or the helpers below). The order is hard-coded by
/// [HijriMonth.index] (1..12) and never derived from string sorting.
///
///   1. محرم            (Muharram)
///   2. صفر             (Safar)
///   3. ربيع الأول       (Rabi' al-Awwal)
///   4. ربيع الآخر       (Rabi' al-Akhir, also called Rabi' al-Thani)
///   5. جمادى الأولى     (Jumada al-Ula)
///   6. جمادى الآخرة     (Jumada al-Akhira, also called Jumada al-Thani)
///   7. رجب             (Rajab)
///   8. شعبان            (Sha'ban)
///   9. رمضان            (Ramadan)
///  10. شوال             (Shawwal)
///  11. ذو القعدة         (Dhu al-Qi'dah)
///  12. ذو الحجة          (Dhu al-Hijjah)
///
/// Rules:
///   * `monthIndex` is the only legitimate ordering key.
///   * String-comparing month names is FORBIDDEN — Arabic forms sort
///     in a completely different order than the chronological one
///     (e.g. "محرم" sorts after "ذو الحجة" in Unicode), and any UI
///     that did so would silently scramble the calendar.
///   * To localize a name use [hijriMonthName] (or [HijriMonth.name]).
///   * To enumerate the months in chronological order, iterate
///     `kHijriMonths` directly — it is already in index order.

class HijriMonth {
  /// 1..12 — chronological month number, never alphabetical.
  final int index;

  final String ar;
  final String fr;
  final String en;
  final String es;

  const HijriMonth({
    required this.index,
    required this.ar,
    required this.fr,
    required this.en,
    required this.es,
  });

  /// Localized name for the chosen UI locale. Falls back to Arabic.
  String name(String locale) {
    switch (locale) {
      case 'fr':
        return fr;
      case 'en':
        return en;
      case 'es':
        return es;
      case 'ar':
      default:
        return ar;
    }
  }
}

/// Canonical, immutable list. Index 0 is محرم, index 11 is ذو الحجة.
///
/// Do NOT reorder. Do NOT mutate. The runtime check
/// [assertHijriMonthOrder] enforces this on app start.
const List<HijriMonth> kHijriMonths = <HijriMonth>[
  HijriMonth(
    index: 1,
    ar: 'محرم',
    fr: 'Mouharram',
    en: 'Muharram',
    es: 'Muharram',
  ),
  HijriMonth(
    index: 2,
    ar: 'صفر',
    fr: 'Safar',
    en: 'Safar',
    es: 'Safar',
  ),
  HijriMonth(
    index: 3,
    ar: 'ربيع الأول',
    fr: "Rabi' al-Awwal",
    en: "Rabi' al-Awwal",
    es: "Rabi' al-Awwal",
  ),
  HijriMonth(
    index: 4,
    ar: 'ربيع الآخر',
    fr: "Rabi' al-Akhir",
    en: "Rabi' al-Akhir",
    es: "Rabi' al-Ajir",
  ),
  HijriMonth(
    index: 5,
    ar: 'جمادى الأولى',
    fr: 'Joumada al-Oula',
    en: 'Jumada al-Ula',
    es: 'Yumada al-Ula',
  ),
  HijriMonth(
    index: 6,
    ar: 'جمادى الآخرة',
    fr: 'Joumada al-Akhira',
    en: 'Jumada al-Akhira',
    es: 'Yumada al-Ajira',
  ),
  HijriMonth(
    index: 7,
    ar: 'رجب',
    fr: 'Rajab',
    en: 'Rajab',
    es: 'Rayab',
  ),
  HijriMonth(
    index: 8,
    ar: 'شعبان',
    fr: 'Chaabane',
    en: "Sha'ban",
    es: "Sha'ban",
  ),
  HijriMonth(
    index: 9,
    ar: 'رمضان',
    fr: 'Ramadan',
    en: 'Ramadan',
    es: 'Ramadán',
  ),
  HijriMonth(
    index: 10,
    ar: 'شوال',
    fr: 'Chawwal',
    en: 'Shawwal',
    es: 'Shawwal',
  ),
  HijriMonth(
    index: 11,
    ar: 'ذو القعدة',
    fr: "Dhou al-Qi'da",
    en: "Dhu al-Qi'dah",
    es: "Du al-Qa'da",
  ),
  HijriMonth(
    index: 12,
    ar: 'ذو الحجة',
    fr: 'Dhou al-Hijja',
    en: 'Dhu al-Hijjah',
    es: 'Du al-Hiyya',
  ),
];

/// Returns the canonical localized name for [monthIndex] (1..12).
/// Returns an empty string for out-of-range input.
String hijriMonthName(int monthIndex, String locale) {
  if (monthIndex < 1 || monthIndex > 12) return '';
  return kHijriMonths[monthIndex - 1].name(locale);
}

/// Strict numeric comparator. NEVER sort by name.
int compareHijriMonthByIndex(int a, int b) => a.compareTo(b);

/// Compares two Hijri (year, month) tuples chronologically using
/// [HijriMonth.index]. Drop-in safer alternative to anywhere code
/// might be tempted to sort by string.
int compareHijriYearMonth(int aYear, int aMonth, int bYear, int bMonth) {
  if (aYear != bYear) return aYear.compareTo(bYear);
  return aMonth.compareTo(bMonth);
}

/// Defensive runtime invariant. Wired into [AppProvider.init].
class HijriMonthOrderError extends StateError {
  HijriMonthOrderError(super.message);
}

void assertHijriMonthOrder() {
  if (kHijriMonths.length != 12) {
    throw HijriMonthOrderError(
        'kHijriMonths must contain 12 entries, got ${kHijriMonths.length}');
  }
  for (var i = 0; i < 12; i++) {
    final m = kHijriMonths[i];
    if (m.index != i + 1) {
      throw HijriMonthOrderError(
          'kHijriMonths[$i].index = ${m.index}, expected ${i + 1}. '
          'The Hijri month order is a hard invariant — do not reorder.');
    }
  }
}
