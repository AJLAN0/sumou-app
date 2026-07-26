# Step 10.6A — Own password-change backend: DEV QA (manual)

Backend-only (Edge Function + RPC). **DEV only**, never Production. **Pending owner
apply/deploy** — this step runs no remote Supabase command. Flutter is **not** wired
here (that is Step 10.6B).

## What it is
`change-own-password` Edge Function + `record_own_password_change` service-only RPC.
A signed-in staff user changes **their own** password and clears
`must_change_password`. Any active, non-deleted account may do this — **no admin
role and no feature permission** are required.

## Request / response
```
POST /functions/v1/change-own-password
Authorization: Bearer <caller access token>
Content-Type: application/json

{ "current_password": "…", "new_password": "…" }
```
The ONLY accepted fields are `current_password` and `new_password`. Identity (uid,
username, internal email) is derived server-side from the JWT and is **rejected**
if supplied (`username`, `email`, `internal_email`, `user_id`, `id`, `token`,
`must_change_password`, `actor_id`, …).

Success (**200**): `{ "user": { "id": "<uuid>", "must_change_password": false,
"is_active": true } }` — **no** password, internal email, or token. Every response
carries `Cache-Control: no-store, max-age=0`, `Pragma: no-cache`,
`X-Content-Type-Options: nosniff`.

### Status codes
`200` success · `400` invalid body / weak new password / new == current ·
`401` unauthenticated / missing bearer / **incorrect current password** ·
`403` caller not an active account · `405` wrong method (`Allow: POST`) ·
`413` oversized body · `415` wrong media type · `500` generic change failure.
Only Auth's explicit `invalid_credentials` response maps to the incorrect-current-
password `401`. Thrown SDK/network failures, rate limiting, missing sessions, and
all other Auth errors return a generic `500`.

## New-password policy (server-side)
- 12–72 characters (72 = bcrypt input limit Supabase enforces)
- at least one uppercase, one lowercase, one digit, one symbol
  (symbol = any non-alphanumeric, non-whitespace character)
- no leading or trailing whitespace
- must **differ** from `current_password`

## Flow (Edge Function)
1. POST + exact `application/json` + Bearer required; bounded body read.
2. Strict body allowlist → new-password policy → differ-from-current — **all before
   any network client is built**.
3. Authorize: `auth.getUser()` → the caller's OWN `profiles` self-read (returns a
   row only when active + not soft-deleted) → require `row.id` to equal the
   authenticated uid → normalize and validate username against
   `^[a-z0-9._-]{2,50}$`. Fail-closed before re-auth/service-client creation
   (thrown SDK/read error or malformed identity → generic 500).
4. Derive the hidden internal email in-function; **re-authenticate** the current
   password on an **isolated anon client** (its own in-memory, non-persisted
   session; the caller's live session is untouched — **no sessions revoked**).
5. `serviceClient` built **only now** → `auth.admin.updateUserById(uid, {password})`
   for ONLY the caller → `record_own_password_change(uid)`.
6. Return the safe summary once.

## Ordering & partial-failure (no distributed transaction)
Auth and the public schema are not one transaction; **Auth-update precedes the RPC.**
- **Auth update fails** → the RPC is **not** called; generic `500`; nothing changed.
- **Auth update throws** → the RPC is **not** called; generic `500`; nothing
  changed and no raw error is returned.
- **RPC fails after the Auth update** → generic `500`; the old password is **not**
  restored (it is not available). **Recovery:** retry the change using the **new**
  password as `current_password` — on success the flag + audit are recorded. The
  only lingering state is `must_change_password` possibly still true until a
  successful retry (or an admin reset).
- **RPC throws after the Auth update** → the same generic `500` partial-failure
  behavior and recovery procedure apply.

## Audit
One row per success: `actor_id` = caller, `action` = `'user.password_changed'`,
`entity` = `'profiles'`, `entity_id` = caller, `meta` = `{}`. **No** password,
internal email, token, or secret.

## Grant matrix — `record_own_password_change(uuid)`
| role | EXECUTE |
|---|---|
| `service_role` | ✅ granted |
| `public` / `anon` / `authenticated` | ❌ revoked |

SECURITY DEFINER, `search_path=''`, schema-qualified, no dynamic SQL, **no direct
write RLS policy** (the flag update happens inside the SECURITY DEFINER RPC).
```sql
-- verify (SQL Editor / psql as DB owner):
select p.proname, p.prosecdef,
       array_to_string(p.proconfig,',')                        as config,
       has_function_privilege('service_role',  p.oid,'EXECUTE') as svc,   -- t
       has_function_privilege('authenticated', p.oid,'EXECUTE') as auth,  -- f
       has_function_privilege('anon',          p.oid,'EXECUTE') as anon,  -- f
       has_function_privilege('public',        p.oid,'EXECUTE') as pub    -- f
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname='record_own_password_change';
```

## Local checks — executed 2026-07-26 (deno 2.9.3), all green
```bash
deno fmt --check supabase/functions/change-own-password/index.ts \
  supabase/functions/change-own-password/index.test.ts
deno check supabase/functions/change-own-password/index.ts
deno test --allow-env supabase/functions/change-own-password/index.test.ts
```
Results: `fmt --check` OK; entrypoint `deno check` OK; `deno test`
**30 passed / 0 failed**. Focused hardening coverage includes: thrown `getUser` and
profile queries → safe 500; wrong profile id / malformed normalized username
rejected before re-auth and service-client creation; confirmed wrong current
password → 401; re-auth network/rate-limit/unexpected Auth failures → 500; thrown
`updateUserById` → 500 with RPC skipped; thrown RPC after Auth update → 500 partial
failure; and every error-response assertion verifies JSON + no-store security
headers and absence of the supplied password, internal email, bearer token, and
environment keys. Existing framing, policy, authorization, ordering, and safe
success-summary cases remain covered.

## Integration cases requiring DEV (owner; after apply + deploy)
Use a **disposable** DEV account; do **not** paste passwords/JWTs into chat.
**Status: PENDING owner** — needs real DEV accounts.
| # | Case | Expect |
|---|---|---|
| 1 | valid current + strong new (differs) | 200; `must_change_password=false`; one `user.password_changed` audit row |
| 2 | wrong current password | 401 (no Auth change) |
| 3 | new == current | 400 |
| 4 | weak new (short / missing a class / edge whitespace) | 400 |
| 5 | inactive / soft-deleted caller | 403 |
| 6 | no / invalid JWT | 401 |
| 7 | after success, old password no longer logs in; new password does | verify |
| 8 | response/audit/logs contain no password, internal email, or token | verify |
| 9 | existing other sessions are NOT revoked by the change | verify (documented) |

## Scope
No email/notification/recovery-link. No finance/payments/Rekaz. No admin
create/reset integration. Flutter untouched (Step 10.6B). No forced-change routing
beyond clearing the flag. Production untouched. Step 10.6B / 10.7 not started.
