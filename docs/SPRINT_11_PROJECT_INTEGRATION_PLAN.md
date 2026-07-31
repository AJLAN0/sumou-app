# Sprint 11 — Project integration plan

**Status:** Step 11.1 contract audit only

**Baseline:** `origin/main` at `6dcd676498c5c34774312c58379ccc3e6f61b70e`

**Working branch:** `codex/sprint-11-project-integration`

**Detailed audit:** `docs/qa/STEP_11_1_PROJECT_CONTRACT_AUDIT.md`

## 1. Goal

Replace the remaining mock-backed project and public-tracking repositories with
strict, trusted Supabase integrations without weakening the Sprint 9 database
authorization model.

This plan does not authorize new SQL, migrations, RPCs, Edge Functions, remote
Supabase commands, or data changes. Step 11.1 changes documentation only.

## 2. Permanent boundaries

- Direct `SELECT` is allowed only for tables and rows already protected by an
  approved RLS policy.
- Every multi-table or state-changing operation must use an existing trusted
  RPC. Flutter must never directly insert, update, upsert, or delete project
  domain rows.
- Flutter must never contain or use `service_role`.
- Backend enum, UUID, date, timestamp, array, join, and JSON values are parsed
  strictly. Unknown or malformed values fail closed with safe Arabic errors.
- RLS and RPC authorization remain authoritative. UI permission gates are only
  usability controls and never replace server checks.
- Internal Auth email and database/Auth implementation details are never shown
  to clients. Authenticated relationship identifiers remain data-layer values
  and are not rendered as user-facing identity.
- `project_team_members.value` remains assignment metadata only. It must never
  become finance, pricing, payment, or reporting data.
- `MockProjectRepository` and `MockTrackingRepository` remain test doubles.
- Finance, payments, Rekaz, notifications, FCM, push, and reminders remain out
  of scope.

## 3. Audited starting point

The normal app still wires:

- `projectRepositoryProvider` → `MockProjectRepository`;
- `trackingRepositoryProvider` → `MockTrackingRepository`.

The database already provides trusted contracts for:

- row-scoped project, team, team-type, stage, closure, and link reads;
- `create_project`;
- `update_project` (working-state basics only; type and status immutable);
- `update_project_stage`;
- `assign_team_roles`;
- `is_available`;
- closure submit, approve, and reject;
- anonymous/authenticated `track_project_by_serial`.

There are no project-domain Edge Functions and no safe contract for manager
reassignment, delivery-link mutation, client review submission, project soft
delete, or manager-safe discovery of assignable staff.

The old planning documents proposed aggregate views (`v_projects`,
`v_closure_requests`, and `v_team`), but no such views exist in migrations.
Sprint 11 must not pretend that they exist.

## 4. Target repository architecture

### 4.1 Read gateway

`SupabaseProjectRepository` should use an injectable gateway around the
authenticated `SupabaseClient`. The gateway may issue multiple RLS-protected
`SELECT` calls to hydrate one project graph:

1. visible `projects` rows;
2. visible `project_stages`, ordered by `stage_order`;
3. visible `project_team_members`;
4. visible `project_team_types` joined to active `photographer_types`;
5. scoped `closure_requests` where requested;
6. scoped `project_links` only for manager/admin link reads.

No read may assume administrator visibility. A photographer legitimately sees
only their own team member row and its types. A manager sees the complete team
for projects they own. An admin sees complete live project graphs.

Because profile RLS does not let an assigned non-admin read the manager's
profile, `managerName` must remain nullable unless it can be derived through an
approved safe contract. The repository must not bypass that boundary.

### 4.2 Write gateway

The write gateway invokes only allowlisted RPC names with exact parameter maps.
It validates scalar UUID returns and re-reads the affected model through RLS.
Caller-supplied identity fields such as `updatedBy`, `submittedBy`, and
`submittedByName` must not be sent when the RPC derives `auth.uid()` and profile
data itself.

### 4.3 Tracking gateway

`SupabaseTrackingRepository.trackBySerial` calls only
`track_project_by_serial(project_serial: text)` and accepts only the exact
client-safe JSON shape. Unknown status values, extra/missing required values,
malformed URLs, or malformed link entries fail safely.

`submitReview` remains unsupported until a trusted anonymous RPC and retained
review schema exist. It must not be implemented as a direct table write.

### 4.4 Error boundary

Repository exceptions should expose a small safe failure vocabulary for Arabic
UI mapping, for example: load failed, invalid data, invalid input, forbidden,
conflict/unavailable, not found, unsupported operation, and generic save failed.
Raw PostgREST messages, SQLSTATE details, URLs, tokens, and payloads must not be
logged or displayed.

## 5. Sequenced implementation

### Step 11.2 — Strict reads and repository foundation

Scope:

- add the project gateway and `SupabaseProjectRepository`;
- add strict parsers for projects, stages, team members/types, and dates;
- hydrate only RLS-visible rows and preserve the deliberate partial team view
  for assigned staff;
- implement visible project list/detail, manager, photographer, completed,
  search, and filter reads;
- keep closure reads disabled or safely partial until the required display-name
  mismatch is resolved;
- verify Data API/table `SELECT` privileges in an owner-controlled environment
  because the migrations define RLS policies but do not explicitly grant table
  privileges;
- retain mock overrides for tests.

Gate:

- malformed UUIDs, enums, dates, timestamps, workflow stages, joins, duplicate
  rows, and unknown catalog values fail closed;
- soft-deleted/inactive projects never appear;
- no write method is enabled merely because reads work.

### Step 11.3 — Project create, basics edit, and stage updates

Scope:

- integrate `create_project`, initially without a team unless Step 11.4's
  assignment-date and candidate-list requirements are satisfied;
- remove client authority over project serial allocation;
- integrate only the supported `update_project` subset: name, client name,
  dates, and notes while preserving the existing type;
- disable UI status overrides and project-type changes in the real flow;
- integrate `update_project_stage`, deriving the actor on the server;
- add UI gates matching `can_add_project`, `can_edit_project`, and
  `can_update_stages`, project ownership/assignment, and working statuses.

Gate:

- real writes are RPC-only;
- working states are exactly `active` and `in_progress`;
- admin behavior follows the RPC's explicit admin bypass; non-admin behavior
  requires both relationship and effective feature permission.

### Step 11.4 — Team catalog, availability, and assignment

Prerequisite backend contract:

- a manager-safe, least-privilege assignable-staff lookup is required. It should
  return only active/non-deleted staff identifiers, display names, active
  photographer types, and availability information needed for assignment. It
  must not expose username, internal email, permissions, leave notes/kinds, or
  unrelated profile data.

Scope after that prerequisite exists:

- replace hardcoded photo-type labels with the active backend catalog;
- collect and preserve a required assignment date for every internal member;
- call `is_available(uid, on_date, exclude_project_id)` or a future batched safe
  candidate RPC; do not query another user's unavailability rows;
- group the Flutter per-type role representation into one backend member with
  multiple `photographer_type_ids` and fan it back out on reads;
- integrate `assign_team_roles` as replace-all, atomic, double-submit protected;
- preserve external members already read from a project; enable creation of new
  external members only when the UX explicitly collects a safe name, optional
  date, and catalog types;
- keep manager reassignment disabled because `set_project_manager` is absent.

Gate:

- backend availability remains authoritative;
- Marketing bypasses project double-booking only, never explicit leave;
- inactive/deleted staff and duplicate internal assignments fail closed;
- assignment metadata is not totalled, reported, or labelled as finance.

### Step 11.5 — Closure workflow and delivery links

Scope:

- resolve the closure display-name mismatch with an approved safe read contract
  or a model adjustment; do not fabricate a submitter name;
- integrate `submit_closure_request`, omitting client-supplied submitter fields;
- integrate `approve_closure_request` and `reject_closure_request`;
- enforce pending-only review and `pending_closure` parent-state UI gates;
- support read-only delivery-link display for owning manager/admin where RLS
  permits it;
- keep add/approve/visibility/soft-delete delivery-link actions disabled until
  trusted RPCs exist.

Gate:

- one pending request per project;
- submit only from `active`/`in_progress` by an assigned permitted caller;
- approve completes the project and all stages; reject returns it to `active`;
- closure URLs/notes never enter audit metadata.

### Step 11.6 — Public tracking, cutover, and security QA

Scope:

- implement `SupabaseTrackingRepository.trackBySerial` with the public RPC;
- keep `submitReview` disabled until `submit_review` exists;
- wire real project/tracking providers only after their supported operations are
  safe; mocks stay explicit in tests;
- add focused parser, exact RPC-body, authorization-gating, partial-RLS-view,
  empty/error/retry, state-transition, and public-data-minimization tests;
- run full Flutter analysis/tests and owner-controlled mobile DEV QA.

Gate:

- public tracking exposes only serial, project/client names, coarse
  `active|done`, and approved/client-visible/live links;
- no UUID, manager/team/value, notes, closure details, audit, permission,
  unavailability, or internal Auth identity reaches the public model;
- malformed and unknown public values fail closed rather than defaulting to an
  internal status.

## 6. Operations held disabled pending contracts

| Operation | Current disposition | Required future contract |
|---|---|---|
| Manager reassignment | Disable real action; retain mock-only tests | authenticated `set_project_manager` RPC with admin/ownership, manager eligibility, live-project/state checks, locking, and audit |
| Assignable staff discovery for managers | Do not use broad profile reads | least-privilege list/availability RPC or security-invoker view with explicit RLS |
| Project delivery-link mutations | Keep coming-soon/read-only | create/update/approve/visibility/soft-delete RPCs with manager/admin gates and URL validation |
| Client review | Keep disabled/mock-only | anon-safe `submit_review` RPC plus retained schema, serial validation, limits, and no project-existence oracle |
| Project soft delete | No UI action | audited admin/authorized-manager RPC with state and relationship handling |
| Status override | Remove/disable in real edit flow | no generic override recommended; add only explicit state-transition RPCs if product approves |
| User unavailability management | Out of project integration | separate attendance/availability contract; no manager access to notes/kind |

## 7. Definition of Sprint 11 completion

Sprint 11 is complete only when every enabled real action has an existing,
tested trusted contract; every unsupported action is visibly disabled; mocks are
used only by tests/previews; strict parsing and safe Arabic failures are covered;
and owner-controlled DEV QA confirms RLS behavior for admin, owning manager,
assigned photographer, Marketing, inactive/deleted staff, and anonymous client.

Production promotion is separate and requires explicit authorization.
