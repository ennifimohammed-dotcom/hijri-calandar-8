# Event Time Behavior — Specification

Builds on `event_model.md`. Strictly scoped to time semantics:
all-day, timed, midnight crossing, validation, and conversions.

Out of scope: recurrence, notifications, UI.

---

## 1. All-day event behavior

### 1.1 Definition

An all-day event represents a span of **whole civil days** in the user's local calendar. It has no clock time, no time zone, and no instant on the absolute timeline.

### 1.2 Storage shape

```
allDay      : true
start.date  : LocalDate          // inclusive
end.date    : LocalDate          // exclusive (see §1.4)
timeZone    : <absent>
```

Any hour/minute/second/zone field MUST be discarded at write time. Reading back an all-day event MUST never expose a clock time.

### 1.3 Day membership

A given calendar day `D` is part of the event iff:

```
start.date  ≤  D  <  end.date
```

Note the strict `<` on the right. This is the half-open interval.

### 1.4 Inclusive end (display) vs exclusive end (storage)

The user always thinks in inclusive days. Storage is exclusive.

| User intent           | `start.date` | `end.date` (stored) | Inclusive last day shown |
|-----------------------|--------------|---------------------|--------------------------|
| Just Apr 16           | 2026-04-16   | 2026-04-17          | 2026-04-16               |
| Apr 16 → Apr 18       | 2026-04-16   | 2026-04-19          | 2026-04-18               |
| Whole month of Ramadan (assume 30 days starting Mar 1) | 2026-03-01 | 2026-03-31 | 2026-03-30 |

The inclusive last day is always `end.date − 1 day`.

### 1.5 Same-day across geographies

An all-day "Eid Al-Fitr 16 April" event is **the same day for every viewer**, regardless of their device's time zone. This is the entire point of the date-only shape: there is no instant to convert.

---

## 2. Timed event behavior

### 2.1 Definition

A timed event represents a precise interval `[start, end)` on the absolute timeline, expressed in the event's own time zone.

### 2.2 Storage shape

```
allDay              : false
start.dateTime      : LocalDateTime          // wall-clock
start.timeZone      : IanaZoneId             // e.g. "Africa/Casablanca"
end.dateTime        : LocalDateTime
end.timeZone        : IanaZoneId             // MUST equal start.timeZone
```

Storing only the absolute instant (UTC) is forbidden — it loses the user's wall-clock intent across DST transitions and zone migrations.

Storing a fixed UTC offset (e.g. `+01:00`) is forbidden for the same reason — an offset is not a zone.

### 2.3 Instant resolution

Whenever an absolute instant is needed (sorting, conflict detection, exporting):

```
instant = LocalDateTime.atZone(IanaZoneId).toInstant()
```

DST transitions:

- Skipped wall-clock time (spring forward): the impossible local time MUST be rejected at write time.
- Ambiguous wall-clock time (fall back, the same wall-clock happens twice): the model resolves to the **earlier** of the two instants, and surfaces a warning. The user MAY override.

### 2.4 Display in another zone

Display is a **pure conversion**, not a mutation. Showing an event created in `Europe/Paris` on a device set to `Asia/Tokyo` re-projects the instant into Tokyo wall-clock for rendering only. The stored zone never changes implicitly.

### 2.5 Duration

```
duration = end.instant − start.instant
```

Duration is computed in absolute time, never by subtracting wall-clocks. This is the only correct behavior across DST.

### 2.6 Zero-duration events

`end == start` is allowed and represents a "moment" event. The interval `[start, end)` is empty but the event remains visible at its start instant.

---

## 3. Events crossing midnight

### 3.1 When it applies

Only timed events can cross midnight. An all-day event is already day-aligned by construction.

### 3.2 Rule

`start.dateTime` and `end.dateTime` MAY belong to different civil days, as long as `end.instant ≥ start.instant`.

Example: night shift in `Africa/Casablanca`:

```
start = 2026-04-16T23:00, zone = Africa/Casablanca
end   = 2026-04-17T01:00, zone = Africa/Casablanca
duration = 2h
```

### 3.3 Day membership for timed events

A query day `D` (in the viewer's zone `Z`) matches a timed event when:

```
[start.instant, end.instant)  overlaps  [D 00:00 in Z, D+1 00:00 in Z)
```

Both intervals are half-open. A timed event ending exactly at `D+1 00:00` does **not** belong to `D+1`.

The midnight-crossing event in §3.2 therefore appears on **both** Apr 16 and Apr 17. It is one event, not two; splitting it visually is a rendering concern.

### 3.4 Exact-midnight end

`end = D+1 00:00` is valid and means "ends on D, does not include D+1". This is consistent with the half-open interval and prevents events from accidentally bleeding into the next day.

### 3.5 DST inside the interval

If the interval contains a DST transition, **wall-clock fields stay as the user typed them**. The duration becomes 1h shorter (spring forward) or 1h longer (fall back). The model never silently shifts the wall-clock to preserve duration.

---

## 4. start / end validation rules

The model rejects an event at write time if **any** rule below is violated.

### 4.1 Shape consistency

R-1. `start` and `end` MUST have the same shape (both date-only or both date+time+zone), matching `allDay`.

### 4.2 Ordering

R-2. All-day: `start.date < end.date` (strict). All-day events always cover at least one full day.

R-3. Timed: `start.instant ≤ end.instant`. Equality is allowed (zero-duration event). Inversion is rejected.

### 4.3 Zone consistency

R-4. Timed: `start.timeZone == end.timeZone`. Two-zone events are not supported.

R-5. Timed: the zone MUST be a valid IANA id. Fixed offsets and "GMT+N" strings are rejected.

### 4.4 DST sanity

R-6. Timed: neither `start.dateTime` nor `end.dateTime` may fall in a DST gap (a wall-clock that does not exist). Rejected at write time.

R-7. Timed: a DST overlap (a wall-clock that exists twice) is accepted; the earlier instant is chosen by default and the user is informed.

### 4.5 All-day cleanliness

R-8. All-day: `start` and `end` MUST NOT carry hour/minute/second/zone fields. If a writer provides them, they MUST be stripped before persisting; the writer MUST NOT silently keep them.

### 4.6 Bounds

R-9. Both endpoints MUST fall within a sane calendar range (e.g. year ≥ 1900 and ≤ 2200). Out-of-range values are rejected.

### 4.7 Identity invariance

R-10. `id`, `kind`, and `createdAt` are immutable across edits. `start`, `end`, `allDay`, and `timeZone` are mutable, subject to R-1 .. R-9.

---

## 5. Converting all-day → timed

### 5.1 Rationale

The user changes their mind: "Eid lunch" was created as all-day on Apr 16 but should actually be 12:00 → 14:00.

### 5.2 Procedure

1. Pick the **device's current IANA zone** as the target zone.
2. Pick default wall-clock times (recommended: `09:00` start, `10:00` end). The choice is policy, not a model rule.
3. Build:
   ```
   timeZone           = device zone
   start.dateTime     = start.date  at <default start>
   end.dateTime       = (end.date − 1 day) at <default end>
   ```
   Using `end.date − 1 day` keeps the conversion on the **inclusive last day** the user originally meant.
4. Validate against §4. If R-3 is violated (e.g. defaults make end < start because the all-day was a single day), the model MUST set `end.dateTime = start.dateTime + 1 hour`.
5. Set `allDay = false` and persist.

### 5.3 Worked example

Before:

```
allDay = true
start.date = 2026-04-16
end.date   = 2026-04-17       (single inclusive day: Apr 16)
```

After conversion (device zone = `Africa/Casablanca`, defaults 09:00/10:00):

```
allDay = false
timeZone = Africa/Casablanca
start.dateTime = 2026-04-16T09:00
end.dateTime   = 2026-04-16T10:00
```

Multi-day all-day example:

```
allDay = true
start.date = 2026-04-16
end.date   = 2026-04-19       (Apr 16, 17, 18)
```

Becomes:

```
allDay = false
timeZone = Africa/Casablanca
start.dateTime = 2026-04-16T09:00
end.dateTime   = 2026-04-18T10:00       // last inclusive day Apr 18
```

The user is then offered an explicit edit step before the conversion is committed.

---

## 6. Converting timed → all-day

### 6.1 Rationale

The user changes their mind: "Conference 09:00 → 17:00 on Apr 16" should actually be all-day.

### 6.2 Procedure

1. Compute the **inclusive day range** the timed event touches in the **event's own zone**:
   ```
   firstDay = floor(start.dateTime to date in event zone)
   lastDay  = floor((end.dateTime − 1 ns) to date in event zone)
   ```
   Subtracting one nanosecond before flooring is what makes "ends exactly at midnight" stop on the previous day, which matches §3.4.
2. Set:
   ```
   allDay     = true
   start.date = firstDay
   end.date   = lastDay + 1 day        // exclusive
   timeZone   = absent
   ```
3. Discard the original wall-clock and zone fields.
4. Validate against §4 (R-2 holds because `lastDay + 1 day > firstDay`).

### 6.3 Worked examples

Single-day timed event:

```
allDay = false
timeZone = Africa/Casablanca
start.dateTime = 2026-04-16T09:00
end.dateTime   = 2026-04-16T17:00
```

Becomes:

```
allDay = true
start.date = 2026-04-16
end.date   = 2026-04-17       // inclusive: Apr 16
```

Midnight-crossing timed event:

```
allDay = false
timeZone = Africa/Casablanca
start.dateTime = 2026-04-16T23:00
end.dateTime   = 2026-04-17T01:00
```

Becomes:

```
allDay = true
start.date = 2026-04-16
end.date   = 2026-04-18       // inclusive: Apr 16 and Apr 17
```

The conversion expands across every civil day the original interval touched.

Exact-midnight end (no spillover):

```
allDay = false
timeZone = Africa/Casablanca
start.dateTime = 2026-04-16T08:00
end.dateTime   = 2026-04-17T00:00
```

Becomes:

```
allDay = true
start.date = 2026-04-16
end.date   = 2026-04-17       // inclusive: Apr 16 only
```

The "subtract 1 ns before flooring" rule is what produces this result — without it, the conversion would wrongly include Apr 17.

### 6.4 Confirmation requirement

Both conversions are **destructive**: the model loses information that cannot be reconstructed (clock time on timed → all-day; zone on either direction). Conversions MUST be explicit user actions. The data layer MUST NOT auto-convert on its own.
