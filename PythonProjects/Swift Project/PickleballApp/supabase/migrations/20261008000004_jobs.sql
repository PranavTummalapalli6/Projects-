-- Scheduled maintenance: historical aggregation, retention/archival, closure corroboration.
set search_path = public, extensions;

-- Rebuilds 30-minute occupancy buckets from the hot window of trust-weighted reports.
create or replace function private.refresh_occupancy_aggregates() returns int
language plpgsql set search_path = public, extensions, pg_temp as $$
declare v_rows int;
begin
  with obs as (
    select r.facility_id,
           (r.reported_at at time zone coalesce(f.time_zone, 'UTC')) as lt,
           coalesce(least(1, r.occupied_courts::numeric / nullif(coalesce(r.usable_courts_seen, f.default_pickleball_courts, f.total_physical_courts), 0)),
                    private.implied_occupancy(r.status)) as occ,
           r.trust_weight as w
    from public.occupancy_reports r join public.facilities f on f.id = r.facility_id
    where r.reported_at > now() - interval '120 days' and r.trust_weight >= 0.2
  ), bucketed as (
    select facility_id, extract(dow from lt)::smallint as dow,
           (extract(hour from lt)::int * 2 + case when extract(minute from lt) >= 30 then 1 else 0 end)::smallint as bucket,
           occ, w
    from obs
  ), agg as (
    select facility_id, dow, bucket, count(*) as n,
           sum(occ * w) / nullif(sum(w), 0) as avg_occ,
           percentile_cont(0.5) within group (order by occ) as median_occ,
           var_samp(occ) as variance
    from bucketed group by facility_id, dow, bucket
  )
  insert into public.occupancy_aggregates (facility_id, day_of_week, bucket, sample_count, avg_occupancy, median_occupancy, variance, updated_at)
  select facility_id, dow, bucket, n, avg_occ, median_occ, variance, now() from agg where avg_occ is not null
  on conflict (facility_id, day_of_week, bucket) do update set
    sample_count = excluded.sample_count, avg_occupancy = excluded.avg_occupancy,
    median_occupancy = excluded.median_occupancy, variance = excluded.variance, updated_at = now();
  get diagnostics v_rows = row_count;

  -- Session durations (stay-until-finished model) from privacy-conscious arrival/departure pairs.
  insert into public.session_duration_aggregates (facility_id, median_minutes, p25_minutes, p75_minutes, sample_count, updated_at)
  select facility_id,
         percentile_cont(0.5) within group (order by m), percentile_cont(0.25) within group (order by m),
         percentile_cont(0.75) within group (order by m), count(*), now()
  from (select facility_id, extract(epoch from departure_at - arrival_at) / 60 as m
        from public.visits where departure_at is not null and arrival_at > now() - interval '180 days'
          and departure_at - arrival_at between interval '10 minutes' and interval '5 hours') v
  group by facility_id
  on conflict (facility_id) do update set median_minutes = excluded.median_minutes, p25_minutes = excluded.p25_minutes,
    p75_minutes = excluded.p75_minutes, sample_count = excluded.sample_count, updated_at = now();

  return v_rows;
end $$;

-- Retention: raw observations stay hot for 120 days (debugging/model work), are then archived as compact
-- JSON (aggregates already captured them). Nothing is blindly deleted; the archive can be exported to
-- Storage and pruned by an operator if size ever matters.
create or replace function private.archive_raw_observations(p_hot_days int default 120) returns int
language plpgsql set search_path = public, extensions, pg_temp as $$
declare v_total int := 0; v_n int;
begin
  with moved as (
    delete from public.occupancy_reports where reported_at < now() - make_interval(days => p_hot_days) returning *)
  insert into private.observation_archive (id, table_name, facility_id, observed_at, data)
  select id, 'occupancy_reports', facility_id, reported_at, to_jsonb(moved) - 'user_id' - 'id' - 'facility_id' from moved;
  get diagnostics v_n = row_count; v_total := v_total + v_n;

  with moved as (
    delete from public.paddle_stack_reports where reported_at < now() - make_interval(days => p_hot_days) returning *)
  insert into private.observation_archive (id, table_name, facility_id, observed_at, data)
  select id, 'paddle_stack_reports', facility_id, reported_at, to_jsonb(moved) - 'user_id' - 'id' - 'facility_id' from moved;
  get diagnostics v_n = row_count; v_total := v_total + v_n;

  with moved as (
    delete from public.surface_reports where reported_at < now() - make_interval(days => p_hot_days) returning *)
  insert into private.observation_archive (id, table_name, facility_id, observed_at, data)
  select id, 'surface_reports', facility_id, reported_at, to_jsonb(moved) - 'user_id' - 'id' - 'facility_id' from moved;
  get diagnostics v_n = row_count; v_total := v_total + v_n;

  -- Visits keep only durations after the hot window (user link removed).
  update public.visits set user_id = null where user_id is not null and arrival_at < now() - make_interval(days => p_hot_days);

  delete from public.facility_operational_overrides where expires_at < now() - interval '30 days';
  delete from public.weather_snapshots where observed_at < now() - interval '2 days';
  return v_total;
end $$;

-- Sustained corroboration: ≥4 distinct users on ≥3 distinct days within 14 days reporting closure, with no
-- positive verified observation since → 'closed'. One report never closes a facility.
create or replace function private.corroborate_closures() returns int
language plpgsql set search_path = public, extensions, pg_temp as $$
declare v_n int;
begin
  with candidates as (
    select i.facility_id
    from public.facility_issue_reports i
    where i.kind = 'possible_closure' and i.created_at > now() - interval '14 days' and i.trust_weight >= 0.2
    group by i.facility_id
    having count(distinct i.user_id) >= 4 and count(distinct date_trunc('day', i.created_at)) >= 3
  )
  update public.facilities f set existence_status = 'closed', existence_confidence = 0.1
  from candidates c
  where f.id = c.facility_id and f.existence_status not in ('closed', 'rejected')
    and not exists (select 1 from public.occupancy_reports r where r.facility_id = f.id and r.location_verified
                    and r.reported_at > (select min(created_at) from public.facility_issue_reports
                                         where facility_id = f.id and kind = 'possible_closure'
                                           and created_at > now() - interval '14 days'));
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- pg_cron is available on Supabase (Database → Extensions). Guarded so local resets without it still work.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('refresh-occupancy-aggregates', '17 3 * * *', 'select private.refresh_occupancy_aggregates()');
    perform cron.schedule('archive-raw-observations', '41 3 * * 0', 'select private.archive_raw_observations()');
    perform cron.schedule('corroborate-closures', '*/30 * * * *', 'select private.corroborate_closures()');
  end if;
end $$;
