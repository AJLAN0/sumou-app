-- =============================================================================
-- Sprint 9 · Step 6.1 — Security helper functions & identity/access RLS
-- Scope: the shared RLS helper functions + the identity/access READ policies
-- needed for safe authenticated access (login, navigation, permission
-- resolution). Runs AFTER Steps 2–5.
--
-- Frozen alignment (docs/SUPABASE_RLS_PLAN.md §1–§3): RLS default-deny; access
-- keyed on the caller's active profile + active roles (D1) + normalized,
-- override-then-role-default permissions (D5); soft-delete filtering (D6).
--
-- Guardrail (docs/BACKEND_SCOPE_GUARD.md): NO finance/payments/Rekaz/
-- notifications/FCM/push/reminders. Inactive legacy codes (finance /
-- wedding_finance roles, can_manage_finance permission) stay INACTIVE, are never
-- assignable/grantable through any policy here, and grant zero access:
--   * has_feature() ignores inactive permissions (can_manage_finance → false).
--   * has_role() ignores inactive roles (finance/wedding_finance → never match).
--   * catalog reads expose inactive rows to ADMIN oversight only, read-only,
--     with NO write policy → they can never become assignable here.
--
-- Scope guard for THIS step (6.1 ONLY):
--   * NO write policies (insert/update/delete) on any table → those stay
--     default-deny. Admin/self writes are routed through admin-gated RPCs / the
--     admin_create_user Edge Function in later steps (RLS plan §5); NOT here.
--   * NO project / team / stages / closure / links / user_unavailability
--     policies (Step 6.2 / later).
--   * NO RPCs, NO Edge Functions, NO anon access, NO Flutter/package changes.
--   * NO Auth Integration (Sprint 10).
--
-- RLS is already ENABLED on every table (Steps 2/3); this migration only adds
-- helpers + SELECT policies. Anon gets NO policy on any table → anon stays fully
-- denied. service_role/migrations bypass RLS.
-- =============================================================================

-- ###########################################################################
-- 1) SECURITY HELPER FUNCTIONS
-- All are SQL, STABLE, schema-qualified, with a fixed empty search_path. The
-- table-reading helpers are SECURITY DEFINER so that, when called inside a
-- policy, they BYPASS RLS on the tables they read — this is what prevents
-- recursive RLS evaluation (a policy on profiles/user_roles never re-enters
-- those tables' policies through a helper). Default EXECUTE (granted to PUBLIC)
-- is revoked; only `authenticated` may execute. anon is never granted execute.
-- ###########################################################################

-- current_profile_id(): the caller's profile id = auth.uid(). Reads no table,
-- so it is SECURITY INVOKER (no RLS interaction, no recursion risk).
create or replace function public.current_profile_id()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select auth.uid()
$$;

-- is_active_user(): caller has a profile that is active and not soft-deleted.
-- SECURITY DEFINER → reads public.profiles without triggering its RLS.
create or replace function public.is_active_user()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.is_active
      and p.deleted_at is null
  )
$$;

-- has_role(role_code): caller is an ACTIVE user who holds the given ACTIVE role.
-- Fails closed for inactive/soft-deleted profiles via the internal
-- is_active_user() gate, so it is safe when called DIRECTLY by a future RPC
-- (independent of any policy-level check). Inactive roles (finance/
-- wedding_finance) never match. SECURITY DEFINER.
create or replace function public.has_role(role_code text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_active_user() and exists (
    select 1
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = auth.uid()
      and r.code = role_code
      and r.is_active
  )
$$;

-- is_admin(): caller is an active user holding the active `admin` role. Inherits
-- the has_role() fail-closed gate → a disabled or soft-deleted admin gets false,
-- including when called directly by an RPC.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.has_role('admin')
$$;

-- has_feature(perm_code): effective permission (D5). Fails closed for inactive/
-- soft-deleted profiles via the internal is_active_user() gate, so it is safe
-- when called DIRECTLY by a future RPC.
--   * requires an ACTIVE caller, then
--   * user_permissions explicit override wins (grant OR revoke), else
--   * OR of role_permissions defaults across the caller's ACTIVE roles, else
--   * false.
-- Only ACTIVE permissions participate (inactive perm → CTE empty → false), and
-- only ACTIVE roles contribute defaults. So can_manage_finance (inactive) always
-- resolves to false. This does NOT copy role defaults into user_permissions.
create or replace function public.has_feature(perm_code text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with p as (
    select id from public.permissions
    where code = perm_code and is_active
  )
  select public.is_active_user() and coalesce(
    -- explicit user override (only for an active permission)
    (select up.granted
       from public.user_permissions up
       join p on p.id = up.permission_id
      where up.user_id = auth.uid()),
    -- else OR of role defaults across the caller's ACTIVE roles
    (select bool_or(rp.granted)
       from public.role_permissions rp
       join p on p.id = rp.permission_id
       join public.user_roles ur on ur.role_id = rp.role_id
       join public.roles r on r.id = ur.role_id and r.is_active
      where ur.user_id = auth.uid()),
    false
  )
$$;

-- Lock down execution: revoke the implicit PUBLIC grant (covers anon), and also
-- revoke from anon explicitly (belt-and-suspenders / auditable). Allow only
-- authenticated. Ownership stays with the migration role, so `authenticated`
-- can execute but can never CREATE OR REPLACE / ALTER / DROP these functions.
revoke all on function public.current_profile_id()      from public;
revoke all on function public.is_active_user()          from public;
revoke all on function public.has_role(text)            from public;
revoke all on function public.is_admin()                from public;
revoke all on function public.has_feature(text)         from public;

revoke all on function public.current_profile_id()      from anon;
revoke all on function public.is_active_user()          from anon;
revoke all on function public.has_role(text)            from anon;
revoke all on function public.is_admin()                from anon;
revoke all on function public.has_feature(text)         from anon;

grant execute on function public.current_profile_id()   to authenticated;
grant execute on function public.is_active_user()       to authenticated;
grant execute on function public.has_role(text)         to authenticated;
grant execute on function public.is_admin()             to authenticated;
grant execute on function public.has_feature(text)      to authenticated;

-- ###########################################################################
-- 2) PROFILES — self read + admin oversight read. NO write policy (default
-- deny): role/permission/status fields cannot be changed directly here.
-- ###########################################################################

-- A user reads ONLY their own profile, and ONLY while active + not soft-deleted.
-- Disabled/soft-deleted users therefore cannot read their own profile → they
-- fail every employee access check (the auth layer treats an unreadable profile
-- after sign-in as "disabled" and signs out — Sprint 10).
create policy profiles_select_self
  on public.profiles for select to authenticated
  using (
    id = (select auth.uid())
    and is_active
    and deleted_at is null
  );

-- Admin oversight: an ACTIVE admin reads all non-deleted profiles (active AND
-- inactive/disabled), per the frozen admin oversight rule. A disabled admin is
-- blocked (is_active_user() is false).
create policy profiles_select_admin
  on public.profiles for select to authenticated
  using (
    public.is_active_user()
    and public.is_admin()
    and deleted_at is null
  );

-- ###########################################################################
-- 3) ROLES & PERMISSIONS CATALOGS — active rows to any active user; inactive
-- reserved rows to admin oversight only. Read-only (no write policy → inactive
-- codes can never be made assignable/grantable here). No anon access.
-- ###########################################################################

create policy roles_select_active
  on public.roles for select to authenticated
  using (public.is_active_user() and is_active);

create policy roles_select_admin_all
  on public.roles for select to authenticated
  using (public.is_active_user() and public.is_admin());

create policy permissions_select_active
  on public.permissions for select to authenticated
  using (public.is_active_user() and is_active);

create policy permissions_select_admin_all
  on public.permissions for select to authenticated
  using (public.is_active_user() and public.is_admin());

-- ###########################################################################
-- 4) USER_ROLES — self read + admin read. NO write policy: a user cannot change
-- their own roles; inactive roles are not assignable (no write path here).
-- ###########################################################################

create policy user_roles_select_self
  on public.user_roles for select to authenticated
  using (public.is_active_user() and user_id = (select auth.uid()));

create policy user_roles_select_admin
  on public.user_roles for select to authenticated
  using (public.is_active_user() and public.is_admin());

-- ###########################################################################
-- 5) ROLE_PERMISSIONS & USER_PERMISSIONS — read what's needed to resolve one's
-- OWN effective permissions; admin reads all. NO write policy: users cannot
-- modify their own permissions (no escalation). Effective resolution itself is
-- computed server-side by has_feature() (SECURITY DEFINER).
-- ###########################################################################

-- Role defaults scoped to the caller's own roles. The subquery reads
-- public.user_roles (a DIFFERENT table whose policies do not reference
-- role_permissions), so the dependency graph is acyclic → no RLS recursion.
create policy role_permissions_select_self
  on public.role_permissions for select to authenticated
  using (
    public.is_active_user()
    and role_id in (
      select ur.role_id from public.user_roles ur
      where ur.user_id = (select auth.uid())
    )
  );

create policy role_permissions_select_admin
  on public.role_permissions for select to authenticated
  using (public.is_active_user() and public.is_admin());

create policy user_permissions_select_self
  on public.user_permissions for select to authenticated
  using (public.is_active_user() and user_id = (select auth.uid()));

create policy user_permissions_select_admin
  on public.user_permissions for select to authenticated
  using (public.is_active_user() and public.is_admin());

-- ###########################################################################
-- 6) PHOTOGRAPHER CATALOG SELF-READ — active types to any active user; a user's
-- OWN photographer types; admin reads all assignments. NO write policy.
-- (user_unavailability, project & team policies are NOT in this step.)
-- ###########################################################################

create policy photographer_types_select_active
  on public.photographer_types for select to authenticated
  using (public.is_active_user() and is_active);

create policy photographer_types_select_admin_all
  on public.photographer_types for select to authenticated
  using (public.is_active_user() and public.is_admin());

create policy user_photographer_types_select_self
  on public.user_photographer_types for select to authenticated
  using (public.is_active_user() and user_id = (select auth.uid()));

create policy user_photographer_types_select_admin
  on public.user_photographer_types for select to authenticated
  using (public.is_active_user() and public.is_admin());

-- ###########################################################################
-- 7) AUDIT_LOGS — admin read only. NO insert/update/delete policy for anyone:
-- normal users can never write audit rows, and history stays immutable. Future
-- SECURITY DEFINER RPCs (later steps) write audit rows by bypassing RLS; those
-- RPCs are NOT created here.
-- ###########################################################################

create policy audit_logs_select_admin
  on public.audit_logs for select to authenticated
  using (public.is_active_user() and public.is_admin());

-- ###########################################################################
-- 8) No anon policies anywhere → anon has zero table access. Public client
-- tracking will use a restricted SECURITY DEFINER RPC only (a later step).
-- No write policies were created → all INSERT/UPDATE/DELETE remain default-deny
-- for authenticated and anon; identity/access mutations go through admin-gated
-- RPCs / the admin_create_user Edge Function in later steps.
-- ###########################################################################
