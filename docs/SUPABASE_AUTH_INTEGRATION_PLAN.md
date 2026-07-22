# Auth Integration Plan — admin-managed accounts & passwords

**Status:** Planning only (docs). No Flutter changes, no packages, no Edge Functions, no remote actions in this doc. Build begins only after approval.
**Frozen anchor:** decision **D2** in `docs/SUPABASE_CORE_PLAN.md` (username login, internal generated auth email, admin creation via secure Edge Function, no email confirmation, secure password flow).
**Guardrail:** nothing here touches finance/payments/Rekaz/notifications/FCM/push/reminders. No email invites/magic links (internal emails are not real inboxes).

**Chosen options:** initial password = **auto-generated temporary** (shown once to the admin); rollout = **plan first, then build**.

---

## 1. The model in one paragraph

Accounts are **password accounts** on an **internal, non-routable email** (`<username>@users.sumou.internal`) that is never shown. The admin **creates a user with an auto-generated temporary password** (via a secure server function), hands it over, the user **logs in with username + temp password**, then **changes their own password**. The `service_role` key lives **only** inside the Edge Function — never in Flutter, never committed.

---

## 2. Bootstrap the first admin (one-time, manual)

There are no users in the DB yet (only the catalog). The first admin can't be created "by an admin", so bootstrap once:

1. Dashboard → **Authentication → Users → Add user**: email `admin@users.sumou.internal`, set a password, tick **Auto Confirm User**. Copy the new user's **UUID**.
2. Dashboard → **SQL Editor**, run (single transaction — satisfies the deferrable default-role FK):

```sql
begin;
insert into public.profiles (id, username, full_name, default_role_id, is_active)
values ('<AUTH_UUID>', 'admin', 'إدارة سمو',
        (select id from public.roles where code = 'admin'), true);
insert into public.user_roles (user_id, role_id)
values ('<AUTH_UUID>', (select id from public.roles where code = 'admin'));
commit;
```

Admin permissions then resolve from `role_permissions` (admin defaults from Step 2). Do this on **DEV** first; repeat on **PROD** when you go live.

---

## 3. Creating users (admin) — `admin-create-user` Edge Function

Runs with **service_role** (an Edge Function secret), so it can create auth users and bypass RLS for the profile insert.

**Input:** `{ username, full_name, default_role, roles[], photo_types[] }` + the caller's JWT (Authorization header).

**Steps:**
1. **Authorize the caller:** verify the JWT → the caller is an **active admin** with `can_manage_users` (checked server-side against `profiles`/`user_roles`/permissions). Reject otherwise.
2. **Normalize + validate** username (`^[a-z0-9._-]{2,50}$`); ensure it's not already taken.
3. **Generate a strong temporary password** (e.g. 16+ random chars).
4. `serviceClient.auth.admin.createUser({ email: '<username>@users.sumou.internal', password: <temp>, email_confirm: true, user_metadata: { username } })` — a **confirmed** account, **no email sent**.
5. **Create the profile atomically** via a `security definer` RPC `create_staff_profile(user_id, username, full_name, default_role, roles[], photo_types[])` that, in ONE transaction, inserts `profiles` (with `must_change_password = true`), `user_roles` (incl. the default role), `user_photographer_types`, and — only when supplied — explicit `user_permissions` **overrides**. It does **NOT** copy `role_permissions` into `user_permissions`; role-default capabilities resolve at read time via `has_feature()`. (Compensation: if this step fails, the function deletes the just-created auth user to avoid an orphaned `auth.users` row.)
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

- **RLS prerequisite:** logging in and loading a profile requires RLS policies that let a user **read their own** `profiles` / `user_roles` / `user_permissions` (+ read the `roles`/`permissions` catalogs). Those are part of **Sprint 9 Step 6**. So this auth step needs **either** Step 6 done first **or** a minimal "self-read" policy subset bundled in.
- The `admin-create-user` path itself works without RLS policies (service_role bypasses RLS), but the **app can't read data back** until the self-read policies exist.
- **Recommendation:** implement the identity/access **self-read RLS policies** (a slice of Step 6) as the first task of the build, then the Edge Function + Flutter auth.

---

## 8. Build checklist (when approved)

1. RLS self-read policies for `profiles`/`user_roles`/`user_permissions`/`roles`/`permissions` (own-row + catalog read). *(migration)*
2. `create_staff_profile` RPC (`security definer`). *(migration)*
3. Edge Function `admin-create-user` (+ optional `admin-reset-password`); `supabase secrets set` for service_role. *(supabase/functions)*
4. Add `supabase_flutter` package; initialize with URL + anon key via `--dart-define-from-file`. *(Flutter)*
5. `SupabaseAuthRepository implements AuthRepository`; wire the "add user" flow to the Edge Function + temp-password dialog; wire `changePassword`. *(Flutter)*
6. Swap `authRepositoryProvider` to Supabase (keep the mock for widget tests). *(Flutter)*
7. Deploy functions + push RPC/policy migrations to DEV; manual end-to-end test; then PROD.

---

## 9. Test plan (DEV)

Bootstrap admin → log in as admin → create a user (get temp password) → log out → log in as the new user with the temp password → change password → log out → log in with the new password. Verify a **deactivated** user (`is_active=false`) is blocked at login. Widget tests continue on the mock auth repo.

---

## 10. Out of scope for this build

No project/team/closure logic, no finance/payments/Rekaz/notifications/FCM/push/reminders, no email-based flows, no self-signup (admin-provisioned only), and `service_role` never leaves the server.

---

## 11. Step 10.1 — Auth schema readiness (implemented)

Migration `supabase/migrations/20260714210000_auth_schema_readiness.sql` (applied
by the owner to DEV). This is the schema-only groundwork before the Edge Functions
and Flutter work — **no** Auth users, Edge Functions, Flutter, RPCs, policies, or
secrets.

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
change-password redirect (Step 10.6). **Backfill (deliberate):** pre-existing
profiles are set to **false** so a manually-bootstrapped admin is not locked into
a forced change once the redirect lands; new rows use the default (true). No
password/token/OTP/secret column was added.

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

### Contact email vs internal Auth email
- `auth.users.email` = the hidden internal identity above.
- **`public.profiles` has no `email` column** and Step 10.1 does not add one (the
  internal Auth email must not be duplicated into a public column). A user's
  optional public/contact email is **not** persisted server-side today and is
  **never** the login identity. If a contact email is wanted later, it is a
  separate, explicitly-approved column — distinct from the Auth identity.

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
See `docs/qa/FIRST_ADMIN_BOOTSTRAP_DEV.sql` — a manual, one-time, placeholder-only
DEV template: create the Auth user in the dashboard with the internal email, then
insert the matching `profiles` + `user_roles` (admin) in one transaction with the
same UUID; `must_change_password` per the bootstrap decision; **no**
`user_permissions` copies; no real credentials committed; verification + cleanup/
recovery included. Never creates a Production administrator.
