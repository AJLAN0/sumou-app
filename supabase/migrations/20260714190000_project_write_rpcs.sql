-- =============================================================================
-- Sprint 9 · Step 6.4 — Project write RPCs: create / edit / stage update /
-- availability / team assignment. Runs AFTER Step 6.3 (depends on the hardened
-- helpers is_active_user(), is_admin(), has_feature(), manages_project(pid),
-- assigned_to_project(pid)).
--
-- Contracts mirror the current repository/mock EXACTLY:
--   create → status 'active'; default stages per ProjectType (3-stage field/
--            wedding, 7-stage social, exact ProjectStageTitles), stage 1 'current'
--            rest 'pending'; optional atomic initial team (create flow passes it).
--   edit   → basics only (name/client/dates/notes); type IMMUTABLE; NO status.
--   stage  → target 'current', earlier 'done', later 'pending'; target-only
--            updated_by/updated_at (mock defines target-only).
--   assign → replace-all team, atomic, availability-checked.
--
-- Owner decisions applied (authoritative — see docs/SUPABASE_RLS_PLAN.md §10/§11):
--   1. Canonical booking date = project_team_members.date (NOT the project range).
--   2. Booking-conflict statuses = active / in_progress / pending_closure.
--   3. Unavailability timezone = Asia/Riyadh calendar-day overlap.
--   4. Marketing (active role) bypasses ONLY project double-booking, never leave.
--
-- Guardrail (docs/BACKEND_SCOPE_GUARD.md): NO finance/payments/Rekaz/
-- notifications/FCM/push/reminders. `project_team_members.value` is assignment
-- metadata only (never finance) and is never exposed to assigned peers (Step 6.2).
--
-- All direct table writes stay DEFAULT-DENY; every mutation happens only inside
-- the SECURITY DEFINER functions below (fail closed for inactive/soft-deleted
-- callers). No table policies are added or modified. No Step-6.3 closure/tracking
-- change. Deferred (reported): manager reassignment (setProjectManager), project
-- soft-delete (no repository method), and status editing (closure-workflow only).
-- =============================================================================

-- ###########################################################################
-- 1) gen_project_serial(type) — server-side serial candidate. Uses the
-- CRYPTOGRAPHICALLY-SECURE gen_random_uuid() (v4) hex — never `random()`;
-- uniqueness = the Step-4 UNIQUE constraint + the retry loop in create_project.
-- Shape matches the Step-4 CHECK exactly (hex 0-9A-F ⊂ [A-Z0-9]). Internal only:
-- execute revoked from PUBLIC+anon and NOT granted to authenticated.
-- ###########################################################################

create or replace function public.gen_project_serial(p_type public.project_type)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_prefix text;
  v_hex    text := upper(replace(gen_random_uuid()::text, '-', '')); -- 32 hex chars
begin
  v_prefix := case p_type
                when 'field'::public.project_type   then 'FLD'
                when 'social'::public.project_type  then 'SOC'
                when 'wedding'::public.project_type then 'WED'
              end;
  return v_prefix || '-' || substr(v_hex, 1, 4) || '-' || substr(v_hex, 5, 2);
end;
$$;

revoke all on function public.gen_project_serial(public.project_type) from public;
revoke all on function public.gen_project_serial(public.project_type) from anon;

-- ###########################################################################
-- 2) is_available(uid, on_date, exclude_project_id) — boolean availability.
-- Decisions 1–4 applied. Order: null-guard → target profile live → explicit
-- LEAVE (blocks everyone incl. Marketing) → Marketing exemption (skips only the
-- project-booking check) → non-Marketing same-DATE project-booking conflict.
--
-- Riyadh calendar day for `on_date`:
--   day_start = on_date::timestamp AT TIME ZONE 'Asia/Riyadh'
--   day_end   = (on_date+1)::timestamp AT TIME ZONE 'Asia/Riyadh'
-- Leave overlap (half-open [day_start, day_end)): active row with
--   starts_at < day_end AND ends_at > day_start.  (kind/notes never read.)
--
-- Direct-call gate: only an active admin, a can_assign_photographers holder, or a
-- caller querying their OWN uid may run it (raises 42501 otherwise). Returns a
-- boolean only — no row data. SECURITY DEFINER so it can authorize + read behind
-- RLS; execute granted to authenticated (gated), revoked from PUBLIC+anon.
-- ###########################################################################

create or replace function public.is_available(
  uid                uuid,
  on_date            date,
  exclude_project_id uuid default null
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_day_start   timestamptz;
  v_day_end     timestamptz;
  v_is_marketing boolean;
begin
  -- direct-call authorization gate (also satisfied by the assign/create callers).
  if not (
    public.is_admin()
    or public.has_feature('can_assign_photographers')
    or uid = auth.uid()
  ) then
    raise exception 'not authorized to check availability' using errcode = '42501';
  end if;

  if uid is null or on_date is null then
    return false;
  end if;
  -- target profile must exist, be active, and not soft-deleted.
  perform 1 from public.profiles p
    where p.id = uid and p.is_active and p.deleted_at is null;
  if not found then
    return false;
  end if;

  v_day_start := on_date::timestamp        at time zone 'Asia/Riyadh';
  v_day_end   := (on_date + 1)::timestamp  at time zone 'Asia/Riyadh';

  -- (1) explicit leave/unavailability overlapping the Riyadh day blocks EVERYONE.
  if exists (
    select 1 from public.user_unavailability u
    where u.user_id = uid
      and u.is_active
      and u.starts_at < v_day_end
      and u.ends_at   > v_day_start
  ) then
    return false;
  end if;

  -- (2) Marketing exemption: an ACTIVE marketing role skips project double-booking
  -- (but not leave, already checked). Inactive marketing grants no exemption.
  select exists (
    select 1 from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = uid and r.code = 'marketing' and r.is_active
  ) into v_is_marketing;
  if v_is_marketing then
    return true;
  end if;

  -- (3) non-Marketing: a same-DATE assignment on a conflicting project blocks.
  if exists (
    select 1
    from public.project_team_members t
    join public.projects p on p.id = t.project_id
    where t.user_id = uid
      and t.date = on_date
      and (exclude_project_id is null or t.project_id <> exclude_project_id)
      and p.is_active
      and p.deleted_at is null
      and p.status in ('active'::public.project_status,
                       'in_progress'::public.project_status,
                       'pending_closure'::public.project_status)
  ) then
    return false;
  end if;

  return true;
end;
$$;

revoke all on function public.is_available(uuid, date, uuid) from public;
revoke all on function public.is_available(uuid, date, uuid) from anon;
grant execute on function public.is_available(uuid, date, uuid) to authenticated;

-- ###########################################################################
-- 3) _apply_project_team(project_id, members jsonb) — INTERNAL trusted routine.
-- Does NOT authorize (the caller must) and does NOT lock the project row (the
-- caller does). Replace-all + atomic. members = jsonb array of
--   {user_id: uuid|null, person_name: text, value: number, date: 'YYYY-MM-DD'|null,
--    photographer_type_ids: [uuid, ...]}.
-- Steps: validate the WHOLE proposed team first → lock internal profiles in
-- deterministic uuid order (cross-project race guard) → verify profiles/types →
-- re-check is_available AFTER the locks → only then delete+reinsert. `value` is
-- metadata only (schema has no bound → none invented). Writes ONE
-- project.team.assign audit row with a member count only.
-- Internal only: no PUBLIC/anon/authenticated grant (called by same-owner definers).
-- ###########################################################################

create or replace function public._apply_project_team(
  p_project_id uuid,
  p_members    jsonb
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid       uuid := auth.uid();
  v_members   jsonb := coalesce(p_members, '[]'::jsonb);
  m           jsonb;
  v_user_ids  uuid[] := '{}';
  v_muid      uuid;
  v_pname     text;
  v_value     numeric;
  v_date      date;
  v_member_id uuid;
  v_tid       uuid;
  v_count     integer := 0;
begin
  if jsonb_typeof(v_members) <> 'array' then
    raise exception 'invalid team payload' using errcode = '22023';
  end if;

  -- ---- validate the complete proposed team BEFORE any delete --------------
  for m in select value from jsonb_array_elements(v_members) loop
    v_count := v_count + 1;

    -- each member must be a JSON object.
    if jsonb_typeof(m) <> 'object' then
      raise exception 'each team member must be a JSON object' using errcode = '22023';
    end if;

    -- photographer_type_ids: absent → empty; if present must be a JSON array.
    if (m ? 'photographer_type_ids')
       and jsonb_typeof(m->'photographer_type_ids') <> 'array' then
      raise exception 'photographer_type_ids must be an array' using errcode = '22023';
    end if;
    -- every photographer type id must be a well-formed UUID.
    if exists (
      select 1 from jsonb_array_elements_text(coalesce(m->'photographer_type_ids','[]'::jsonb)) as e(v)
      where e.v !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    ) then
      raise exception 'invalid photographer type id' using errcode = '22023';
    end if;
    -- no duplicate type id within one member.
    if (select count(*) from jsonb_array_elements_text(coalesce(m->'photographer_type_ids','[]'::jsonb)))
       <> (select count(distinct value) from jsonb_array_elements_text(coalesce(m->'photographer_type_ids','[]'::jsonb))) then
      raise exception 'duplicate photographer type for a team member'
        using errcode = '22023';
    end if;

    -- value, if present, must be a JSON number (or null → treated as 0).
    if (m ? 'value') and jsonb_typeof(m->'value') not in ('number', 'null') then
      raise exception 'value must be numeric' using errcode = '22023';
    end if;

    if m->>'user_id' is not null then
      -- INTERNAL member: user_id must be a well-formed UUID; the stored
      -- person_name is derived from the profile (never the client input).
      if (m->>'user_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
        raise exception 'invalid user_id' using errcode = '22023';
      end if;
      v_muid := (m->>'user_id')::uuid;
      if v_muid = any (v_user_ids) then
        raise exception 'a user is assigned more than once' using errcode = '22023';
      end if;
      v_user_ids := array_append(v_user_ids, v_muid);
      if m->>'date' is null or btrim(m->>'date') = '' then
        raise exception 'assignment date is required for internal members'
          using errcode = '22023';
      end if;
    else
      -- EXTERNAL member: user_id null; a non-blank person_name is required and is
      -- stored as given (no profile/Auth account is created).
      if btrim(coalesce(m->>'person_name', '')) = '' then
        raise exception 'person_name is required for external members'
          using errcode = '22023';
      end if;
    end if;
  end loop;

  -- ---- lock internal profiles in deterministic uuid order ----------------
  -- Serializes concurrent assignments of the same user across projects, so two
  -- transactions cannot both pass availability for the same user (§7). Ordered
  -- locking also reduces deadlock risk.
  perform 1 from public.profiles p
    where p.id = any (v_user_ids)
    order by p.id
    for update;

  -- ---- verify members + types + availability (post-lock) -----------------
  for m in select value from jsonb_array_elements(v_members) loop
    if (m->>'user_id') is not null then
      v_muid := (m->>'user_id')::uuid;
      v_date := (m->>'date')::date;
      perform 1 from public.profiles p
        where p.id = v_muid and p.is_active and p.deleted_at is null;
      if not found then
        raise exception 'an assigned member is not an active profile'
          using errcode = 'P0002';
      end if;
      -- availability re-checked AFTER the profile lock; exclude THIS project so
      -- the member's own existing row here is not a self-conflict.
      if not public.is_available(v_muid, v_date, p_project_id) then
        raise exception 'an assigned member is not available on the assignment date'
          using errcode = 'P0001';
      end if;
    end if;
    -- every selected photographer type must exist and be active.
    for v_tid in
      select (value)::uuid from jsonb_array_elements_text(coalesce(m->'photographer_type_ids','[]'::jsonb))
    loop
      perform 1 from public.photographer_types pt where pt.id = v_tid and pt.is_active;
      if not found then
        raise exception 'a selected photographer type is not available'
          using errcode = 'P0002';
      end if;
    end loop;
  end loop;

  -- ---- replace-all: delete existing (cascade drops types) then insert -----
  delete from public.project_team_members where project_id = p_project_id;

  for m in select value from jsonb_array_elements(v_members) loop
    v_value := coalesce((m->>'value')::numeric, 0);
    if m->>'user_id' is not null then
      -- INTERNAL: authoritative name from the locked+verified profile — the
      -- client-supplied person_name is never used for an internal member.
      v_muid := (m->>'user_id')::uuid;
      select p.full_name into v_pname from public.profiles p where p.id = v_muid;
      v_date := (m->>'date')::date;
    else
      -- EXTERNAL: normalized input name; date optional (no availability check).
      v_muid  := null;
      v_pname := btrim(m->>'person_name');
      v_date  := nullif(btrim(coalesce(m->>'date', '')), '')::date;
    end if;

    insert into public.project_team_members (project_id, user_id, person_name, value, date)
    values (p_project_id, v_muid, v_pname, v_value, v_date)
    returning id into v_member_id;

    insert into public.project_team_types (team_member_id, photographer_type_id)
    select v_member_id, (value)::uuid
    from jsonb_array_elements_text(coalesce(m->'photographer_type_ids', '[]'::jsonb));
  end loop;

  -- audit: member count only (never names/values/dates/types/leave).
  insert into public.audit_logs (actor_id, action, entity, entity_id, meta)
  values (v_uid, 'project.team.assign', 'projects', p_project_id,
          jsonb_build_object('member_count', v_count));

  return v_count;
end;
$$;

revoke all on function public._apply_project_team(uuid, jsonb) from public;
revoke all on function public._apply_project_team(uuid, jsonb) from anon;

-- ###########################################################################
-- 4) create_project — atomically create project + default stages + optional
-- initial team + audit. Authorization: is_admin() OR has_feature('can_add_project');
-- if a non-empty initial team is supplied, ALSO is_admin()/can_assign_photographers.
-- manager_id: non-admin ⇒ auth.uid(); an admin may delegate to another profile
-- that is active, non-deleted, AND holds an active management role
-- (admin/manager/wedding_admin). Returns the new project id.
--
-- Field mapping: name←name, client_name←clientName, type←type, start_date←
-- startDate, end_date←endDate, notes←notes, manager_id←managerId, members←
-- teamRoles (grouped per person; type names→photographer_type_ids by the repo).
-- The current Flutter create flow always sets manager = the signed-in user.
-- ###########################################################################

create or replace function public.create_project(
  p_name        text,
  p_client_name text,
  p_type        public.project_type,
  p_start_date  date,
  p_end_date    date,
  p_notes       text default null,
  p_manager_id  uuid default null,
  p_members     jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid        uuid := auth.uid();
  v_manager    uuid;
  v_name       text := btrim(coalesce(p_name, ''));
  v_client     text := btrim(coalesce(p_client_name, ''));
  v_notes      text := nullif(btrim(p_notes), '');
  v_has_team   boolean := jsonb_typeof(coalesce(p_members, '[]'::jsonb)) = 'array'
                          and jsonb_array_length(coalesce(p_members, '[]'::jsonb)) > 0;
  v_serial     text;
  v_project_id uuid;
  v_attempts   int := 0;
  v_constraint text;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  if not (public.is_admin() or public.has_feature('can_add_project')) then
    raise exception 'not authorized to create projects' using errcode = '42501';
  end if;
  -- assigning an initial team requires the assignment capability too.
  if v_has_team and not (public.is_admin() or public.has_feature('can_assign_photographers')) then
    raise exception 'not authorized to assign the initial team' using errcode = '42501';
  end if;

  -- manager resolution.
  if public.is_admin() then
    v_manager := coalesce(p_manager_id, v_uid);
  else
    if p_manager_id is not null and p_manager_id <> v_uid then
      raise exception 'a manager can only create their own projects'
        using errcode = '42501';
    end if;
    v_manager := v_uid;
  end if;
  -- owning manager profile must be active + not soft-deleted.
  perform 1 from public.profiles pr
    where pr.id = v_manager and pr.is_active and pr.deleted_at is null;
  if not found then
    raise exception 'manager profile is not available' using errcode = 'P0002';
  end if;
  -- when an admin DELEGATES to another manager, that target must hold an active
  -- management role (admin / manager / wedding_admin).
  if public.is_admin() and p_manager_id is not null and p_manager_id <> v_uid then
    perform 1 from public.user_roles ur
      join public.roles r on r.id = ur.role_id
      where ur.user_id = v_manager and r.is_active
        and r.code in ('admin', 'manager', 'wedding_admin');
    if not found then
      raise exception 'target profile is not an eligible project manager'
        using errcode = '42501';
    end if;
  end if;

  if v_name = '' or v_client = '' then
    raise exception 'name and client are required' using errcode = '22023';
  end if;
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception 'invalid project date range' using errcode = '22023';
  end if;

  -- insert with collision-safe serial retry (UNIQUE constraint is the guard).
  v_serial := public.gen_project_serial(p_type);
  loop
    begin
      insert into public.projects
        (serial, name, client_name, manager_id, type, status,
         start_date, end_date, notes)
      values
        (v_serial, v_name, v_client, v_manager, p_type,
         'active'::public.project_status, p_start_date, p_end_date, v_notes)
      returning id into v_project_id;
      exit;
    exception when unique_violation then
      -- Only a serial collision (projects_serial_key) is retried; any other
      -- unique violation is re-raised unchanged (not masked as a serial error).
      get stacked diagnostics v_constraint = constraint_name;
      if v_constraint is distinct from 'projects_serial_key' then
        raise;
      end if;
      v_attempts := v_attempts + 1;
      if v_attempts >= 10 then
        raise exception 'could not allocate a unique project serial'
          using errcode = 'P0001';
      end if;
      v_serial := public.gen_project_serial(p_type);
    end;
  end loop;

  -- default stages: social → 7-stage, field/wedding → 3-stage (exact
  -- ProjectStageTitles), deterministic stage_order, stage 1 'current' rest
  -- 'pending' (mock createProject).
  insert into public.project_stages (project_id, title, stage_order, status)
  select v_project_id, t.title, t.ord,
         case when t.ord = 1 then 'current'::public.stage_status
              else 'pending'::public.stage_status end
  from unnest(
    case p_type
      when 'social'::public.project_type then array[
        'استلام الأوردر','الاجتماع مع العميل','كتابة الخطة','رحلة الإبداع',
        'رحلة التعديل','التسليم','النشر']
      else array[
        'استلام الأوردر','في رحلة الإبداع','تم التسليم']
    end
  ) with ordinality as t(title, ord);

  insert into public.audit_logs (actor_id, action, entity, entity_id)
  values (v_uid, 'project.create', 'projects', v_project_id);

  -- optional atomic initial team (same transaction). The new project has no team
  -- yet, so availability excludes it naturally. Writes its own project.team.assign.
  if v_has_team then
    perform public._apply_project_team(v_project_id, p_members);
  end if;

  return v_project_id;
end;
$$;

revoke all on function public.create_project(text, text, public.project_type, date, date, text, uuid, jsonb) from public;
revoke all on function public.create_project(text, text, public.project_type, date, date, text, uuid, jsonb) from anon;
grant execute on function public.create_project(text, text, public.project_type, date, date, text, uuid, jsonb) to authenticated;

-- ###########################################################################
-- 5) update_project — edit BASICS only. Auth: is_admin() OR (manages_project AND
-- can_edit_project). Project TYPE is IMMUTABLE after creation (it selects the
-- 3-/7-stage template; the sources define no safe stage-rebuild and rebuilding
-- would lose stage history) — a change attempt is rejected. status / manager_id /
-- serial / team / stages / soft-delete fields are untouched (status only via the
-- Step-6.3 closure workflow). Returns the project id.
-- ###########################################################################

create or replace function public.update_project(
  p_project_id  uuid,
  p_name        text,
  p_client_name text,
  p_type        public.project_type,
  p_start_date  date,
  p_end_date    date,
  p_notes       text default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_name    text := btrim(coalesce(p_name, ''));
  v_client  text := btrim(coalesce(p_client_name, ''));
  v_notes   text := nullif(btrim(p_notes), '');
  v_active  boolean;
  v_deleted timestamptz;
  v_ptype   public.project_type;
  v_pstatus public.project_status;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  if not (
    public.is_admin()
    or (public.manages_project(p_project_id) and public.has_feature('can_edit_project'))
  ) then
    raise exception 'project not found or access denied' using errcode = '42501';
  end if;
  select p.is_active, p.deleted_at, p.type, p.status
    into v_active, v_deleted, v_ptype, v_pstatus
    from public.projects p where p.id = p_project_id for update;
  if not found or not v_active or v_deleted is not null then
    raise exception 'project not found or access denied' using errcode = '42501';
  end if;
  -- Editable only while the project is in a working state (ProjectModel.isActive
  -- = {active, in_progress}). Basics of a project under closure review
  -- (pending_closure) or finished (completed/delivered/approved) or rejected are
  -- NOT editable here — a conservative resolution of an undefined-in-sources case
  -- (mock allows any); reported for owner confirmation.
  if v_pstatus not in ('active'::public.project_status,
                       'in_progress'::public.project_status) then
    raise exception 'project is not in an editable state' using errcode = 'P0001';
  end if;
  -- type is immutable (protects the stage template / history).
  if p_type is distinct from v_ptype then
    raise exception 'project type cannot be changed after creation'
      using errcode = '22023';
  end if;
  if v_name = '' or v_client = '' then
    raise exception 'name and client are required' using errcode = '22023';
  end if;
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception 'invalid project date range' using errcode = '22023';
  end if;

  -- basics only; updated_at maintained by the Step-4 trigger.
  update public.projects
    set name = v_name, client_name = v_client,
        start_date = p_start_date, end_date = p_end_date, notes = v_notes
    where id = p_project_id;

  insert into public.audit_logs (actor_id, action, entity, entity_id)
  values (v_uid, 'project.edit', 'projects', p_project_id);

  return p_project_id;
end;
$$;

revoke all on function public.update_project(uuid, text, text, public.project_type, date, date, text) from public;
revoke all on function public.update_project(uuid, text, text, public.project_type, date, date, text) from anon;
grant execute on function public.update_project(uuid, text, text, public.project_type, date, date, text) to authenticated;

-- ###########################################################################
-- 6) update_project_stage — target 'current', earlier 'done', later 'pending'.
-- Target-only updated_by/updated_at (the mock defines target-only metadata — §11
-- exception). Auth: is_admin() OR ((manages_project OR assigned_to_project) AND
-- can_update_stages). Blocks soft-deleted/inactive and completed projects; never
-- touches project status or closure. Returns the project id.
-- ###########################################################################

create or replace function public.update_project_stage(
  p_project_id uuid,
  p_stage_id   uuid,
  p_notes      text default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_active  boolean;
  v_deleted timestamptz;
  v_pstatus public.project_status;
  v_target  int;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  if not (
    public.is_admin()
    or ((public.manages_project(p_project_id) or public.assigned_to_project(p_project_id))
        and public.has_feature('can_update_stages'))
  ) then
    raise exception 'project not found or access denied' using errcode = '42501';
  end if;
  select p.is_active, p.deleted_at, p.status
    into v_active, v_deleted, v_pstatus
    from public.projects p where p.id = p_project_id for update;
  if not found or not v_active or v_deleted is not null then
    raise exception 'project not found or access denied' using errcode = '42501';
  end if;
  -- Stages are updatable only in a working state (ProjectModel.isActive =
  -- {active, in_progress}); this blocks completed/delivered/approved AND
  -- closure-pending (pending_closure, under review — §8) and rejected.
  if v_pstatus not in ('active'::public.project_status,
                       'in_progress'::public.project_status) then
    raise exception 'cannot update stages of a project in this state'
      using errcode = 'P0001';
  end if;
  select s.stage_order into v_target
    from public.project_stages s
    where s.id = p_stage_id and s.project_id = p_project_id
    for update;
  if not found then
    raise exception 'stage not found for this project' using errcode = 'P0002';
  end if;
  perform 1 from public.project_stages s
    where s.project_id = p_project_id for update;

  update public.project_stages s
    set status = case
                   when s.stage_order <  v_target then 'done'::public.stage_status
                   when s.stage_order =  v_target then 'current'::public.stage_status
                   else 'pending'::public.stage_status
                 end,
        notes      = case when s.stage_order = v_target then nullif(btrim(p_notes), '')
                          else s.notes end,
        updated_by = case when s.stage_order = v_target then v_uid else s.updated_by end,
        updated_at = case when s.stage_order = v_target then now() else s.updated_at end
    where s.project_id = p_project_id;

  insert into public.audit_logs (actor_id, action, entity, entity_id)
  values (v_uid, 'project.stage.update', 'project_stages', p_stage_id);

  return p_project_id;
end;
$$;

revoke all on function public.update_project_stage(uuid, uuid, text) from public;
revoke all on function public.update_project_stage(uuid, uuid, text) from anon;
grant execute on function public.update_project_stage(uuid, uuid, text) to authenticated;

-- ###########################################################################
-- 7) assign_team_roles(project_id, members jsonb) — replace the whole team,
-- atomically. Name mirrors the repository contract (assignTeamRoles). Auth:
-- is_admin() OR (manages_project AND can_assign_photographers). Locks the live
-- project row (rejects soft-deleted/inactive and completed projects), then
-- delegates the validate/lock/replace/audit to the trusted internal routine.
-- Returns the project id (the repository re-reads via Step-6.2 SELECT policies;
-- teammate `value` stays hidden from assigned peers — Step 6.2 privacy model).
-- ###########################################################################

create or replace function public.assign_team_roles(
  p_project_id uuid,
  p_members    jsonb
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_active  boolean;
  v_deleted timestamptz;
  v_pstatus public.project_status;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  if not (
    public.is_admin()
    or (public.manages_project(p_project_id) and public.has_feature('can_assign_photographers'))
  ) then
    raise exception 'project not found or access denied' using errcode = '42501';
  end if;
  -- lock order step 1: the project row.
  select p.is_active, p.deleted_at, p.status
    into v_active, v_deleted, v_pstatus
    from public.projects p where p.id = p_project_id for update;
  if not found or not v_active or v_deleted is not null then
    raise exception 'project not found or access denied' using errcode = '42501';
  end if;
  -- Team changes allowed only in a working state (ProjectModel.isActive =
  -- {active, in_progress}); blocks completed/delivered/approved AND
  -- closure-pending (pending_closure) and rejected — conservative resolution of
  -- an undefined-in-sources case (mock has no gate), reported for owner review.
  if v_pstatus not in ('active'::public.project_status,
                       'in_progress'::public.project_status) then
    raise exception 'cannot change the team of a project in this state'
      using errcode = 'P0001';
  end if;

  -- lock order steps 2-4 (profiles → delete/insert) + audit happen inside.
  perform public._apply_project_team(p_project_id, p_members);
  return p_project_id;
end;
$$;

revoke all on function public.assign_team_roles(uuid, jsonb) from public;
revoke all on function public.assign_team_roles(uuid, jsonb) from anon;
grant execute on function public.assign_team_roles(uuid, jsonb) to authenticated;

-- ###########################################################################
-- 8) No table policies were added or changed. Direct INSERT/UPDATE/DELETE on
-- projects/project_team_members/project_team_types/project_stages/
-- user_unavailability/closure_requests/project_links remain DEFAULT-DENY; every
-- write flows through the narrowly-authorized SECURITY DEFINER functions above
-- (and the Step-6.3 closure RPCs, which are unchanged). No closure/tracking
-- change, no project-link CRUD, no soft-delete RPC, no Edge Functions, no Flutter.
-- ###########################################################################
