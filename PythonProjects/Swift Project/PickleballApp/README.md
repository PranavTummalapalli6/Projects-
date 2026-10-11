# Pickleball Now

> Where can I realistically play pickleball **right now**, at my level, under acceptable conditions, with access I
> can actually use, in the least reasonable amount of time?

An iOS-first pickleball decision engine (SwiftUI + MapKit + Supabase/PostGIS). It isn't just a court directory:
every facility goes through **Eligibility → Player fit → Time to play → Cost/access**, and the app shows the
trade-offs ("Fastest to play · $15 day pass" vs "Best free option · 5–15 min wait") with honest ranges and
confidence.

- **Run it now:** open `PickleballApp.xcodeproj` and Run. Demo mode needs no backend. See [docs/SETUP.md](docs/SETUP.md).
- **Architecture, schema, data flows, prediction/confidence/trust/privacy models:** [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Repository layout

| Path | What |
|---|---|
| `PickleballApp/` | SwiftUI app: `App`, `Core` (networking, keychain, location, maps, persistence), `DesignSystem`, `Models`, `Repositories` (Supabase + Demo), `Services`, `Features/*` |
| `Packages/PickleCore/` | Pure Swift logic package: Prediction V1, confidence, best time, recommendation engine, eligibility, player fit, weather/wind, duplicate detection, prompt-fatigue policy, location verification, integrity mirror, clustering, plus 66 unit tests |
| `PickleballAppTests/`, `PickleballAppUITests/` | App unit tests (repositories, caching, filters, prompt flow, encoding, photo privacy) and UI tests |
| `supabase/migrations/` | Schema + PostGIS, RLS, SECURITY DEFINER RPCs (all trust logic), scheduled jobs |
| `supabase/functions/region-discovery/` | Throttled, cached cold-start OSM backfill (Deno) |
| `supabase/tests/` | SQL behaviour tests + local stub for validating on plain PostGIS |
| `scripts/` | CSV/JSON facility importer, demo-data generator, SQL validation harness |

## Phase status

| Phase | Status |
|---|---|
| 0 Architecture | Done: `docs/ARCHITECTURE.md` |
| 1 App shell, design system, map, location, search, states | Done |
| 2 Supabase/PostGIS schema, RLS, repositories | Done. Validated on PostGIS 15 with a Supabase stub, not yet against a live Supabase project |
| 3 Facility map, clustering, debounced region queries, sheet, travel, directions | Done |
| 4 Ingestion (OSM, CSV/JSON, manual) | Done: `import_facility`, importer script, edge function |
| 5 Add court, duplicates, confirmations, edits, photos | Done (photo approval is manual SQL) |
| 6 Access, cost, usable courts, blackouts, overrides | Done |
| 7 One-tap reporting, location verification, cooldowns, prompt fatigue | Done |
| 8 Player fit | Done |
| 9 Prediction V1 | Done (on-device from server-weighted signals, see [D1]) |
| 10 Recommendation engine | Done |
| 11 Best time | Done |
| 12 Contributor system | Done (server-controlled; gating off by default during cold start) |
| 13 Regional cold start | Done (server-side throttle + cache) |
| 14 Passive visits | Foundation done: foreground arrival/departure, opt-in upload, session-duration aggregates. Background region monitoring isn't built yet; the server already accepts `region_monitoring` |
| 15 Polish | Ongoing: verified in simulator, light mode |
| 16 Tests | 66 core + 17 app unit + 4 UI + 14 SQL + 2 Deno, all passing |

**Not built yet (deliberately):** notifications (the `wait_predictions` table is reserved for them), reservation
integrations, a moderation UI (moderate in the Supabase SQL editor for now), and account upgrade (anonymous →
email/Apple). WeatherKit code is written, but it needs the paid program to run; until then Open-Meteo is used.

## Cost

Development costs $0. Early production fits Supabase's free tier, with Pro at $25/month once usage needs it.
MapKit, Core Location and Open-Meteo are free. The $99/year Apple Developer Program is needed only for
TestFlight, the App Store and WeatherKit. See ARCHITECTURE §16 for the cost-control decisions.
