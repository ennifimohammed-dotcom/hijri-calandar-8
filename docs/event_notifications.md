# Event Notifications — Specification

Builds on `event_model.md`, `event_time_behavior.md`, and
`event_recurrence.md`. Scoped to the **business rules** of reminders:
what they trigger on, when they fire, how they compose with all-day
events, timed events, and recurrence.

Out of scope: UI, channel/audio platform behavior, code.

---

## 1. Vocabulary

| Term            | Meaning                                                                                  |
|-----------------|------------------------------------------------------------------------------------------|
| **Reminder**    | A user-configured rule attached to an event that asks the system to fire a notification. |
| **Trigger**     | The absolute instant computed from a reminder for a specific event occurrence.           |
| **Occurrence**  | A single instance of an event (the event itself for non-recurring; one of N for recurring). |
| **Window**      | The bounded time range in which the system actually schedules upcoming triggers.         |

A reminder is part of the event's data; a trigger is derived. The
system never persists triggers — only reminders.

---

## 2. Reminder kinds

Two and only two reminder kinds exist. They map directly to the two
shapes of `start` defined in `event_time_behavior.md`.

### 2.1 Relative reminder — for timed events

Fires at:

```
trigger.instant = occurrence.start.instant − offsetMinutes × 60s
```

Stored shape:

```
Reminder.relative {
  id              : string                 // stable within the event
  type            : "notification"
  offsetMinutes   : integer ≥ 0            // 0 = at the moment of the event
}
```

`offsetMinutes` is interpreted in absolute time, never wall-clock. A
relative reminder on an event that crosses a DST transition still fires
the same number of minutes before the event start instant.

### 2.2 Fixed-time reminder — for all-day events

Fires at:

```
trigger.localDateTime =
  (occurrence.start.date − daysBefore) at fixedHour:fixedMinute
```

Stored shape:

```
Reminder.fixedTime {
  id            : string
  type          : "notification"
  daysBefore    : integer ≥ 0              // 0 = same day, 1 = day before, …
  fixedHour     : 0..23
  fixedMinute   : 0..59
}
```

The trigger is a **wall-clock** in the **viewer's current zone**. There
is no IANA zone stored on the reminder itself — the all-day event has no
zone, so the trigger inherits the device's zone at fire time. This is
the Google Agenda behavior and makes "Eid Al-Fitr 9:00 the day before"
mean exactly what it says wherever the user happens to be.

---

## 3. Strict pairing rules

R-N-1. An event with `allDay == true` MAY only carry
`Reminder.fixedTime` reminders. Relative reminders are **rejected at
write time** — the concept "10 minutes before" is undefined for an
event that has no minute.

R-N-2. An event with `allDay == false` MAY only carry
`Reminder.relative` reminders. Fixed-time reminders are **rejected at
write time** — the concept "the day before at 09:00" is offered for
all-day only; for a timed event the right way to express it is a
relative offset measured in minutes/hours/days.

R-N-3. Toggling an event between all-day and timed (see
`event_time_behavior.md` §5–§6) MUST also convert or drop reminders:

- timed → all-day: each existing `Reminder.relative` is converted to the
  closest `Reminder.fixedTime` whose semantics make sense:
  - 0 min → same day at 09:00
  - ≤ 1440 min → same day at 09:00
  - ≤ 2 × 1440 min → 1 day before at 09:00
  - ≤ 7 × 1440 min → 1 week before at 09:00
  - otherwise → drop and notify the user

- all-day → timed: each existing `Reminder.fixedTime` is **dropped**
  and replaced by a single default `Reminder.relative` of 30 minutes.
  The user is told. No silent re-mapping is attempted (a fixed-time
  reminder has no defensible relative equivalent against a freshly
  picked clock time).

R-N-4. Both conversions are explicit user actions. The model never
auto-converts behind the user's back.

---

## 4. Standard presets

Presets are policy, not invariants. They are listed here so every layer
of the system stays consistent.

### 4.1 Relative (timed events)

| Label              | offsetMinutes |
|--------------------|---------------|
| At the time        | 0             |
| 5 minutes before   | 5             |
| 10 minutes before  | 10            |
| 15 minutes before  | 15            |
| 30 minutes before  | 30            |
| 1 hour before      | 60            |
| 2 hours before     | 120           |
| 1 day before       | 1440          |
| 2 days before      | 2880          |
| 1 week before      | 10080         |
| Custom (value + unit) | user-defined |

Default for a freshly created timed event: a single reminder at
30 minutes before.

### 4.2 Fixed-time (all-day events)

| Label                              | daysBefore | fixedHour:fixedMinute |
|------------------------------------|------------|------------------------|
| Same day at 09:00                  | 0          | 09:00                  |
| The day before at 09:00            | 1          | 09:00                  |
| The day before at 11:00            | 1          | 11:00                  |
| The day before at 17:00            | 1          | 17:00                  |
| 2 days before at 09:00             | 2          | 09:00                  |
| 1 week before at 09:00             | 7          | 09:00                  |
| Custom (date + time)               | user-defined |                      |

Default for a freshly created all-day event: a single reminder
**1 day before at 09:00**. 09:00 is chosen because it is early enough to
be useful and late enough to be non-intrusive.

---

## 5. Per-event constraints

R-N-5. An event MAY carry **0 to 5** reminders. The cap defends users
against runaway notifications without being arbitrarily small.

R-N-6. Reminders within an event MUST have unique ids. Two reminders
that resolve to the same trigger instant are allowed (the system
de-duplicates at fire time, see §8).

R-N-7. A reminder is enabled iff:
- the event is `isEnabled == true`, AND
- the event's notifications-per-event toggle is on (a single boolean on
  the event), AND
- the global notifications switch is on (out of scope here, see the
  notification settings spec).

R-N-8. Reminders survive event edits except where R-N-3 applies. A
title or location change does not touch reminders.

---

## 6. Recurrence interaction

R-N-9. A reminder attached to a recurring event applies to **every
occurrence** that the rule produces. The reminder is part of the
master, not of any single occurrence.

R-N-10. Per-occurrence overrides MAY add or remove reminders for that
single occurrence:

```
OccurrenceOverride {
  reminders?         : Reminder[]              // replaces master.reminders for this occurrence
  remindersDisabled? : boolean                 // silences the occurrence
}
```

If `reminders` is absent in the override, the occurrence inherits the
master's reminders.

R-N-11. A cancelled occurrence (EXDATE) produces **no triggers**, even
if the master has reminders.

R-N-12. SPLIT (this-and-following) carries the master's reminders into
the new master by default. The user is offered the chance to edit them
during the split.

---

## 7. Trigger computation summary

For each occurrence and each enabled reminder:

```
if reminder.kind == relative:
    trigger.instant = occurrence.start.instant
                      − reminder.offsetMinutes × 60s

if reminder.kind == fixedTime:
    trigger.localDate = occurrence.start.date − reminder.daysBefore
    trigger.localTime = (reminder.fixedHour, reminder.fixedMinute)
    trigger.instant   = (trigger.localDate, trigger.localTime)
                        .atZone(device.currentZone)
                        .toInstant()
```

Triggers are **derived on demand** from the persisted event data. They
are never cached in the event row.

---

## 8. Bounded scheduling window

The system schedules concrete OS-level alarms only for triggers inside
a rolling forward window.

R-N-13. The window MUST be at least 30 days. Triggers further in the
future MUST be recomputed and re-scheduled lazily (see R-N-15).

R-N-14. A trigger whose `instant < now` MUST be discarded silently — it
is in the past. This includes the freshly-created case where the user
adds "10 min before" to an event starting in 5 min.

R-N-15. The system MUST recompute upcoming triggers on:

- application start,
- daily at a fixed local time (e.g. 00:01), to roll the 30-day window,
- after device boot,
- every time an event or reminder is created, edited, or deleted,
- every time the user changes the device time zone or system clock.

R-N-16. Identical triggers (same instant, same event) MUST be
de-duplicated; the system fires one notification per (event,
trigger.instant) pair, even if multiple reminders resolve to the same
moment.

---

## 9. Time-zone interactions

R-N-17. Relative reminders inherit the event's zone implicitly because
they're computed against the event's start instant, which already
encodes the zone. Travelling does not shift the trigger.

R-N-18. Fixed-time reminders are computed in the **device's current
zone at scheduling time**. If the user crosses zones between scheduling
and fire time, the system MUST re-resolve in the new zone on the next
recompute (R-N-15). The intent of "9:00 the day before" is "9:00 where
I am", not "9:00 where I was when I created the event".

R-N-19. DST gaps inside a fixed-time trigger (the configured wall-clock
does not exist on the trigger day, e.g. 02:30 on a spring-forward day)
MUST be resolved to the **next valid wall-clock** (typically 03:00).
DST overlaps resolve to the **earlier** instant. Both behaviors are
identical to the rules in `event_time_behavior.md` §2.3.

---

## 10. Per-event override of notifications

Each event carries a single boolean: `notificationsEnabled`. When
`false`, all reminders attached to that event are inert: no triggers
are computed, no alarms scheduled. The reminders themselves remain
stored, so flipping the switch back on restores them exactly as they
were.

This is independent of:

- the global notifications switch (system-wide off),
- the event's `isEnabled` flag (which hides the event entirely from
  calendar views).

Precedence (highest wins):

```
global off  >  event.isEnabled == false  >  event.notificationsEnabled == false  >  reminder fires
```

---

## 11. Hard invariants (notifications)

1. A reminder's kind MUST match the event's `allDay` flag (R-N-1, R-N-2).
2. An event MUST NOT carry more than 5 reminders.
3. Reminders are never silently created, deleted, or converted —
   conversions in §3 always require an explicit user action and notify
   the user of any drops.
4. Triggers in the past or beyond the rolling window are dropped, not
   queued.
5. Identical triggers de-duplicate; the user sees one notification per
   distinct (event, instant) pair.
6. A cancelled occurrence produces zero triggers.
7. Toggling `notificationsEnabled` is reversible without data loss —
   the reminder array is preserved.
