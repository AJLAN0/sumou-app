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
-- Deliberate backfill (reported): profiles that already exist BEFORE this feature
-- are treated as already-established and are NOT forced through the change flow —
-- this avoids locking a manually-bootstrapped admin (dashboard-set password) out
-- of a usable login once the redirect lands. New rows use the column default
-- (true). On an empty database this affects 0 rows (reproducible). The first-admin
-- bootstrap template sets the value explicitly for a freshly bootstrapped admin.
-- ---------------------------------------------------------------------------
update public.profiles set must_change_password = false;
