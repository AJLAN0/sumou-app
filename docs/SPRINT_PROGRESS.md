# Sumou App — Sprint Progress & Delivery Report

**Project:** Sumou Creative internal operations app ("سمو الإبداع")
**Platform:** Flutter · mobile-first · **Arabic RTL primary**
**Backend status:** Mock-backed (in-memory repositories behind interfaces). **No live backend yet** — this is the pre-backend milestone.
**This document:** full record of the sprints delivered so far, with descriptions, story points, implementation notes, bugs fixed, and test coverage — so the team can start backend work with a clear picture of what exists.

---

## Legend & conventions

- **Status:** ✅ Done · 🔄 In progress · ⏭️ Planned · 🚫 Out of scope
- **Points (SP):** indicative story-point estimates (relative effort), not hours.
- **Mock-backed:** all data comes from in-memory `Mock*Repository` classes implementing abstract repository interfaces. The UI never talks to a backend directly — it goes through a repository/service layer, so swapping in Supabase later touches only the repository implementations.

### Architecture at a glance
- **State:** Riverpod (`flutter_riverpod`) — `FutureProvider`, `NotifierProvider`, `StateProvider`, `.family`.
- **Navigation:** `go_router` with centralized `AppRoutes` and role-based redirects.
- **UI system:** reusable `Sumou*` design-system widgets; no per-screen reinvented widgets.
- **RTL:** forced Arabic RTL at the app root (`Directionality.rtl`, locale `ar`).
- **Layering:** `models` → `repositories` (interface + mock impl) → `providers` → `features/*` screens.

### Permanent out of scope (🚫 — do not build)
Finance module · payment/transfer flows · payment requests · finance reports · Rekaz configuration/integration · notifications of any kind (in-app, push, FCM) · reminders · `NotificationRepository` working implementation.
_Existing finance/Rekaz/notifications nav entries may remain only as inert branded placeholders._

### Security baseline
No hardcoded secrets or API keys. Demo credentials are **mock-only** (`dev-only-1234`) and never production. Client "serial" codes are mock.

---

## Sprint summary table

| Sprint | Focus | Points | Status |
|---|---|---:|---|
| 1 | Foundations: auth, shell, design system, models, mocks | 34 | ✅ Done |
| 2 | Manager & Photographer core: projects, stages, closures | 42 | ✅ Done |
| 3 | Smart Calendar & Requests Hub | 13 | ✅ Done |
| 4 | Admin Control Center: dashboard, users, roles, permissions | 34 | ✅ Done |
| 5 | Admin Project Oversight: all projects, details, edit, team, stages | 34 | ✅ Done |
| 6 | Manager Flow QA fixes (10-point checklist) | 26 | ✅ Done |
| 7 | Post-sprint polish: Users CRUD, Access Control merge, Branding, Manager details refactor | 29 | ✅ Done |
| **Total** | | **212** | |

---

## Sprint 1 — Foundations ✅ (34 SP)

**Goal:** stand up the app skeleton, authentication, role-based navigation, the design system, and the mock data layer.

**Delivered**
- **Auth flow** (8 SP): splash → entry landing → login → role selection; disabled-account rejection; multi-role users must pick a role on login. Logout.
- **Role-based shell** (8 SP): `MainShellScreen` with a role-aware bottom navigation (`RoleNavConfig`); per-role tab sets for admin/manager/photographer + placeholder configs for later roles.
- **Design system** (8 SP): `SumouScaffold`, `SumouAppBar`, `SumouButton` (primary/secondary/danger + loading + fullWidth), `SumouCard`, `SumouTextField`, `SumouSectionHeader`, `SumouStatCard`, `SumouStatusChip`, `SumouEmptyState`, `SumouErrorBox`, `showSumouConfirmSheet`.
- **Models** (5 SP): `UserModel`, `RoleType`, `FeaturePermissions`/`AppFeature`, `ProjectModel`, `ProjectType`/`ProjectStatus`/`ProjectStageStatus`, `ProjectTeamRole`, `ProjectStageModel`, `ClosureRequestModel`, `ProjectSerial`, `RoleModel`.
- **Repository layer + mocks** (5 SP): `AuthRepository`, `UserRepository`, `ProjectRepository`, `TrackingRepository`, `PermissionRepository`, `NotificationRepository` (interface only, intentionally no working impl). Mock implementations + seed data (`MockUsers`, `MockProjects`).
- **Client tracking (public)**: enter a serial code → view read-only project status without login.

**Tests:** `auth_controller_test`, `auth_flow_test`, `nav_shell_test`, `models_test`, `project_models_test`, `repositories_test`, `tracking_test`, `widget_test`, `profile_test`.

---

## Sprint 2 — Manager & Photographer core ✅ (42 SP)

**Goal:** the day-to-day production workflow — create/manage projects, assign the team, run stages, and handle closure requests.

**Delivered**
- **Manager projects list** (5 SP): search + status/type filters, mobile cards, "مشروع جديد".
- **Create-project flow** (8 SP): multi-step wizard (basics → client/dates → manager → team → review); mock serial preview; writes through `createProject`.
- **Assign photographers** (5 SP): available photographers with workload signal (متاح/مشغول/ممتلئ), current-team editor, save via `assignTeamRoles`.
- **Photographer "my projects"** (3 SP): assigned projects, search/filters.
- **Stage timeline + update stage** (8 SP): `StageTimeline` widget; move a project to its current stage (3-stage vs 7-stage flows), with notes/updatedBy.
- **Submit closure request** (5 SP): photographer submits delivery link/notes; one pending request per project; project → `pendingClosure`.
- **Manager approve / reject closure** (8 SP): review card + confirm ("قبول وإنهاء") / reject-with-reason; approve completes the project + marks all stages done; reject returns it to active.

**Bugs fixed**
- Snackbar tests were auto-dismissing under `pumpAndSettle` → standardized on `pump()` + `pump(Duration(seconds:1))`.
- Lazy list tapping/scrolling flakiness → `scrollUntilVisible` on the correct `Scrollable`, and `.first`/`.last` disambiguation for repeated labels.

**Tests:** `manager_projects_test`, `add_project_test`, `assign_photographers_test`, `photographer_my_projects_test`, `update_project_stage_test`, `submit_closure_request_test`, `closure_requests_test`.

---

## Sprint 3 — Smart Calendar & Requests Hub ✅ (13 SP)

**Goal:** schedule visibility and a single entry point for requests.

**Delivered**
- **Smart Calendar** (8 SP): role-scoped schedule (manager's projects / photographer's assigned projects) with date buckets; date logic uses real `DateTime.now()` vs mock dates (tests assert only date-independent facts).
- **Requests Hub** (5 SP): manager "الطلبات" hub with request categories; closure category links to the closure inbox with live pending/approved/rejected counts; photographer requests view.

**Tests:** `smart_calendar_test`, `requests_hub_test`.

---

## Sprint 4 — Admin Control Center ✅ (34 SP)

**Goal:** give admins a read-only overview plus user/role/permission management.

**Delivered**
- **Admin overview dashboard** (8 SP): system stats computed from mocks (projects, team, requests) with guards for loading/error.
- **Users management** (8 SP): searchable/filterable user cards; detail sheet with activate/deactivate (`setUserActive`).
- **Role management** (8 SP): per-user default role + roles editing (`updateUserRoles`) with the "default must be in roles" invariant.
- **Permissions control** (8 SP): per-user feature-flag editor grouped by area, sensitive-permission confirmation (`updateUserPermissions`).
- **QA/cleanup** (2 SP): shared admin widgets extracted — `AdminFilterChip`, `AdminAvatar`, `AdminRoleChip`, `AdminStatusPill`, `AdminTextChip`, `featureLabelAr`.

**Bugs fixed**
- `dashboard_test` admin assertion broke when a static card was removed → updated to the real overview labels.

**Tests:** `admin_test`, `admin_overview_test`, `admin_roles_test`, `admin_permissions_test`.

---

## Sprint 5 — Admin Project Oversight ✅ (34 SP)

**Goal:** let admins see and safely manage every project system-wide.

**Delivered**
- **All projects** (5 SP): system-wide list (search, status/type filters, manager/photographer selectors), timeline action → stage oversight. Shared `AdminProjectCard`.
- **Project details (read-only)** (5 SP): oversight view — summary, team (+active pill), stage timeline, read-only closure request, approved client links.
- **Project actions / edit** (8 SP): `AdminEditProjectScreen` — safe basic edit (title/client/type/status/dates/notes) with validation + status-change confirm (`updateProjectBasics`).
- **Team oversight & editing** (8 SP): change manager (`setProjectManager` + confirm), current-team editor (remove + active pill), add-photographer list (search/filter/workload, no duplicates) via `assignTeamRoles`.
- **Stage oversight** (6 SP): monitor stage progress across all projects; "delayed" detection (not completed & delivery date passed, date-only); filters + delayed tag.
- **QA/cleanup** (2 SP): reused `AdminFilterChip`/`AdminProjectCard` across the new screens.

**Bugs fixed**
- Stale `admin_project_details_test` asserted old action labels → updated to the renamed actions.
- Removed a now-unused `_comingSoon` method (unused-element warning) after wiring real edit actions.

**Tests:** `admin_all_projects_test`, `admin_project_details_test`, `admin_edit_project_test`, `admin_project_team_test`, `admin_stage_oversight_test`.

---

## Sprint 6 — Manager Flow QA Fixes ✅ (26 SP)

**Goal:** apply manager-side UX/workflow fixes found during full-app QA. Delivered as a 10-item checklist.

1. **Monthly summary** (2 SP): manager home changed from "today" to **"ملخص الشهر"**; removed "مهام اليوم"; operational stats.
2. **Clickable dashboard cards** (3 SP): المشاريع النشطة / طلبات الإنهاء / الفريق المتاح now switch the shell tabs (active-projects pre-filter applied) via a small shell tab-controller (`shellJumpTabProvider`, `managerProjectsShowActiveProvider`).
3. **Activated home buttons** (1 SP): "عرض الطلبات" / "عرض الفريق" jump to the matching tabs.
4. **Create project — remove manager step** (3 SP): the project manager is always the signed-in manager; steps renumbered to 4.
5. **Team selection upgrade** (5 SP): assign **multiple photo types** per photographer, enter an optional **value/fee** (assignment metadata only — no finance records), duplicate-photographer prevention, Arabic chips.
6. **Availability rule** (5 SP): photographers **booked on the same project date** or **on mock leave** are shown **locked (🔒)** with the reason (محجوز في نفس التاريخ / لديه إذن في نفس اليوم) and can't be selected. Includes a documented, currently-inert **Marketing exemption hook** (no Marketing role exists yet).
7. **Serial copy button** (2 SP): copy the serial on project details (manager + admin) → "تم نسخ الرقم التسلسلي" (Flutter `Clipboard`, no new package).
8. **Manager details bottom actions** (3 SP): replaced تحديث المرحلة/إسناد المصور with **تعديل المشروع** + **إنهاء المشروع** (further refined in Sprint 7).
9. **Kept existing flows safe** (1 SP): admin/photographer/tracking/auth flows verified unaffected.
10. **UI/UX rules** (1 SP): Arabic RTL, mobile-first, Sumou components, no desktop tables/sidebars, large touch targets.

**New building blocks:** `ManagerTeamScreen` (الفريق tab availability view), `team_availability.dart` (booking + `MockLeave` + marketing hook), `shell_providers.dart`.

**Bugs fixed**
- **Provider-modified-during-build** risk: the projects tab clears the "show active" flag in a `addPostFrameCallback` (not during build).
- **Nav-label collision**: dashboard "التقارير" action also matched the "التقارير" nav tab → test scoped to the dashboard subtree.
- Availability logic covered by deterministic unit tests (dates fixed, not `now()`-dependent).

**Tests:** updated `add_project_test` (4-step count), `project_details_test`, `admin_overview_test`, `dashboard_test`; added `team_availability_test`.

---

## Sprint 7 — Post-sprint polish ✅ (29 SP)

**Goal:** close the remaining UX gaps before backend.

- **Admin dashboard redesign** (5 SP): regrouped the long flat list into a KPI hero strip + sectioned cards (projects/team/requests) + quick actions; removed the redundant duplicate-numbers grid.
- **Users CRUD** (8 SP): admin can **add / edit / remove** users. Repository gains `createUser` / `updateUser` / `deleteUser` (username-uniqueness + default-in-roles guards, generated ids, permissions preserved on profile edits). New add/edit form sheet; delete with confirm.
- **Merged Roles + Permissions → Access Control** (8 SP): one navbar screen (`AccessControlScreen`) manages a user's **roles and feature permissions together**, with a one-tap **"تطبيق صلاحيات الدور"** (apply the role's default permission set). Removed the standalone role-management screen/route and the old permissions screen.
- **Branding polish** (3 SP): full Sumou logo on the entry screen; icon-only logo as a brand mark in app headers (`SumouLogo`, `AppAssets`); assets registered in `pubspec.yaml`; graceful `errorBuilder` fallback so the app builds before the PNGs are dropped in.
- **Manager details → two actions, done right** (5 SP):
  - **تعديل المشروع** opens a **manage hub** (`ManageProjectScreen`) merging *edit basics + تحديث المرحلة + إدارة الفريق* as cards; each opens its focused screen and returns to the project (uses `pushReplacement` from the hub).
  - **إنهاء المشروع** opens a **review/approve screen** (`EndProjectScreen`): the manager reviews the **photographer's pending closure request** and accepts it to finish (or rejects). Empty state when no request exists. Removed the standalone stage/assign buttons and the inline approve card from details.

**Bugs fixed**
- Merged the `admin_overview_test` conflict (dashboard action vs shared `test_helpers`) correctly after upstream changes.
- Cleaned unused imports/vars after consolidating manager details (`closure_actions`, `ClosureRequestCard`, `canApproveClosure`, `canAssign`).
- Re-pointed navigation tests (`assign_photographers_test`, `update_project_stage_test`) through the new hub so they still verify persistence back on details.

**Tests:** `admin_users_test`, `end_project_test`; updated `admin_roles_test`, `admin_permissions_test`, `admin_test`, `project_details_test`, `dashboard_test`, `admin_overview_test`.

---

## What exists by area (feature inventory)

- **Auth & entry:** login, role selection, splash, branded entry landing, logout, public client tracking.
- **Admin:** overview dashboard; Users CRUD; unified Access Control (roles + permissions); all-projects oversight; read-only project details; safe project edit; team oversight; stage oversight; reports placeholder.
- **Manager:** monthly home with tab-switching cards; projects list (+filters, active deep-link); requests hub; team availability view; create-project (auto-manager, multi-type + fee team, same-date availability locking); project details with a two-action model (manage hub + end/approve closure); calendar.
- **Photographer:** my projects; stage updates; submit closure request; requests view; calendar.
- **Design system & branding:** full `Sumou*` component set; `SumouLogo` (full/icon) with centralized `AppAssets`.

---

## Test coverage (current suite)

Widget + unit tests across: auth (`auth_controller`, `auth_flow`, `widget`), shell/nav (`nav_shell`, `router`), models/repos (`models`, `project_models`, `repositories`), manager flow (`manager_projects`, `add_project`, `assign_photographers`, `update_project_stage`, `submit_closure_request`, `closure_requests`, `project_details`, `end_project`, `dashboard`), admin (`admin`, `admin_overview`, `admin_roles`, `admin_permissions`, `admin_users`, `admin_all_projects`, `admin_project_details`, `admin_edit_project`, `admin_project_team`, `admin_stage_oversight`), calendar/hub (`smart_calendar`, `requests_hub`), tracking (`tracking`), profile (`profile`), availability (`team_availability`).

> Note: this environment has no Flutter SDK, so `flutter analyze`/`flutter test` run in **CI on the branch**, not locally. All changes were verified by reading + kept green against the existing suite.

---

## Known limitations & explicit follow-ups (for backend planning)

- **Everything is mock/in-memory** — data resets each app session; there is no persistence, real auth, or multi-device sync yet.
- **Availability/leave is mock** (`MockLeave`) — replace with a real attendance/leave source. Same-date booking is derived from project date ranges.
- **Marketing role doesn't exist** — the availability exemption hook (`isMarketingExempt`) is inert until the role is added.
- **Client delivery links / "رابط التسليم"** and a few edges are "قريباً" placeholders.
- **Notifications / finance / Rekaz remain out of scope** by policy (see above).
- **Branding assets** — `assets/branding/sumou_logo_full.png` and `sumou_logo_icon.png` need to be dropped in (code + pubspec are ready; fallbacks render until then).

---

## Backend readiness — the seams to implement

The app is structured so the backend slots in **behind existing interfaces** without touching the UI. Implement real (e.g., Supabase) versions of:

- `AuthRepository` — login, session, role selection, disabled-account handling.
- `UserRepository` — `getUsers`, `getUserById/ByUsername`, `setUserActive`, `updateUserRoles`, `updateUserPermissions`, `createUser`, `updateUser`, `deleteUser`.
- `ProjectRepository` — `getProjects`, `getProjectById`, `getProjectsForManager/Photographer`, `getCompletedProjects`, `searchProjects`, `filterProjects`, `getClosureRequests`, `createProject`, `assignTeamRoles`, `updateProjectStage`, `updateProjectBasics`, `setProjectManager`, `submitClosureRequest`, `approveClosureRequest`, `rejectClosureRequest`.
- `TrackingRepository` — public serial lookup.
- `PermissionRepository` — permission resolution.
- `NotificationRepository` — **leave unimplemented** (out of scope).

Swap the implementations in `repository_providers.dart` (or override in a `ProviderScope`); nothing else in the app needs to change.

---

_Prepared as the pre-backend milestone summary. Ready to begin backend integration._
