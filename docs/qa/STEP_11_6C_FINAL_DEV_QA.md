# Sprint 11 — Step 11.6C Final DEV QA

## A. Automated closure

### Scope and baseline

Automated closure was performed locally on 2026-08-11 from
`5c39c4e0d97c67d0ea0added85ff608c97943a64` on
`codex/sprint-11-project-integration`.

The complete Sprint 11 plan and every Step 11.1–11.6B QA document were reviewed
before validation. The provider cutover retained the frozen strict-parsing,
RLS, trusted-write, availability, closure-history, assignment-type,
unsupported-operation, and public-data-minimization boundaries.

No live DEV query or mutation was performed. References to migrations being
applied to DEV repeat prior owner-confirmed status only and are not an
independent remote verification by Step 11.6C.

### Automated results

| Gate | Result |
|---|---|
| `flutter test --concurrency=1` | PASS — 433 passed, 0 failed, 0 skipped |
| `flutter analyze` | PASS — `No issues found` |
| `dart format --output=none --set-exit-if-changed lib test` | PASS — 168 files checked, 0 changed |
| `git diff --check` | PASS |
| Production project provider | PASS — `SupabaseProjectRepository(ref.watch(supabaseClientProvider))` |
| Production tracking provider | PASS — `SupabaseTrackingRepository(ref.watch(supabaseClientProvider))` |
| Auth/User providers | PASS — approved `SupabaseAuthRepository` and `SupabaseUserRepository` remain wired |
| Project/tracking mock boundary | PASS — no implicit runtime fallback; tests use explicit provider overrides |
| Project write scan | PASS — trusted RPCs only; no direct Flutter project insert/update/upsert/delete |
| Tracking scan | PASS — only `track_project_by_serial`; no direct or supplementary table access |
| Unsupported-operation scan | PASS — no enabled real action for missing contracts |
| Public minimization scan | PASS — exact safe tracking allowlist; malformed/unknown status rejected |
| RLS partial-view review | PASS — visible team rows are accepted without inferring hidden teammates |
| Automatic retry audit | PASS — no project mutation or tracking repository retry |
| Migration presence review | PASS — all three expected Sprint 11 migrations exist locally and are unchanged |

### Optional iOS simulator compile

The optional compile was attempted because 17 GiB was available and
`flutter doctor -v` reported healthy Xcode 26.6 and CocoaPods 1.16.2.

`flutter build ios --simulator --debug` reached Xcode but failed in the local
simulator `CodeSign` phase. Xcode reported `resource fork, Finder information,
or similar detritus not allowed` on generated Pod frameworks for
`url_launcher_ios`, `shared_preferences_foundation`, and `app_links`.

This is recorded as a local filesystem/toolchain environment failure, separate
from the green Flutter tests and analyzer. No signing setting was changed, no
archive/upload/device installation occurred, and no cache or file cleanup was
performed. Owner mobile QA remains the runtime gate.

### Provider and trusted-contract verification

Normal runtime resolution is fixed to the shared configured Supabase client:

- `authRepositoryProvider` → `SupabaseAuthRepository`;
- `userRepositoryProvider` → `SupabaseUserRepository`;
- `projectRepositoryProvider` → `SupabaseProjectRepository`;
- `trackingRepositoryProvider` → `SupabaseTrackingRepository`.

There is no project/tracking switch based on `kDebugMode`, assertions,
`Platform.environment`, environment name, platform, test detection, failed-real
fallback, or debug build mode. `MockProjectRepository` and
`MockTrackingRepository` remain explicit test doubles.

Project mutations use exactly these trusted RPCs:

| Operation | Contract |
|---|---|
| Create | `create_project` |
| Team replace-all | `assign_team_roles` |
| Basics edit | `update_project` |
| Stage update | `update_project_stage` |
| Closure submit | `submit_closure_request` |
| Closure approve | `approve_closure_request` |
| Closure reject | `reject_closure_request` |

The gateway contains authenticated, RLS-scoped direct SELECTs only for the
approved project graph and management-visible read-only links. No direct
project-domain mutation exists in Flutter. No service-role credential or secret
was found; existing source comments explicitly prohibit it.

### Tracking and public minimization

Public tracking requires no authenticated user and calls only:

```text
track_project_by_serial(project_serial: <trimmed-uppercase-serial>)
```

Malformed input and null RPC results use the same neutral not-found result. A
successful result is accepted only with the exact fields:

- `serial`;
- `projectName`;
- `clientName`;
- status `active` or `done`;
- `approvedLinks`, each containing only `label` and an HTTP(S) `url`.

The strict repository rejects unknown status instead of defaulting it. Real
reads set `message` and `rating` to null. The tracking gateway performs no
project, link, profile, closure, role, permission, or unavailability query.

No public result exposes project/user UUIDs, manager, photographers, team,
assignment value/date, project notes/dates/type/internal status, stages,
closure/rejection/reviewer data, roles, permissions, leave/unavailability,
audit data, username, internal Auth email, or phone.

### RLS partial project graphs

Assigned-staff reads may contain the project, its stages, and only the caller's
own team-member/type rows. The repository hydrates only returned rows and does
not reconstruct hidden identities. Search and filtering remain within the
visible graph. UI summaries and details render the rows supplied under RLS and
do not fabricate teammate placeholders or expose hidden assignment metadata.

Manager/admin views likewise use only rows actually returned under their RLS
scope. Post-write full-team comparisons occur only in authorized management
workflows and do not broaden reads.

### Real operation and state review

- Create uses the real repository, exact project type, server serial/stages,
  server manager rules, atomic `p_members`, explicit assignment dates, and
  UUID-backed catalog types.
- Basics edit sends only name, client, dates, notes, and the unchanged type;
  type/status/manager cannot change and only `active`/`in_progress` is allowed.
- Stage update uses `update_project_stage` on working projects and omits a
  client-supplied actor.
- Team discovery uses the candidate RPC, exact date and exclusion project,
  boolean availability without a reason, multiple UUID-backed types, and
  replace-all `assign_team_roles`. Existing external members are preserved,
  server type membership is authoritative, and clearing the team requires
  confirmation.
- Closure submission is working-state and assigned-permission gated; the server
  derives submitter identity. Review requires pending request plus a
  `pending_closure` parent; retained approved/rejected history remains readable,
  rejection requires a reason, and delivery links remain read-only.
- Tracking remains anonymous, neutral on absence, `active|done` only, approved
  links only, and has no review submission control.

### Unsupported operations

No enabled real UI action exists for:

- manager reassignment;
- project-link create/edit/approve/visibility/delete/restore;
- project soft delete;
- generic project status override;
- client review or rating submission.

`SupabaseProjectRepository.setProjectManager` remains `unsupportedOperation`.
`SupabaseTrackingRepository.submitReview` returns `unsupportedOperation` and
performs zero gateway or Supabase calls.

### Safe errors and retry behavior

Project and tracking failures expose bounded safe Arabic categories. Raw
PostgREST messages, SQLSTATE, details, hints, queries, function/table details,
payloads, tokens, and internal email are not rendered or logged. Unexpected
errors collapse to safe load/save failures.

Create, edit, stage, team assignment, closure submit, closure approve, and
closure reject each invoke their mutation once and never retry automatically.
Tracking does not retry automatically. Read retry controls invalidate/reinvoke
only through an explicit user action.

### Migration consistency and scope

The following expected migrations are present locally and unchanged:

- `20260809180755_assignable_project_staff_rpc.sql`;
- `20260810171930_closure_request_read_rpc.sql`;
- `20260810204812_project_team_type_integrity_hardening.sql`.

No migration, SQL/RLS/RPC definition, Edge Function, remote Supabase state, DEV
data/account, or Production system was changed or accessed. Finance, Payments,
Rekaz, Notifications, FCM, push, and reminders remain excluded. `AGENTS.md` and
`docs/engineering` remain untouched.

## B. Owner-controlled DEV/mobile QA

All checks below are intentionally unchecked. The owner must use disposable
DEV projects/identities where state changes are required, avoid permanently
damaging real accounts, and never use Production.

### Anonymous client

| Done | Manual DEV scenario |
|---|---|
| [ ] | Launch tracking without login. |
| [ ] | A valid active serial loads only project/client public data. |
| [ ] | A valid completed serial returns `done`. |
| [ ] | Only approved, client-visible, active links appear. |
| [ ] | A project with no public links shows `جاري الإبداع ⏳`. |
| [ ] | An invalid serial shows the neutral not-found UX. |
| [ ] | An unknown serial shows the same neutral not-found UX. |
| [ ] | No UUID, team, manager, notes, or other internal data is visible. |
| [ ] | No review/rating submission control is visible. |
| [ ] | A network failure produces a safe explicit retry. |

### Admin

| Done | Manual DEV scenario |
|---|---|
| [ ] | Log in successfully. |
| [ ] | Project list reads real DEV data. |
| [ ] | Open a real visible project. |
| [ ] | Create a disposable project with no team. |
| [ ] | Create a disposable project with a valid initial team. |
| [ ] | Manager assignment rules are respected. |
| [ ] | Edit only allowed basic fields. |
| [ ] | Project type is immutable. |
| [ ] | Project status is immutable. |
| [ ] | Manager reassignment is unavailable. |
| [ ] | Update a stage on a working project. |
| [ ] | Assign and reassign a team. |
| [ ] | Assign multiple photographer types. |
| [ ] | Assignment date is required. |
| [ ] | An unavailable photographer is disabled without a reason. |
| [ ] | Clear-team confirmation works before mutation. |
| [ ] | Closure history, including retained decisions, is visible. |
| [ ] | Approve a pending closure. |
| [ ] | Reject a pending closure with a nonblank reason. |
| [ ] | Read management-visible project links. |
| [ ] | No project-link mutation action is available. |
| [ ] | No raw backend error is displayed. |

### Owning Manager

| Done | Manual DEV scenario |
|---|---|
| [ ] | Sees only permitted projects. |
| [ ] | Sees the full team of an owned project as allowed by RLS. |
| [ ] | Can create only when the effective permission permits. |
| [ ] | Can edit only an owned working project when permitted. |
| [ ] | Cannot change project type, status, or manager. |
| [ ] | Can update stages only when permitted. |
| [ ] | Candidate list exposes only safe staff fields. |
| [ ] | Unavailable candidates expose no reason. |
| [ ] | Team assignment date is preserved. |
| [ ] | Selected types are constrained to the candidate catalog. |
| [ ] | A type the internal user does not hold cannot be assigned. |
| [ ] | Closure review works only on an owned project when permitted. |
| [ ] | Project links are read-only. |
| [ ] | An unrelated project remains inaccessible. |

### Assigned Photographer

| Done | Manual DEV scenario |
|---|---|
| [ ] | Sees an assigned project. |
| [ ] | Sees the project stages. |
| [ ] | Own-row/type-only team visibility renders correctly. |
| [ ] | Hidden teammate assignment metadata is not visible. |
| [ ] | No fake teammate placeholder is displayed. |
| [ ] | Can submit closure only with `can_request_closure`. |
| [ ] | Submitter identity is not editable. |
| [ ] | Submission changes the project to pending closure. |
| [ ] | Cannot approve/reject unless the backend role actually allows it. |
| [ ] | Manager/admin-only link management data is not exposed. |

### Marketing

Use an active Marketing account with relevant project/team permissions.

| Done | Manual DEV scenario |
|---|---|
| [ ] | Project access follows assignment and effective-permission rules. |
| [ ] | Same-date project double booking is allowed. |
| [ ] | Explicit leave/unavailability still blocks assignment. |
| [ ] | The unavailable reason is not exposed. |
| [ ] | Marketing is never treated as Designer. |
| [ ] | Photographer-type catalog remains independent of Marketing role. |

### Inactive/deleted staff

Use disposable DEV identities or restore all owner-controlled state afterward.

| Done | Manual DEV scenario |
|---|---|
| [ ] | Inactive/deleted staff are absent from candidate options. |
| [ ] | Availability fails closed. |
| [ ] | Team assignment cannot add inactive/deleted internal staff. |
| [ ] | A disabled/deleted caller cannot use protected project actions. |
| [ ] | Retained historical closure submitter names remain readable where the contract permits. |

### Authorization isolation

| Done | Manual DEV scenario |
|---|---|
| [ ] | An unrelated manager cannot access another manager's protected project actions. |
| [ ] | An unrelated manager cannot use `excludeProjectId` as an availability bypass. |
| [ ] | A photographer cannot see another user's leave notes, kind, or date range. |
| [ ] | A photographer cannot read teammate value metadata through hidden RLS rows. |
| [ ] | `anon` cannot directly read projects, project links, or profiles. |
| [ ] | Link, closure, and project writes remain inaccessible except through trusted contracts. |

### Mobile/iPad runtime QA

Record the actual target before testing:

- Device/model: ______________________________
- OS/version: _________________________________
- App build/commit: ___________________________

| Done | Manual runtime scenario |
|---|---|
| [ ] | Cold launch. |
| [ ] | Login. |
| [ ] | Logout and login again. |
| [ ] | Arabic RTL layout. |
| [ ] | Manager dashboard. |
| [ ] | Project list. |
| [ ] | Project details. |
| [ ] | Add project. |
| [ ] | Edit basics. |
| [ ] | Assignment date picker. |
| [ ] | Candidate loading and explicit retry. |
| [ ] | Multiple photographer-type selection. |
| [ ] | Team save. |
| [ ] | Stage update. |
| [ ] | Closure submit. |
| [ ] | Closure review. |
| [ ] | Project links remain read-only. |
| [ ] | Anonymous tracking. |
| [ ] | App restart and session recovery. |
| [ ] | Loading, error, and empty states. |
| [ ] | No crashes. |
| [ ] | No stuck loading state. |
| [ ] | Repeated taps do not create duplicate submissions. |

## Completion decision

**Sprint 11 completion decision: PENDING OWNER DEV QA**
