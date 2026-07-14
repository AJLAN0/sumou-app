# Supabase Core Plan — Sprint 8 (Backend Planning & Contracts)

**Status:** Planning only. **No Supabase connection, no migrations, no Flutter changes, no packages in this sprint.**
**Goal:** understand the current app and lock the backend design before writing any migration.
**Companion docs:** `SUPABASE_SCHEMA_DRAFT.md`, `SUPABASE_RLS_PLAN.md`, `SUPABASE_MIGRATION_PLAN.md`.

---

## 0. Hard guardrails (permanent exclusions)

These are **permanently out of scope** and apply to **every layer** — database, Supabase, tables & migrations, RPC & Edge Functions, repositories, screens & navigation, and **any future sprint**:

🚫 No Finance · 🚫 No Payments · 🚫 No Payment Requests · 🚫 No Finance Reports · 🚫 No Rekaz (config or integration) · 🚫 No Notifications · 🚫 No FCM · 🚫 No Push Notifications · 🚫 No Reminders

**Consequences for the backend design:**
- No `finance_*`, `payments`, `transfers`, `rekaz_*`, `notifications`, `reminders`, or `devices/fcm_tokens` tables.
- No RPC / Edge Functions for finance, payments, Rekaz, or notifications.
- No RLS policies for excluded domains (the tables simply won't exist).
- `NotificationRepository` stays **interface-only with no methods** (as it is today).
- The `finance` / `wedding_finance` roles and the `can_manage_finance` permission flag may exist as **inert labels** for role fidelity, but they get **no tables, no data, and no logic**.

---

## 1. Why the app is backend-ready

The UI never talks to a data source directly. Every screen goes through **Riverpod providers → repository interfaces**, and the current data comes from in-memory `Mock*Repository` classes. Swapping to Supabase means writing new implementations of the same interfaces and changing one wiring file (`lib/core/providers/repository_providers.dart`). The widgets, providers, and models do not change.

**The contract to preserve (interfaces = the backend spec):**

| Interface | Responsibility | Backend note |
|---|---|---|
| `AuthRepository` | login / logout / currentUser / changePassword | Supabase Auth + `profiles` |
| `UserRepository` | staff CRUD, roles, permissions, active flag | `profiles` + `user_permissions` |
| `ProjectRepository` | projects, team, stages, closures | core tables + RPC |
| `TrackingRepository` | public serial lookup + client review | security-definer RPC (anon) |
| `PermissionRepository` | per-user permission record | `user_permissions` |
| `NotificationRepository` | — | 🚫 out of scope, stays empty |

---

## 2. Data domains (in scope)

1. **Identity & access** — staff accounts, roles (multi-role), feature permissions, photo types, active/disabled.
2. **Projects** — core project record, serial, type (field/social/wedding), status lifecycle, dates, notes, manager.
3. **Team assignments** — photographers/roles on a project, photo type(s), optional value/fee (metadata only), assignment date.
4. **Stages** — ordered workflow per project (3-stage vs 7-stage), status (pending/current/done), notes, who advanced it.
5. **Closure requests** — photographer submits; manager approves (completes project) or rejects (returns to active).
6. **Deliverables** — approved deliverable links shown to the client (currently URLs; `report_file_url` is plain text today).
7. **Client tracking & reviews** — public read of a project by secret serial; optional client rating (1–5) + message.

> The **"value/fee"** on a team assignment is **assignment metadata only** — it is **not** a finance record and must never drive payments, transfers, or reports (see guardrails).

---

## 3. Per-role data map

Resolved from `auth.uid()` → `profiles` → `roles[]` + `user_permissions`. (Roles gate navigation; feature flags gate actions.)

| Role | Reads | Writes | Notes |
|---|---|---|---|
| **Admin** | Everything (all users, projects, team, stages, closures, deliverables, reviews) | Users CRUD, roles & permissions, project basics/manager/team/stage oversight | System-wide; not scoped to ownership |
| **Manager** | Own projects (+their team, stages, closures) | Create projects; edit basics; manage team & stage; approve/reject closures on own projects | Scoped by `projects.manager_id = uid` |
| **Photographer** | Projects they're assigned to | Update stage; submit closure request (assigned + permitted) | Scoped by team assignment |
| **Marketing** *(proposed — not in app yet)* | Same domain as social/marketing projects | TBD (assignment-focused) | ⚠️ No `marketing` role in `RoleType` today; see §6 |
| **Public Client** *(anon)* | One project's public status + approved links by **serial only** | Submit a review (rating + message) | Via security-definer RPC; no table access |

**Other roles present in the enum** (`designer`, `attendance`, `personal_photo`, `finance`, `wedding_admin`, `wedding_finance`) are **placeholder roles** for later sprints. Only admin/manager/photographer are fully exercised today. `finance` / `wedding_finance` get **no finance data** (guardrail).

---

## 4. Auth strategy (username-based app → Supabase Auth)

The app authenticates by **username + password**, not email. Recommended mapping:

- Use **Supabase Auth** as the credential store. Because Auth is email-first, map each staff username to a **synthetic email** (e.g. `username@staff.sumou.local`) at account-creation time, OR store a `username` column on `profiles` and resolve `username → email` before `signInWithPassword`.
- A **`profiles`** table (PK = `auth.users.id`) holds `username`, `full_name`, `email?`, `avatar_initials?`, `active`, plus role/permission joins.
- `currentUser()` = `auth.uid()` → `profiles` (+ roles/permissions).
- `changePassword()` = Supabase Auth `updateUser({ password })` after re-auth.
- **Disabled accounts:** `profiles.active = false` must block login. Enforce in a **login RPC / post-login check** (Auth alone won't block a disabled profile) and in RLS (`active` gate on sensitive reads).

**Decision to confirm with the team:** synthetic-email mapping vs. a custom username login RPC. (Documented, not implemented.)

---

## 5. Operations that need RPC / Edge Functions

Anything that is **multi-step / transactional / must run atomically or with elevated rights** should be a Postgres **RPC (`security definer`)** rather than multiple client writes. No Edge Functions are strictly required for the in-scope features (all logic is DB-local); RPCs suffice.

| Operation | Why RPC | Mechanism |
|---|---|---|
| `createProject` | Insert project **+ generate serial + seed stages** atomically | RPC returns the full project |
| `updateProjectStage` | Cascade: earlier→done, target→current, later→pending | RPC (single transaction) |
| `submitClosureRequest` | Insert request **+** flip project → `pendingClosure`, enforce "one pending per project" | RPC |
| `approveClosureRequest` | Mark approved **+** complete project **+** mark all stages done | RPC |
| `rejectClosureRequest` | Mark rejected **+** return project → `active` | RPC |
| `assignTeamRoles` | Replace whole team (delete + re-insert, re-keyed) | RPC |
| Serial allocation | Uniqueness + format ownership (`PREFIX-XXXX-XX`) | RPC / DB default |
| **Public tracking** (`trackBySerial`) | Anon read of **only** approved links for a serial, no table exposure | `security definer` RPC |
| **Client review** (`submitReview`) | Anon insert of rating/message tied to a serial | `security definer` RPC |

Everything else (list/get/search/filter, user reads, permission reads) is plain **table select/insert/update** guarded by RLS.

---

## 6. Open decisions (to confirm before schema is frozen)

1. **Marketing role** — the per-role plan mentions "Marketing", but `RoleType` has **no `marketing` value** today (social projects are labeled "social/marketing"). Options: (a) add a `marketing` role in a later Flutter sprint and to the DB `role_type` enum; (b) treat marketing as the social project domain and skip a dedicated role. **Recommend (a)** if marketing users truly need cross-project same-date assignment (the availability exemption). Until decided, the schema includes `marketing` as a **reserved, unused enum value**.
2. **Photo types** — lookup table vs. free text. Currently free strings on users and team roles. **Recommend** a `photo_types` lookup for consistency, with text kept for legacy.
3. **Deliverables/report files** — today `report_file_url` and delivery links are plain text. Decide whether to adopt **Supabase Storage** for real files, or keep URL text for now. **Recommend** URL text first; Storage later (still no finance/report *generation*).
4. **Username↔email** mapping approach (see §4).
5. **Permissions storage** — normalized boolean columns vs. `features jsonb`. **Recommend `jsonb`** to avoid enumerating (and to naturally exclude finance flags), with a `has_feature()` helper for policies.
6. **Soft-delete** for users/projects vs. hard delete (Users CRUD currently hard-deletes). **Recommend** soft-delete (`deleted_at`) for auditability.

---

## 7. Sprint 8 deliverables (this sprint)

- ✅ `docs/SUPABASE_CORE_PLAN.md` (this file)
- ✅ `docs/SUPABASE_SCHEMA_DRAFT.md` — tables, columns, relations, enums, ERD, model→column mapping
- ✅ `docs/SUPABASE_RLS_PLAN.md` — role resolution, helper functions, RLS matrix
- ✅ `docs/SUPABASE_MIGRATION_PLAN.md` — phased Mock→Supabase transition + per-method mapping

**Not in this sprint:** connecting Supabase, writing/running migrations, editing Flutter, adding packages.
