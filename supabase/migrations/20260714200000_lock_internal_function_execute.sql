-- =============================================================================
-- Sprint 9 · Step 6.5 (QA fix) — lock EXECUTE on internal/trigger-only functions
-- and stop future public functions from auto-granting EXECUTE to the API roles.
-- Runs AFTER 20260714190000_project_write_rpcs.sql. Forward-only; no applied
-- migration edited; no table, RLS policy, or function body change.
--
-- DEFECT (critical): Supabase default privileges grant EXECUTE on every new
-- `public` function to anon/authenticated/service_role. The Step-6.4 internal
-- functions _apply_project_team / gen_project_serial revoked EXECUTE only from
-- public and anon, so authenticated (and service_role) kept the grant.
-- _apply_project_team is SECURITY DEFINER and does NO caller authorization, so a
-- logged-in user could call it directly to wipe/replace any project's team or
-- insert themselves onto a victim project (RLS privilege escalation).
--
-- Prevention (revoking EXECUTE) is the control, not detection: a direct call
-- bypasses the assign_team_roles workflow and must not be assumed to be audited.
--
-- FIX: revoke EXECUTE on the internal/trigger functions from PUBLIC + all API
-- roles, and change the schema DEFAULT privileges so future postgres-owned public
-- functions are not auto-granted EXECUTE (each externally callable RPC must add
-- an explicit grant in its own migration). Legitimate flows are unaffected:
-- create_project / assign_team_roles are SECURITY DEFINER owned by the same role
-- (postgres) that owns the helpers, and an owner always retains EXECUTE on its own
-- objects — so the trusted callers still invoke the helpers via ownership.
--
-- Guardrail: no finance/payments/Rekaz/notifications/FCM/push/reminders. Only
-- privilege / default-privilege statements; no schema/RLS/body change; no data.
-- =============================================================================

-- 1) Revoke EXECUTE on the internal/trigger-only functions from PUBLIC and every
--    API role (anon, authenticated, service_role). Owner (postgres) keeps it.
revoke all
on function public._apply_project_team(uuid, jsonb)
from public, anon, authenticated, service_role;

revoke all
on function public.gen_project_serial(public.project_type)
from public, anon, authenticated, service_role;

revoke all
on function public.set_updated_at()
from public, anon, authenticated, service_role;

-- 2) Secure-by-default: stop future postgres-owned `public` functions from
--    auto-granting EXECUTE to the API roles. Externally callable RPCs must add an
--    explicit `grant execute ... to authenticated` (and/or `anon`) themselves.
alter default privileges for role postgres in schema public
  revoke execute on functions from public;

alter default privileges for role postgres in schema public
  revoke execute on functions from anon, authenticated, service_role;
