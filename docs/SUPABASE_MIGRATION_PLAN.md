# Supabase Migration Plan — Sprint 8

**Status:** Planning only. **No Supabase connection, no migrations, no Flutter changes, no packages this sprint.**
**Principle:** migrate **behind the repository interfaces**, one interface at a time, keeping the mock as a fallback until each phase is verified. The UI/providers/models never change.

**Excluded (never migrated):** finance, payments, Rekaz, notifications, FCM, push, reminders. `NotificationRepository` stays empty.

---

## 1. Strategy overview

1. Backend is introduced as **new implementations** of the existing interfaces (`SupabaseAuthRepository`, `SupabaseUserRepository`, `SupabaseProjectRepository`, `SupabaseTrackingRepository`, `SupabasePermissionRepository`).
2. The **only wiring change** is in `lib/core/providers/repository_providers.dart` (swap the concrete class, or override in a `ProviderScope`). Everything above the repository layer is untouched.
3. Swap **incrementally**: a repository can point at Supabase while others still use mocks, so the app stays runnable throughout.
4. Keep mocks in the tree as a **fallback / test double** (widget tests keep using mocks via `UncontrolledProviderScope`).

> The actual DDL + RLS + RPCs (from the schema/RLS drafts) are created in a **separate, explicitly-approved apply-sprint**. This plan sequences that work; it does not perform it.

---

## 2. Phased plan

### Phase 0 — Prerequisites (planning/setup, no app code)
- Create the Supabase project (out-of-repo, owner-driven).
- Store URL + anon key in **environment config** (never hardcoded; matches the security rule). Decide config mechanism (`--dart-define` / env file) — documented, not added this sprint.
- Freeze the schema (schema draft) and RLS (RLS plan) after the §6 open decisions in the core plan are answered.

### Phase 1 — Schema & policies (DB only)
- Apply enums + tables + indexes + constraints (from `SUPABASE_SCHEMA_DRAFT.md`).
- Create helper functions, then RLS policies, then RPCs (from `SUPABASE_RLS_PLAN.md`).
- Run the policy test matrix. **No app involvement yet.**

### Phase 2 — Identity & auth (`AuthRepository` + `profiles`)
- Seed staff accounts (from `MockUsers`) into Auth + `profiles` + `user_roles` + `user_permissions`.
- Implement `SupabaseAuthRepository`: username→login, `currentUser`, `logout`, `changePassword`, **disabled-account block**.
- Swap only the auth provider; keep the rest on mocks. Verify login/role-selection/logout for admin/manager/photographer + disabled user.

### Phase 3 — Read paths (`UserRepository` + `PermissionRepository` reads, `ProjectRepository` reads)
- Implement reads: `getUsers`, `getUserById/ByUsername`, `getPermissions`; `getProjects`, `getProjectById`, `getProjectsForManager/Photographer`, `getCompletedProjects`, `searchProjects`, `filterProjects`, `getClosureRequests`.
- Back reads with the **join views** (`v_projects`, `v_closure_requests`) so denormalized display names (`managerName`, `projectName`, `submittedByName`) resolve in one query.
- Swap read providers; write paths still mock. Verify all list/detail screens render real data.

### Phase 4 — Write paths (`ProjectRepository` writes + `UserRepository` writes)
- Implement via RPCs: `createProject`, `assignTeamRoles`, `updateProjectStage`, `submitClosureRequest`, `approveClosureRequest`, `rejectClosureRequest`, `updateProjectBasics`, `setProjectManager`.
- Implement user writes: `setUserActive`, `updateUserRoles`, `updateUserPermissions`, `createUser`, `updateUser`, `deleteUser` (soft-delete).
- Verify the full manager/admin/photographer flows end-to-end against RLS.

### Phase 5 — Public tracking (`TrackingRepository`)
- Implement `trackBySerial` + `submitReview` via the anon `security definer` RPCs.
- Verify the public client screen shows only approved links and can submit a review.

### Phase 6 — Cutover & cleanup
- All providers point at Supabase. Mocks remain for tests only.
- Remove any temporary dual-wiring. Final regression pass across all roles.
- Confirm no excluded domain leaked in.

---

## 3. Per-method mapping (interface → backend mechanism)

### AuthRepository
| Method | Mechanism |
|---|---|
| `login` | resolve username→email, `signInWithPassword`, then block if `profiles.active=false` |
| `logout` | `signOut` |
| `currentUser` | `auth.uid()` → `v_profile` |
| `changePassword` | re-auth + `updateUser({password})` |

### UserRepository
| Method | Mechanism |
|---|---|
| `getUsers` / `getUserById` / `getUserByUsername` | select `profiles` (+roles/permissions) |
| `setUserActive` | update `profiles.active` |
| `updateUserRoles` | replace `user_roles` (+ set `default_role`) — RPC or txn |
| `updateUserPermissions` | update `user_permissions.features` |
| `createUser` | RPC: create Auth user + `profiles` + roles + permissions |
| `updateUser` | update `profiles` (+roles/photo types) |
| `deleteUser` | soft-delete `profiles.deleted_at` |

### ProjectRepository
| Method | Mechanism |
|---|---|
| `getProjects` / `getProjectById` | select `v_projects` |
| `getProjectsForManager` / `getProjectsForPhotographer` | select filtered by `manager_id` / assignment |
| `getCompletedProjects` / `searchProjects` / `filterProjects` | select with predicates |
| `getClosureRequests` | select `v_closure_requests` |
| `createProject` | **RPC** (project + serial + stages) |
| `assignTeamRoles` | **RPC** (replace team) |
| `updateProjectStage` | **RPC** (cascade) |
| `updateProjectBasics` | update `projects` (basic fields) |
| `setProjectManager` | update `projects.manager_id` |
| `submitClosureRequest` | **RPC** (insert + status flip, one-pending rule) |
| `approveClosureRequest` | **RPC** (approve + complete + stages done) |
| `rejectClosureRequest` | **RPC** (reject + back to active) |

### TrackingRepository / PermissionRepository
| Method | Mechanism |
|---|---|
| `trackBySerial` | anon RPC `track_by_serial` |
| `submitReview` | anon RPC `submit_review` |
| `getAllPermissions` / `getPermissions` / `updatePermissions` | select/update `user_permissions` |

### NotificationRepository
🚫 **Not migrated.** Interface stays empty; no table, RPC, or provider.

---

## 4. Data migration (seed)

- Source of truth today: `MockUsers` (5 accounts) and `MockProjects` (projects + stages + one seeded closure request).
- **IDs:** app uses string ids (`u-manager`, `p-1`, …); DB uses `uuid`. Seed script assigns real UUIDs and keeps a **name/username/serial mapping** so relationships (manager_id, team.user_id, closure.project_id) resolve correctly.
- **Passwords:** the mock `dev-only-1234` is **not** migrated as a real credential — real passwords are set per account at seed time (owner-provided) and never hardcoded.
- **Serials:** preserve existing serial format; enforce uniqueness at insert.

---

## 5. Testing & rollback

- **Per phase:** run the existing widget/unit suite against mocks (unchanged), plus a manual smoke pass of the swapped area against Supabase (dev project).
- **RLS matrix tests** (from the RLS plan) gate Phase 1 before any app swap.
- **Rollback:** because each phase swaps one provider, reverting a phase = pointing that provider back at its mock. No data loss risk to the app (state was already ephemeral).
- Keep a short-lived **feature switch** in `repository_providers.dart` (mock ⇄ supabase) during the transition, removed at Phase 6.

---

## 6. Risks & watch-items

- **Username↔email** mapping must be settled before Phase 2 (see core plan §4).
- **Disabled-account** enforcement needs both a login-time check and RLS (`active` gate) — easy to miss one.
- **Denormalized names** (`managerName`, etc.) must come from views, or reads become N+1.
- **One-pending-closure** rule must be a DB constraint (partial unique index) + RPC guard, not just app logic.
- **Marketing role** decision (core plan §6.1) affects `role_type` enum and availability rules — resolve before freezing the enum.
- **Availability/leave** is still mock (`MockLeave`); a real source is a **later** decision, not part of this migration, and must not pull in notifications/reminders.

---

## 7. What this sprint delivered

The four planning docs only:
`SUPABASE_CORE_PLAN.md` · `SUPABASE_SCHEMA_DRAFT.md` · `SUPABASE_RLS_PLAN.md` · `SUPABASE_MIGRATION_PLAN.md`.

**No Supabase link · no migrations · no Flutter edits · no new packages.** Implementation begins only in a later, explicitly-approved apply-sprint.
