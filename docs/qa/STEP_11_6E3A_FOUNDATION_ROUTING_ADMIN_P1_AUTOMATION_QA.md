# Sprint 11 Step 11.6E3A — Foundation, routing, and admin P1 automation QA

## Outcome

Step 11.6E3A assessed exactly **47** accepted P1 candidates from BUILD,
PUBLIC, SESSION, ROLE, and USERS. It added direct local evidence for **44** and
reclassified **3** BUILD checks to the layer that can truthfully verify them.
No candidate was left partial or skipped, and no already-covered candidate was
discovered.

- Newly automated: **44**
- Already covered: **0**
- Partial: **0**
- Reclassified: **3**
- Skipped: **0**
- New tests: **25**
- Focused result: **90 passing** across the six changed focused test files
- Full result: **499 passing** (`flutter test --concurrency=1`)
- Flutter analyze: **no issues found**

## Candidate disposition

Newly automated IDs:

- BUILD-002, BUILD-004, BUILD-006, BUILD-009, BUILD-012, BUILD-017
- PUBLIC-001, PUBLIC-002, PUBLIC-003, PUBLIC-004, PUBLIC-005, PUBLIC-006,
  PUBLIC-010, PUBLIC-011, PUBLIC-012
- SESSION-004, SESSION-005, SESSION-006, SESSION-007, SESSION-008,
  SESSION-009, SESSION-010, SESSION-011, SESSION-016
- ROLE-003, ROLE-004, ROLE-005, ROLE-006, ROLE-007
- USERS-003, USERS-004, USERS-005, USERS-007, USERS-008, USERS-011,
  USERS-012, USERS-013, USERS-014, USERS-015, USERS-016, USERS-017,
  USERS-019, USERS-020, USERS-021

Reclassified IDs:

- BUILD-001: `F TESTFLIGHT_RELEASE_REQUIRED`. A feature branch must not pretend
  to be `main`; the merged release branch/commit is a pre-release check.
- BUILD-003: `E DEVICE_MANUAL_REQUIRED`. `config/dev.json` is intentionally
  ignored owner-machine state and must not make clean checkout/CI tests fail.
- BUILD-005: `D DEV_INTEGRATION_REQUIRED`. A synthetic HTTPS parser test cannot
  prove that the owner's ignored configuration points to the real SUMOU-DEV
  project.

## Direct evidence added

Repository/static tests now prove version and iOS bundle wiring, ignored DEV
configuration, publishable-key-only configuration, generated release defines,
configuration-value logging absence, and consistent iOS deployment targets.

Router/widget tests now prove controlled signed-out restoration, anonymous
tracking transitions without protected-route flashes, public error/UUID
minimization, signed-out deep links, restored single-role homes, multi-role
selection/restoration, logout reachability, and account cache isolation.

Admin-user tests now prove held loading, bounded failure and explicit one-shot
retry, role/default-role display, full-name and username search, all five list
filters, private-field minimization, and strict duplicate-profile rejection at
the real repository boundary.

## Runtime defect and correction

BUILD-017 exposed one existing inconsistency: Xcode and the Podfile declared
iOS 13.0 while `ios/Flutter/AppFrameworkInfo.plist` still declared 12.0. The
smallest correction changes that plist value to 13.0. No other production
runtime behavior changed.

## Files and security boundary

Test files changed:

- `test/repository_invariants_test.dart`
- `test/security_invariants_test.dart`
- `test/router_test.dart`
- `test/session_restoration_test.dart`
- `test/admin_users_test.dart`
- `test/supabase_user_repository_test.dart`

Runtime/config file changed:

- `ios/Flutter/AppFrameworkInfo.plist` — deployment target consistency only

The tests use only obvious synthetic credentials, UUIDs, errors, email, and
token markers. No real password, temporary password, JWT, access/refresh token,
Authorization value, internal email, Supabase secret, or service-role
credential was added or printed.

## Coverage after this step

- Authoritative requirements: **657**
- A Automated: **275**
- B Partially automated: **13**
- C Missing automation: **52**
- D/E/F reclassification changes: **+1 / +1 / +1**
- Automatable denominator: **340**
- Fully automated: **275/340 = 80.9%**
- Full-or-partial: **288/340 = 84.7%**
- Remaining P1: **51**
- Remaining P2: **1**

## Scope confirmation

Step 11.6E3B was not started. No Supabase remote command, DEV mutation,
account/data action, SQL, migration, RLS, RPC, Edge Function, or Production
action occurred. `AGENTS.md` and `docs/engineering/` were untouched. Sprint 11
remains incomplete pending E3B, E3C, E4, owner DEV/RLS QA, and
device/TestFlight QA.
