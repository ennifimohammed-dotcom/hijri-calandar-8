# Event Data Model — Conceptual Design

Scope: data model only. Notifications and UI are deliberately out of scope.

---

## 1. Event types

An event has exactly one **kind**, chosen at creation and never inferred:

| Kind       | Meaning                                                             | Default `allDay` |
|------------|---------------------------------------------------------------------|------------------|
| `event`    | A scheduled activity. May be all-day or timed.                      | `false`          |
| `task`     | A to-do anchored to a date or a date+time. Has a status (done/not). | `false`          |
| `birthday` | A yearly recurring all-day marker tied to a person.                 | `true` (forced)  |

Rules:

- `kind` is immutable after creation.
- `birthday` events MUST be `allDay = true` and MUST recur yearly.
- `task` events MAY be all-day or timed; they additionally carry a `completed` boolean. Completion does not delete the event, it only flags it.
- `event` is the general case; no extra constraints beyond the rest of this document.

---

## 2. `allDay` vs timed

Each event has a boolean `allDay`. It is the single switch that determines the entire shape of `start` and `end`.

### 2.1 `allDay = true`

- The event has **no clock time**.
- It occupies one or more **whole civil days** in the user's local calendar.
- It has **no time zone**: it is interpreted in whatever local calendar the user is currently looking at.
- `start` and `end` carry **a date only** (year/month/day). Any hour/minute component MUST be discarded when persisting.

### 2.2 `allDay = false` (timed)

- The event has a precise instant for its start and a precise instant for its end.
- `start` and `end` carry a **wall-clock date+time** plus an **IANA time zone**.
- The duration is `end − start` in absolute (UTC) time.
- A timed event MAY span midnight (see §4).

Rules:

- Toggling `allDay` is a **destructive conversion**, not a free-form edit:
  - timed → all-day: drop hours/minutes and time zone, set `start.date = floor(start)` and `end.date = floor(end) + 1 day` (see §3).
  - all-day → timed: pick default times (e.g. 09:00 → 10:00 in the device time zone) and require the user to confirm.
- The two shapes never coexist for the same event.

---

## 3. `start` / `end` fields

The model stores `start` and `end` as a tagged union driven by `allDay`:

```
Event {
  id            : string                    // stable, globally unique
  kind          : "event" | "task" | "birthday"
  title         : string
  description   : string?                   // optional, plain text
  location      : string?                   // optional, free text
  allDay        : boolean
  start         : DatePoint                 // see below
  end           : DatePoint                 // see below
  recurrence    : RecurrenceRule?           // optional
  participants  : Participant[]             // possibly empty
  videoLink     : string?                   // URL, optional
  color         : ColorRef                  // single accent color
  createdAt     : Instant
  updatedAt     : Instant
  // task-only:
  completed     : boolean?                  // present iff kind == "task"
}

DatePoint =
    AllDayDate { date: LocalDate }                  // when allDay == true
  | ZonedDateTime { dateTime: LocalDateTime,
                    timeZone: IanaZoneId }          // when allDay == false
```

### 3.1 Shared invariants

- `start` and `end` MUST have the same shape as dictated by `allDay`. Mixing (e.g. `start` zoned + `end` date-only) is invalid.
- `end` is **never strictly before** `start`. Equality is allowed (zero-duration timed event), inversion is rejected.
- Time zone of `start` and `end` MUST be identical for timed events. Two-zone events are not supported in this model.

---

## 4. The exclusive end-date rule (all-day events)

For all-day events, `end.date` is **exclusive**. This is the same convention used by RFC 5545 (`DTEND` for `VALUE=DATE`) and by Google Calendar's API.

### 4.1 Storage vs display

| Concept                     | Stored value     | Shown to the user |
|-----------------------------|------------------|-------------------|
| Single-day event on Apr 16  | `start = 2026-04-16`, `end = 2026-04-17` | "Apr 16"          |
| Three-day event Apr 16–18   | `start = 2026-04-16`, `end = 2026-04-19` | "Apr 16 – Apr 18" |

The inclusive last day (the one the user sees) is always `end.date − 1 day`.

### 4.2 Invariants

- `end.date > start.date` (strict). An all-day event always covers at least one whole day.
- "Containment" check for a query day `D`:
  `start.date ≤ D < end.date`
  Note the strict `<` on the right. A day-D event `[start=D, end=D+1)` does **not** include `D+1`.
- Conversion timed → all-day rounds inward: `start.date = floor(start.dateTime)`, `end.date = floor(end.dateTime) + 1 day` so the visible inclusive last day matches the timed event's last calendar day.
- Conversion all-day → timed expands to the local zone: `start.dateTime = start.date 00:00`, `end.dateTime = (end.date − 1 day) 23:59:59.999`, then offered to the user for adjustment.

### 4.3 Why exclusive?

- Arithmetic: duration in days is just `end.date − start.date`, no off-by-one.
- Range queries on day buckets become half-open intervals, which compose cleanly.
- Same model as ICS / Google → import/export is lossless.

---

## 5. Events crossing midnight

A timed event MAY have `start.dateTime` and `end.dateTime` on different civil days. This is the only correct way to represent things like "23:00 → 01:00".

### 5.1 Rules

- Midnight crossing is allowed only when `allDay == false`.
- The event is rendered in **every calendar day it overlaps**, but its identity remains a single event. Splitting it into two day-fragments is a rendering concern (out of scope here), not a data concern.
- A query for events on day `D` (in zone `Z`) matches a timed event when the timed interval `[start, end)` overlaps the local-day interval `[D 00:00 in Z, D+1 00:00 in Z)`. Use a strict half-open overlap test.
- If the user converts a midnight-crossing timed event to all-day, the resulting all-day event covers every civil day the original interval touched, applying the exclusive-end rule.

### 5.2 Edge cases that MUST be supported

- Exactly-midnight end: `end = D+1 00:00` is valid and means "ends on D, does not include D+1". This is consistent with the exclusive-end rule applied at hour resolution.
- Daylight-saving transition night: duration is computed in absolute time. A "nightly 23:00 → 06:00" recurring event can be 6h, 7h, or 8h depending on DST; the local wall-clock fields stay 23:00 and 06:00 and the time zone is what disambiguates.

---

## 6. Time-zone handling

Time zones apply only to **timed** events.

### 6.1 Representation

- Every `ZonedDateTime` stores:
  1. a wall-clock `LocalDateTime` (no offset attached),
  2. an `IanaZoneId` (e.g. `Africa/Casablanca`, `Europe/Paris`, `UTC`).
- The instant is derived: `instant = LocalDateTime.atZone(IanaZoneId).toInstant()`.
- Storing the instant alone is **forbidden**: it loses the user's intent across DST.
- Storing a fixed UTC offset (e.g. `+01:00`) is **forbidden** for the same reason: the offset is not a zone, it cannot survive DST.

### 6.2 Rules

- The zone is a property of the **event**, not of the device. An event created in `Europe/Paris` retains that zone forever, even when displayed on a device in `Asia/Tokyo`.
- Display is always converted to the device's current zone unless the user opts to view the event in its own zone.
- Comparing two timed events compares their **instants** (UTC), never their wall-clocks.
- All-day events ignore time zones entirely. They are date-only and identical for every viewer regardless of their location.
- Recurrence rules attached to timed events expand in the **event's own zone**, then each occurrence's instant is computed individually. This is what makes "every day at 09:00" actually fire at 09:00 local even across DST.

### 6.3 Required validations

- `IanaZoneId` MUST validate against the platform's tz database at write time.
- A serialized event whose zone no longer exists in the tz database (rare, but possible after years) MUST be flagged on read and presented to the user for migration; it MUST NOT be silently coerced.

---

## 7. Hard invariants (summary)

A persisted event is valid if and only if **all** of the following hold:

1. `id` is non-empty and unique within the store.
2. `kind ∈ {event, task, birthday}` and is immutable.
3. `kind == "birthday"` ⇒ `allDay == true` and `recurrence` is yearly.
4. `kind == "task"` ⇒ `completed` is present (boolean). For non-task kinds, `completed` is absent.
5. `start` and `end` have the same shape as `allDay`.
6. If `allDay == true`: `start.date < end.date` (strict, exclusive end).
7. If `allDay == false`: `start.dateTime ≤ end.dateTime`, both share the same `timeZone`, and `timeZone` is a valid IANA id.
8. `title` is non-empty after trimming.
9. `createdAt ≤ updatedAt`.

Anything that violates these MUST be rejected at the model boundary, not silently repaired.
