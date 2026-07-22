-- =============================================================================
-- FIRST-ADMIN BOOTSTRAP — DEV ONLY, MANUAL, ONE-TIME. NOT a migration.
--
-- Runs in the Supabase DEV SQL Editor (the DEV database-owner execution context).
-- ⛔ Do NOT run against Production. ⛔ Do NOT commit real credentials/UUIDs.
-- This file is a PLACEHOLDER template. It creates the FIRST administrator profile
-- so the admin-create-user flow (Step 10.2) has an admin to authenticate — there
-- is no "create by an admin" path for the very first admin.
--
-- Canonical identity contract:
--   • login username (shown to users):   e.g. 'admin'
--   • normalized username (stored):       lower(trim(username)), ^[a-z0-9._-]{2,50}$
--   • hidden internal Auth email:         <normalized_username>@users.sumou.internal
--     (on auth.users only — NEVER shown, NEVER in audit_logs, NEVER via a public RPC)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- STEP A — create the Auth user in the DEV Dashboard (NOT via SQL):
--   Dashboard → Authentication → Users → Add user
--     Email:    admin@users.sumou.internal   (= <normalized_username>@users.sumou.internal)
--     Password: <choose a strong password>   (do NOT write it in this file)
--     ☑ Auto Confirm User
--   Copy the new user's UUID and paste it into v_admin_uid below.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- STEP B — create the matching profile + admin role in ONE transaction. Replace
-- the three placeholders below, then run the whole block in the SQL Editor.
--   • v_admin_uid    : the UUID from STEP A (must NOT stay the all-zero placeholder)
--   • v_admin_user   : the login username (will be normalized + validated)
--   • v_admin_name   : the Arabic display name
--   • must_change_password: choose false (dashboard password is the real password,
--     default here) or true (treat it as temporary → forced change once Step 10.6
--     redirect exists).
-- NO user_permissions rows are inserted — admin capability resolves from
-- role_permissions via has_feature() (never copy role defaults into user_permissions).
-- ---------------------------------------------------------------------------
do $$
declare
  v_admin_uid  uuid := '00000000-0000-0000-0000-000000000000';  -- <-- replace
  v_admin_user text := 'admin';                                  -- <-- replace if needed
  v_admin_name text := 'إدارة سمو';                              -- <-- replace if needed
  v_must_change boolean := false;                                -- bootstrap decision
  v_username   text;
  v_expected_email text;
  v_actual_email   text;
  v_role_id    uuid;
begin
  -- guard: refuse to run with the placeholder UUID still in place.
  if v_admin_uid = '00000000-0000-0000-0000-000000000000' then
    raise exception 'Replace v_admin_uid with the Auth user UUID from STEP A first.';
  end if;

  -- normalize + validate the username (same rule the app/Edge Function use).
  v_username := lower(btrim(v_admin_user));
  if v_username !~ '^[a-z0-9._-]{2,50}$' then
    raise exception 'Invalid username "%": must match ^[a-z0-9._-]{2,50}$', v_admin_user;
  end if;

  -- expected hidden internal Auth identity derived from the normalized username.
  v_expected_email := v_username || '@users.sumou.internal';

  -- verify the Auth user (STEP A) exists and matches this username. The internal
  -- email is NEVER printed in exception text (it is a hidden identity).
  select lower(email) into v_actual_email from auth.users where id = v_admin_uid;
  if v_actual_email is null then
    raise exception 'No auth.users row for v_admin_uid — create the Auth user in the Dashboard (STEP A) first.';
  end if;
  if v_actual_email is distinct from v_expected_email then
    raise exception 'auth.users UUID belongs to a different internal identity than username "%"; fix v_admin_uid or v_admin_user.', v_username;
  end if;

  -- active admin role must exist.
  select id into v_role_id from public.roles where code = 'admin' and is_active;
  if v_role_id is null then
    raise exception 'Active admin role not found — run the Sprint 9 migrations first.';
  end if;

  insert into public.profiles
    (id, username, full_name, default_role_id, is_active, must_change_password)
  values
    (v_admin_uid, v_username, v_admin_name, v_role_id, true, v_must_change);

  insert into public.user_roles (user_id, role_id)
  values (v_admin_uid, v_role_id);

  raise notice 'Bootstrapped admin "%" (uid %) — must_change_password=%',
    v_username, v_admin_uid, v_must_change;
end
$$;

-- ---------------------------------------------------------------------------
-- STEP C — verify (replace the UUID). Expect username='admin', is_active=t,
-- roles={admin}. Admin permissions resolve via role_permissions (has_feature),
-- NOT user_permissions.
-- ---------------------------------------------------------------------------
-- select p.username, p.is_active, p.must_change_password,
--        (select array_agg(r.code) from public.user_roles ur
--           join public.roles r on r.id = ur.role_id where ur.user_id = p.id) as roles
-- from public.profiles p
-- where p.id = '00000000-0000-0000-0000-000000000000';

-- ---------------------------------------------------------------------------
-- CLEANUP / RECOVERY (DEV only; replace the UUID).
--   • wrong profile:  delete from public.user_roles where user_id = '<uid>';
--                     delete from public.profiles  where id      = '<uid>';
--                     then delete the Auth user in the Dashboard.
--   • locked out:     Dashboard → Authentication → reset the user's password;
--                     or re-run STEP B after cleanup.
--   • disable (keep history): update public.profiles set is_active = false where id = '<uid>';
--     (do NOT hard-delete auth.users for history; disabling fails closed in RLS.)
-- ---------------------------------------------------------------------------
