import 'package:flutter/material.dart';
import '../theme.dart';

class IslamicEventConfig {
  final String id;
  final Map<String, String> names;
  final Map<String, String> description;
  final Map<String, String> virtue;
  final int day;
  final int month;   // 0 = every month, -1 = every week
  final bool isMonthly;
  final bool isWeekly;
  final bool isDaily;
  final Color color;
  final String emoji;
  final bool defaultEnabled;
  final int? weekday; // 1=Mon..7=Sun, for weekly events

  const IslamicEventConfig({
    required this.id,
    required this.names,
    required this.description,
    required this.virtue,
    required this.day,
    required this.month,
    this.isMonthly = false,
    this.isWeekly = false,
    this.isDaily = false,
    required this.color,
    required this.emoji,
    this.defaultEnabled = true,
    this.weekday,
  });

  String name(String locale) => names[locale] ?? names['ar'] ?? '';
  String desc(String locale) => description[locale] ?? description['ar'] ?? '';
  String virt(String locale) => virtue[locale] ?? virtue['ar'] ?? '';
}

class IslamicEventsData {
  static List<IslamicEventConfig> get events => [

    // ── DAILY ─────────────────────────────────────────────
    IslamicEventConfig(
      id: 'adhkar_sabah',
      names: {
        'ar': 'أذكار الصباح',
        'fr': 'Dhikr du matin',
        'en': 'Morning Dhikr',
        'es': 'Dhikr de la mañana',
      },
      description: {
        'ar': 'أذكار الصباح بعد صلاة الفجر',
        'fr': 'Invocations du matin après Fajr',
        'en': 'Morning remembrance after Fajr prayer',
        'es': 'Remembranza matutina tras Fajr',
      },
      virtue: {
        'ar': '«من قال حين يصبح: لا إله إلا الله وحده...» — صحيح مسلم',
        'fr': '«Celui qui dit le matin: Lâ ilâha illallâh...» — Muslim',
        'en': '«Whoever says in the morning: Lâ ilâha illallâh...» — Muslim',
        'es': '«Quien diga por la mañana: Lâ ilâha illallâh...» — Muslim',
      },
      day: 0, month: 0, isDaily: true,
      color: AppColors.gold, emoji: '🌅',
    ),

    IslamicEventConfig(
      id: 'adhkar_masaa',
      names: {
        'ar': 'أذكار المساء',
        'fr': 'Dhikr du soir',
        'en': 'Evening Dhikr',
        'es': 'Dhikr de la tarde',
      },
      description: {
        'ar': 'أذكار المساء بعد صلاة العصر',
        'fr': 'Invocations du soir après Asr',
        'en': 'Evening remembrance after Asr prayer',
        'es': 'Remembranza vespertina tras Asr',
      },
      virtue: {
        'ar': '«من قال حين يمسي: أعوذ بكلمات الله التامات...» — صحيح',
        'fr': '«Celui qui dit le soir: A\'outhu bikalimâtillâh...» — Sahîh',
        'en': '«Whoever says in the evening: A\'outhu bikalimâtillâh...» — Sahîh',
        'es': '«Quien diga por la tarde: A\'outhu bikalimâtillâh...» — Sahîh',
      },
      day: 0, month: 0, isDaily: true,
      color: AppColors.gold, emoji: '🌆',
    ),

    IslamicEventConfig(
      id: 'adhkar_nawm',
      names: {
        'ar': 'أذكار النوم',
        'fr': 'Dhikr avant le sommeil',
        'en': 'Sleep Dhikr',
        'es': 'Dhikr antes de dormir',
      },
      description: {
        'ar': 'أذكار النوم بعد صلاة العشاء بساعة',
        'fr': 'Invocations avant le sommeil, 1h après Isha',
        'en': 'Bedtime remembrance, 1 hour after Isha',
        'es': 'Remembranza nocturna, 1h después de Isha',
      },
      virtue: {
        'ar': '«إذا أخذت مضجعك فاقرأ آية الكرسي» — البخاري',
        'fr': '«Quand tu vas te coucher, lis Aayat al-Kursiy» — Bukhâri',
        'en': '«When you go to bed, recite Ayat al-Kursi» — Bukhâri',
        'es': '«Cuando te acuestes, recita Ayat al-Kursi» — Bujari',
      },
      day: 0, month: 0, isDaily: true,
      color: AppColors.navy, emoji: '🌙',
    ),

    // ── MONTHLY ───────────────────────────────────────────
    IslamicEventConfig(
      id: 'hijama',
      names: {
        'ar': 'الحجامة',
        'fr': 'Hijama (Cupping)',
        'en': 'Hijama (Cupping)',
        'es': 'Hijama (Ventosas)',
      },
      description: {
        'ar': 'يوم الحجامة: 17، 19، 21 من كل شهر هجري',
        'fr': 'Jours de hijama : 17, 19, 21 de chaque mois',
        'en': 'Hijama days: 17, 19, 21 of each Hijri month',
        'es': 'Días de hijama: 17, 19, 21 de cada mes',
      },
      virtue: {
        'ar': '«الشفاء في ثلاثة: شرطة محجم...» — صحيح البخاري',
        'fr': '«La guérison est dans trois choses: l\'incision...» — Bukhâri',
        'en': '«Healing is in three: a cupping incision...» — Bukhâri',
        'es': '«La cura está en tres cosas: una incisión...» — Bujari',
      },
      day: 17, month: 0, isMonthly: true,
      color: AppColors.red, emoji: '🩸', defaultEnabled: false,
    ),

    IslamicEventConfig(
      id: 'ayyam_albid',
      names: {
        'ar': 'الأيام البيض',
        'fr': 'Ayyam Al-Bid',
        'en': 'White Days (13-15)',
        'es': 'Días Blancos (13-15)',
      },
      description: {
        'ar': 'الأيام البيض: 13، 14، 15 من كل شهر — يُستحب صيامها',
        'fr': 'Ayyam Al-Bid: 13, 14, 15 de chaque mois — jeûne recommandé',
        'en': 'White Days: 13, 14, 15 each month — fasting recommended',
        'es': 'Días Blancos: 13, 14, 15 cada mes — ayuno recomendado',
      },
      virtue: {
        'ar': '«صم من الشهر ثلاثة أيام: ثلاث عشرة وأربع عشرة وخمس عشرة» — النسائي',
        'fr': '«Jeûne trois jours du mois: le 13, 14 et 15» — Nasâî',
        'en': '«Fast three days of the month: the 13th, 14th and 15th» — Nasâî',
        'es': '«Ayuna tres días del mes: el 13, 14 y 15» — Nasai',
      },
      day: 13, month: 0, isMonthly: true,
      color: AppColors.gold, emoji: '🌕',
    ),

    // ── ANNUAL ────────────────────────────────────────────
    IslamicEventConfig(
      id: 'ashura',
      names: {
        'ar': 'يوم عاشوراء',
        'fr': 'Achoura',
        'en': 'Ashura',
        'es': 'Ashura',
      },
      description: {
        'ar': 'اليوم العاشر من محرم — يوم نجّى الله فيه موسى عليه السلام',
        'fr': '10 Mouharram — jour où Allah a sauvé Moïse (paix sur lui)',
        'en': '10 Muharram — day Allah saved Moses (peace be upon him)',
        'es': '10 Muharram — día en que Alá salvó a Moisés (paz sobre él)',
      },
      virtue: {
        'ar': '«صيام يوم عاشوراء يكفّر السنة الماضية» — صحيح مسلم',
        'fr': '«Le jeûne d\'Achoura expie les péchés de l\'année passée» — Muslim',
        'en': '«Fasting Ashura expiates the sins of the previous year» — Muslim',
        'es': '«El ayuno de Ashura expía los pecados del año anterior» — Muslim',
      },
      day: 10, month: 1, isMonthly: false,
      color: AppColors.blue, emoji: '🕯',
    ),

    IslamicEventConfig(
      id: 'ramadan_start',
      names: {
        'ar': 'بداية رمضان',
        'fr': '1er Ramadan',
        'en': '1st of Ramadan',
        'es': '1 de Ramadán',
      },
      description: {
        'ar': 'أول أيام شهر رمضان المبارك — شهر الصيام والقرآن',
        'fr': 'Premier jour du Ramadan béni — mois du jeûne et du Coran',
        'en': 'First day of blessed Ramadan — month of fasting and Quran',
        'es': 'Primer día del Ramadán bendito — mes de ayuno y Corán',
      },
      virtue: {
        'ar': '«من صام رمضان إيماناً واحتساباً غفر له ما تقدم من ذنبه» — متفق عليه',
        'fr': '«Celui qui jeûne le Ramadan par foi... ses péchés passés seront pardonnés» — Muttafaq',
        'en': '«Whoever fasts Ramadan out of faith... his past sins are forgiven» — Agreed upon',
        'es': '«Quien ayune el Ramadán con fe... se le perdonan sus pecados pasados» — Acordado',
      },
      day: 1, month: 9, isMonthly: false,
      color: AppColors.green, emoji: '🌙',
    ),

    IslamicEventConfig(
      id: 'eid_alfitr',
      names: {
        'ar': 'عيد الفطر',
        'fr': 'Aïd al-Fitr',
        'en': 'Eid al-Fitr',
        'es': 'Eid al-Fitr',
      },
      description: {
        'ar': 'عيد الفطر المبارك — أول شوال — يوم الفرحة والعيدية',
        'fr': 'Aïd al-Fitr — 1er Chawwal — jour de célébration',
        'en': 'Eid al-Fitr — 1 Shawwal — day of joy and celebration',
        'es': 'Eid al-Fitr — 1 Shawwal — día de alegría y celebración',
      },
      virtue: {
        'ar': '«للصائم فرحتان: فرحة عند فطره وفرحة عند لقاء ربه» — متفق عليه',
        'fr': '«Le jeûneur aura deux joies: l\'iftar et la rencontre avec son Seigneur» — Muttafaq',
        'en': '«The fasting person has two joys: breaking fast and meeting his Lord» — Agreed upon',
        'es': '«El ayunante tendrá dos alegrías: el iftar y el encuentro con su Señor» — Acordado',
      },
      day: 1, month: 10, isMonthly: false,
      color: AppColors.green, emoji: '🎉',
    ),

    IslamicEventConfig(
      id: 'dhulhijja_start',
      names: {
        'ar': 'أول أيام عشر ذي الحجة',
        'fr': 'Début des 10 jours de Dhou Al-Hijja',
        'en': 'Start of 10 Days of Dhul Hijjah',
        'es': 'Inicio de los 10 días de Dhu al-Hijjah',
      },
      description: {
        'ar': 'أفضل أيام الدنيا — العشر الأوائل من ذي الحجة',
        'fr': 'Les meilleurs jours de ce monde — 10 premiers jours de Dhou Al-Hijja',
        'en': 'The best days on earth — first 10 days of Dhul Hijjah',
        'es': 'Los mejores días en la tierra — primeros 10 días de Dhu al-Hijjah',
      },
      virtue: {
        'ar': '«ما من أيام العمل الصالح فيها أحب إلى الله من هذه الأيام العشر» — البخاري',
        'fr': '«Il n\'y a pas de jours où les bonnes œuvres sont plus aimées d\'Allah» — Bukhâri',
        'en': '«There are no days when good deeds are more beloved to Allah» — Bukhâri',
        'es': '«No hay días en los que las buenas obras sean más amadas por Alá» — Bujari',
      },
      day: 1, month: 12, isMonthly: false,
      color: AppColors.gold, emoji: '📅',
    ),

    IslamicEventConfig(
      id: 'arafat',
      names: {
        'ar': 'يوم عرفة',
        'fr': "Jour d'Arafat",
        'en': 'Day of Arafat',
        'es': 'Día de Arafat',
      },
      description: {
        'ar': 'يوم عرفة — التاسع من ذي الحجة — أفضل أيام السنة',
        'fr': 'Jour d\'Arafat — 9 Dhou Al-Hijja — meilleur jour de l\'année',
        'en': 'Day of Arafat — 9 Dhul Hijjah — best day of the year',
        'es': 'Día de Arafat — 9 Dhu al-Hijjah — mejor día del año',
      },
      virtue: {
        'ar': '«صيام يوم عرفة يكفّر سنتين: الماضية والقابلة» — صحيح مسلم',
        'fr': '«Le jeûne d\'Arafat expie deux ans: l\'année passée et la suivante» — Muslim',
        'en': '«Fasting Arafat expiates two years: past and coming» — Muslim',
        'es': '«El ayuno de Arafat expía dos años: el pasado y el siguiente» — Muslim',
      },
      day: 9, month: 12, isMonthly: false,
      color: AppColors.gold, emoji: '🏔',
    ),

    IslamicEventConfig(
      id: 'eid_aladha',
      names: {
        'ar': 'عيد الأضحى',
        'fr': 'Aïd al-Adha',
        'en': 'Eid al-Adha',
        'es': 'Eid al-Adha',
      },
      description: {
        'ar': 'عيد الأضحى المبارك — العاشر من ذي الحجة — يوم النحر',
        'fr': 'Aïd al-Adha — 10 Dhou Al-Hijja — jour du sacrifice',
        'en': 'Eid al-Adha — 10 Dhul Hijjah — day of sacrifice',
        'es': 'Eid al-Adha — 10 Dhu al-Hijjah — día del sacrificio',
      },
      virtue: {
        'ar': '«ما عمل آدمي من عمل يوم النحر أحب إلى الله من إهراق الدم» — الترمذي',
        'fr': '«Nulle œuvre le jour du sacrifice n\'est plus aimée d\'Allah que le sang versé» — Tirmidhi',
        'en': '«No deed on the day of sacrifice is more beloved to Allah than shedding blood» — Tirmidhi',
        'es': '«Ninguna obra el día del sacrificio es más amada por Alá que derramar sangre» — Tirmidhi',
      },
      day: 10, month: 12, isMonthly: false,
      color: AppColors.green, emoji: '🎊',
    ),

    // ── WEEKLY ────────────────────────────────────────────
    IslamicEventConfig(
      id: 'jumuah',
      names: {
        'ar': 'يوم الجمعة',
        'fr': 'Vendredi — Joumou\'a',
        'en': 'Friday — Jumu\'ah',
        'es': 'Viernes — Jumu\'ah',
      },
      description: {
        'ar': 'يوم الجمعة — سيد الأيام — تُستحب قراءة سورة الكهف',
        'fr': 'Le vendredi — maître des jours — lire Sourate Al-Kahf recommandé',
        'en': 'Friday — master of days — reciting Surah Al-Kahf recommended',
        'es': 'Viernes — señor de los días — recitar Surah Al-Kahf recomendado',
      },
      virtue: {
        'ar': '«خير يوم طلعت عليه الشمس يوم الجمعة» — صحيح مسلم',
        'fr': '«Le meilleur jour où le soleil s\'est levé est le vendredi» — Muslim',
        'en': '«The best day the sun rises on is Friday» — Muslim',
        'es': '«El mejor día en que sale el sol es el viernes» — Muslim',
      },
      day: 0, month: 0, isWeekly: true, weekday: 5,
      color: AppColors.green, emoji: '🕌',
    ),

    IslamicEventConfig(
      id: 'sawm_ithnayn_khamis',
      names: {
        'ar': 'صيام الاثنين والخميس',
        'fr': 'Jeûne lundi et jeudi',
        'en': 'Fasting Monday & Thursday',
        'es': 'Ayuno lunes y jueves',
      },
      description: {
        'ar': 'يُستحب الصيام كل اثنين وخميس اقتداءً بالنبي ﷺ',
        'fr': 'Jeûne recommandé chaque lundi et jeudi, suivant le Prophète ﷺ',
        'en': 'Recommended fasting every Monday and Thursday following the Prophet ﷺ',
        'es': 'Ayuno recomendado cada lunes y jueves siguiendo al Profeta ﷺ',
      },
      virtue: {
        'ar': '«تُعرض الأعمال يوم الاثنين والخميس فأحب أن يُعرض عملي وأنا صائم» — الترمذي',
        'fr': '«Les œuvres sont présentées le lundi et jeudi, j\'aime que mes œuvres soient présentées en jeûnant» — Tirmidhi',
        'en': '«Deeds are presented on Monday and Thursday and I like mine to be presented while fasting» — Tirmidhi',
        'es': '«Las obras se presentan el lunes y jueves, me gusta que las mías se presenten ayunando» — Tirmidhi',
      },
      day: 0, month: 0, isWeekly: true, weekday: 1,
      color: AppColors.blue, emoji: '🤲', defaultEnabled: false,
    ),
  ];
}
