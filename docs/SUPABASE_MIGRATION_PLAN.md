# Supabase Migration Plan — Sprint 8 (Decisions Frozen)

**Status:** Planning only, aligned to `SUPABASE_CORE_PLAN.md` §1. **No Supabase connection, no migrations, no SQL migration files, no Flutter changes, no packages this sprint. Sprint 9 not started.**
**Principle:** migrate **behind the repository interfaces**, one interface at a time, keeping mocks as fallback until each phase is verified. UI/providers/models never change.

**Excluded (never migrated):** finance, payments, Rekaz, notifications, FCM, push, reminders. `NotificationRepository` stays empty.

---

## 1. Strategy

1. New implementations of existing interfaces (`SupabaseAuthRepository`, `SupabaseUserRepository`, `SupabaseProjectRepository`, `SupabaseTrackingRepository`, `SupabasePermissionRepository`).
2. Only wiring change: `lib/core/providers/repository_providers.dart` (swap concrete class or override in a `ProviderScope`).
3. Swap incrementally; the app stays runnable throughout. Mocks remain as test doubles.
4. DDL + RLS + RPCs + the `admin_create_user` Edge Function are created in a **separate approved apply-sprint**; this plan sequences that work.

---

## 2. Phased plan

### Phase 0 — Prerequisites (no app code)
- Create the Supabase project (owner-driven). Put URL + anon key in **environment config** (never hardcoded).
- Confirm the non-blocking items in core plan §6 (leave source stays mock; env mechanism; audit granularity).

### Phase 1 — Schema, seeds & policies (DB only)
- Apply enums + tables + indexes + constraints (`SUPABASE_SCHEMA_DRAFT.md`).
- **Seed lookups:** `roles` (incl. `marketing`, D1), `permissions`, `role_permissions` (role defaults, D5), `photographer_types` (D3).
- Create helper functions → RLS policies → RPCs (`SUPABASE_RLS_PLAN.md`). Run the policy test matrix (incl. soft-delete invisibility + marketing exemption). **No app involvement.**

### Phase 2 — Identity & auth (`AuthRepository` + `profiles`, D2)
- Seed staff (from `MockUsers`) via the `admin_create_user` **Edge Function**: internal email `normalized_username@users.sumou.internal`, no email confirmation, then `profiles` + `user_roles` + `user_permissions` overrides (where they differ from role defaults).
- Implement `SupabaseAuthRepository`: `username → normalize → internal email → signInWithPassword`, then **block `is_active = false`**; `currentUser`, `logout`, `changePassword` (secure internal/admin flow).
- Swap only the auth provider. Verify login/role-selection/logout for admin/manager/photographer/marketing + disabled user. Confirm the internal email is **never shown**.

### Phase 3 — Read paths
- `UserRepository` reads (`getUsers`, `getUserById/ByUsername`), `PermissionRepository` reads, `ProjectRepository` reads (`getProjects`, `getProjectById`, `getProjectsForManager/Photographer`, `getCompletedProjects`, `searchProjects`, `filterProjects`, `getClosureRequests`).
- Back reads with **views** (`v_projects`, `v_closure_requests`, `v_team`) that join display names, aggregate `project_team_members`+`project_team_types` into the app's `ProjectTeamRole` shape (D3), and **pre-filter soft-deleted** rows (D6).
- Swap read providers. Verify all list/detail screens render real data.

### Phase 4 — Write paths
- `ProjectRepository` writes via RPCs: `create_project`, `assign_team_roles` (member + types + availability guard), `update_project_stage`, `submit_closure_request`, `approve_closure_request`, `reject_closure_request`, plus `updateProjectBasics`, `setProjectManager`.
- `UserRepository` writes: `setUserActive`, `updateUserRoles`, `updateUserPermissions` (overrides), `createUser` (→ Edge Function), `updateUser`, `deleteUser` (**soft-delete**, D6). Wire the **"apply role permissions"** action to `apply_role_permissions` (D5).
- Verify full manager/admin/photographer/marketing flows against RLS.

### Phase 5 — Public tracking (`TrackingRepository`, D4)
- Implement `trackBySerial` + `submitReview` via the anon `security definer` RPCs (approved **and** client-visible links only; non-deleted projects).
- Verify the public client screen exposes nothing beyond eligible links + can submit a review.

### Phase 6 — Cutover & cleanup
- All providers point at Supabase; mocks remain for tests. Remove temporary dual-wiring. Regression pass across all roles. Confirm no excluded domain leaked in.

---

## 3. Per-method mapping (interface → backend)

### AuthRepository (D2)
| Method | Mechanism |
|---|---|
| `login` | normalize username → internal email → `signInWithPassword` → block if `is_active=false` |
| `logout` | `signOut` |
| `currentUser` | `auth.uid()` → `v_profile` (roles + effective permissions) |
| `changePassword` | secure internal/admin flow (re-auth + `updateUser({password})`) |

### UserRepository (D5, D6)
| Method | Mechanism |
|---|---|
| `getUsers` / `getUserById` / `getUserByUsername` | select `profiles` (+roles, effective permissions, photographer types) |
| `setUserActive` | update `profiles.is_active` |
| `updateUserRoles` | replace `user_roles` (+ `default_role_id`) — RPC/txn |
| `updateUserPermissions` | upsert `user_permissions` overrides |
| `createUser` | **`admin_create_user` Edge Function** |
| `updateUser` | update `profiles` (+ `user_photographer_types`) |
| `deleteUser` | **soft-delete** (`is_active=false`, `deleted_at`, `deleted_by`) |
| "apply role permissions" | `apply_role_permissions` RPC (copy `role_permissions` → `user_permissions`) |

### ProjectRepository (D3, D4, D6)
| Method | Mechanism |
|---|---|
| `getProjects` / `getProjectById` | select `v_projects` (non-deleted) |
| `getProjectsForManager` / `getProjectsForPhotographer` | filtered by `manager_id` / assignment |
| `getCompletedProjects` / `searchProjects` / `filterProjects` | select with predicates |
| `getClosureRequests` | select `v_closure_requests` |
| `createProject` | **RPC** (project + serial + stages) |
| `assignTeamRoles` | **RPC** (replace `project_team_members` + `project_team_types`; availability guard, marketing exempt) |
| `updateProjectStage` | **RPC** (cascade) |
| `updateProjectBasics` | update `projects` basic fields |
| `setProjectManager` | update `projects.manager_id` |
| `submitClosureRequest` | **RPC** (insert + status flip, one-pending rule) |
| `approveClosureRequest` | **RPC** (approve + complete + stages done) |
| `rejectClosureRequest` | **RPC** (reject + back to active) |
| delivery links | `project_links` writes (approve / set client-visible / soft-delete) |

### TrackingRepository / PermissionRepository
| Method | Mechanism |
|---|---|
| `trackBySerial` | anon RPC `track_by_serial` (approved + client-visible + non-deleted) |
| `submitReview` | anon RPC `submit_review` |
| `getAllPermissions` / `getPermissions` / `updatePermissions` | resolve/upsert normalized permission tables (D5) |

### NotificationRepository
🚫 **Not migrated.** Interface stays empty; no table, RPC, Edge Function, or provider.

---

## 4. Data migration (seed)

- **Lookups first:** `roles` (with `marketing`), `permissions`, `role_permissions` (defaults per `FeaturePermissions.defaultsFor`), `photographer_types`.
- **Accounts:** `MockUsers` → `admin_create_user` (internal emails). Real passwords set at seed time (owner-provided), never hardcoded; the mock `dev-only-1234` is **not** migrated.
- **Projects:** `MockProjects` → projects + `project_team_members`/`project_team_types` + stages + the seeded closure request.
- **IDs:** app string ids (`u-manager`, `p-1`, …) → real `uuid`; keep a username/serial mapping so `manager_id`, `team.user_id`, `closure.project_id` resolve.
- **Permissions:** seed only **overrides** where a user differs from role defaults; everything else resolves from `role_permissions`.

---

## 5. Testing & rollback

- **Per phase:** existing widget/unit suite runs on mocks (unchanged) + a manual smoke pass of the swapped area on a dev Supabase project.
- **Phase 1 gate:** RLS policy matrix (incl. soft-delete invisibility + marketing exemption + tracking exposure) before any app swap.
- **Rollback:** each phase swaps one provider; revert = point it back at its mock. App state was already ephemeral, so no data-loss risk to the app.
- Keep a short-lived **mock ⇄ supabase switch** in `repository_providers.dart` during transition; remove at Phase 6.

---

## 6. Risks & watch-items

- **Team shape (D3):** the read layer must aggregate `project_team_members` + `project_team_types` back into per-(person,type) `ProjectTeamRole` so Flutter models don't change.
- **Permission resolution (D5):** override-then-role-default must be server-enforced (`has_feature`), not re-implemented client-side as the source of truth.
- **Soft-delete (D6):** every read/policy/view must filter `is_active AND deleted_at IS NULL`; easy to miss one.
- **Disabled accounts (D2):** enforce at login **and** in RLS (`is_active`).
- **Internal email (D2):** must never surface in UI or logs.
- **Marketing exemption (D1):** live once the Flutter `RoleType` gains `marketing` (a later Flutter sprint) and the `roles` seed includes it; the availability rule is enforced in `assign_team_roles`.
- **Leave conflicts:** data source stays mock/deferred — must not introduce notifications/reminders.

---

## 7. What this sprint delivered

The four planning docs, now **decision-frozen and consistent**:
`SUPABASE_CORE_PLAN.md` · `SUPABASE_SCHEMA_DRAFT.md` · `SUPABASE_RLS_PLAN.md` · `SUPABASE_MIGRATION_PLAN.md`.

**No Supabase link · no migrations · no SQL files · no Flutter edits · no new packages · Sprint 9 not started.** Implementation begins only in a later, explicitly-approved apply-sprint.

---

## 8. Sprint 10 — Auth integration sequence (added at Step 10.1)

Backend/DB precedes Flutter. Order:
1. **Auth schema readiness** — `profiles.must_change_password` (migration
   `20260714210000_auth_schema_readiness.sql`). *(Step 10.1 — prepared in code;
   pending owner review and manual DEV application.)*
2. Admin **create-user** backend — `admin-create-user` Edge Function +
   `create_staff_profile` `security definer` RPC (migration
   `20260714220000_admin_create_user_backend.sql`; explicit `execute` grant to
   `service_role` only — hardened defaults, Step 6.5). *(Step 10.2 — **APPLIED +
   DEPLOYED to DEV `fnanhaflpsoggfoaqzes` on 2026-07-23**: migration `20260714220000`
   pushed via `supabase db push --linked`; function deployed via
   `supabase functions deploy admin-create-user --project-ref … --use-api` (JWT
   verification left ON). DB-verified: `create_staff_profile` is SECURITY DEFINER,
   `search_path=""`, EXECUTE = service_role only (public/anon/authenticated revoked);
   `has_feature` remains EXECUTE-able by `authenticated`. Production untouched.)*
3. Admin **reset-password** backend — `admin-reset-password` Edge Function +
   `record_admin_password_reset` `security definer` RPC (migration
   `20260714230000_admin_reset_password_backend.sql`; explicit `execute` grant to
   `service_role` only — hardened defaults, Step 6.5). *(Step 10.3 — **APPLIED +
   DEPLOYED to DEV `fnanhaflpsoggfoaqzes` on 2026-07-23.** Reset requires an active
   admin + effective `can_manage_users` (NOT `can_manage_permissions`); caller
   authz via the authenticated `has_feature` RPC; the RPC re-checks the actor.
   Ordering: Auth password update BEFORE the RPC (no distributed txn), with a
   preflight; on RPC-after-Auth failure the temp password is NOT exposed and the
   recovery is an idempotent retry. DB-verified: `record_admin_password_reset` is
   SECURITY DEFINER, `search_path=""`, EXECUTE service_role only; no profiles write
   RLS policy. Local Deno gate green (fmt/check OK, 64 tests); smoke tests pass.
   Production untouched.)*
4. Flutter Supabase **initialization** (add `supabase_flutter`, env wiring).
5. **Username login / session / profile loading** (`SupabaseAuthRepository`;
   sign out / block inactive/deleted profiles).
6. **Forced first password change** (redirect on `must_change_password` + the
   password-update operation).
7. Admin **user-management integration** (wire create/reset/activate/roles).
8. **Auth QA**.

Excluded throughout: finance/payments/Rekaz/notifications/FCM/push/reminders, and
no `role_permissions` are ever copied into `user_permissions`.
