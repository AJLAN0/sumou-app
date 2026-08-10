# Sprint 11 — Step 11.5B Closure Workflow QA

## Scope

Step 11.5B integrates the approved closure workflow and management-visible,
read-only project links into the Flutter repository and existing screens. The
owner applied `20260810171930_closure_request_read_rpc.sql` to DEV before this
work. No migration, SQL contract, RLS policy, Edge Function, remote Supabase
state, DEV data/account, or Production system was changed by this step.

`projectRepositoryProvider` remains `MockProjectRepository`; real-provider
cutover is deferred to Step 11.6.

## Exact closure contracts

The authenticated gateway consumes exactly four closure contracts:

1. `list_visible_closure_requests()` with no arguments;
2. `submit_closure_request` with `p_project_id`, `p_delivery_link`,
   `p_report_file_url`, and `p_notes`;
3. `approve_closure_request` with `p_request_id`;
4. `reject_closure_request` with `p_request_id` and trimmed `p_reason`.

The real repository never sends `submittedBy`, `submittedByName`, a caller
UUID, or a status. The submitter identity remains derived from `auth.uid()` by
the trusted backend. There is no automatic retry for reads or mutations.

## Strict closure hydration

The read RPC must return an array. Every item must contain exactly:

- `id`;
- `project_id`;
- `project_name`;
- `submitted_by`;
- `submitted_by_name`;
- `created_at`;
- `report_file_url`;
- `delivery_link`;
- `notes`;
- `status`;
- `reject_reason`;
- `reviewed_at`.

Parsing validates UUIDs, nonblank stored display names, timezone-bearing valid
timestamps, nullable string types, HTTP(S) delivery URLs, the exact three
status values, and unique closure IDs. Missing or additional keys fail closed.
Backend ordering is preserved.

State invariants also fail closed:

- pending: no `reviewed_at` or `reject_reason`;
- approved: `reviewed_at` required and no `reject_reason`;
- rejected: `reviewed_at` and a nonblank `reject_reason` required.

No project or submitter display name is fabricated. Approved and rejected
history remains in manager, photographer, and admin project views; only a
pending request on a `pending_closure` project exposes review actions.

## Mutation verification

Submission accepts only a strict project UUID, normalizes blank optional text
to null, and accepts a delivery link only when it is a trimmed HTTP(S) URL.
After one RPC call, the repository requires the exact returned UUID, re-reads
the authoritative closure list, verifies the pending request and normalized
fields, then re-reads the project and requires `pendingClosure`.

Approval first requires a visible pending request. After one RPC call, the
repository requires the same UUID, an approved hydrated request with a review
timestamp and no rejection reason, and a completed parent project whose every
stage is done.

Rejection first requires a visible pending request and a trimmed nonblank
reason. After one RPC call, it requires the same UUID, a rejected hydrated
request with the exact reason and review timestamp, and an active parent
project.

Contradictory post-write state maps to `invalidData`. Backend authorization,
validation, availability, missing/race, SDK, network, and server failures map
to safe repository categories without retaining SQLSTATE text, PostgREST
messages, details, hints, SQL, payloads, tokens, or internal email.

## Closure UI

The existing submission screen now:

- exposes no caller-identity input;
- allows submission only for `active` or `in_progress` projects;
- validates the delivery URL;
- shows loading and prevents duplicate submissions;
- surfaces safe Arabic repository errors.

Manager/admin review actions require a pending request and a
`pending_closure` project. Admin is allowed by the existing server contract;
an owning manager also requires `can_approve_closure`. Approval and rejection
are guarded against double submission, and rejection requires a nonblank
reason. The backend remains authoritative for every permission and state gate.

## Read-only project links

`ProjectDeliveryLink` contains only:

- `id`, `projectId`, `label`, and `url`;
- `isApproved`, `isClientVisible`, and `isActive`;
- `createdAt` and nullable `deletedAt`.

The gateway performs one authenticated RLS-scoped `project_links` SELECT with
the explicit corresponding columns. It validates exact row shape, UUIDs,
nonblank labels, HTTP(S) URLs, booleans, timestamps, parent-project identity,
and unique link IDs. Unapproved, internal, inactive, and soft-deleted rows are
retained when RLS returns them.

Manager and admin project details show these states as read-only metadata.
There are no add, edit, approve, visibility, delete, restore, insert, update,
upsert, or delete controls/contracts. Photographer closure submission
continues to use `closure_requests.delivery_link`. Project-link mutations and
client reviews remain unsupported.

## Automated verification

Verification completed locally:

- `dart format` completed and the required format check is clean;
- full `flutter analyze` reports no issues;
- all 180 tests in the 13 focused repository, model, existing Step 11 team,
  closure, manager/admin detail, and photographer/manager project test files
  pass with `--concurrency=1`;
- repository tests cover exact gateway methods/payloads, strict parsing,
  state invariants, post-write verification, failure mapping, no retry,
  immutable results, explicit link columns, and the no-write boundary;
- widget tests cover loading/error states, URL input, no identity control,
  double-submit guards, manager/admin review, required rejection reason,
  retained history, and read-only link states.

Live DEV mutation QA is not claimed. It requires suitable DEV accounts and
projects and remains an owner-run check.

## Boundary confirmation

- `projectRepositoryProvider` remains mock-backed.
- Step 11.6 was not started.
- The Step 11.4 residual team backend limitation was not changed.
- No client tracking or review integration was added.
- No migration, existing SQL/RLS/RPC definition, or Edge Function changed.
- No remote Supabase command or DEV data/account action occurred.
- `AGENTS.md` and `docs/engineering` remain untouched.
- Production remains untouched.
