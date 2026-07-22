-- =============================================================================
-- Sprint 9 · Step 6.5 (QA fix) — lock EXECUTE on internal/trigger-only functions.
-- Runs AFTER 20260714190000_project_write_rpcs.sql. Forward-only fix migration
-- (prior migrations are NOT edited).
--
-- DEFECT (critical): Supabase's default privileges grant EXECUTE on every new
-- `public` function to the API roles `anon`, `authenticated`, and `service_role`.
-- The Step-6.4 internal functions `public._apply_project_team(uuid, jsonb)` and
-- `public.gen_project_serial(public.project_type)` only did
--   revoke all ... from public;  revoke all ... from anon;
-- so `authenticated` KEPT the default EXECUTE grant and could call them directly.
-- `_apply_project_team` is SECURITY DEFINER and performs NO caller authorization
-- (it trusts its callers create_project/assign_team_roles), so a logged-in user
-- could invoke it directly to:
--   • wipe any project's team:  _apply_project_team('<victim>', '[]')  (empty →
--     no availability calls → deletes all project_team_members for that project);
--   • replace a team with arbitrary EXTERNAL members (user_id null → no
--     availability calls);
--   • insert THEMSELVES onto a victim project (is_available passes its own gate
--     when uid = auth.uid()), gaining assigned RLS access to that project.
-- The `set_updated_at()` trigger helper likewise retained the default API-role
-- grants (harmless — it is SECURITY INVOKER and a no-op outside a trigger — but
-- no API role needs to execute it).
--
-- RISK: unauthorized destruction/manipulation of any project's team and RLS
-- privilege escalation via self-assignment. Traceable in audit_logs (actor_id),
-- but still a serious integrity/authorization hole.
--
-- FIX: explicitly REVOKE EXECUTE from the API roles for these internal/trigger
-- functions. The SECURITY DEFINER callers (create_project / assign_team_roles),
-- owned by the same role that owns these functions, still execute them via
-- ownership — so legitimate flows are unaffected. This is defense-in-depth even
-- if a given project's default privileges differ: revoking a grant the role does
-- not hold is a harmless no-op.
--
-- Guardrail: no finance/payments/Rekaz/notifications/FCM/push/reminders. No table
-- policy, no schema change, no data. Only EXECUTE privilege changes.
-- =============================================================================

revoke all on function public._apply_project_team(uuid, jsonb)
  from public, anon, authenticated;

revoke all on function public.gen_project_serial(public.project_type)
  from public, anon, authenticated;

revoke all on function public.set_updated_at()
  from public, anon, authenticated;
