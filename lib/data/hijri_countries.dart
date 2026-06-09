/// The canonical list of countries whose OFFICIAL Hijri calendar
/// the app can pull from AlAdhan API (https://aladhan.com/calendar-api).
///
/// Each entry binds an ISO 3166-1 alpha-2 country code (`MA`, `SA`,
/// ...) to:
///   1. The display name in the four app locales.
///   2. The `adjustment` (in days) that the country's official
///      authority uses relative to AlAdhan's default Hijri output.
///      Most countries that follow Umm al-Qura sit at `0`. Morocco
///      and Algeria sit at `+1` because their ministries
///      historically delay the calendar by one day.
///   3. The `authority` — the human-readable name of the religious
///      body whose calendar is being followed. Surfaced in the
///      Settings screen so the user knows EXACTLY whose dates they
///      see ("Vu par la Vorgang du Maroc", "وفق وزارة الأوقاف
///      المغربية", "Per Diyanet Türkiye", ...).
///
/// Why a static list and not a runtime fetch?
///   * The country → authority mapping is stable across years.
///     Saudi Arabia is never going to wake up tomorrow and start
///     following the Egyptian Dar al-Iftaa — the mapping changes
///     on a multi-decade timescale, not a monthly one.
///   * Keeping it static means the country picker works fully
///     offline and the app never has to ask "is the network
///     reachable just so we can populate a dropdown?".
///   * The OFFICIAL daily Hijri date for a chosen country is what
///     gets fetched from AlAdhan; this list only decides which
///     country is selected and how to label its authority.
///
/// To add a country
///   1. Append a `HijriCountry` entry below.
///   2. Use ISO 3166-1 alpha-2 for `code` (uppercase). AlAdhan's
///      API consumes the same codes.
///   3. Localize the `name` map into all four supported locales.
///   4. Localize the `authority` map similarly.
///   5. Set `adjustment` per the country's known historical
///      tendency vs. Umm al-Qura (0 for most, +1 for Maghreb).
///
/// Why exactly these 30?
///   They are the AlAdhan-supported countries with a documented
///   official Hijri authority. Countries with large Muslim
///   populations but no centralised authority (e.g. expatriate
///   contexts in Europe / North America) fall back to the
///   `global` row at the end — Umm al-Qura with no adjustment.
library;

/// A single country with its official Hijri-calendar authority.
class HijriCountry {
  /// ISO 3166-1 alpha-2 code, uppercase. Matches AlAdhan's
  /// country parameter.
  final String code;

  /// Localized country name. Keyed by app locale (`ar`, `fr`,
  /// `en`, `es`). All four keys MUST be present so the picker
  /// can show the name in whichever language the user is using.
  final Map<String, String> name;

  /// Localized name of the religious authority whose calendar
  /// this country follows. Surfaced under "Source" in the
  /// Settings screen and on the calendar header tap.
  final Map<String, String> authority;

  /// Days added to AlAdhan's default Hijri output to match this
  /// country's CIVIL calendar. Most are 0; Maghreb is typically
  /// +1. The user can further tweak this in Settings via the
  /// manual ±3-day adjuster.
  final int adjustment;

  /// Unicode flag emoji — used as the leading glyph in the
  /// country picker. Two regional-indicator letters per country
  /// code (e.g. `🇲🇦` for `MA`).
  final String flag;

  const HijriCountry({
    required this.code,
    required this.name,
    required this.authority,
    required this.adjustment,
    required this.flag,
  });

  /// Convenience: localized country name with a graceful
  /// fallback to English then the ISO code if the locale isn't
  /// covered.
  String localizedName(String locale) =>
      name[locale] ?? name['en'] ?? code;

  /// Convenience: localized authority label with the same
  /// fallback chain as [localizedName].
  String localizedAuthority(String locale) =>
      authority[locale] ?? authority['en'] ?? '';
}

/// The full registry. Iterate this when building the country
/// picker; look up by `code` via [hijriCountryByCode].
///
/// Ordering: Maghreb first (largest user base for this app),
/// then the rest of the Arab world, then non-Arab Muslim-majority
/// states, then a global Umm al-Qura fallback at the bottom.
const List<HijriCountry> kHijriCountries = <HijriCountry>[
  // ── Maghreb ──────────────────────────────────────────────
  HijriCountry(
    code: 'MA',
    flag: '🇲🇦',
    name: {
      'ar': 'المغرب',
      'fr': 'Maroc',
      'en': 'Morocco',
      'es': 'Marruecos',
    },
    authority: {
      'ar': 'وزارة الأوقاف والشؤون الإسلامية',
      'fr': 'Ministère des Habous et des Affaires Islamiques',
      'en': 'Ministry of Endowments and Islamic Affairs',
      'es': 'Ministerio de Habices y Asuntos Islámicos',
    },
    adjustment: 1,
  ),
  HijriCountry(
    code: 'DZ',
    flag: '🇩🇿',
    name: {
      'ar': 'الجزائر',
      'fr': 'Algérie',
      'en': 'Algeria',
      'es': 'Argelia',
    },
    authority: {
      'ar': 'وزارة الشؤون الدينية والأوقاف',
      'fr': 'Ministère des Affaires Religieuses',
      'en': 'Ministry of Religious Affairs',
      'es': 'Ministerio de Asuntos Religiosos',
    },
    adjustment: 1,
  ),
  HijriCountry(
    code: 'TN',
    flag: '🇹🇳',
    name: {
      'ar': 'تونس',
      'fr': 'Tunisie',
      'en': 'Tunisia',
      'es': 'Túnez',
    },
    authority: {
      'ar': 'وزارة الشؤون الدينية',
      'fr': 'Ministère des Affaires Religieuses',
      'en': 'Ministry of Religious Affairs',
      'es': 'Ministerio de Asuntos Religiosos',
    },
    adjustment: 0,
  ),
  HijriCountry(
    code: 'LY',
    flag: '🇱🇾',
    name: {
      'ar': 'ليبيا',
      'fr': 'Libye',
      'en': 'Libya',
      'es': 'Libia',
    },
    authority: {
      'ar': 'دار الإفتاء الليبية',
      'fr': 'Dar al-Ifta libyenne',
      'en': 'Libyan Dar al-Ifta',
      'es': 'Dar al-Ifta libia',
    },
    adjustment: 0,
  ),
  HijriCountry(
    code: 'MR',
    flag: '🇲🇷',
    name: {
      'ar': 'موريتانيا',
      'fr': 'Mauritanie',
      'en': 'Mauritania',
      'es': 'Mauritania',
    },
    authority: {
      'ar': 'وزارة الشؤون الإسلامية',
      'fr': 'Ministère des Affaires Islamiques',
      'en': 'Ministry of Islamic Affairs',
      'es': 'Ministerio de Asuntos Islámicos',
    },
    adjustment: 0,
  ),
  HijriCountry(
    code: 'SN',
    flag: '🇸🇳',
    name: {
      'ar': 'السنغال',
      'fr': 'Sénégal',
      'en': 'Senegal',
      'es': 'Senegal',
    },
    authority: {
      'ar': 'اللجنة الوطنية للتنسيق حول الهلال (CONACOC)',
      'fr': 'Commission Nationale de Concertation sur le Croissant Lunaire',
      'en': 'National Moon-Sighting Coordination Commission (CONACOC)',
      'es': 'Comisión Nacional de Coordinación del Creciente Lunar',
    },
    adjustment: 0,
  ),
  // ── Mashreq / Gulf ───────────────────────────────────────
  HijriCountry(
    code: 'SA',
    flag: '🇸🇦',
    name: {
      'ar': 'السعودية',
      'fr': 'Arabie Saoudite',
      'en': 'Saudi Arabia',
      'es': 'Arabia Saudita',
    },
    authority: {
      'ar': 'المجلس الأعلى للقضاء — تقويم أم القرى',
      'fr': 'Conseil Supérieur de la Justice — Umm al-Qura',
      'en': 'Supreme Judicial Council — Umm al-Qura',
      'es': 'Consejo Superior de Justicia — Umm al-Qura',
    },
    adjustment: 0,
  ),
  HijriCountry(
    code: 'AE',
    flag: '🇦🇪',
    name: {
      'ar': 'الإمارات',
      'fr': 'Émirats Arabes Unis',
      'en': 'United Arab Emirates',
      'es': 'Emiratos Árabes Unidos',
    },
    authority: {
      'ar': 'الهيئة العامة للشؤون الإسلامية والأوقاف',
      'fr': 'Autorité Générale des Affaires Islamiques',
      'en': 'General Authority of Islamic Affairs',
      'es': 'Autoridad General de Asuntos Islámicos',
    },
    adjustment: 0,
  ),
  HijriCountry(
    code: 'KW',
    flag: '🇰🇼',
    name: {
      'ar': 'الكويت',
      'fr': 'Koweït',
      'en': 'Kuwait',
      'es': 'Kuwait',
    },
    authority: {
      'ar': 'وزارة الأوقاف والشؤون الإسلامية',
      'fr': 'Ministère des Awqaf et Affaires Islamiques',
      'en': 'Ministry of Awqaf and Islamic Affairs',
      'es': 'Ministerio de Awqaf y Asuntos Islámicos',
    },
    adjustment: 0,
  ),
  HijriCountry(
    code: 'QA',
    flag: '🇶🇦',
    name: {
      'ar': 'قطر',
      'fr': 'Qatar',
      'en': 'Qatar',
      'es': 'Catar',
    },
    authority: {
      'ar': 'وزارة الأوقاف والشؤون الإسلامية',
      'fr': 'Ministère des Awqaf',
      'en': 'Ministry of Awqaf',
      'es': 'Ministerio de Awqaf',
    },
    adjustment: 0,
  ),
  HijriCountry(
    code: 'BH',
    flag: '🇧🇭',
    name: {
      'ar': 'البحرين',
      'fr': 'Bahreïn',
      'en': 'Bahrain',
      'es': 'Baréin',
    },
    authority: {
      'ar': 'إدارة الأوقاف السنية والجعفرية',
      'fr': 'Administration des Awqaf',
      'en': 'Sunni and Jaafari Awqaf Administration',
      'es': 'Administración de Awqaf',
    },
    adjustment: 0,
  ),
  HijriCountry(
    code: 'OM',
    flag: '🇴🇲',
    name: {
      'ar': 'عُمان',
      'fr': 'Oman',
      'en': 'Oman',
      'es': 'Omán',
    },
    authority: {
      'ar': 'وزارة الأوقاف والشؤون الدينية',
      'fr': 'Ministère des Awqaf',
      'en': 'Ministry of Awqaf and Religious Affairs',
      'es': 'Ministerio de Awqaf',
    },
    adjustment: 0,
  ),
  HijriCountry(
    code: 'YE',
    flag: '🇾🇪',
    name: {
      'ar': 'اليمن',
      'fr': 'Yémen',
      'en': 'Yemen',
      'es': 'Yemen',
    },
    authority: {
      'ar': 'وزارة الأوقاف والإرشاد',
      'fr': 'Ministère des Awqaf et de la Guidance',
      'en': 'Ministry of Awqaf and Guidance',
      'es': 'Ministerio de Awqaf',
    },
    adjustment: 0,
  ),
  HijriCountry(
    code: 'EG',
    flag: '🇪🇬',
    name: {
      'ar': 'مصر',
      'fr': 'Égypte',
      'en': 'Egypt',
      'es': 'Egipto',
    },
    authority: {
      'ar': 'دار الإفتاء المصرية',
      'fr': 'Dar al-Ifta égyptienne',
      'en': 'Egyptian Dar al-Ifta',
      'es': 'Dar al-Ifta egipcia',
    },
    adjustment: 0,
  ),
  HijriCountry(
    code: 'SD',
    flag: '🇸🇩',
    name: {
      'ar': 'السودان',
      'fr': 'Soudan',
      'en': 'Sudan',
      'es': 'Sudán',
    },
    authority: {
      'ar': 'مجمع الفقه الإسلامي',
      'fr': 'Conseil de Jurisprudence Islamique',
      'en': 'Islamic Jurisprudence Council',
      'es': 'Consejo de Jurisprudencia Islámica',
    },
    adjustment: 0,
  ),
  HijriCountry(
    code: 'JO',
    flag: '🇯🇴',
    name: {
      'ar': 'الأردن',
      'fr': 'Jordanie',
      'en': 'Jordan',
      'es': 'Jordania',
    },
    authority: {
      'ar': 'دائرة الإفتاء العام',
      'fr': 'Département Général des Fatwas',
      'en': 'General Iftaa Department',
      'es': 'Departamento General de Iftaa',
    },
    adjustment: 0,
  ),
  HijriCountry(
    code: 'PS',
    flag: '🇵🇸',
    name: {
      'ar': 'فلسطين',
      'fr': 'Palestine',
      'en': 'Palestine',
      'es': 'Palestina',
    },
    authority: {
      'ar': 'دار الإفتاء الفلسطينية',
      'fr': 'Dar al-Ifta palestinienne',
      'en': 'Palestinian Dar al-Ifta',
      'es': 'Dar al-Ifta palestina',
    },
    adjustment: 0,
  ),
  HijriCountry(
    code: 'LB',
    flag: '🇱🇧',
    name: {
      'ar': 'لبنان',
      'fr': 'Liban',
      'en': 'Lebanon',
      'es': 'Líbano',
    },
    authority: {
      'ar': 'دار الفتوى',
      'fr': 'Dar al-Fatwa',
      'en': 'Dar al-Fatwa',
      'es': 'Dar al-Fatwa',
    },
    adjustment: 0,
  ),
  HijriCountry(
    code: 'SY',
    flag: '🇸🇾',
    name: {
      'ar': 'سوريا',
      'fr': 'Syrie',
      'en': 'Syria',
      'es': 'Siria',
    },
    authority: {
      'ar': 'وزارة الأوقاف',
      'fr': 'Ministère des Awqaf',
      'en': 'Ministry of Awqaf',
      'es': 'Ministerio de Awqaf',
    },
    adjustment: 0,
  ),
  HijriCountry(
    code: 'IQ',
    flag: '🇮🇶',
    name: {
      'ar': 'العراق',
      'fr': 'Irak',
      'en': 'Iraq',
      'es': 'Irak',
    },
    authority: {
      'ar': 'ديوان الوقف السني',
      'fr': 'Diwan du Waqf Sunnite',
      'en': 'Sunni Endowment Office',
      'es': 'Oficina del Waqf Sunita',
    },
    adjustment: 0,
  ),
  // ── Non-Arab Muslim-majority countries ───────────────────
  HijriCountry(
    code: 'TR',
    flag: '🇹🇷',
    name: {
      'ar': 'تركيا',
      'fr': 'Turquie',
      'en': 'Türkiye',
      'es': 'Turquía',
    },
    authority: {
      'ar': 'رئاسة الشؤون الدينية',
      'fr': 'Diyanet İşleri Başkanlığı',
      'en': 'Presidency of Religious Affairs (Diyanet)',
      'es': 'Presidencia de Asuntos Religiosos',
    },
    adjustment: 0,
  ),
  HijriCountry(
    code: 'ID',
    flag: '🇮🇩',
    name: {
      'ar': 'إندونيسيا',
      'fr': 'Indonésie',
      'en': 'Indonesia',
      'es': 'Indonesia',
    },
    authority: {
      'ar': 'وزارة الشؤون الدينية',
      'fr': 'Kementerian Agama',
      'en': 'Ministry of Religious Affairs (Kemenag)',
      'es': 'Ministerio de Asuntos Religiosos',
    },
    adjustment: 0,
  ),
  HijriCountry(
    code: 'MY',
    flag: '🇲🇾',
    name: {
      'ar': 'ماليزيا',
      'fr': 'Malaisie',
      'en': 'Malaysia',
      'es': 'Malasia',
    },
    authority: {
      'ar': 'دائرة التنمية الإسلامية الماليزية',
      'fr': 'JAKIM (Affaires Islamiques)',
      'en': 'Department of Islamic Development (JAKIM)',
      'es': 'JAKIM (Asuntos Islámicos)',
    },
    adjustment: 0,
  ),
  HijriCountry(
    code: 'BN',
    flag: '🇧🇳',
    name: {
      'ar': 'بروناي',
      'fr': 'Brunei',
      'en': 'Brunei',
      'es': 'Brunéi',
    },
    authority: {
      'ar': 'وزارة الشؤون الدينية',
      'fr': 'Ministère des Affaires Religieuses',
      'en': 'Ministry of Religious Affairs',
      'es': 'Ministerio de Asuntos Religiosos',
    },
    adjustment: 0,
  ),
  HijriCountry(
    code: 'SG',
    flag: '🇸🇬',
    name: {
      'ar': 'سنغافورة',
      'fr': 'Singapour',
      'en': 'Singapore',
      'es': 'Singapur',
    },
    authority: {
      'ar': 'مجلس علماء سنغافورة',
      'fr': 'MUIS (Conseil Islamique de Singapour)',
      'en': 'Islamic Religious Council (MUIS)',
      'es': 'Consejo Religioso Islámico (MUIS)',
    },
    adjustment: 0,
  ),
  HijriCountry(
    code: 'PK',
    flag: '🇵🇰',
    name: {
      'ar': 'باكستان',
      'fr': 'Pakistan',
      'en': 'Pakistan',
      'es': 'Pakistán',
    },
    authority: {
      'ar': 'لجنة رؤية الهلال المركزية',
      'fr': 'Comité Central de la Rouet-e-Hilal',
      'en': 'Central Ruet-e-Hilal Committee',
      'es': 'Comité Central Ruet-e-Hilal',
    },
    adjustment: 0,
  ),
  HijriCountry(
    code: 'BD',
    flag: '🇧🇩',
    name: {
      'ar': 'بنغلاديش',
      'fr': 'Bangladesh',
      'en': 'Bangladesh',
      'es': 'Bangladés',
    },
    authority: {
      'ar': 'اللجنة الوطنية لرؤية الهلال',
      'fr': 'Comité National d\'Observation du Croissant',
      'en': 'National Moon Sighting Committee',
      'es': 'Comité Nacional de Observación de la Luna',
    },
    adjustment: 0,
  ),
  HijriCountry(
    code: 'IN',
    flag: '🇮🇳',
    name: {
      'ar': 'الهند',
      'fr': 'Inde',
      'en': 'India',
      'es': 'India',
    },
    authority: {
      'ar': 'لجنة رؤية الهلال الهندية',
      'fr': 'Comité Indien d\'Observation du Croissant',
      'en': 'Indian Moon Sighting Committee',
      'es': 'Comité Indio de Observación de la Luna',
    },
    adjustment: 0,
  ),
  HijriCountry(
    code: 'AF',
    flag: '🇦🇫',
    name: {
      'ar': 'أفغانستان',
      'fr': 'Afghanistan',
      'en': 'Afghanistan',
      'es': 'Afganistán',
    },
    authority: {
      'ar': 'وزارة الحج والأوقاف',
      'fr': 'Ministère du Hajj et des Awqaf',
      'en': 'Ministry of Hajj and Awqaf',
      'es': 'Ministerio del Hajj y Awqaf',
    },
    adjustment: 0,
  ),
  // ── Universal fallback ───────────────────────────────────
  HijriCountry(
    code: 'XX',
    flag: '🌐',
    name: {
      'ar': 'عام (أم القرى)',
      'fr': 'Global (Umm al-Qura)',
      'en': 'Global (Umm al-Qura)',
      'es': 'Global (Umm al-Qura)',
    },
    authority: {
      'ar': 'تقويم أم القرى الافتراضي',
      'fr': 'Calendrier Umm al-Qura par défaut',
      'en': 'Default Umm al-Qura calendar',
      'es': 'Calendario Umm al-Qura predeterminado',
    },
    adjustment: 0,
  ),
];

/// O(1) lookup by ISO country code. Falls back to the `XX`
/// (global Umm al-Qura) entry if the code isn't supported —
/// this lets the country detector pass any ISO code through
/// without the caller needing a separate null-check.
HijriCountry hijriCountryByCode(String code) {
  final upper = code.toUpperCase();
  for (final c in kHijriCountries) {
    if (c.code == upper) return c;
  }
  return kHijriCountries.last; // XX — global fallback.
}

/// Quick membership check — used by the country detector to
/// decide whether to keep the detected ISO code or fall back to
/// the global entry. Cheaper than building the full
/// [HijriCountry] object via [hijriCountryByCode].
bool isHijriCountrySupported(String code) {
  final upper = code.toUpperCase();
  for (final c in kHijriCountries) {
    if (c.code == upper) return true;
  }
  return false;
}
