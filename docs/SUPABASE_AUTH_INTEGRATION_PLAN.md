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
5. **Create the profile atomically** via a `security definer` RPC `create_staff_profile(user_id, username, full_name, default_role, roles[], photo_types[])` that inserts `profiles` + `user_roles` (incl. default) + applies role-default permissions — in one transaction. (If step 5 fails, the function deletes the just-created auth user to avoid an orphan.)
6. **Return `{ user, temp_password }` once** — the app shows the temp password to the admin to hand over. It is **never stored**.

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

**Admin reset (optional) — `admin-reset-password` Edge Function (service_role):**
1. Authorize caller (admin + `can_manage_users`).
2. Generate a new temp password (or accept an admin-provided one).
3. `auth.admin.updateUserById(targetUserId, { password: <temp> })`.
4. Return the temp password **once** for the admin to hand over.

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
