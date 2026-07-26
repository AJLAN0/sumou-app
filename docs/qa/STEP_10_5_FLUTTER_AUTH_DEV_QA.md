# Step 10.5 — Flutter real auth (login / session / profile): DEV QA

Flutter-only wiring of the real Supabase auth path. **No** backend/migration/Edge/
remote changes. Production untouched. Step 10.6 (forced password change) not started.

## What changed
- `authRepositoryProvider` now returns the real **`SupabaseAuthRepository`**
  (`SupabaseAuthRepository(ref.watch(supabaseClientProvider))`) in the normal app.
  Tests/previews explicitly override it with `MockAuthRepository` via
  `mockAuthOverrides()` in `test/test_helpers.dart` — the mock is never selected
  implicitly (no `kDebugMode`, no "under test" detection).
- Real `login`, `logout`, and `currentUser`/session restoration.

## Username → hidden internal email
`normalized = lower(trim(username))`, validated `^[a-z0-9._-]{2,50}$`. The internal
Auth email `<normalized>@users.sumou.internal` is built **only** in
`lib/data/repositories/supabase/auth_identity.dart` — never stored in `UserModel`,
returned in errors, displayed, logged, or in `toString`. An invalid username fails
with `invalidCredentials` **before any network request**.

## Login flow
`signInWithPassword(email: internalEmail, password: password)` (username trimmed;
password passed through untouched, never retained). On success, the caller's OWN
public context is loaded: profile → active roles → active photographer types →
effective permissions → `UserModel`. If context loading fails after sign-in, the
new session is **signed out** (no authenticated user left without a Flutter
profile). Failures map to safe typed reasons — raw GoTrue/Postgres text, policy
names, internal email, and tokens are never exposed; existence of a username is
never revealed.

## Profile mapping
Selected columns only: `id, username, full_name, avatar_initials, is_active,
deleted_at, default_role_id, must_change_password`. Rules: profile `id` must equal
the Auth user id; missing → `profileUnavailable` + sign out; `is_active=false` or
`deleted_at` set → `accountDisabled` + sign out. **`UserModel.email` stays null**
(the Auth email is never read/mapped/displayed). Raw payloads are never logged.

## Roles / default role / marketing
Loads `user_roles` joined to `roles`; only `roles.is_active=true` participate.
- Inactive roles excluded (so inactive `finance`/`wedding_finance` are unusable).
- Unknown **active** role code → fail closed (never silently mapped to manager).
- No active roles → reject + sign out.
- `default_role_id` must resolve to one of the caller's active roles, else reject.
- `client_tracking` is **not** a staff role and is skipped if present.
- New `RoleType.marketing` (`key: marketing`, `تسويق` / `Marketing`). Marketing uses
  the existing fallback shell/home (a minimal nav); no new marketing screens here.

## Photographer types
Loads the caller's own `user_photographer_types` joined to `photographer_types`;
active types only; `UserModel.photoTypes` uses `photographer_types.name_ar`.

## Effective permissions (own-role-scoped)
1. explicit `user_permissions` override wins (including explicit **false**), else
2. OR of `role_permissions` defaults across the caller's **own active role ids**,
3. only **active** permission-catalog rows count, 4. otherwise false.
**CRITICAL:** the `role_permissions` query is scoped by the caller's own active role
ids (an `IN` filter), never by permission code alone — an admin can read ALL
`role_permissions` via oversight RLS, so a code-only query would leak another
role's grant. `FeaturePermissions.defaultsFor` is NOT used for real users. Mapping
is centralized in `AppFeature.fromCode` (13 active operational codes);
`can_manage_finance` (inactive) and any unknown code map to `null` → never grant.

## Session restoration (startup)
`AuthController.initializeSession()` (idempotent): reads the persisted session via
`AuthRepository.currentUser()`. No session → initialized + signed out. Valid session
→ full user loaded. Disabled/deleted/invalid persisted account → the repo signs the
bad session out and the controller resolves to signed-out. An unexpected restore
failure → signed-out with a safe Arabic message. `AuthState.isInitializing`
distinguishes "restoring" from "signed out"; the initial state is **restoring** so
Entry never flashes before restoration.

### Restoration hardening (final Step 10.5 pass)
- **Concurrency:** `initializeSession()` caches and returns the **in-flight**
  future (`_initFuture ??= _restoreSession()`), so a second caller awaits the same
  restoration. Previously a concurrent caller got an already-completed future and
  could route while restoration was still running (risking an Entry flash).
- **Transient vs terminal failure:** a transient failure (network/query) clears the
  cached future so a later call can **retry** — a one-off outage no longer latches
  the app signed-out for its whole lifetime; the persisted session is left intact.
  A terminal `AuthException` (disabled/deleted account) stays settled — the repo
  already cleared the bad session, so the user must log in again.
- **`isInitializing` never goes stale:** `login()` settles it on **every** path
  (success and both failure paths) and marks restoration complete, so a login
  attempt during startup can't leave the router pinned on Splash hiding the error,
  and a late restore can't overwrite the login result.
- **Logout** marks restoration settled too, so returning to Splash cannot re-query
  or resurrect a just-cleared session.
- The declared `AuthFailure.sessionRestoreFailed` is now actually used (the restore
  message goes through the central `_messageFor` mapper instead of a literal).

## Splash / router
Splash waits for BOTH a minimum branding duration AND `initializeSession()` before
routing. The router holds protected/auth routes on Splash while `isInitializing`;
public client-tracking routes stay public. After restore: signed-out → Entry/Login;
authenticated multi-role w/o a selected role → Role Select; authenticated with an
active role → role home. **No `must_change_password` routing** (Step 10.6).

## Logout
Real `client.auth.signOut()` (idempotent). The controller resets state (clears the
user + selected role); the router returns to Entry; no cached `UserModel` remains.

## changePassword (deferred)
`SupabaseAuthRepository.changePassword` throws `passwordChangeUnavailable`
(no `auth.updateUser`, no re-auth, no flag clearing). The controller maps it to
«سيتم تفعيل تغيير كلمة المرور في الخطوة التالية». `MockAuthRepository` keeps its
working change-password behavior for mock-only tests. Real change + forced-change
routing + trusted flag clearing are Step 10.6.

## Automated tests (all pass; no live network)
Run all: `flutter test`. Focused:
```bash
flutter test test/auth_identity_test.dart test/permissions_mapping_test.dart \
  test/supabase_auth_repository_test.dart test/session_restoration_test.dart \
  test/auth_controller_test.dart test/router_test.dart
```
- `auth_identity_test.dart` — normalize/validate + hidden-email construction.
- `permissions_mapping_test.dart` — `AppFeature.code`/`fromCode`, `can_manage_finance`
  excluded, unknown → null; `RoleType.marketing` key/labels.
- `supabase_auth_repository_test.dart` — login/roles/permissions/photo-types/
  restoration/logout/changePassword via a fake `AuthGateway` (`test/fakes/`).
- `session_restoration_test.dart` — `initializeSession` states + idempotency +
  **concurrent callers share the in-flight future**, **transient failure retries**,
  **terminal disabled-account does not retry**, **login settles `isInitializing`
  on success and failure** + logout reset + admin own-role scoping (no leak).
- Existing widget/flow/router tests pass through `mockAuthOverrides()`.

Full suite (2026-07-23, after the hardening pass): **223 passed / 5 failed** — the 5 failures are the
**pre-existing** `assign_photographers_test.dart` (3) + `project_details_test.dart`
(2) UI hit-test issues, unrelated to Step 10.5 (verified identical before this step).

## Manual DEV QA (owner; run `flutter run --dart-define-from-file=config/dev.json`)
Do **not** paste passwords/JWTs/internal email/session values into chat. `config/dev.json`
stays local (gitignored). **Status: PENDING owner** — needs real DEV accounts.
| # | Case | Expect |
|---|---|---|
| 1 | invalid username format (e.g. `a`) | no Auth call; generic error |
| 2 | wrong credentials | generic Arabic error; no leak |
| 3 | valid admin login | admin home |
| 4 | valid manager login (if an account exists) | manager home |
| 5 | app restart | persisted session restored (Splash → home) |
| 6 | logout | session removed; back to Entry |
| 7 | multi-role account | Role Select then chosen role home |
| 8 | profile page | public username/name only; internal email never shown |
| 9 | disabled/deleted account | rejected (signed out) |
| 10 | `must_change_password=true` account | loads and logs in (NOT forced yet) |
