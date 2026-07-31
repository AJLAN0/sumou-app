# Sprint 11 — Step 11.3 Project Writes DEV QA

## Scope

Step 11.3 integrates the existing trusted project mutation contracts inside
`SupabaseProjectRepository` only. The normal application provider remains
`MockProjectRepository`; no Flutter project screen is connected to these real
writes in this step.

## Integrated contracts

All calls use the authenticated `SupabaseClient` through the narrow,
fakeable `ProjectGateway`. No caller identity, service role, or direct table
mutation is used.

| Repository operation | Trusted RPC | Exact arguments |
| --- | --- | --- |
| `createProject` | `create_project` | `p_name`, `p_client_name`, `p_type`, `p_start_date`, `p_end_date`, `p_notes`, `p_manager_id`, `p_members: []` |
| `updateProjectBasics` | `update_project` | `p_project_id`, `p_name`, `p_client_name`, existing `p_type`, `p_start_date`, `p_end_date`, `p_notes` |
| `updateProjectStage` | `update_project_stage` | `p_project_id`, `p_stage_id`, `p_notes` |

The backend remains authoritative for project serials, initial stages, project
status, timestamps, stage updater identity, authorization, and state gates.
Each mutation is called at most once. The repository then performs an
RLS-scoped re-read and fails closed if the returned UUID or persisted result
contradicts the requested contract.

## Validation and safe failures

- Names and client names must be nonblank after trimming.
- Project, manager, and stage identifiers must be UUIDs.
- Project dates must be date-only values and the end date cannot precede the
  start date.
- Blank notes become `null`.
- A client-supplied serial is rejected before the create RPC.
- A nonempty initial team remains unsupported and is rejected before the create
  RPC.
- Basic edits require an existing `active` or `in_progress` project and cannot
  change its type or status.
- Stage updates require an existing working project and a stage belonging to
  that project.
- `28000` maps to `notAuthenticated`, `42501` to `forbidden`, `22023` to
  `invalidInput`, and `P0001` to `unavailable`.
- `P0002` maps to `unavailable` for create and `notFound` for update/stage.
- Malformed or contradictory results map to `invalidData`; unexpected SDK,
  network, or server failures map to `saveFailed`.
- Backend diagnostics, tokens, internal Auth email, and request payloads are not
  logged or exposed through errors.

## Unsupported operations retained

These operations still fail with `unsupportedOperation` and perform no
mutation call:

- manager reassignment (`setProjectManager`)
- team replacement (`assignTeamRoles`)
- closure request list, submit, approve, and reject

Tracking repositories and client tracking are unchanged.

## Automated verification

- `git diff --check`: passed
- `dart format --output=none --set-exit-if-changed lib test`: passed
  (`161` files checked, `0` changed)
- `flutter analyze`: passed with no issues
- focused Flutter tests: `62` passed

Focused coverage includes exact RPC maps, omitted unsupported fields, strict
input/result validation, post-write invariants, safe error mapping, no write
retry, unsupported-operation zero calls, static mutation boundaries, provider
wiring, existing read parsing, repository compatibility, and project model
compatibility.

## Real DEV QA status

No live DEV create, edit, or stage write was attempted. Real DEV QA is deferred
until the provider cutover or a separate owner-controlled test with approved DEV
accounts and data. This document does not claim live mutation success.

## Scope confirmation

- No migration, RLS policy, RPC SQL, or Edge Function was changed.
- No Supabase remote command was run.
- No DEV account or data was created, edited, or deleted.
- Production was untouched.
- Step 11.4 was not started.
