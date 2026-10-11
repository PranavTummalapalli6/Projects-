# Pickleball Now — Architecture (Phase 0)

> Core question: *"Where can I realistically play pickleball right now, at my level, under acceptable
> conditions, with access I can actually use, in the least reasonable amount of time?"*

This document is the Phase 0 deliverable. It is the source of truth for structure, data, trust, privacy
and cost decisions. Decisions marked **[D#]** are engineering decisions made without asking; each lists
its trade-off.

---

## 1. Architecture overview

```
                         iOS app (SwiftUI, iOS 17+)
 ┌────────────────────────────────────────────────────────────────────────────┐
 │ Features (Views + small @Observable ViewModels)                            │
 │   Map · Facility · Search · Filters · Reports · AddCourt · Edit · Profile  │
 │                │                                                           │
 │ Services:  FacilityService · RecommendationService · PredictionService     │
 │            ReportService · SubmissionService · LocationService             │
 │            WeatherService · TravelTimeService · VisitService · Prompting   │
 │                │                                                           │
 │ Repositories (protocols):  FacilityRepository · ReportRepository ·         │
 │            SubmissionRepository · ContributorRepository · VisitRepository  │
 │        ├── Supabase*Repository  (PostgREST RPC over URLSession)            │
 │        └── Demo*Repository      (bundled sample data, no backend needed)   │
 │                                                                            │
 │ PickleCore (local Swift package, pure logic, no UI, unit-tested on macOS): │
 │   Models · Geo · Prediction V1 · Confidence · BestTime · Recommendation    │
 │   Eligibility · PlayerFit · Weather assessment · DuplicateDetector         │
 │   PromptPolicy · LocationVerifier · Integrity pre-check · Clusterer        │
 └───────────────┬─────────────────────────────────┬──────────────────────────┘
                 │ HTTPS (anon key + user JWT)      │ MapKit / CoreLocation / WeatherKit
                 ▼                                  ▼
 ┌──────────────────────────── Supabase ─────────────────────────────────────┐
 │ Auth (anonymous sign-in → upgradable)   Storage (facility-photos bucket)  │
 │ PostgreSQL 15 + PostGIS                                                    │
 │   tables (RLS on every table; writes only through SECURITY DEFINER RPCs)   │
 │   RPCs: nearby_facilities, facility_detail, search_facilities,             │
 │         submit_live_report, report_facility_issue, find_duplicate_facilities│
 │         submit_facility, confirm_facility, suggest_edit, register_photo,   │
 │         my_contributor_status, record_visit, upsert_profile               │
 │   jobs (pg_cron): refresh_occupancy_aggregates, archive_raw_observations, │
 │         expire_operational_state                                          │
 │ Edge Function: region-discovery (throttled, cached cold-start backfill)    │
 └────────────────────────────────────────────────────────────────────────────┘
```

**[D1] Prediction math runs in `PickleCore` (the dedicated prediction layer), fed by server-side
trust-weighted signals.** The server owns everything trust-related (location verification, integrity
score, trust weight, contributor gating, aggregation). The device turns those signals into ranges.
*Why:* $0 compute per map pan, works offline from cached signals, one independently testable module.
*Trade-off:* future server-side notifications need a port of `WaitPredictor` (it is ~300 lines of
deterministic arithmetic with fixture tests, so the port is mechanical). The client never sees raw
reports, user ids, or precise reporter locations.

**[D2] No Supabase Swift SDK.** A ~250-line `SupabaseClient` (PostgREST RPC, anonymous auth, token refresh,
Storage upload) over `URLSession`. *Why:* no SPM resolution needed to build, fewer moving parts, we use
~5% of the SDK. *Trade-off:* if Realtime is ever needed, adopt `supabase-swift` then.

**[D3] Demo mode.** If `SUPABASE_URL`/`SUPABASE_ANON_KEY` are empty the app runs on bundled,
clearly-labelled fictional facilities (Cupertino + Fairfax, VA areas) so the app is fully usable in the
simulator with zero setup. A banner says "Demo data".

**[D4] Weather.** `WeatherService` wraps a `WeatherProvider` protocol. `WeatherKitProvider` is the
production provider. WeatherKit needs the paid Developer Program entitlement, so until then the app
falls back to `OpenMeteoProvider` (free, keyless, includes wind + gusts). This is not "another provider
just for wind"; it exists only because WeatherKit is unavailable on a free account. Results are cached
per ~1 km cell for 15 minutes.

---

## 2. Xcode project structure

```
PickleballApp/
  PickleballApp.xcodeproj           (Xcode 16 synchronized folders: add files on disk, no pbxproj edits)
  PickleballApp/
    App/                PickleballApp.swift, AppEnvironment.swift, AppConfig.swift, RootView.swift
    Core/
      Networking/       SupabaseClient.swift, APIError.swift, JSONCoding.swift
      Security/         KeychainStore.swift
      Location/         LocationService.swift
      Maps/             TravelTimeService.swift, MapRegionFetcher.swift
      Persistence/      LocalStore.swift (prompt state, prefs, caches)
      Utilities/        Debouncer.swift, Haptics.swift, Formatters.swift, Analytics.swift
    DesignSystem/       Theme.swift, Components/*.swift, Icons.swift (status → SF Symbol + label)
    Repositories/       protocols + Supabase*/Demo* implementations
    Services/           FacilityService, PredictionService, RecommendationService, ReportService,
                        SubmissionService, WeatherService, VisitService, ContributorService
    Features/
      Map/              MapScreen, MapViewModel, FacilityAnnotationView, RecommendationStrip
      Facility/         FacilitySheet, FacilityDetailView, FacilityDetailViewModel, sections
      Search/           SearchView, SearchViewModel
      Filters/          FiltersSheet, FilterState
      Reports/          QuickReportSheet, ReportViewModel, IssueReportSheet
      AddCourt/         AddCourtFlow, AddCourtViewModel
      Edit/             SuggestEditSheet
      PlayerProfile/    ProfileView (skill, cost pref, privacy, contributor status)
      Onboarding/       LocationPrimerView
    Resources/          Assets.xcassets, DemoFacilities.json, Info.plist
  PickleballAppUITests/
  Packages/PickleCore/  (Sources + Tests — the bulk of the unit tests)
  Config/               Base.xcconfig, Secrets.example.xcconfig (Secrets.xcconfig is git-ignored)
  supabase/             config.toml, migrations/, functions/region-discovery/, tests/ (pgTAP), seed.sql
  scripts/              import_csv.mjs (city datasets / manual seeds → import RPC)
  docs/                 ARCHITECTURE.md, SETUP.md
```

---

## 3. Schema (PostgreSQL + PostGIS) — see `supabase/migrations`

Logical layers are kept separate:

| Layer | Tables |
|---|---|
| Stable facility facts | `facilities`, `facility_sources`, `facility_hours`, `facility_rules`, `facility_access`, `facility_costs` (amenities are boolean columns on `facilities` **[D5]** — 4 fixed booleans don't justify an EAV table) |
| Community contributions | `facility_submissions`, `facility_confirmations`, `facility_edit_suggestions`, `facility_photos` |
| Temporary operational state | `facility_blackouts`, `facility_operational_overrides` |
| Community observations | `occupancy_reports`, `paddle_stack_reports`, `surface_reports`, `skill_observations`, `play_culture_observations`, `visits` |
| Derived / predictions | `occupancy_aggregates`, `session_duration_aggregates`, `wait_predictions` (cache for future server-side alerts), `weather_snapshots` |
| Users & control | `profiles`, `contributor_status`, `report_prompt_state`, `user_report_activity`, `app_config`, `region_coverage`, `region_import_log`, `analytics_events` |

Key columns: `facilities.location geography(Point,4326)` with GiST index; `existence_status/confidence`
is independent from `facility_access.verification_status/confidence`; `court_type`,
`total_physical_courts`, `default_pickleball_courts` are separate from the *current* usable count which
lives in `facility_operational_overrides(kind='usable_courts')`.

## 4. Entity relationships

```
auth.users 1─1 profiles 1─1 contributor_status
                  │
                  ├─< occupancy_reports >─┐
                  ├─< paddle_stack_reports >┤
                  ├─< surface_reports >─────┤
                  ├─< skill_observations >──┤
                  ├─< play_culture_observations >┤
                  ├─< visits >──────────────┤
                  ├─< facility_confirmations >┤
                  ├─< facility_edit_suggestions >┤
                  ├─< facility_submissions ──(resulting_facility_id)─┤
                  └─< report_prompt_state >─┤
                                            ▼
 facility_sources >── facilities ──1 facility_access
                         │      └──1 facility_costs
                         ├─< facility_hours, facility_rules, facility_photos
                         ├─< facility_blackouts, facility_operational_overrides
                         └─< occupancy_aggregates, session_duration_aggregates, wait_predictions
 region_coverage (geohash-4 cell) ─< region_import_log
```

## 5. Flow: open app → recommendation → detail

```
launch → anonymous session (Keychain) ─┐
location? ──yes→ center on user        │
          └─no→ last region / city search
camera settles (onEnd) → debounce 350ms → if visible bbox ⊄ cached padded bbox:
   RPC nearby_facilities(padded bbox)  → facilities + access/cost + blackouts + overrides
                                        + latest surface + skill/culture summary
                                        + historical bucket(now) + live observations (if entitled)
   if 0 results & cell not tried recently → Edge fn region-discovery (server decides)
→ PickleCore.WaitPredictor per facility (cheap, synchronous)
→ TravelTimeService: straight-line estimate for all, MKDirections ETA for top 6 only (cached 10 min)
→ WeatherService for outdoor candidates (cached per cell)
→ RecommendationEngine: Eligibility → Fit → Time-to-play → Cost/Access → labelled picks
→ map annotations (clustered) + bottom strip: Best match / Fastest / Best free
tap marker → FacilitySheet (decision-critical) → Court Details → RPC facility_detail (hours, week
histogram, rules, photos) → BestTimePlanner
```

## 6. Flow: occupancy report

```
client: LocationVerifier pre-check (enables button only when near; never trusted)
→ RPC submit_live_report(facility, kind, value, lat, lng, accuracy, fix_age, simulated_flag)
server (SECURITY DEFINER):
   rate limit (per user: N/hour, cooldown per facility+kind)
   distance(user point, facility) ≤ radius + min(accuracy, cap) → location_verified
   integrity_score = f(accuracy, fix age, simulated flag (prod), impossible travel vs last report,
                       report burst, distinct facilities/hour, contradiction with fresh consensus)
   trust_weight = (verified ? 1.0 : 0.25) × integrity_score × account_age_factor
   insert report (reporter coordinates are NOT stored — only distance + accuracy)
   if useful → extend contributor_status.insights_until (server config)
→ next nearby_facilities call returns the observation (age, value, rounded weight; no user id)
→ PickleCore applies exp(-λ·age) decay and blends with history
```

## 7. Flow: missing court

```
Add Court → location (current / drop pin / search) → minimal form (courts, type, indoor/outdoor)
→ RPC find_duplicate_facilities(lat,lng,name)  ("Is this one of these?")  → user picks existing
   (becomes a confirmation) or "No, it's new"
→ RPC submit_facility → server re-runs duplicate check (distance < 60 m, or < 250 m + name sim ≥ .6)
   → facility created with existence_status='community_reported' (or 'pending' if low integrity)
→ optional photo → Storage facility-photos/{uid}/{uuid}.jpg (EXIF stripped, ≤1600px, JPEG .7)
   → RPC register_photo
→ others: "Is this court here? Yes/No" → confirm_facility → confidence grows → partially_verified
   (2 independent verified yes) → verified (4 + age > 24h, or photo approved by moderator)
```

## 8. Flow: regional cold start

```
nearby returns ~0 within a real map region
→ client calls region-discovery(lat,lng) at most once per geohash-4 cell per 24h (client throttle)
→ Edge fn (service role): region_coverage[cell]
     imported & fresh (< 30 days) → return coverage (no external call)
     import running / failed recently (< 6h backoff) → return status
     global budget exceeded (≤ 20 imports / hour, config) → status 'deferred'
     else mark 'importing' → Overpass query (leisure=pitch + sport~pickleball, bbox of cell)
          → normalize → upsert via import_facility() (dedupe by source id, then spatial+name)
          → region_coverage: facility_count, last_imported_at, status
→ client re-queries our DB. Source is pluggable: Overpass today; scheduled OSM extracts or a
  self-hosted Overpass later without client changes.
```

## 9. Prediction V1 (PickleCore/Prediction)

Explainable, statistical, no ML/LLM.

1. **Usable courts** `u` = fresh `usable_courts` override (confidence ≥ medium) else `default_pickleball_courts`
   else `total_physical_courts` else unknown (→ low confidence).
2. **Historical signal** for the current 30-min bucket: occupancy ratio `h`, sample count `n_h`. With no
   history, a generic population prior curve (weekday evenings / weekend mornings busier) is used,
   flagged `prior`, with weight 0.5.
3. **Live signal**: each observation `i` has server trust `t_i`, age `a_i` minutes,
   `w_i = t_i · exp(-λ a_i)` (λ = ln2 / 25 min half-life, configurable). Status → occupancy + queue:
   `courts_open→(0.45,0)`, `mostly_full→(0.85,0)`, `all_full→(1.0,0.25)`, `players_waiting→(1.0,1.0)`
   groups/court, overridden by explicit `occupied_courts`/`groups_waiting` when given.
4. **Blend**: `occ = (h·W_h + Σ w_i occ_i)/(W_h + Σw_i)` where `W_h = min(1.5, n_h/20)` (prior: 0.3).
   Weather multiplies demand (rain ×0.4, very windy ×0.7, extreme heat ×0.75) **only for the historical
   part** — live observations already reflect today.
5. **Wait**:
   - *Rotation / paddle stack*: `games_ahead = paddles/(4·u)` (doubles; singles-only uses 2);
     `wait ≈ games_ahead · g` where `g` = typical game minutes (default 13). Range
     `[max(0, games_ahead−0.5)·g·0.8, (games_ahead+0.5)·g·1.25]`.
   - *Stay-until-finished*: if `occ < 1` → `0–5 min` (scaled by occ). If full with `q` groups queued per
     court: residual-life approximation `wait ≈ (q·u + 1)·S/(u+1)`, with `S` = median session (default 60),
     range from session p25/p75.
6. **Range snapping** to honest buckets: `0–5, 5–15, 10–20, 15–30, 20–40, 30–45, 45–60, 60+`;
   low confidence widens by one bucket.

## 10. Recommendation engine (PickleCore/Recommendation)

Staged and explainable — every stage outputs a reason string; there is no single opaque score for the
user; the ranking key is a tuple of explainable components.

- **A Eligibility** → `eligible | restricted(reason) | unavailable(reason, until)`:
  hours, confirmed/likely blackout, closure overrides (fast negative propagation), unsafe/wet surface,
  access type vs user (resident/HOA/membership/private/school → restricted), usable courts == 0.
  Unavailable facilities never appear as top picks; they show with their reason.
- **B Fit** (soft): skill band overlap of user preference vs community band distribution
  (`great | good | stretch | mismatch | unknown`), culture tags vs prefs (beginner friendly, competitive),
  dedicated vs converted courts.
- **C Time to play** = travel minutes + wait range → `timeToPlay.low/high/mid`.
- **D Cost/access**: free / day pass / reservation fee / membership; respects `Free only` preference.
- **Picks** (labelled cards): `Best match`, `Fastest to play`, `Best free option`,
  `Reservable option` (paid + reservation system) — duplicates collapsed.
- **Best overall ordering**: `mid time-to-play + fitPenalty(0/5/12/25 min) + costPenalty(pref-based) +
  uncertaintyPenalty(low conf: +40% of wait mid)` — expressed in *minutes*, so each component is explainable
  ("+12 min-equivalent: more competitive than your level"). Low-confidence short waits cannot dominate.
- Sort modes: Best overall, Fastest to play, Closest, Shortest wait, Best skill match, Most courts.

## 11. Confidence model

Evidence points (0–∞): live `Σ w_i` × agreement (1 − normalised status std-dev) × verified share,
plus historical `min(1, n_h/30)`, plus configuration certainty (usable courts known).
`High` ≥ 2.0 with ≥ 2 fresh observations (< 30 min); `Medium` ≥ 0.8; else `Low`. No percentages in UI.

## 12. Facility verification model

Existence (`facilities.existence_status`) and access (`facility_access.verification_status`) are
independent state machines: `pending → community_reported → partially_verified → verified`, plus
`rejected` and `closed`. Positive evidence accumulates slowly (distinct users, location-verified,
spread over time). Negative evidence is asymmetric: one credible location-verified closure/locked/
construction/tournament report → immediate `facility_operational_overrides` warning (expires in 6–48 h);
2+ independent negative reports within 24 h → `temporarily_unavailable`; `closed` only via moderator or
sustained corroboration over 14 days. Nothing is deleted on one report.

## 13. Anti-abuse model

Server-only fields: `trust_weight`, `integrity_score`, `verification_status`, `is_admin`, contributor
entitlement. Writes happen only through SECURITY DEFINER RPCs that validate input ranges, coordinate
sanity (lat/lng bounds, not 0,0, inside service area), rate limits (`user_report_activity`), cooldowns,
impossible travel (> 150 km/h between consecutive reports), bursts, contradiction with fresh
high-weight consensus, account age. Suspicious reports are down-weighted silently — users are never told
they are suspected. Software-simulated locations get integrity × 0.2 in production; DEBUG/demo accepts them.
We do not claim spoof-proofing.

## 14. Privacy model

- No account needed to browse; anonymous auth for contributions, upgradable later (link identity).
- Location is used on-device; the server receives coordinates only at the moment of a report/
  submission, stores **distance to facility + accuracy**, never the raw point (submissions store the
  court location, which is the point of the submission).
- Visits store `arrival_at/departure_at/facility_id/method/confidence` only; no trails. Passive visit
  detection is opt-in, off by default, and foreground-only unless the user enables region monitoring.
- Photos: EXIF/GPS metadata stripped on device before upload.
- Analytics: event name + facility id + coarse timestamp; no IP/device identifiers stored.
- Location denied → city/ZIP search and manual browsing remain fully functional; one unobtrusive
  "Enable location" row in Profile, never repeated prompts.

## 15. Prompt-fatigue / minimal-input rules (PickleCore/Community/PromptPolicy)

- One primary question per visit; optional "Add more detail" never auto-opens.
- Question is chosen by context: unverified facility → "Is this court here?"; recent rain & no fresh
  surface report → "Court surface?"; paddle-stack facility → "Paddle wait?"; else "How busy?".
- Skip if a high-confidence observation < 15 min old exists; skip if user reported here < 3 h ago;
  after 2 consecutive dismissals → 3-day backoff; 4+ → 14-day backoff; never two prompts within 20 min.
  All values in `PromptPolicyConfig`, overridable from `app_config`.
- Prompts are non-modal cards, dismiss = one tap, answer = one tap, haptic confirmation.

## 16. Cost-control decisions

| Decision | Effect |
|---|---|
| Supabase free tier (500 MB DB, 1 GB storage, 50k MAU) | $0 dev; Pro $25/mo only when needed |
| Bounding-box RPC with padded bbox client cache, `onEnd` camera + 350 ms debounce | ~1 RPC per real map move |
| Prediction on device from aggregated signals | no per-request compute cost |
| No Realtime subscriptions; refresh on sheet open / pull | zero websocket cost |
| MKDirections only for top 6 candidates, 10-min cache | stays within Apple throttles, free |
| Weather cached per cell 15 min | free tiers suffice |
| Overpass only server-side, ≤ 20 imports/h, 30-day cell cache | polite & free; swap for extracts later |
| Raw observations aggregated nightly; raw kept 120 days, then archived to aggregates | DB stays small |
| Photos compressed ≤ 1600 px JPEG 0.7 | ~250 KB/photo |

## 17. Development dependency graph

```
P0 Architecture
 └─ P1 App shell / design system / location / search
     └─ P2 Supabase schema, RLS, client, repositories ─┐
         └─ P3 Facility map, clustering, sheet, travel  │
             ├─ P4 Ingestion (OSM/CSV/manual) ◄─────────┘
             ├─ P5 Add court, duplicates, confirm, edit, photos
             ├─ P6 Access/cost/usable courts/blackouts/overrides
             │    └─ P7 One-tap live reporting + prompt policy
             │         └─ P8 Player fit
             │              └─ P9 Prediction V1 ─ P10 Recommendation ─ P11 Best time
             │                                       └─ P12 Contributor system
             ├─ P13 Regional cold start (needs P4)
             └─ P14 Passive visits (needs P7 stable)
 P15 Polish, P16 Tests run continuously
```
