# Step 10.2 — Admin Create-User Backend: DEV QA (manual)

Backend-only. **DEV only**, never Production. The owner applies the migration and
deploys the function manually (this repo runs no remote commands).

## Automated unit tests (no stack needed)
```bash
deno test supabase/functions/_shared/auth-utils.test.ts
```
Covers: username normalization/validation, internal-email construction, temp-password
length/character-classes/charset/uniqueness, forbidden-field rejection, blank name,
default-role-in-roles, duplicate roles/types/overrides, override boolean/code shape.

## One-time setup (owner, DEV)
1. Apply the migration: `20260714220000_admin_create_user_backend.sql` (review then
   `supabase db push`).
2. Bootstrap a first admin: `docs/qa/FIRST_ADMIN_BOOTSTRAP_DEV.sql`.
3. Set function secrets (DEV): `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
   `SUPABASE_SERVICE_ROLE_KEY` (`supabase secrets set …`). **Never commit them.**
4. Deploy the function: `supabase functions deploy admin-create-user`.

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
- Server logs never contain the request body or the temp password.

## Local checks (owner; Deno required — NOT run in this repo's CI env)
```bash
deno fmt --check supabase/functions/admin-create-user/index.ts \
  supabase/functions/_shared/auth-utils.ts supabase/functions/_shared/auth-utils.test.ts
deno check supabase/functions/admin-create-user/index.ts
deno test supabase/functions/_shared/auth-utils.test.ts
```
> Deno was **not available** in the environment that authored this step, so these
> were **not executed** here — run them locally/CI before deploy. Do not assume
> they passed.

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
