import 'dart:convert';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────
// ENUMS
// ─────────────────────────────────────────────
enum EventType { islamic, personal, system }
enum RecurrenceFrequency { daily, weekly, monthly, yearly }
enum EventPriority { low, medium, high }
enum ReminderType { notification }

// ─────────────────────────────────────────────
// RECURRENCE RULE
// ─────────────────────────────────────────────
class RecurrenceRule {
  final RecurrenceFrequency frequency;
  final int interval;           // every N units
  final List<int> weekdays;     // 1=Mon..7=Sun for weekly
  final int? monthDay;          // for monthly (1-30)
  final int? month;             // for yearly (1-12)
  final int? count;             // max occurrences
  final DateTime? until;        // end date

  const RecurrenceRule({
    required this.frequency,
    this.interval = 1,
    this.weekdays = const [],
    this.monthDay,
    this.month,
    this.count,
    this.until,
  });

  Map<String, dynamic> toJson() => {
    'frequency': frequency.name,
    'interval': interval,
    'weekdays': weekdays,
    'monthDay': monthDay,
    'month': month,
    'count': count,
    'until': until?.millisecondsSinceEpoch,
  };

  factory RecurrenceRule.fromJson(Map<String, dynamic> j) => RecurrenceRule(
    frequency: RecurrenceFrequency.values.firstWhere(
        (e) => e.name == j['frequency'],
        orElse: () => RecurrenceFrequency.daily),
    interval: (j['interval'] as num?)?.toInt() ?? 1,
    weekdays: (j['weekdays'] as List?)?.map((e) => (e as num).toInt()).toList() ?? [],
    monthDay: (j['monthDay'] as num?)?.toInt(),
    month: (j['month'] as num?)?.toInt(),
    count: (j['count'] as num?)?.toInt(),
    until: j['until'] != null
        ? DateTime.fromMillisecondsSinceEpoch((j['until'] as num).toInt())
        : null,
  );
}

// ─────────────────────────────────────────────
// REMINDER
// ─────────────────────────────────────────────
class EventReminder {
  final String id;
  final int minutesBefore;
  final ReminderType type;

  const EventReminder({
    required this.id,
    required this.minutesBefore,
    this.type = ReminderType.notification,
  });

  String label(String locale) {
    if (minutesBefore == 0) {
      return locale == 'ar' ? 'عند الحدث' : locale == 'fr' ? 'Au moment' : 'At time';
    }
    if (minutesBefore < 60) {
      return locale == 'ar' ? '$minutesBefore دقيقة قبل'
          : locale == 'fr' ? '$minutesBefore min avant'
          : '$minutesBefore min before';
    }
    if (minutesBefore < 1440) {
      final h = minutesBefore ~/ 60;
      return locale == 'ar' ? '${h == 1 ? "ساعة" : "$h ساعات"} قبل'
          : locale == 'fr' ? '${h}h avant' : '${h}h before';
    }
    final d = minutesBefore ~/ 1440;
    return locale == 'ar' ? '${d == 1 ? "يوم" : "$d أيام"} قبل'
        : locale == 'fr' ? '${d}j avant' : '${d}d before';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'minutesBefore': minutesBefore,
    'type': type.name,
  };

  factory EventReminder.fromJson(Map<String, dynamic> j) => EventReminder(
    id: j['id'] as String,
    minutesBefore: (j['minutesBefore'] as num).toInt(),
    type: ReminderType.values.firstWhere(
        (e) => e.name == (j['type'] ?? 'notification'),
        orElse: () => ReminderType.notification),
  );
}

// ─────────────────────────────────────────────
// APP EVENT (production model)
// ─────────────────────────────────────────────
class AppEvent {
  final String id;
  final Map<String, String> titles;       // {ar, fr, en, es}
  final Map<String, String> descriptions; // multilingual
  final DateTime startDate;
  final DateTime endDate;
  final bool isAllDay;
  final RecurrenceRule? recurrenceRule;
  final List<EventReminder> reminders;
  final EventType type;
  final Color color;
  final String emoji;
  final String category;
  final String location;
  final EventPriority priority;
  final bool isEnabled;
  final bool isPrivate;
  final DateTime createdAt;
  final DateTime updatedAt;
  // Hijri reference (for Islamic events)
  final int? hijriDay;
  final int? hijriMonth;
  final int? hijriYear;
  final bool isIslamic;

  const AppEvent({
    required this.id,
    required this.titles,
    this.descriptions = const {},
    required this.startDate,
    required this.endDate,
    this.isAllDay = true,
    this.recurrenceRule,
    this.reminders = const [],
    this.type = EventType.personal,
    required this.color,
    this.emoji = '',
    this.category = 'personal',
    this.location = '',
    this.priority = EventPriority.medium,
    this.isEnabled = true,
    this.isPrivate = false,
    required this.createdAt,
    required this.updatedAt,
    this.hijriDay,
    this.hijriMonth,
    this.hijriYear,
    this.isIslamic = false,
  });

  String title(String locale) =>
      titles[locale] ?? titles['ar'] ?? titles.values.firstOrNull ?? '';

  String description(String locale) =>
      descriptions[locale] ?? descriptions['ar'] ?? '';

  bool get isRecurring => recurrenceRule != null;

  AppEvent copyWith({
    String? id,
    Map<String, String>? titles,
    Map<String, String>? descriptions,
    DateTime? startDate,
    DateTime? endDate,
    bool? isAllDay,
    RecurrenceRule? recurrenceRule,
    List<EventReminder>? reminders,
    EventType? type,
    Color? color,
    String? emoji,
    String? category,
    String? location,
    EventPriority? priority,
    bool? isEnabled,
    bool? isPrivate,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? hijriDay, int? hijriMonth, int? hijriYear,
    bool? isIslamic,
  }) => AppEvent(
    id: id ?? this.id,
    titles: titles ?? this.titles,
    descriptions: descriptions ?? this.descriptions,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    isAllDay: isAllDay ?? this.isAllDay,
    recurrenceRule: recurrenceRule ?? this.recurrenceRule,
    reminders: reminders ?? this.reminders,
    type: type ?? this.type,
    color: color ?? this.color,
    emoji: emoji ?? this.emoji,
    category: category ?? this.category,
    location: location ?? this.location,
    priority: priority ?? this.priority,
    isEnabled: isEnabled ?? this.isEnabled,
    isPrivate: isPrivate ?? this.isPrivate,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    hijriDay: hijriDay ?? this.hijriDay,
    hijriMonth: hijriMonth ?? this.hijriMonth,
    hijriYear: hijriYear ?? this.hijriYear,
    isIslamic: isIslamic ?? this.isIslamic,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'titles': titles,
    'descriptions': descriptions,
    'startDate': startDate.millisecondsSinceEpoch,
    'endDate': endDate.millisecondsSinceEpoch,
    'isAllDay': isAllDay,
    'recurrenceRule': recurrenceRule?.toJson(),
    'reminders': reminders.map((r) => r.toJson()).toList(),
    'type': type.name,
    'color': color.value,
    'emoji': emoji,
    'category': category,
    'location': location,
    'priority': priority.name,
    'isEnabled': isEnabled,
    'isPrivate': isPrivate,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'hijriDay': hijriDay,
    'hijriMonth': hijriMonth,
    'hijriYear': hijriYear,
    'isIslamic': isIslamic,
  };

  factory AppEvent.fromJson(Map<String, dynamic> j) {
    final now = DateTime.now();
    return AppEvent(
      id: j['id'] as String,
      titles: Map<String, String>.from(j['titles'] as Map),
      descriptions: j['descriptions'] != null
          ? Map<String, String>.from(j['descriptions'] as Map)
          : const {},
      startDate: j['startDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch((j['startDate'] as num).toInt())
          : now,
      endDate: j['endDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch((j['endDate'] as num).toInt())
          : now,
      isAllDay: (j['isAllDay'] as bool?) ?? true,
      recurrenceRule: j['recurrenceRule'] != null
          ? RecurrenceRule.fromJson(j['recurrenceRule'] as Map<String, dynamic>)
          : null,
      reminders: j['reminders'] != null
          ? (j['reminders'] as List)
              .map((r) => EventReminder.fromJson(r as Map<String, dynamic>))
              .toList()
          : [],
      type: EventType.values.firstWhere(
          (e) => e.name == (j['type'] ?? 'personal'),
          orElse: () => EventType.personal),
      color: Color((j['color'] as num).toInt()),
      emoji: (j['emoji'] as String?) ?? '',
      category: (j['category'] as String?) ?? 'personal',
      location: (j['location'] as String?) ?? '',
      priority: EventPriority.values.firstWhere(
          (e) => e.name == (j['priority'] ?? 'medium'),
          orElse: () => EventPriority.medium),
      isEnabled: (j['isEnabled'] as bool?) ?? true,
      isPrivate: (j['isPrivate'] as bool?) ?? false,
      createdAt: j['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch((j['createdAt'] as num).toInt())
          : now,
      updatedAt: j['updatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch((j['updatedAt'] as num).toInt())
          : now,
      hijriDay: (j['hijriDay'] as num?)?.toInt(),
      hijriMonth: (j['hijriMonth'] as num?)?.toInt(),
      hijriYear: (j['hijriYear'] as num?)?.toInt(),
      isIslamic: (j['isIslamic'] as bool?) ?? false,
    );
  }

  static String encodeList(List<AppEvent> events) =>
      jsonEncode(events.map((e) => e.toJson()).toList());

  static List<AppEvent> decodeList(String source) {
    final list = jsonDecode(source) as List;
    return list.map((e) => AppEvent.fromJson(e as Map<String, dynamic>)).toList();
  }
}

// ─────────────────────────────────────────────
// EVENT INSTANCE (expanded occurrence)
// ─────────────────────────────────────────────
class EventInstance {
  final AppEvent event;
  final DateTime instanceDate;
  final bool isFirstOccurrence;

  const EventInstance({
    required this.event,
    required this.instanceDate,
    this.isFirstOccurrence = true,
  });

  String title(String locale) => event.title(locale);
  Color get color => event.color;
  bool get isAllDay => event.isAllDay;
  bool get isIslamic => event.isIslamic;
}
