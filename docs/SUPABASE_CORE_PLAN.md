# Supabase Core Plan — Sprint 8 (Backend Planning & Contracts)

**Status:** Planning only — **DECISIONS FROZEN**. No Supabase connection, no migrations, no SQL migration files, no Flutter changes, no packages.
**Goal:** understand the current app and lock the backend design before any migration.
**Companion docs:** `SUPABASE_SCHEMA_DRAFT.md`, `SUPABASE_RLS_PLAN.md`, `SUPABASE_MIGRATION_PLAN.md`.

---

## 0. Hard guardrails (permanent exclusions)

Permanently out of scope at **every layer** — database, Supabase, tables & migrations, RPC & Edge Functions, repositories, documentation, screens & navigation, and **any future sprint**:

🚫 No Finance · 🚫 No Payments · 🚫 No Payment Requests · 🚫 No Finance Reports · 🚫 No Rekaz · 🚫 No Notifications · 🚫 No FCM · 🚫 No Push Notifications · 🚫 No Reminders

**Consequences:** no `finance_*` / `payments` / `transfers` / `rekaz_*` / `notifications` / `reminders` / `devices|fcm_tokens` tables, RPCs, Edge Functions, or RLS. `NotificationRepository` stays interface-only with no methods. `finance` / `wedding_finance` roles and any finance permission are **inert labels only** — no tables, data, or logic.

---

## 1. Backend Decisions — Frozen

The following decisions are **approved and frozen**. All schema/RLS/migration docs conform to them.

### D1 — Marketing role (real, first-class)
- **Decision:** Add **Marketing** as a real supported role, code `marketing`. Do **not** map Marketing to Designer or any other role. Marketing users **may be assigned to overlapping projects**; all other users remain subject to **project-date and leave conflicts**. Role codes live in a **`roles` lookup table**, not a rigid Postgres enum.
- **Reasoning:** Marketing genuinely needs cross-project, same-date assignment (the availability exemption). A lookup table lets us add/adjust roles without an enum migration.
- **Impact:** `roles` lookup replaces the `role_type` enum; `user_roles` FKs to `roles`. RLS `has_role('marketing')` drives the availability exemption in the assignment path. The Flutter `RoleType` must gain a `marketing` value in a **later Flutter sprint** (not this one) for the exemption to go live end-to-end; the currently-inert `isMarketingExempt` hook becomes active then.

### D2 — Username login + internal Supabase Auth email
- **Decision:** Keep **username-based login** in the Flutter UX. Store `username` as a **unique, normalized** field on `profiles` (lowercase, trimmed, validated). Back each account with an **internal generated** Supabase Auth email `normalized_username@users.sumou.internal` that is **never displayed** in the app. **Email confirmation not required** for internal accounts. **Admin user creation** later uses a **secure Edge Function** (service role). **Password reset/change** uses a **secure internal/admin flow**. **Document only — do not implement yet.**
- **Reasoning:** Supabase Auth is email-first; a deterministic internal email preserves the username UX without exposing a fake email, and keeps account creation server-controlled.
- **Impact:** `profiles.username` unique + normalized; auth email is an internal implementation detail on `auth.users`. Adds one Edge Function (`admin_create_user`) and an admin password-reset flow to the plan (see §5). Login resolves `username → internal email → signInWithPassword`, then blocks disabled accounts.

### D3 — Photographer types (normalized, many-to-many)
- **Decision:** Normalized lookup + relations: **`photographer_types`**, **`user_photographer_types`**, **`project_team_types`**. Support **multiple types per user** and **multiple assignment types per project team member**.
- **Reasoning:** Photo types are shared vocabulary and a member can hold several on one project; free-text drifts.
- **Impact:** Replaces the free-text `type` on team rows. The team base row becomes **`project_team_members`** (one per person per project) with types in `project_team_types`. `assignTeamRoles` writes a member + its types. `user_photographer_types` carries a user's skills.

### D4 — Delivery links (URL only, approval + visibility)
- **Decision:** First backend version stores **URL-based delivery links only**, in **`project_links`** with **`is_approved`** and **`is_client_visible`**. **Public tracking exposes only links that are both approved and client-visible.** Supabase **Storage/file uploads are deferred** (not in the initial backend).
- **Reasoning:** Links cover the delivery need now; Storage adds ops surface we don't need yet (and no report *generation* — that's finance-adjacent and excluded).
- **Impact:** Replaces the draft `project_deliverables`. `report_file_url` stays plain text/URL. Tracking RPC filters `is_approved AND is_client_visible`.

### D5 — Permissions (normalized tables, server-enforced)
- **Decision:** Normalized **`permissions`**, **`role_permissions`** (role defaults), **`user_permissions`** (user-specific overrides) — **not** jsonb. Resolution is **server-enforced**. The existing **"apply role permissions"** action later **copies/applies role defaults** safely.
- **Reasoning:** Auditable, queryable, and enforceable in RLS/RPC; overrides layer cleanly on top of role defaults.
- **Impact:** Effective permission = user override if present, else OR of role defaults across the user's roles. `has_feature()` reads these tables. `updateUserPermissions` writes overrides; the "apply role defaults" action is an RPC that copies `role_permissions` → `user_permissions`.

### D6 — Soft delete / deactivation
- **Decision:** Use **soft delete/deactivation** (`is_active`, `deleted_at`, `deleted_by` where relevant), primarily on **`profiles`**, **`projects`**, **`project_links`**. **No hard delete** for operational records. **`project_stages`, `closure_requests`, and audit logs are retained** as operational history.
- **Reasoning:** Preserves history and referential integrity; avoids destructive loss of operational records.
- **Impact:** Every read/RLS SELECT filters out soft-deleted rows. `deleteUser`/project delete become soft-deletes. Stages/closures are never deleted (status changes only).

---

## 2. Why the app is backend-ready

The UI never touches a data source directly: **Riverpod providers → repository interfaces → `Mock*Repository`**. Moving to Supabase means new implementations of the same interfaces and one wiring change (`lib/core/providers/repository_providers.dart`). Widgets, providers, and models are unchanged.

| Interface | Responsibility | Backend home |
|---|---|---|
| `AuthRepository` | login / logout / currentUser / changePassword | Supabase Auth + `profiles` (D2) |
| `UserRepository` | staff CRUD, roles, permissions, active flag | `profiles` + roles/permissions tables (D5, D6) |
| `ProjectRepository` | projects, team, stages, closures | core tables + RPC (D3, D4) |
| `TrackingRepository` | public serial lookup + client review | security-definer RPC (D4) |
| `PermissionRepository` | per-user permission record | `permissions` tables (D5) |
| `NotificationRepository` | — | 🚫 out of scope, stays empty |

---

## 3. Data domains (in scope)

Identity & access (D2, D5) · Roles (D1) · Photographer types (D3) · Projects · Team assignments (metadata-only fee) · Stages · Closure requests · Delivery links (D4) · Client tracking & reviews.

> A team member's **value/fee** is **assignment metadata only** — never a finance record, payment, transfer, or report (guardrail).

---

## 4. Per-role data map

Resolved from `auth.uid()` → `profiles` (active) → `user_roles` → `roles`, plus effective permissions (D5). Roles gate navigation; permissions gate actions.

| Role | Reads | Writes | Notes |
|---|---|---|---|
| **Admin** | Everything | Users CRUD (soft-delete), roles & permissions, project oversight | System-wide |
| **Manager** | Own projects (+team, stages, closures, links) | Create projects; edit basics; team & stage; approve/reject closures on own projects; manage links | `projects.manager_id = uid` |
| **Photographer** | Assigned projects | Update stage; submit closure request (assigned + permitted) | via team assignment |
| **Marketing** | Same project domain; **assignable to overlapping projects** | Assignment-focused (per granted permissions) | **D1** — availability exemption |
| **Public Client** *(anon)* | One project's public status + **approved & client-visible** links, by serial | Submit review (rating + message) | RPC only (D4) |

Placeholder roles (`designer`, `attendance`, `personal_photo`, `wedding_admin`, and inert `finance`/`wedding_finance`) exist in `roles` for fidelity; only admin/manager/photographer (and now marketing) are exercised.

---

## 5. Operations needing RPC / Edge Functions

Multi-step/transactional or privileged operations are Postgres **RPC (`security definer`)**; account creation needs an **Edge Function** (service role).

| Operation | Type | Why |
|---|---|---|
| `create_project` | RPC | project + serial + seed stages, atomic |
| `assign_team_roles` | RPC | replace member(s) + their `project_team_types` atomically; availability guard (D1) |
| `update_project_stage` | RPC | cascade earlier→done / target→current / later→pending |
| `submit_closure_request` | RPC | insert + project → `pending_closure`; one-pending rule |
| `approve_closure_request` | RPC | approve + project `completed` + all stages `done` |
| `reject_closure_request` | RPC | reject + project → `active` |
| `apply_role_permissions` | RPC | copy `role_permissions` → `user_permissions` overrides (D5) |
| `track_by_serial` | RPC (anon, security definer) | public read of approved + client-visible links only (D4, D6) |
| `submit_review` | RPC (anon, security definer) | client rating/message by serial |
| **`admin_create_user`** | **Edge Function** (service role) | create Auth user w/ internal email, no email confirm, set profile/roles/permissions (D2) |
| **admin password reset/change** | **secure internal/admin flow** | server-controlled (D2) — documented only |

---

## 6. Remaining (non-blocking) items to confirm during the apply-sprint

All six core decisions are frozen. Minor items to finalize when implementation starts (none block the schema freeze):
1. **Leave/attendance data source** for the availability rule stays **mock (`MockLeave`) / deferred** — marketing exemption (D1) is real, but leave-conflict data is not part of the initial backend and must not pull in notifications/reminders.
2. **Environment config** mechanism for URL/anon key (`--dart-define` vs env file) — a later Flutter/infra choice; documented, not added.
3. **Audit log** granularity/retention (which mutations to log) — table reserved (D6); scope decided at apply time.

---

## 7. Sprint 8 deliverables

`SUPABASE_CORE_PLAN.md` (this) · `SUPABASE_SCHEMA_DRAFT.md` · `SUPABASE_RLS_PLAN.md` · `SUPABASE_MIGRATION_PLAN.md`. **Not in this sprint:** connecting Supabase, writing/running migrations, editing Flutter, adding packages, or starting Sprint 9.
