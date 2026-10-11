set search_path = public, extensions;
-- Pickleball Now — core schema
-- Layers: stable facility facts | community contributions | temporary operational state |
--         community observations | derived/predictions | users & control.
-- All client writes go through SECURITY DEFINER RPCs (see 0003); tables have RLS on (see 0002).

create schema if not exists extensions;
create extension if not exists postgis with schema extensions;
create extension if not exists pg_trgm with schema extensions;

create schema if not exists private;   -- not exposed through PostgREST
revoke all on schema private from public;

-- ───────────────────────────── Users & control ─────────────────────────────

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  skill_band text not null default 'unknown'
    check (skill_band in ('beginner','2.0-2.5','2.5-3.0','3.0-3.5','3.5-4.0','4.0-4.5','4.5+','unknown')),
  cost_preference text not null default 'no_preference'
    check (cost_preference in ('free_only','include_paid','no_preference')),
  prefers_competitive boolean,
  wants_beginner_friendly boolean not null default false,
  passive_visits_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Server-controlled; never writable by clients.
create table private.app_admins (
  user_id uuid primary key references auth.users (id) on delete cascade
);

create table public.app_config (
  key text primary key,
  value jsonb not null,
  is_public boolean not null default false,
  description text
);

create table public.contributor_status (
  user_id uuid primary key references auth.users (id) on delete cascade,
  insights_until timestamptz,
  qualifying_contributions int not null default 0,
  last_contribution_at timestamptz,
  updated_at timestamptz not null default now()
);

-- ───────────────────────────── Stable facility facts ─────────────────────────────

create table public.facilities (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 160),
  name_normalized text not null default '',
  location geography(Point, 4326) not null,
  latitude double precision not null default 0,
  longitude double precision not null default 0,
  geohash4 text not null default '',
  address text,
  city text,
  state text,
  postal_code text,
  time_zone text,
  total_physical_courts int check (total_physical_courts between 0 and 200),
  default_pickleball_courts int check (default_pickleball_courts between 0 and 200),
  court_type text not null default 'unknown' check (court_type in
    ('dedicated_pickleball','pickleball_lined_tennis','convertible_tennis','multi_use','mixed_facility','unknown')),
  indoor_outdoor text not null default 'unknown' check (indoor_outdoor in ('indoor','outdoor','both','unknown')),
  has_lights boolean,
  has_restrooms boolean,
  has_water boolean,
  has_parking boolean,
  play_system text not null default 'unknown' check (play_system in
    ('paddle_stack','rotation_board','stay_until_finished','reservation_only','organized_open_play','unknown')),
  typical_game_minutes numeric check (typical_game_minutes between 5 and 60),
  source text not null default 'manual',
  source_last_updated timestamptz,
  existence_status text not null default 'pending' check (existence_status in
    ('pending','community_reported','partially_verified','verified','rejected','closed')),
  existence_confidence numeric not null default 0 check (existence_confidence between 0 and 1),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index facilities_location_gix on public.facilities using gist (location);
create index facilities_name_trgm on public.facilities using gin (name_normalized gin_trgm_ops);
create index facilities_geohash4 on public.facilities (geohash4);
create index facilities_postal on public.facilities (postal_code);
create index facilities_city_trgm on public.facilities using gin (lower(city) gin_trgm_ops);

create table public.facility_sources (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references public.facilities (id) on delete cascade,
  source text not null,                 -- 'osm', 'city:fairfax_va', 'manual', 'community'
  external_id text not null,
  raw jsonb,
  imported_at timestamptz not null default now(),
  unique (source, external_id)
);
create index on public.facility_sources (facility_id);

-- Access verification is independent of existence verification.
create table public.facility_access (
  facility_id uuid primary key references public.facilities (id) on delete cascade,
  access_type text not null default 'unknown' check (access_type in
    ('public_walk_on','public_reservation','public_permit_required','resident_only','resident_guest_allowed',
     'hoa','membership_required','day_pass_available','private','school_restricted','unknown')),
  access_notes text check (char_length(access_notes) <= 300),
  reservation_required boolean,
  reservation_available boolean,
  permit_required boolean,
  verification_status text not null default 'pending' check (verification_status in
    ('pending','community_reported','partially_verified','verified','rejected','closed')),
  confidence numeric not null default 0 check (confidence between 0 and 1),
  last_verified_at timestamptz,
  updated_at timestamptz not null default now()
);

create table public.facility_costs (
  facility_id uuid primary key references public.facilities (id) on delete cascade,
  cost_type text not null default 'unknown' check (cost_type in
    ('free','paid','day_pass','reservation_fee','membership','unknown')),
  day_pass_price numeric(8,2) check (day_pass_price >= 0 and day_pass_price < 1000),
  reservation_fee numeric(8,2) check (reservation_fee >= 0 and reservation_fee < 1000),
  pricing_notes text check (char_length(pricing_notes) <= 300),
  last_verified_at timestamptz,
  updated_at timestamptz not null default now()
);

create table public.facility_hours (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references public.facilities (id) on delete cascade,
  day_of_week smallint not null check (day_of_week between 0 and 6),   -- 0 = Sunday
  opens time not null,
  closes time not null,
  notes text,
  check (closes > opens)
);
create index on public.facility_hours (facility_id);

create table public.facility_rules (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references public.facilities (id) on delete cascade,
  kind text not null default 'general',   -- 'reservation','guest','time_limit','hours_note','general'
  rule_text text not null check (char_length(rule_text) <= 500),
  source text not null default 'community',
  created_at timestamptz not null default now()
);
create index on public.facility_rules (facility_id);

-- ───────────────────────────── Community contributions ─────────────────────────────

create table public.facility_submissions (
  id uuid primary key default gen_random_uuid(),
  submitted_by uuid not null references auth.users (id) on delete cascade,
  location geography(Point, 4326) not null,
  payload jsonb not null,
  status text not null default 'accepted' check (status in ('pending','accepted','duplicate','rejected')),
  resulting_facility_id uuid references public.facilities (id) on delete set null,
  duplicate_of uuid references public.facilities (id) on delete set null,
  submitter_distance_m numeric,
  integrity_score numeric,
  created_at timestamptz not null default now()
);
create index on public.facility_submissions (submitted_by, created_at desc);

create table public.facility_confirmations (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references public.facilities (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('exists','not_exists','access_confirmed','access_wrong')),
  location_verified boolean not null default false,
  trust_weight numeric not null default 0.5,
  created_at timestamptz not null default now(),
  unique (facility_id, user_id, kind)
);

create table public.facility_edit_suggestions (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references public.facilities (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  edit_type text not null check (edit_type in (
    'permanently_closed','court_count_changed','pickleball_courts_added','striped_for_pickleball',
    'converted_to_dedicated','no_longer_pickleball','indoor_outdoor_changed','access_changed','cost_changed',
    'reservation_policy_changed','play_system_changed','hours_changed','amenities_changed','other')),
  proposed jsonb not null default '{}'::jsonb,
  note text check (char_length(note) <= 500),
  status text not null default 'open' check (status in ('open','applied','rejected','superseded')),
  supporters uuid[] not null default '{}',
  support_weight numeric not null default 0,
  location_verified boolean not null default false,
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);
create index on public.facility_edit_suggestions (facility_id, status);

create table public.facility_photos (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid references public.facilities (id) on delete cascade,
  submission_id uuid references public.facility_submissions (id) on delete set null,
  uploaded_by uuid not null references auth.users (id) on delete cascade,
  storage_path text not null unique,
  metadata jsonb not null default '{}'::jsonb,
  verification_status text not null default 'pending' check (verification_status in ('pending','approved','rejected')),
  created_at timestamptz not null default now()
);
create index on public.facility_photos (facility_id);

-- Negative operational reports from individual users (aggregated into overrides).
create table public.facility_issue_reports (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references public.facilities (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('possible_closure','temporarily_unavailable','locked_gates','construction',
    'nets_removed','pickleball_prohibited','unsafe_surface','tournament')),
  note text check (char_length(note) <= 300),
  location_verified boolean not null default false,
  trust_weight numeric not null,
  integrity_score numeric not null,
  created_at timestamptz not null default now()
);
create index on public.facility_issue_reports (facility_id, kind, created_at desc);

-- ───────────────────────────── Temporary operational state ─────────────────────────────

create table public.facility_blackouts (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references public.facilities (id) on delete cascade,
  start_at timestamptz not null,
  end_at timestamptz not null,
  reason text not null check (reason in ('tournament','league_event','maintenance','construction','private_event',
    'seasonal_closure','facility_closure','other')),
  description text check (char_length(description) <= 300),
  courts_affected int check (courts_affected > 0),          -- null = whole facility
  source text not null default 'community' check (source in ('official','community','moderator','import')),
  verification_status text not null default 'pending' check (verification_status in
    ('pending','community_reported','partially_verified','verified','rejected','closed')),
  confidence numeric not null default 0.3 check (confidence between 0 and 1),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (end_at > start_at)
);
create index on public.facility_blackouts (facility_id, end_at);

create table public.facility_operational_overrides (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references public.facilities (id) on delete cascade,
  kind text not null check (kind in ('usable_courts','possible_closure','temporarily_unavailable','locked_gates',
    'construction','nets_removed','pickleball_prohibited','unsafe_surface','tournament')),
  value int,
  note text,
  starts_at timestamptz not null default now(),
  expires_at timestamptz not null,
  report_count int not null default 1,
  confidence numeric not null default 0.3 check (confidence between 0 and 1),
  verified boolean not null default false,
  source text not null default 'community',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on public.facility_operational_overrides (facility_id, kind, expires_at);

-- ───────────────────────────── Community observations ─────────────────────────────
-- Reporter coordinates are never stored: only distance to the facility and fix accuracy.

create table public.occupancy_reports (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references public.facilities (id) on delete cascade,
  user_id uuid references auth.users (id) on delete set null,
  status text not null check (status in ('courts_open','mostly_full','all_full','players_waiting')),
  occupied_courts int check (occupied_courts between 0 and 200),
  groups_waiting int check (groups_waiting between 0 and 100),
  usable_courts_seen int check (usable_courts_seen between 0 and 200),
  location_verified boolean not null,
  distance_m numeric,
  accuracy_m numeric,
  reported_at timestamptz not null default now(),
  expires_at timestamptz not null,
  trust_weight numeric not null,
  integrity_score numeric not null,
  client_report_id uuid,
  unique (user_id, client_report_id)
);
create index on public.occupancy_reports (facility_id, reported_at desc);
create index on public.occupancy_reports (user_id, reported_at desc);

create table public.paddle_stack_reports (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references public.facilities (id) on delete cascade,
  user_id uuid references auth.users (id) on delete set null,
  level text not null check (level in ('none','short','medium','long')),
  paddles numeric check (paddles between 0 and 100),
  location_verified boolean not null,
  distance_m numeric,
  reported_at timestamptz not null default now(),
  expires_at timestamptz not null,
  trust_weight numeric not null,
  integrity_score numeric not null
);
create index on public.paddle_stack_reports (facility_id, reported_at desc);
create index on public.paddle_stack_reports (user_id, reported_at desc);

create table public.surface_reports (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references public.facilities (id) on delete cascade,
  user_id uuid references auth.users (id) on delete set null,
  condition text not null check (condition in ('dry','slightly_damp','wet','standing_water','debris','ice_snow',
    'construction','unsafe')),
  location_verified boolean not null,
  distance_m numeric,
  reported_at timestamptz not null default now(),
  expires_at timestamptz not null,
  trust_weight numeric not null,
  integrity_score numeric not null
);
create index on public.surface_reports (facility_id, reported_at desc);
create index on public.surface_reports (user_id, reported_at desc);

create table public.skill_observations (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references public.facilities (id) on delete cascade,
  user_id uuid references auth.users (id) on delete set null,
  band text not null check (band in ('beginner','2.0-2.5','2.5-3.0','3.0-3.5','3.5-4.0','4.0-4.5','4.5+')),
  observed_at timestamptz not null default now(),
  trust_weight numeric not null default 0.5
);
create index on public.skill_observations (facility_id, observed_at desc);

create table public.play_culture_observations (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references public.facilities (id) on delete cascade,
  user_id uuid references auth.users (id) on delete set null,
  tag text not null check (tag in ('open_play','organized_rotation','challenge_court','mostly_doubles',
    'singles_available','beginner_friendly','casual','competitive','mixed')),
  observed_at timestamptz not null default now(),
  trust_weight numeric not null default 0.5
);
create index on public.play_culture_observations (facility_id, observed_at desc);

-- Arrival/departure only. No GPS trails.
create table public.visits (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references public.facilities (id) on delete cascade,
  user_id uuid references auth.users (id) on delete set null,
  arrival_at timestamptz not null,
  departure_at timestamptz,
  detection_method text not null check (detection_method in ('foreground','region_monitoring','report')),
  confidence numeric not null default 0.5 check (confidence between 0 and 1),
  created_at timestamptz not null default now(),
  check (departure_at is null or (departure_at > arrival_at and departure_at - arrival_at < interval '10 hours'))
);
create index on public.visits (facility_id, arrival_at desc);

-- Compact archive for raw observations older than the hot window (retention policy, see 0004).
create table private.observation_archive (
  id uuid primary key,
  table_name text not null,
  facility_id uuid not null,
  observed_at timestamptz not null,
  data jsonb not null,
  archived_at timestamptz not null default now()
);
create index on private.observation_archive (facility_id, observed_at);

-- ───────────────────────────── Derived / predictions ─────────────────────────────

create table public.occupancy_aggregates (
  facility_id uuid not null references public.facilities (id) on delete cascade,
  day_of_week smallint not null check (day_of_week between 0 and 6),
  bucket smallint not null check (bucket between 0 and 47),
  sample_count int not null,
  avg_occupancy numeric not null,
  median_occupancy numeric,
  median_wait_minutes numeric,
  variance numeric,
  updated_at timestamptz not null default now(),
  primary key (facility_id, day_of_week, bucket)
);

create table public.session_duration_aggregates (
  facility_id uuid primary key references public.facilities (id) on delete cascade,
  median_minutes numeric not null,
  p25_minutes numeric not null,
  p75_minutes numeric not null,
  sample_count int not null,
  updated_at timestamptz not null default now()
);

-- Reserved for server-side predictions (notifications, Phase 64). The app computes predictions on-device.
create table public.wait_predictions (
  facility_id uuid primary key references public.facilities (id) on delete cascade,
  computed_at timestamptz not null default now(),
  valid_until timestamptz not null,
  payload jsonb not null
);

create table public.weather_snapshots (
  geohash5 text primary key,
  observed_at timestamptz not null,
  payload jsonb not null
);

-- ───────────────────────────── Cold start ─────────────────────────────

create table public.region_coverage (
  geohash text primary key,
  facility_count int not null default 0,
  last_imported_at timestamptz,
  source text,
  import_status text not null default 'never' check (import_status in
    ('never','queued','importing','imported','failed','deferred')),
  last_attempt_at timestamptz,
  attempt_count int not null default 0,
  next_eligible_at timestamptz,
  error text
);

create table private.region_import_log (
  id bigint generated always as identity primary key,
  geohash text not null,
  source text not null,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  status text not null,
  fetched int,
  inserted int,
  merged int,
  error text
);

create table public.report_prompt_state (
  user_id uuid not null references auth.users (id) on delete cascade,
  facility_id uuid not null references public.facilities (id) on delete cascade,
  prompt_type text not null check (prompt_type in ('how_busy','paddle_wait','court_surface','confirm_exists')),
  last_prompted_at timestamptz,
  last_reported_at timestamptz,
  dismissal_count int not null default 0,
  visit_id uuid,
  primary key (user_id, facility_id, prompt_type)
);

-- Privacy-conscious analytics: no user id, no device id, no coordinates.
create table private.analytics_events (
  id bigint generated always as identity primary key,
  event text not null,
  facility_id uuid,
  props jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default date_trunc('minute', now())
);

-- ───────────────────────────── Triggers ─────────────────────────────

create or replace function private.normalize_name(p text) returns text
language sql immutable as $$
  select trim(regexp_replace(
    regexp_replace(
      regexp_replace(lower(coalesce(p, '')), '[^a-z0-9 ]+', ' ', 'g'),
      '\m(the|of|at|and|courts?|pickleball|tennis|facility|complex)\M', ' ', 'g'),
    '\s+', ' ', 'g'))
$$;

create or replace function private.facilities_before_write() returns trigger
language plpgsql as $$
begin
  new.latitude := st_y(new.location::geometry);
  new.longitude := st_x(new.location::geometry);
  new.geohash4 := st_geohash(new.location::geometry, 4);
  new.name_normalized := private.normalize_name(new.name);
  new.updated_at := now();
  return new;
end $$;

create trigger facilities_before_write before insert or update on public.facilities
for each row execute function private.facilities_before_write();

create or replace function private.touch_updated_at() returns trigger
language plpgsql as $$ begin new.updated_at := now(); return new; end $$;

create trigger profiles_touch before update on public.profiles for each row execute function private.touch_updated_at();
create trigger access_touch before update on public.facility_access for each row execute function private.touch_updated_at();
create trigger costs_touch before update on public.facility_costs for each row execute function private.touch_updated_at();
create trigger blackouts_touch before update on public.facility_blackouts for each row execute function private.touch_updated_at();
create trigger overrides_touch before update on public.facility_operational_overrides for each row execute function private.touch_updated_at();

-- ───────────────────────────── Default configuration ─────────────────────────────

insert into public.app_config (key, value, is_public, description) values
  ('environment', '"development"', true, 'development | production — production down-weights simulated locations'),
  ('live_gating_enabled', 'false', true, 'When true, detailed live observations require contributor status. Off during cold start.'),
  ('contributor_insights_days', '7', true, 'Days of live insights granted per qualifying contribution'),
  ('report_radius_m', '250', true, 'Facility radius for location-verified reports'),
  ('allow_unverified_live_reports', 'false', false, 'Dev only: accept live reports from far away'),
  ('reports_per_hour_limit', '12', false, 'Per-user live report rate limit'),
  ('same_facility_cooldown_minutes', '10', false, 'Minimum minutes between same-kind reports at a facility'),
  ('submissions_per_day_limit', '5', false, 'Per-user new facility submissions per day'),
  ('region_import_cooldown_hours', '6', false, 'Retry backoff for failed region imports'),
  ('region_import_fresh_days', '30', false, 'Region coverage considered fresh for this many days'),
  ('region_imports_per_hour', '20', false, 'Global budget for external imports'),
  ('prediction', '{"half_life_minutes":25,"live_max_age_minutes":180,"default_game_minutes":13}', true, 'Prediction V1 overrides'),
  ('prompt_policy', '{"same_facility_cooldown_hours":3,"min_gap_minutes":20,"short_backoff_days":3,"long_backoff_days":14}', true, 'Prompt fatigue overrides');
