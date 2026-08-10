# Sprint 11 — Step 11.5A Closure Read Backend QA

## Scope and rationale

The existing `closure_requests` SELECT policy safely scopes rows, but the
Flutter `ClosureRequestModel` also requires non-null project and submitter
display names. Those names are not stored on the closure row, and ordinary
profile RLS cannot reliably hydrate a retained submitter after team membership
changes. Step 11.5A therefore prepares one least-privilege SECURITY DEFINER read
boundary without broadening table RLS or profile access.

This step is local migration preparation only. The migration was not applied to
DEV, no remote Supabase command was run, no Flutter integration or closure
mutation was added, and Production was untouched.

## Function contract

Exact signature:

```sql
public.list_visible_closure_requests()
returns jsonb
```

The function is `STABLE`, `SECURITY DEFINER`, uses `SET search_path = ''`, has
no parameters or caller-supplied identity, and schema-qualifies every referenced
relation and helper. It contains no dynamic SQL and no write statement.

An absent `auth.uid()` fails with SQLSTATE `28000`. An authenticated caller
without an active, non-deleted profile fails with `42501`. An active caller is
allowed to invoke the scoped read; unrelated or hidden rows are filtered and
therefore indistinguishable from absence.

## Exact visibility predicate

A request is returned only when its parent project has `is_active = true` and
`deleted_at is null`, and one of these conditions holds:

1. the caller UUID equals the project's owning `manager_id`;
2. the caller UUID equals the request's `submitted_by` UUID; or
3. `public.is_admin()` confirms the active caller holds the active admin role.

This explicitly reproduces the existing closure SELECT intent inside the
SECURITY DEFINER function. It does not grant visibility to unrelated managers,
other assigned staff, Marketing, or other photographers. The function does not
depend on RLS bypass as authorization.

## Exact result

The function always returns a JSON array, including `[]` when no rows qualify.
Each item contains exactly:

```json
{
  "id": "<closure uuid>",
  "project_id": "<project uuid>",
  "project_name": "<project display name>",
  "submitted_by": "<profile uuid>",
  "submitted_by_name": "<submitter display name>",
  "created_at": "<timestamptz>",
  "report_file_url": "<string|null>",
  "delivery_link": "<string|null>",
  "notes": "<string|null>",
  "status": "pending|approved|rejected",
  "reject_reason": "<string|null>",
  "reviewed_at": "<timestamptz|null>"
}
```

All three closure statuses are retained. Results are ordered by `created_at`
descending and then `id` for a deterministic tie break. Approved and rejected
history remains readable under the same visibility predicate while the parent
project remains live.

## Display-name behavior

`project_name` is derived only from `projects.name`.
`submitted_by_name` is derived only from `profiles.full_name` using the
request's `submitted_by` foreign key. No placeholder or fabricated name is
used.

The actual schema soft-deletes profiles and declares
`closure_requests.submitted_by -> profiles.id ON DELETE RESTRICT`. A disabled or
soft-deleted submitter therefore retains the profile row and historical display
name. The function deliberately does not filter the submitter profile by active
or deleted state. Its inner join requires that profile row and fails closed by
omitting a row if referential integrity were ever violated; the declared
foreign key prevents that state during normal operation.

Normal `profiles` SELECT RLS is unchanged. SECURITY DEFINER is used only for
this scoped name derivation and never returns other profile fields.

## Deliberately excluded data

The function returns no username, internal Auth email, phone, roles,
permissions, reviewer identity, audit data, manager identity, team members,
project notes/dates/status/serial, assignment values, leave/unavailability
information, password flags, or non-allowlisted timestamps. It does not read or
expose `audit_logs`; reviewer identity remains there only.

## Privilege and static verification

The exact no-argument signature explicitly revokes all privileges from
`PUBLIC` and `anon`, then grants execute only to `authenticated`. No table grant
or default-privilege change is present.

Repository inspection found no established migration SQL execution-test
framework, so no new framework was invented and no runtime SQL execution is
claimed. Static review confirmed:

- exact name/signature and JSON return type;
- `SECURITY DEFINER`, `STABLE`, and empty search path;
- explicit authentication and active-caller gates;
- exact live-project manager/submitter/admin visibility predicate;
- exact output allowlist and all three closure statuses;
- project/profile name derivation and deterministic ordering;
- empty-array result behavior;
- `PUBLIC`/`anon` revocation and authenticated-only grant;
- no table grants, dynamic SQL, or write SQL;
- no modification to existing closure/tracking functions, policies, or project
  link contracts.

## Boundary confirmation

- Migration prepared locally only; DEV apply remains pending owner action.
- No existing migration, closure RPC, RLS policy, or Edge Function changed.
- No Flutter runtime file or provider changed; Step 11.5B is not started.
- No project-link mutation or client-review contract was added.
- No DEV data/account or Production action occurred.
- `AGENTS.md` and `docs/engineering` remain untouched.
