set search_path = public, extensions;
-- Row Level Security. Principle: clients may READ public facility facts directly; every WRITE goes
-- through a validated SECURITY DEFINER RPC. Trust/integrity/verification/entitlement columns are
-- therefore never client-writable.

do $$
declare t text;
begin
  foreach t in array array[
    'profiles','app_config','contributor_status','facilities','facility_sources','facility_access','facility_costs',
    'facility_hours','facility_rules','facility_submissions','facility_confirmations','facility_edit_suggestions',
    'facility_photos','facility_issue_reports','facility_blackouts','facility_operational_overrides',
    'occupancy_reports','paddle_stack_reports','surface_reports','skill_observations','play_culture_observations',
    'visits','occupancy_aggregates','session_duration_aggregates','wait_predictions','weather_snapshots',
    'region_coverage','report_prompt_state']
  loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- Public facility facts (read-only for everyone, including signed-out browsing).
create policy facilities_read on public.facilities for select to anon, authenticated
  using (existence_status <> 'rejected' and (existence_status <> 'pending' or created_by = auth.uid()));

create policy access_read on public.facility_access for select to anon, authenticated using (true);
create policy costs_read on public.facility_costs for select to anon, authenticated using (true);
create policy hours_read on public.facility_hours for select to anon, authenticated using (true);
create policy rules_read on public.facility_rules for select to anon, authenticated using (true);
create policy blackouts_read on public.facility_blackouts for select to anon, authenticated
  using (verification_status <> 'rejected');
create policy overrides_read on public.facility_operational_overrides for select to anon, authenticated using (true);
create policy aggregates_read on public.occupancy_aggregates for select to anon, authenticated using (true);
create policy sessions_read on public.session_duration_aggregates for select to anon, authenticated using (true);
create policy config_read on public.app_config for select to anon, authenticated using (is_public);

create policy photos_read on public.facility_photos for select to anon, authenticated
  using (verification_status = 'approved' or uploaded_by = auth.uid());

-- Own rows only.
create policy profiles_select_own on public.profiles for select to authenticated using (id = auth.uid());
create policy contributor_select_own on public.contributor_status for select to authenticated using (user_id = auth.uid());
create policy prompt_state_own on public.report_prompt_state for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy submissions_select_own on public.facility_submissions for select to authenticated using (submitted_by = auth.uid());
create policy edits_select_own on public.facility_edit_suggestions for select to authenticated using (user_id = auth.uid());
create policy confirmations_select_own on public.facility_confirmations for select to authenticated using (user_id = auth.uid());

-- Everything else (raw reports, sources, visits, coverage, predictions cache) has RLS enabled with no
-- client policies: readable only via aggregated RPC output or the service role.

-- Table privileges: remove default write grants entirely so a policy mistake can't open writes.
revoke insert, update, delete on all tables in schema public from anon, authenticated;
grant select on all tables in schema public to anon, authenticated;
grant insert, update, delete on public.report_prompt_state to authenticated;

-- Storage: private bucket; users upload only into their own folder; approved photos readable by all.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('facility-photos', 'facility-photos', false, 3145728, array['image/jpeg','image/png','image/heic'])
on conflict (id) do update set file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create policy photo_upload_own_folder on storage.objects for insert to authenticated
  with check (bucket_id = 'facility-photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy photo_read_own_or_approved on storage.objects for select to authenticated, anon
  using (bucket_id = 'facility-photos' and (
    (storage.foldername(name))[1] = auth.uid()::text
    or exists (select 1 from public.facility_photos p where p.storage_path = name and p.verification_status = 'approved')));

create policy photo_delete_own_pending on storage.objects for delete to authenticated
  using (bucket_id = 'facility-photos' and (storage.foldername(name))[1] = auth.uid()::text
    and not exists (select 1 from public.facility_photos p where p.storage_path = name and p.verification_status = 'approved'));
