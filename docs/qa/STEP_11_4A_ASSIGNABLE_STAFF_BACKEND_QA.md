# Sprint 11 — Step 11.4A Assignable Staff Backend QA

## Scope and deployment status

Step 11.4A prepares one local migration containing the manager-safe staff
discovery contract required before real team assignment can be integrated.

- Migration: `20260809180755_assignable_project_staff_rpc.sql`
- Prepared locally only; it has not been applied to DEV.
- No live or local database execution was claimed. No local Supabase PostgreSQL
  listener was present on the standard project port during verification.
- Flutter integration, `assign_team_roles` integration, Step 11.4B, and Step
  11.4C have not started.

## Function contract

```sql
public.list_assignable_project_staff(
  p_on_date date,
  p_exclude_project_id uuid default null
) returns jsonb
```

The function is `STABLE`, `SECURITY DEFINER`, uses an empty `search_path`,
contains no dynamic SQL, and schema-qualifies every referenced relation and
application function.

Execution is revoked from `PUBLIC` and `anon`, then granted only to
`authenticated`. It accepts no actor/caller identity parameter and contains no
service-role path.

## Authorization

The function derives the caller from `auth.uid()` and applies these gates in
order:

1. a missing authenticated UID fails with SQLSTATE `28000`;
2. `public.is_active_user()` must confirm a live, non-deleted caller;
3. the caller must be an active admin through `public.is_admin()` or hold the
   effective `can_assign_photographers` permission through
   `public.has_feature(...)`;
4. authorization failures use SQLSTATE `42501`.

No role rows or permission rows are returned.

## Argument and exclusion protection

- `p_on_date` is mandatory. `null` fails with SQLSTATE `22023`; the function
  never substitutes `current_date`.
- A null `p_exclude_project_id` supports candidate discovery before a project
  exists.
- A non-null exclusion is accepted only when one predicate confirms the project
  is active, not soft-deleted, in the team-editable `active` or `in_progress`
  state, and either owned by the caller or accessed by an admin.
- Missing, inaccessible, unrelated, deleted, rejected, closure-pending, and
  completed projects all fail through the same neutral SQLSTATE `P0002`
  response. The contract does not reveal which condition failed.

This prevents a permission holder from excluding an unrelated project to hide
that project's booking conflict.

## Candidate eligibility

Every returned candidate:

- is an internal `profiles` row with `is_active = true` and `deleted_at is
  null`;
- has at least one `user_photographer_types` association;
- is associated with an active `photographer_types` catalog row;
- has at least one currently allowlisted catalog code: `photo`, `video`,
  `instagram`, or `design`.

A distinct typed source prevents duplicate type entries. Candidates without an
eligible active type never enter the grouped result, so an empty
`photographer_types` array cannot be returned.

## Exact result allowlist

The result is always a JSON array; no candidates produces `[]`, never `null`.
Candidates are ordered by trimmed/lowercased display name using deterministic
`C` collation, then user UUID. Types are ordered by catalog code, then type UUID.

Each candidate contains exactly:

```json
{
  "user_id": "<uuid>",
  "full_name": "<display name>",
  "photographer_types": [
    {
      "id": "<uuid>",
      "code": "photo|video|instagram|design",
      "name_ar": "<Arabic catalog name>"
    }
  ],
  "is_available": true
}
```

`is_available` may be `true` or `false`. The function calls
`public.is_available(candidate_user_id, p_on_date, p_exclude_project_id)` for
the authoritative value and does not duplicate its Riyadh-day, leave,
Marketing, project-status, or inactive-staff rules.

## Deliberately excluded data

The result contains no username, Auth/internal/public/personal email, phone,
roles, permissions, password-change flag, active/deleted flags, leave kind,
leave notes, leave range, conflicting project identity, project/workload count,
assignment value, audit data, or timestamps. It returns no reason explaining an
unavailable result.

No profile SELECT policy, manager access to `user_unavailability`, table grant,
RLS policy, internal-function grant, or broader database object was added.

## Static verification

The repository has no established migration-contract test framework, so no new
testing framework or brittle source-text test was introduced. The migration was
reviewed statically for every required contract:

- exact function name, parameter types/default, and `jsonb` return;
- one externally callable function only;
- `STABLE`, `SECURITY DEFINER`, and `SET search_path = ''`;
- fully qualified relations/helpers and no dynamic SQL;
- authenticated UID, active-user, admin/effective-permission gates;
- required-date validation and exact SQLSTATE categories;
- neutral exclusion-project ownership/live/working-state predicate;
- active/non-deleted profile and active photographer-type filters;
- distinct types and deterministic candidate/type ordering;
- exact outer and nested JSON key allowlists;
- `[]` fallback and authoritative `public.is_available` call;
- explicit `PUBLIC`/`anon` revocation and authenticated-only grant;
- absence of prohibited identity, leave, conflict, assignment, finance,
  payment, Rekaz, notification, FCM, push, reminder, and audit fields;
- absence of tables, views, enums, columns, triggers, policies, data writes,
  default-privilege changes, and existing-function modifications.

`git diff --check` passed. Final Git status, name-only, and stat review confirmed
that the staged change contains only this new migration, this QA document, and
the narrow Step 11.4 plan status update. `AGENTS.md` remains untracked and
unstaged.

## Environment confirmation

- No Supabase remote command or remote SQL was run.
- The migration was not applied to DEV.
- No DEV data or account was created, edited, or deleted.
- No existing migration, RPC, RLS policy, or Edge Function was changed.
- No Flutter runtime, repository, gateway, provider, or UI file was changed.
- Production was untouched.
