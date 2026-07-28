# Sprint 10 — Auth closure report

**Date:** 2026-07-26

**Branch:** `claude/funny-mendel-te0w4y`

**Reviewed baseline:** `7cbb2e5` (`Implement Sprint 10 admin users integration`)

## Closure decision

| Gate | Status |
|---|---|
| Local automated Auth contracts | **PASS** |
| Full Flutter static analysis | **PASS** |
| Full Flutter test suite | **PASS** |
| Local security/scope scan | **PASS with deployment constraints below** |
| Real DEV end-to-end QA | **BLOCKED / PENDING** |
| Production release | **NOT AUTHORIZED / NOT ATTEMPTED** |

**Automated Sprint 10 closure is GREEN.** Sprint 10 is not yet closed for real
DEV: no Auth user or profile exists, so the required live actor and target flows
cannot be exercised. In addition, the source repair described below must be
redeployed to the DEV `change-own-password` function before its live success path
can be signed off.

No account was created or bootstrapped. No Supabase remote command was run. No
migration was applied, no Edge Function was deployed, and Production was not
touched.

## Automated regression results

### Auth-focused Flutter suite

The focused regression set covered controllers, login/session restoration,
identity normalization, password change and forced routing, permissions,
Supabase configuration/client providers, real Auth/User repositories, and admin
user/role/permission UI.

Result: **172 passed / 0 failed**.

### Auth Edge Function suite

```bash
deno fmt --check \
  supabase/functions/_shared/auth-utils.ts \
  supabase/functions/_shared/auth-utils.test.ts \
  supabase/functions/admin-create-user/index.ts \
  supabase/functions/admin-create-user/index.test.ts \
  supabase/functions/admin-reset-password/index.ts \
  supabase/functions/admin-reset-password/index.test.ts \
  supabase/functions/change-own-password/index.ts \
  supabase/functions/change-own-password/index.test.ts

deno check \
  supabase/functions/admin-create-user/index.ts \
  supabase/functions/admin-reset-password/index.ts \
  supabase/functions/change-own-password/index.ts

deno test --allow-env \
  supabase/functions/_shared/auth-utils.test.ts \
  supabase/functions/admin-create-user/index.test.ts \
  supabase/functions/admin-reset-password/index.test.ts \
  supabase/functions/change-own-password/index.test.ts
```

Results: format **8 files / 0 changed**; type check **3 entrypoints / 0
errors**; tests **94 passed / 0 failed**.

The final changed-function gate was rerun immediately before closure:
`change-own-password` format **2 files / 0 changed**, entrypoint check **0
errors**, and focused tests **30 passed / 0 failed**.

### Full Flutter gates

```bash
flutter analyze
flutter test
```

Results: analyze **No issues found**; full suite **291 passed / 0 failed**.

The first full-suite run exposed seven stale widget drivers:

- two password-screen tests tapped an offscreen mobile submit button;
- three photographer-assignment tests tapped an offscreen project action;
- two project-details tests targeted an action that had already been merged into
  the project-management hub or tapped it offscreen.

The tests now scroll through the actual mobile UI and target the current action
contract. No production project/team behavior was changed.

## Regression found and repaired locally

The initial Deno type check found an undeclared `res` assignment inside
`reauthenticate` in `change-own-password`. In an ES-module runtime this can make
the re-authentication path fail closed as a generic server error after the Auth
call, preventing a successful own-password change.

The local source now scopes the Auth response with `const res` and removes the
unreachable duplicate return. The complete Deno gate passes after the repair.

**DEV remains unchanged.** The owner must review and redeploy the corrected
`change-own-password` source to DEV before live password-change QA. This report
does not claim that the currently active remote function contains the repair.

## Security and scope scan

### Passed checks

- `config/dev.json` and `.env` are ignored and absent from tracked files; only
  placeholder examples are tracked.
- No real Supabase URL, secret key, JWT, temporary password, or account
  credential was found in tracked application source.
- Flutter has no `SUPABASE_SERVICE_ROLE_KEY` value or service-role client.
  Service-role use remains confined to trusted Edge Function/migration
  contracts; Flutter references are guardrail comments only.
- No direct `insert`, `update`, `upsert`, or `delete` call exists in the real
  Supabase Flutter repository layer.
- No application logging call records a password, token, Authorization header,
  internal Auth email, or temporary password.
- Internal Auth email remains derived only in trusted identity/auth contexts and
  is not mapped into `UserModel` or UI.
- Create/reset/change requests use the authenticated Supabase client and the
  frozen allowlisted request bodies.
- Finance and wedding-finance roles and `can_manage_finance` remain inactive or
  fail closed; regression tests explicitly assert that they never grant access.
- No payment, Rekaz, notification, FCM, push, reminder, or Production behavior
  was added.
- Sprint-wide changes outside Auth/Admin Users are test harness adjustments
  needed to override the now-real repositories; the closure fixes to project
  tests are test-only.

### Trusted contracts present

- own-profile/session reads through authenticated RLS;
- admin-readable staff/profile/access SELECT policies;
- `admin-create-user` → `create_staff_profile`;
- `admin-reset-password` → `record_admin_password_reset`;
- `change-own-password` → `record_own_password_change`.

### Missing contracts kept disabled

There is still no trusted RPC or Edge Function for:

- activate/deactivate;
- profile/name/username edit;
- role/default-role mutation;
- user permission override mutation;
- photographer-type mutation on an existing user;
- soft or permanent delete.

Flutter does not replace these missing contracts with direct table writes. The
real UI keeps only those actions disabled; mock-backed tests retain mock CRUD.
These are documented product/backend gaps, not failures of the supported Sprint
10 create/reset/read scope.

## Blocked real DEV cases

DEV currently has no Auth users or `profiles`, and this closure pass deliberately
created none. The following cases remain pending:

| Area | Pending real DEV verification | Blocker |
|---|---|---|
| Login | valid username login, invalid password, safe error, logout | no DEV staff account |
| Restoration | persisted session, token refresh, Splash ordering | no DEV session |
| Forced change | temp-password login, forced route, policy, success flag clear, old/new login | no DEV account; corrected function not redeployed |
| Create user | empty list, permission gates, returned password shown once, refresh | no bootstrapped DEV admin |
| Reset password | confirmation, password shown once, `must_change_password=true`, refresh | no admin and target users |
| Account status | inactive/deleted login rejection | no disposable DEV target; mutation contract absent |
| Authorization | callers missing one or both management permissions | no disposable permission variants |
| Audit/secrecy | Auth/profile/audit state and absence of secrets in remote logs | no live successful operations |
| Partial failure | Auth-update/RPC recovery behavior | requires a controlled DEV failure exercise |

### Flutter Web constraint

The three Auth mutation Edge Functions (`admin-create-user`,
`admin-reset-password`, and `change-own-password`) reject `OPTIONS` and provide no
approved `Access-Control-Allow-Origin` policy. Browser preflight can therefore
block the calls before Flutter receives an application response.

This is not bypassed in Flutter. The owner must either:

1. run the real DEV Auth mutation QA on a mobile target; or
2. separately approve and implement a narrow backend CORS origin contract before
   claiming Flutter Web support.

## Owner actions required for real DEV closure

1. Review the local `change-own-password` re-authentication repair.
2. Redeploy the corrected function commit to DEV through the approved
   owner-controlled process; keep JWT verification enabled.
3. Provision a disposable DEV admin through the approved bootstrap process
   without placing credentials in source, chat, screenshots, or logs.
4. Run the login → create user → temp-password login → forced password change →
   new-password login → admin reset → forced change flow on mobile.
5. Verify permission-denied, inactive/deleted, audit, one-time secret, and
   recovery cases listed above.
6. Record the evidence in the relevant Step 10 QA documents.

Production promotion remains a separate explicitly approved release activity.
