# Sprint 11 · Step 11.1 — Project contract audit

**Audit date:** 2026-07-31

**Starting main:** `6dcd676498c5c34774312c58379ccc3e6f61b70e`

**Branch:** `codex/sprint-11-project-integration`

**Scope:** documentation and local source audit only

## 1. Evidence reviewed

### Flutter

- `ProjectRepository`, `MockProjectRepository`, `TrackingRepository`, and
  `MockTrackingRepository`;
- project, stage, team-role, closure, tracking, enum, role, user, and permission
  models;
- repository, manager, photographer, admin, calendar, and tracking providers;
- project list/detail/create/edit/manage/team/availability/stage/closure screens;
- public tracking entry/result screens and the relevant tests.

### Supabase source

- migrations `20260714120000` through `20260714200000` for identity, catalogs,
  project schema, RLS, workflow RPCs, tracking, and function hardening;
- later Sprint 10 migrations and all Edge Functions to confirm that none adds a
  project-domain contract;
- Sprint 8/9 schema, RLS, migration, QA, and master-spec documentation.

No remote Supabase command or live-data query was run. The audit therefore
describes the version-controlled contract, not the current grants/data of a
linked DEV project.

Supabase's 2026 changelog notes that public-schema tables may no longer be
automatically exposed to the Data API. These migrations create RLS policies but
do not explicitly `GRANT SELECT` on project tables. Step 11.2 must verify table
privileges in an owner-controlled environment before relying on direct reads;
RLS alone does not grant table access.

## 2. Audit decision

| Area | Decision |
|---|---|
| RLS-scoped project/stage/team reads | Trusted policies exist; exact visibility is relationship-scoped |
| Project create/edit/stage/team writes | Trusted RPCs exist, with Flutter contract mismatches documented below |
| Closure workflow | Trusted submit/approve/reject RPCs exist; closure display hydration is mismatched |
| Availability | Trusted boolean RPC exists; current Flutter/mock behavior contradicts it |
| Public tracking | Trusted minimal RPC exists |
| Manager reassignment | Missing |
| Manager-safe assignable-staff discovery | Missing |
| Delivery-link mutation | Missing |
| Client review submission | Missing |
| Project soft delete | Missing |
| Project-domain Edge Functions | None; none required by an existing trusted project contract |

The project and tracking providers remain mock-backed. Step 11.1 makes no
runtime change and does not start `SupabaseProjectRepository`.

## 3. Frozen security boundaries

1. Authenticated direct reads are permitted only through the SELECT policies in
   §§5–6 and only if Data API/table privileges are actually present.
2. There are no authenticated insert/update/delete policies on project-domain
   tables. Flutter must not perform direct writes.
3. Multi-table and state transitions use only the SECURITY DEFINER RPCs in §7.
4. Every externally callable function has explicit EXECUTE grants. Internal
   `_apply_project_team`, `gen_project_serial`, and trigger helper
   `set_updated_at` are revoked from `PUBLIC`, `anon`, `authenticated`, and
   `service_role` by migration `20260714200000`.
5. `service_role` is not allowed in Flutter. There is no reason to add a
   project-domain Edge Function for any currently supported operation.
6. Effective permissions are resolved by `has_feature`: an explicit active-user
   override wins, otherwise an active role default grants; unknown/inactive
   permissions and inactive roles fail closed.
7. Admin branches in project RPCs deliberately use `is_admin()` and may bypass
   a feature flag where the SQL says so. Non-admin callers need the exact
   relationship and feature predicates listed below.
8. `value` is visible only with its team row and is assignment metadata. RLS
   prevents assigned peers from reading teammate rows/values.
9. Public tracking never exposes UUIDs, manager/team data, `value`, notes,
   stages, closures, audit, permissions, unavailability, or Auth identity.
10. Unknown/malformed backend values must produce a safe repository failure;
    they must never map to manager, active, current, or another default.

## 4. Canonical database-to-model result shapes

These are the exact source rows available to a future repository. There is no
`v_projects`, `v_team`, or `v_closure_requests` view in migrations.

### 4.1 Project graph

- `projects`: `id uuid`, `serial text`, `name text`, `client_name text`,
  `manager_id uuid`, `type project_type`, `status project_status`,
  `start_date date`, `end_date date`, `notes text?`, `is_active boolean`,
  `created_at timestamptz`, `updated_at timestamptz`, `deleted_at timestamptz?`,
  `deleted_by uuid?`.
- `project_stages`: `id uuid`, `project_id uuid`, `title text`,
  `stage_order int`, `status stage_status`, `notes text?`, `updated_by uuid?`,
  `updated_at timestamptz?`.
- `project_team_members`: `id uuid`, `project_id uuid`, `user_id uuid?`,
  `person_name text`, `value numeric`, `date date?`.
- `project_team_types`: `id uuid`, `team_member_id uuid`,
  `photographer_type_id uuid` joined to `photographer_types(id, code, name_ar,
  is_active)`.

Hydration fans one database member with multiple type rows out into the current
Flutter per-type `ProjectTeamRole` list. It must not duplicate `value` across
types when consumers aggregate it. For an assigned staff caller, the hydrated
team deliberately contains only that caller's own member/type rows.

`manager_name` is not stored. Profile RLS lets an assigned non-admin read only
their own profile, so the repository must leave `ProjectModel.managerName` null
unless an approved safe contract supplies it.

### 4.2 Closure rows

`closure_requests` returns `id uuid`, `project_id uuid`, `submitted_by uuid`,
`status closure_status`, `delivery_link text?`, `report_file_url text?`,
`notes text?`, `reject_reason text?`, `reviewed_at timestamptz?`, and
`created_at timestamptz`.

`project_name` and `submitted_by_name` are not stored. Project name can be
derived from a visible project. A manager can sometimes derive the submitter
name from a current team row, but replace-all team edits can remove that row.
Therefore the required non-null `ClosureRequestModel.submittedByName` cannot be
reliably hydrated for retained history. This is a real contract mismatch, not a
value the client may invent.

### 4.3 Delivery links

Authenticated manager/admin reads return `project_links(id, project_id, label,
url, is_approved, is_client_visible, is_active, created_by, created_at,
deleted_at, deleted_by)` under RLS. No repository method or mutation RPC exists.

The public tracking RPC returns either JSON null or exactly the client-safe
logical shape:

```json
{
  "serial": "FLD-1A2B-3C",
  "project_name": "...",
  "client_name": "...",
  "status": "active|done",
  "links": [{"label": "...", "url": "https://..."}]
}
```

The SQL constructs these keys; a strict Flutter parser should reject wrong
types, malformed URLs, unknown status, or malformed link entries.

## 5. SELECT RLS matrix

| Table | Direct authenticated SELECT | Visible rows | Important limits |
|---|---|---|---|
| `projects` | Policy exists | live/non-deleted project when caller owns it, is assigned, or is admin | `getProjects` means caller-visible projects, never globally all except admin |
| `project_team_members` | Policy exists | owner/admin: all rows; assigned staff: own row only | external rows are owner/admin only; teammate `value` hidden from assigned staff |
| `project_team_types` | Policy exists | mirrors parent team-member scope | assigned staff sees own types only |
| `project_stages` | Policy exists | stages whose parent project is RLS-visible | read only; no direct stage write |
| `closure_requests` | Policy exists | owning manager, submitter's own requests, or admin; parent must be live | other assigned staff cannot read requests |
| `project_links` | Policy exists | owning manager or admin on a live project | assigned staff have no direct link read; no anon policy |
| `photographer_types` | Policy exists | active catalog to any active user; all rows to admin | current active seed is four codes only |
| `user_photographer_types` | Policy exists | own assignments or admin all | manager cannot use it to discover candidates' skills |
| `user_unavailability` | Policy exists | caller's own rows or admin all | manager cannot read another user's kind, notes, or periods |
| `profiles` | Policy exists | self or admin | managers cannot list photographer candidates through broad profile reads |
| `audit_logs` | Policy exists | admin only | immutable through direct access |

Every project parent policy fails closed for inactive/soft-deleted callers and
filters inactive/soft-deleted projects. There is no anon table SELECT.

## 6. Permission and role semantics

RPC role descriptions below describe defaults, not hardcoded role allowlists:

- `manager` defaults: add/edit/assign/update-stage/approve-closure;
- `photographer` defaults: update-stage/request-closure;
- `wedding_admin` defaults: add/assign/manage-wedding;
- `admin`: explicit `is_admin()` branches in the RPCs;
- `marketing`: no default project permissions, but an override can grant them;
  its active role grants only the documented double-booking exemption;
- any other active role can act only when SQL is role-agnostic and the caller
  has the required override plus relationship;
- inactive `finance`/`wedding_finance` and `can_manage_finance` grant nothing.

Relationship checks, feature checks, live-profile checks, and project-state
checks all remain server-authoritative.

## 7. Trusted RPC inventory

| Function and exact arguments | Result | Authorization | Allowed project state | SECURITY / EXECUTE |
|---|---|---|---|---|
| `create_project(p_name text, p_client_name text, p_type project_type, p_start_date date, p_end_date date, p_notes text = null, p_manager_id uuid = null, p_members jsonb = [])` | new project UUID | active `is_admin()` or `can_add_project`; non-admin manager is `auth.uid()`; non-empty team also needs admin or `can_assign_photographers` | creates `active` | DEFINER, fixed empty search path; authenticated only |
| `update_project(p_project_id uuid, p_name text, p_client_name text, p_type project_type, p_start_date date, p_end_date date, p_notes text = null)` | project UUID | admin, or owning manager + `can_edit_project` | `active`, `in_progress` | DEFINER; authenticated only |
| `update_project_stage(p_project_id uuid, p_stage_id uuid, p_notes text = null)` | project UUID | admin, or owner/assigned caller + `can_update_stages` | `active`, `in_progress` | DEFINER; authenticated only |
| `assign_team_roles(p_project_id uuid, p_members jsonb)` | project UUID | admin, or owning manager + `can_assign_photographers` | `active`, `in_progress` | DEFINER; authenticated only |
| `is_available(uid uuid, on_date date, exclude_project_id uuid = null)` | boolean | admin, `can_assign_photographers`, or caller checking own UID | considers other `active`, `in_progress`, `pending_closure` projects | DEFINER/STABLE; authenticated only |
| `submit_closure_request(p_project_id uuid, p_delivery_link text = null, p_report_file_url text = null, p_notes text = null)` | closure-request UUID | assigned caller + `can_request_closure` | `active`, `in_progress` → `pending_closure` | DEFINER; authenticated only |
| `approve_closure_request(p_request_id uuid)` | request UUID | admin, or owning manager + `can_approve_closure` | pending request + parent `pending_closure` → `completed`; all stages `done` | DEFINER; authenticated only |
| `reject_closure_request(p_request_id uuid, p_reason text)` | request UUID | admin, or owning manager + `can_approve_closure` | pending request + parent `pending_closure` → `active` | DEFINER; authenticated only |
| `track_project_by_serial(project_serial text)` | JSON object above or null | no profile/feature requirement | any live project; status collapsed to `active|done` | DEFINER/STABLE; anon + authenticated |

### 7.1 Exact team JSON contract

`p_members` must be a JSON array. Each object is:

```json
{
  "user_id": "uuid-or-null",
  "person_name": "required for external; ignored/derived for internal",
  "value": 0,
  "date": "YYYY-MM-DD-or-null",
  "photographer_type_ids": ["uuid"]
}
```

- Internal members require a valid, active/non-deleted profile and a non-null
  date; their stored name is derived from `profiles.full_name`.
- External members require a non-blank name; their date is optional.
- Internal user IDs cannot repeat. Type IDs cannot repeat within one member and
  must reference active catalog rows.
- Existing rows are deleted and replaced only after the complete proposed team
  validates and profile locks/availability checks succeed.
- The SQL currently allows an empty type array even though planning prose says
  1..N types. It also does not require an assigned type to be among that user's
  `user_photographer_types`. These are documented backend contradictions; the
  client must not silently decide new rules.
- Assignment dates are not constrained to the project date range.

### 7.2 Audit effects

Trusted writes add identifier-only audit actions:

- `project.create`;
- `project.edit`;
- `project.stage.update`;
- `project.team.assign` with `member_count` only;
- `closure.submit`;
- `closure.approve`;
- `closure.reject`.

Names, assignment values/dates/types, URLs, notes, rejection text, tokens,
passwords, and internal Auth email are not copied into audit metadata.

## 8. `ProjectRepository` contract matrix

The matrix contains, for every method, its Flutter callers, backend mechanism,
exact arguments/result, feature/role/state gates, direct-read/RPC decision,
compatibility decision, and recommended implementation step.

| Flutter operation and callers | Backend contract | Exact arguments | Exact result | Feature permission | Allowed callers | Allowed statuses | Direct SELECT? | Trusted RPC mandatory? | Decision | Sprint step |
|---|---|---|---|---|---|---|---|---|---|---|
| `getProjects`; all/admin providers, capacity and photographer-request joins | RLS SELECT project graph (§4.1) | no RPC; optional client query predicates only | caller-visible hydrated `List<ProjectModel>` | none beyond active caller/RLS | owner, assigned staff, admin | every enum status, live/non-deleted only | yes | no | **Supported**, but not globally all for non-admin | 11.2 |
| `getProjectById(id)`; manager/photographer/admin detail and all write screens | same graph with project UUID equality | strict UUID `id` | one visible `ProjectModel` or null | none beyond RLS | owner, assigned staff, admin | all, live only | yes | no | **Supported** | 11.2 |
| `getProjectsForManager(managerId)`; manager lists/calendar/closure joins | `projects.manager_id` filter under project RLS | strict manager UUID; normal manager call must use current UID | visible matching project graphs | none beyond RLS | own manager; admin may query target | all, live only | yes | no | **Supported**; never trust ID as authorization | 11.2 |
| `getProjectsForPhotographer(userId)`; photographer lists/calendar | visible projects joined/filtered through own team row | strict user UUID; normal caller must use current UID | visible assigned project graphs, team limited to own rows | none beyond RLS | assigned self; admin may query target | all, live only | yes | no | **Supported** | 11.2 |
| `getCompletedProjects`; tests/future completed views | project status filter | statuses `completed`, `delivered`, `approved` | visible completed-group projects | none beyond RLS | owner, assigned staff, admin | completion group only | yes | no | **Supported** | 11.2 |
| `searchProjects(query)`; interface/tests, list screens currently search locally | hydrated visible graph search | trimmed query; name/client/serial/team `person_name` | matching visible projects | none beyond RLS | owner/admin can search full visible team; assigned staff only own row | all, live only | yes, then safe local filtering or approved PostgREST predicates | no | **Mismatched/role-dependent** for teammate-name search | 11.2 |
| `filterProjects(status,type)`; interface/tests | typed predicates on visible `projects` | known enum or null for each | matching visible projects | none beyond RLS | owner, assigned staff, admin | requested known status | yes | no | **Supported** | 11.2 |
| `createProject(...)`; `AddProjectScreen` | `create_project` | exact §7 args; team uses §7.1; no client serial or manager name | scalar project UUID, then RLS re-read | admin or `can_add_project`; team also admin/`can_assign_photographers` | admin; any active feature holder (defaults manager/wedding admin); non-admin owns result | creates `active` | no | yes | **Mismatched**: interface sends serial/name and flattened team; UI preview assumes client serial | 11.3 without team; 11.4 team |
| `updateProjectBasics(id, name, clientName, type, status, dates, notes)`; shared manager/admin edit screen | `update_project` | project UUID, names, **existing** type, dates, notes; no status arg | scalar project UUID, then re-read | admin or owner + `can_edit_project` | admin; owning feature holder (default manager) | `active`, `in_progress` | no | yes | **Mismatched**: Flutter permits type/status changes; RPC forbids type change and has no status override | 11.3 |
| `setProjectManager(id, managerId, managerName)`; admin team screen | none | none | none | undefined | none through trusted contract | undefined | no | required but absent | **Unsupported** | disable; future contract |
| `assignTeamRoles(id, roles)`; manager assign and admin team screens | `assign_team_roles` | project UUID + grouped §7.1 JSON | scalar project UUID, then re-read | admin or owner + `can_assign_photographers` | admin; owning feature holder (default manager) | `active`, `in_progress` | no | yes | **Mismatched**: screens omit assignment dates, hardcode invalid types, and lack manager-safe candidates | 11.4 after prerequisite |
| `updateProjectStage(projectId, stageId, notes, updatedBy)`; stage screen | `update_project_stage` | project UUID, stage UUID, notes; omit `updatedBy` because server uses `auth.uid()` | scalar project UUID, then re-read | admin or owner/assigned + `can_update_stages` | admin; owner/assigned permitted caller | `active`, `in_progress` | no | yes | **Supported with argument mismatch** | 11.3 |
| `getClosureRequests`; closure/admin/manager/photographer providers | RLS SELECT closure rows plus visible projects/name hydration | optional visible filters | `List<ClosureRequestModel>` requires derived project/submitter names | none beyond RLS | owning manager, submitting self, admin | parent live; request any closure status | yes | no for rows; a safe read RPC/view may be needed for names | **Mismatched**: retained submitter name not reliably derivable | 11.5 prerequisite decision |
| `submitClosureRequest(...)`; submit screen | `submit_closure_request` | project UUID, delivery link?, report URL/text?, notes?; omit submittedBy/name | request UUID, then scoped re-read | `can_request_closure` | assigned permitted caller (default photographer) | `active`, `in_progress` | no | yes | **Supported with identity-argument mismatch** | 11.5 |
| `approveClosureRequest(requestId)`; manager closure list/end flow | `approve_closure_request` | request UUID | request UUID; re-read request/project/stages | admin bypass or owner + `can_approve_closure` | admin; owning permitted manager | pending request; project `pending_closure` | no | yes | **Supported**; EndProject UI currently lacks permission gate | 11.5 |
| `rejectClosureRequest(requestId, reason)`; same flows | `reject_closure_request` | request UUID + non-blank trimmed reason | request UUID; re-read request/project | admin bypass or owner + `can_approve_closure` | admin; owning permitted manager | pending request; project `pending_closure` | no | yes | **Supported**; UI gate mismatch on direct end route | 11.5 |

## 9. Operations missing from the repository interface

| Operation and affected caller | Existing backend | Exact contract/result | Permission / callers / states | SELECT vs RPC | Decision | Recommended step |
|---|---|---|---|---|---|---|
| Photographer availability lookup; create/assign/team/calendar capacity UI | `is_available` | args `uid`, `on_date`, `exclude_project_id`; boolean only | admin, `can_assign_photographers`, or self; checks conflicting live projects | RPC mandatory for another user | **Mismatched**: UI expects booked-vs-leave reason and bulk candidates | 11.4 after candidate contract |
| User unavailability lookup | RLS SELECT `user_unavailability` | full row including kind/notes/timestamps | self or admin only; manager intentionally denied | direct SELECT only for self/admin | **Supported for self/admin; unsupported for manager UI** | do not add to manager repository |
| Project delivery links | RLS SELECT `project_links` | authenticated row shape §4.3 | owning manager/admin, live project | direct SELECT for read; RPC mandatory for mutations | **Read supported; every mutation unsupported** | 11.5 read-only |
| Anonymous client tracking; public screens | `track_project_by_serial` | arg `project_serial`; JSON/null §4.3 | anon or authenticated; any live project | RPC mandatory | **Supported** | 11.6 |
| Client review; `TrackingRepository.submitReview` (no production caller) | none; `client_reviews` and `submit_review` were deferred | none | undefined | future anon RPC mandatory | **Unsupported** | keep disabled/mock-only |
| Manager reassignment; admin project-team screen | none | none | undefined | future transactional RPC mandatory | **Unsupported** | disable real action |
| External team members; current model/read/admin preserve path | `assign_team_roles` payload supports `user_id:null` | name required; optional date; active type IDs; returns project UUID | same assignment authorization/states | RPC mandatory | **Backend-supported, UI-mismatched**: no creation UX and type/date rules incomplete | 11.4 only after explicit UX |
| Assignable internal staff discovery for manager screens | none; profile/type RLS gives managers only self/catalog, not candidates | needed safe rows: ID, display name, active types, availability boolean; no username/permissions/leave detail | admin or `can_assign_photographers`; optionally project owner/state | future least-privilege RPC or invoker view/policy | **Unsupported and blocking manager assignment UX** | prerequisite for 11.4 |
| Project soft delete | schema columns only; no write policy/RPC | none | undefined | future audited RPC mandatory | **Unsupported** | no real UI action |
| Audit-log reads | admin SELECT RLS | audit rows | admin only | direct SELECT, but not a ProjectRepository concern | **Supported, out of repository scope** | separate audit UI only if approved |

## 10. Model compatibility audit

| Concern | Flutter | PostgreSQL/trusted behavior | Compatibility decision |
|---|---|---|---|
| `ProjectType` | `field`, `social`, `wedding`; `fromKey` returns null on unknown | identical enum | exact; parser rejects unknown |
| `ProjectStatus` | seven keys; active group = active/in-progress; completed group = completed/delivered/approved | identical seven-value enum | exact values; `rejected` belongs to neither helper group; no generic default |
| `ProjectStageStatus` | pending/current/done; no parser helper | identical enum | implement explicit strict switch; never default to current/pending |
| `ClosureRequestStatus` | pending/approved/rejected; no parser helper | identical enum | implement explicit strict switch |
| Team-member role/type | `ProjectTeamRole.type` is Arabic text, one row per type | normalized member + many type IDs/codes/names | repository must group/fan out; no free-text internal type |
| Photographer catalog | add screen: four canonical Arabic labels; assign/admin screens: eight mixed labels; master spec lists thirteen | active seed: `photo`, `video`, `instagram`, `design` only | backend four-code catalog is authoritative; `درون`, `مونتاج`, `مساعد مصور`, `كواليس`, `تيك توك`, etc. are unsupported until migrated |
| Project dates | Dart `DateTime` | `date` without timezone | parse `YYYY-MM-DD` as a calendar date; do not apply UTC offset conversion |
| Assignment dates | nullable Dart `DateTime` | nullable column, but RPC requires date for internal member | UI must collect/preserve a date; serialize `YYYY-MM-DD` only |
| Timestamps | nullable/local `DateTime` fields | `timestamptz` instants | require ISO timestamp with offset; normalize instant (prefer UTC internally), localize only for display |
| Manager ID/name | `managerId` required; `managerName` nullable | `manager_id` non-null; name derived, profile RLS restricted | ID exact UUID; name may be null; never fabricate or expose Auth email |
| Team user ID | nullable | null means external person | exact; internal UUID strict, external requires non-blank name |
| Closure submitter ID/name | both required in model | ID stored, name not stored | mismatch for retained history; safe read contract or model change required |
| External team | model supports null user ID | RPC/schema support external name, optional date, multiple types | read/preserve possible for owner/admin; creation UX absent |
| `value` | defaults 0 and comments/UI sometimes call it fee | numeric metadata, no bound | metadata only; never finance, total, payment, or public value |
| Soft-deleted rows | no model flags | project RLS and RPCs require `is_active` and `deleted_at is null` | never hydrate; null/not-found is safe behavior |
| Serial | client generator/preview exists | server generates `FLD|SOC|WED-[A-Z0-9]{4}-[A-Z0-9]{2}` with collision retry | server authoritative; do not send/retain client preview as persisted serial |
| Stage order | integer `order` | positive `stage_order`, unique per project | sort ascending; reject duplicates/non-positive/missing joins |
| Workflow shape | type helpers expect social=7, field/wedding=3; currentStage has fallbacks | create RPC seeds exact canonical titles/statuses; schema alone permits other counts | strict read should validate canonical created workflow and fail closed on malformed state rather than rely on fallback |
| Three-stage titles | exact canonical list | exact same RPC titles | compatible |
| Seven-stage titles | exact canonical list | exact same RPC titles | compatible |
| Public tracking status | string; result UI defaults unknown to in-progress | RPC returns only `active` or `done` | parser must reject unknown before UI; no silent fallback |

Authenticated UUIDs may be kept internally to perform scoped repository calls,
but they are not user-facing identity and must never enter public tracking output
or logs. Internal Auth email is absent from all project models and RPC results.

## 11. Availability behavior frozen from current backend

The trusted SQL, not the mock UI, is authoritative for Sprint 11:

1. The booking key is `project_team_members.date`, not the project's date
   range and not automatically `projects.start_date`.
2. Internal members require an assignment date. External members may omit it.
3. Project overlap is exact same assignment date, not any overlap with
   `projects.start_date..end_date`.
4. Booking-conflict project statuses are exactly `active`, `in_progress`, and
   `pending_closure` when the project is live/non-deleted.
5. `completed`, `delivered`, `approved`, and `rejected` projects do not block a
   booking.
6. Active `user_unavailability` blocks when its half-open timestamp range
   overlaps the selected Asia/Riyadh calendar day:
   `starts_at < day_end AND ends_at > day_start`.
7. Marketing membership bypasses only project double-booking. Explicit
   unavailability still blocks Marketing.
8. A target internal profile must be active and non-deleted.
9. `exclude_project_id` prevents the project's existing member row from
   conflicting during replace-all edits.
10. Duplicate internal users in one proposed team are rejected. Multiple types
    belong to one member object, not duplicate member objects.
11. The function returns only true/false. It deliberately does not disclose
    whether leave or another project caused false.
12. Profile locks and a post-lock availability recheck protect concurrent team
    assignments.

### Mock/backend contradictions

- `team_availability.dart` checks whether a selected day lies anywhere in an
  active project's start/end range; SQL checks exact assignment date.
- the mock counts only `active`/`in_progress`; SQL also counts
  `pending_closure` as a conflict.
- `MockLeave` is date-only and can return a reason; SQL uses timestamptz overlap
  in Asia/Riyadh and returns no reason.
- `isMarketingExempt` always returns false; SQL recognizes an active Marketing
  role and exempts project double-booking only.
- capacity providers count active projects and use `<2` as a UI signal; this is
  not an authorization or availability rule and must not block/allow writes.
- create assigns `_startDate` to each mock role, while existing manager/admin
  team edit screens reconstruct roles without dates, which the RPC rejects.

## 12. Other contradictions and gaps

1. **Proposed read views do not exist.** Sprint 8 documentation planned
   `v_projects`, `v_team`, and `v_closure_requests`; migrations implemented
   base-table RLS instead.
2. **Manager candidate discovery is absent.** Project screens use
   `UserRepository.getUsers()`, but non-admin profile/user-type RLS exposes only
   the manager's own identity and types. The real manager gets no photographer
   list.
3. **Admin basic edit overreaches.** Flutter offers type and status changes;
   `update_project` makes type immutable and accepts no status argument.
4. **Manager hub permission gates are incomplete.** Role-only UI exposes edit,
   stage, team, and closure paths even when an effective permission is revoked.
   Direct routes have no project-specific router guard. RPCs still fail safely.
5. **Manager ownership UI is too broad.** `ProjectDetailsScreen` treats any user
   holding the manager role as able to manage every project they can see; SQL
   requires ownership for non-admin edits/assignment/closure review.
6. **Closure end route lacks a feature gate.** `ClosureRequestsScreen` checks
   `can_approve_closure`; `EndProjectScreen` directly enables approve/reject.
7. **Photo-type sources disagree.** Master spec has thirteen labels, backend has
   four active codes, and assign/admin screens have a different eight-label
   list. Only the backend catalog may drive real payloads.
8. **Multiple types are flattened inconsistently.** Create emits repeated
   `ProjectTeamRole` entries for one user; SQL rejects repeated member user IDs
   unless the repository groups them into one member with many type IDs.
9. **Closure names are not durable.** The schema intentionally stores no
   submitted name, while Flutter requires it and team replacement can remove
   the only manager-visible display source.
10. **Project status values are broader than transitions.** No trusted RPC sets
    project `delivered`, `approved`, or `rejected`; closure approval sets
    `completed`, rejection returns to `active`.
11. **Team type minimum is not enforced.** Documentation says 1..N, but schema
    and `_apply_project_team` accept zero type IDs.
12. **Skill membership is not enforced.** Assignment validates active type IDs
    but does not require them to be in the internal user's
    `user_photographer_types`.
13. **Assignment date/range relation is undefined.** SQL does not require a
    member date to fall inside project start/end dates.
14. **Public tracking status UI has a fallback.** Safety depends on the future
    repository rejecting values other than `active|done` before rendering.
15. **Data API privileges are deployment-dependent.** RLS policies exist, but
    explicit table grants are not version-controlled in these migrations.

## 13. Missing trusted contracts and required UI disposition

| Missing contract | Affected screen/action | Step 11 disposition | Future contract recommendation |
|---|---|---|---|
| Manager-safe assignable staff | add project team picker, assign photographers, manager team/capacity | disable real team selection or retain mock-only until present | least-privilege authenticated RPC returning active staff ID/name, active type codes, and boolean availability; gate admin or `can_assign_photographers`; no username/email/permission/leave detail |
| Manager reassignment | admin project team "change manager" | disable real action; mock remains for tests | `set_project_manager(p_project_id,p_manager_id)` DEFINER RPC with admin/approved owner gate, eligible active management role check, project lock/state check, audit, UUID return |
| Durable safe closure read | manager/admin/photographer closure lists | do not fabricate submitter name | security-invoker view with correct RLS or scoped RPC returning request fields plus safe project/submitter display names; no extra profile data |
| Delivery-link create/edit/approve/visibility/delete | completed-project link action and future manager link management | retain coming-soon/read-only | audited RPCs with owner/admin gates, live/state checks, HTTP(S) validation, approval/visibility controls, and soft delete |
| Client review schema/RPC | `TrackingRepository.submitReview` | unsupported/mock-only; no direct write | anon DEFINER `submit_review` with normalized serial, rating 1..5, bounded message, rate/abuse controls, neutral errors, and retained review table |
| Project soft delete | no approved current UI | no action | audited RPC that sets `is_active=false`, `deleted_at`, `deleted_by` and defines closure/team consequences |
| Generic project status override | admin basic edit | disable status editing | do not add a generic setter; add only explicit product-approved transitions with state machines and audit |
| Candidate conflict reason | assignment lock reason text | show neutral unavailable only | if product truly needs reasons, return a coarse enum that does not reveal leave notes/kind or another project's identity |

No missing contract may be replaced by a Flutter table insert/update/upsert/delete
or a broader RLS policy in this sprint.

## 14. Recommended implementation mapping

- **11.2:** strict RLS reads, graph hydration, parser/error foundation, read
  provider cutover where supported.
- **11.3:** `create_project` without unsafe initial-team assumptions,
  supported-subset `update_project`, `update_project_stage`, and correct UI
  permission/state gates.
- **11.4:** manager-safe candidate prerequisite, backend catalog, assignment
  dates, exact availability, multi-type grouping, and `assign_team_roles`.
- **11.5:** closure read-shape resolution, closure workflow RPCs, and read-only
  scoped project links; missing mutations remain disabled.
- **11.6:** strict `track_project_by_serial`, provider cutover, security tests,
  full regression, and owner-controlled mobile DEV QA; reviews stay disabled.

## 15. Step 11.1 change and environment confirmation

Step 11.1 created only:

- `docs/SPRINT_11_PROJECT_INTEGRATION_PLAN.md`;
- `docs/qa/STEP_11_1_PROJECT_CONTRACT_AUDIT.md`.

It did not modify Flutter runtime code, tests, migrations, RLS, RPCs, Edge
Functions, accounts, DEV data, or Production. No Supabase remote command ran.
The pre-existing `docs/engineering` files were read only to confirm repository
state and were not modified or staged.
