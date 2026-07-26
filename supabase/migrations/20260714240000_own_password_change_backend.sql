-- =============================================================================
-- Sprint 10 · Step 10.6A — Own password-change backend: record_own_password_change.
-- Runs AFTER 20260714230000_admin_reset_password_backend.sql. Forward-only; no
-- applied migration edited. No Auth users, no test data, no direct write RLS policy.
--
-- record_own_password_change is the SERVICE-ONLY, transactional "finalize" step of
-- a user changing THEIR OWN password. The `change-own-password` Edge Function
-- (service_role) first re-authenticates the caller's current password and updates
-- their Supabase Auth password, then calls this RPC to (a) clear
-- profiles.must_change_password and (b) write ONE audit row — atomically. Auth and
-- the public schema cannot share one SQL transaction, so the Edge Function orders
-- Auth-update BEFORE this call; if this call fails AFTER the Auth password changed,
-- it returns a generic failure (the safe retry uses the NEW password as
-- current_password). See docs/SUPABASE_AUTH_INTEGRATION_PLAN.md + the Step 10.6 QA.
--
-- SECURITY: SECURITY DEFINER, fixed empty search_path, schema-qualified, no dynamic
-- SQL. Step-6.5 hardened default privileges revoke EXECUTE from all API roles, so
-- this function is granted EXECUTE to service_role ONLY (PUBLIC/anon/authenticated
-- explicitly revoked). Invoked in the service_role context, so it re-validates the
-- supplied p_user_id itself (active, non-deleted profile + matching auth row).
--
-- AUTHORIZATION: any active, non-deleted staff account may change its own password
-- — NO admin role and NO feature permission is required (the Edge Function already
-- proved the caller owns the session and knows the current password). This function
-- NEVER changes is_active, roles, photographer types, permissions, username, or
-- full_name — it only clears must_change_password.
--
-- Guardrail (docs/BACKEND_SCOPE_GUARD.md): no finance/payments/Rekaz/notifications/
-- FCM/push/reminders. No password, token, internal email, or secret is accepted,
-- stored, audited, or returned.
-- =============================================================================

create or replace function public.record_own_password_change(
  p_user_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_is_active boolean;
  v_deleted   timestamptz;
begin
  -- ===== 1) Caller validation (service context; re-checked here) =============
  if p_user_id is null then
    raise exception 'missing user id' using errcode = '22023';
  end if;
  select pr.is_active, pr.deleted_at
    into v_is_active, v_deleted
  from public.profiles pr
  where pr.id = p_user_id;
  if not found then
    raise exception 'profile not found' using errcode = 'P0002';
  end if;
  if v_deleted is not null or not v_is_active then
    raise exception 'account is not active' using errcode = '42501';
  end if;
  if not exists (select 1 from auth.users u where u.id = p_user_id) then
    raise exception 'auth user does not exist' using errcode = 'P0002';
  end if;

  -- ===== 2) Clear the forced-change flag ONLY ================================
  -- Never touches is_active/roles/photographer_types/permissions/username/name.
  -- updated_at is auto-maintained by the profiles_set_updated_at trigger.
  update public.profiles
     set must_change_password = false
   where id = p_user_id;

  -- ===== 3) Audit — identifiers only; NEVER password/email/token/secret ======
  insert into public.audit_logs (actor_id, action, entity, entity_id, meta)
  values (
    p_user_id, 'user.password_changed', 'profiles', p_user_id, '{}'::jsonb
  );

  -- ===== 4) Safe result (no email/password/token/secret) =====================
  return jsonb_build_object(
    'id', p_user_id,
    'must_change_password', false,
    'is_active', v_is_active
  );
end;
$$;

comment on function public.record_own_password_change(uuid) is
  'Service-only: finalize a user own-password change — clear profiles.must_change_password for p_user_id and write one user.password_changed audit row, atomically. Re-validates the caller (active, non-deleted profile + matching auth row). Requires NO admin role or feature permission. Never changes roles/permissions/is_active/username/name; never handles passwords/internal email. Called by the change-own-password Edge Function (service_role) AFTER the Auth password update.';

-- Execution: service_role ONLY (default privileges are hardened, Step 6.5).
revoke all on function public.record_own_password_change(uuid)
  from public, anon, authenticated;
grant execute on function public.record_own_password_change(uuid)
  to service_role;
