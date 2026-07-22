-- =============================================================================
-- Sprint 9 · Step 6.5 (QA fix) — lock EXECUTE on internal/trigger-only functions
-- and stop future public functions from auto-granting EXECUTE to the API roles.
-- Runs AFTER 20260714190000_project_write_rpcs.sql. Forward-only fix migration
-- (prior migrations are NOT edited; no table, RLS policy, or function body change).
--
-- DEFECT (critical): Supabase's default privileges grant EXECUTE on every new
-- `public` function to the API roles `anon`, `authenticated`, and `service_role`.
-- The Step-6.4 internal functions `public._apply_project_team(uuid, jsonb)` and
-- `public.gen_project_serial(public.project_type)` revoked EXECUTE only from
-- `public` and `anon`, so `authenticated` (and `service_role`) KEPT the default
-- grant and could call them directly. `_apply_project_team` is SECURITY DEFINER
-- and performs NO caller authorization (it trusts its callers create_project /
-- assign_team_roles), so a logged-in user could invoke it directly to:
--   • wipe any project's team:  _apply_project_team('<victim>', '[]')  (empty →
--     no availability calls → deletes all project_team_members for that project);
--   • replace a team with arbitrary EXTERNAL members (user_id null → no
--     availability calls);
--   • insert THEMSELVES onto a victim project (is_available passes its own gate
--     when uid = auth.uid()), gaining assigned RLS access to that project.
-- The `set_updated_at()` trigger helper likewise retained the default API-role
-- grants (harmless — SECURITY INVOKER, a no-op outside a trigger — but no API
-- role needs to execute it).
--
-- RISK: unauthorized destruction/manipulation of any project's team and RLS
-- privilege escalation via self-assignment. NOTE: do NOT rely on audit_logs as a
-- mitigation — a direct call bypasses the intended assign_team_roles
-- authorization workflow, and any audit row it might write is indistinguishable
-- from a legitimate assignment and is not guaranteed. Prevention (revoking
-- EXECUTE) is the control, not detection.
--
-- FIX: (1) explicitly REVOKE EXECUTE from PUBLIC + the three API roles for these
-- internal/trigger functions; (2) change the schema's DEFAULT privileges so
-- future postgres-owned `public` functions are NOT auto-granted EXECUTE to the
-- API roles — each externally callable RPC must then receive an EXPLICIT grant in
-- its own migration.
--
-- LEGITIMATE FLOWS ARE UNAFFECTED: create_project and assign_team_roles are
-- SECURITY DEFINER and owned by the same role (postgres) that owns
-- _apply_project_team / gen_project_serial. A function's OWNER always retains
-- EXECUTE on its own objects regardless of REVOKEs, and a SECURITY DEFINER
-- function calls other functions as its owner — so these trusted callers keep
-- invoking the internal helpers through the database-owner execution context.
--
-- Guardrail: no finance/payments/Rekaz/notifications/FCM/push/reminders. Only
-- EXECUTE-privilege / default-privilege changes; no schema/RLS/body change; no data.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) Revoke EXECUTE on the internal/trigger-only functions from PUBLIC and every
--    API role (anon, authenticated, service_role). Owner (postgres) keeps it.
-- ---------------------------------------------------------------------------
revoke all on function public._apply_project_team(uuid, jsonb)
  from public, anon, authenticated, service_role;

revoke all on function public.gen_project_serial(public.project_type)
  from public, anon, authenticated, service_role;

revoke all on function public.set_updated_at()
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2) Secure-by-default: stop future postgres-owned `public` functions from
--    auto-granting EXECUTE. Externally callable RPCs must add an explicit
--    `grant execute ... to authenticated` (and/or `anon`) in their own migration.
-- ---------------------------------------------------------------------------
alter default privileges for role postgres in schema public
  revoke execute on functions from public;

alter default privileges for role postgres in schema public
  revoke execute on functions from anon, authenticated, service_role;
