import 'package:flutter/material.dart';
import '../theme.dart';

/// Static description of an Islamic reminder event.
///
/// Repetition rules supported (in priority order):
///   * [isDaily]   → fires every day.
///   * [isWeekly]  → fires on the weekday(s) listed in [weekdays]
///                   (or the legacy single [weekday] field).
///   * [isMonthly] → fires on the Hijri day(s) listed in
///                   [monthlyDays] (or the legacy single [day] field).
///   * yearly       → all of the above false → fires on the
///                   (Hijri [day], Hijri [month]) tuple every year.
///
/// Each event has a default hour/minute that the user can override
/// via [AppProvider.setIslamicEventTime]. The trigger time is the
/// configured hour/minute on the day the rule matches.
class IslamicEventConfig {
  final String id;
  final Map<String, String> names;
  final Map<String, String> description;
  final Map<String, String> virtue;

  /// Single Hijri day (1..30). Used by yearly events and as a
  /// fallback for monthly events with no [monthlyDays].
  final int day;

  /// Single Hijri month (1..12). Used by yearly events. 0 means N/A.
  final int month;

  /// Multi-day list for monthly events (e.g. hijama on 16/18/20).
  final List<int> monthlyDays;

  /// Multi-weekday list for weekly events (e.g. fasting reminder on
  /// Sunday & Wednesday). Uses 1=Mon..7=Sun like [DateTime.weekday].
  final List<int> weekdays;

  final bool isMonthly;
  final bool isWeekly;
  final bool isDaily;
  final Color color;
  final String emoji;
  final bool defaultEnabled;

  /// Legacy single-weekday field. Read only when [weekdays] is empty.
  final int? weekday;

  /// Default trigger time. Overridden per-event via
  /// [AppProvider._islamicEventTimes].
  final int defaultHour;
  final int defaultMinute;

  const IslamicEventConfig({
    required this.id,
    required this.names,
    required this.description,
    required this.virtue,
    required this.day,
    required this.month,
    this.monthlyDays = const <int>[],
    this.weekdays = const <int>[],
    this.isMonthly = false,
    this.isWeekly = false,
    this.isDaily = false,
    required this.color,
    required this.emoji,
    this.defaultEnabled = true,
    this.weekday,
    this.defaultHour = 9,
    this.defaultMinute = 0,
  });

  String name(String locale) => names[locale] ?? names['ar'] ?? '';
  String desc(String locale) => description[locale] ?? description['ar'] ?? '';
  String virt(String locale) => virtue[locale] ?? virtue['ar'] ?? '';

  /// Whether this event fires on the day described by ([hijriDay],
  /// [hijriMonth]) which falls on the Gregorian [greg] date.
  ///
  /// Used both by the calendar/Agenda view (to show the event card)
  /// and by [AppProvider._scheduleIslamicNotifications] when picking
  /// which days in the next 30-day window need reminders.
  bool matchesDay({
    required int hijriDay,
    required int hijriMonth,
    required DateTime greg,
  }) {
    if (isDaily) return true;
    if (isWeekly) {
      final wds = weekdays.isNotEmpty
          ? weekdays
          : (weekday != null ? <int>[weekday!] : const <int>[]);
      return wds.contains(greg.weekday);
    }
    if (isMonthly) {
      final days = monthlyDays.isNotEmpty ? monthlyDays : <int>[day];
      return days.contains(hijriDay);
    }
    // Yearly
    return hijriDay == day && hijriMonth == month;
  }
}

class IslamicEventsData {
  /// 13 Islamic reminder events with the exact repetition rules
  /// specified by the product spec. Some rules are deliberately
  /// shifted from the actual Islamic date so the reminder fires the
  /// day before the observance:
  ///   * Friday reminder on Thursday.
  ///   * Mon/Thu fasting reminder on Sunday + Wednesday.
  ///   * Hijama on 16/18/20 (one day before the classical 17/19/21).
  ///   * Ayyam al-Bid reminder on day 12 (one day before 13).
  ///   * Ashura reminder on 8 Muharram (two days before 10).
  ///   * Ramadan-start reminder on 28 Sha'ban.
  ///   * Eid al-Fitr reminder on 28 Ramadan.
  ///   * Dhul-Hijjah ten days reminder on 28 Dhul-Qa'dah.
  ///   * Arafat reminder on 8 Dhul-Hijjah.
  ///   * Eid al-Adha reminder on 9 Dhul-Hijjah.
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
        'ar':
            'عن أبي هريرة رضي الله عنه قال: قال رسول الله ﷺ: «من قال حين يصبح: لا إله إلا الله وحده لا شريك له، له الملك وله الحمد، وهو على كل شيء قدير، مئة مرة في يوم، كانت له عدل عشر رقاب، وكُتبت له مئة حسنة، ومُحيت عنه مئة سيئة، وكانت له حِرزاً من الشيطان يومه ذلك حتى يُمسي» — متفق عليه.',
        'fr':
            "D'après Abû Hurayra, le Prophète ﷺ a dit: «Celui qui dit le matin: Lâ ilâha illallâh wahdahû lâ sharîka lah, lahu-l-mulk wa lahu-l-hamd, wa huwa ‘alâ kulli shay’in qadîr, cent fois dans la journée, en obtient l'équivalent de l'affranchissement de dix esclaves, cent bonnes actions lui sont inscrites, cent mauvaises lui sont effacées, et il est protégé contre Satan jusqu'au soir.» — Muttafaq ‘alayh.",
        'en':
            'On the authority of Abû Hurayrah, the Prophet ﷺ said: «Whoever says in the morning a hundred times: Lâ ilâha illallâh, alone with no partner, His is the dominion and the praise, He is over all things able — earns the reward of freeing ten slaves, has a hundred good deeds recorded, a hundred bad deeds erased, and is protected from Satan until evening.» — Agreed upon.',
        'es':
            'De Abu Huraira: el Profeta ﷺ dijo: «Quien diga por la mañana cien veces: Lâ ilâha illallâh, sin asociado, Suyo es el dominio y la alabanza, sobre todo es Poderoso — obtiene la recompensa de liberar diez esclavos, se le inscriben cien buenas obras, se le borran cien malas y queda protegido del Demonio hasta la tarde.» — Acordado.',
      },
      day: 0, month: 0, isDaily: true,
      color: AppColors.gold, emoji: '🌅',
      defaultHour: 6, defaultMinute: 30,
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
        'fr': 'Invocations du soir après ‘Asr',
        'en': 'Evening remembrance after ‘Asr prayer',
        'es': 'Remembranza vespertina tras ‘Asr',
      },
      virtue: {
        'ar':
            'عن أبي هريرة رضي الله عنه قال: جاء رجل إلى النبي ﷺ فقال: يا رسول الله، ما لقيتُ من عقربٍ لدغتني البارحة! قال: «أَمَا لو قلتَ حين أمسيتَ: أعوذ بكلمات الله التامات من شر ما خلق، لم تضرّك» — رواه مسلم.',
        'fr':
            "D'après Abû Hurayra, un homme vint dire au Prophète ﷺ: « Ô Messager d'Allah, j'ai été piqué cette nuit par un scorpion ! » Il répondit: « Si tu avais dit le soir: A‘ûdhu bi-kalimâti-llâhi-t-tâmmâti min sharri mâ khalaq (Je cherche refuge auprès des paroles parfaites d'Allah contre le mal qu'Il a créé), il ne t'aurait pas nui. » — Muslim.",
        'en':
            'Abû Hurayrah reported that a man came to the Prophet ﷺ saying: "O Messenger of Allah, a scorpion stung me last night!" He ﷺ said: "Had you said in the evening: A‘ûdhu bi-kalimâti-llâhi-t-tâmmâti min sharri mâ khalaq (I seek refuge in the perfect words of Allah from the evil of what He has created), it would not have harmed you." — Muslim.',
        'es':
            'De Abu Huraira: un hombre se quejó al Profeta ﷺ de la picadura de un escorpión. Él ﷺ dijo: «Si hubieras dicho por la tarde: A‘ûdhu bi-kalimâti-llâhi-t-tâmmâti min sharri mâ khalaq (Busco refugio en las palabras perfectas de Alá del mal que ha creado), no te habría dañado.» — Muslim.',
      },
      day: 0, month: 0, isDaily: true,
      color: AppColors.gold, emoji: '🌆',
      defaultHour: 17, defaultMinute: 0,
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
        'ar': 'أذكار النوم قبل النوم',
        'fr': 'Invocations à dire avant de dormir',
        'en': 'Bedtime remembrance before sleeping',
        'es': 'Remembranza antes de dormir',
      },
      virtue: {
        'ar':
            'عن أبي هريرة رضي الله عنه أن رسول الله ﷺ قال: «إذا أوى أحدكم إلى فراشه فلْيقرأ آية الكرسي، فإنه لن يزال عليه من الله حافظ، ولا يقربه شيطان حتى يصبح» — رواه البخاري.',
        'fr':
            "D'après Abû Hurayra, le Prophète ﷺ a dit: « Quand l'un de vous s'apprête à dormir, qu'il récite Âyat al-Kursî: aucun gardien d'Allah ne cessera de veiller sur lui et aucun démon ne s'approchera de lui jusqu'au matin. » — Bukhârî.",
        'en':
            'Abû Hurayrah reported that the Prophet ﷺ said: "When one of you goes to bed, let him recite Âyat al-Kursî — a guardian from Allah will not cease to watch over him, and no devil will approach him until morning." — al-Bukhârî.',
        'es':
            'De Abu Huraira: el Profeta ﷺ dijo: «Cuando alguno de vosotros vaya a dormir, que recite Âyat al-Kursî: un guardián de Alá no dejará de protegerle y ningún demonio se acercará a él hasta la mañana.» — al-Bujari.',
      },
      day: 0, month: 0, isDaily: true,
      color: AppColors.navy, emoji: '🌙',
      defaultHour: 22, defaultMinute: 0,
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
        'ar': 'تذكير بأيام الحجامة: 16، 18، 20 من كل شهر هجري',
        'fr': 'Rappel des jours de Hijama : 16, 18, 20 de chaque mois hégirien',
        'en': 'Hijama reminder days: 16, 18, 20 of each Hijri month',
        'es': 'Recordatorio de días de Hijama: 16, 18, 20 de cada mes hégira',
      },
      virtue: {
        'ar':
            'عن ابن عباس رضي الله عنهما قال: قال رسول الله ﷺ: «الشفاء في ثلاثة: شَرْطةِ مِحْجَم، أو شَرْبةِ عسل، أو كَيَّةٍ بنار، وأنهى أمتي عن الكَيّ» — رواه البخاري.',
        'fr':
            "D'après Ibn ‘Abbâs, le Prophète ﷺ a dit: « La guérison se trouve en trois choses: une incision de ventouses (hijama), une gorgée de miel ou une cautérisation par le feu — et j'interdis la cautérisation à ma communauté. » — Bukhârî.",
        'en':
            'Ibn ‘Abbâs reported that the Prophet ﷺ said: "Healing is in three: an incision by the cupper, a draught of honey, or cauterisation with fire — and I forbid cauterisation for my Ummah." — al-Bukhârî.',
        'es':
            'De Ibn ‘Abbâs: el Profeta ﷺ dijo: «La cura está en tres cosas: una incisión de ventosas (hijama), un trago de miel o una cauterización con fuego — y prohíbo la cauterización a mi comunidad.» — al-Bujari.',
      },
      day: 16, month: 0, isMonthly: true,
      monthlyDays: <int>[16, 18, 20],
      color: AppColors.red, emoji: '🩸', defaultEnabled: false,
      defaultHour: 9, defaultMinute: 0,
    ),

    IslamicEventConfig(
      id: 'ayyam_albid',
      names: {
        'ar': 'الأيام البيض',
        'fr': 'Ayyam Al-Bid',
        'en': 'White Days',
        'es': 'Días Blancos',
      },
      description: {
        'ar': 'تذكير بصيام الأيام البيض — يبدأ التذكير في اليوم 12 من كل شهر هجري',
        'fr': 'Rappel du jeûne des Ayyam Al-Bid — déclenché le 12 de chaque mois hégirien',
        'en': 'White Days fasting reminder — fires on day 12 of each Hijri month',
        'es': 'Recordatorio del ayuno de los Días Blancos — el día 12 de cada mes hégira',
      },
      virtue: {
        'ar':
            'عن أبي ذر رضي الله عنه قال: قال لي رسول الله ﷺ: «يا أبا ذر، إذا صمتَ من الشهر ثلاثاً فصُمْ ثلاث عشرة، وأربع عشرة، وخمس عشرة» — رواه الترمذي وحسّنه، والنسائي.',
        'fr':
            "D'après Abû Dharr, le Prophète ﷺ lui a dit: « Ô Abû Dharr, si tu jeûnes trois jours du mois, jeûne le 13, le 14 et le 15. » — Tirmidhî (hasan) et Nasâ'î.",
        'en':
            'Abû Dharr reported that the Prophet ﷺ said to him: "O Abû Dharr, when you fast three days of the month, fast the 13th, the 14th and the 15th." — Tirmidhî (hasan) and Nasâ\'î.',
        'es':
            'De Abu Dharr: el Profeta ﷺ le dijo: «Oh Abu Dharr, si ayunas tres días del mes, ayuna el 13, el 14 y el 15.» — Tirmidhî (hasan) y Nasa\'î.',
      },
      day: 12, month: 0, isMonthly: true,
      monthlyDays: <int>[12],
      color: AppColors.gold, emoji: '🌕',
      defaultHour: 9, defaultMinute: 0,
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
        'ar': 'تذكير بيوم عاشوراء — يفعّل في اليوم 8 من شهر محرم',
        'fr': "Rappel de la journée d'Achoura — déclenché le 8 Mouharram",
        'en': 'Ashura reminder — fires on the 8th of Muharram',
        'es': 'Recordatorio del día de Ashura — el 8 de Muharram',
      },
      virtue: {
        'ar':
            'عن أبي قتادة رضي الله عنه أن رسول الله ﷺ قال: «صيام يوم عاشوراء، أحتسب على الله أن يكفّر السنة التي قبله» — رواه مسلم.',
        'fr':
            "D'après Abû Qatâda, le Prophète ﷺ a dit: « Le jeûne du jour d'Achoura, j'espère d'Allah qu'il efface les péchés de l'année passée. » — Muslim.",
        'en':
            'Abû Qatâdah reported that the Prophet ﷺ said: "Fasting the day of Ashura — I expect of Allah that it expiates the sins of the previous year." — Muslim.',
        'es':
            'De Abu Qatada: el Profeta ﷺ dijo: «El ayuno del día de Ashura, espero de Alá que expíe los pecados del año anterior.» — Muslim.',
      },
      day: 8, month: 1,
      color: AppColors.blue, emoji: '🕯',
      defaultHour: 9, defaultMinute: 0,
    ),

    IslamicEventConfig(
      id: 'ramadan_start',
      names: {
        'ar': 'بداية رمضان',
        'fr': 'Début du Ramadan',
        'en': 'Start of Ramadan',
        'es': 'Inicio de Ramadán',
      },
      description: {
        'ar': 'تذكير ببداية رمضان — يفعّل في اليوم 28 من شهر شعبان',
        'fr': 'Rappel du début du Ramadan — déclenché le 28 Cha‘bâne',
        'en': 'Ramadan-start reminder — fires on the 28th of Sha‘bân',
        'es': 'Recordatorio del inicio de Ramadán — el 28 de Sha‘bân',
      },
      virtue: {
        'ar':
            'عن أبي هريرة رضي الله عنه أن رسول الله ﷺ قال: «من صام رمضان إيماناً واحتساباً غُفر له ما تقدم من ذنبه، ومن قام رمضان إيماناً واحتساباً غُفر له ما تقدم من ذنبه، ومن قام ليلة القدر إيماناً واحتساباً غُفر له ما تقدم من ذنبه» — متفق عليه.',
        'fr':
            "D'après Abû Hurayra, le Prophète ﷺ a dit: « Celui qui jeûne le Ramadan par foi et en espérant la récompense d'Allah verra ses péchés passés pardonnés. Celui qui veille en prière le Ramadan par foi et espoir verra ses péchés passés pardonnés. Et celui qui veille la Nuit du Destin par foi et espoir verra ses péchés passés pardonnés. » — Muttafaq ‘alayh.",
        'en':
            'Abû Hurayrah reported that the Prophet ﷺ said: "Whoever fasts Ramadan out of faith and hoping for reward, his past sins are forgiven. Whoever stands in prayer through Ramadan out of faith and hope, his past sins are forgiven. And whoever stands the Night of Decree out of faith and hope, his past sins are forgiven." — Agreed upon.',
        'es':
            'De Abu Huraira: el Profeta ﷺ dijo: «Quien ayune Ramadán con fe y buscando la recompensa, le serán perdonados sus pecados pasados. Quien rece de noche en Ramadán con fe y buscando la recompensa, le serán perdonados sus pecados pasados. Y quien rece en la Noche del Decreto con fe y buscando la recompensa, le serán perdonados sus pecados pasados.» — Acordado.',
      },
      day: 28, month: 8,
      color: AppColors.green, emoji: '🌙',
      defaultHour: 9, defaultMinute: 0,
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
        'ar': 'تذكير بعيد الفطر — يفعّل في اليوم 28 من شهر رمضان',
        'fr': "Rappel de l'Aïd al-Fitr — déclenché le 28 Ramadan",
        'en': 'Eid al-Fitr reminder — fires on the 28th of Ramadan',
        'es': 'Recordatorio del Eid al-Fitr — el 28 de Ramadán',
      },
      virtue: {
        'ar':
            'عن أبي هريرة رضي الله عنه أن رسول الله ﷺ قال: «للصائم فرحتان يفرحُهما: إذا أفطر فرح بفطره، وإذا لقي ربه فرح بصومه» — متفق عليه.',
        'fr':
            "D'après Abû Hurayra, le Prophète ﷺ a dit: « Le jeûneur a deux joies dont il se réjouit: lorsqu'il rompt le jeûne, il se réjouit de sa rupture, et lorsqu'il rencontrera son Seigneur, il se réjouira de son jeûne. » — Muttafaq ‘alayh.",
        'en':
            'Abû Hurayrah reported that the Prophet ﷺ said: "The fasting person has two joys: when he breaks his fast he rejoices, and when he meets his Lord he rejoices because of his fast." — Agreed upon.',
        'es':
            'De Abu Huraira: el Profeta ﷺ dijo: «El ayunante tiene dos alegrías: cuando rompe su ayuno se alegra de la ruptura, y cuando encuentre a su Señor se alegrará de su ayuno.» — Acordado.',
      },
      day: 28, month: 9,
      color: AppColors.green, emoji: '🎉',
      defaultHour: 9, defaultMinute: 0,
    ),

    IslamicEventConfig(
      id: 'dhulhijja_start',
      names: {
        'ar': 'أيام عشر ذي الحجة',
        'fr': 'Dix jours de Dhou Al-Hijja',
        'en': 'Ten Days of Dhul Hijjah',
        'es': 'Diez días de Dhu al-Hiyya',
      },
      description: {
        'ar': 'تذكير بأيام عشر ذي الحجة — يفعّل في اليوم 28 من شهر ذي القعدة',
        'fr': 'Rappel des dix jours de Dhou Al-Hijja — déclenché le 28 Dhou Al-Qa‘da',
        'en': 'Ten Days of Dhul Hijjah reminder — fires on the 28th of Dhul Qa‘dah',
        'es': 'Recordatorio de los diez días de Dhu al-Hiyya — el 28 de Dhu al-Qa‘da',
      },
      virtue: {
        'ar':
            'عن ابن عباس رضي الله عنهما أن رسول الله ﷺ قال: «ما من أيامٍ العمل الصالح فيهن أحبّ إلى الله من هذه الأيام العشر». قالوا: يا رسول الله، ولا الجهاد في سبيل الله؟ قال: «ولا الجهاد في سبيل الله، إلا رجل خرج بنفسه وماله فلم يرجع من ذلك بشيء» — رواه البخاري.',
        'fr':
            "D'après Ibn ‘Abbâs, le Prophète ﷺ a dit: « Il n'est pas de jours où l'œuvre pieuse est plus aimée d'Allah que ces dix jours. » Ils dirent: Ô Messager d'Allah, même pas le combat dans Son sentier ? Il répondit: « Même pas le combat dans le sentier d'Allah, sauf pour un homme sorti avec sa personne et ses biens et qui n'en revient avec rien. » — Bukhârî.",
        'en':
            'Ibn ‘Abbâs reported that the Prophet ﷺ said: "There are no days in which righteous deeds are more beloved to Allah than these ten." They said: O Messenger of Allah, not even Jihâd in the path of Allah? He said: "Not even Jihâd in the path of Allah, except for a man who goes out with himself and his wealth and returns with nothing." — al-Bukhârî.',
        'es':
            'De Ibn ‘Abbâs: el Profeta ﷺ dijo: «No hay días en los que la buena obra sea más amada por Alá que estos diez.» Dijeron: ¿Ni siquiera el yihâd en Su sendero? Dijo: «Ni siquiera el yihâd en el sendero de Alá, salvo un hombre que sale con su persona y bienes y no regresa con nada.» — al-Bujari.',
      },
      day: 28, month: 11,
      color: AppColors.gold, emoji: '📅',
      defaultHour: 9, defaultMinute: 0,
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
        'ar': 'تذكير بيوم عرفة — يفعّل في اليوم 8 من شهر ذي الحجة',
        'fr': "Rappel du jour d'Arafat — déclenché le 8 Dhou Al-Hijja",
        'en': 'Day of Arafat reminder — fires on the 8th of Dhul Hijjah',
        'es': 'Recordatorio del día de Arafat — el 8 de Dhu al-Hiyya',
      },
      virtue: {
        'ar':
            'عن أبي قتادة رضي الله عنه أن رسول الله ﷺ سُئل عن صيام يوم عرفة، فقال: «يكفّر السنة الماضية والباقية» — رواه مسلم.',
        'fr':
            "D'après Abû Qatâda, le Prophète ﷺ fut interrogé sur le jeûne du jour d'Arafat. Il répondit: « Il efface les péchés de l'année passée et de l'année à venir. » — Muslim.",
        'en':
            'Abû Qatâdah reported that the Prophet ﷺ was asked about fasting the day of Arafat and he said: "It expiates the sins of the past year and the year to come." — Muslim.',
        'es':
            'De Abu Qatada: el Profeta ﷺ fue preguntado sobre el ayuno del día de Arafat y dijo: «Expía los pecados del año pasado y del próximo.» — Muslim.',
      },
      day: 8, month: 12,
      color: AppColors.gold, emoji: '🏔',
      defaultHour: 9, defaultMinute: 0,
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
        'ar': 'تذكير بعيد الأضحى — يفعّل في اليوم 9 من شهر ذي الحجة',
        'fr': "Rappel de l'Aïd al-Adha — déclenché le 9 Dhou Al-Hijja",
        'en': 'Eid al-Adha reminder — fires on the 9th of Dhul Hijjah',
        'es': 'Recordatorio del Eid al-Adha — el 9 de Dhu al-Hiyya',
      },
      virtue: {
        'ar':
            'عن عائشة رضي الله عنها أن رسول الله ﷺ قال: «ما عمل ابن آدم يوم النحر عملاً أحبّ إلى الله من إهراق الدم؛ إنه ليأتي يوم القيامة بقرونها وأشعارها وأظلافها، وإن الدم ليقع من الله بمكان قبل أن يقع من الأرض، فطِيبوا بها نفساً» — رواه الترمذي وابن ماجه.',
        'fr':
            "D'après ‘Â'isha, le Prophète ﷺ a dit: « Aucune œuvre du fils d'Adam, le jour du sacrifice, n'est plus aimée d'Allah que le sang versé. La bête se présentera le Jour de la Résurrection avec ses cornes, ses poils et ses sabots; et le sang est agréé par Allah avant même de toucher la terre. Sacrifiez donc d'un cœur joyeux. » — Tirmidhî et Ibn Mâja.",
        'en':
            '‘Â\'ishah reported that the Prophet ﷺ said: "No deed of the son of Adam on the Day of Sacrifice is more beloved to Allah than shedding blood. The animal will come on the Day of Resurrection with its horns, hair and hooves; and the blood is accepted by Allah before it touches the ground — so let your hearts rejoice in it." — Tirmidhî and Ibn Mâjah.',
        'es':
            'De ‘Â\'isha: el Profeta ﷺ dijo: «Ninguna obra del hijo de Adán, el día del sacrificio, es más amada por Alá que la sangre derramada. El animal vendrá el Día de la Resurrección con sus cuernos, pelos y pezuñas; y la sangre es aceptada por Alá antes de tocar la tierra — alegrad por ello vuestros corazones.» — Tirmidhî e Ibn Mâya.',
      },
      day: 9, month: 12,
      color: AppColors.green, emoji: '🎊',
      defaultHour: 9, defaultMinute: 0,
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
        'ar': 'تذكير بيوم الجمعة — يفعّل كل خميس استعداداً ليوم الجمعة',
        'fr': 'Rappel du vendredi — déclenché chaque jeudi pour préparer Joumou\'a',
        'en': 'Friday reminder — fires every Thursday in preparation for Jumu\'ah',
        'es': 'Recordatorio del viernes — cada jueves para preparar Jumu\'ah',
      },
      virtue: {
        'ar':
            'عن أبي هريرة رضي الله عنه أن رسول الله ﷺ قال: «خير يوم طلعت عليه الشمس يوم الجمعة، فيه خُلِق آدم، وفيه أُدخل الجنة، وفيه أُخرج منها، ولا تقوم الساعة إلا في يوم الجمعة» — رواه مسلم.',
        'fr':
            "D'après Abû Hurayra, le Prophète ﷺ a dit: « Le meilleur jour où le soleil se lève est le vendredi: c'est en ce jour qu'Adam fut créé, qu'il entra au Paradis et en fut expulsé, et l'Heure n'arrivera qu'un vendredi. » — Muslim.",
        'en':
            'Abû Hurayrah reported that the Prophet ﷺ said: "The best day on which the sun has risen is Friday: on it Adam was created, on it he entered Paradise and on it he was expelled from it, and the Hour will not come except on a Friday." — Muslim.',
        'es':
            'De Abu Huraira: el Profeta ﷺ dijo: «El mejor día en que sale el sol es el viernes: en él fue creado Adán, en él entró al Paraíso y en él fue expulsado, y la Hora no llegará sino un viernes.» — Muslim.',
      },
      day: 0, month: 0, isWeekly: true,
      // Reminder fires the day BEFORE Friday → Thursday (4).
      weekday: 4, weekdays: <int>[4],
      color: AppColors.green, emoji: '🕌',
      defaultHour: 18, defaultMinute: 0,
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
        'ar':
            'تذكير بصيام الاثنين والخميس — يفعّل كل أحد وكل أربعاء استعداداً لصيام اليوم التالي',
        'fr':
            'Rappel du jeûne du lundi et du jeudi — déclenché chaque dimanche et chaque mercredi pour le jeûne du lendemain',
        'en':
            'Monday/Thursday fasting reminder — fires every Sunday and Wednesday for the next-day fast',
        'es':
            'Recordatorio del ayuno del lunes y jueves — cada domingo y miércoles para el ayuno del día siguiente',
      },
      virtue: {
        'ar':
            'عن أبي هريرة رضي الله عنه أن رسول الله ﷺ قال: «تُعرض الأعمال يوم الاثنين والخميس، فأُحبّ أن يُعرض عملي وأنا صائم» — رواه الترمذي وحسّنه.',
        'fr':
            "D'après Abû Hurayra, le Prophète ﷺ a dit: « Les œuvres sont présentées le lundi et le jeudi: j'aime que mes œuvres soient présentées alors que je jeûne. » — Tirmidhî (hasan).",
        'en':
            'Abû Hurayrah reported that the Prophet ﷺ said: "Deeds are presented (to Allah) on Mondays and Thursdays, and I like my deeds to be presented while I am fasting." — Tirmidhî (hasan).',
        'es':
            'De Abu Huraira: el Profeta ﷺ dijo: «Las obras se presentan los lunes y jueves, y me gusta que las mías sean presentadas mientras ayuno.» — Tirmidhî (hasan).',
      },
      day: 0, month: 0, isWeekly: true,
      // Reminder fires the day BEFORE → Sunday (7) and Wednesday (3).
      weekday: 7, weekdays: <int>[7, 3],
      color: AppColors.blue, emoji: '🤲', defaultEnabled: false,
      defaultHour: 19, defaultMinute: 0,
    ),
  ];
}
