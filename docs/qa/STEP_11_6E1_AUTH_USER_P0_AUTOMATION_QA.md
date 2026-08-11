# Step 11.6E1 — Authentication/User/Admin P0 Automation QA

## Scope and result

Step 11.6E1 selected the 52 P0 requirements in Sections 3–13 of the accepted
Step 11.6D audit that belong to authentication, forced password change,
password policy, and Admin user create/reset. All 52 received direct isolated
automated assertions and moved from C to A. No selected requirement was
skipped, reclassified, or left partial.

Attempted and newly automated IDs:

- `LOGIN-006`–`LOGIN-010`, `LOGIN-016`–`LOGIN-025`
- `FORCED-005`, `FORCED-013`, `FORCED-015`
- `POLICY-006`, `POLICY-010`, `POLICY-012`, `POLICY-013`, `POLICY-019`
- `OWNPWD-004`, `OWNPWD-014`–`OWNPWD-017`
- `USERCREATE-004`–`USERCREATE-020`, `USERCREATE-023`,
  `USERCREATE-024`, `USERCREATE-031`
- `USERRESET-003`, `USERRESET-005`, `USERRESET-007`, `USERRESET-010`

No already-covered row required correction without a new test. No DEV,
device, TestFlight, or real E2E requirement was promoted.

## Direct coverage added

- Login: empty fields, non-oracular wrong credentials, pending-request
  deduplication/loading, recovery, visibility toggle, secret-safe errors, and
  distinct generic handling for network, server, rate-limit, and unexpected
  Auth failures.
- Forced password change: non-recursive routing, validation/server failure flag
  retention, missing lowercase, trailing whitespace, confirmation failures,
  safe error presentation, and controller disposal.
- Admin create/reset: username/name validation and normalization, role/type
  invariants, all four supported photographer types, Finance exclusions,
  pending-request locks with call-count assertions, one-time explanation/copy,
  failure secrecy, non-admin reset denial, cancel-with-zero-calls, and reset
  deduplication.
- Static security: focused auth/password-change source assertions forbid
  password, token/Authorization, and internal-email logging statements.

## Runtime defects fixed

- Login now rejects empty credentials before repository access, ignores a
  second pending submission, supports password visibility, and distinguishes
  confirmed invalid credentials from generic Auth/network/server failure.
- User creation now normalizes and strictly validates usernames, requires a
  photographer type for photographer users, and rejects duplicate pending
  submissions at the handler boundary.

These are approved-behavior hardenings exposed by direct P0 tests. No product
feature, unsupported user operation, backend contract, or authorization rule
was added.

## Files under test

- `test/auth_flow_test.dart`
- `test/change_password_test.dart`
- `test/admin_users_test.dart`
- `test/supabase_auth_repository_test.dart`
- `test/security_invariants_test.dart`

The runtime changes are limited to the auth repository/gateway/controller/login
screen and Admin user form listed in the final Git diff.

## Automated gates

- Baseline: 433 Flutter tests passed; `flutter analyze` had no issues.
- Focused auth/password/Admin tests: passed.
- Final format check: passed (169 files unchanged).
- `git diff --check`: passed.
- `flutter analyze`: no issues.
- Full `flutter test --concurrency=1`: 461 tests passed (28 new tests over the
  433-test baseline).

Coverage after this step:

- A: 213
- B: 13
- C: 117
- Automatable denominator: 343
- Fully automated: 213/343 = 62.1%
- Full-or-partial: 226/343 = 65.9%
- Remaining P0: 18; P1: 98; P2: 1

## Environment and security boundary

All tests use local fakes and explicit provider overrides. No SUMOU-DEV call,
account/data mutation, remote Supabase command, SQL/RLS/RPC/migration/Edge
Function change, service-role use, or Production action occurred. Step 11.6E2,
owner DEV QA, device QA, and TestFlight QA remain pending.
