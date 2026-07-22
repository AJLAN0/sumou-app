-- =============================================================================
-- Sprint 10 · Step 10.1 — Auth schema readiness (forced first password change).
-- Runs AFTER 20260714200000_lock_internal_function_execute.sql. Forward-only; no
-- applied migration edited.
--
-- SCOPE: the ONE schema addition needed before the Auth Edge Functions / Flutter
-- integration — a first-login password-change gate on public.profiles. No Auth
-- users, no Edge Functions, no Flutter, no RPCs, no policies, no secrets.
--
-- Identity model is unchanged and already correct (Step 2 / Step 6.1):
--   • profiles.id = auth.users.id (1:1, on delete cascade).
--   • username is normalized + unique (CHECK ^[a-z0-9._-]{2,50}$, UNIQUE).
--   • the internal Auth email lives ONLY on auth.users — never stored on profiles,
--     never displayed, never in audit_logs, never returned by a public RPC.
--   • role defaults come from role_permissions; user_permissions holds per-user
--     overrides only; nothing here copies role defaults into user_permissions.
--   • is_active_user()/has_role()/has_feature() fail closed for inactive/deleted
--     profiles (Step 6.1) — unaffected by this column.
--
-- Guardrail (docs/BACKEND_SCOPE_GUARD.md): no finance/payments/Rekaz/
-- notifications/FCM/push/reminders. NO password hashes, temporary passwords,
-- tokens, OTPs, reset secrets, or internal Auth email are added to profiles.
--
-- RLS: unchanged. The existing profiles SELECT policies already scope this column
-- correctly — a user reads only their OWN row (so their own must_change_password),
-- an admin reads all non-deleted rows for account management, and no other
-- ordinary user can read someone else's profile. NO new policy, NO profile UPDATE
-- policy (writes stay default-deny); the flag is flipped only by trusted backend
-- operations (the Step-10.2/10.3 Edge Functions / a later narrow authorized RPC).
-- Default function privileges stay hardened (Step 6.5); no anon grant.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Forced first-login password change gate. New users start `true` (created with
-- a temporary password); a successful first self-change sets it `false`; an admin
-- reset sets it back `true`. The Flutter redirect and the password-update
-- operation are NOT implemented here (later Step 10.5/10.6).
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column must_change_password boolean not null default true;

comment on column public.profiles.must_change_password is
  'First-login password gate. New users start true (temp password); set false on '
  'first successful self password change; an admin reset sets it true again. Drives '
  'a later forced change-password redirect. Never stores passwords/tokens/OTPs/secrets.';

-- ---------------------------------------------------------------------------
-- Deliberate, NARROW backfill: clear the flag ONLY for an existing active,
-- non-deleted profile that holds the active `admin` role — i.e. the manually
-- bootstrapped first admin, whose dashboard-set password is a real password.
-- This protects that account from being forced into a change (once the Step-10.6
-- redirect lands) WITHOUT exempting every old row: disabled, soft-deleted, and
-- non-admin profiles KEEP must_change_password = true, so any pre-existing staff
-- account (which would have been created with a temporary password) is still
-- correctly forced to change. New rows use the column default (true). On an empty
-- database this matches 0 rows (reproducible).
-- ---------------------------------------------------------------------------
update public.profiles p
set must_change_password = false
where p.is_active
  and p.deleted_at is null
  and exists (
    select 1
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = p.id
      and r.code = 'admin'
      and r.is_active
  );
