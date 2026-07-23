-- =============================================================================
-- Sprint 10 · Step 10.3 — Admin reset-password backend: record_admin_password_reset.
-- Runs AFTER 20260714220000_admin_create_user_backend.sql. Forward-only; no applied
-- migration edited. No Auth users, no test data, no direct write RLS policies.
--
-- record_admin_password_reset is the SERVICE-ONLY, transactional "finalize" step of
-- an admin password reset. The `admin-reset-password` Edge Function (service_role)
-- first updates the target's Supabase Auth password (a temporary one), then calls
-- this RPC to (a) set profiles.must_change_password = true and (b) write ONE audit
-- row — atomically. Auth and the public schema cannot share one SQL transaction, so
-- the Edge Function orders Auth-update BEFORE this call and, if this call fails,
-- returns a generic failure WITHOUT exposing the temporary password (see
-- docs/SUPABASE_AUTH_INTEGRATION_PLAN.md and the Step 10.3 DEV QA doc).
--
-- SECURITY: SECURITY DEFINER, fixed empty search_path, schema-qualified, no dynamic
-- SQL. Step-6.5 hardened default privileges revoke EXECUTE from all API roles, so
-- this function is granted EXECUTE to service_role ONLY (PUBLIC/anon/authenticated
-- explicitly revoked). It is invoked with the service_role context, so it does NOT
-- trust auth.uid() — it re-validates the supplied p_actor_id itself (active admin +
-- effective can_manage_users), fail-closed.
--
-- AUTHORIZATION (frozen §12 gate): reset password requires an active admin with
-- effective can_manage_users. It does NOT require can_manage_permissions, because a
-- reset assigns NO roles or permissions. This function NEVER changes is_active,
-- roles, photographer types, permissions, username, or full_name.
--
-- TARGET RULES (frozen): active target → allowed; INACTIVE target → allowed for
-- administrative recovery but NOT reactivated (the account stays unusable until a
-- separate reactivation); SOFT-DELETED target → rejected. Self-reset is allowed;
-- the flag is still forced true (the caller's live session may persist until token
-- expiry — no global session revocation here).
--
-- Guardrail (docs/BACKEND_SCOPE_GUARD.md): no finance/payments/Rekaz/notifications/
-- FCM/push/reminders. No email/notification/recovery-link is sent. No password,
-- temporary password, internal email, token, or secret is accepted, stored,
-- audited, or returned.
-- =============================================================================

create or replace function public.record_admin_password_reset(
  p_actor_id        uuid,
  p_target_user_id  uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_can_users boolean;
  v_is_active boolean;
  v_deleted   timestamptz;
begin
  -- ===== 1) Actor authorization (re-checked here; auth.uid() is NOT trusted) ==
  if p_actor_id is null or p_target_user_id is null then
    raise exception 'missing actor or target id' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.profiles a
    where a.id = p_actor_id and a.is_active and a.deleted_at is null
  ) then
    raise exception 'actor is not an active profile' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = p_actor_id and r.code = 'admin' and r.is_active
  ) then
    raise exception 'actor is not an admin' using errcode = '42501';
  end if;
  -- Effective can_manage_users for the ACTOR (override-first, else OR of ACTIVE-
  -- role defaults; only ACTIVE permission catalog rows count) — mirrors
  -- has_feature but keyed on p_actor_id. Reset does NOT require
  -- can_manage_permissions (it assigns no roles/permissions).
  with p as (
    select id from public.permissions
    where code = 'can_manage_users' and is_active
  )
  select coalesce(
    (select up.granted from public.user_permissions up
       join p on p.id = up.permission_id
      where up.user_id = p_actor_id),
    (select bool_or(rp.granted) from public.role_permissions rp
       join p on p.id = rp.permission_id
       join public.user_roles ur on ur.role_id = rp.role_id
       join public.roles r on r.id = ur.role_id and r.is_active
      where ur.user_id = p_actor_id),
    false)
  into v_can_users;
  if not coalesce(v_can_users, false) then
    raise exception 'actor lacks can_manage_users' using errcode = '42501';
  end if;

  -- ===== 2) Target validation ================================================
  -- Must exist, must not be soft-deleted, must have a matching auth row. Inactive
  -- targets ARE allowed (administrative recovery) and are NOT reactivated here.
  select pr.is_active, pr.deleted_at
    into v_is_active, v_deleted
  from public.profiles pr
  where pr.id = p_target_user_id;
  if not found then
    raise exception 'target profile not found' using errcode = 'P0002';
  end if;
  if v_deleted is not null then
    raise exception 'target is soft-deleted' using errcode = 'P0002';
  end if;
  if not exists (select 1 from auth.users u where u.id = p_target_user_id) then
    raise exception 'target auth user does not exist' using errcode = 'P0002';
  end if;

  -- ===== 3) Force the change flag ONLY =======================================
  -- Never touches is_active/roles/photographer_types/permissions/username/name.
  -- updated_at is auto-maintained by the profiles_set_updated_at trigger.
  update public.profiles
     set must_change_password = true
   where id = p_target_user_id;

  -- ===== 4) Audit — minimal, non-sensitive meta only =========================
  -- Never username/email/password/temp-password/token/secret.
  insert into public.audit_logs (actor_id, action, entity, entity_id, meta)
  values (
    p_actor_id, 'user.password_reset', 'profiles', p_target_user_id,
    jsonb_build_object('self_reset', (p_actor_id = p_target_user_id))
  );

  -- ===== 5) Safe result (no email/password/token/secret) =====================
  return jsonb_build_object(
    'id', p_target_user_id,
    'must_change_password', true,
    'is_active', v_is_active
  );
end;
$$;

comment on function public.record_admin_password_reset(uuid, uuid) is
  'Service-only: finalize an admin password reset — set profiles.must_change_password=true for the target and write one user.password_reset audit row, atomically. Re-validates the actor (active admin + can_manage_users; NOT can_manage_permissions). Allows active/inactive targets (inactive is NOT reactivated); rejects soft-deleted. Never changes roles/permissions/is_active/username/name; never handles passwords/internal email. Called by the admin-reset-password Edge Function (service_role) AFTER the Auth password update.';

-- Execution: service_role ONLY (default privileges are hardened, Step 6.5).
revoke all on function public.record_admin_password_reset(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.record_admin_password_reset(uuid, uuid)
  to service_role;
