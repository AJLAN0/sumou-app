-- =============================================================================
-- Sprint 9 · Step 6.3 — Closure & delivery-link RLS + closure workflow RPCs +
--                       restricted public client-tracking RPC.
-- Runs AFTER Step 6.2 (depends on the hardened helpers is_active_user(),
-- is_admin(), has_feature(), manages_project(pid), assigned_to_project(pid)).
--
-- Frozen alignment (docs/SUPABASE_RLS_PLAN.md §3–§5, §4 public RPC; SCHEMA_DRAFT
-- §4.5/§4.6). Transitions mirror the current mock (MockProjectRepository) EXACTLY:
--   submit  → project status 'pending_closure'
--   approve → request 'approved', reviewed_at=now; project 'completed'; all
--             stages 'done'
--   reject  → request 'rejected', reject_reason=reason, reviewed_at=now; project
--             back to 'active'
--
-- Guardrail (docs/BACKEND_SCOPE_GUARD.md): NO finance/payments/Rekaz/
-- notifications/FCM/push/reminders. No Storage/uploads. `report_file_url`/
-- `delivery_link` are plain text URLs on closure_requests (Step 5).
--
-- Scope guard for THIS step (6.3 ONLY):
--   * closure_requests + project_links: SELECT policies only (no writes).
--   * Closure submit/approve/reject RPCs + ONE anonymous tracking RPC.
--   * NO project create/edit RPC, NO team-assignment RPC, NO stage-advance RPC,
--     NO is_available()/booking-overlap, NO Marketing exemption, NO project-link
--     CRUD RPC (no implemented Flutter contract → deferred), NO client reviews/
--     ratings, NO Edge Functions, NO Flutter/package changes, NO Auth Integration.
--   * NO new policies on projects/team/stages/unavailability/identity (Steps
--     6.1/6.2). NO new closure status (pending/approved/rejected only).
--
-- All direct table writes stay DEFAULT-DENY; every mutation happens only inside
-- the SECURITY DEFINER RPCs below, which re-check authorization with the hardened
-- helpers (fail closed for inactive/soft-deleted callers).
-- =============================================================================

-- ###########################################################################
-- 1) closure_requests — SELECT policies only (RLS already enabled, Step 5).
-- Frozen matrix §3: admin (live projects) · owning manager (their projects) ·
-- submitter (their own submissions, parent project live). No "all assigned"
-- visibility. No write policy → retained history is immutable via table access.
-- reject_reason/reviewed_at are legitimate closure columns (shown in the app);
-- reviewer IDENTITY is NOT a column here — it lives only in audit_logs.
-- ###########################################################################

create policy closure_requests_select_scoped
  on public.closure_requests for select to authenticated
  using (
    public.is_active_user()
    and (
      -- owning manager of the parent project (helper: active caller + live project)
      public.manages_project(project_id)
      -- submitter reads their own request, while the parent project is live
      or (
        submitted_by = (select auth.uid())
        and exists (
          select 1 from public.projects pr
          where pr.id = closure_requests.project_id
            and pr.is_active and pr.deleted_at is null
        )
      )
      -- admin oversight: closure requests of live projects
      or (
        public.is_admin()
        and exists (
          select 1 from public.projects pr
          where pr.id = closure_requests.project_id
            and pr.is_active and pr.deleted_at is null
        )
      )
    )
  );

-- ###########################################################################
-- 2) project_links — authenticated SELECT policies only (RLS enabled, Step 5).
-- Admin (live projects) + owning manager (ALL links of their projects, incl.
-- unapproved/hidden/retained, for management). NO assigned-staff policy: no
-- current Flutter contract reads project_links directly (the delivery URL a
-- photographer submits is stored on closure_requests, not here), so the frozen
-- matrix's P/MK "assigned project" link read is DEFERRED (reported) rather than
-- granting broad access to internal/unapproved links. NO anon policy — public
-- access is ONLY via track_project_by_serial (§7). No write policy.
-- ###########################################################################

create policy project_links_select_manage
  on public.project_links for select to authenticated
  using (
    public.is_active_user()
    and (
      public.manages_project(project_id)
      or (
        public.is_admin()
        and exists (
          select 1 from public.projects pr
          where pr.id = project_links.project_id
            and pr.is_active and pr.deleted_at is null
        )
      )
    )
  );

-- ###########################################################################
-- 3) submit_closure_request — photographer submits a closure/delivery request.
-- SECURITY DEFINER (writes to default-deny tables); re-checks authorization.
-- Guard (frozen §5): has_feature('can_request_closure') AND assigned_to_project.
-- Inputs mirror the repository contract (submitter is auth.uid(), never a client
-- input; submitted_by_name is derived, not stored). Returns the new request id.
-- ###########################################################################

create or replace function public.submit_closure_request(
  p_project_id      uuid,
  p_delivery_link   text default null,
  p_report_file_url text default null,
  p_notes           text default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := auth.uid();
  v_link   text := nullif(btrim(p_delivery_link), '');
  v_report text := nullif(btrim(p_report_file_url), '');
  v_notes  text := nullif(btrim(p_notes), '');
  v_req_id uuid;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  -- fail closed for inactive/soft-deleted callers + permission + assignment
  if not public.has_feature('can_request_closure')
     or not public.assigned_to_project(p_project_id) then
    raise exception 'not authorized to submit a closure request for this project'
      using errcode = '42501';
  end if;
  -- delivery_link, when provided, must be an http(s) URL (matches the Flutter
  -- submit-closure validator). report_file_url/notes are plain text (schema has
  -- no CHECK — Step 5), so they are stored as-is.
  if v_link is not null and v_link !~* '^https?://' then
    raise exception 'delivery link must be an http(s) URL' using errcode = '22023';
  end if;
  -- lock the parent project row; it must be live. Serializes concurrent submits
  -- on the same project so the one-pending rule holds without a race.
  perform 1 from public.projects p
    where p.id = p_project_id and p.is_active and p.deleted_at is null
    for update;
  if not found then
    raise exception 'project is not available for closure' using errcode = 'P0002';
  end if;
  -- one pending request per project (explicit check; the partial unique index
  -- closure_requests_one_pending_per_project_uidx is the hard guarantee).
  if exists (
    select 1 from public.closure_requests c
    where c.project_id = p_project_id and c.status = 'pending'::public.closure_status
  ) then
    raise exception 'a pending closure request already exists for this project'
      using errcode = 'P0001';
  end if;

  insert into public.closure_requests
    (project_id, submitted_by, status, delivery_link, report_file_url, notes)
  values
    (p_project_id, v_uid, 'pending'::public.closure_status, v_link, v_report, v_notes)
  returning id into v_req_id;

  -- frozen/mock transition: project → pending_closure.
  update public.projects
    set status = 'pending_closure'::public.project_status, updated_at = now()
    where id = p_project_id;

  -- audit: reviewer/actor accountability only (no URLs/notes/secrets in meta).
  insert into public.audit_logs (actor_id, action, entity, entity_id)
  values (v_uid, 'closure.submit', 'closure_requests', v_req_id);

  return v_req_id;
exception
  when unique_violation then
    -- lost the race to the partial unique index → same clean error.
    raise exception 'a pending closure request already exists for this project'
      using errcode = 'P0001';
end;
$$;

-- ###########################################################################
-- 4) approve_closure_request — admin or owning manager (can_approve_closure)
-- approves a PENDING request. Locks the request then the project row. Idempotent
-- against double-processing (a second caller sees the committed non-pending
-- status after the FOR UPDATE lock). Returns the request id.
-- ###########################################################################

create or replace function public.approve_closure_request(p_request_id uuid)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_project uuid;
  v_status  public.closure_status;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  -- lock the request row first (serializes concurrent reviewers).
  select project_id, status into v_project, v_status
    from public.closure_requests
    where id = p_request_id
    for update;
  if not found then
    raise exception 'closure request not found' using errcode = 'P0002';
  end if;
  -- reviewer authorization: active admin OR owning manager w/ can_approve_closure.
  if not (
    public.is_admin()
    or (public.manages_project(v_project) and public.has_feature('can_approve_closure'))
  ) then
    raise exception 'not authorized to review this closure request'
      using errcode = '42501';
  end if;
  -- only a pending request may be approved (rejects repeat approve/reject).
  if v_status <> 'pending'::public.closure_status then
    raise exception 'closure request is not pending' using errcode = 'P0001';
  end if;
  perform 1 from public.projects where id = v_project for update;

  -- frozen/mock transition: request approved; project completed; all stages done.
  update public.closure_requests
    set status = 'approved'::public.closure_status, reviewed_at = now()
    where id = p_request_id;
  update public.projects
    set status = 'completed'::public.project_status, updated_at = now()
    where id = v_project;
  update public.project_stages
    set status = 'done'::public.stage_status, updated_at = now()
    where project_id = v_project;

  -- audit: reviewer identity retained here (no reviewed_by column by design).
  insert into public.audit_logs (actor_id, action, entity, entity_id)
  values (v_uid, 'closure.approve', 'closure_requests', p_request_id);

  return p_request_id;
end;
$$;

-- ###########################################################################
-- 5) reject_closure_request — same authorization as approve. Requires a non-blank
-- reason (stored in reject_reason). Frozen/mock transition: request rejected;
-- project back to ACTIVE. Returns the request id.
-- ###########################################################################

create or replace function public.reject_closure_request(
  p_request_id uuid,
  p_reason     text
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_project uuid;
  v_status  public.closure_status;
  v_reason  text := btrim(coalesce(p_reason, ''));
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  if v_reason = '' then
    raise exception 'a rejection reason is required' using errcode = '22023';
  end if;
  select project_id, status into v_project, v_status
    from public.closure_requests
    where id = p_request_id
    for update;
  if not found then
    raise exception 'closure request not found' using errcode = 'P0002';
  end if;
  if not (
    public.is_admin()
    or (public.manages_project(v_project) and public.has_feature('can_approve_closure'))
  ) then
    raise exception 'not authorized to review this closure request'
      using errcode = '42501';
  end if;
  if v_status <> 'pending'::public.closure_status then
    raise exception 'closure request is not pending' using errcode = 'P0001';
  end if;
  perform 1 from public.projects where id = v_project for update;

  update public.closure_requests
    set status = 'rejected'::public.closure_status,
        reject_reason = v_reason,
        reviewed_at = now()
    where id = p_request_id;
  -- frozen/mock transition: closure declined → project back to active.
  update public.projects
    set status = 'active'::public.project_status, updated_at = now()
    where id = v_project;

  -- audit: action + identifiers only. The full reason is NOT copied into meta.
  insert into public.audit_logs (actor_id, action, entity, entity_id)
  values (v_uid, 'closure.reject', 'closure_requests', p_request_id);

  return p_request_id;
end;
$$;

-- ###########################################################################
-- 6) Lock down workflow RPC execution: authenticated only (never anon/PUBLIC).
-- Ownership stays with the migration role, so authenticated cannot alter/drop.
-- ###########################################################################

revoke all on function public.submit_closure_request(uuid, text, text, text)  from public;
revoke all on function public.approve_closure_request(uuid)                    from public;
revoke all on function public.reject_closure_request(uuid, text)               from public;
revoke all on function public.submit_closure_request(uuid, text, text, text)  from anon;
revoke all on function public.approve_closure_request(uuid)                    from anon;
revoke all on function public.reject_closure_request(uuid, text)               from anon;
grant execute on function public.submit_closure_request(uuid, text, text, text) to authenticated;
grant execute on function public.approve_closure_request(uuid)                  to authenticated;
grant execute on function public.reject_closure_request(uuid, text)             to authenticated;

-- ###########################################################################
-- 7) track_project_by_serial — the ONLY anonymous client-tracking entry point.
-- SECURITY DEFINER + STABLE + fixed empty search_path; reads projects/project_links
-- directly (anon has NO table policy). Returns a neutral NULL for invalid /
-- unknown / soft-deleted / inactive projects — indistinguishable, so existence
-- of a hidden project never leaks. Exposes ONLY the client-safe fields that map
-- to ClientTrackingModel: serial, project_name, client_name, a coarse public
-- status, and approved+client-visible links. NO uuid/manager/team/value/notes/
-- reject/reviewer/audit/roles/permissions/unavailability. No dynamic SQL.
-- Serial is normalized (trim + upper) exactly like the Flutter tracking flow and
-- validated against the canonical FLD/SOC/WED format before any lookup.
--
-- Links satisfy the COMPLETE eligibility predicate:
--   is_approved AND is_client_visible AND is_active AND deleted_at IS NULL,
-- ordered deterministically by created_at, id.
--
-- NOTE (reported): the current Flutter tracking `status` vocabulary is 'active'/
-- 'done' (ungated to a projects mapping in the mock). To avoid leaking internal
-- workflow states (pending_closure/rejected/approved) the mapping here collapses
-- completed/delivered/approved → 'done', everything else → 'active'. Confirm/adjust
-- at Flutter integration time. Stages, rating, and message are NOT returned
-- (ClientTrackingModel has no stages; reviews/ratings are deferred).
-- ###########################################################################

create or replace function public.track_project_by_serial(project_serial text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with norm as (select upper(btrim(project_serial)) as s)
  select case
    when (select s from norm) !~ '^(FLD|SOC|WED)-[A-Z0-9]{4}-[A-Z0-9]{2}$'
      then null::jsonb
    else (
      select jsonb_build_object(
        'serial',       p.serial,
        'project_name', p.name,
        'client_name',  p.client_name,
        'status',       case
                          when p.status::text in ('completed', 'delivered', 'approved')
                            then 'done' else 'active'
                        end,
        'links', coalesce((
          select jsonb_agg(
                   jsonb_build_object('label', l.label, 'url', l.url)
                   order by l.created_at, l.id)
          from public.project_links l
          where l.project_id = p.id
            and l.is_approved
            and l.is_client_visible
            and l.is_active
            and l.deleted_at is null
        ), '[]'::jsonb)
      )
      from public.projects p
      where p.serial = (select s from norm)
        and p.is_active
        and p.deleted_at is null
    )
  end
$$;

-- Public entry point: execute to anon + authenticated ONLY; anon still has NO
-- direct table access (RLS default-deny), so this RPC is anon's only path in.
revoke all on function public.track_project_by_serial(text) from public;
grant execute on function public.track_project_by_serial(text) to anon;
grant execute on function public.track_project_by_serial(text) to authenticated;

-- ###########################################################################
-- 8) After this migration: closure_requests + project_links have SELECT policies
-- only (no INSERT/UPDATE/DELETE, no anon). All closure mutations flow through the
-- three SECURITY DEFINER workflow RPCs; the public tracking RPC is the sole anon
-- entry point and grants anon NO table access. No project-link CRUD RPC was
-- created (deferred — no Flutter contract). No is_available()/overlap/Marketing
-- exemption, no client reviews/ratings, no Edge Functions, no Flutter changes.
-- ###########################################################################
