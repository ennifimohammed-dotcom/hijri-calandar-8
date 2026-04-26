# Event Recurrence — Specification

Builds on `event_model.md` and `event_time_behavior.md`. Strictly scoped
to recurrence semantics: single events, recurring patterns, exceptions,
and edit-scope rules.

Out of scope: notifications, UI.

---

## 1. Single (one-time) events

### 1.1 Definition

An event with `recurrence == null` (or `recurrence.frequency == none`).
It happens exactly once, on the date(s) defined by its own `start` and
`end` fields.

### 1.2 Rules

- A single event has exactly **one occurrence**, identified by the event
  itself. There is no "first occurrence" abstraction; the event *is* the
  occurrence.
- Editing a single event mutates the event in place. There is no notion
  of "this and following" because there is nothing following.
- Deleting a single event removes it entirely.
- A single all-day event obeys §1 of `event_time_behavior.md` (exclusive
  end). A single timed event obeys §2..§3 of the same document.

### 1.3 Worked example

```
id            = "evt_001"
kind          = event
allDay        = true
start.date    = 2026-04-16
end.date      = 2026-04-17        // exclusive
recurrence    = null
```

Contributes one item to the calendar, on Apr 16. Editing it on Apr 16
edits the same row; there is no "this occurrence only" path.

---

## 2. Recurring events — concept

### 2.1 Master event vs occurrences

A recurring event is stored as **one master row**:

```
master = {
  id, kind, title, allDay, start, end,
  recurrence: RecurrenceRule,
  exceptions: ExceptionSet,
  ...
}
```

The master holds the **template**. Concrete occurrences are **derived**
on demand by applying the recurrence rule to `start` (and to `end`,
which gives each occurrence its duration). Occurrences are *not*
materialized in storage except when overridden (see §6).

### 2.2 Occurrence identity

Each occurrence is uniquely addressed by:

```
(master.id, originalStart)
```

`originalStart` is the occurrence's *scheduled* start as the rule would
produce it (the "RECURRENCE-ID" in RFC 5545). It is what makes
"the Apr 16 occurrence of weekly meeting" addressable even after the
user moves it to Apr 17.

### 2.3 Duration carries over

Every occurrence inherits the master's duration:

```
occurrence.start = <expanded by rule>
occurrence.end   = occurrence.start + (master.end − master.start)
```

This is computed on absolute instants for timed events, and on whole
days for all-day events.

---

## 3. Recurrence rule shape

```
RecurrenceRule {
  frequency : "daily" | "weekly" | "monthly" | "yearly" | "custom"
  interval  : integer ≥ 1                  // every N units
  byWeekday : Weekday[]?                   // weekly / custom
  byMonthDay: integer[]?                   // monthly / custom (1..31, -1 for last)
  byMonth   : integer[]?                   // yearly / custom (1..12)
  count     : integer?                     // total occurrences (incl. first)
  until     : LocalDate | LocalDateTime?   // last allowed start, inclusive
  weekStart : Weekday                      // default MO; affects weekly bucketing
}
```

Rules:

- `count` and `until` are mutually exclusive. At most one MAY be set.
- If neither is set, the rule is open-ended.
- `interval` defaults to 1.
- `byWeekday`, `byMonthDay`, `byMonth` are filters layered on top of the
  base frequency. `custom` is just the case where two or more filters
  are combined non-trivially.
- `weekStart` matters only for weekly recurrences with multiple
  `byWeekday` and `interval > 1`, to disambiguate which week each
  occurrence belongs to.

---

## 4. Recurrence frequencies

All examples assume `master.start` is `2026-04-16` (a Thursday) for
all-day, or `2026-04-16T09:00 Africa/Casablanca` for timed.

### 4.1 daily

`{ frequency: daily, interval: N }` produces an occurrence every `N` days.

| N  | Occurrence sequence (first 4) |
|----|-------------------------------|
| 1  | Apr 16, 17, 18, 19 …          |
| 2  | Apr 16, 18, 20, 22 …          |
| 7  | Apr 16, 23, 30, May 7 …       |

### 4.2 weekly

`{ frequency: weekly, interval: N, byWeekday: [...] }` produces
occurrences on the listed weekdays, every `N` weeks.

If `byWeekday` is empty, it defaults to the master's own weekday.

| Rule                                            | Sequence (first 4) |
|-------------------------------------------------|--------------------|
| `weekly, interval=1, byWeekday=[]`              | Apr 16 (Thu), 23, 30, May 7 |
| `weekly, interval=1, byWeekday=[MO, WE, FR]`    | Apr 17 (Fri), 20, 22, 24    |
| `weekly, interval=2, byWeekday=[MO, FR]`        | Apr 17, 20, May 1, 4        |

When a weekly rule lists weekdays that fall **before** `master.start`'s
weekday in the same week, those weekdays do not produce occurrences in
the master's first week — generation begins at `master.start` itself.

### 4.3 monthly

Two sub-modes:

1. **By day-of-month**: `{ frequency: monthly, byMonthDay: [16] }`
   → Apr 16, May 16, Jun 16 …
   - If a target month does not have the requested day (e.g. day=31 in
     February), the occurrence for that month is **skipped**, not
     coerced to the last day. Skipping preserves user intent.
   - `byMonthDay = [-1]` means "last day of the month" → Apr 30, May 31,
     Jun 30 …
2. **By weekday-of-month** (custom): combine `byWeekday` + ordinal hint
   in a custom rule, e.g. "third Thursday of every month".

`interval > 1` jumps months: `interval=2` → Apr, Jun, Aug …

### 4.4 yearly

`{ frequency: yearly, byMonth: [4], byMonthDay: [16] }` → Apr 16 every
year.

- Defaults: `byMonth = [master.start.month]`, `byMonthDay =
  [master.start.day]`.
- Feb 29 leap-year masters: skip non-leap years (consistent with §4.3
  skip rule).
- Interval > 1 jumps years.

### 4.5 custom

`custom` is the combinatorial form. It composes `byWeekday`,
`byMonthDay`, and `byMonth` filters over a base frequency.

Examples:

- "Every weekday" → `weekly, byWeekday=[MO, TU, WE, TH, FR]`.
- "First Monday of every month" → `monthly, byWeekday=[MO], setPos=[1]`
  (a `setPos` integer-array filter selects the Nth match within the
  base period; only required for the custom mode).

`custom` MUST NOT be used as a fallback for unknown frequencies. The
parser MUST reject anything it doesn't recognize.

---

## 5. Bounds: count and until

### 5.1 `count`

`count = N` means the rule produces at most `N` occurrences total,
**including** the first one (the master itself).

```
{ frequency: daily, interval: 1, count: 3 }
master.start = 2026-04-16
→ Apr 16, Apr 17, Apr 18    (3 occurrences, then stop)
```

### 5.2 `until`

`until = D` means the rule produces every occurrence whose start is
**less than or equal to** `D`. For timed rules, `until` is compared on
the absolute instant resolved in the master's zone.

```
{ frequency: weekly, interval: 1, until: 2026-05-07 }
master.start = 2026-04-16 (Thu)
→ Apr 16, 23, 30, May 7    (May 7 included because ≤ until)
```

### 5.3 No bound

If both `count` and `until` are absent, the rule is open-ended. Storage
and queries MUST handle that case. Materialization is always done over
a bounded query window — never "all future".

---

## 6. Exceptions

The master event holds an `exceptions` set. There are three exception
kinds; each is keyed by `originalStart`.

### 6.1 EXDATE — cancelled occurrence

```
ExceptionSet.cancelled : Set<originalStart>
```

The user opens an occurrence and chooses *Delete this occurrence*.
That occurrence's `originalStart` is added to the cancelled set. Future
expansion skips it.

### 6.2 OVERRIDE — modified occurrence

```
ExceptionSet.overrides : Map<originalStart, OccurrenceOverride>

OccurrenceOverride {
  start?, end?              // moved in time (still respect §2.3 if both omitted)
  title?, description?, location?, color?, allDay?
  // any field of the master that may differ for this single occurrence
}
```

The user opens an occurrence and chooses *Edit this occurrence only*.
A row is added to `overrides` keyed by the occurrence's `originalStart`.
Future expansion produces the modified version for that
`originalStart`, leaving every other occurrence untouched.

`originalStart` is **not** changed when the user moves an occurrence in
time. The override's `start` field carries the new time; the
`originalStart` key still points to the rule-derived slot. This is what
allows the user to later move it again — or revert.

### 6.3 SPLIT — "this and following"

The user chooses *Edit this and following occurrences*. The model:

1. Truncates the master rule with `until = (originalStart − 1 unit)` so
   the master no longer produces occurrences from `originalStart`
   onward.
2. Creates a new master event with `start = originalStart`, copying the
   recurrence rule (and any `count` becomes the remaining count) with
   the user's edits applied.
3. Carries forward the original master's exceptions whose
   `originalStart ≥ split point` to the new master.
4. The new master gets its own `id`. Occurrences before the split keep
   pointing at the old master.

This avoids touching every occurrence individually and keeps both halves
addressable as discrete master events.

---

## 7. Editing scope rules

When the user edits an occurrence, the model MUST ask which scope:

| Scope                  | Effect                                                                              |
|------------------------|-------------------------------------------------------------------------------------|
| This occurrence        | Add/replace an entry in `overrides` keyed by `originalStart`.                       |
| This and following     | Apply the SPLIT procedure of §6.3. Past occurrences untouched.                      |
| All occurrences        | Mutate the master event itself. Existing exceptions are kept unless they conflict.  |

Conflict handling for "All occurrences":

- If the user changes `recurrence` (e.g. weekly → daily), all existing
  `cancelled` and `overrides` entries become orphaned (their
  `originalStart` is no longer produced by the new rule). Orphans MUST
  be either dropped or converted to single events keyed by their last
  known `start`. The model MUST surface this and ask the user.
- If the user changes `start` time only, override entries are
  re-anchored: each override's `originalStart` shifts by the same delta
  applied to the master.

Editing scope rules apply identically to all-day and timed recurring
events; they make no assumption about `allDay`.

---

## 8. Deletion scope rules

Symmetrical to §7:

| Scope               | Effect                                                                  |
|---------------------|-------------------------------------------------------------------------|
| This occurrence     | Add `originalStart` to `cancelled`. Master and other occurrences kept.  |
| This and following  | Truncate master with `until = originalStart − 1 unit`. No new master.   |
| All occurrences     | Delete the master row entirely; occurrences disappear from queries.     |

A "this occurrence" deletion that also carries an existing override MUST
remove the override and add to `cancelled` in a single atomic write.

---

## 9. Querying recurring events

### 9.1 Materialization window

A query specifies a window `[from, to)` (half-open). The model:

1. Loads all master rows whose recurrence may overlap `[from, to)`.
   "May overlap" is a coarse pre-filter: `master.start < to` and
   (`until == null` or `until ≥ from`).
2. For each master, expands the rule within the window:
   - Walk occurrence dates by `frequency` × `interval`, applying
     `byWeekday` / `byMonthDay` / `byMonth` filters.
   - Stop when the next occurrence would exceed `to` or when `count` /
     `until` is exhausted.
3. For each produced occurrence:
   - If its `originalStart` is in `cancelled`, skip it.
   - If its `originalStart` is in `overrides`, yield the override-merged
     occurrence.
   - Otherwise yield the rule-derived occurrence.
4. For each timed occurrence, day-membership uses the half-open overlap
   test from `event_time_behavior.md` §3.3.

### 9.2 Performance constraints

- Generation MUST be capped (e.g. 500 occurrences per master per query)
  to defend against pathological rules.
- The model MUST NOT pre-materialize "all future" occurrences into
  storage. Only overrides and cancellations are persisted.

---

## 10. Hard invariants (recurrence)

1. A master event has at most one `recurrence` rule.
2. `count` and `until` are never both set.
3. `interval ≥ 1` always.
4. Every entry in `cancelled` and `overrides` has an `originalStart` that
   the rule would actually produce. Orphan entries are forbidden in
   persisted state and MUST be cleaned up at write time.
5. An occurrence's identity `(master.id, originalStart)` is stable across
   moves — moving an occurrence updates the override's `start`, not the
   key.
6. SPLIT preserves the total set of occurrences: the union of (old
   master after truncation) ∪ (new master) is exactly the occurrences
   the original rule would have produced.
