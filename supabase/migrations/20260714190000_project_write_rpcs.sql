-- =============================================================================
-- Sprint 9 · Step 6.4 — Project write RPCs (create / edit / stage update).
-- Runs AFTER Step 6.3 (depends on the hardened helpers is_active_user(),
-- is_admin(), has_feature(), manages_project(pid), assigned_to_project(pid)).
--
-- Transitions/titles mirror the current contracts EXACTLY:
--   create → project status 'active'; default stages seeded per ProjectType
--            (3-stage field/wedding, 7-stage social), stage 1 'current' rest
--            'pending' (MockProjectRepository.createProject + ProjectStageTitles).
--   edit   → basics only (MockProjectRepository.updateProjectBasics minus status).
--   stage  → set target 'current', earlier 'done', later 'pending'
--            (MockProjectRepository.updateProjectStage).
--
-- Guardrail (docs/BACKEND_SCOPE_GUARD.md): NO finance/payments/Rekaz/
-- notifications/FCM/push/reminders. `project_team_members.value` untouched here.
--
-- All direct table writes stay DEFAULT-DENY; every mutation happens only inside
-- the SECURITY DEFINER RPCs below, which re-check authorization with the hardened
-- helpers (fail closed for inactive/soft-deleted callers). No table policies are
-- added or modified.
--
-- ────────────────────────────────────────────────────────────────────────────
-- DEFERRED IN THIS STEP — with the reasons (see docs/SUPABASE_RLS_PLAN.md §10):
--
--  * is_available() + assign_project_team()  — the availability contract is BOTH
--    conflicting and under-specified, and the task forbids guessing:
--      (A) CONFLICT — booking window: the Flutter contract (team_availability.dart
--          `isBookedOn`) treats a user as booked when assigned to an ACTIVE
--          project whose DATE RANGE [start_date,end_date] covers the date; the
--          frozen `is_available` (RLS_PLAN §1) checks a single
--          `project_team_members.date = on_date`.
--      (B) CONFLICT — conflict statuses: Flutter uses ProjectModel.isActive
--          = {active,in_progress}; the frozen plan uses
--          {active,in_progress,pending_closure}.
--      (C) UNRESOLVED — timezone/day boundary: `user_unavailability` is
--          `timestamptz` (Step 3) while Flutter `MockLeave` is date-only; no doc
--          defines how a timestamptz range maps to `on_date` (UTC? Asia/Riyadh?).
--    Because assign_project_team MUST re-check availability (incl. leave) and the
--    initial team on create depends on the same rule, BOTH are deferred pending an
--    owner decision. No is_available()/overlap/Marketing-exemption logic here.
--
--  * update_project does NOT change `status`: the mock admin edit exposes a
--    status override over {active,completed,pending_closure}, but every such edit
--    is a closure-workflow transition; §4 forbids bypassing Step 6.3, so status
--    is intentionally omitted (closure state changes only via the Step 6.3 RPCs).
--
--  * Manager reassignment (setProjectManager) — deferred (owner-reassignment is a
--    distinct admin flow; §4 cautions against arbitrary reassignment).
--
--  * Project soft-delete RPC — the ProjectRepository has NO delete method, so per
--    §8 it is deferred (not invented). No project.deactivate action is emitted.
-- ────────────────────────────────────────────────────────────────────────────
-- =============================================================================

-- ###########################################################################
-- 1) gen_project_serial(type) — server-side serial candidate. Uses the
-- CRYPTOGRAPHICALLY-SECURE gen_random_uuid() (v4) hex — never `random()` — so it
-- is unpredictable; uniqueness is guaranteed by the Step-4 UNIQUE constraint plus
-- the retry loop in create_project. Shape matches the Step-4 CHECK exactly:
--   ^(FLD|SOC|WED)-[A-Z0-9]{4}-[A-Z0-9]{2}$  (hex 0-9A-F ⊂ [A-Z0-9]).
-- Helper only — execute revoked from PUBLIC+anon and NOT granted to authenticated;
-- only the SECURITY DEFINER create_project (same owner) calls it.
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
-- 2) create_project — atomically create a project, seed its default stages, and
-- audit. Authorization (frozen §5 generalized to the D5 permission model so it
-- does not block non-'manager' holders of can_add_project such as wedding_admin):
--   is_admin() OR has_feature('can_add_project').
-- manager_id: an admin may set another (active, non-deleted) manager; a non-admin
-- may only create for themselves (manager_id = auth.uid()), matching the frozen
-- matrix "M: manager_id=uid". No wedding-specific gate (not required by frozen).
-- Returns the new project id (the future repository re-reads via the Step-6.2
-- projects SELECT policy — owner/admin can read the row they just created).
-- Field mapping: name←name, client_name←clientName, type←type, start_date←
-- startDate, end_date←endDate, notes←notes, manager_id←managerId.
-- ###########################################################################

create or replace function public.create_project(
  p_name        text,
  p_client_name text,
  p_type        public.project_type,
  p_start_date  date,
  p_end_date    date,
  p_notes       text default null,
  p_manager_id  uuid default null
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
  v_serial     text;
  v_project_id uuid;
  v_attempts   int  := 0;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  -- permission (fails closed for inactive/soft-deleted callers via has_feature).
  if not (public.is_admin() or public.has_feature('can_add_project')) then
    raise exception 'not authorized to create projects' using errcode = '42501';
  end if;
  -- manager resolution: admin may delegate, non-admin creates for self only.
  if public.is_admin() then
    v_manager := coalesce(p_manager_id, v_uid);
  else
    if p_manager_id is not null and p_manager_id <> v_uid then
      raise exception 'a manager can only create their own projects'
        using errcode = '42501';
    end if;
    v_manager := v_uid;
  end if;
  -- the owning manager profile must be active and not soft-deleted.
  perform 1 from public.profiles pr
    where pr.id = v_manager and pr.is_active and pr.deleted_at is null;
  if not found then
    raise exception 'manager profile is not available' using errcode = 'P0002';
  end if;
  -- field validation (belt-and-suspenders over the Step-4 CHECKs).
  if v_name = '' or v_client = '' then
    raise exception 'name and client are required' using errcode = '22023';
  end if;
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception 'invalid project date range' using errcode = '22023';
  end if;

  -- insert with a collision-safe serial retry (UNIQUE constraint is the guard).
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
      v_attempts := v_attempts + 1;
      if v_attempts >= 10 then
        raise exception 'could not allocate a unique project serial'
          using errcode = 'P0001';
      end if;
      v_serial := public.gen_project_serial(p_type);
    end;
  end loop;

  -- seed default stages: social → 7-stage, field/wedding → 3-stage (exact
  -- ProjectStageTitles). Deterministic stage_order via WITH ORDINALITY; stage 1
  -- 'current', the rest 'pending' (mock createProject).
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

  -- audit: identifiers only (no client name / notes / values / URLs / secrets).
  insert into public.audit_logs (actor_id, action, entity, entity_id)
  values (v_uid, 'project.create', 'projects', v_project_id);

  return v_project_id;
end;
$$;

revoke all on function public.create_project(text, text, public.project_type, date, date, text, uuid) from public;
revoke all on function public.create_project(text, text, public.project_type, date, date, text, uuid) from anon;
grant execute on function public.create_project(text, text, public.project_type, date, date, text, uuid) to authenticated;

-- ###########################################################################
-- 3) update_project — edit BASICS only (name, client_name, type, start_date,
-- end_date, notes). Does NOT touch status / manager_id / serial / team / stages
-- (status edits would bypass the Step-6.3 closure workflow — see header). Auth:
--   is_admin() OR (manages_project(id) AND has_feature('can_edit_project')).
-- Consistent not-found/unauthorized error avoids project-existence probing.
-- Returns the project id (repository re-reads).
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
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  -- authorization (helpers fail closed; consistent error hides existence).
  if not (
    public.is_admin()
    or (public.manages_project(p_project_id) and public.has_feature('can_edit_project'))
  ) then
    raise exception 'project not found or access denied' using errcode = '42501';
  end if;
  -- lock + require the project live (rejects soft-deleted/inactive, admin too).
  select p.is_active, p.deleted_at into v_active, v_deleted
    from public.projects p where p.id = p_project_id for update;
  if not found or not v_active or v_deleted is not null then
    raise exception 'project not found or access denied' using errcode = '42501';
  end if;
  if v_name = '' or v_client = '' then
    raise exception 'name and client are required' using errcode = '22023';
  end if;
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception 'invalid project date range' using errcode = '22023';
  end if;

  -- basics only; updated_at is maintained by the Step-4 trigger. Soft-delete
  -- fields, status, manager_id, and serial are deliberately left untouched.
  update public.projects
    set name = v_name, client_name = v_client, type = p_type,
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
-- 4) update_project_stage — set the target stage 'current', earlier stages
-- 'done', later stages 'pending' (mock updateProjectStage). updated_by/updated_at
-- recorded on the TARGET stage only. Auth (frozen §5):
--   is_admin() OR ((manages_project OR assigned_to_project) AND can_update_stages).
-- Project must be live AND not completed (§7: do not alter completed projects —
-- ProjectModel.isCompleted = {completed,delivered,approved}). Does NOT submit or
-- approve closure and never touches project status. Returns the project id.
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
  -- authorization (consistent error hides existence).
  if not (
    public.is_admin()
    or ((public.manages_project(p_project_id) or public.assigned_to_project(p_project_id))
        and public.has_feature('can_update_stages'))
  ) then
    raise exception 'project not found or access denied' using errcode = '42501';
  end if;
  -- lock the project; it must be live and not a completed state.
  select p.is_active, p.deleted_at, p.status
    into v_active, v_deleted, v_pstatus
    from public.projects p where p.id = p_project_id for update;
  if not found or not v_active or v_deleted is not null then
    raise exception 'project not found or access denied' using errcode = '42501';
  end if;
  if v_pstatus in ('completed'::public.project_status,
                   'delivered'::public.project_status,
                   'approved'::public.project_status) then
    raise exception 'cannot update stages of a completed project'
      using errcode = 'P0001';
  end if;
  -- lock the target stage and read its order (must belong to this project).
  select s.stage_order into v_target
    from public.project_stages s
    where s.id = p_stage_id and s.project_id = p_project_id
    for update;
  if not found then
    raise exception 'stage not found for this project' using errcode = 'P0002';
  end if;
  -- lock the remaining stages of the project for a consistent rewrite.
  perform 1 from public.project_stages s
    where s.project_id = p_project_id for update;

  -- mock transition: earlier → done, target → current (+ notes/updated_by/at),
  -- later → pending. Guarantees exactly one 'current' stage.
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
-- 5) No table policies were added or changed. Direct INSERT/UPDATE/DELETE on
-- projects/project_team_members/project_team_types/project_stages/
-- user_unavailability/closure_requests/project_links remain DEFAULT-DENY; every
-- write flows through the narrowly-authorized SECURITY DEFINER RPCs above (and
-- the Step-6.3 closure RPCs). No is_available()/assignment/Marketing-exemption,
-- no closure/tracking changes, no project-link CRUD, no soft-delete RPC, no Edge
-- Functions, no Flutter — see the DEFERRED header and docs/SUPABASE_RLS_PLAN.md §10.
-- ###########################################################################
