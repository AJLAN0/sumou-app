-- =============================================================================
-- Sprint 10 · Step 10.2 — Admin create-user backend: create_staff_profile RPC.
-- Runs AFTER 20260714210000_auth_schema_readiness.sql. Forward-only; no applied
-- migration edited. No Auth users, no test data, no direct write policies.
--
-- create_staff_profile is the SERVICE-ONLY transactional core of admin user
-- provisioning. The `admin-create-user` Edge Function (service_role) creates the
-- auth.users row + temporary password, then calls this RPC to create ALL public
-- identity rows + one audit row atomically. Auth and public schema cannot be one
-- cross-system SQL transaction, so the Edge Function compensates (deletes the
-- just-created Auth user) if this RPC fails — see docs/SUPABASE_AUTH_INTEGRATION_PLAN.md.
--
-- SECURITY: SECURITY DEFINER, fixed empty search_path, schema-qualified, no
-- dynamic SQL. Because Step-6.5 hardened default privileges revoke EXECUTE from
-- all API roles, this function is granted EXECUTE to service_role ONLY (PUBLIC/
-- anon/authenticated explicitly revoked). It is called with the service_role
-- context, so it does NOT trust auth.uid() — it re-validates the supplied
-- p_actor_id (active admin + effective can_manage_users) itself, fail-closed.
--
-- Guardrail (docs/BACKEND_SCOPE_GUARD.md): no finance/payments/Rekaz/
-- notifications/FCM/push/reminders. Inactive roles (finance/wedding_finance) and
-- inactive permissions (can_manage_finance) are REJECTED, never assigned. Role
-- defaults are NEVER copied into user_permissions (they resolve via has_feature()).
-- No password/temp-password/internal-email/token/secret is accepted, stored,
-- audited, or returned.
--
-- Inputs use stable CODES (roles/permissions/photographer types), never internal
-- UUIDs. p_actor_id and p_user_id are trusted only as identifiers to validate.
-- =============================================================================

create or replace function public.create_staff_profile(
  p_actor_id             uuid,
  p_user_id              uuid,
  p_username             text,
  p_full_name            text,
  p_default_role         text,
  p_roles                text[],
  p_photographer_types   text[]  default '{}',
  p_permission_overrides jsonb   default '[]'::jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_username   text := lower(btrim(coalesce(p_username, '')));
  v_full_name  text := btrim(coalesce(p_full_name, ''));
  v_roles      text[] := coalesce(p_roles, '{}');
  v_types      text[] := coalesce(p_photographer_types, '{}');
  v_overrides  jsonb  := coalesce(p_permission_overrides, '[]'::jsonb);
  v_default_id uuid;
  v_email      text;
  v_can_manage boolean;
begin
  -- ===== 1) Actor authorization (re-checked here; auth.uid() is NOT trusted) ==
  if p_actor_id is null or p_user_id is null then
    raise exception 'missing actor or user id' using errcode = '22023';
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
  -- effective can_manage_users for the ACTOR: user override wins, else OR of
  -- active-role defaults (mirrors has_feature but keyed on p_actor_id).
  with p as (select id from public.permissions where code = 'can_manage_users' and is_active)
  select coalesce(
    (select up.granted from public.user_permissions up join p on p.id = up.permission_id
       where up.user_id = p_actor_id),
    (select bool_or(rp.granted) from public.role_permissions rp
       join p on p.id = rp.permission_id
       join public.user_roles ur on ur.role_id = rp.role_id
       join public.roles r on r.id = ur.role_id and r.is_active
       where ur.user_id = p_actor_id),
    false)
  into v_can_manage;
  if not coalesce(v_can_manage, false) then
    raise exception 'actor lacks can_manage_users' using errcode = '42501';
  end if;

  -- ===== 2) New-user identity validation =====================================
  if not exists (select 1 from auth.users u where u.id = p_user_id) then
    raise exception 'auth user does not exist' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.profiles pr where pr.id = p_user_id) then
    raise exception 'a profile already exists for this user' using errcode = '23505';
  end if;
  if v_username <> coalesce(p_username, '') or v_username !~ '^[a-z0-9._-]{2,50}$' then
    raise exception 'username is not normalized or is malformed' using errcode = '22023';
  end if;
  if exists (select 1 from public.profiles pr where pr.username = v_username) then
    raise exception 'username is already taken' using errcode = '23505';
  end if;
  if v_full_name = '' then
    raise exception 'full name is required' using errcode = '22023';
  end if;
  -- hidden internal email must match the normalized username. Never echo it.
  select lower(u.email) into v_email from auth.users u where u.id = p_user_id;
  if v_email is distinct from (v_username || '@users.sumou.internal') then
    raise exception 'auth identity does not match the username' using errcode = '42501';
  end if;

  -- ===== 3) Roles validation (all active, no dup, default included) ==========
  if array_length(v_roles, 1) is null then
    raise exception 'at least one role is required' using errcode = '22023';
  end if;
  if (select count(*) from unnest(v_roles)) <>
     (select count(distinct x) from unnest(v_roles) x) then
    raise exception 'duplicate role in selection' using errcode = '22023';
  end if;
  if not (p_default_role = any (v_roles)) then
    raise exception 'default role must be among the selected roles' using errcode = '22023';
  end if;
  if not exists (select 1 from public.roles r where r.code = p_default_role and r.is_active) then
    raise exception 'default role is invalid or inactive' using errcode = '22023';
  end if;
  -- every selected code must resolve to an ACTIVE role (rejects finance/
  -- wedding_finance/client_tracking/unknown). Count match = all valid.
  if (select count(*) from public.roles r
        where r.code = any (v_roles) and r.is_active)
     <> (select count(distinct x) from unnest(v_roles) x) then
    raise exception 'one or more roles are invalid or inactive' using errcode = '22023';
  end if;
  select r.id into v_default_id from public.roles r where r.code = p_default_role and r.is_active;

  -- ===== 4) Photographer types validation (optional; active, no dup) =========
  if array_length(v_types, 1) is not null then
    if (select count(*) from unnest(v_types)) <>
       (select count(distinct x) from unnest(v_types) x) then
      raise exception 'duplicate photographer type in selection' using errcode = '22023';
    end if;
    if (select count(*) from public.photographer_types pt
          where pt.code = any (v_types) and pt.is_active)
       <> (select count(distinct x) from unnest(v_types) x) then
      raise exception 'one or more photographer types are invalid or inactive' using errcode = '22023';
    end if;
  end if;

  -- ===== 5) Permission overrides validation (explicit, active, no dup) =======
  if jsonb_typeof(v_overrides) <> 'array' then
    raise exception 'permission_overrides must be an array' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_overrides) o
    where jsonb_typeof(o) <> 'object'
       or jsonb_typeof(o->'granted') <> 'boolean'
       or coalesce(o->>'code','') = ''
  ) then
    raise exception 'each permission override needs a code and a boolean granted' using errcode = '22023';
  end if;
  if (select count(*) from jsonb_array_elements(v_overrides) o) <>
     (select count(distinct (o->>'code')) from jsonb_array_elements(v_overrides) o) then
    raise exception 'duplicate permission override' using errcode = '22023';
  end if;
  -- every override code must be an ACTIVE permission (rejects can_manage_finance
  -- and any inactive/unknown code). Never materializes role defaults.
  if exists (
    select 1 from jsonb_array_elements(v_overrides) o
    where not exists (
      select 1 from public.permissions pm
      where pm.code = o->>'code' and pm.is_active
    )
  ) then
    raise exception 'one or more permission overrides are invalid or inactive' using errcode = '22023';
  end if;

  -- ===== 6) Atomic inserts (whole function = one transaction) ================
  insert into public.profiles
    (id, username, full_name, default_role_id, is_active, must_change_password)
  values
    (p_user_id, v_username, v_full_name, v_default_id, true, true);

  insert into public.user_roles (user_id, role_id)
  select p_user_id, r.id from public.roles r
  where r.code = any (v_roles) and r.is_active;

  insert into public.user_photographer_types (user_id, photographer_type_id)
  select p_user_id, pt.id from public.photographer_types pt
  where pt.code = any (v_types) and pt.is_active;

  -- explicit overrides only; nothing when the array is empty.
  insert into public.user_permissions (user_id, permission_id, granted)
  select p_user_id, pm.id, (o->'granted')::boolean
  from jsonb_array_elements(v_overrides) o
  join public.permissions pm on pm.code = o->>'code' and pm.is_active;

  -- audit: counts only — never username/email/password/tokens/secrets.
  insert into public.audit_logs (actor_id, action, entity, entity_id, meta)
  values (
    p_actor_id, 'user.create', 'profiles', p_user_id,
    jsonb_build_object(
      'role_count', array_length(v_roles, 1),
      'photo_type_count', coalesce(array_length(v_types, 1), 0),
      'override_count', jsonb_array_length(v_overrides)
    )
  );

  -- ===== 7) Safe result (no email/password/token/secret) =====================
  return jsonb_build_object(
    'id', p_user_id,
    'username', v_username,
    'full_name', v_full_name,
    'default_role', p_default_role,
    'roles', (select coalesce(jsonb_agg(x order by x), '[]'::jsonb) from unnest(v_roles) x),
    'photographer_types', (select coalesce(jsonb_agg(x order by x), '[]'::jsonb) from unnest(v_types) x),
    'permission_overrides', v_overrides,
    'is_active', true,
    'must_change_password', true
  );
end;
$$;

comment on function public.create_staff_profile(uuid, uuid, text, text, text, text[], text[], jsonb) is
  'Service-only: atomically create a staff identity (profiles+user_roles+user_photographer_types+optional user_permissions overrides) + a user.create audit row. Re-validates the actor (active admin + can_manage_users). Never copies role_permissions into user_permissions; never handles passwords/internal email. Called by the admin-create-user Edge Function (service_role).';

-- Execution: service_role ONLY (default privileges are hardened, Step 6.5).
revoke all on function public.create_staff_profile(uuid, uuid, text, text, text, text[], text[], jsonb)
  from public, anon, authenticated;
grant execute on function public.create_staff_profile(uuid, uuid, text, text, text, text[], text[], jsonb)
  to service_role;
