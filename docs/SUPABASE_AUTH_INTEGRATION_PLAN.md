# Auth Integration Plan — admin-managed accounts & passwords

**Status:** Planning only (docs). No Flutter changes, no packages, no Edge Functions, no remote actions in this doc. Build begins only after approval.
**Frozen anchor:** decision **D2** in `docs/SUPABASE_CORE_PLAN.md` (username login, internal generated auth email, admin creation via secure Edge Function, no email confirmation, secure password flow).
**Guardrail:** nothing here touches finance/payments/Rekaz/notifications/FCM/push/reminders. No email invites/magic links (internal emails are not real inboxes).

**Chosen options:** initial password = **auto-generated temporary** (shown once to the admin); rollout = **plan first, then build**.

---

## 1. The model in one paragraph

Accounts are **password accounts** on an **internal, non-routable email** (`<username>@users.sumou.internal`) that is never shown. The admin **creates a user with an auto-generated temporary password** (via a secure server function), hands it over, the user **logs in with username + temp password**, then **changes their own password**. The `service_role` key lives **only** inside the Edge Function — never in Flutter, never committed.

---

## 2. Bootstrap the first admin (one-time, manual — DEV)

The first admin can't be created "by an admin", so it is bootstrapped once,
manually, in **DEV only**. The single **canonical** procedure is the
placeholder-only template `docs/qa/FIRST_ADMIN_BOOTSTRAP_DEV.sql` (SQL-Editor
`DO` block): create the Auth user in the Dashboard with the internal email, then
insert the matching `profiles` (same UUID, active `admin` default role,
`must_change_password` set explicitly) + `user_roles` in one transaction — **no**
`user_permissions` copies (admin capability resolves from `role_permissions` via
`has_feature()`). Admin state may or may not already exist on DEV; the template's
placeholder guard and username validation make it safe to run once.

> **Production bootstrap is a separate, future release procedure** — do **not**
> run it now, and do **not** reuse the DEV template against Production.

---

## 3. Creating users (admin) — `admin-create-user` Edge Function

Runs with **service_role** (an Edge Function secret), so it can create auth users and bypass RLS for the profile insert.

**Input:** `{ username, full_name, default_role, roles[], photo_types[] }` + the caller's JWT (Authorization header).

**Steps:**
1. **Authorize the caller:** verify the JWT → the caller is an **active admin** with `can_manage_users` (checked server-side against `profiles`/`user_roles`/permissions). Reject otherwise.
2. **Normalize + validate** username (`^[a-z0-9._-]{2,50}$`); ensure it's not already taken.
3. **Generate a strong temporary password** (e.g. 16+ random chars).
4. `serviceClient.auth.admin.createUser({ email: '<username>@users.sumou.internal', password: <temp>, email_confirm: true, user_metadata: { username } })` — a **confirmed** account, **no email sent**.
5. **Create the profile atomically** via the service-only `security definer` RPC
   `create_staff_profile(p_actor_id, p_user_id, p_username, p_full_name, p_default_role, p_roles[], p_photographer_types[], p_permission_overrides jsonb)` — **exact signature/behavior in §12**. In ONE transaction it inserts `profiles` (`is_active=true`, `must_change_password=true`), `user_roles` (incl. the default), `user_photographer_types`, and — only when supplied — explicit `user_permissions` **overrides**, plus the audit row. It **re-validates `p_actor_id`** (active admin + `can_manage_users`) since `auth.uid()` is not the admin in the service context, and it **NEVER** copies `role_permissions` into `user_permissions` (role defaults resolve via `has_feature()`). Compensation: if this step fails, the Edge Function deletes the just-created auth user (§9).
6. **Audit** one minimal `audit_logs` row: `actor_id` = caller, `action` = `user.create`, `entity` = `profiles`, `entity_id` = new user id. **Never** log the password, the internal email, or any secret in `meta`.
7. **Return `{ user, temp_password }` once** — the app shows the temp password to the admin to hand over. It is **never stored** (not in the DB, not in logs).

> Wiring into the app: the existing admin "add user" flow calls `supabase.functions.invoke('admin-create-user', ...)` and displays the returned temp password in a copyable dialog. Username-based UX stays; internal email is hidden.

---

## 4. Login — `SupabaseAuthRepository.login`

1. `email = normalize(username) + '@users.sumou.internal'` (derived, no DB lookup, never shown).
2. `signInWithPassword({ email, password })`.
3. On success, load the profile; if `is_active = false` → `signOut()` + throw `AuthException(accountDisabled)`.
4. On failure → `AuthException(invalidCredentials)`.
5. Map profile + roles + **effective** permissions (override-then-role-default) → `UserModel`.

Keeps the exact `AuthRepository` interface, so the UI/providers don't change.

---

## 5. Changing the password

**User self-service (existing `ChangePasswordScreen` + `changePassword(currentPassword, newPassword)`):**
1. Re-authenticate with the current password (sign in with `email` + `currentPassword`) to verify identity.
2. `auth.updateUser({ password: newPassword })`. No service_role, no Edge Function.

**Admin reset — `admin-reset-password` Edge Function (service_role):**
1. Authorize caller (**active, non-deleted admin** + `can_manage_users`); the target must be an **active, non-deleted** managed account. A normal user can never reset another user's password.
2. Generate a new **temporary** password.
3. `auth.admin.updateUserById(targetUserId, { password: <temp> })`.
4. Set the target's `profiles.must_change_password = true` (via the trusted server context) so the next login forces a change.
5. **Audit** `action = user.reset_password` (identifiers only — **no** password/email/secret).
6. Return the temp password **once** for the admin to hand over. No email/notification delivery. The internal Auth email stays hidden throughout.

---

## 6. Security rules

- `service_role` key: set via `supabase secrets set` for the Edge Function(s) only. **Never** in Flutter, `.env` committed files, or the repo.
- Flutter uses **only** the public `anon` key + project URL (per environment).
- Temp/new passwords are returned once, shown once, **never stored** in the DB or logs (see `audit_logs` guardrail: no passwords/tokens/emails in `meta`).
- Internal auth email is derived and never displayed.

---

## 7. Dependency & sequencing (important)

- **RLS prerequisite — already satisfied.** Logging in and loading a profile
  requires RLS policies that let a user **read their own** `profiles` /
  `user_roles` / `user_permissions` (+ read the `roles`/`permissions` catalogs).
  These identity/access **self-read RLS policies are completed and live on DEV**
  (Sprint 9 Step 6.1, migration `20260714160000_identity_access_rls.sql`). **No
  additional self-read RLS prerequisite is needed in Sprint 10** — the Auth build
  starts directly at the create-user backend.
- The `admin-create-user` path runs with service_role (bypasses RLS); the app
  reads data back through the existing self-read policies.

---

## 8. Build checklist — the approved eight-step Sprint 10 sequence

Identity/access self-read RLS is **already done** (Step 6.1, live on DEV), so it
is **not** a step here. The Auth build follows the approved sequence (see §11):

1. **Auth schema readiness** — `profiles.must_change_password` (migration
   `20260714210000`). *(done — prepared in code; pending manual DEV apply.)*
2. **Admin create-user backend** — `create_staff_profile` `security definer` RPC
   (needs an **explicit** `execute` grant — default function privileges are
   hardened, Step 6.5) + `admin-create-user` Edge Function (service_role secret).
3. **Admin reset-password backend** — `admin-reset-password` Edge Function.
4. **Flutter Supabase initialization** — add `supabase_flutter`; URL + anon key via
   `--dart-define-from-file`.
5. **Username login / session / profile loading** — `SupabaseAuthRepository`;
   sign out / block inactive/deleted profiles.
6. **Forced first password change** — redirect on `must_change_password` + the
   trusted completion operation that clears the flag (mechanism TBD; §11).
7. **Admin user-management integration** — wire create/reset/activate/roles.
8. **Auth QA**.

> **Production deployment remains a separate, explicitly-approved future release**
> — do not push functions/migrations to Production or perform any Production
> action now. All apply steps in this checklist are **DEV-only** until then.

---

## 9. Test plan (DEV)

Bootstrap admin → log in as admin → create a user (get temp password) → log out → log in as the new user with the temp password → change password → log out → log in with the new password. Verify a **deactivated** user (`is_active=false`) is blocked at login. Widget tests continue on the mock auth repo.

---

## 10. Out of scope for this build

No project/team/closure logic, no finance/payments/Rekaz/notifications/FCM/push/reminders, no email-based flows, no self-signup (admin-provisioned only), and `service_role` never leaves the server.

---

## 11. Step 10.1 — Auth schema readiness (prepared in code)

Migration `supabase/migrations/20260714210000_auth_schema_readiness.sql` —
**prepared in code; pending owner review and manual DEV application** (not yet
applied to DEV, not on Production). This is the schema-only groundwork before the
Edge Functions and Flutter work — **no** Auth users, Edge Functions, Flutter,
RPCs, policies, or secrets.

### Approved Sprint 10 sequence
1. **Auth schema readiness** ← this step (10.1)
2. Admin create-user backend (Edge Function + `create_staff_profile` RPC)
3. Admin reset-password backend (Edge Function)
4. Flutter Supabase initialization
5. Username login / session / profile loading
6. Forced first password change (redirect + password update)
7. Admin user-management integration
8. Auth QA

### Schema change
`public.profiles.must_change_password boolean NOT NULL DEFAULT true`.
Lifecycle: **true** at creation (temp password) → **false** on first successful
self-change → **true** again on an admin reset. It drives the later forced
change-password redirect (Step 10.6). No password/token/OTP/secret column added.

**Backfill (deliberate, narrow):** only an existing **active, non-deleted** profile
that holds the **active `admin` role** is set to **false** — the manually
bootstrapped first admin, whose dashboard-set password is a real password. Every
**other** existing profile keeps **true**: disabled, soft-deleted, and non-admin
accounts are NOT exempted, so any pre-existing staff account (which would have been
created with a temporary password) is still correctly forced to change. New rows
use the default (true); on an empty database the backfill matches 0 rows.

### Forced first-password-change — completion is NOT done in Step 10.1
Step 10.1 only adds the **state** (`must_change_password`). Clearing it requires a
**trusted** operation, because `profiles` has **no direct UPDATE policy**. A plain
`auth.updateUser({ password })` changes the Supabase Auth password but does **not**
clear the database flag. **Step 10.6** must implement the approved trusted
completion (e.g. a narrow `security definer` RPC callable only by the
authenticated owner for their own row, or an Edge Function) that sets
`must_change_password = false` after a verified first change. **Do not** claim the
forced first-password flow is complete, and **do not** build that operation now —
the exact Step-10.6 mechanism (narrow RPC vs Edge Function, re-auth requirement)
remains to be finalized before implementation.

### Username normalization — ownership
- **Rule (deterministic):** `lower(btrim(username))`, validated `^[a-z0-9._-]{2,50}$`;
  reject blank/malformed; the normalized value is what `profiles.username` stores
  (the Step-2 CHECK + UNIQUE enforce it), so two inputs can never map to one identity.
- **Owner:** the trusted **auth adapter** (Flutter `SupabaseAuthRepository`, for
  login) and the **`admin-create-user` Edge Function** (for creation) each apply
  the SAME rule. The **database enforces** the normalized username via the existing
  CHECK/UNIQUE. **No SQL normalization helper and no public RPC** is added — a
  public RPC that returns or derives internal emails is forbidden.

### Internal Auth email — construction & secrecy
- Constructed as `<normalized_username>@users.sumou.internal` **in the trusted
  contexts only**: the login adapter derives it **locally** (no DB lookup) for
  `signInWithPassword`; the create-user Edge Function builds it for
  `auth.admin.createUser`. It is **never** displayed, **never** written to
  `audit_logs`, and **never** returned by a public RPC.

### Contact email vs internal Auth email — mapping rule
- `auth.users.email` = the hidden internal login identity (`<username>@users.sumou.internal`).
- **`public.profiles` has no `email` column** and Step 10.1 does not add one (the
  internal Auth email must not be duplicated into a public column).
- `UserModel.email` (Flutter) currently has **no backend profile source**. The
  future `SupabaseProfileMapper`/`SupabaseAuthRepository` **must map
  `UserModel.email` to `null`** — it must **never** expose `auth.users.email` as
  `UserModel.email` (that would leak the hidden internal identity into the UI).
- A user's optional public/contact email is **not** persisted server-side and is
  **never** the login identity. Only if a separate public contact-email column is
  explicitly approved later would the mapper source `UserModel.email` from it — a
  distinct decision from the Auth identity, not part of Step 10.1.

### Permission codes
No new permission codes are required or added. User management resolves through
the existing frozen permissions: **`can_manage_users`** (create / reset password /
activate-deactivate / edit profile) and **`can_manage_permissions`** (edit role &
permission assignments). Excluded-domain permission (`can_manage_finance`) stays
inactive/ungranted.

### RLS impact
The existing `profiles` SELECT policies already scope the new column safely: a user
reads only their **own** row (hence their own `must_change_password`), an admin
reads all non-deleted rows for management, and no other ordinary user can read
someone else's profile. **No masking view is needed** (no cross-user column leak),
**no profile UPDATE policy** is added — the flag is flipped only by trusted backend
operations (the create/reset Edge Functions or a later narrow authorized RPC).

### User-lifecycle boundaries (distinct states)
- **Auth account** — an `auth.users` row exists.
- **Profile active** — `profiles.is_active = true AND deleted_at IS NULL`.
- **First-login password state** — `profiles.must_change_password`.
- **Authorization** — active `user_roles` + resolved permissions.
Disabling a profile fails closed immediately in the RLS/RPC helpers (Step 6.1) and
does **not** require deleting `auth.users`; soft-deleted profiles are retained for
history. A deleted/inactive user must not reach usable app access even if Supabase
Auth still accepts the password — the Step-10.5 session loader signs out / blocks
inactive/deleted profiles. No hard-delete of accounts.

### First-admin bootstrap (DEV only)
The single canonical procedure is `docs/qa/FIRST_ADMIN_BOOTSTRAP_DEV.sql` (see §2)
— a manual, one-time, placeholder-only DEV template run in the SQL Editor (DEV
database-owner context): a `DO $$` block with a placeholder-UUID guard, username
normalization/validation, active-admin-role lookup, and `profiles` + `user_roles`
inserted in one transaction with `must_change_password` explicitly chosen and **no**
`user_permissions` inserts. Auth-user creation stays manual in the DEV Dashboard.
No real credentials/project-ref/secrets. **Production bootstrap is a separate,
future release procedure — never run it now.**

---

## 12. Step 10.2 — Admin create-user backend (implemented; DEV-pending)

**Prepared in code; pending owner review, manual DEV apply + deploy.** Not on
Production. Files: `supabase/migrations/20260714220000_admin_create_user_backend.sql`,
`supabase/functions/admin-create-user/index.ts`,
`supabase/functions/_shared/auth-utils.ts` (+ `.test.ts`),
`docs/qa/STEP_10_2_ADMIN_CREATE_USER_DEV_QA.md`.

### RPC signature & grant
```
public.create_staff_profile(
  p_actor_id uuid, p_user_id uuid, p_username text, p_full_name text,
  p_default_role text, p_roles text[], p_photographer_types text[] default '{}',
  p_permission_overrides jsonb default '[]'
) returns jsonb
```
`SECURITY DEFINER`, `search_path=''`, schema-qualified, no dynamic SQL. **EXECUTE
revoked from PUBLIC/anon/authenticated; granted to `service_role` ONLY** (default
privileges are hardened — Step 6.5 — so the grant is explicit). Inputs are stable
**codes** (roles/permissions/photographer types), never UUIDs; it accepts **no**
password/temp-password/internal-email/token/secret/`is_active`/`must_change_password`.

Return `jsonb`: `{ id, username, full_name, default_role, roles[], photographer_types[],
permission_overrides[], is_active:true, must_change_password:true }` — **never** the
internal email, password, hash, token, or service-role data. The temp password is
added only by the Edge Function HTTP response.

### Authorization (defense-in-depth, in BOTH layers)
- **Edge Function** (caller-scoped RLS client): `auth.getUser()` → active profile
  (self policy only returns active/non-deleted) → active **admin** role →
  effective **`can_manage_users`** (user override else OR of active-role defaults).
  It **never** trusts Flutter-supplied roles/permissions for authorization, and
  uses `service_role` only **after** this passes.
- **RPC** (service context, so `auth.uid()` is NOT the admin): re-validates the
  supplied `p_actor_id` itself — active, non-deleted, active admin role, effective
  `can_manage_users` — fail-closed. So authorization does not depend on the Edge
  Function alone.

### Normalization & internal email
`normalizedUsername = username.trim().toLowerCase()`, validated `^[a-z0-9._-]{2,50}$`.
The internal email `<normalizedUsername>@users.sumou.internal` is built **only** in
the Edge Function, never accepted from the client, never returned or logged. The
RPC additionally verifies `auth.users.email` matches the username (never echoing it).

### Temporary password
Generated in the Edge Function with `crypto.getRandomValues` (rejection-sampled, no
`Math.random`): 20 chars from an unambiguous set (no `0/O/1/l/I`) guaranteeing ≥1
lower/upper/digit/symbol. Never stored, never logged, never in `audit_logs`;
returned **once** in the 201 body.

### Atomic profile creation & audit
The RPC does all public writes + the audit row in **one transaction**: `profiles`
(`is_active=true`, `must_change_password=true`), `user_roles` (validated active
roles incl. the default), `user_photographer_types` (active types),
`user_permissions` (**explicit overrides only** — inserts nothing when none;
**never** copies `role_permissions`), and one `audit_logs` row (`actor_id`,
`action='user.create'`, `entity='profiles'`, `entity_id`, `meta` = counts only —
no username/email/password/secret). Any failure rolls back everything.

### Compensation
Auth and public schema cannot share one SQL transaction, so: create the Auth user
→ call the RPC → on RPC failure the Edge Function calls `auth.admin.deleteUser` for
**only** the UUID it just created (never a pre-existing user; a taken username
returns 409 before any Auth create). If cleanup also fails, it returns a generic
provisioning failure and never leaks details.

### Validation & rejections
Inactive roles (`finance`/`wedding_finance`), non-catalog roles (`client_tracking`),
inactive permissions (`can_manage_finance`), duplicate roles/types/overrides,
missing default-in-roles, blank name, and malformed/un-normalized usernames are all
rejected. **No email/notification/password delivery.** **No Production deployment.**
