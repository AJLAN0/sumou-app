# Step 11.2 — Project reads DEV QA

**Scope:** Sprint 11 Step 11.2 only

**Branch:** `codex/sprint-11-project-integration`

**Baseline:** `dfd866745ed3b1941544259de995704cb632cfe4`

## Implemented scope

- Added a safe typed project failure contract with Arabic UI messages. Raw
  PostgREST, SQL, query, payload, and authentication diagnostics are not
  retained by the exception.
- Added an injectable authenticated project gateway with explicit-column,
  SELECT-only access to the existing RLS-protected `projects`,
  `project_stages`, `project_team_members`, `project_team_types`, active
  `photographer_types`, and RLS-visible `profiles` rows.
- Added `SupabaseProjectRepository` read implementations for visible project
  list/detail, manager, photographer, completed, search, and typed filters.
- Hydration begins with caller-visible projects and never infers hidden team or
  profile rows. Manager names remain null when profile RLS does not return the
  profile. Team `personName` is accepted only from a visible, non-null team row;
  hidden teammates remain absent and are never reconstructed from profiles.
- One backend member with multiple active photographer types is fanned out into
  the current Flutter per-type model. Member-level assignment `value` metadata
  is attached once so fan-out cannot turn it into a duplicated total. It is not
  labelled, calculated, or exposed as finance.
- PostgreSQL `date` values are parsed as local calendar dates without timezone
  conversion. `timestamptz` values require an explicit offset and are normalized
  to UTC.
- Strict parsing rejects malformed identifiers, serial/type mismatches, enum
  values, dates, timestamps, joins, workflow shapes, stage orders, duplicates,
  inactive catalog rows, and unexpected parent relationships. Inactive and
  soft-deleted project rows are excluded.
- Every write and closure method remains a safe unsupported operation and
  performs no gateway call.

## Provider boundary

`projectRepositoryProvider` still returns `MockProjectRepository`. The normal
application has not been cut over to this real repository; that remains Step
11.6 after the approved write integrations and QA gates are complete.

`MockProjectRepository` remains unchanged and available to existing tests and
previews. `TrackingRepository` was not implemented or modified.

## Automated verification

The final Step 11.2 verification runs:

- `git diff --check`
- `dart format --output=none --set-exit-if-changed lib test`
- `flutter analyze`
- focused Flutter tests for the Supabase project repository, existing mock
  repositories, and project models

The focused repository coverage includes empty results, strict graph parsing,
canonical three/seven-stage ordering, multiple types, external members, partial
RLS visibility, hidden profile names, exact enums, malformed values, duplicates,
soft deletion, safe query failure mapping, legitimate not-found, scoped local
filtering/search, and unsupported write isolation.

Final results:

- `git diff --check`: passed.
- Dart formatting: 161 files checked, 0 changes required.
- `flutter analyze --no-pub`: no issues found.
- Focused Flutter tests: **44 passed** across the new Supabase project
  repository tests and the existing repository/project-model regression tests.

## Real DEV QA status

Real DEV read QA is **pending**, not passed. The provider is deliberately not
cut over in Step 11.2, and no owner-authorized live read test was requested.

The current migrations define project SELECT RLS policies but do not explicitly
grant table SELECT privileges. Supabase's 2026 Data API exposure change makes
grants a separate prerequisite from RLS. The owner must verify the DEV Data API
settings and effective `authenticated` SELECT privileges before Step 11.6 or an
explicit owner-controlled DEV test. No grant or policy is added in this step.

When the owner authorizes real DEV QA, use an existing active account and
existing data only. Verify admin complete graphs, owning-manager complete team
graphs, assigned-staff own-row-only graphs, hidden manager names, empty visible
results, and legitimate not-found behavior without modifying data.

## Security and environment confirmation

- No project create/update/assignment/stage/closure write was enabled.
- No migration, RLS policy, RPC, or Edge Function was changed.
- No Supabase remote command was run.
- No DEV data or account was created, edited, or deleted.
- Production was untouched.
- `AGENTS.md` and `docs/engineering` were not modified.
