# Setup

## 1. Run the app right now (no accounts, $0)

Requirements: Xcode 16+ (tested with 16.4), iOS 17+ simulator or device.

```bash
open PickleballApp.xcodeproj
```

Choose the **PickleballApp** scheme and an iPhone simulator, then Run. Without Supabase keys, the app runs in
**demo mode** on fictional courts around Fairfax, VA and Cupertino, CA. A "Demo data" chip appears on the map.

- Simulator location: **Features → Location → Custom Location…** (e.g. `38.8458, -77.3060` stands you
  next to "Laurel Creek Park" and triggers the one-tap arrival prompt after ~60 s).
- To report from anywhere in demo mode: **You (profile) → Demo mode → Allow reports from anywhere**, or
  use "Demo: pretend I'm here" in the report sheet.

**Physical iPhone with a free Apple ID:** in Config/Secrets.xcconfig set `APP_BUNDLE_ID = com.yourname.pickleballnow`,
select your Personal Team under Signing & Capabilities, and run. You don't need the $99 program until you want
TestFlight, App Store distribution, or WeatherKit.

## 2. Connect a Supabase backend (free tier)

1. Create a project at supabase.com (free tier: 500 MB database, 1 GB storage).
2. **Authentication → Sign In / Providers → Allow anonymous sign-ins**: enable it. Browsing never needs an account;
   anonymous sessions are created only for the first contribution and can be upgraded later.
3. **Database → Extensions**: `postgis`, `pg_trgm` and `pg_cron` are installed by the migrations. If your
   project restricts extension creation, enable them in the dashboard first.
4. Apply migrations and the demo seed with the Supabase CLI:

   ```bash
   brew install supabase/tap/supabase
   ```

   ```bash
   supabase link --project-ref YOUR_PROJECT_REF
   ```

   ```bash
   supabase db push
   ```

   For a fresh **local** stack (Docker) use `supabase start` then `supabase db reset` (applies migrations + seed.sql).
   Don't load `seed.sql` into a production project; it holds the fictional demo courts.
5. Deploy the cold-start function:

   ```bash
   supabase functions deploy region-discovery
   ```

   `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically. Optionally set `OVERPASS_URL`
   (`supabase secrets set OVERPASS_URL=...`) to point at a self-hosted Overpass later.
6. Configure the app:

   ```bash
   cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
   ```

   Fill in `SUPABASE_URL` (keep the `https:/$()/` form) and the **anon** key from Project Settings → API.
   **Never** put the service-role key in the app or in this file.
7. Go to production mode: `update app_config set value = '"production"' where key = 'environment';`
   This makes simulated GPS locations count for less. Leave `live_gating_enabled = false` until the community
   is big enough that gating live detail to contributors makes sense.

## 3. Importing real facilities

- **City / county datasets, or your own verified list** (CSV or JSON). Columns: `name, latitude, longitude`
  plus any of `courts, pickleball_courts, court_type, indoor_outdoor, lit, play_system, address, city, state,
  postal_code, time_zone, access_type, access_notes, cost_type, day_pass_price, reservation_available`.

  ```bash
  SUPABASE_URL=https://xyz.supabase.co SUPABASE_SERVICE_ROLE_KEY=... node scripts/import_facilities.mjs data/fairfax.csv --source city:fairfax_va
  ```

  Rows are normalized and deduplicated server-side by `import_facility` (same source id → update; within
  60 m, or within 250 m with a similar name → merge into the existing facility).
- **OpenStreetMap**: done automatically and on demand by `region-discovery`. Throttling, caching and a global
  budget are enforced in the database (`region_claim_import`). For bulk/regular imports, move to a scheduled
  job over an OSM extract and reuse `import_facility`. No client changes are needed.

## 4. Moderation (no admin UI yet; use the Supabase SQL editor)

```sql
-- New community courts awaiting review
select id, name, existence_status, existence_confidence, created_at from facilities
where source = 'community' order by created_at desc;

-- Approve a photo / confirm a closure / add an official blackout
update facility_photos set verification_status = 'approved' where id = '...';
update facilities set existence_status = 'closed' where id = '...';
insert into facility_blackouts (facility_id, start_at, end_at, reason, description, source, verification_status, confidence)
values ('...', '2026-10-10 08:00-04', '2026-10-10 18:00-04', 'tournament', 'Regional tournament', 'official', 'verified', 0.95);

-- Open edit suggestions that need a human (closures, "other", high-impact)
select * from facility_edit_suggestions where status = 'open' order by created_at desc;
```

## 5. WeatherKit (after joining the Apple Developer Program)

1. Add the WeatherKit capability to the PickleballApp target (Signing & Capabilities) and enable WeatherKit
   for the App ID in the developer portal.
2. Set `USE_WEATHERKIT = YES` in Config/Secrets.xcconfig.
   The app then uses WeatherKit and falls back to Open-Meteo only if a WeatherKit request fails.

## 6. Tests

```bash
cd Packages/PickleCore && swift test
```

```bash
xcodebuild test -project PickleballApp.xcodeproj -scheme PickleballApp -destination 'platform=iOS Simulator,name=iPhone 16'
```

```bash
./scripts/validate_sql.sh
```

`validate_sql.sh` needs Docker. It applies every migration plus the seed to a throwaway PostGIS 15 container
and runs `supabase/tests/rpc_test.sql`. The test file covers RLS denial, location verification, cooldowns,
integrity down-weighting, live gating, duplicate detection, verification thresholds, fast negative
propagation, edit auto-apply, search, jobs and cold-start throttling.

Edge-function tests (Deno):

```bash
docker run --rm -v "$PWD/supabase/functions/region-discovery:/app" -w /app denoland/deno:2.1.4 deno test normalize_test.ts
```
