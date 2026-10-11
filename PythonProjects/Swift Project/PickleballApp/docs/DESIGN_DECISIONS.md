# Pickleball Now: Design Decisions & Logic Reference

This is the long-form companion to [ARCHITECTURE.md](ARCHITECTURE.md). ARCHITECTURE.md gives the overview.
This document records **every architectural and logical decision in the code**, with the exact formulas,
thresholds and defaults, and the reason for each and its trade-off. When code and this document disagree,
the code wins. Please update this file in the same change.

**Where the numbers live:**
- Swift logic: `Packages/PickleCore/Sources/PickleCore/**`
- Server logic: `supabase/migrations/2026100800000{1..4}_*.sql`
- App wiring: `PickleballApp/**`

---

## Table of contents

1. [Product principles that shaped the code](#1-product-principles-that-shaped-the-code)
2. [System architecture decisions](#2-system-architecture-decisions)
3. [iOS app architecture](#3-ios-app-architecture)
4. [Data model decisions](#4-data-model-decisions)
5. [Security & trust boundary](#5-security--trust-boundary)
6. [Facility discovery, map loading & caching](#6-facility-discovery-map-loading--caching)
7. [Cold-start regional discovery](#7-cold-start-regional-discovery)
8. [Prediction V1 (wait estimation)](#8-prediction-v1-wait-estimation)
9. [Confidence model](#9-confidence-model)
10. [Weather & wind](#10-weather--wind)
11. [Recommendation engine (staged)](#11-recommendation-engine-staged)
12. [Best time to go](#12-best-time-to-go)
13. [Community reporting & minimal input](#13-community-reporting--minimal-input)
14. [Location verification & integrity](#14-location-verification--integrity)
15. [Facility verification, edits & negative information](#15-facility-verification-edits--negative-information)
16. [Duplicate detection](#16-duplicate-detection)
17. [Contributor system](#17-contributor-system)
18. [Visits (passive signals)](#18-visits-passive-signals)
19. [Privacy decisions](#19-privacy-decisions)
20. [Historical aggregation & retention](#20-historical-aggregation--retention)
21. [UI / UX decisions](#21-ui--ux-decisions)
22. [Cost decisions](#22-cost-decisions)
23. [Testing strategy](#23-testing-strategy)
24. [Known limitations & deliberate omissions](#24-known-limitations--deliberate-omissions)
25. [Tuning cheat-sheet (all constants)](#25-tuning-cheat-sheet-all-constants)

---

## 1. Product principles that shaped the code

| Principle | How it shows up in code |
|---|---|
| "Available court ≠ good destination" | Recommendations run in stages: Eligibility → Fit → Time to play → Cost (`RecommendationEngine`). An empty court can still be `unavailable` or `restricted`. |
| Trust beats false precision | Waits are always snapped to ranges (`WaitRange.snapped`). Confidence is High/Medium/Low, never a percentage. Each info block is tagged *Verified / Community estimate / LIVE / Usual pattern / Estimate* (`InfoKind`). |
| Useful before anyone contributes | Seeds, imports and a generic occupancy prior (`OccupancyPrior`) mean every facility gets an estimate on day one. |
| Infer first, ask rarely | `PromptPolicy` asks at most one context-chosen question per visit and skips when fresh high-confidence data exists. |
| Negative info travels faster | Closure-type reports become warnings after **one** credible report and exclusions after **two**. Positive existence confirmations accumulate slowly. |
| Cheap to run | Prediction runs on the device; queries use bounding boxes; caches sit everywhere; there's no realtime and no polling. |

---

## 2. System architecture decisions

### D1: Prediction math runs on-device in `PickleCore`; trust runs on the server
- **What:** The server returns *signals*: trust-weighted, anonymised observations plus aggregates. The device turns
  them into wait ranges, confidence and rankings.
- **Why:** Map panning costs nothing in compute. Predictions keep working from cached signals when offline. All the
  math lives in one deterministic, unit-tested Swift module.
- **Trade-off:** Server-side push alerts would need a port of `WaitPredictor`. It's about 300 lines of pure arithmetic
  with fixture tests, so the port is mechanical. The table `wait_predictions` is reserved for that.
- **Invariant:** The client never sees raw reports, reporter ids, reporter coordinates or integrity scores. It only sees
  `weight` (trust × integrity, rounded to 0.1) and `location_verified` per observation.

### D2: No Supabase Swift SDK
- A ~250-line `SupabaseClient` actor covers PostgREST RPC, anonymous sign-up, token refresh, Storage upload and
  Edge Function calls over `URLSession`.
- **Why:** There are no SPM dependencies to resolve, so the project builds offline, and the app uses only a small
  slice of the SDK.
- **Trade-off:** If Realtime is ever needed, adopt `supabase-swift` at that point.

### D3: Demo mode is a first-class backend
- If `SUPABASE_URL` or `SUPABASE_ANON_KEY` is empty, or the app is launched with `-uiTesting`, `AppEnvironment`
  wires in `DemoBackend`. That is an actor implementing all four repository protocols.
- It runs the same PickleCore rules the server mirrors, including duplicate detection and location checks, so
  every flow can be exercised without an account.
- A "Demo data" chip is always visible. Demo facilities are fictional, which avoids presenting made-up wait times
  for real parks.
- A single generator (`scripts/demo_facilities.py`) writes both `DemoFacilities.json` (bundled) and
  `supabase/seed.sql`, so demo and local-DB data can't drift apart.

### D4: Weather provider abstraction
- `WeatherProvider` protocol, implemented by `WeatherKitProvider` (production) and `OpenMeteoProvider` (fallback).
- WeatherKit needs the paid developer program, so it's off unless `USE_WEATHERKIT = YES`. If WeatherKit fails
  once, `ConditionsService` flags it and uses the fallback for the rest of the session.
- Open-Meteo isn't "another provider just for wind". It exists only because WeatherKit can't run on a free account.

### D5: Amenities are columns, not a table
- `has_lights`, `has_restrooms`, `has_water` and `has_parking` are boolean columns on `facilities`.
- Four fixed booleans don't justify an EAV table and an extra join on every map query.

### D6: Local Swift package for logic
- `PickleCore` has no UIKit, SwiftUI or MapKit, so `swift test` runs its 66 tests on macOS in well under a second.
- The app links it as a local package (an `XCLocalSwiftPackageReference` in the project file).

### D7: Xcode 16 synchronized folders
- The project uses `PBXFileSystemSynchronizedRootGroup`, so adding a file on disk adds it to the target without
  editing the project file.
- `Resources/Info.plist` is excluded from target membership through an exception set; it's the custom-keys plist
  merged with the generated one.

---

## 3. iOS app architecture

```
Views (SwiftUI)  →  small @Observable @MainActor ViewModels  →  Services  →  Repository protocols
                                                                              ├─ Supabase*Repository
                                                                              └─ DemoBackend
PickleCore (pure logic) is called from Services and ViewModels; never from Views directly for I/O.
```

| Decision | Detail |
|---|---|
| iOS 17 minimum | Needed for the Observation framework, SwiftUI MapKit (`Map`, `Annotation`, `onMapCameraChange`), `containerRelativeFrame` and `scrollTargetBehavior`. |
| Swift 5 language mode | Avoids strict-concurrency churn. Actors and `@MainActor` are still used deliberately, and the build has zero warnings. |
| Composition root | `AppEnvironment` builds everything once and injects it with `.environment`. Views never construct services. |
| Repositories as protocols | `FacilityRepository`, `ReportRepository`, `SubmissionRepository` and `ProfileRepository` make the Supabase/Demo swap and test doubles trivial. |
| Actors for shared caches | `SupabaseClient` (session refresh de-duplication), `FacilityService` (bbox cache), `TravelTimeService`, `ConditionsService` and `DemoBackend`. |
| Typed errors | `APIError` covers offline, timeout, unauthorized, rate-limited, invalid input, server, network, decoding and not-configured. `isConnectivity` drives offline fallbacks. |
| Resilient decoding | `ResilientEnum` decodes unknown server enum values to a fallback (`.unknown`) instead of failing the whole payload, so the backend can add cases without breaking shipped apps. |
| Wire format | Snake-case JSON; dates parsed from ISO-8601 with or without fractions and from Postgres `2026-10-10 08:00:00.123456+00` (`JSONCoding.parseDate` trims to 3 fractional digits). |
| Secrets | `Config/Base.xcconfig` → optional `Secrets.xcconfig` (git-ignored) → `Info.plist` keys → `AppConfig`. URLs use the `https:/$()/` trick because `//` starts a comment in xcconfig files. Only the public anon key ever ships. |
| Production flag | `AppConfig.isProduction` is `!DEBUG`. It controls whether simulated GPS is down-weighted on the client mirror, and whether "pretend I'm here" exists outside demo mode. |

---

## 4. Data model decisions

### 4.1 Layer separation (tables)
| Layer | Tables | Why separate |
|---|---|---|
| Stable facts | `facilities`, `facility_sources`, `facility_hours`, `facility_rules`, `facility_access`, `facility_costs` | They change rarely and are verified independently. |
| Contributions | `facility_submissions`, `facility_confirmations`, `facility_edit_suggestions`, `facility_photos`, `facility_issue_reports` | Each is an audit trail; facts are derived from them. |
| Temporary state | `facility_blackouts`, `facility_operational_overrides` | They have explicit start and expiry times, so they can't silently become permanent facts. |
| Observations | `occupancy_reports`, `paddle_stack_reports`, `surface_reports`, `skill_observations`, `play_culture_observations`, `visits` | High volume, decaying relevance, aggregated later. |
| Derived | `occupancy_aggregates`, `session_duration_aggregates`, `wait_predictions`, `weather_snapshots` | Rebuildable from raw data. |
| Control | `profiles`, `contributor_status`, `report_prompt_state`, `app_config`, `region_coverage`, `private.*` | Server-controlled behaviour. |

### 4.2 Key modelling choices
- **The facility is the map object.** There's one marker per facility, never one per court. OSM imports cluster
  adjacent pitches within 80 m into one facility.
- **Court counts:** `total_physical_courts` and `default_pickleball_courts` are *stable facts*. *Current* usable
  courts are an operational override (`kind = 'usable_courts'`) with an expiry and a confidence.
- **Court type enum:** `dedicated_pickleball`, `pickleball_lined_tennis`, `convertible_tennis`, `multi_use`,
  `mixed_facility`, `unknown`. Converted tennis courts are first-class.
- **Access is not a boolean.** There are 11 access types plus free-text notes. Only `public_walk_on`,
  `public_reservation`, `public_permit_required`, `day_pass_available`, `school_restricted` and `unknown` count as
  open to ordinary players (`AccessType.isOpenToOrdinaryPlayers`). Users can mark "I'm a member/resident here",
  which makes a restricted facility eligible for them only.
- **Existence vs access verification:** `facilities.existence_status/confidence` and
  `facility_access.verification_status/confidence` are separate state machines.
- **Cost:** `cost_type` is one of free, paid, day_pass, reservation_fee, membership or unknown, with
  `day_pass_price`, `reservation_fee`, `pricing_notes` and `last_verified_at`. Pricing is community-editable
  and time-stamped.
- **Enums are `text` with CHECK constraints, not Postgres ENUM types.** Adding a value is a one-line migration with
  no type rewrite, and the client tolerates unknown values (`ResilientEnum`).
- **Derived columns kept by a trigger** (`latitude`, `longitude`, `geohash4`, `name_normalized`). A trigger is more
  portable than generated columns built from PostGIS casts.
- **Indexes:** GiST on `location`; trigram GIN on `name_normalized` and `lower(city)`; B-tree on `geohash4`,
  `postal_code`, and `(facility_id, reported_at desc)` / `(user_id, reported_at desc)` on every observation table.
- **Day of week follows Postgres `extract(dow)`:** 0 = Sunday. Buckets are 30 minutes, numbered 0–47 from local midnight.

---

## 5. Security & trust boundary

| Rule | Implementation |
|---|---|
| Clients may **read** public facility facts | RLS `select` policies for `anon` and `authenticated` on facilities, access, costs, hours, rules, blackouts (not rejected), overrides and aggregates. `pending` facilities are visible only to their creator. |
| Clients may **never write tables directly** | `revoke insert, update, delete on all tables … from anon, authenticated`. The only exception is the user's own `report_prompt_state`. |
| All writes go through validated RPCs | `SECURITY DEFINER` functions with `set search_path = public, extensions, pg_temp`. Each one checks types, ranges, coordinates, rate limits and cooldowns. |
| Server-only fields | `trust_weight`, `integrity_score`, `verification_status`, `existence_status`, contributor entitlement and admin status are never accepted from the client. Admins live in `private.app_admins`, a schema PostgREST doesn't expose. |
| Raw observations are private | Observation tables have RLS enabled with no policies, so they're reachable only through aggregated RPC output. |
| Function grants | Execute is revoked from everyone, then granted narrowly. Reads go to `anon, authenticated`; writes to `authenticated`; `import_facility`, `region_claim_import` and `region_finish_import` go to `service_role` only. |
| Storage | The `facility-photos` bucket is private, with a 3 MB limit and JPEG/PNG/HEIC only. Uploads must go into `{auth.uid()}/…`. Reads are allowed for the owner or for photos marked `approved`. Owners can delete only unapproved photos. `register_photo` also checks the path regex and that the object exists. |
| Service key | Never in the app. It's used only by the edge function (injected by Supabase) and by `scripts/import_facilities.mjs` run from a trusted machine. |
| Coordinate sanity | `private.valid_point` rejects out-of-range, NaN and (0,0). The client's `GeoPoint.isValid` mirrors it. |
| Bounding-box cost guard | `nearby_facilities` rejects boxes over 3° on either side and caps results at 300 (default 150, app asks for 200). |

---

## 6. Facility discovery, map loading & caching

1. `onMapCameraChange(frequency: .onEnd)` fires only after the camera settles, never during a pan.
2. `MapViewModel.cameraChanged` **debounces for 350 ms**.
3. If the visible span is over **2.5°**, the state becomes `.zoomedOut` ("Zoom in or search") and nothing is fetched.
4. `FacilityService.facilities(visible:)`:
   - **Cache hit:** the visible box is inside the last fetched box, the fetch is under **120 s** old, and the
     visible latitude span is over **15 %** of the fetched span. Zooming far in forces a refetch so the dataset
     stays relevant. A hit returns cached facilities filtered to the visible box padded by 10 %.
   - **Miss:** fetch the visible box **padded by 25 % on each side** (1.5× span), clamped to 2.9°.
   - **Offline:** fall back to the in-memory snapshot, then to the last saved list on disk (`facility_cache.json`).
     The UI shows "Offline — tap to retry".
5. Ranking (`recompute`) is synchronous and makes no network calls. It runs immediately after the fetch.
6. **Refinement runs after first paint:** weather for at most **4** cells and routed ETAs for the top **6**
   candidates. Afterwards the app **always** re-ranks once. An earlier, cancelled refinement may already have
   filled the caches, so checking whether anything changed would miss the update.
7. The app also re-ranks when the user moves **≥ 300 m**, because travel times change.
8. **Clustering:** a grid in coordinate space with ~7 cells across the visible longitude and latitude cells of
   `span / (7 × 1.6)`. It's deterministic, so cluster ids (joined member ids) are stable for animation. Tapping a
   cluster zooms to a third of the current span.

**Travel time (`TravelTimeService`):**
- Straight-line estimate: `minutes = (meters × 1.35) / 1609.34 / 28 mph × 60 + 3`, with labels prefixed "~".
- Routed ETA: `MKDirections.calculateETA` plus 2 minutes for parking. Cached **10 min**, keyed by facility and the
  origin's geohash-6 (~1.2 km × 0.6 km), so small movements reuse the cache.
- Why only the top 6: Apple throttles directions requests, and only the candidates you might actually pick need
  precise times.

**Search:** server-side `search_facilities` uses trigram similarity on the normalized name, exact postal code
(score 1.0), and exact city (score 0.9), ordered by score then distance. It returns at most 20 results and
needs 2–100 characters. Places and ZIP codes come from `MKLocalSearchCompleter`. Neither path needs location
permission.

---

## 7. Cold-start regional discovery

- **Trigger:** the client calls the `region-discovery` Edge Function only when a non-zoomed-out query returns **zero**
  facilities. It never fires on ordinary map pans.
- **Client throttle:** once per **geohash-4 cell** (~39 × 20 km) per **24 h**, persisted on disk.
- **Server decision** (`region_claim_import`, which row-locks the coverage row):
  | Condition | Action |
  |---|---|
  | `imported` within **30 days** | `fresh`: serve the cached DB, no external call |
  | `importing` started within **10 min** | `busy` |
  | `next_eligible_at` in the future (failed imports back off **6 h**) | `deferred` |
  | ≥ **20** imports started in the last hour (global budget) | `deferred` for 15 min |
  | otherwise | mark `importing`, log, return `import` |
- **Source:** the Overpass query `nwr["sport"~"pickleball"](bbox); out center tags;` with a 30 s timeout.
  Swappable by setting `OVERPASS_URL`, or replaceable with scheduled OSM extracts, without client changes.
- **Normalization** (`normalize.ts`):
  - Clusters elements within 80 m.
  - `courts` comes from the `courts` tag, else the number of `leisure=pitch` elements.
  - `sport` containing `tennis` → `pickleball_lined_tennis`; pickleball alone → `dedicated_pickleball`; else `multi_use`.
  - `indoor=yes`, a `building`, or a sports centre → indoor.
  - Access mapping: `private` → private; customers/members → `membership_required`; yes/public → `public_walk_on`.
  - `fee` → paid or free.
  - Imported facilities start as `partially_verified` with confidence 0.55.
- **Dedupe on import** (`import_facility`):
  1. Same `(source, external_id)` → *update* but only **fill gaps**; never overwrite community-maintained values.
  2. Else the nearest facility within 250 m that is within 60 m, or has a name trigram similarity ≥ 0.45 → *merge*
     (attach the source and add +0.1 existence confidence).
  3. Else *insert*.

---

## 8. Prediction V1 (wait estimation)

No LLM, no neural network: just an explainable statistical blend (`WaitPredictor`).

### 8.1 Usable courts
1. The newest active `usable_courts` override with confidence ≥ **0.5** (source `reported`).
2. Else `default_pickleball_courts` (`configured`).
3. Else `total_physical_courts` (`physical`).
4. Else **2**, with source `assumed`; the UI shows "?".

Then subtract `courts_affected` of any **confirmed**, active partial blackout (for example, 2 courts held for a
lesson). If the result is 0, the raw wait becomes 60–120 and eligibility marks the facility unavailable.

### 8.2 Historical signal
- If the facility has a bucket with samples: `h = avg_occupancy`, `W_h = min(1.5, samples / 20)`.
- Otherwise the generic **population prior** (`OccupancyPrior`) with `W_h = 0.3`. The prior is a sum of Gaussian
  bumps:
  - Weekdays: 0.08 base, morning 9:00 (0.45), lunch 12:30 (0.10), evening 18:30 (0.70).
  - Weekends: 0.10 base, 10:30 (0.60), 15:00 (0.35), 18:30 (0.20).
  - Clamped to 0.03 before 6:00 and from 22:00; ×1.1 for indoor facilities.
  - It is always reported as low confidence.
- **Weather demand multiplier applies to the historical part only**, because live observations already reflect
  today's weather. Multipliers: rain likely ×0.4, very windy ×0.7, windy ×0.85, extreme heat ×0.75 (they combine).
- Implied historical queue: `max(0, h − 0.85) × 4` groups per court.

### 8.3 Live signal
- Observations older than **180 min** are ignored.
- Each weight is `w_i = server_weight × exp(−λ·age)` with `λ = ln 2 / 25 min`, so the **half-life is 25 minutes**.
  A 3-minute-old report keeps ~92 % of its weight; a 2-hour-old one keeps ~4 %.
- One-tap status maps to occupancy and queue (groups per court):

  | Status | Occupancy | Queue per court |
  |---|---|---|
  | Courts open | 0.45 | 0 |
  | Mostly full | 0.85 | 0 |
  | All full | 1.00 | 0.25 |
  | Players waiting | 1.00 | 1.00 |

- Optional precise values override this: `occupied_courts / usable` (capped at 1) and `groups_waiting / usable`.
- Paddle-stack observations produce a weighted paddle count.

### 8.4 Blend
```
occ   = (h·W_h + Σ w_i·occ_i) / (W_h + Σ w_i)
queue = (q_h·W_h + Σ w_i·q_i) / (W_h + Σ w_i)
```
**Basis label:**
- `live` if live weight > 2 × `W_h`
- `blended` if any live weight
- `prior` if no facility history
- otherwise `historical`

### 8.5 Wait formulas
**Rotation systems** (paddle stack, rotation board, organized open play):
```
paddles      = observed weighted paddles  OR  queue × usable × 4
if paddles < 1 and occ < 0.9:  raw = 0–4 min
games_ahead  = paddles / (4 × usable)           # 4 players per doubles game
raw_low      = max(0, games_ahead − 0.5) × g × 0.8
raw_high     = (games_ahead + 0.5) × g × 1.25    # g = typical_game_minutes or 13
```
**Stay-until-finished / reservation:**
```
if occ < 0.9:  raw = 0 … 5·max(0.2, occ)
else:          factor = (queue·usable + 1) / (usable + 1)      # residual-life approximation
               raw = factor × session_p25 … factor × session_p75
```
The default session distribution is median 60 / p25 40 / p75 90 minutes. Real values come from
`session_duration_aggregates`, used only with ≥ 10 samples.

The **"full" threshold is 0.9**, not 1.0. Blending even weak prior weight with "all full" reports lands just
below 1.0, which would otherwise wrongly report "0–5 min" for a full facility. A unit test caught this.

### 8.6 Honest range snapping
The raw midpoint selects a bucket:

| midpoint < | 4 | 10 | 15 | 22 | 32 | 40 | 55 | ∞ |
|---|---|---|---|---|---|---|---|---|
| range | 0–5 | 5–15 | 10–20 | 15–30 | 20–40 | 30–45 | 45–60 | 60+ |

**Low confidence widens** the range to the next bucket's upper bound (for example, 5–15 becomes 5–20). For
arithmetic, an open-ended "60+" uses midpoint +20 and high +30.

### 8.7 Busy level (used for map status)
- queue/court ≥ 0.5 → **very busy**
- occ ≥ 0.9 → **busy**
- occ ≥ 0.7 → **moderate**
- otherwise **likely available**

A facility on the generic prior with no live data shows **"No recent info"** rather than a guess.

---

## 9. Confidence model

```
live_evidence = Σw × agreement × (0.5 + 0.5 × verified_share)
history       = min(1, samples / 30)
config        = 0.2 if usable courts are reported or configured
score         = live_evidence + history + config
```
- `agreement = 1 − 2 × weighted std-dev(occupancy values)`, clamped to 0…1. It's 1 when there's only one observation.
- `fresh` counts observations no older than 30 min with server weight ≥ 0.3.
- **Levels:**
  - Generic prior with live weight < 0.5 → **Low**, always.
  - **High** needs score ≥ 2.0, ≥ 2 fresh observations, and agreement ≥ 0.6.
  - **Medium** needs score ≥ 0.8.
  - Otherwise **Low**.
- Confidence feeds ranking (§11) as an *uncertainty penalty*, so one low-confidence short wait can't dominate.

---

## 10. Weather & wind

- **Effective wind** = `max(sustained, gust × 0.75)`.
- **Categories** are configurable (`WindThresholds`): Calm < 8 mph ≤ Breezy < 13 ≤ Windy < 20 ≤ Very windy. No single
  universal "unplayable" threshold exists; windy and very windy affect ranking and labels, not eligibility.
- **Flags:**
  - Rain likely: next-hour precipitation chance ≥ 60 %.
  - Recent rain: ≥ 0.5 mm in the last 3 hours.
  - Extreme heat: apparent temperature ≥ 95 °F.
  - Cold: ≤ 38 °F.
  - Dark: not daylight.
- **Impact:** rain likely or very windy is *significant*; recent rain, windy, heat or cold is *minor*. The first
  matching headline is shown, e.g. "Wind may noticeably affect play".
- **Direct observations beat forecasts:** a surface report under 3 hours old overrides rain-based warnings.
  Weather alone never makes a facility ineligible, except darkness at unlit outdoor courts.
- **Caching:** per geohash-5 cell (~5 × 5 km) for 15 min, with in-flight requests de-duplicated. Indoor
  facilities skip weather entirely.

---

## 11. Recommendation engine (staged)

### Stage A: Eligibility (`EligibilityEvaluator`), evaluated in this order
1. `existence_status` closed or rejected → **unavailable** "Confirmed closed".
2. Active **confirmed** whole-facility blackout (verified, or confidence ≥ 0.7) → **unavailable**, e.g.
   "Tournament — public play unavailable until 6 PM". An unconfirmed blackout is only a warning.
3. Active negative override: if credible (verified, confidence ≥ 0.6, or ≥ 2 reports) → **unavailable**, worded
   "Multiple recent reports: …" when it comes from multiple reporters. Otherwise it's a warning.
4. Hours known and closed now → **unavailable** "Closed — opens 7 AM". The next opening is searched up to 7 days ahead.
5. Outdoor, no lights, and dark → **unavailable**.
6. Surface report ≤ 180 min old: unplayable (wet, standing water, ice/snow, construction, unsafe) with
   confidence ≥ 0.4 → **unavailable** "Courts currently wet". Degraded (damp, debris) → warning. With no recent
   surface report, rain flags become warnings.
7. Usable courts = 0 → **unavailable**.
8. Access type not open to ordinary players and the user hasn't marked access → **restricted**, showing the
   facility's access note.
9. Permit or reservation required → warnings.

Unavailable and restricted facilities are **never picks**. They still appear on the map with their reason.

### Stage B: Player fit (`PlayerFitEvaluator`), always soft
- Needs at least **3** skill observations.
- The typical range is the central 70 % (15th–85th weighted percentile) of the band distribution.
- **Skill summary confidence:**
  - High: ≥ 20 observations and the newest within 60 days.
  - Medium: ≥ 6 observations within 60 days.
  - Otherwise Low.
- **Fit:**
  - User band inside the range → *great* (confidence ≥ medium) or *good*.
  - One band outside → *stretch*.
  - Further → *mismatch*.
  - With a trade-off line: "Play here tends to be stronger (4.0–4.5+)" or "…more casual".
- **Penalty in minutes:** great/good 0, unknown 3, stretch 8, mismatch 18.
  - Beginner or wants-beginner-friendly users: −4 if the facility is beginner-friendly, +5 if it's competitive.
  - Users who like competitive play: −3 at competitive facilities.
  - Halved when the skill estimate is low-confidence.
- Age demographics are deliberately **not** used.

### Stage C: Time to play
`time_to_play = travel + wait.low … travel + wait.effectiveHigh`, labelled "Estimated playing in 14–24 min".

### Stage D: Cost & access
| Cost type | Fit | Penalty (min-equivalent) |
|---|---|---|
| free | Free | 0 |
| day pass / reservation fee / paid | Paid($) | price × 0.3 (include paid) or × 0.5 (no preference); unknown price uses $12 |
| membership | Membership | 10 |
| unknown | Cost unknown | 4 |
| any non-free when user chose **Free only** | outside preference | 60, and never picked |

### Ranking: explainable components, not an opaque score
`total = travel + wait_midpoint + uncertainty + fit_penalty + cost_penalty + conditions`

| Component | Rule |
|---|---|
| Uncertainty | High 0 · Medium 0.15 × wait midpoint · Low 0.4 × wait midpoint + 5 |
| Conditions | +15 significant weather · +5 minor · +8 if a degraded-surface warning |

Every component is kept as a named `ScoreComponent`, so the UI can explain any ordering.

### Labelled picks (trade-offs, not one winner)
| Badge | Rule |
|---|---|
| BEST MATCH | lowest `total` |
| FASTEST TO PLAY | lowest `time_to_play.mid + uncertainty` |
| BEST FREE OPTION | lowest `total` among free facilities |
| RESERVABLE OPTION | lowest `total` among non-free facilities with reservations (skipped for Free-only users) |

A facility can earn several badges; each facility appears once in the strip. **Sort modes:**
- Best overall: `total`
- Fastest to play: `ttp.mid + uncertainty`
- Closest: distance
- Shortest wait: `wait.mid + uncertainty`
- Best skill match: fit, then total
- Most courts: usable courts

**Explanation text** is built from the stages: fit headline, cost sentence ("Free public access." or "Requires a
$15 fee."), then time to play. Ineligible facilities show only their reason.

---

## 12. Best time to go

`BestTimePlanner` builds a timeline of 30-minute slots from now until closing (or 6:00–22:00 if hours are unknown):

- **Occupancy:** the facility's bucket for that weekday if it exists, else the prior. The current live prediction
  is blended in with weight `1 − minutes_ahead / 90`, fading to zero after 90 minutes.
- **Levels:** < 0.6 Good · < 0.85 Moderate · < 1.0 Busy · ≥ 1.0 Very busy.
- **Overrides:**
  - A confirmed whole-facility blackout → Unavailable.
  - Outdoor and dark without lights → Unavailable.
  - Rain chance ≥ 60 % → Poor weather (+0.8 score).
  - Very windy → Poor weather (+0.4).
  - Windy → note (+0.15).
- **Best window:** the contiguous run of playable slots, 2 to 6 slots long (60–180 minutes), with the lowest average
  score. Ties within 0.05 prefer the earlier window, then the longer one.
- The UI labels the result "From this facility's usual pattern" (≥ 3 samples) or "General estimate — not enough
  history yet".

---

## 13. Community reporting & minimal input

### 13.1 One question, chosen by context (`PromptPolicy.chooseKind`)
1. Facility is community-reported and the user hasn't confirmed it → **"Is this court here?"** Yes/No.
2. Outdoor facility with no surface report in the last 90 min and recent or likely rain → **"Court surface?"**
   Dry/Damp/Wet/Debris.
3. A live report under 15 min old exists **and** confidence is High → **don't ask**.
4. Rotation facility → **"Paddle wait?"** None/Short/Medium/Long.
5. Otherwise → **"How busy is it?"** Courts open/Mostly full/All full/Players waiting.

### 13.2 Fatigue rules (`PromptPolicy.decide`)
| Rule | Default |
|---|---|
| Must be at the facility | arrival detected (§18) |
| One prompt per visit | tracked by `visitID` |
| Same facility cooldown after a report or a prompt | 3 h |
| Minimum gap between any two prompts | 20 min |
| 2 consecutive dismissals | 3-day backoff |
| 4 consecutive dismissals | 14-day backoff |
| Any answer (prompted or not) | resets dismissals and backoff |

All defaults live in `PromptPolicyConfig`. Server-side overrides are stored in `app_config.prompt_policy`, but the
app doesn't fetch them yet (§24).

### 13.3 Interaction design
- The prompt is a **non-modal card**. "Not now" is one tap, an answer is one tap, a haptic confirms, and "Thanks!"
  auto-hides after 1.6 s.
- "Report Status" in the sheet opens the same single question first. **"Add more detail (optional)"** appears
  only *after* a successful answer. It offers paddle count ranges (0, 1–4, 5–8, 9–12, 13–20, 20+), usable courts,
  typical level, and play-style tags; each sends independently.
- Typing is never needed for routine reporting. Text fields exist only for names, notes, prices, hours, and search.
- Paddle levels map to representative paddle counts: none 0, short 4, medium 9, long 16.

### 13.4 Server-side report rules (`submit_live_report`)
| Rule | Value |
|---|---|
| Rate limit | 12 contributions / hour / user (across all observation types) |
| Same facility + kind cooldown | 10 min ("too_soon") |
| Live kinds require location verification | occupancy, paddle stack, surface, usable courts |
| Expiry | occupancy 3 h · paddle 90 min · surface 4 h (24 h for construction/unsafe) · usable-courts override 4 h |
| Idempotency | `(user_id, client_report_id)` unique, so retries don't double-count |
| Usable-courts merge | same value: `c ← 1 − (1−c)(1 − 0.6·trust)`; different value replaces it with `0.6·trust` |
| What the client receives | `accepted`, `location_verified`, `insights_until`, and never trust or integrity |

Skill and culture observations don't need location verification; they're stored with lower trust if unverified.

---

## 14. Location verification & integrity

### 14.1 Location verification
- **Client pre-check** (`LocationVerifier`), which only enables the button:
  - Fix age ≤ 120 s.
  - Accuracy ≤ 150 m.
  - Distance ≤ **250 m + min(accuracy, 75 m)**.
  - Messages: "Live reports open when you're at the courts (2.3 mi away)", "Waiting for a more precise location…".
- **Server re-check** uses the same rule; the radius comes from `app_config.report_radius_m`. Confirmations use
  300 m and 300 s. **The server never trusts the client's verdict.**
- In demo or DEBUG builds, "Demo: pretend I'm here" sets `simulatedPresence`. The resulting fix is flagged
  `isSimulatedBySoftware`, so a production server would down-weight it.

### 14.2 Integrity score (internal, 0–1, never shown to users)
The score starts at 1 and is multiplied by each penalty that applies:

| Signal | Multiplier |
|---|---|
| Software-simulated location (production only) | × 0.2 |
| Accuracy > 65 m or missing | × 0.7 |
| Fix age > 60 s or missing | × 0.8 |
| Impossible travel: > 150 km/h from the previous report's facility (within 6 h) | × 0.25 |
| Burst: ≥ 4 contributions in 10 min | × 0.5 |
| > 3 distinct facilities in 1 h | × 0.5 |

### 14.3 Trust weight
`trust = (verified ? 1.0 : 0.25) × integrity × account_age_factor × contradiction_factor`

- Account age factor: 0.7 if the account is less than a day old.
- Contradiction factor (occupancy only): 0.7 if at least 2 reports in the last 15 min (each with trust ≥ 0.3)
  have a weighted-mean implied occupancy that differs from this report by more than 0.5.

Suspicious reports are **down-weighted silently**. Users are never accused, and the app never claims to stop
spoofing. `IntegrityRiskEvaluator` in PickleCore mirrors the server rules for tests and local diagnostics only.

---

## 15. Facility verification, edits & negative information

### 15.1 Existence verification (`recompute_existence`)
```
base       = 0.2 (community submissions) | 0.6 (imports/seeds)
confidence = clamp(base + 0.15·Σtrust(exists) − 0.2·Σtrust(not_exists), 0, 1)
```
| Transition | Requirement |
|---|---|
| pending → community_reported | ≥ 1 verified positive and no negatives |
| → partially_verified | ≥ 2 location-verified "exists" from distinct users |
| → verified | ≥ 4 location-verified "exists", facility older than 24 h, negatives < positives / 2 |
| → closed | moderator, or sustained corroboration (§15.3); never automatic from a single report |

- Submitters can't confirm their own facility.
- New submissions start `community_reported`, or `pending` (visible only to the submitter) if the account has
  ≥ 3 rejected submissions.
- Starting confidence is 0.35 if the submitter's own location was within 300 m of the pin (accuracy ≤ 150 m),
  otherwise 0.2.
- Submissions are limited to **5 per day** per user.

### 15.2 Negative information propagates faster
- Issue kinds: possible closure, temporarily unavailable, locked gates, construction, nets removed,
  pickleball prohibited, unsafe surface, tournament.
- Override confidence = `1 − exp(−0.7 × Σtrust)` over distinct recent reporters. One verified report gives ≈ 0.50,
  which shows a **warning**. Two give ≈ 0.75 (or `report_count ≥ 2`), which makes the facility **unavailable**.
- TTLs: tournament 12 h · locked gates 6 h · temporarily unavailable 24 h · unsafe surface 24 h ·
  pickleball prohibited 72 h · others 48 h. Expiry is measured from the latest report.
- **Asymmetric recovery:** a location-verified occupancy report halves the confidence of unverified
  possible-closure, temporarily-unavailable and locked-gates overrides, because people are evidently playing.
- "No, it's not here" on a confirmation also files a `possible_closure` issue.
- Issue rate limits: 6 per hour per user, and one per facility + kind per 6 h.

### 15.3 Sustained closure corroboration (`corroborate_closures`, every 30 min)
A facility becomes `closed` only if **≥ 4 distinct users** reported possible closure on **≥ 3 distinct days**
within **14 days** (trust ≥ 0.2), and no location-verified occupancy report has arrived since the first of those
reports.

### 15.4 Blackouts
- A dedicated `facility_blackouts` object (reason, start/end, description, source, verification, confidence,
  `courts_affected` with null meaning the whole facility).
- **Confirmed** whole-facility blackouts override wait prediction (eligibility = unavailable) and grey out
  best-time slots. Partial blackouts reduce usable courts. Unconfirmed blackouts only warn.
- The server returns blackouts that end in the future and start within the next 7 days.

### 15.5 Suggest an edit
- 14 edit types. Each has a minimal follow-up input (steppers, segmented pickers, toggles), with free text only
  for hours and notes.
- Identical proposals are merged: additional users become *supporters*. Support weight is 1.0 if location-verified,
  0.4 otherwise, × the account age factor.
- **Auto-apply** needs `supporters ≥ 2` (≥ 3 for access and cost changes) **and** support weight ≥ 1.5.
  - The applied changes are whitelisted per type.
  - A failed apply (for example, an invalid value hitting a CHECK constraint) marks the suggestion rejected
    instead of erroring.
  - Applying one suggestion supersedes other open suggestions of the same type.
- **High-impact types** (`permanently_closed`, `no_longer_pickleball`, `other`) never auto-apply. The first two also
  feed the fast negative-issue path.
- Limited to 20 edits per day per user.

---

## 16. Duplicate detection

**Client** (`DuplicateDetector`, instant "Is this one of these?"):
- **Normalization:**
  - Case and diacritic folding; punctuation becomes spaces.
  - Abbreviations expand: pk→park, ctr/cntr/centre→center, rec→recreation, st→street, ave→avenue, rd→road,
    hs/ms/es→high/middle/elementary school, comm→community, reg→regional, mt→mount.
  - Stop-words are dropped: the, of, at, and, court(s), pickleball, tennis, facility, complex.
- **Similarity:** a soft token Dice coefficient. Tokens match when their Jaro-Winkler similarity is ≥ 0.88, so
  "Hansen"/"Hanson" match. Whole-string Jaro-Winkler was rejected because it scored unrelated names like
  "Oak Ridge HOA" vs "Hanson Regional Park" ≥ 0.6. A test caught this.
- **A candidate is a duplicate if:**
  - it's ≤ 60 m away (any name), or
  - it's ≤ 250 m away and the name similarity is ≥ 0.6, the address matches, or no name was given, or
  - it's within 400 m and the name similarity is ≥ 0.85.
- Ranked by `0.5·(1 − d/400) + 0.5·similarity (+0.2 address match)`.

**Server** (`find_duplicate_facilities`, authoritative): the same distance rules with pg_trgm similarity thresholds
of 0.45 and 0.8. `submit_facility` repeats the check. **"No, it's a different court" is refused within 30 m**, so
there are never stacked markers for the same park. Choosing "Yes, this one" turns the submission into a
confirmation of the existing facility.

---

## 17. Contributor system

- No tokens and no points. A verified, useful contribution sets `insights_until = max(current, now + 7 days)`.
  The duration is configurable with `app_config.contributor_insights_days`.
- Contributions that qualify:
  - A live report with trust ≥ 0.4.
  - A location-verified issue or confirmation with trust ≥ 0.4.
  - A location-verified edit.
  - Any accepted facility submission.
- **Gating is server-controlled** (`app_config.live_gating_enabled`, default **false** during cold start). When it's
  on, non-contributors get `live = null`: they still see history-based estimates, confidence, best time and every
  facility fact, but not live observation detail.
- The app shows "Thanks for helping nearby players. Live court insights are available for the next 7 days." once,
  after the first unlocking contribution.

---

## 18. Visits (passive signals)

- **Foreground detection** (`VisitService`):
  - Arrival happens when a fix with accuracy ≤ 100 m stays within **150 m** of the nearest facility for **60 s**.
  - A **dwell timer** re-checks after 61 s, because a stationary phone gets no new fixes. A real bug found during
    simulator testing.
  - Departure happens beyond **350 m**.
- Arrival opens a new `visitID` and runs the prompt policy once. Departure uploads `{facility, arrival, departure,
  method, confidence}` **only if** the user turned on "Share anonymous visit timing" (off by default).
- `record_visit` validation:
  - Arrival time no more than 24 h in the past or 5 min in the future; departure after arrival; total under 10 h.
  - An open visit at the same facility (arrival within 10 min) is closed instead of duplicated.
  - The `region_monitoring` method is accepted only if the profile enabled passive visits.
- Session durations between 10 min and 5 h, over the last 180 days, feed `session_duration_aggregates`
  (median / p25 / p75), which drive the stay-until-finished wait model.
- Background geofencing is deliberately not built (§24).

---

## 19. Privacy decisions

| Decision | Detail |
|---|---|
| No account to browse | Reads use the anon key. An anonymous session is created lazily on the first contribution, stored in the Keychain (`AfterFirstUnlockThisDeviceOnly`, not synced), and can be upgraded later. |
| Reporter coordinates never stored | Report RPCs store `distance_m` and `accuracy_m` only. Submissions store the *court's* location, which is the point of the submission. |
| No GPS trails | The app holds only the current visit in memory. The device-side report history keeps facility + time for 24 h (used for the integrity mirror). |
| Foreground-only location | `requestWhenInUseAuthorization`; updates stop when the app goes to the background. "Always" permission is never requested. |
| Contextual permission | An explanation card comes first ("Use your location to find nearby courts and verify live court reports"). Choosing "Not now" never re-prompts; Profile has a quiet Settings link. Search, ZIP and map browsing work without permission. |
| Photos | Re-rendered into a fresh bitmap at ≤ 1600 px, JPEG quality 0.7, which drops all EXIF and GPS metadata. A test asserts there's no GPS dictionary. |
| Analytics | Allow-listed event names, a facility id, and ≤ 1 KB of properties. Timestamps are truncated to the minute. No user id, device id, IP or coordinates. Stored in the non-exposed `private` schema. |
| Retention | User links are removed from visits and archived observations after 120 days (§20). |

---

## 20. Historical aggregation & retention

**Scheduled with pg_cron** (only if it's available):

| Job | Schedule | What it does |
|---|---|---|
| `refresh_occupancy_aggregates` | daily 03:17 | Recomputes 30-min buckets per weekday from the last **120 days** of occupancy reports with trust ≥ 0.2. Occupancy comes from occupied/usable counts if present, else the status. Stores the trust-weighted mean, median, variance and sample count. Also rebuilds session-duration percentiles. |
| `archive_raw_observations` | Sundays 03:41 | Moves raw occupancy, paddle and surface reports older than 120 days into `private.observation_archive` as compact JSON with the user id removed. Unlinks users from old visits. Deletes overrides that expired more than 30 days ago and weather snapshots older than 2 days. |
| `corroborate_closures` | every 30 min | §15.3 |

Raw data is **archived, not blindly deleted**. The archive can be exported to Storage and pruned by an operator if
size ever matters. Aggregates are recomputable from the hot window plus the archive.

---

## 21. UI / UX decisions

- **The map is the home screen.** A full-screen MapKit map with POIs hidden to reduce clutter. Chrome: a search
  capsule and profile button at the top; status chips (Demo, active filters, loading/offline); a right-side stack
  (locate, filters with a count badge, add court); and one bottom slot.
- **The bottom slot shows one thing at a time**, in priority order: arrival prompt → location primer →
  empty/zoomed-out/error card → recommendation strip. The side controls hide while a prompt or primer card is
  showing, so they don't overlap.
- **Markers:**
  - A pickleball glyph in the status color with a white outline.
  - A status badge icon (✓ hourglass people ? drop lock calendar ✕), so status is **never color-only**.
  - A compact wait label ("5–15m").
  - A purple people badge for community-reported facilities.
  - A VoiceOver label like "Laurel Creek Park, Likely available, estimated wait 0–5 min".
- **Facility sheet** (detents at 52 % and large; the map stays interactive behind it), ordered by what decides
  "should I go?":
  1. Badges.
  2. Name, save and share.
  3. Status and travel.
  4. Ineligibility or warning banners.
  5. Community-reported banner.
  6. Fit.
  7. A wait / courts-usable card with confidence and an information-kind tag.
  8. Surface and wind.
  9. Access and cost.
  10. Directions (primary button), Court Details, Report Status.
- **Detail page** (progressive disclosure): Availability (with explanation bullets) → Busy times today (Swift
  Charts plus "Best time today") → Player fit → Access & cost (with an "I'm a member/resident" toggle) →
  Playability → Facility (hours and rules collapsed) → Keep this accurate (confirm, suggest edit, report a
  problem) → Data sources & verification (collapsed; existence vs access status; OSM attribution).
- **Accessibility:**
  - Large tap targets (choice tiles ≥ 92 pt tall, primary buttons 52 pt, controls 50 pt).
  - Whole-card taps.
  - Dynamic Type through text styles.
  - Combined accessibility elements and selected-state traits.
  - Semantic colors that adapt to dark mode (`Color(light:dark:)`).
- **Design language:** one restrained green accent (#1F7A5C / #4CC69A dark), semantic status colors, native
  materials, SF Symbols, rounded continuous corners, and haptics on answers and selections. Deliberately not
  "neon pickleball green everywhere".
- **Empty and error states:** "No known courts nearby. Know one we're missing? [Add a Court]", "Zoom in to see
  courts", "Couldn't load courts [Try again]", "Nothing playable right now", the offline chip, and "Turn on
  location for travel times".
- **Add Court:**
  - Pin-under-crosshair placement on a hybrid map, plus "My location" and address search.
  - Minimal step: court-count tiles, a type tile, indoor/outdoor, and an optional name.
  - Optional details step: lights, access, cost, rotation style, notes, photo.
  - Duplicate step, then a done screen showing the "Community-reported · Verification pending" pill.

---

## 22. Cost decisions

| Area | Decision | Effect |
|---|---|---|
| Backend | Supabase free tier first (500 MB DB, 1 GB storage); Pro at $25/month only when needed | ~$0 development and early production |
| Queries | Bounding boxes with GiST, padded client cache, settle + 350 ms debounce | About one RPC per real map move |
| Compute | Prediction runs on the device | No per-request server compute |
| Realtime | None; refresh on demand or after a report | No websocket cost |
| Directions | Routed ETAs for the top 6 only, cached 10 min | Within Apple's free throttles |
| Weather | ≤ 4 cells per refresh, cached 15 min | Free tiers suffice |
| Overpass | Server-side only, cell cache 30 days, ≤ 20 imports per hour | Polite and free; swappable |
| Storage | Photos ≤ 1600 px JPEG 0.7 (~250 KB) | Stays within the 1 GB free storage |
| Raw data | Aggregated nightly and archived at 120 days | The database stays small |

Paid services are introduced only with a stated reason, a cost, a cheaper alternative and the trade-off. None has
been needed so far. The $99/year Apple Developer Program is needed only for TestFlight, the App Store and
WeatherKit.

---

## 23. Testing strategy

| Layer | Tests | How to run |
|---|---|---|
| PickleCore | 66 unit tests: prediction, decay, range snapping, confidence, best time, eligibility, fit, recommendation picks and sorting, weather, duplicates, location verification, integrity, prompt policy, validation, geohash, clustering, decoding | `cd Packages/PickleCore && swift test` |
| App unit | 17 tests: DemoBackend flows, FacilityService caching, offline fallback, discovery throttle, filters, prompt flow integration, RPC null encoding, photo EXIF stripping | Xcode scheme `PickleballApp`, or `xcodebuild test` |
| UI | 4 tests: map → sheet → details; one-tap arrival prompt; add-court flow; search without location. They run against the demo backend at a fixed location with `-uiTesting`. | same |
| SQL | 14 behavioural blocks in `supabase/tests/rpc_test.sql`, run against real PostGIS 15 with a small stub for Supabase's auth and storage | `./scripts/validate_sql.sh` (Docker) |
| Edge function | Geohash correctness and OSM pitch clustering | `deno test` (see SETUP.md) |

**Bugs the tests or simulator runs caught,** each fixed and recorded above:
- The full-court threshold diluted by the prior (§8.5).
- Whole-string Jaro-Winkler being too lenient (§16).
- Weather never applied because a cancelled refinement had filled the cache (§6).
- No arrival prompt for stationary users (§18).
- Initial map centering missed a fix that arrived before the view subscribed (fixed with `onChange(…, initial: true)`).

---

## 24. Known limitations & deliberate omissions

- **Not validated against a live Supabase project.** The SQL was validated on PostGIS 15 with stubs for `auth.uid()`,
  roles and `storage`.
- **Background geofencing is not built.** It's foreground-only for now; the server already accepts `region_monitoring`.
- **No push notifications.** `wait_predictions` is reserved for server-side predictions that would power alerts.
- **No reservation or facility integrations, and no camera or sensor signals.**
- **No moderation UI.** Moderation is done with SQL (see SETUP.md).
- **Anonymous → email/Apple account upgrade is not wired in the UI yet.**
- **The client doesn't fetch `app_config` overrides yet.** The `prediction` and `prompt_policy` JSON exist
  server-side, but PickleCore uses compiled defaults. Fetching them is the next step for remote tuning.
- **WeatherKit is untested** without the paid entitlement.
- **Contributor gating** is wired end to end, but demo mode reports gating off.
- **Skill from passive signals isn't inferred.** Only explicit observations count.

---

## 25. Tuning cheat-sheet (all constants)

| Area | Constant | Default | Location |
|---|---|---|---|
| Prediction | live half-life | 25 min | `PredictionConfig.halfLifeMinutes` |
| | live max age | 180 min | `liveMaxAgeMinutes` |
| | history full weight / max weight | 20 samples / 1.5 | `historicalFullWeightSamples`, `historicalMaxWeight` |
| | prior weight | 0.3 | `priorWeight` |
| | default game / players per game | 13 min / 4 | `defaultGameMinutes`, `playersPerGame` |
| | usable-courts override min confidence | 0.5 | `usableCourtsOverrideMinConfidence` |
| | assumed courts | 2 | `assumedCourtsWhenUnknown` |
| | "full" threshold | 0.9 | `WaitPredictor` |
| | default session | 60 / 40 / 90 min | `SessionStats.default` |
| Weather | demand multipliers | rain 0.4 · very windy 0.7 · windy 0.85 · heat 0.75 | `PredictionConfig` |
| | wind thresholds | 8 / 13 / 20 mph, gust factor 0.75 | `WindThresholds` |
| | rain likely / recent rain / heat / cold | 60 % / 0.5 mm / 95 °F / 38 °F | `WeatherAssessor` |
| Confidence | High / Medium | score ≥ 2.0 + ≥ 2 fresh + agreement ≥ 0.6 / score ≥ 0.8 | `ConfidenceModel` |
| Eligibility | surface max age / min confidence | 180 min / 0.4 | `EligibilityEvaluator` |
| | negative override exclude confidence | 0.6 (or ≥ 2 reports) | `EligibilityEvaluator` |
| Fit | min observations | 3 | `PlayerFitEvaluator` |
| Prompts | facility cooldown / min gap | 3 h / 20 min | `PromptPolicyConfig` |
| | fresh live / fresh surface windows | 15 / 90 min | `PromptPolicyConfig` |
| | backoffs | 2 → 3 days, 4 → 14 days | `PromptPolicyConfig` |
| Location | radius + accuracy allowance | 250 m + ≤ 75 m | `LocationVerifier`, `app_config.report_radius_m` |
| | max accuracy / fix age | 150 m / 120 s | `LocationVerifier` |
| Visits | arrival radius / dwell / departure | 150 m / 60 s / 350 m | `VisitService` |
| Map | debounce / max span / cache TTL / padding | 350 ms / 2.5° / 120 s / 25 % per side | `MapViewModel`, `FacilityService` |
| | re-rank distance | 300 m | `MapViewModel.locationChanged` |
| Travel | detour / speed / overhead / routed count / cache | 1.35 / 28 mph / +3 min / 6 / 10 min | `TravelEstimate`, `TravelTimeService`, `RecommendationService` |
| Weather cache | cell / TTL / cells per refresh | geohash-5 / 15 min / 4 | `ConditionsService`, `RecommendationService` |
| Server limits | reports / issues / submissions / edits / photos | 12/h · 6/h · 5/day · 20/day · 10/day | `app_config` + RPCs |
| | same facility + kind cooldown | 10 min (issues: 6 h) | `app_config.same_facility_cooldown_minutes` |
| Contributor | insights duration | 7 days | `app_config.contributor_insights_days` |
| Cold start | fresh / busy / failure backoff / budget | 30 days / 10 min / 6 h / 20 per hour | `app_config`, `region_claim_import` |
| Retention | hot window | 120 days | `archive_raw_observations` |
