# Step 10.3 — Admin Reset-Password Backend: DEV QA (manual)

Backend-only. **DEV only**, never Production. **Pending owner apply/deploy** —
this step does not run any remote Supabase command.

## What it is
`admin-reset-password` Edge Function + `record_admin_password_reset` service-only
RPC. An active admin (with `can_manage_users`) resets another user's password to a
one-time temporary one; the target is forced to change it on next login. No email,
notification, or recovery link is sent.

## Request / response
```
POST /functions/v1/admin-reset-password
Authorization: Bearer <caller access token>
Content-Type: application/json

{ "user_id": "<target profile UUID>" }
```
The ONLY accepted field is `user_id`. The actor is taken from the verified JWT.
`username`, internal email, any password, `actor_id`, `is_active`,
`must_change_password`, `roles`, `permissions`, `audit`/`meta` are **rejected**.

Success (**200**):
```json
{ "user": { "id": "<uuid>", "must_change_password": true, "is_active": <bool> },
  "temp_password": "<shown once>" }
```
`temp_password` appears **only** in a fully-successful 200 body. `is_active`
reflects the target's real state (an inactive target is **not** reactivated).

### Status codes
`200` success · `400` invalid input / malformed JSON · `401` unauthenticated /
missing bearer · `403` caller not active-admin or lacks `can_manage_users` · `404`
target missing or soft-deleted · `405` wrong method (`Allow: POST`) · `415` wrong
media type · `413` oversized body · `500` generic reset failure (incl. partial).

## Authorization
- **Edge Function** (caller-scoped RLS client): `auth.getUser()` → active profile
  (self policy only returns active/non-deleted) → active **admin** role →
  effective **`can_manage_users`** via the authenticated `public.has_feature`
  RPC. **Does NOT require `can_manage_permissions`** (a reset assigns no roles or
  permissions). Never reads `role_permissions` directly. Every read fails closed
  (error → 500). `service_role` is built **only after** authorization succeeds.
- **RPC** (service context, `auth.uid()` is NOT the admin): `record_admin_password_reset`
  independently re-checks `p_actor_id` — active, non-deleted, active admin,
  effective `can_manage_users` — fail-closed. Defense in depth.

## Target account rules (frozen)
- **Active target:** allowed.
- **Inactive target:** allowed for administrative recovery, but **not reactivated**
  — the account stays unusable until separately reactivated.
- **Soft-deleted target** (`deleted_at` not null): **rejected** (404).
- Target must have a matching `auth.users` row (guaranteed by the
  `profiles.id → auth.users(id)` FK; the RPC re-checks anyway).
- Never changes roles, photographer types, permissions, username, or full_name.

## Self-reset (frozen)
An admin **may** reset their own password (`actor_id == user_id`). The response
still forces `must_change_password = true`. The caller's **current session may
remain valid until token expiry** — there is **no global session revocation** in
this step (not implemented; would need explicit support + testing).

## Temporary password
Reuses `generateTempPassword` from `_shared/auth-utils.ts`: `crypto.getRandomValues`,
≥16 chars (20), guaranteed lower/upper/digit/symbol, unambiguous charset. **Never
stored, logged, or audited**; returned once; response is `no-store`.

## Operation ordering & partial-failure (no distributed transaction)
Auth and the public schema cannot share one SQL transaction. Order:
1. authorize caller · validate input · **preflight target** (service read: exists +
   not soft-deleted) — all **before** any Auth change.
2. generate temp password.
3. `serviceClient.auth.admin.updateUserById(target, { password })`.
4. `record_admin_password_reset(actor, target)` — sets `must_change_password=true`
   + writes the audit row atomically.
5. return the temp password once.

**If step 3 fails:** the DB RPC is **never called**; return generic `500`; no temp
password. Nothing changed that needs cleanup.

**If step 4 fails after step 3 succeeded (partial failure):** the target's Auth
password was changed but the flag/audit were not recorded. We **do not** expose the
temp password (a non-finalized reset), **do not** attempt to restore the old
password (it is not available), and return a generic `500`. **Recovery:** simply
**reset again** — it is idempotent (new temp password; flag + audit set on success).
The only lingering state is that the target may have `must_change_password` unset
until a successful retry, which the next successful reset (or the create-time
default) corrects.

## Audit
One row per successful reset: `actor_id` = validated admin, `action` =
`'user.password_reset'`, `entity` = `'profiles'`, `entity_id` = target UUID,
`meta` = `{ "self_reset": <bool> }` only. **No** username, internal email,
password, temp password, token, or secret.

## Grant matrix — `record_admin_password_reset(uuid, uuid)`
| role | EXECUTE |
|---|---|
| `service_role` | ✅ granted |
| `public` | ❌ revoked |
| `anon` | ❌ revoked |
| `authenticated` | ❌ revoked |

SECURITY DEFINER, `search_path=''`, schema-qualified, no dynamic SQL, **no direct
write RLS policy** (the flag update is done inside the SECURITY DEFINER RPC).
```sql
-- verify (SQL Editor / psql as DB owner):
select p.proname, p.prosecdef,
       array_to_string(p.proconfig,',')                       as config,
       has_function_privilege('service_role',  p.oid,'EXECUTE') as svc,   -- t
       has_function_privilege('authenticated', p.oid,'EXECUTE') as auth,  -- f
       has_function_privilege('anon',          p.oid,'EXECUTE') as anon,  -- f
       has_function_privilege('public',        p.oid,'EXECUTE') as pub    -- f
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname='record_admin_password_reset';
```

## Local Deno checks — executed 2026-07-23 (deno 2.9.3), all green
```bash
deno fmt --check supabase/functions/admin-reset-password/index.ts \
  supabase/functions/admin-reset-password/index.test.ts \
  supabase/functions/_shared/auth-utils.ts supabase/functions/_shared/auth-utils.test.ts
deno check supabase/functions/admin-reset-password/index.ts
deno test --allow-env supabase/functions/admin-reset-password/index.test.ts \
  supabase/functions/_shared/auth-utils.test.ts
```
Results: `fmt --check` OK; `deno check` OK; `deno test` **64 passed / 0 failed**
across the whole function suite (13 admin-create-user + 24 admin-reset-password +
27 auth-utils). `--allow-env` is needed only so the handler's "malformed JSON"
framing test can read dummy env vars; it builds no network client.

Covered by unit tests: request framing (405/415/401/400 malformed); strict input
allowlist + invalid UUID + forbidden fields; `callerHasFeature` RPC mapping
(true/false/error → fail closed); `authorizeAdminReset` requires admin +
`can_manage_users` and **NOT** `can_manage_permissions`, rejects inactive/non-admin/
unauthenticated, fails closed on profile/user_roles/has_feature errors; `performReset`
ordering (preflight→update→rpc), target missing/soft-deleted → 404 with no Auth
update, preflight error → 500, **Auth-update failure → RPC not called + no temp
password**, **RPC failure after Auth update → 500 + no temp password**, inactive
target proceeds (not reactivated), self-reset allowed, and the temp password / no-
store headers on success.

## Integration cases requiring DEV (owner; after apply + deploy)
Bootstrap or reuse a DEV admin with `can_manage_users`; use a **disposable** DEV
target created via `admin-create-user`. Do **not** paste JWTs/passwords into chat.
| # | Case | Expect |
|---|---|---|
| 1 | active admin (can_manage_users) resets a disposable target | 200 + temp password; `profiles.must_change_password=true`; one `user.password_reset` audit row (meta = self_reset only) |
| 2 | admin **without** `can_manage_users` | 403 (no Auth change) |
| 3 | **non-admin** caller | 403 |
| 4 | **inactive** admin caller | 403 |
| 5 | missing/unknown `user_id` | 404 |
| 6 | **soft-deleted** target | 404 (no Auth change) |
| 7 | **inactive** target | 200; password reset; `is_active` stays false (NOT reactivated) |
| 8 | **self-reset** (admin resets own id) | 200; own `must_change_password=true` |
| 9 | new temp password lets the target log in, then is forced to change it | login works once; forced change on next step (10.4/10.6) |
| — | response/audit/logs never contain internal email, password, or token | verify |

## No delivery / scope
No email, push, FCM, notification, invitation, or recovery link. No finance/
payments/Rekaz. No Flutter changes in this step (contracts read only to preserve
future compatibility). Production untouched. Step 10.4 not started.
