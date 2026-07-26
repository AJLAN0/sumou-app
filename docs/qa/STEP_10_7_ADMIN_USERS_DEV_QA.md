# Step 10.7 — Flutter admin users integration: DEV QA

**Scope:** Flutter connects the existing Admin Users UI to the trusted contracts
already present on DEV. No migration or Edge Function was changed. No account was
created or bootstrapped. No Supabase remote command was run. Production and Step
10.8 are untouched.

**Baseline:** `83e5e4f` (Sprint 10 Step 10.6B). DEV currently has no Auth users or
`profiles`, so live manual QA remains **PENDING owner provisioning**.

## Backend contract audit

### Available and used

| Operation | Existing trusted contract | Authorization |
|---|---|---|
| List/load staff | Admin-readable SELECT RLS on `profiles`, `user_roles`, `role_permissions`, `user_permissions`, `photographer_types`, and `user_photographer_types` | active authenticated admin; RLS remains authoritative |
| Create user | `admin-create-user` Edge Function → service-only `create_staff_profile` RPC | active admin + effective `can_manage_users` **and** `can_manage_permissions` |
| Reset password | `admin-reset-password` Edge Function → service-only `record_admin_password_reset` RPC | active admin + effective `can_manage_users`; `can_manage_permissions` is not required |

Create sends exactly:

```json
{
  "username": "<normalized>",
  "full_name": "<trimmed>",
  "default_role": "<code>",
  "roles": ["<code>"],
  "photographer_types": ["<code>"],
  "permission_overrides": [
    { "code": "<permission>", "granted": true }
  ]
}
```

It never sends `email`, internal email, `id`, active/deleted flags, a password, a
token, or any service key. Reset sends exactly `{ "user_id": "<profile uuid>" }`.
The authenticated `SupabaseClient` supplies the caller session.

### Missing and deliberately unsupported in this pass

The identity/access RLS migration gives Flutter **SELECT only** and creates no
write policy for these tables. There is no matching trusted RPC or Edge Function
for:

- activating or deactivating a profile;
- editing name/username/profile data;
- changing default role or role assignments;
- changing user permission overrides;
- changing photographer-type assignments on an existing user;
- soft deletion or permanent deletion.

`SupabaseUserRepository` therefore advertises these operations as unsupported and
throws a safe typed failure if called. The real UI disables profile/status
actions, disables access-control editing, and removes permanent delete. It never
falls back to direct `insert`, `update`, `upsert`, or `delete` table calls.
Mock-backed tests retain their existing editable CRUD behavior.

### Flutter Web constraint already present in the backend

The existing create/reset Edge Functions intentionally reject `OPTIONS` and send
no approved `Access-Control-Allow-Origin` header. A browser may therefore block
their authenticated cross-origin calls during preflight. Mobile targets are not
subject to browser CORS. No CORS policy was invented in this Flutter-only pass;
adding one requires a separately approved backend contract.

## Real repository behavior

The normal provider now uses `SupabaseUserRepository`; tests/previews explicitly
override it with `MockUserRepository`.

Reads are caller-scoped and bulk-load:

1. non-deleted profiles visible through RLS;
2. assigned active staff roles and the default-role relationship;
3. assigned active photographer types;
4. active role permission defaults;
5. active explicit user permission overrides.

Explicit user overrides win (including `false`), otherwise role defaults are
OR-combined across the user's assigned active roles. Unknown/inactive permission
codes never grant. `finance`, `wedding_finance`, `client_tracking`, and
`can_manage_finance` are never exposed or granted.

Parsing is strict and fail-closed: UUIDs, normalized usernames, required strings,
booleans, embedded relations, default-role membership, duplicates, deleted state,
and function success summaries are validated. Query/SDK/network exceptions and
malformed responses become safe Arabic typed failures. No raw Auth/PostgREST/
Function error is retained or displayed. Auth email is never queried and
`UserModel.email` is always null.

An empty `profiles` result returns an empty list without making dependent
assignment/permission queries. The users screen displays:

- title: `لا يوجد مستخدمون`
- message: `لم تتم إضافة مستخدمين بعد`

Loading, retry, filtering, empty, safe error, and submit-lock states remain
available.

## Temporary password lifecycle

Create (`201`) and reset (`200`) responses are accepted only when their exact safe
summary shape is valid. The temporary password is wrapped in a redacted,
UI-scoped `OneTimePassword` holder:

- it is never stored in repository fields, provider state, user-list state, a
  controller, logs, or `UserModel`;
- the dialog displays it once and provides an explicit clipboard copy action;
- the holder's `toString()` is always redacted;
- the holder is cleared in `finally` when the dialog is dismissed, and also if
  the widget disappears before display;
- create/reset success invalidates the users-list provider;
- reset preserves the server result `must_change_password=true`.

Create/reset failures never expose a temporary password. Status mapping is:

| Status | Create | Reset |
|---|---|---|
| `400` | invalid input | invalid input |
| `401` | session expired | session expired |
| `403` | forbidden | forbidden |
| `404` | generic create failure | target not found |
| `409` | username already used | generic reset failure |
| other / thrown / malformed / partial | generic safe create failure | generic safe reset failure |

## UI gates

- Create: active admin UI context + `can_manage_users` +
  `can_manage_permissions`; the server repeats the authoritative checks.
- Reset: active admin UI context + `can_manage_users`; confirmation is required.
- Profile/status/delete: unavailable in the real flow because no trusted backend
  contract exists.
- Roles/permissions: read-only in the real flow because no trusted mutation
  contract exists; a clear Arabic notice explains this.
- Create and role pickers exclude `finance`, `wedding_finance`, and
  `client_tracking`; finance permission is never shown.

## Automated focused QA

Use the actual existing filenames (`admin_users_test.dart` replaces the absent
`users_test.dart`/`user_form_test.dart`; `admin_permissions_test.dart` and
`admin_roles_test.dart` replace the absent `access_control_test.dart`):

```bash
dart format --output=none --set-exit-if-changed lib test

flutter test \
  test/admin_users_test.dart \
  test/admin_permissions_test.dart \
  test/admin_roles_test.dart \
  test/repositories_test.dart \
  test/supabase_user_repository_test.dart
```

Final local result: format **158 files / 0 changed**; focused Flutter tests
**40 passed / 0 failed**.

Coverage includes empty real list, strict parsing, effective permissions, exact
create/reset bodies, success and one-time secret clearing, safe error mapping,
malformed/leaking response rejection, no email/service-role/request-password
fields, list refresh after create/reset, permission gates, unsupported operation
fail-closed behavior, and existing mock compatibility.

## Manual DEV QA — pending

DEV has no Auth users or profiles and this step intentionally creates none. Once
the owner provisions a disposable DEV admin through the approved process:

1. sign in on a mobile target with that username and password;
2. verify the initial users list/empty state;
3. create a disposable user and copy the temporary password once;
4. verify the list refreshes and no internal email appears;
5. confirm password reset, copy the new temporary password once, and verify the
   target is forced through `must_change_password`;
6. verify a caller missing the required permissions receives the safe forbidden
   state;
7. verify status/profile/access/delete controls remain unavailable until their
   trusted backend contracts exist.

Do not paste passwords, JWTs, internal Auth identities, or keys into QA notes or
logs.
