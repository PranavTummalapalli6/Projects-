-- RPCs and private helpers. All trust, integrity, verification and entitlement logic lives here.
set search_path = public, extensions;

-- ───────────────────────────── Private helpers ─────────────────────────────

create or replace function private.config_num(p_key text, p_default numeric) returns numeric
language sql stable set search_path = public, extensions, pg_temp as $$
  select coalesce((select (value #>> '{}')::numeric from public.app_config where key = p_key), p_default)
$$;

create or replace function private.config_bool(p_key text, p_default boolean) returns boolean
language sql stable set search_path = public, extensions, pg_temp as $$
  select coalesce((select (value #>> '{}')::boolean from public.app_config where key = p_key), p_default)
$$;

create or replace function private.is_production() returns boolean
language sql stable set search_path = public, extensions, pg_temp as $$
  select coalesce((select value #>> '{}' from public.app_config where key = 'environment'), 'development') = 'production'
$$;

create or replace function private.require_user() returns uuid
language plpgsql stable set search_path = public, extensions, pg_temp as $$
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  return auth.uid();
end $$;

create or replace function private.safe_tz(p_tz text) returns text
language sql stable set search_path = public, extensions, pg_temp as $$
  select case when exists (select 1 from pg_timezone_names where name = p_tz) then p_tz else 'UTC' end
$$;

create or replace function private.valid_point(p_lat double precision, p_lng double precision) returns boolean
language sql immutable as $$
  select p_lat between -90 and 90 and p_lng between -180 and 180
     and not (abs(p_lat) < 0.0001 and abs(p_lng) < 0.0001)
     and p_lat = p_lat and p_lng = p_lng   -- rejects NaN
$$;

create or replace function private.make_point(p_lat double precision, p_lng double precision) returns geography
language sql immutable set search_path = public, extensions, pg_temp as $$
  select st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography
$$;

create or replace function private.has_live_insights(p_uid uuid) returns boolean
language sql stable set search_path = public, extensions, pg_temp as $$
  select not private.config_bool('live_gating_enabled', false)
      or exists (select 1 from public.contributor_status c where c.user_id = p_uid and c.insights_until > now())
$$;

-- All of a user's recent contributions (facility + time only).
create or replace function private.user_recent_reports(p_uid uuid, p_window interval)
returns table (facility_id uuid, at timestamptz)
language sql stable set search_path = public, extensions, pg_temp as $$
  select facility_id, reported_at from public.occupancy_reports where user_id = p_uid and reported_at > now() - p_window
  union all
  select facility_id, reported_at from public.paddle_stack_reports where user_id = p_uid and reported_at > now() - p_window
  union all
  select facility_id, reported_at from public.surface_reports where user_id = p_uid and reported_at > now() - p_window
  union all
  select facility_id, created_at from public.facility_issue_reports where user_id = p_uid and created_at > now() - p_window
$$;

create or replace function private.reported_recently(p_uid uuid, p_facility_id uuid, p_kind text, p_minutes numeric)
returns boolean language sql stable set search_path = public, extensions, pg_temp as $$
  select case p_kind
    when 'occupancy' then exists (select 1 from public.occupancy_reports where user_id = p_uid and facility_id = p_facility_id
                                   and reported_at > now() - make_interval(mins => p_minutes::int))
    when 'paddle_stack' then exists (select 1 from public.paddle_stack_reports where user_id = p_uid and facility_id = p_facility_id
                                   and reported_at > now() - make_interval(mins => p_minutes::int))
    when 'surface' then exists (select 1 from public.surface_reports where user_id = p_uid and facility_id = p_facility_id
                                   and reported_at > now() - make_interval(mins => p_minutes::int))
    else false end
$$;

create or replace function private.account_age_factor(p_uid uuid) returns numeric
language sql stable set search_path = public, extensions, pg_temp as $$
  select case when coalesce((select created_at from auth.users where id = p_uid), now()) > now() - interval '1 day'
              then 0.7 else 1.0 end
$$;

-- Internal integrity score (0..1). Mirrors PickleCore.IntegrityRiskEvaluator. Never returned to clients.
create or replace function private.compute_integrity(
  p_uid uuid, p_facility_id uuid, p_accuracy double precision, p_fix_age double precision, p_simulated boolean
) returns numeric
language plpgsql stable set search_path = public, extensions, pg_temp as $$
declare
  s numeric := 1;
  v_loc geography;
  v_last record;
  v_hours numeric;
  v_km numeric;
  v_recent int;
  v_facilities int;
begin
  select location into v_loc from public.facilities where id = p_facility_id;
  if coalesce(p_simulated, false) and private.is_production() then s := s * 0.2; end if;
  if p_accuracy is null or p_accuracy > 65 then s := s * 0.7; end if;
  if p_fix_age is null or p_fix_age > 60 then s := s * 0.8; end if;

  select r.facility_id, r.at, f.location as loc into v_last
  from private.user_recent_reports(p_uid, interval '6 hours') r
  join public.facilities f on f.id = r.facility_id
  order by r.at desc limit 1;
  if found and v_last.facility_id <> p_facility_id then
    v_hours := greatest(extract(epoch from now() - v_last.at) / 3600, 1.0 / 60);
    v_km := st_distance(v_last.loc, v_loc) / 1000;
    if v_km / v_hours > 150 then s := s * 0.25; end if;
  end if;

  select count(*) into v_recent from private.user_recent_reports(p_uid, interval '10 minutes');
  if v_recent >= 4 then s := s * 0.5; end if;

  select count(distinct x.facility_id) into v_facilities from (
    select r.facility_id from private.user_recent_reports(p_uid, interval '1 hour') r
    union select p_facility_id) x;
  if v_facilities > 3 then s := s * 0.5; end if;

  return greatest(0, least(1, s));
end $$;

create or replace function private.implied_occupancy(p_status text) returns numeric
language sql immutable as $$
  select case p_status when 'courts_open' then 0.45 when 'mostly_full' then 0.85
                       when 'all_full' then 1.0 when 'players_waiting' then 1.0 end
$$;

-- Down-weights a report that sharply contradicts a fresh, multi-report consensus.
create or replace function private.contradiction_factor(p_facility_id uuid, p_status text) returns numeric
language sql stable set search_path = public, extensions, pg_temp as $$
  select case when count(*) >= 2
               and abs(sum(private.implied_occupancy(status) * trust_weight) / nullif(sum(trust_weight), 0)
                       - private.implied_occupancy(p_status)) > 0.5
         then 0.7 else 1.0 end
  from public.occupancy_reports
  where facility_id = p_facility_id and reported_at > now() - interval '15 minutes' and trust_weight >= 0.3
$$;

create or replace function private.grant_contributor(p_uid uuid) returns timestamptz
language plpgsql set search_path = public, extensions, pg_temp as $$
declare v_until timestamptz := now() + make_interval(days => private.config_num('contributor_insights_days', 7)::int);
begin
  insert into public.contributor_status as c (user_id, insights_until, qualifying_contributions, last_contribution_at)
  values (p_uid, v_until, 1, now())
  on conflict (user_id) do update
    set insights_until = greatest(c.insights_until, excluded.insights_until),
        qualifying_contributions = c.qualifying_contributions + 1,
        last_contribution_at = now(),
        updated_at = now()
  returning insights_until into v_until;
  return v_until;
end $$;

create or replace function private.issue_ttl(p_kind text) returns interval
language sql immutable as $$
  select case p_kind
    when 'tournament' then interval '12 hours'
    when 'locked_gates' then interval '6 hours'
    when 'temporarily_unavailable' then interval '24 hours'
    when 'unsafe_surface' then interval '24 hours'
    when 'pickleball_prohibited' then interval '72 hours'
    else interval '48 hours' end
$$;

-- Negative reports propagate fast: confidence = 1 − e^(−0.7·Σtrust) over distinct recent reporters.
create or replace function private.recompute_issue_override(p_facility_id uuid, p_kind text) returns jsonb
language plpgsql set search_path = public, extensions, pg_temp as $$
declare
  v_n int; v_w numeric; v_last timestamptz; v_conf numeric; v_id uuid;
begin
  select count(distinct user_id), coalesce(sum(trust_weight), 0), max(created_at)
    into v_n, v_w, v_last
  from public.facility_issue_reports
  where facility_id = p_facility_id and kind = p_kind and created_at > now() - private.issue_ttl(p_kind);

  if v_n = 0 then return null; end if;
  v_conf := least(1, 1 - exp(-0.7 * v_w));

  update public.facility_operational_overrides
     set report_count = v_n, confidence = greatest(confidence * 0.5, v_conf), expires_at = v_last + private.issue_ttl(p_kind)
   where facility_id = p_facility_id and kind = p_kind and source = 'community' and expires_at > now()
  returning id into v_id;
  if v_id is null then
    insert into public.facility_operational_overrides (facility_id, kind, starts_at, expires_at, report_count, confidence, source)
    values (p_facility_id, p_kind, now(), v_last + private.issue_ttl(p_kind), v_n, v_conf, 'community');
  end if;
  return jsonb_build_object('report_count', v_n, 'confidence', round(v_conf, 2));
end $$;

-- Existence verification. Positive evidence accumulates slowly; status changes to 'closed' only via
-- moderators or the sustained-corroboration job (0004).
create or replace function private.recompute_existence(p_facility_id uuid) returns void
language plpgsql set search_path = public, extensions, pg_temp as $$
declare
  f public.facilities;
  v_pos numeric; v_pos_verified int; v_neg numeric; v_base numeric; v_conf numeric; v_status text;
begin
  select * into f from public.facilities where id = p_facility_id for update;
  if not found or f.existence_status in ('closed', 'rejected') then return; end if;

  select coalesce(sum(trust_weight) filter (where kind = 'exists'), 0),
         count(*) filter (where kind = 'exists' and location_verified),
         coalesce(sum(trust_weight) filter (where kind = 'not_exists'), 0)
    into v_pos, v_pos_verified, v_neg
  from public.facility_confirmations where facility_id = p_facility_id;

  v_base := case when f.source = 'community' then 0.2 else 0.6 end;
  v_conf := greatest(0, least(1, v_base + 0.15 * v_pos - 0.2 * v_neg));
  v_status := f.existence_status;
  if v_pos_verified >= 4 and f.created_at < now() - interval '24 hours' and v_neg < v_pos / 2 then
    v_status := 'verified';
  elsif v_pos_verified >= 2 and v_status in ('pending', 'community_reported') then
    v_status := 'partially_verified';
  elsif v_status = 'pending' and v_pos_verified >= 1 and v_neg = 0 then
    v_status := 'community_reported';
  end if;

  update public.facilities set existence_confidence = v_conf, existence_status = v_status where id = p_facility_id;
end $$;

-- Builds the wire-format facility object consumed by PickleCore.Facility.
create or replace function private.facility_json(f public.facilities, p_entitled boolean, p_tz text, p_now timestamptz)
returns jsonb language sql stable set search_path = public, extensions, pg_temp as $$
  select jsonb_build_object(
    'id', f.id, 'name', f.name, 'latitude', f.latitude, 'longitude', f.longitude,
    'address', f.address, 'city', f.city, 'state', f.state, 'postal_code', f.postal_code,
    'time_zone', coalesce(f.time_zone, p_tz),
    'total_physical_courts', f.total_physical_courts, 'default_pickleball_courts', f.default_pickleball_courts,
    'court_type', f.court_type, 'indoor_outdoor', f.indoor_outdoor,
    'has_lights', f.has_lights, 'has_restrooms', f.has_restrooms, 'has_water', f.has_water, 'has_parking', f.has_parking,
    'play_system', f.play_system, 'typical_game_minutes', f.typical_game_minutes, 'source', f.source,
    'existence_status', f.existence_status, 'existence_confidence', f.existence_confidence,
    'access', (select jsonb_build_object(
        'access_type', a.access_type, 'access_notes', a.access_notes, 'reservation_required', a.reservation_required,
        'reservation_available', a.reservation_available, 'permit_required', a.permit_required,
        'verification_status', a.verification_status, 'confidence', a.confidence, 'last_verified_at', a.last_verified_at)
      from public.facility_access a where a.facility_id = f.id),
    'cost', (select jsonb_build_object(
        'cost_type', c.cost_type, 'day_pass_price', c.day_pass_price, 'reservation_fee', c.reservation_fee,
        'pricing_notes', c.pricing_notes, 'last_verified_at', c.last_verified_at)
      from public.facility_costs c where c.facility_id = f.id),
    'hours', coalesce((select jsonb_agg(jsonb_build_object(
        'day_of_week', h.day_of_week, 'opens', left(h.opens::text, 5), 'closes', left(h.closes::text, 5), 'notes', h.notes)
        order by h.day_of_week, h.opens)
      from public.facility_hours h where h.facility_id = f.id), '[]'::jsonb),
    'blackouts', coalesce((select jsonb_agg(jsonb_build_object(
        'id', b.id, 'start_at', b.start_at, 'end_at', b.end_at, 'reason', b.reason, 'description', b.description,
        'verification_status', b.verification_status, 'confidence', b.confidence, 'courts_affected', b.courts_affected)
        order by b.start_at)
      from public.facility_blackouts b
      where b.facility_id = f.id and b.end_at > p_now and b.start_at < p_now + interval '7 days'
        and b.verification_status <> 'rejected'), '[]'::jsonb),
    'overrides', coalesce((select jsonb_agg(jsonb_build_object(
        'id', o.id, 'kind', o.kind, 'value', o.value, 'note', o.note, 'starts_at', o.starts_at, 'expires_at', o.expires_at,
        'report_count', o.report_count, 'confidence', round(o.confidence, 2), 'verified', o.verified))
      from public.facility_operational_overrides o
      where o.facility_id = f.id and o.expires_at > p_now and o.starts_at <= p_now), '[]'::jsonb),
    'surface', (select jsonb_build_object('condition', s.condition, 'age_minutes', round(s.age, 1),
                                          'report_count', s.n, 'confidence', round(least(1, s.w / 1.5), 2))
      from (select condition,
                   (extract(epoch from p_now - max(reported_at)) / 60)::numeric as age,
                   count(*) as n,
                   sum(trust_weight * exp(-ln(2) * extract(epoch from p_now - reported_at) / 3600))::numeric as w
            from public.surface_reports
            where facility_id = f.id and reported_at > p_now - interval '3 hours' and expires_at > p_now
            group by condition order by w desc limit 1) s),
    'skill', (select case when count(*) = 0 then null else jsonb_build_object(
                'bands', jsonb_agg(jsonb_build_object('band', x.band, 'weight', round(x.w, 2))),
                'observation_count', sum(x.n), 'newest_days_ago', round(min(x.newest), 1)) end
      from (select band, count(*) as n,
                   sum(trust_weight * exp(-ln(2) * extract(epoch from p_now - observed_at) / 86400 / 90))::numeric as w,
                   min(extract(epoch from p_now - observed_at) / 86400)::numeric as newest
            from public.skill_observations
            where facility_id = f.id and observed_at > p_now - interval '365 days'
            group by band) x),
    'culture', coalesce((select jsonb_agg(jsonb_build_object('tag', c.tag, 'share', round(c.share, 2), 'observation_count', c.n))
      from (select tag, count(distinct user_id) as n,
                   count(distinct user_id)::numeric / nullif((
                     select count(distinct p2.user_id) from public.play_culture_observations p2
                     where p2.facility_id = f.id and p2.observed_at > p_now - interval '365 days'), 0) as share
            from public.play_culture_observations
            where facility_id = f.id and observed_at > p_now - interval '365 days'
            group by tag) c), '[]'::jsonb),
    'historical_now', (select jsonb_build_object(
        'day_of_week', a.day_of_week, 'bucket', a.bucket, 'sample_count', a.sample_count,
        'avg_occupancy', round(a.avg_occupancy, 3), 'median_wait_minutes', a.median_wait_minutes, 'variance', a.variance)
      from public.occupancy_aggregates a,
           lateral (select p_now at time zone coalesce(f.time_zone, p_tz) as lt) t
      where a.facility_id = f.id
        and a.day_of_week = extract(dow from t.lt)
        and a.bucket = extract(hour from t.lt)::int * 2 + case when extract(minute from t.lt) >= 30 then 1 else 0 end),
    'session_stats', (select jsonb_build_object('median_minutes', s.median_minutes, 'p25_minutes', s.p25_minutes,
                                                'p75_minutes', s.p75_minutes, 'sample_count', s.sample_count)
      from public.session_duration_aggregates s where s.facility_id = f.id and s.sample_count >= 10),
    'live', case when p_entitled then jsonb_build_object('observations', coalesce((
        select jsonb_agg(o.obj order by o.age) from (
          (select extract(epoch from p_now - r.reported_at) / 60 as age, jsonb_build_object(
              'kind', 'occupancy', 'age_minutes', round((extract(epoch from p_now - r.reported_at) / 60)::numeric, 1),
              'status', r.status, 'occupied_courts', r.occupied_courts, 'groups_waiting', r.groups_waiting,
              'weight', round(r.trust_weight, 1), 'location_verified', r.location_verified) as obj
           from public.occupancy_reports r
           where r.facility_id = f.id and r.reported_at > p_now - interval '3 hours' and r.expires_at > p_now
             and r.trust_weight >= 0.05
           order by r.reported_at desc limit 20)
          union all
          (select extract(epoch from p_now - p.reported_at) / 60, jsonb_build_object(
              'kind', 'paddle_stack', 'age_minutes', round((extract(epoch from p_now - p.reported_at) / 60)::numeric, 1),
              'paddles', coalesce(p.paddles, case p.level when 'none' then 0 when 'short' then 4 when 'medium' then 9 else 16 end),
              'weight', round(p.trust_weight, 1), 'location_verified', p.location_verified)
           from public.paddle_stack_reports p
           where p.facility_id = f.id and p.reported_at > p_now - interval '3 hours' and p.expires_at > p_now
             and p.trust_weight >= 0.05
           order by p.reported_at desc limit 10)
        ) o), '[]'::jsonb)) else null end
  )
$$;

-- ───────────────────────────── Read RPCs ─────────────────────────────

create or replace function public.nearby_facilities(
  p_min_lat double precision, p_min_lng double precision, p_max_lat double precision, p_max_lng double precision,
  p_limit int default 150, p_time_zone text default 'UTC'
) returns jsonb
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare
  v_center geography;
  v_entitled boolean := private.has_live_insights(auth.uid());
  v_tz text := private.safe_tz(p_time_zone);
  v_now timestamptz := now();
begin
  if p_min_lat is null or p_min_lng is null or p_max_lat is null or p_max_lng is null
     or p_max_lat <= p_min_lat or p_max_lng <= p_min_lng
     or p_min_lat < -90 or p_max_lat > 90 or p_min_lng < -180 or p_max_lng > 180 then
    raise exception 'invalid bounding box' using errcode = '22023';
  end if;
  if (p_max_lat - p_min_lat) > 3 or (p_max_lng - p_min_lng) > 3 then
    raise exception 'bounding box too large; zoom in' using errcode = '22023';
  end if;
  v_center := private.make_point((p_min_lat + p_max_lat) / 2, (p_min_lng + p_max_lng) / 2);

  return coalesce((
    with ids as (
      select f.id from public.facilities f
      where f.location && st_makeenvelope(p_min_lng, p_min_lat, p_max_lng, p_max_lat, 4326)::geography
        and f.existence_status <> 'rejected'
        and (f.existence_status <> 'pending' or f.created_by = auth.uid())
      order by f.location <-> v_center
      limit least(greatest(coalesce(p_limit, 150), 1), 300))
    select jsonb_agg(private.facility_json(f, v_entitled, v_tz, v_now) order by st_distance(f.location, v_center))
    from public.facilities f join ids using (id)
  ), '[]'::jsonb);
end $$;

create or replace function public.facility_detail(p_facility_id uuid, p_time_zone text default 'UTC') returns jsonb
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare
  f public.facilities;
  v_tz text := private.safe_tz(p_time_zone);
begin
  select * into f from public.facilities
  where id = p_facility_id and existence_status <> 'rejected'
    and (existence_status <> 'pending' or created_by = auth.uid());
  if not found then return null; end if;

  return jsonb_build_object(
    'facility', private.facility_json(f, private.has_live_insights(auth.uid()), v_tz, now()),
    'week_buckets', coalesce((select jsonb_agg(jsonb_build_object(
        'day_of_week', a.day_of_week, 'bucket', a.bucket, 'sample_count', a.sample_count,
        'avg_occupancy', round(a.avg_occupancy, 3), 'median_wait_minutes', a.median_wait_minutes, 'variance', a.variance)
        order by a.day_of_week, a.bucket)
      from public.occupancy_aggregates a where a.facility_id = f.id), '[]'::jsonb),
    'rules', coalesce((select jsonb_agg(jsonb_build_object('kind', r.kind, 'text', r.rule_text) order by r.created_at)
      from public.facility_rules r where r.facility_id = f.id), '[]'::jsonb),
    'photos', coalesce((select jsonb_agg(p.storage_path order by p.created_at desc)
      from (select storage_path, created_at from public.facility_photos
            where facility_id = f.id and verification_status = 'approved' order by created_at desc limit 8) p), '[]'::jsonb),
    'sources', coalesce((select jsonb_agg(distinct s.source) from public.facility_sources s where s.facility_id = f.id), '[]'::jsonb),
    'my_confirmation', (select kind from public.facility_confirmations
                        where facility_id = f.id and user_id = auth.uid() and kind in ('exists', 'not_exists')
                        order by created_at desc limit 1),
    'confirmation_count', (select count(distinct user_id) from public.facility_confirmations
                           where facility_id = f.id and kind = 'exists')
  );
end $$;

create or replace function public.search_facilities(
  p_query text, p_latitude double precision default null, p_longitude double precision default null,
  p_time_zone text default 'UTC'
) returns jsonb
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare
  q text := trim(coalesce(p_query, ''));
  nq text := private.normalize_name(p_query);
  v_near geography;
  v_entitled boolean := private.has_live_insights(auth.uid());
  v_tz text := private.safe_tz(p_time_zone);
begin
  if char_length(q) < 2 or char_length(q) > 100 then return '[]'::jsonb; end if;
  if p_latitude is not null and p_longitude is not null and private.valid_point(p_latitude, p_longitude) then
    v_near := private.make_point(p_latitude, p_longitude);
  end if;
  return coalesce((
    with hits as (
      select f.id,
             greatest(similarity(f.name_normalized, nq),
                      case when f.postal_code = q then 1 else 0 end,
                      case when lower(f.city) = lower(q) then 0.9 else 0 end) as score,
             case when v_near is null then 0 else st_distance(f.location, v_near) end as dist
      from public.facilities f
      where f.existence_status not in ('rejected', 'pending')
        and (f.name_normalized % nq or f.name ilike '%' || q || '%' or f.postal_code = q or lower(f.city) = lower(q))
      order by 2 desc, 3 asc
      limit 20)
    select jsonb_agg(private.facility_json(f, v_entitled, v_tz, now()) order by h.score desc, h.dist asc)
    from hits h join public.facilities f on f.id = h.id
  ), '[]'::jsonb);
end $$;

create or replace function public.find_duplicate_facilities(
  p_latitude double precision, p_longitude double precision, p_name text default null
) returns jsonb
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare
  pt geography;
  nq text := private.normalize_name(p_name);
begin
  if not private.valid_point(p_latitude, p_longitude) then
    raise exception 'invalid location' using errcode = '22023';
  end if;
  pt := private.make_point(p_latitude, p_longitude);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'facility_id', c.id, 'name', c.name, 'distance_meters', round(c.d::numeric), 'name_similarity', round(c.sim::numeric, 2),
      'existence_status', c.existence_status, 'latitude', c.latitude, 'longitude', c.longitude)
      order by (1 - c.d / 400) * 0.5 + c.sim * 0.5 desc)
    from (
      select f.id, f.name, f.existence_status, f.latitude, f.longitude,
             st_distance(f.location, pt) as d,
             case when nq = '' then 0 else similarity(f.name_normalized, nq) end as sim
      from public.facilities f
      where st_dwithin(f.location, pt, 400) and f.existence_status not in ('rejected')
    ) c
    where c.d <= 60 or (c.d <= 250 and (c.sim >= 0.45 or nq = '')) or c.sim >= 0.8
  ), '[]'::jsonb);
end $$;

create or replace function public.my_contributor_status() returns jsonb
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select jsonb_build_object(
    'insights_until', (select insights_until from public.contributor_status where user_id = auth.uid()),
    'qualifying_contributions', coalesce((select qualifying_contributions from public.contributor_status where user_id = auth.uid()), 0),
    'has_live_insights', private.has_live_insights(auth.uid()),
    'live_gating_enabled', private.config_bool('live_gating_enabled', false))
$$;

-- ───────────────────────────── Write RPCs ─────────────────────────────

create or replace function public.submit_live_report(
  p_facility_id uuid,
  p_kind text,                       -- occupancy | paddle_stack | surface | usable_courts | skill | culture
  p_value text default null,
  p_count int default null,          -- occupied courts / paddles / usable courts
  p_groups_waiting int default null,
  p_latitude double precision default null,
  p_longitude double precision default null,
  p_accuracy_m double precision default null,
  p_fix_age_seconds double precision default null,
  p_is_simulated boolean default false,
  p_client_report_id uuid default null
) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare
  v_uid uuid := private.require_user();
  v_fac public.facilities;
  v_distance numeric;
  v_verified boolean := false;
  v_integrity numeric;
  v_trust numeric;
  v_insights timestamptz;
  v_tag text;
  v_override uuid;
  v_live_kind boolean := p_kind in ('occupancy', 'paddle_stack', 'surface', 'usable_courts');
begin
  select * into v_fac from public.facilities where id = p_facility_id and existence_status not in ('rejected', 'closed');
  if not found then return jsonb_build_object('accepted', false, 'reason', 'facility_not_found'); end if;

  -- Input validation.
  if p_kind not in ('occupancy', 'paddle_stack', 'surface', 'usable_courts', 'skill', 'culture') then
    raise exception 'invalid report kind' using errcode = '22023';
  end if;
  if (p_kind = 'occupancy' and p_value not in ('courts_open', 'mostly_full', 'all_full', 'players_waiting'))
     or (p_kind = 'paddle_stack' and p_value not in ('none', 'short', 'medium', 'long'))
     or (p_kind = 'surface' and p_value not in ('dry', 'slightly_damp', 'wet', 'standing_water', 'debris', 'ice_snow', 'construction', 'unsafe'))
     or (p_kind = 'skill' and p_value not in ('beginner', '2.0-2.5', '2.5-3.0', '3.0-3.5', '3.5-4.0', '4.0-4.5', '4.5+'))
     or (p_kind = 'usable_courts' and (p_count is null or p_count < 0 or p_count > 200))
     or (p_count is not null and (p_count < 0 or p_count > 200))
     or (p_groups_waiting is not null and (p_groups_waiting < 0 or p_groups_waiting > 100)) then
    raise exception 'invalid report value' using errcode = '22023';
  end if;

  -- Rate limits.
  if (select count(*) from private.user_recent_reports(v_uid, interval '1 hour')) >= private.config_num('reports_per_hour_limit', 12) then
    return jsonb_build_object('accepted', false, 'reason', 'rate_limited');
  end if;
  if private.reported_recently(v_uid, p_facility_id, p_kind, private.config_num('same_facility_cooldown_minutes', 10)) then
    return jsonb_build_object('accepted', false, 'reason', 'too_soon');
  end if;

  -- Location verification (server-side; the client's pre-check is advisory only).
  if p_latitude is not null and p_longitude is not null and private.valid_point(p_latitude, p_longitude) then
    v_distance := st_distance(private.make_point(p_latitude, p_longitude), v_fac.location);
    v_verified := coalesce(p_accuracy_m, 9999) <= 150
              and coalesce(p_fix_age_seconds, 9999) <= 120
              and v_distance <= private.config_num('report_radius_m', 250) + least(coalesce(p_accuracy_m, 0), 75);
  end if;
  if v_live_kind and not v_verified and not private.config_bool('allow_unverified_live_reports', false) then
    return jsonb_build_object('accepted', false, 'reason', 'not_nearby');
  end if;

  v_integrity := private.compute_integrity(v_uid, p_facility_id, p_accuracy_m, p_fix_age_seconds, p_is_simulated);
  v_trust := round((case when v_verified then 1.0 else 0.25 end) * v_integrity * private.account_age_factor(v_uid), 3);

  if p_kind = 'occupancy' then
    v_trust := v_trust * private.contradiction_factor(p_facility_id, p_value);
    insert into public.occupancy_reports (facility_id, user_id, status, occupied_courts, groups_waiting, location_verified,
                                          distance_m, accuracy_m, expires_at, trust_weight, integrity_score, client_report_id)
    values (p_facility_id, v_uid, p_value, p_count, p_groups_waiting, v_verified, round(v_distance), p_accuracy_m,
            now() + interval '3 hours', v_trust, v_integrity, p_client_report_id)
    on conflict (user_id, client_report_id) do nothing;
    -- A verified "it's operating" observation halves stale negative warnings (asymmetric trust).
    if v_verified then
      update public.facility_operational_overrides set confidence = confidence * 0.5
      where facility_id = p_facility_id and kind in ('possible_closure', 'temporarily_unavailable', 'locked_gates')
        and expires_at > now() and not verified;
    end if;
  elsif p_kind = 'paddle_stack' then
    insert into public.paddle_stack_reports (facility_id, user_id, level, paddles, location_verified, distance_m,
                                             expires_at, trust_weight, integrity_score)
    values (p_facility_id, v_uid, p_value, p_count, v_verified, round(v_distance), now() + interval '90 minutes', v_trust, v_integrity);
  elsif p_kind = 'surface' then
    insert into public.surface_reports (facility_id, user_id, condition, location_verified, distance_m,
                                        expires_at, trust_weight, integrity_score)
    values (p_facility_id, v_uid, p_value, v_verified, round(v_distance),
            now() + case when p_value in ('construction', 'unsafe') then interval '24 hours' else interval '4 hours' end,
            v_trust, v_integrity);
  elsif p_kind = 'usable_courts' then
    update public.facility_operational_overrides
       set confidence = case when value = p_count then 1 - (1 - confidence) * (1 - 0.6 * v_trust) else 0.6 * v_trust end,
           value = p_count, report_count = report_count + 1, expires_at = now() + interval '4 hours'
     where facility_id = p_facility_id and kind = 'usable_courts' and expires_at > now()
    returning id into v_override;
    if v_override is null then
      insert into public.facility_operational_overrides (facility_id, kind, value, expires_at, confidence, source)
      values (p_facility_id, 'usable_courts', p_count, now() + interval '4 hours', 0.6 * v_trust, 'community');
    end if;
  elsif p_kind = 'skill' then
    insert into public.skill_observations (facility_id, user_id, band, trust_weight) values (p_facility_id, v_uid, p_value, v_trust);
  elsif p_kind = 'culture' then
    foreach v_tag in array string_to_array(coalesce(p_value, ''), ',') loop
      v_tag := trim(v_tag);
      if v_tag in ('open_play', 'organized_rotation', 'challenge_court', 'mostly_doubles', 'singles_available',
                   'beginner_friendly', 'casual', 'competitive', 'mixed') then
        insert into public.play_culture_observations (facility_id, user_id, tag, trust_weight) values (p_facility_id, v_uid, v_tag, v_trust);
      end if;
    end loop;
  end if;

  if v_live_kind and v_trust >= 0.4 then
    v_insights := private.grant_contributor(v_uid);
  end if;

  return jsonb_build_object('accepted', true, 'location_verified', v_verified, 'insights_until', v_insights);
end $$;

create or replace function public.report_facility_issue(
  p_facility_id uuid, p_kind text, p_note text default null,
  p_latitude double precision default null, p_longitude double precision default null,
  p_accuracy_m double precision default null, p_fix_age_seconds double precision default null,
  p_is_simulated boolean default false
) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare
  v_uid uuid := private.require_user();
  v_fac public.facilities;
  v_verified boolean := false;
  v_distance numeric;
  v_integrity numeric;
  v_trust numeric;
  v_result jsonb;
begin
  if p_kind not in ('possible_closure', 'temporarily_unavailable', 'locked_gates', 'construction', 'nets_removed',
                    'pickleball_prohibited', 'unsafe_surface', 'tournament') then
    raise exception 'invalid issue kind' using errcode = '22023';
  end if;
  select * into v_fac from public.facilities where id = p_facility_id and existence_status <> 'rejected';
  if not found then return jsonb_build_object('accepted', false, 'reason', 'facility_not_found'); end if;
  if (select count(*) from public.facility_issue_reports where user_id = v_uid and created_at > now() - interval '1 hour') >= 6 then
    return jsonb_build_object('accepted', false, 'reason', 'rate_limited');
  end if;
  if exists (select 1 from public.facility_issue_reports where user_id = v_uid and facility_id = p_facility_id
             and kind = p_kind and created_at > now() - interval '6 hours') then
    return jsonb_build_object('accepted', false, 'reason', 'too_soon');
  end if;

  if p_latitude is not null and p_longitude is not null and private.valid_point(p_latitude, p_longitude) then
    v_distance := st_distance(private.make_point(p_latitude, p_longitude), v_fac.location);
    v_verified := coalesce(p_accuracy_m, 9999) <= 150 and coalesce(p_fix_age_seconds, 9999) <= 120
              and v_distance <= private.config_num('report_radius_m', 250) + least(coalesce(p_accuracy_m, 0), 75);
  end if;
  v_integrity := private.compute_integrity(v_uid, p_facility_id, p_accuracy_m, p_fix_age_seconds, p_is_simulated);
  v_trust := (case when v_verified then 1.0 else 0.25 end) * v_integrity * private.account_age_factor(v_uid);

  insert into public.facility_issue_reports (facility_id, user_id, kind, note, location_verified, trust_weight, integrity_score)
  values (p_facility_id, v_uid, p_kind, left(p_note, 300), v_verified, v_trust, v_integrity);

  v_result := private.recompute_issue_override(p_facility_id, p_kind);
  if v_verified and v_trust >= 0.4 then perform private.grant_contributor(v_uid); end if;
  return jsonb_build_object('accepted', true, 'location_verified', v_verified,
                            'state', case when (v_result ->> 'confidence')::numeric >= 0.6 or (v_result ->> 'report_count')::int >= 2
                                          then 'unavailable' else 'warning' end);
end $$;

create or replace function public.submit_facility(
  p_latitude double precision, p_longitude double precision,
  p_name text default null,
  p_court_count int default null,
  p_court_type text default 'unknown',
  p_indoor_outdoor text default 'outdoor',
  p_has_lights boolean default null,
  p_access_type text default 'unknown',
  p_cost_type text default 'unknown',
  p_play_system text default 'unknown',
  p_notes text default null,
  p_hours_note text default null,
  p_force_new boolean default false,
  p_user_latitude double precision default null,
  p_user_longitude double precision default null,
  p_user_accuracy_m double precision default null
) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare
  v_uid uuid := private.require_user();
  v_pt geography;
  v_candidates jsonb;
  v_user_distance numeric;
  v_facility_id uuid;
  v_submission_id uuid;
  v_status text := 'community_reported';
  v_conf numeric := 0.2;
  v_name text := nullif(trim(coalesce(p_name, '')), '');
begin
  if not private.valid_point(p_latitude, p_longitude) then
    return jsonb_build_object('status', 'invalid', 'reason', 'invalid_location');
  end if;
  if p_court_count is not null and (p_court_count < 1 or p_court_count > 60) then
    return jsonb_build_object('status', 'invalid', 'reason', 'court_count_out_of_range');
  end if;
  if char_length(coalesce(v_name, '')) > 120 or v_name ~* '(https?://|www\.|@)' then
    return jsonb_build_object('status', 'invalid', 'reason', 'invalid_name');
  end if;
  if char_length(coalesce(p_notes, '')) > 500 or char_length(coalesce(p_hours_note, '')) > 500 then
    return jsonb_build_object('status', 'invalid', 'reason', 'notes_too_long');
  end if;
  if (select count(*) from public.facility_submissions where submitted_by = v_uid and created_at > now() - interval '1 day')
     >= private.config_num('submissions_per_day_limit', 5) then
    return jsonb_build_object('status', 'rate_limited');
  end if;

  v_pt := private.make_point(p_latitude, p_longitude);
  v_candidates := public.find_duplicate_facilities(p_latitude, p_longitude, v_name);
  if jsonb_array_length(v_candidates) > 0 and (
       not p_force_new
       or exists (select 1 from jsonb_array_elements(v_candidates) c where (c ->> 'distance_meters')::numeric <= 30)) then
    return jsonb_build_object('status', 'duplicate_candidates', 'candidates', v_candidates);
  end if;

  if p_user_latitude is not null and private.valid_point(p_user_latitude, p_user_longitude) then
    v_user_distance := st_distance(private.make_point(p_user_latitude, p_user_longitude), v_pt);
    if v_user_distance <= 300 and coalesce(p_user_accuracy_m, 9999) <= 150 then v_conf := 0.35; end if;
  end if;
  -- Accounts with several rejected submissions go to moderation first.
  if (select count(*) from public.facility_submissions where submitted_by = v_uid and status = 'rejected') >= 3 then
    v_status := 'pending';
  end if;

  insert into public.facilities (name, location, total_physical_courts, default_pickleball_courts, court_type,
                                 indoor_outdoor, has_lights, play_system, source, source_last_updated,
                                 existence_status, existence_confidence, created_by)
  values (coalesce(v_name, 'Pickleball courts'), v_pt, p_court_count, p_court_count, p_court_type,
          p_indoor_outdoor, p_has_lights, p_play_system, 'community', now(), v_status, v_conf, v_uid)
  returning id into v_facility_id;

  insert into public.facility_access (facility_id, access_type, verification_status, confidence)
  values (v_facility_id, p_access_type, 'community_reported', case when p_access_type = 'unknown' then 0 else 0.2 end);
  insert into public.facility_costs (facility_id, cost_type, last_verified_at)
  values (v_facility_id, p_cost_type, case when p_cost_type = 'unknown' then null else now() end);
  if nullif(trim(coalesce(p_notes, '')), '') is not null then
    insert into public.facility_rules (facility_id, kind, rule_text) values (v_facility_id, 'general', trim(p_notes));
  end if;
  if nullif(trim(coalesce(p_hours_note, '')), '') is not null then
    insert into public.facility_rules (facility_id, kind, rule_text) values (v_facility_id, 'hours_note', trim(p_hours_note));
  end if;

  insert into public.facility_submissions (submitted_by, location, payload, status, resulting_facility_id, submitter_distance_m)
  values (v_uid, v_pt, jsonb_build_object('name', v_name, 'court_count', p_court_count, 'court_type', p_court_type,
            'indoor_outdoor', p_indoor_outdoor, 'has_lights', p_has_lights, 'access_type', p_access_type,
            'cost_type', p_cost_type, 'play_system', p_play_system, 'notes', p_notes, 'hours_note', p_hours_note),
          case when v_status = 'pending' then 'pending' else 'accepted' end, v_facility_id, round(v_user_distance))
  returning id into v_submission_id;

  insert into public.facility_sources (facility_id, source, external_id) values (v_facility_id, 'community', v_submission_id::text);
  insert into public.facility_confirmations (facility_id, user_id, kind, location_verified, trust_weight)
  values (v_facility_id, v_uid, 'exists', v_conf >= 0.35, 0.5);

  return jsonb_build_object('status', 'created', 'facility_id', v_facility_id, 'submission_id', v_submission_id,
                            'existence_status', v_status, 'insights_until', private.grant_contributor(v_uid));
end $$;

create or replace function public.confirm_facility(
  p_facility_id uuid, p_exists boolean,
  p_latitude double precision default null, p_longitude double precision default null,
  p_accuracy_m double precision default null, p_fix_age_seconds double precision default null,
  p_is_simulated boolean default false
) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare
  v_uid uuid := private.require_user();
  v_fac public.facilities;
  v_verified boolean := false;
  v_trust numeric;
begin
  select * into v_fac from public.facilities where id = p_facility_id and existence_status <> 'rejected';
  if not found then return jsonb_build_object('accepted', false, 'reason', 'facility_not_found'); end if;
  if v_fac.created_by = v_uid then return jsonb_build_object('accepted', false, 'reason', 'own_submission'); end if;

  if p_latitude is not null and p_longitude is not null and private.valid_point(p_latitude, p_longitude) then
    v_verified := coalesce(p_accuracy_m, 9999) <= 150 and coalesce(p_fix_age_seconds, 9999) <= 300
              and st_distance(private.make_point(p_latitude, p_longitude), v_fac.location) <= 300;
  end if;
  v_trust := (case when v_verified then 1.0 else 0.25 end)
           * private.compute_integrity(v_uid, p_facility_id, p_accuracy_m, p_fix_age_seconds, p_is_simulated)
           * private.account_age_factor(v_uid);

  delete from public.facility_confirmations where facility_id = p_facility_id and user_id = v_uid
    and kind = case when p_exists then 'not_exists' else 'exists' end;
  insert into public.facility_confirmations (facility_id, user_id, kind, location_verified, trust_weight)
  values (p_facility_id, v_uid, case when p_exists then 'exists' else 'not_exists' end, v_verified, v_trust)
  on conflict (facility_id, user_id, kind) do update
    set location_verified = excluded.location_verified, trust_weight = excluded.trust_weight, created_at = now();

  if not p_exists then
    -- "Not here" is a high-impact negative signal: also feed the fast-propagating closure path.
    if not exists (select 1 from public.facility_issue_reports where user_id = v_uid and facility_id = p_facility_id
                   and kind = 'possible_closure' and created_at > now() - interval '6 hours') then
      insert into public.facility_issue_reports (facility_id, user_id, kind, location_verified, trust_weight, integrity_score)
      values (p_facility_id, v_uid, 'possible_closure', v_verified, v_trust, v_trust);
      perform private.recompute_issue_override(p_facility_id, 'possible_closure');
    end if;
  end if;

  perform private.recompute_existence(p_facility_id);
  if v_verified and v_trust >= 0.4 then perform private.grant_contributor(v_uid); end if;

  select * into v_fac from public.facilities where id = p_facility_id;
  return jsonb_build_object('accepted', true, 'location_verified', v_verified,
                            'existence_status', v_fac.existence_status, 'existence_confidence', v_fac.existence_confidence);
end $$;

-- Applies a sufficiently supported low-risk edit. High-impact edits stay open for moderators.
create or replace function private.apply_edit(p_suggestion_id uuid) returns boolean
language plpgsql set search_path = public, extensions, pg_temp as $$
declare
  e public.facility_edit_suggestions;
  p jsonb;
begin
  select * into e from public.facility_edit_suggestions where id = p_suggestion_id and status = 'open' for update;
  if not found then return false; end if;
  p := e.proposed;
  begin
    case e.edit_type
      when 'court_count_changed', 'pickleball_courts_added' then
        update public.facilities set
          total_physical_courts = coalesce((p ->> 'total_physical_courts')::int, total_physical_courts),
          default_pickleball_courts = coalesce((p ->> 'default_pickleball_courts')::int, default_pickleball_courts)
        where id = e.facility_id;
      when 'striped_for_pickleball' then
        update public.facilities set court_type = 'pickleball_lined_tennis',
          default_pickleball_courts = coalesce((p ->> 'default_pickleball_courts')::int, default_pickleball_courts)
        where id = e.facility_id;
      when 'converted_to_dedicated' then
        update public.facilities set court_type = 'dedicated_pickleball',
          default_pickleball_courts = coalesce((p ->> 'default_pickleball_courts')::int, default_pickleball_courts)
        where id = e.facility_id;
      when 'indoor_outdoor_changed' then
        update public.facilities set indoor_outdoor = p ->> 'indoor_outdoor' where id = e.facility_id;
      when 'play_system_changed' then
        update public.facilities set play_system = p ->> 'play_system' where id = e.facility_id;
      when 'amenities_changed' then
        update public.facilities set
          has_lights = coalesce((p ->> 'has_lights')::boolean, has_lights),
          has_restrooms = coalesce((p ->> 'has_restrooms')::boolean, has_restrooms),
          has_water = coalesce((p ->> 'has_water')::boolean, has_water),
          has_parking = coalesce((p ->> 'has_parking')::boolean, has_parking)
        where id = e.facility_id;
      when 'access_changed' then
        update public.facility_access set access_type = coalesce(p ->> 'access_type', access_type),
          access_notes = coalesce(p ->> 'access_notes', access_notes),
          verification_status = 'community_reported', confidence = 0.5, last_verified_at = now()
        where facility_id = e.facility_id;
      when 'reservation_policy_changed' then
        update public.facility_access set
          reservation_required = coalesce((p ->> 'reservation_required')::boolean, reservation_required),
          reservation_available = coalesce((p ->> 'reservation_available')::boolean, reservation_available),
          last_verified_at = now()
        where facility_id = e.facility_id;
      when 'cost_changed' then
        update public.facility_costs set cost_type = coalesce(p ->> 'cost_type', cost_type),
          day_pass_price = coalesce((p ->> 'day_pass_price')::numeric, day_pass_price),
          reservation_fee = coalesce((p ->> 'reservation_fee')::numeric, reservation_fee),
          pricing_notes = coalesce(p ->> 'pricing_notes', pricing_notes),
          last_verified_at = now()
        where facility_id = e.facility_id;
      when 'hours_changed' then
        insert into public.facility_rules (facility_id, kind, rule_text)
        values (e.facility_id, 'hours_note', left(coalesce(p ->> 'hours_note', e.note, ''), 500));
      else
        return false;   -- permanently_closed, no_longer_pickleball, other → moderators
    end case;
  exception when others then
    update public.facility_edit_suggestions set status = 'rejected', resolved_at = now() where id = e.id;
    return false;
  end;
  update public.facility_edit_suggestions set status = 'applied', resolved_at = now() where id = e.id;
  update public.facility_edit_suggestions set status = 'superseded', resolved_at = now()
  where facility_id = e.facility_id and edit_type = e.edit_type and status = 'open' and id <> e.id;
  return true;
end $$;

create or replace function public.suggest_edit(
  p_facility_id uuid, p_edit_type text, p_proposed jsonb default '{}'::jsonb, p_note text default null,
  p_latitude double precision default null, p_longitude double precision default null,
  p_accuracy_m double precision default null
) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare
  v_uid uuid := private.require_user();
  v_fac public.facilities;
  v_verified boolean := false;
  v_trust numeric;
  v_id uuid;
  e public.facility_edit_suggestions;
  v_needed int;
  v_applied boolean := false;
begin
  select * into v_fac from public.facilities where id = p_facility_id and existence_status <> 'rejected';
  if not found then return jsonb_build_object('status', 'facility_not_found'); end if;
  if p_edit_type not in ('permanently_closed', 'court_count_changed', 'pickleball_courts_added', 'striped_for_pickleball',
      'converted_to_dedicated', 'no_longer_pickleball', 'indoor_outdoor_changed', 'access_changed', 'cost_changed',
      'reservation_policy_changed', 'play_system_changed', 'hours_changed', 'amenities_changed', 'other') then
    raise exception 'invalid edit type' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_proposed, '{}'::jsonb)) <> 'object' or octet_length(coalesce(p_proposed, '{}'::jsonb)::text) > 2048
     or char_length(coalesce(p_note, '')) > 500 then
    raise exception 'invalid edit payload' using errcode = '22023';
  end if;
  if (select count(*) from public.facility_edit_suggestions where user_id = v_uid and created_at > now() - interval '1 day') >= 20 then
    return jsonb_build_object('status', 'rate_limited');
  end if;

  if p_latitude is not null and p_longitude is not null and private.valid_point(p_latitude, p_longitude) then
    v_verified := coalesce(p_accuracy_m, 9999) <= 150
              and st_distance(private.make_point(p_latitude, p_longitude), v_fac.location) <= 300;
  end if;
  v_trust := (case when v_verified then 1.0 else 0.4 end) * private.account_age_factor(v_uid);

  -- High-impact negatives also go through the fast warning path.
  if p_edit_type = 'permanently_closed' then
    perform public.report_facility_issue(p_facility_id, 'possible_closure', p_note, p_latitude, p_longitude, p_accuracy_m, 0, false);
  elsif p_edit_type = 'no_longer_pickleball' then
    perform public.report_facility_issue(p_facility_id, 'pickleball_prohibited', p_note, p_latitude, p_longitude, p_accuracy_m, 0, false);
  end if;

  select * into e from public.facility_edit_suggestions
  where facility_id = p_facility_id and edit_type = p_edit_type and status = 'open' and proposed = coalesce(p_proposed, '{}'::jsonb)
  order by created_at limit 1 for update;
  if found then
    if v_uid = any(e.supporters) then
      return jsonb_build_object('status', 'already_supported', 'suggestion_id', e.id);
    end if;
    update public.facility_edit_suggestions
       set supporters = supporters || v_uid, support_weight = support_weight + v_trust,
           location_verified = location_verified or v_verified
     where id = e.id returning * into e;
    v_id := e.id;
  else
    insert into public.facility_edit_suggestions (facility_id, user_id, edit_type, proposed, note, supporters, support_weight, location_verified)
    values (p_facility_id, v_uid, p_edit_type, coalesce(p_proposed, '{}'::jsonb), p_note, array[v_uid], v_trust, v_verified)
    returning * into e;
    v_id := e.id;
  end if;

  v_needed := case when p_edit_type in ('access_changed', 'cost_changed') then 3 else 2 end;
  if cardinality(e.supporters) >= v_needed and e.support_weight >= 1.5 then
    v_applied := private.apply_edit(v_id);
  end if;
  if v_verified then perform private.grant_contributor(v_uid); end if;
  return jsonb_build_object('status', case when v_applied then 'applied' else 'recorded' end, 'suggestion_id', v_id);
end $$;

create or replace function public.register_photo(
  p_storage_path text, p_facility_id uuid default null, p_submission_id uuid default null, p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare
  v_uid uuid := private.require_user();
  v_id uuid;
begin
  if p_storage_path !~ ('^' || v_uid::text || '/[0-9a-f-]{36}\.(jpg|jpeg|png|heic)$') then
    raise exception 'invalid storage path' using errcode = '22023';
  end if;
  if not exists (select 1 from storage.objects where bucket_id = 'facility-photos' and name = p_storage_path) then
    raise exception 'photo not uploaded' using errcode = '22023';
  end if;
  if (select count(*) from public.facility_photos where uploaded_by = v_uid and created_at > now() - interval '1 day') >= 10 then
    return jsonb_build_object('status', 'rate_limited');
  end if;
  if p_submission_id is not null and not exists (
      select 1 from public.facility_submissions where id = p_submission_id and submitted_by = v_uid) then
    raise exception 'unknown submission' using errcode = '22023';
  end if;
  insert into public.facility_photos (facility_id, submission_id, uploaded_by, storage_path, metadata)
  values (p_facility_id, p_submission_id, v_uid, p_storage_path,
          jsonb_strip_nulls(jsonb_build_object('width', p_metadata -> 'width', 'height', p_metadata -> 'height',
                                               'bytes', p_metadata -> 'bytes')))
  returning id into v_id;
  return jsonb_build_object('status', 'registered', 'photo_id', v_id);
end $$;

create or replace function public.upsert_profile(
  p_skill_band text default 'unknown', p_cost_preference text default 'no_preference',
  p_prefers_competitive boolean default null, p_wants_beginner_friendly boolean default false,
  p_passive_visits_enabled boolean default false
) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare v_uid uuid := private.require_user(); r public.profiles;
begin
  insert into public.profiles as pr (id, skill_band, cost_preference, prefers_competitive, wants_beginner_friendly, passive_visits_enabled)
  values (v_uid, p_skill_band, p_cost_preference, p_prefers_competitive, p_wants_beginner_friendly, p_passive_visits_enabled)
  on conflict (id) do update set skill_band = excluded.skill_band, cost_preference = excluded.cost_preference,
    prefers_competitive = excluded.prefers_competitive, wants_beginner_friendly = excluded.wants_beginner_friendly,
    passive_visits_enabled = excluded.passive_visits_enabled
  returning * into r;
  return to_jsonb(r) - 'id';
end $$;

create or replace function public.record_visit(
  p_facility_id uuid, p_arrival_at timestamptz, p_departure_at timestamptz default null,
  p_detection_method text default 'foreground', p_confidence numeric default 0.5
) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare v_uid uuid := private.require_user(); v_id uuid;
begin
  if p_detection_method not in ('foreground', 'region_monitoring', 'report') then
    raise exception 'invalid detection method' using errcode = '22023';
  end if;
  if p_detection_method = 'region_monitoring' and not coalesce(
       (select passive_visits_enabled from public.profiles where id = v_uid), false) then
    return jsonb_build_object('status', 'passive_visits_disabled');
  end if;
  if p_arrival_at > now() + interval '5 minutes' or p_arrival_at < now() - interval '24 hours'
     or (p_departure_at is not null and (p_departure_at <= p_arrival_at or p_departure_at > now() + interval '5 minutes')) then
    raise exception 'implausible visit times' using errcode = '22023';
  end if;
  if not exists (select 1 from public.facilities where id = p_facility_id) then
    return jsonb_build_object('status', 'facility_not_found');
  end if;
  -- Close an open visit at the same facility instead of duplicating it.
  update public.visits set departure_at = p_departure_at, confidence = greatest(confidence, least(1, p_confidence))
   where user_id = v_uid and facility_id = p_facility_id and departure_at is null
     and arrival_at between p_arrival_at - interval '10 minutes' and p_arrival_at + interval '10 minutes'
     and p_departure_at is not null
  returning id into v_id;
  if v_id is null then
    insert into public.visits (facility_id, user_id, arrival_at, departure_at, detection_method, confidence)
    values (p_facility_id, v_uid, p_arrival_at, p_departure_at, p_detection_method, least(1, greatest(0, p_confidence)))
    returning id into v_id;
  end if;
  return jsonb_build_object('status', 'recorded', 'visit_id', v_id);
end $$;

create or replace function public.log_event(p_event text, p_facility_id uuid default null, p_props jsonb default '{}'::jsonb)
returns void
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
begin
  if p_event not in ('map_search', 'facility_open', 'directions_tap', 'prediction_view', 'report_submitted', 'court_added',
                     'court_confirmed', 'edit_suggested', 'prompt_shown', 'prompt_completed', 'prompt_dismissed',
                     'filters_changed', 'region_discovery') then
    return;
  end if;
  if octet_length(coalesce(p_props, '{}'::jsonb)::text) > 1024 then p_props := '{}'::jsonb; end if;
  insert into private.analytics_events (event, facility_id, props) values (p_event, p_facility_id, coalesce(p_props, '{}'::jsonb));
end $$;

-- ───────────────────────────── Ingestion & cold start (service role only) ─────────────────────────────

-- Normalizes + deduplicates one externally sourced facility. Returns 'inserted' | 'merged' | 'updated'.
create or replace function public.import_facility(
  p_source text, p_external_id text, p_name text, p_latitude double precision, p_longitude double precision,
  p_attrs jsonb default '{}'::jsonb
) returns text
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare
  v_pt geography;
  v_existing uuid;
  v_id uuid;
  v_courts int := nullif(p_attrs ->> 'courts', '')::int;
  v_pb int := nullif(p_attrs ->> 'pickleball_courts', '')::int;
begin
  if not private.valid_point(p_latitude, p_longitude) or coalesce(trim(p_name), '') = '' then
    raise exception 'invalid import row %', p_external_id using errcode = '22023';
  end if;
  v_pt := private.make_point(p_latitude, p_longitude);

  select facility_id into v_existing from public.facility_sources where source = p_source and external_id = p_external_id;
  if v_existing is not null then
    -- Re-import: refresh source-owned gaps only; never overwrite community-maintained values.
    update public.facilities set
      total_physical_courts = coalesce(total_physical_courts, v_courts),
      default_pickleball_courts = coalesce(default_pickleball_courts, v_pb),
      has_lights = coalesce(has_lights, (p_attrs ->> 'lit')::boolean),
      source_last_updated = now()
    where id = v_existing;
    update public.facility_sources set raw = p_attrs, imported_at = now() where source = p_source and external_id = p_external_id;
    return 'updated';
  end if;

  select f.id into v_existing from public.facilities f
  where st_dwithin(f.location, v_pt, 250) and f.existence_status <> 'rejected'
    and (st_distance(f.location, v_pt) <= 60 or similarity(f.name_normalized, private.normalize_name(p_name)) >= 0.45)
  order by st_distance(f.location, v_pt) limit 1;

  if v_existing is not null then
    insert into public.facility_sources (facility_id, source, external_id, raw) values (v_existing, p_source, p_external_id, p_attrs);
    update public.facilities set
      total_physical_courts = coalesce(total_physical_courts, v_courts),
      default_pickleball_courts = coalesce(default_pickleball_courts, v_pb),
      has_lights = coalesce(has_lights, (p_attrs ->> 'lit')::boolean),
      existence_confidence = least(1, existence_confidence + 0.1)
    where id = v_existing;
    return 'merged';
  end if;

  insert into public.facilities (name, location, address, city, state, postal_code, time_zone,
                                 total_physical_courts, default_pickleball_courts, court_type, indoor_outdoor,
                                 has_lights, play_system, source, source_last_updated, existence_status, existence_confidence)
  values (left(trim(p_name), 160), v_pt, p_attrs ->> 'address', p_attrs ->> 'city', p_attrs ->> 'state', p_attrs ->> 'postal_code',
          p_attrs ->> 'time_zone', v_courts, coalesce(v_pb, v_courts),
          coalesce(p_attrs ->> 'court_type', 'unknown'), coalesce(p_attrs ->> 'indoor_outdoor', 'outdoor'),
          (p_attrs ->> 'lit')::boolean, coalesce(p_attrs ->> 'play_system', 'unknown'),
          p_source, now(), coalesce(p_attrs ->> 'existence_status', 'partially_verified'),
          coalesce((p_attrs ->> 'existence_confidence')::numeric, 0.6))
  returning id into v_id;

  insert into public.facility_access (facility_id, access_type, access_notes, reservation_required, reservation_available,
                                      verification_status, confidence)
  values (v_id, coalesce(p_attrs ->> 'access_type', 'unknown'), p_attrs ->> 'access_notes',
          (p_attrs ->> 'reservation_required')::boolean, (p_attrs ->> 'reservation_available')::boolean,
          case when p_attrs ? 'access_type' then 'partially_verified' else 'pending' end,
          case when p_attrs ? 'access_type' then 0.5 else 0 end);
  insert into public.facility_costs (facility_id, cost_type, day_pass_price, pricing_notes)
  values (v_id, coalesce(p_attrs ->> 'cost_type', 'unknown'), (p_attrs ->> 'day_pass_price')::numeric, p_attrs ->> 'pricing_notes');
  insert into public.facility_sources (facility_id, source, external_id, raw) values (v_id, p_source, p_external_id, p_attrs);
  return 'inserted';
end $$;

-- Atomically decides whether a cold-start import may run for a geohash cell (throttling + caching).
create or replace function public.region_claim_import(p_geohash text, p_source text default 'osm_overpass') returns jsonb
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare
  r public.region_coverage;
  v_log bigint;
begin
  if p_geohash !~ '^[0-9b-hjkmnp-z]{3,6}$' then raise exception 'invalid geohash' using errcode = '22023'; end if;
  insert into public.region_coverage (geohash) values (p_geohash) on conflict do nothing;
  select * into r from public.region_coverage where geohash = p_geohash for update;

  if r.import_status = 'imported'
     and r.last_imported_at > now() - make_interval(days => private.config_num('region_import_fresh_days', 30)::int) then
    return jsonb_build_object('action', 'fresh', 'facility_count', r.facility_count, 'last_imported_at', r.last_imported_at);
  end if;
  if r.import_status = 'importing' and r.last_attempt_at > now() - interval '10 minutes' then
    return jsonb_build_object('action', 'busy');
  end if;
  if r.next_eligible_at is not null and r.next_eligible_at > now() then
    return jsonb_build_object('action', 'deferred', 'next_eligible_at', r.next_eligible_at);
  end if;
  if (select count(*) from private.region_import_log where started_at > now() - interval '1 hour')
     >= private.config_num('region_imports_per_hour', 20) then
    update public.region_coverage set import_status = 'deferred', next_eligible_at = now() + interval '15 minutes'
    where geohash = p_geohash;
    return jsonb_build_object('action', 'deferred', 'next_eligible_at', now() + interval '15 minutes');
  end if;

  update public.region_coverage set import_status = 'importing', last_attempt_at = now(), attempt_count = attempt_count + 1,
    source = p_source where geohash = p_geohash;
  insert into private.region_import_log (geohash, source, status) values (p_geohash, p_source, 'started') returning id into v_log;
  return jsonb_build_object('action', 'import', 'log_id', v_log);
end $$;

create or replace function public.region_finish_import(
  p_geohash text, p_log_id bigint, p_status text, p_fetched int default 0, p_inserted int default 0,
  p_merged int default 0, p_error text default null
) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare v_count int;
begin
  if p_status not in ('imported', 'failed') then raise exception 'invalid status' using errcode = '22023'; end if;
  select count(*) into v_count from public.facilities where geohash4 = left(p_geohash, 4) and existence_status <> 'rejected';
  update public.region_coverage set
    import_status = p_status,
    facility_count = v_count,
    last_imported_at = case when p_status = 'imported' then now() else last_imported_at end,
    next_eligible_at = case when p_status = 'failed'
                            then now() + make_interval(hours => private.config_num('region_import_cooldown_hours', 6)::int)
                            else null end,
    error = left(p_error, 500)
  where geohash = p_geohash;
  update private.region_import_log set finished_at = now(), status = p_status, fetched = p_fetched,
    inserted = p_inserted, merged = p_merged, error = left(p_error, 500)
  where id = p_log_id;
  return jsonb_build_object('facility_count', v_count);
end $$;

-- ───────────────────────────── Grants ─────────────────────────────

revoke execute on all functions in schema public from public, anon, authenticated;
revoke execute on all functions in schema private from public, anon, authenticated;

grant execute on function public.nearby_facilities(double precision, double precision, double precision, double precision, int, text) to anon, authenticated;
grant execute on function public.facility_detail(uuid, text) to anon, authenticated;
grant execute on function public.search_facilities(text, double precision, double precision, text) to anon, authenticated;
grant execute on function public.find_duplicate_facilities(double precision, double precision, text) to anon, authenticated;
grant execute on function public.log_event(text, uuid, jsonb) to anon, authenticated;

grant execute on function public.my_contributor_status() to authenticated;
grant execute on function public.submit_live_report(uuid, text, text, int, int, double precision, double precision, double precision, double precision, boolean, uuid) to authenticated;
grant execute on function public.report_facility_issue(uuid, text, text, double precision, double precision, double precision, double precision, boolean) to authenticated;
grant execute on function public.submit_facility(double precision, double precision, text, int, text, text, boolean, text, text, text, text, text, boolean, double precision, double precision, double precision) to authenticated;
grant execute on function public.confirm_facility(uuid, boolean, double precision, double precision, double precision, double precision, boolean) to authenticated;
grant execute on function public.suggest_edit(uuid, text, jsonb, text, double precision, double precision, double precision) to authenticated;
grant execute on function public.register_photo(text, uuid, uuid, jsonb) to authenticated;
grant execute on function public.upsert_profile(text, text, boolean, boolean, boolean) to authenticated;
grant execute on function public.record_visit(uuid, timestamptz, timestamptz, text, numeric) to authenticated;

grant execute on function public.import_facility(text, text, text, double precision, double precision, jsonb) to service_role;
grant execute on function public.region_claim_import(text, text) to service_role;
grant execute on function public.region_finish_import(text, bigint, text, int, int, int, text) to service_role;
