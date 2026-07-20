-- =============================================================================
-- Sprint 9 · Step 6.2 — Project-domain read helpers & RLS
-- Scope: project-domain authorization helpers + READ (SELECT) policies for
--   projects, project_team_members, project_team_types, project_stages,
--   user_unavailability.
-- Runs AFTER Step 6.1 (depends on public.is_active_user() / public.is_admin()).
--
-- Frozen alignment (docs/SUPABASE_RLS_PLAN.md §1–§3): RLS default-deny; project
-- access keyed on manager ownership (D1) + team assignment (D3), with
-- soft-delete filtering (D6). Public/anon access is NOT granted here — client
-- tracking is a restricted SECURITY DEFINER RPC in a later step.
--
-- Guardrail (docs/BACKEND_SCOPE_GUARD.md): NO finance/payments/Rekaz/
-- notifications/FCM/push/reminders. `project_team_members.value` is assignment
-- metadata only (never finance); see the value-exposure note in §3 below.
--
-- Scope guard for THIS step (6.2 ONLY):
--   * READ policies only. NO INSERT/UPDATE/DELETE (incl. soft-delete) policies →
--     all writes stay default-deny; project/team/stage writes go through the
--     transactional RPCs in a later step (RLS plan §5), NOT here.
--   * NO is_available(), NO assignment/overlap validation, NO Marketing
--     double-booking exemption, NO booking/assignment RPCs (later RPC step).
--   * NO closure_requests / project_links policies or RPCs (Step 6.3+).
--   * NO client-tracking policy/RPC, NO anon access, NO Edge Functions,
--     NO Flutter/package changes, NO Auth Integration.
--   * Step 6.1 identity helpers are NOT modified.
--
-- RLS is already ENABLED on all five tables (Steps 3/4); this migration only
-- adds helpers + SELECT policies. Anon gets NO policy → anon stays fully denied.
-- =============================================================================

-- ###########################################################################
-- 1) PROJECT-DOMAIN AUTHORIZATION HELPERS
-- SQL, STABLE, schema-qualified, fixed empty search_path, SECURITY DEFINER so
-- that — called inside a policy — they BYPASS RLS on projects/project_team_members
-- and cannot cause recursive RLS evaluation. Both FAIL CLOSED via is_active_user()
-- (Step 6.1), so a disabled/soft-deleted caller always gets false, even if a
-- future RPC calls them directly. Default PUBLIC execute is revoked, anon is
-- revoked explicitly, and execute is granted to `authenticated` only.
--
-- Parameter name `pid` matches the frozen canonical signature in
-- docs/SUPABASE_RLS_PLAN.md §1 (manages_project(pid)/assigned_to_project(pid)).
-- It deliberately differs from the `project_id` COLUMN name to avoid a
-- parameter/column collision that would silently break the WHERE clause.
-- ###########################################################################

-- manages_project(pid): caller is the owning manager of an active, non-deleted
-- project. Returns no row data — a boolean only.
create or replace function public.manages_project(pid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_active_user() and exists (
    select 1 from public.projects p
    where p.id = pid
      and p.manager_id = auth.uid()
      and p.is_active
      and p.deleted_at is null
  )
$$;

-- assigned_to_project(pid): caller is a team member (project_team_members.user_id
-- = auth.uid()) on an active, non-deleted project. Boolean only.
create or replace function public.assigned_to_project(pid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_active_user() and exists (
    select 1
    from public.project_team_members t
    join public.projects p on p.id = t.project_id
    where t.project_id = pid
      and t.user_id = auth.uid()
      and p.is_active
      and p.deleted_at is null
  )
$$;

-- Lock down execution: revoke implicit PUBLIC grant (covers anon), revoke anon
-- explicitly, grant execute to authenticated only. Ownership stays with the
-- migration role, so authenticated cannot replace/alter/drop these functions.
revoke all on function public.manages_project(uuid)     from public;
revoke all on function public.assigned_to_project(uuid)  from public;
revoke all on function public.manages_project(uuid)     from anon;
revoke all on function public.assigned_to_project(uuid)  from anon;
grant execute on function public.manages_project(uuid)     to authenticated;
grant execute on function public.assigned_to_project(uuid)  to authenticated;

-- ###########################################################################
-- 2) PROJECTS — SELECT only. A project is visible to: its owning manager, any
-- assigned staff (photographer/marketing/etc.), or an admin — and ONLY while
-- active + not soft-deleted. No anon, no serial lookup, no client tracking here.
-- No write policy (default-deny): project writes go through RPCs later.
-- ###########################################################################

create policy projects_select_visible
  on public.projects for select to authenticated
  using (
    -- owning manager (helper: active caller + live project + manager_id = uid)
    public.manages_project(id)
    -- assigned staff incl. Marketing (helper: active caller + live + assigned)
    or public.assigned_to_project(id)
    -- admin oversight, live rows only
    or (public.is_admin() and is_active and deleted_at is null)
  );

-- ###########################################################################
-- 3) PROJECT_TEAM_MEMBERS — SELECT only, DELEGATED to project visibility:
-- "you can see a team row iff you can see its parent project." This yields the
-- frozen matrix exactly (admin: live projects; owning manager: their projects;
-- assigned staff: their projects, i.e. own + teammates) and inherently excludes
-- soft-deleted/inactive projects (they are invisible via §2).
--
-- ASSIGNMENT-VALUE EXPOSURE NOTE (reported, not silently changed): because RLS is
-- row-level, an assigned staff member who can see the project sees ALL teammate
-- rows, INCLUDING `value`. This matches BOTH the frozen matrix (P/MK read
-- own/teammates) AND the current Flutter UI (project_details_screen renders every
-- teammate's `value` as «… ر.س», ungated by role), so it is the approved
-- visibility — not an over-exposure beyond the frozen plan. `value` is assignment
-- metadata, never finance. If the owner later wants `value` restricted to
-- manager/admin only, that requires a column-masking read VIEW or RPC — which is
-- deliberately NOT created in this step (per the Step 6.2 instruction).
-- No write policy (default-deny): team assignment goes through the assign RPC.
-- ###########################################################################

create policy project_team_members_select_via_project
  on public.project_team_members for select to authenticated
  using (
    public.is_active_user()
    and exists (
      select 1 from public.projects pr
      where pr.id = project_team_members.project_id
    )
  );

-- ###########################################################################
-- 4) PROJECT_TEAM_TYPES — SELECT only, DELEGATED to team-member visibility:
-- "you can see a type iff you can see its team member" (which in turn delegates
-- to project visibility). Safe project_team_members → projects traversal, no
-- recursion (see §8). No write policy (default-deny).
-- ###########################################################################

create policy project_team_types_select_via_member
  on public.project_team_types for select to authenticated
  using (
    public.is_active_user()
    and exists (
      select 1 from public.project_team_members m
      where m.id = project_team_types.team_member_id
    )
  );

-- ###########################################################################
-- 5) PROJECT_STAGES — SELECT only, DELEGATED to project visibility. Admin/owning
-- manager/assigned staff read stages of projects they can see; retained stage
-- history stays scoped by the active parent project. NO stage-update policy, NO
-- advance-stage RPC, NO automatic status changes, NO notifications/reminders.
-- ###########################################################################

create policy project_stages_select_via_project
  on public.project_stages for select to authenticated
  using (
    public.is_active_user()
    and exists (
      select 1 from public.projects pr
      where pr.id = project_stages.project_id
    )
  );

-- ###########################################################################
-- 6) USER_UNAVAILABILITY — SELECT only. Leave/permission details are private.
--   * A user reads their OWN records, including retained inactive/cancelled
--     history (no is_active filter on the self policy).
--   * Admin reads ALL records (oversight).
--   * Managers get NO direct table access here — notes/reasons/full leave
--     records are NOT exposed to managers. Manager availability checks will use
--     a restricted boolean availability function/RPC in the later assignment/RPC
--     step, NOT broad table reads.
-- No write policy (default-deny): no availability write/cancel policy or RPC in
-- this step. No notifications/reminders/approval/attendance behavior.
-- ###########################################################################

create policy user_unavailability_select_self
  on public.user_unavailability for select to authenticated
  using (public.is_active_user() and user_id = (select auth.uid()));

create policy user_unavailability_select_admin
  on public.user_unavailability for select to authenticated
  using (public.is_active_user() and public.is_admin());

-- ###########################################################################
-- 7) MARKETING — deferred availability rule (documentation only; NO logic here).
-- Marketing is a first-class role resolved via user_roles → roles.code =
-- 'marketing' (never mapped to `designer`). An ASSIGNED marketing user receives
-- the SAME approved project read visibility as any other assigned staff through
-- assigned_to_project() above (role-agnostic assignment check). The Marketing
-- DOUBLE-BOOKING EXEMPTION is NOT implemented here: future availability
-- enforcement (the assignment RPC / is_available()) must exempt Marketing ONLY
-- from project double-booking overlaps — NOT automatically from explicit
-- leave/unavailability — unless the frozen business rule states otherwise.
-- ###########################################################################

-- ###########################################################################
-- 8) No anon policies anywhere → anon has zero project-domain access. No write
-- policies were created → all INSERT/UPDATE/DELETE stay default-deny for
-- authenticated and anon. Recursion safety: the two helpers are SECURITY DEFINER
-- (bypass RLS), so projects policy → helpers never re-enters projects RLS; the
-- delegated child policies read projects/project_team_members UNDER RLS but those
-- parents' policies use only the definer helpers (which bypass RLS) and plain
-- columns, so the dependency graph
--   team_types → team_members → projects → (definer helpers, no RLS)
-- is acyclic and terminates.
-- ###########################################################################
