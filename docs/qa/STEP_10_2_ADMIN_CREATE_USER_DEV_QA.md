# Step 10.2 — Admin Create-User Backend: DEV QA (manual)

Backend-only. **DEV only**, never Production.

## DEV rollout status — 2026-07-23 (project `fnanhaflpsoggfoaqzes` / SUMOU-DEV)
- **Migration `20260714220000` APPLIED** — `supabase db push --linked` (dry-run
  first confirmed exactly one pending migration). `migration list --linked` shows
  it in both Local and Remote.
- **Function `admin-create-user` DEPLOYED** — `supabase functions deploy
  admin-create-user --project-ref fnanhaflpsoggfoaqzes --use-api` (Docker absent);
  **JWT verification left ON** (no `--no-verify-jwt`). `functions list` → ACTIVE v1.
- **DB contract verified** (psql, read-only): `create_staff_profile` → SECURITY
  DEFINER, `search_path=""`, EXECUTE = **service_role only** (public/anon/
  authenticated all revoked); `has_feature` → SECURITY DEFINER, `search_path=""`,
  EXECUTE-able by `authenticated` (needed by the caller RPC).
- **Local Deno gate (deno 2.9.3): all green** — `deno fmt --check` OK (after a
  one-time `deno fmt` of the never-formatted function files); `deno check` OK
  (fixed a real TS2345 in `authorizeAdmin`'s embedded-relation typing); `deno test`
  **34 passed / 0 failed** (13 admin-create-user + 21 auth-utils).
- **Unauthenticated / handler smoke tests: PASS** — no-JWT → **401** (platform
  gateway); with a project key: GET/PUT → **405** + `Allow: POST`; `text/plain` →
  **415**; malformed JSON → **400**; valid body + non-user token → **401** at
  `auth.getUser()` (rejected before any service_role/Auth-create work). Every
  response carried `Cache-Control: no-store, max-age=0`, `Pragma: no-cache`,
  `X-Content-Type-Options: nosniff`.
- **PENDING (owner):** authenticated admin create-user QA (HTTP matrix rows with a
  real admin JWT + post-success DB checks) — needs a bootstrapped DEV admin and an
  admin session token; not run here (no JWT/passwords pasted into chat). Production
  untouched. Step 10.3 not started.

> The owner performed the DEV apply/deploy from this machine (linking authorized
> for this task). This repo still runs no Production commands.

## Automated unit tests (no stack needed)
```bash
deno test supabase/functions/
```
Covers (auth-utils.test.ts): username normalization/validation, internal-email
construction, temp-password length/classes/charset/uniqueness, forbidden + unknown
fields, blank name, default-role-in-roles, duplicate roles/types/overrides, override
shape, exact media-type, bounded/multibyte body reader.
Covers (index.test.ts, fake client): `callerHasFeature` maps the authenticated
`has_feature` RPC result (true→granted, any non-true success→denied, RPC error→
fail closed); authorizeAdmin requires BOTH can_manage_users AND can_manage_permissions,
and fails closed on profile / user_roles / has_feature-RPC read errors; 401/403/500
paths. **Effective-permission logic (override precedence, active-role-scoped
defaults, inactive-role/permission exclusion) is NOT computed by the Edge Function
— it lives in `public.has_feature(perm_code)` and is verified by the DB QA below.**

## One-time setup (owner, DEV)
1. Apply the migration: `20260714220000_admin_create_user_backend.sql` (review then
   `supabase db push`).
2. Bootstrap a first admin: `docs/qa/FIRST_ADMIN_BOOTSTRAP_DEV.sql`.
3. Function secrets `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`
   are **auto-injected** into every Edge Function by the platform — no
   `supabase secrets set` needed (confirmed on DEV: the deployed function reaches
   `auth.getUser()` rather than the "server is not configured" 500). Never commit them.
4. Deploy the function: `supabase functions deploy admin-create-user --use-api`
   (add `--project-ref <ref>` when unlinked; Docker not required with `--use-api`).

## RPC assertions (SQL Editor, as the DEV database-owner)
```sql
-- create_staff_profile is service_role-only:
select p.proname,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec,  -- expect f
       has_function_privilege('anon',          p.oid, 'EXECUTE') as anon_exec,  -- expect f
       has_function_privilege('service_role',  p.oid, 'EXECUTE') as svc_exec    -- expect t
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'create_staff_profile';
```

## Caller authorization — `has_feature` correctness (SQL Editor)
The Edge Function authorizes the caller **only** through the authenticated
`public.has_feature(perm_code)` RPC (caller-scoped/RLS client). It never reads
`role_permissions` directly — an active admin can read **all** `role_permissions`
rows via oversight RLS, so a code-only scan would count a grant on an unrelated
role and wrongly authorize. Confirm `has_feature` resolves per-caller (run each as
the signed-in caller, i.e. via the deployed function or a caller-scoped session):

- **Unrelated-role grant does NOT leak.** Grant `can_manage_permissions` as a
  default on a role the caller does **not** hold; the caller keeps only a role
  without it. `select public.has_feature('can_manage_permissions')` → **false**,
  and create-user for that caller → **403**.
- **Inactive-role default does NOT contribute.** A default `true` on an *inactive*
  role the caller holds → `has_feature` → **false**.
- **Explicit `false` user override wins** over a `true` active-role default →
  `has_feature` → **false** → create-user **403**.
- **Both present → allowed.** Caller effectively has both `can_manage_users` and
  `can_manage_permissions` → each `has_feature` → **true** → create-user proceeds.
- **Role defaults are never copied into `user_permissions`** on create (see the
  post-success check): the new user's `user_permissions` holds only the explicit
  overrides that were supplied.

## HTTP matrix (call the deployed function; `<JWT>` = a signed-in user's access token)
| # | Request | Expect |
|---|---|---|
| 1 | `GET` | 405 |
| 2 | `POST`, no `Authorization` | 401 |
| 3 | `POST`, `Content-Type: text/plain` | 415 |
| 4 | `POST`, admin JWT, body `{` (malformed) | 400 |
| 5 | `POST`, admin JWT, body with `password`/`email`/`user_id`/`is_active`/`must_change_password` | 400 (forbidden field) |
| 6 | `POST`, admin JWT, `username:"A"` | 400 (username regex) |
| 7 | `POST`, admin JWT, blank `full_name` | 400 |
| 8 | `POST`, admin JWT, `default_role` not in `roles` | 400 |
| 9 | `POST`, admin JWT, duplicate `roles` / `photographer_types` / `permission_overrides` | 400 |
| 10 | `POST`, **non-admin** JWT, valid body | 403 (no Auth user created) |
| 11 | `POST`, **disabled admin** JWT | 403 |
| 11a | `POST`, admin JWT with BOTH `can_manage_users`+`can_manage_permissions` | proceeds (→ 201 on valid body) |
| 11b | `POST`, admin missing `can_manage_users` | 403 (no Auth user created) |
| 11c | `POST`, admin missing `can_manage_permissions` | 403 (no Auth user created) |
| 11d | `POST`, admin with an explicit `false` override for either permission | 403 |
| 12 | `POST`, admin JWT, `roles:["finance"]` or `["client_tracking"]` | provisioning_failed → 400 (RPC rejects inactive/unknown role); **Auth user compensated/deleted** |
| 13 | `POST`, admin JWT, `permission_overrides:[{code:"can_manage_finance",granted:true}]` | 400 (inactive permission); compensated |
| 14 | `POST`, admin JWT, valid `{username,full_name,default_role,roles,photographer_types,permission_overrides}` | **201** `{ user:{…, is_active:true, must_change_password:true}, temp_password:"…"}` |
| 15 | repeat #14 same username | 409 (conflict) |

## Post-success DB checks (SQL Editor)
```sql
-- profiles: is_active=t, must_change_password=t; user_roles include the default;
-- user_photographer_types match; user_permissions hold ONLY the supplied overrides.
select is_active, must_change_password from public.profiles where username = '<u>';
select r.code from public.user_roles ur join public.roles r on r.id=ur.role_id
  where ur.user_id = (select id from public.profiles where username='<u>');
-- MUST be empty unless overrides were explicitly supplied (no role-default copies):
select pm.code, up.granted from public.user_permissions up
  join public.permissions pm on pm.id = up.permission_id
  where up.user_id = (select id from public.profiles where username='<u>');
-- audit: one user.create row, meta = counts only (no username/email/password).
select actor_id, action, entity, meta from public.audit_logs
  where action='user.create' order by created_at desc limit 1;
```

## Must-verify security properties
- Response and all error bodies contain **no** internal email, password hash,
  token, or service-role data. `temp_password` appears **only** in the 201 body.
- `must_change_password` is **true** for every created user; `is_active` is **true**.
- No `role_permissions` are materialized into `user_permissions` (check #post + #14).
- Compensation (#12/#13) deletes **only** the Auth user created by that request —
  a pre-existing user with the same username is never deleted (guarded by the
  friendly pre-check + unique constraint → 409 before any Auth create).
- Server logs never contain the request body, username, internal email, or temp password.
- **Create requires BOTH `can_manage_users` AND `can_manage_permissions`.** The
  Edge Function resolves each through the authenticated `public.has_feature(perm_code)`
  RPC on the caller-scoped client — it does **not** compute permissions by reading
  `role_permissions`/`user_permissions` directly. The `create_staff_profile` RPC
  then **independently** re-checks the actor (`p_actor_id`) with actor-scoped SQL,
  because in the service-role context `auth.uid()` is not the admin. An explicit
  `false` override for either permission, or an inactive permission-catalog row,
  denies. Any authorization read error (auth.getUser / profile / user_roles /
  has_feature RPC / username pre-check) fails closed (500), never treated as empty.
- role defaults are never copied into `user_permissions` (post-success check).

## Local checks (Deno)
```bash
deno fmt --check supabase/functions/admin-create-user/index.ts \
  supabase/functions/admin-create-user/index.test.ts \
  supabase/functions/_shared/auth-utils.ts supabase/functions/_shared/auth-utils.test.ts
deno check supabase/functions/admin-create-user/index.ts
deno test supabase/functions/admin-create-user/index.test.ts \
  supabase/functions/_shared/auth-utils.test.ts
```
> **Executed 2026-07-23 with deno 2.9.3 — all green.** `fmt --check` OK (after a
> one-time `deno fmt` of the function files, which had never been Deno-formatted);
> `deno check` OK (it surfaced and we fixed a real TS2345 where `authorizeAdmin`
> read the embedded `user_roles→roles` relation as an object although postgrest-js
> types it as an array); `deno test` **34 passed / 0 failed**.

## Response-header assertions (every response)
`Content-Type: application/json`, `Cache-Control: no-store, max-age=0`,
`Pragma: no-cache`, `X-Content-Type-Options: nosniff`; a 405 additionally carries
`Allow: POST`. The 201 body (with `temp_password`) must be uncacheable.

## Framing/allowlist assertions
- `Content-Type` must be exactly `application/json` (params ok); `text/plain,
  application/json` → 415.
- Oversized body → 413 **without** parsing (bounded streaming read; byte-counted,
  multibyte-safe; a lying/absent `Content-Length` is still capped).
- Any unknown top-level key (incl. case variants like `Password`, `IS_ACTIVE`) →
  400; any extra key inside a `permission_overrides` object → 400.
