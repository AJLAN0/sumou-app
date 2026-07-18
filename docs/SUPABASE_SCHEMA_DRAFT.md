# Supabase Schema Draft — Sprint 8 (Decisions Frozen)

**Status:** DRAFT for review, aligned to the **frozen decisions** in `SUPABASE_CORE_PLAN.md` §1. **Not a migration.** DDL is illustrative reference only; real migrations happen in a later approved apply-sprint.

**Excluded (no tables/columns):** finance, payments, payment requests, finance reports, Rekaz, notifications, FCM, push, reminders.

**Frozen-decision anchors:** roles as lookup (D1) · username + internal auth email (D2) · normalized photographer types (D3) · `project_links` with approval + client visibility (D4) · normalized permissions (D5) · soft-delete on profiles/projects/project_links (D6).

---

## 1. Enums (kept as Postgres enums — stable domains)

```sql
-- DRAFT. Roles are NOT an enum (see D1 → roles lookup table).
create type project_type   as enum ('field','social','wedding');
create type project_status as enum (
  'active','in_progress','pending_closure','completed','delivered','approved','rejected'
);
create type stage_status   as enum ('pending','current','done');
create type closure_status as enum ('pending','approved','rejected');
```

---

## 2. Identity, roles & permissions

### 2.1 `roles` (lookup — D1)
| Column | Type | Notes |
|---|---|---|
| `id` | `uuid` PK | |
| `code` | `text` unique not null | `admin`,`manager`,`photographer`,`marketing`,`designer`,`wedding_admin`,`attendance`,`personal_photo`,`finance`*,`wedding_finance`* |
| `name_ar` | `text` not null | display label |
| `is_active` | `boolean` default true | |

\* `finance`/`wedding_finance` are **inert labels** — no finance data/logic (guardrail).

### 2.2 `profiles` (staff identity — D2, D6)
PK links 1:1 to `auth.users`.

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid` PK → `auth.users(id)` | |
| `username` | `text` unique not null | **normalized: lowercase, trimmed, validated** |
| `full_name` | `text` not null | |
| `default_role_id` | `uuid` → `roles(id)` not null | routing role |
| `avatar_initials` | `text` null | computed client-side today |
| `is_active` | `boolean` not null default true | disabled = cannot log in |
| `created_at` / `updated_at` | `timestamptz` default now() | |
| `deleted_at` | `timestamptz` null | soft delete (D6) |
| `deleted_by` | `uuid` null → `profiles(id)` | who deactivated |

> The **internal auth email** (`normalized_username@users.sumou.internal`) lives on `auth.users.email`. It is an implementation detail — **never displayed**; the app only shows `username`. `username` unique constraint should be enforced case-insensitively (store normalized).

### 2.3 `user_roles` (multi-role join — D1)
| Column | Type | Notes |
|---|---|---|
| `user_id` | `uuid` → `profiles(id)` | |
| `role_id` | `uuid` → `roles(id)` | |
| PK | (`user_id`,`role_id`) | `default_role_id` must be among these |

### 2.4 `permissions` (lookup — D5)
| Column | Type | Notes |
|---|---|---|
| `id` | `uuid` PK | |
| `code` | `text` unique not null | mirrors `AppFeature` |
| `name_ar` | `text` | |
| `is_active` | `boolean` not null default true | inactive = inert reserved placeholder, never granted |

> Active/grantable codes: `can_add_project`, `can_edit_project`, `can_assign_photographers`, `can_request_photographer`, `can_request_design`, `can_update_stages`, `can_request_closure`, `can_approve_closure`, `can_manage_users`, `can_manage_permissions`, `can_view_reports`, `can_manage_attendance`, `can_manage_wedding_projects`.
> **Inert reserved (is_active=false, never granted/assigned):** `can_manage_finance` — kept as a legacy placeholder for future compatibility; finance remains permanently out of scope functionally.

### 2.5 `role_permissions` (role defaults — D5)
| Column | Type | Notes |
|---|---|---|
| `role_id` | `uuid` → `roles(id)` | |
| `permission_id` | `uuid` → `permissions(id)` | |
| `granted` | `boolean` not null default true | default for the role |
| PK | (`role_id`,`permission_id`) | |

### 2.6 `user_permissions` (user overrides — D5)
| Column | Type | Notes |
|---|---|---|
| `user_id` | `uuid` → `profiles(id)` | |
| `permission_id` | `uuid` → `permissions(id)` | |
| `granted` | `boolean` not null | explicit override (true/false) |
| PK | (`user_id`,`permission_id`) | absence = fall back to role default |

**Resolution (server-enforced):** `effective(user, perm) = user_permissions.granted` if a row exists, **else** `OR` of `role_permissions.granted` across the user's roles (default `false`).

---

## 3. Photographer types (D3)

### 3.1 `photographer_types` (lookup)
| Column | Type | Notes |
|---|---|---|
| `id` | `uuid` PK | |
| `code` | `text` unique | stable key (`photo`,`video`,`instagram`,`design`) |
| `name_ar` | `text` unique | «مصور فوتوغرافي», «مصور فيديو», «انستقرام», «تصميم» |
| `is_active` | `boolean` default true | |

Seeded reference values (Step 3): `photo`→«مصور فوتوغرافي», `video`→«مصور فيديو», `instagram`→«انستقرام», `design`→«تصميم».

### 3.2 `user_photographer_types` (a user's skills — many-to-many)
| Column | Type | Notes |
|---|---|---|
| `user_id` | `uuid` → `profiles(id)` | on delete cascade |
| `photographer_type_id` | `uuid` → `photographer_types(id)` | on delete restrict |
| PK | (`user_id`,`photographer_type_id`) | prevents duplicates |

### 3.3 `user_unavailability` (leave / permission periods)
Backs the availability rule (replaces the mock `MockLeave`). Retained history — cancel via `is_active=false`, never hard-delete. **No notifications/reminders.**

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid` PK | |
| `user_id` | `uuid` → `profiles(id)` | on delete cascade |
| `starts_at` | `timestamptz` not null | period start |
| `ends_at` | `timestamptz` not null | check `ends_at >= starts_at` |
| `kind` | `text` null | reason/type (e.g. leave/permission; free-form for now) |
| `notes` | `text` null | |
| `is_active` | `boolean` not null default true | false = cancelled (history kept) |
| `created_by` | `uuid` → `profiles(id)` | on delete set null |
| `created_at` / `updated_at` | `timestamptz` default now() | `updated_at` via `set_updated_at` trigger |

Index: `(user_id, starts_at, ends_at) where is_active` — supports "is user X unavailable overlapping date D" checks.

---

## 4. Projects & work

### 4.1 `projects` (D6)
| Column | Type | Notes |
|---|---|---|
| `id` | `uuid` PK | |
| `serial` | `text` unique not null | `PREFIX-XXXX-XX` (FLD/SOC/WED) |
| `name` | `text` not null | |
| `client_name` | `text` not null | |
| `manager_id` | `uuid` → `profiles(id)` | owner |
| `type` | `project_type` not null | |
| `status` | `project_status` not null default 'active' | |
| `start_date` | `date` not null | |
| `end_date` | `date` not null | check `end_date >= start_date` |
| `notes` | `text` null | |
| `is_active` | `boolean` not null default true | |
| `created_at` / `updated_at` | `timestamptz` default now() | |
| `deleted_at` / `deleted_by` | `timestamptz` / `uuid` null | soft delete (D6) |

Indexes: `serial` unique, `manager_id`, `status`, `type`, `(start_date,end_date)`, partial `where deleted_at is null`.
`manager_name` (model display field) is **derived** via a join/view, not stored.

### 4.2 `project_team_members` (one row per person per project — D3)
_(base team row; renamed from the earlier `project_team_roles` — types now normalized)_

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid` PK | |
| `project_id` | `uuid` → `projects(id)` on delete cascade | |
| `user_id` | `uuid` null → `profiles(id)` | null = external person |
| `person_name` | `text` not null | |
| `value` | `numeric default 0` | **assignment metadata only — not finance** |
| `date` | `date` null | assignment/shoot date (availability) |

Indexes: `project_id`, `user_id`, `date`. Unique (`project_id`,`user_id`) where `user_id is not null` (no duplicate photographer per project).

### 4.3 `project_team_types` (types per team member — D3)
| Column | Type | Notes |
|---|---|---|
| `id` | `uuid` PK | |
| `team_member_id` | `uuid` → `project_team_members(id)` on delete cascade | |
| `photographer_type_id` | `uuid` → `photographer_types(id)` | |
| PK-ish | unique (`team_member_id`,`photographer_type_id`) | multiple types per member |

### 4.4 `project_stages` (retained history — no soft delete)
| Column | Type | Notes |
|---|---|---|
| `id` | `uuid` PK | |
| `project_id` | `uuid` → `projects(id)` on delete cascade | |
| `title` | `text` not null | |
| `order` | `int` not null | unique (`project_id`,`order`) |
| `status` | `stage_status` not null default 'pending' | |
| `notes` | `text` null | |
| `updated_by` | `uuid` null → `profiles(id)` | |
| `updated_at` | `timestamptz` null | |

### 4.5 `closure_requests` (retained history — no soft delete)
| Column | Type | Notes |
|---|---|---|
| `id` | `uuid` PK | |
| `project_id` | `uuid` → `projects(id)` on delete cascade | |
| `submitted_by` | `uuid` → `profiles(id)` | photographer |
| `created_at` | `timestamptz` default now() | |
| `delivery_link` | `text` null | URL |
| `report_file_url` | `text` null | URL/text (Storage deferred, D4) |
| `notes` | `text` null | |
| `status` | `closure_status` not null default 'pending' | |
| `reject_reason` | `text` null | |
| `reviewed_at` | `timestamptz` null | |

Partial unique: **one pending per project** → `unique (project_id) where status='pending'`.
`project_name` / `submitted_by_name` (model display) are **derived** via join/view.

### 4.6 `project_links` (delivery links — D4, D6)
_(replaces the earlier `project_deliverables`)_

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid` PK | |
| `project_id` | `uuid` → `projects(id)` on delete cascade | |
| `label` | `text` not null | |
| `url` | `text` not null | URL only (no Storage yet) |
| `is_approved` | `boolean` not null default false | |
| `is_client_visible` | `boolean` not null default false | |
| `is_active` | `boolean` not null default true | soft delete (D6) |
| `created_at` | `timestamptz` default now() | |
| `deleted_at` / `deleted_by` | `timestamptz` / `uuid` null | |

Public exposure requires **`is_approved AND is_client_visible AND is_active AND deleted_at is null`**. Index: `(project_id) where is_approved and is_client_visible`.

### 4.7 `client_reviews` (retained history)
| Column | Type | Notes |
|---|---|---|
| `id` | `uuid` PK | |
| `project_id` | `uuid` → `projects(id)` on delete cascade | |
| `rating` | `int` check (1..5) | |
| `message` | `text` null | |
| `created_at` | `timestamptz` default now() | |

### 4.8 `audit_logs` (reserved — retained history, D6)
Optional but recommended for operational history (who did what). Retained, never deleted. Granularity finalized at apply time.
| Column | Type | Notes |
|---|---|---|
| `id` | `uuid` PK | |
| `actor_id` | `uuid` → `profiles(id)` | |
| `action` | `text` | e.g. `project.create`, `closure.approve`, `user.deactivate` |
| `entity` / `entity_id` | `text` / `uuid` | target |
| `meta` | `jsonb` | small context (no finance/PII beyond need) |
| `created_at` | `timestamptz` default now() | |

---

## 5. Relationships (ERD)

```mermaid
erDiagram
  roles ||--o{ user_roles : grants
  roles ||--o{ role_permissions : defaults
  permissions ||--o{ role_permissions : in
  permissions ||--o{ user_permissions : overrides
  profiles ||--o{ user_roles : has
  profiles ||--o{ user_permissions : overrides
  profiles ||--o{ user_photographer_types : skilled_in
  photographer_types ||--o{ user_photographer_types : classifies
  profiles ||--o{ projects : manages
  profiles ||--o{ project_team_members : assigned
  profiles ||--o{ closure_requests : submits
  projects ||--o{ project_team_members : contains
  project_team_members ||--o{ project_team_types : typed_as
  photographer_types ||--o{ project_team_types : classifies
  projects ||--o{ project_stages : contains
  projects ||--o{ closure_requests : has
  projects ||--o{ project_links : has
  projects ||--o{ client_reviews : receives
```

---

## 6. Model → column mapping (fidelity)

| Dart model | Field | Table.column |
|---|---|---|
| `UserModel` | id/fullName/username/active/defaultRole | `profiles.*` (+`default_role_id`→`roles`) |
| `UserModel` | roles | `user_roles` → `roles.code` |
| `UserModel` | permissions | resolved: `user_permissions` over `role_permissions` (D5) |
| `UserModel` | photoTypes | `user_photographer_types` → `photographer_types` |
| `ProjectModel` | id/serial/name/clientName/managerId/type/status/startDate/endDate/notes | `projects.*` |
| `ProjectModel` | managerName | derived (join `profiles`) |
| `ProjectModel` | teamRoles | `project_team_members` + `project_team_types` (D3) |
| `ProjectTeamRole` | personName/userId/value/date | `project_team_members.*` |
| `ProjectTeamRole` | type | `project_team_types` (row per type) |
| `ProjectStageModel` | title/order/status/notes/updatedBy/updatedAt | `project_stages.*` |
| `ClosureRequestModel` | projectId/submittedBy/createdAt/deliveryLink/reportFileUrl/notes/status/rejectReason/reviewedAt | `closure_requests.*` |
| `ClosureRequestModel` | projectName/submittedByName | derived (join) |
| `DeliveryLink` | label/url | `project_links.*` (approved + client-visible) |
| `ClientTrackingModel` | rating/message | `client_reviews.*` |

> **App impedance note (D3):** the app currently models one `ProjectTeamRole` per (person, type). The Supabase read implementation **aggregates** `project_team_members` + `project_team_types` back into that shape (one `ProjectTeamRole` per type, sharing person/fee/date), so the Flutter models don't change.

---

## 7. Conventions

- **UUID PKs** everywhere (app string ids like `p-1` are reseeded — see migration plan).
- **`timestamptz`** for time, **`date`** for shoot/delivery dates (matches date-only availability).
- **Soft delete** (`is_active` + `deleted_at` + `deleted_by`) on `profiles`, `projects`, `project_links` (D6). Stages, closures, reviews, audit logs are retained (status changes, never deleted).
- **RLS enabled on every table**, default deny (`SUPABASE_RLS_PLAN.md`).
- **Read views** (`v_projects`, `v_closure_requests`, `v_team`) join display names and pre-filter soft-deleted rows, so repository reads stay one-shot.

---

## 8. Explicitly NOT created (guardrail)

No `finance_*`, `payments`, `payment_requests`, `transfers`, `finance_reports`, `rekaz_*`, `notifications`, `notification_settings`, `reminders`, `devices`, or `fcm_tokens` — now or in any future sprint, unless the owner explicitly reverses the exclusion.

---

## 9. Step 2 implementation notes (identity & access)

Migration `supabase/migrations/20260714120000_identity_and_access.sql` implements
§2 (identity/roles/permissions) + `audit_logs`. Details decided at implementation
time (consistent with, and refining, this draft):

- **Seeded `name_ar`:** roles use `RoleType.nameAr`; permissions use
  `featureLabelAr` (Flutter). Seeded via idempotent `on conflict` upserts.
- **`marketing` name_ar = «تسويق»** — provisional: the Flutter `RoleType` has no
  `marketing` value yet, so it has no canonical Arabic label. Update when the
  Flutter role is added.
- **`client_tracking` is NOT a staff role** — it exists in Flutter `RoleType` but
  public tracking is anonymous (no profile), so it is not seeded into `roles`.
- **Excluded-domain codes kept as inert reserved placeholders** (future
  compatibility, per owner decision): the `finance` / `wedding_finance` roles and
  the `can_manage_finance` permission exist in the catalog but are marked
  **`is_active = false`**, carry **NO permission defaults**, and are **never
  granted or assigned**. Zero operational behavior; finance stays permanently out
  of scope functionally. (`roles` and `permissions` both have an `is_active`
  column to support this marking.)
- **Default-role invariant** (`profiles.default_role_id` must be a role the user
  holds) is enforced by a **composite `DEFERRABLE INITIALLY DEFERRED` FK**
  `profiles(id, default_role_id) → user_roles(user_id, role_id)`, so a profile
  and its default `user_roles` row are inserted in one transaction.
- **Finance kept inert (revised):** `can_manage_finance` is stored as an
  **inactive** catalog row (`is_active = false`) and is never granted — no
  blocking CHECK. `finance`/`wedding_finance` roles are likewise inactive with no
  defaults. (Inert-placeholder decision; supersedes the earlier "excluded from
  catalog" approach.)
- **Normalized username** enforced by check `^[a-z0-9._-]{2,50}$` (lowercase,
  trimmed, no spaces, non-blank).
- **`updated_at`** maintained by a generic `public.set_updated_at()` trigger
  (only `profiles` has `updated_at` in this domain).
- **RLS enabled, no policies** on all 7 tables → access denied until Step 6.

---

## 10. Step 3 implementation notes (photographer types & availability)

Migration `supabase/migrations/20260714130000_photographer_types_and_availability.sql`
implements §3 (`photographer_types`, `user_photographer_types`, `user_unavailability`).
Runs after the Step 2 migration.

- **photographer_types** seeded with 4 canonical types (codes `photo`/`video`/
  `instagram`/`design`) from the frozen schema + Flutter `_kPhotoTypes`; idempotent
  upsert. Code format check `^[a-z][a-z_]*$`; `code` and `name_ar` both unique.
- **user_photographer_types** — M:N, PK `(user_id, photographer_type_id)` dedupes;
  `user_id` cascade, `photographer_type_id` restrict; index on the type for reverse
  lookups.
- **user_unavailability** — new table (not in the original draft) that backs the
  leave/permission side of the availability rule, replacing mock `MockLeave`.
  Fields: `starts_at`/`ends_at` (`timestamptz`, check `ends_at >= starts_at`),
  `kind`, `notes`, `is_active` (cancel = false, history retained), `created_by`,
  `created_at`/`updated_at` (trigger). No notifications/reminders.
- **Availability support:** a same-date/leave check is a range-overlap query,
  `user_id = X AND starts_at <= D_end AND ends_at >= D_start AND is_active`,
  served by the partial index `(user_id, starts_at, ends_at) where is_active`.
- **Marketing prep only:** membership is derivable via `user_roles` →
  `roles.code = 'marketing'`. The overlap **exemption is NOT implemented** — it
  belongs to the later project-team assignment RPC/business-rule step.
- **RLS enabled, no policies** on all 3 tables → access denied until Step 6;
  availability is never public.
- **Not created:** no project/project-team tables (Step 4), no RPCs, no Edge
  Functions, no assignment/overlap logic.

## 11. Step 4 implementation notes (projects core)

Migration `supabase/migrations/20260714140000_projects_core.sql` implements the
core project domain from §4.1–4.4 (`projects`, `project_team_members`,
`project_team_types`, `project_stages`) plus the three enums from §1. Runs after
the Step 2 (profiles, `set_updated_at`) and Step 3 (`photographer_types`)
migrations.

- **Enums** `project_type` (`field`/`social`/`wedding`), `project_status`
  (`active`/`in_progress`/`pending_closure`/`completed`/`delivered`/`approved`/
  `rejected`), `stage_status` (`pending`/`current`/`done`) — values verified
  1:1 against `lib/core/models/project_enums.dart`. The `closure_status` enum is
  **deliberately deferred to Step 5**.
- **projects (D6):** `serial` unique + format check
  `^(FLD|SOC|WED)-[A-Z0-9]{4}-[A-Z0-9]{2}$` (exactly matches `ProjectSerial`: only
  the canonical prefixes FLD/SOC/WED — field/social/wedding — + `[A-Z0-9]` 4- and
  2-char blocks) (generated by the future create_project
  RPC, not here); `manager_id → profiles` `on delete restrict` (ownership anchor
  for `manages_project()` in Step 6); `status` default `active`; date range check
  `end_date >= start_date`; soft-delete columns (`is_active`/`deleted_at`/
  `deleted_by`); `updated_at` via the shared `set_updated_at` trigger. `deleted_by`
  is `on delete set null`. `manager_name` stays a derived/view field.
- **project_team_members (D3):** supports **multiple members per project**;
  `user_id` nullable (`null` = external person), `on delete set null` to keep the
  team row if a profile is hard-removed; partial unique
  `(project_id, user_id) where user_id is not null` prevents a duplicate internal
  photographer. `value` is **assignment metadata only — not finance** (guardrail,
  documented in a column comment). `date` (non-reserved keyword, kept as-is) is
  the assignment/shoot date the Step 6 `is_available()` overlap check reads
  (`t.date`), enabling the booking-overlap rule later.
- **project_team_types (D3):** one row per (member, photographer type) with
  `unique (team_member_id, photographer_type_id)` → **multiple types per member**,
  each referencing the normalized `photographer_types` catalog (`on delete
  restrict`). This is what the Flutter read layer aggregates back into one
  `ProjectTeamRole` per (person, type).
- **project_stages:** retained history (no soft delete). `order` renamed to
  **`stage_order`** because `order` is a reserved SQL keyword; unique
  `(project_id, stage_order)`. Stage **count and titles are per-project DATA**
  seeded by the future create_project RPC — the schema imposes no fixed count, so
  it serves both the **3-stage** (field/wedding) and **7-stage** (social) flows.
  `updated_at` is nullable and set explicitly by the stage-advance RPC (no
  auto-trigger) so it reflects real stage activity.
- **Manager ownership** flows through `projects.manager_id`; the read/write
  policies keyed on it come in Step 6.
- **RLS enabled, no policies** on all 4 tables → default-deny until Step 6. **No**
  seed/reference rows inserted (enums cover the closed domains; stage titles are
  seeded per project later).
- **Not created (Step 5 scope):** no `closure_requests`, no `project_links`, no
  `client_reviews`, no client-tracking tables/RPCs, no `closure_status` enum. No
  RPCs, Edge Functions, serial generation, stage seeding, or availability/overlap
  enforcement in this step. No Flutter or package changes.

## 12. Step 5 implementation notes (closure requests & project links)

Migration `supabase/migrations/20260714150000_closure_requests_and_project_links.sql`
implements §4.5 (`closure_requests`) and §4.6 (`project_links`) plus the
`closure_status` enum from §1. Runs after Steps 2, 3, and 4.

- **closure_status enum** (`pending`/`approved`/`rejected`) — verified 1:1 against
  `ClosureRequestStatus` in `lib/core/models/closure_request_model.dart`. Deferred
  out of Step 4; created here. No statuses invented.
- **closure_requests (retained history):** exact frozen §4.5 fields — `id`,
  `project_id`→projects (cascade), `submitted_by`→profiles (**restrict**, keeps
  history intact; profiles soft-delete under D6), `status` (default `pending`),
  `delivery_link`, `report_file_url` (**plain text URL, Storage deferred — not a
  file upload**), `notes`, `reject_reason`, `reviewed_at`, `created_at`. **No
  `reviewed_by` and no `updated_at`** — neither is in the frozen schema or the
  Flutter contract, so neither (nor an updated_at trigger) was added. No
  soft/hard-delete columns → approved/rejected rows are retained history. **No**
  automatic project-status change and **no** submit/approve/reject RPC in this
  step.
- **Duplicate pending prevention:** partial unique index
  `closure_requests_one_pending_per_project_uidx on (project_id) where status =
  'pending'`. A second `pending` row for the same project violates it; approved/
  rejected rows are unconstrained, so history accumulates and a project may
  re-request after a rejection.
- **project_links (D4/D6, URL-only):** exact frozen §4.6 fields — `id`,
  `project_id`→projects (cascade), `label` (not blank), `url` (not blank + safe
  `^https?://` check; **no Storage, no file-upload field**), `is_approved`
  (default false), `is_client_visible` (default false), `is_active` (default
  true), `created_at`, `deleted_at`, `deleted_by`→profiles (set null). Plus
  **`created_by`**→profiles (set null), included per the Step 5 instruction
  (symmetric with `deleted_by`; extends the §4.6 draft). No `updated_at` (not in
  the frozen schema).
- **Client-visible link protection before Step 6:** eligibility (`is_approved AND
  is_client_visible AND is_active AND deleted_at IS NULL`) is only **data** here.
  RLS is enabled with **no policies** and there is **no anon/public SELECT and no
  `track_by_serial` RPC**, so no client (or any role) can read these rows yet.
  Public exposure will happen solely through the restricted security-definer RPC
  in Step 6, keyed on the project serial, excluding staff names/identities,
  internal notes, assignment `value`, roles/permissions, and review internals.
- **Indexes:** closure — `(project_id)`, `(status)`, + the pending partial
  unique. links — `(project_id)`, + partial `(project_id) where is_approved and
  is_client_visible` (frozen §4.6). No speculative indexes.
- **client_reviews:** **DEFERRED** (not created). No standalone Flutter
  ClientReview contract exists (rating/message live on `ClientTrackingModel`, via
  the future anon `submit_review` RPC), and Step 5 is scoped to closure + links.
  Remains deferred to the tracking/RPC step. Nothing invented.
- **RLS enabled, no policies** on both tables → default-deny until Step 6. **No**
  RPCs, Edge Functions, RLS policies, Storage buckets, roles/permissions changes,
  seed data, or Flutter/package changes. Reproducible from empty (enum before
  table; Step 2 `profiles` + Step 4 `projects` deps present).
