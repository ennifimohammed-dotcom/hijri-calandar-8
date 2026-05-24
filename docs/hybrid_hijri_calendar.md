# Hybrid Hijri Calendar — Architecture

Scope: the Hijri-calendar engine only. The UI surfaces (calendar
grid, agenda, settings picker, transparency badge) consume what
this document describes; their internals are out of scope.

---

## 1. The problem

A "Hijri calendar" is not a single, globally agreed thing. Different
countries publish different official dates because the start of each
Hijri month follows local moon-sighting practice:

- 🇸🇦 Saudi Arabia, 🇦🇪 UAE, 🇶🇦 Qatar follow **Umm al-Qura** (an
  astronomical-table-based calendar, published years in advance).
- 🇲🇦 Morocco, 🇩🇿 Algeria follow their ministry of religious
  affairs, which historically delays the calendar by one day vs.
  Umm al-Qura because they require local naked-eye sighting.
- 🇪🇬 Egypt's Dar al-Iftaa, 🇹🇷 Türkiye's Diyanet, 🇮🇩 Indonesia's
  Kemenag, 🇵🇰 Pakistan's Ruet-e-Hilal each publish their own
  calendar.

A purely arithmetic Hijri converter (the kind used by `intl`'s
`HijriCalendar` and most other small Flutter packages) cannot match
all of these — it is, by definition, one fixed calendar.

The hybrid engine in this app picks the right calendar for the
user's country, falls back to local arithmetic when offline, and
lets the user override either choice manually. It does ALL of this
without requiring the developer to maintain a server or push
updates.

---

## 2. Architecture at a glance

```
┌─────────────────────────────────────────────────────────────┐
│  17 consumer sites (calendar grid, agenda, notifications,   │
│  recurrence engine, widget snapshots, search, converter)    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼  synchronous, unchanged signature
              ┌──────────────────────────────┐
              │  hijri_kernel.dart           │
              │    hijriFromGreg(g, offset)  │
              │    gregFromHijri(h, offset)  │
              └──────────────┬───────────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
       ┌────────────┐  ┌─────────────┐  ┌─────────────┐
       │ HijriCache │  │ HijriHybrid │  │ HijriDate   │
       │ in-memory  │  │ (refresh    │  │ arithmetic  │
       │  + disk    │  │  scheduler) │  │  engine     │
       └──────┬─────┘  └──────┬──────┘  └─────────────┘
              │               │
              └───┐       ┌───┘
                  ▼       ▼
              ┌────────────────────┐
              │ HijriApiService    │
              │ (AlAdhan REST)     │
              └────────────────────┘
```

### 2.1 Layered fallback

Every kernel call walks the fallback ladder, top to bottom:

1. **HijriCache (memory)** — O(1) `Map` lookup keyed by
   `(country, gYear, gMonth)`. Filled by `HijriHybrid.boot()`
   from SharedPreferences once at app start. **This is what the
   kernel hot path reads.**
2. **HijriCache (disk)** — `SharedPreferences` mirror of the
   memory map. Only read at boot; never blocks kernel calls.
3. **HijriDate.fromGregorian** — pure arithmetic, the same
   engine the app used pre-hybrid. Byte-identical to the old
   behaviour when invoked.

A cache miss never blocks: the kernel immediately returns the
arithmetic value AND fires a fire-and-forget AlAdhan refresh in
the background. The next conversion for that month will see the
fresh data.

### 2.2 Synchronous contract

`hijriFromGreg(g, offset)` and `gregFromHijri(h, offset)` are
**SYNCHRONOUS** by deliberate design. There are 17 call sites
across the provider, recurrence engine, notification scheduler,
home-screen widget snapshots, and four screens. Making them
async would force a rewrite of every consumer and would block
the calendar grid (42 cells per page) on I/O.

The hybrid layer hides its async work inside `HijriHybrid`:

- `boot()` is the one async entry point — called from
  `AppProvider.init()` before the first conversion.
- `scheduleRefresh()` enqueues network work via `Future.microtask`
  and never returns anything the kernel cares about.

---

## 3. Module breakdown

### `lib/utils/hijri_kernel.dart`

The single, authoritative public face. Two top-level functions:

```dart
HijriDate hijriFromGreg(DateTime g, int offset);
DateTime  gregFromHijri(HijriDate h, int offset);
```

Plus the `HijriHybrid` class for boot / country selection /
refresh:

```dart
HijriHybrid.boot();                 // hydrate cache from disk
HijriHybrid.setCountry(code, adj);  // retarget the cache
HijriHybrid.clearCountry();         // disable hybrid mode
HijriHybrid.scheduleRefresh(y, m);  // fire-and-forget AlAdhan fetch
HijriHybrid.forceRefresh(y, m);     // awaitable refresh for UI button
```

### `lib/services/hijri_api_service.dart`

Thin AlAdhan client. One public method:

```dart
HijriApiService.fetchGregorianMonth({
  required int gregorianYear,
  required int gregorianMonth,
  required String countryCode,
  int adjustment = 0,
}) -> Future<HijriMonthData?>
```

Returns `null` on ANY failure (network, status code, JSON parse,
missing field). The kernel treats `null` exactly like a cache
miss and falls through to arithmetic. **No exceptions ever leak
out of this service.**

Endpoint used:

```
GET https://api.aladhan.com/v1/gToHCalendar/{month}/{year}?adjustment={n}
```

No API key required. AlAdhan has been live since 2014.

### `lib/services/hijri_cache.dart`

Two-tier cache. Public API:

```dart
HijriCache.boot();                    // async, idempotent
HijriCache.lookup(country, y, m);     // SYNC, kernel hot path
HijriCache.lookupGregDay(...);        // SYNC convenience
HijriCache.store(HijriMonthData);     // memory-first, disk-second
HijriCache.isFresh(country, y, m);    // bool, no I/O
HijriCache.lastSyncFor(country);      // DateTime?, no I/O
HijriCache.prune();                   // drop hard-expired entries
HijriCache.clear();                   // wipe both tiers
```

Storage budget: ~1.5 KB per month per country.
TTL: 7 days = stale (refresh in background).
Hard expiry: 60 days = drop entry.

### `lib/services/country_detector.dart`

Best-effort ISO country resolver. One public method:

```dart
CountryDetector.detect({bool requestPermission = false})
  -> Future<String>  // always returns SOMETHING, never throws
```

Detection ladder:

1. GPS reverse-geocode (reuses the Qibla screen's geolocator +
   geocoding plugins — no new native deps).
2. Device locale country tag (`fr_MA` → `MA`).
3. Global `XX` fallback.

Total ceiling: 4 seconds. Never blocks the UI thread.

### `lib/data/hijri_countries.dart`

Static registry of 30 supported countries + 1 global fallback
(`XX`). Each entry binds an ISO 3166-1 code to:

- Localized country name (4 locales).
- Localized authority name (4 locales).
- Day-offset vs. AlAdhan's default Hijri output (`0` for most,
  `+1` for Maghreb).
- Unicode flag glyph.

Public lookups:

```dart
hijriCountryByCode(String code) -> HijriCountry  // falls back to XX
isHijriCountrySupported(String code) -> bool
```

---

## 4. Data flow walkthrough

### 4.1 Cold start, online

```
[App opens]
  │
  ▼
AppProvider.init()
  ├── _loadPrefs()              ← reads region, country_code, hybrid flag
  ├── HijriHybrid.boot()        ← hydrates cache from SharedPreferences
  ├── _syncHybridCountry()      ← pushes country into HijriHybrid
  └── _todayForRegion()         ← FIRST kernel call
        │
        ▼
hijri_kernel.hijriFromGreg(now, offset)
  ├── HijriHybrid.scheduleRefresh(gYear, gMonth)
  │     └── (background) HijriApiService.fetchGregorianMonth(...)
  │           └── HijriCache.store(...)
  │                 └── notifyListeners() in the next provider call
  │
  ├── HijriCache.lookupGregDay(country, gYear, gMonth, gDay)
  │     └── (cache miss on cold start — empty cache)
  │
  └── HijriDate.fromGregorian(g.subtract(offset days))
        └── returns the ARITHMETIC value
              [UI renders with arithmetic value]

[~250 ms later, background fetch completes]
  └── Next conversion → cache hit → returns OFFICIAL value
```

### 4.2 Warm start, offline

```
[App opens]
  ├── HijriHybrid.boot()        ← loads ~13 months × 1.5 KB from disk
  └── First conversion
        ├── HijriCache.lookupGregDay() → HIT
        └── returns OFFICIAL Hijri immediately
```

### 4.3 User picks a different country

```
User: taps Settings → Hijri source → Egypt
  │
  ▼
AppProvider.setCountry('EG')
  ├── _countryCode = 'EG'
  ├── _region      = 'global' (no legacy code for Egypt)
  ├── _syncHybridCountry()    ← HijriHybrid retargets to EG
  ├── _today = _todayForRegion()
  ├── _savePrefs()
  ├── notifyListeners()
  └── _repo.rescheduleAllNotifications()

[Next render of any kernel-consuming widget]
  ├── HijriCache.lookup(EG, year, month) → MISS (first time)
  ├── Returns arithmetic
  └── HijriHybrid.scheduleRefresh(year, month) fires the EG fetch
```

### 4.4 User toggles "Use online calendar" OFF

```
User: flips toggle in Settings → Hijri source
  │
  ▼
AppProvider.setUseHybridHijri(false)
  ├── _useHybridHijri = false
  ├── _syncHybridCountry()
  │     └── HijriHybrid.clearCountry()   ← kernel forgets country
  ├── _today = _todayForRegion()
  └── notifyListeners()

[Every subsequent conversion]
  └── kernel: country is empty → skip cache → arithmetic fallback
     [Byte-identical to pre-hybrid app]
```

---

## 5. Adding a new country

1. **Pick the ISO 3166-1 alpha-2 code** (uppercase). AlAdhan uses
   the same codes.

2. **Append an entry to `kHijriCountries` in
   `lib/data/hijri_countries.dart`.** Required fields:

   ```dart
   HijriCountry(
     code: 'XX',                // ISO 3166-1 alpha-2
     flag: '🏳️',                // Unicode flag glyph
     name: {
       'ar': '…', 'fr': '…', 'en': '…', 'es': '…',
     },
     authority: {
       'ar': '…', 'fr': '…', 'en': '…', 'es': '…',
     },
     adjustment: 0,             // Days offset vs AlAdhan default.
                                // Usually 0; Maghreb is +1.
   ),
   ```

3. **No code changes needed elsewhere.** The picker reads
   `kHijriCountries`, the kernel reads the adjustment via
   `hijriCountryByCode(...)`, the auto-detector matches by ISO
   code via `isHijriCountrySupported(...)`.

4. **Verify** the country has an entry in AlAdhan's calendar API
   (it does for any country with a recognised religious
   authority).

---

## 6. Failure modes & guarantees

| Scenario                                | Behaviour                            |
|-----------------------------------------|--------------------------------------|
| No network, cold cache                  | Arithmetic fallback. Identical to pre-hybrid. |
| No network, warm cache                  | Cached official date. No degradation. |
| AlAdhan returns 5xx                     | Silent. Cache unchanged. Arithmetic fallback. |
| AlAdhan returns malformed JSON          | Silent. Cache unchanged. Arithmetic fallback. |
| Cache entry > 60 days old               | Dropped on next `boot()` or `prune()`. |
| User picks an unsupported ISO code      | Falls back to `XX` (global Umm al-Qura). |
| User toggles hybrid OFF                 | Kernel forgets country → arithmetic only. |
| User taps "Clear cache"                 | Both memory & disk wiped. Refresh on next render. |
| Country detection times out (4 s)       | Falls back to device locale, then to `XX`. |

The arithmetic fallback is always available. The app can never
end up "blank" because of a Hijri-engine failure.

---

## 7. Why these design choices

| Choice                                     | Why                                                                                  |
|--------------------------------------------|--------------------------------------------------------------------------------------|
| AlAdhan vs. our own server                 | Zero maintenance. They've been live since 2014. No costs to us.                      |
| Two-tier cache (memory + disk)             | Kernel must stay synchronous. Disk I/O is async.                                     |
| Static country list vs. fetched            | Country list is stable; the mapping rarely changes. Picker works fully offline.      |
| Country `adjustment` baked in vs. computed | Reflects historical practice; doesn't drift over time.                               |
| Fire-and-forget refresh                    | Avoids blocking the UI on background reconciliation.                                 |
| Coalesced refresh requests                 | A calendar grid renders 42 cells per page; we don't want 42 network calls in flight. |
| Always-on arithmetic fallback              | Guarantees the app works offline.                                                    |
| `setLocaleIdentifier` for place names      | Reuses the geocoding package the Qibla screen already pulls in. No new deps.         |
| Manual ±3 user override                    | Some users follow a different ministry than their country's default.                 |

---

## 8. Things explicitly NOT done

- **No background sync service.** Refreshes happen opportunistically
  when the user opens the app and a stale month is requested. A
  full WorkManager-style scheduler was deemed unnecessary for a
  calendar that the user opens at least monthly.

- **No moon-sighting committee feed.** Live sighting announcements
  ("the Egyptian committee just declared Eid for tomorrow") would
  need an API beyond AlAdhan's daily calendar. Out of scope for
  the current "zero-maintenance" goal.

- **No astronomical engine.** A pure-calculation crescent-visibility
  engine (Odeh / Yallop criteria) is not what most Muslim users
  treat as "shar'i". The hybrid takes the OFFICIAL date a country
  publishes, which already incorporates whatever balance of
  calculation and sighting that country's authority uses.

- **No native iOS support.** The Hijri kernel itself is pure Dart
  and works on iOS, but the app's build pipeline only ships
  Android APKs.
