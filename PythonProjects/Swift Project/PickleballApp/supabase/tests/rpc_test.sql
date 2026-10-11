-- Behavioural tests for RPCs, trust logic and RLS. Runs on Supabase (`supabase test db` via psql) and on the
-- local PostGIS harness. Each block raises on failure.
set search_path = public, extensions;

insert into auth.users (id, created_at) values
  ('11111111-1111-4111-8111-111111111111', now() - interval '30 days'),
  ('22222222-2222-4222-8222-222222222222', now() - interval '30 days'),
  ('33333333-3333-4333-8333-333333333333', now() - interval '30 days'),
  ('44444444-4444-4444-8444-444444444444', now() - interval '30 days');

create or replace function pg_temp.as_user(p uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p::text, ''), false);
  if p is null then set role anon; else set role authenticated; end if;
end $$;
grant execute on function pg_temp.as_user(uuid) to anon, authenticated;

-- 1. Anonymous nearby query returns seeded facilities with sub-objects, nearest first.
do $$
declare r jsonb;
begin
  perform pg_temp.as_user(null);
  r := public.nearby_facilities(38.80, -77.36, 38.90, -77.24, 50, 'America/New_York');
  assert jsonb_array_length(r) >= 9, 'expected seeded Fairfax facilities, got ' || jsonb_array_length(r);
  assert r -> 0 -> 'access' ->> 'access_type' is not null, 'access sub-object missing';
  assert jsonb_typeof(r -> 0 -> 'hours') = 'array', 'hours missing';
  assert (select count(*) from jsonb_array_elements(r) e where e ->> 'name' = 'Laurel Creek Park') = 1, 'Laurel Creek missing';
  reset role;
end $$;

-- 2. Oversized bounding boxes are rejected (cost control).
do $$
begin
  perform public.nearby_facilities(30, -90, 40, -70);
  raise exception 'expected bbox rejection';
exception when sqlstate '22023' then null;
end $$;

-- 3. RLS: raw observations are invisible; direct writes are denied.
do $$
declare n int;
begin
  perform pg_temp.as_user('11111111-1111-4111-8111-111111111111');
  begin
    insert into public.facilities (name, location) values ('Hack', 'SRID=4326;POINT(-77 38)');
    raise exception 'direct insert should be denied';
  exception when insufficient_privilege then null;
  end;
  begin
    update public.facility_access set verification_status = 'verified';
    raise exception 'direct update should be denied';
  exception when insufficient_privilege then null;
  end;
  select count(*) into n from public.occupancy_reports; assert n = 0, 'occupancy_reports must not be readable';
  select count(*) into n from public.contributor_status where user_id <> auth.uid(); assert n = 0;
  reset role;
end $$;

-- 4. Location-verified occupancy report accepted; far-away rejected; cooldown enforced.
do $$
declare r jsonb; fid uuid;
begin
  select id into fid from public.facilities where name = 'Laurel Creek Park';
  perform pg_temp.as_user('11111111-1111-4111-8111-111111111111');
  r := public.submit_live_report(fid, 'occupancy', 'all_full', null, 2, 38.8463, -77.3065, 12, 5, false, gen_random_uuid());
  assert (r ->> 'accepted')::boolean and (r ->> 'location_verified')::boolean, 'nearby report should be accepted: ' || r;
  assert r ->> 'insights_until' is not null, 'contributor insights should be granted';
  r := public.submit_live_report(fid, 'occupancy', 'courts_open', null, null, 38.8463, -77.3065, 12, 5, false, gen_random_uuid());
  assert r ->> 'reason' = 'too_soon', 'cooldown expected: ' || r;
  perform pg_temp.as_user('22222222-2222-4222-8222-222222222222');
  r := public.submit_live_report(fid, 'occupancy', 'courts_open', null, null, 38.70, -77.30, 12, 5, false, gen_random_uuid());
  assert r ->> 'reason' = 'not_nearby', '12 miles away must be rejected: ' || r;
  reset role;
end $$;

-- 5. Integrity: simulated location in production is down-weighted (internal only).
do $$
declare r jsonb; fid uuid; w numeric;
begin
  update public.app_config set value = '"production"' where key = 'environment';
  select id into fid from public.facilities where name = 'Cedar Run Pickleball Complex';
  perform pg_temp.as_user('22222222-2222-4222-8222-222222222222');
  r := public.submit_live_report(fid, 'paddle_stack', 'long', 20, null, 38.8212, -77.2651, 10, 3, true, null);
  reset role;
  select trust_weight into w from public.paddle_stack_reports where facility_id = fid order by reported_at desc limit 1;
  assert w < 0.3, 'simulated location should be down-weighted, got ' || w;
  update public.app_config set value = '"development"' where key = 'environment';
end $$;

-- 6. Live gating: non-contributors get no live detail; contributors do.
do $$
declare r jsonb;
begin
  update public.app_config set value = 'true' where key = 'live_gating_enabled';
  perform pg_temp.as_user('33333333-3333-4333-8333-333333333333');
  r := public.nearby_facilities(38.84, -77.32, 38.85, -77.30);
  assert (select e -> 'live' from jsonb_array_elements(r) e where e ->> 'name' = 'Laurel Creek Park') = 'null'::jsonb,
    'non-contributor must not see live detail';
  perform pg_temp.as_user('11111111-1111-4111-8111-111111111111');
  r := public.nearby_facilities(38.84, -77.32, 38.85, -77.30);
  assert jsonb_array_length((select e -> 'live' -> 'observations' from jsonb_array_elements(r) e where e ->> 'name' = 'Laurel Creek Park')) = 1,
    'contributor should see live observation';
  reset role;
  update public.app_config set value = 'false' where key = 'live_gating_enabled';
end $$;

-- 7. Add court: duplicate detection, then creation of a genuinely new court.
do $$
declare r jsonb; new_id uuid;
begin
  perform pg_temp.as_user('11111111-1111-4111-8111-111111111111');
  r := public.submit_facility(38.8464, -77.3066, 'Laurel Creek Pk');
  assert r ->> 'status' = 'duplicate_candidates', 'duplicate expected: ' || r;
  assert r -> 'candidates' -> 0 ->> 'name' = 'Laurel Creek Park';
  r := public.submit_facility(38.8000, -77.4000, 'Brookside HOA Courts', 2, 'pickleball_lined_tennis', 'outdoor', null,
                              'hoa', 'unknown', 'unknown', null, null, false, 38.8001, -77.4001, 10);
  assert r ->> 'status' = 'created', 'creation expected: ' || r;
  new_id := (r ->> 'facility_id')::uuid;
  assert (select existence_status from public.facilities where id = new_id) = 'community_reported';
  reset role;

  -- 8. Two independent location-verified confirmations → partially verified.
  perform pg_temp.as_user('22222222-2222-4222-8222-222222222222');
  perform public.confirm_facility(new_id, true, 38.8001, -77.4001, 10, 5);
  perform pg_temp.as_user('33333333-3333-4333-8333-333333333333');
  r := public.confirm_facility(new_id, true, 38.8001, -77.4001, 10, 5);
  assert r ->> 'existence_status' = 'partially_verified', 'expected partially_verified: ' || r;
  perform pg_temp.as_user('11111111-1111-4111-8111-111111111111');
  r := public.confirm_facility(new_id, true, 38.8001, -77.4001, 10, 5);
  assert r ->> 'reason' = 'own_submission', 'submitter cannot self-confirm';
  reset role;
end $$;

-- 9. Negative reports propagate fast: one → warning, two independent → unavailable.
do $$
declare r jsonb; fid uuid;
begin
  select id into fid from public.facilities where name = 'Oak Hollow Community Courts';
  perform pg_temp.as_user('33333333-3333-4333-8333-333333333333');
  r := public.report_facility_issue(fid, 'locked_gates', 'Chain on gate', 38.8304, -77.3291, 10, 5);
  assert r ->> 'state' = 'warning', 'single report should warn: ' || r;
  perform pg_temp.as_user('44444444-4444-4444-8444-444444444444');
  r := public.report_facility_issue(fid, 'locked_gates', null, 38.8304, -77.3291, 10, 5);
  assert r ->> 'state' = 'unavailable', 'two reports should mark unavailable: ' || r;
  reset role;
  assert (select existence_status from public.facilities where id = fid) <> 'closed', 'must never close on reports alone';
end $$;

-- 10. Suggest-an-edit: low-risk edit applies after two verified supporters.
do $$
declare r jsonb; fid uuid;
begin
  select id into fid from public.facilities where name = 'Willow Pond Park';
  perform pg_temp.as_user('11111111-1111-4111-8111-111111111111');
  r := public.suggest_edit(fid, 'amenities_changed', '{"has_lights": true}', null, 38.8793, -77.3012, 10);
  assert r ->> 'status' = 'recorded';
  perform pg_temp.as_user('22222222-2222-4222-8222-222222222222');
  r := public.suggest_edit(fid, 'amenities_changed', '{"has_lights": true}', null, 38.8793, -77.3012, 10);
  assert r ->> 'status' = 'applied', 'expected applied: ' || r;
  reset role;
  assert (select has_lights from public.facilities where id = fid), 'lights should now be recorded';
end $$;

-- 11. Search by name, city and ZIP-less fuzzy match.
do $$
declare r jsonb;
begin
  perform pg_temp.as_user(null);
  r := public.search_facilities('laurel creek', 38.85, -77.3);
  assert r -> 0 ->> 'name' = 'Laurel Creek Park', 'search failed: ' || coalesce(r::text, 'null');
  r := public.search_facilities('Cupertino');
  assert jsonb_array_length(r) >= 4, 'city search failed';
  reset role;
end $$;

-- 12. Facility detail, aggregation & retention jobs run cleanly.
do $$
declare r jsonb; fid uuid;
begin
  select id into fid from public.facilities where name = 'Laurel Creek Park';
  perform private.refresh_occupancy_aggregates();
  perform private.archive_raw_observations();
  perform private.corroborate_closures();
  perform pg_temp.as_user(null);
  r := public.facility_detail(fid, 'America/New_York');
  assert r -> 'facility' ->> 'name' = 'Laurel Creek Park';
  assert jsonb_array_length(r -> 'week_buckets') >= 1, 'aggregates expected';
  assert r -> 'facility' -> 'skill' ->> 'observation_count' is not null, 'skill summary expected';
  reset role;
end $$;

-- 13. Region cold-start throttling: fresh cells are served from cache, not re-imported.
do $$
declare r jsonb;
begin
  r := public.region_claim_import('dqbv');
  assert r ->> 'action' = 'import';
  perform public.region_finish_import('dqbv', (r ->> 'log_id')::bigint, 'imported', 10, 8, 2);
  r := public.region_claim_import('dqbv');
  assert r ->> 'action' = 'fresh', 'fresh cell must not re-import: ' || r;
end $$;

-- 14. Anonymous callers cannot write.
do $$
begin
  perform pg_temp.as_user(null);
  begin
    perform public.submit_live_report(gen_random_uuid(), 'occupancy', 'courts_open');
    raise exception 'anon write should fail';
  exception when insufficient_privilege then null;
  end;
  reset role;
end $$;

select 'rpc tests passed';
