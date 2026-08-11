# Sprint 11 — Step 11.4C Team Assignment QA

## Scope and environment

Step 11.4C integrates the existing trusted `assign_team_roles` contract into
the Flutter repository and the existing manager/admin assignment flows. It also
makes the existing create-project team step compatible with the atomic
`create_project(p_members)` contract.

The normal `projectRepositoryProvider` remains `MockProjectRepository`; real
provider cutover remains Step 11.6. No remote Supabase command was run, no DEV
data or account was changed, live DEV mutation QA is not claimed, and
Production was untouched.

## Trusted mutation contract

`ProjectGateway.assignTeamRoles` invokes `assign_team_roles` exactly once with
exactly:

```json
{
  "p_project_id": "<project uuid>",
  "p_members": [
    {
      "user_id": "<internal user uuid or null>",
      "person_name": "<null for internal, preserved name for external>",
      "value": 0,
      "date": "YYYY-MM-DD or null for an external member",
      "photographer_type_ids": ["<type uuid>"]
    }
  ]
}
```

One member object represents one person and contains every selected type UUID.
The repository does not emit one member per type. Internal user IDs and type
IDs are deduplicated, values must be finite, and internal assignment dates are
mandatory. The value is treated only as opaque assignment metadata and is not
summed, reported, or labelled as finance.

The gateway contains no direct insert, update, upsert, or delete operation, no
service role, and no retry. Safe mutation mappings are: `28000` to
`notAuthenticated`, `42501` to `forbidden`, `22023` to `invalidInput`, `P0001`
and assignment `P0002` to `unavailable`, and unexpected SDK/network/server
failures to `saveFailed`. Raw backend diagnostics are not retained or shown.

## Date and candidate behavior

- Every internal member has an explicit local calendar-midnight date.
- Dates serialize from calendar components as `YYYY-MM-DD` without timezone
  conversion and are not constrained to the project date range.
- Existing-project discovery passes the project UUID as
  `excludeProjectId`; creation passes null.
- Candidate preflight is grouped by unique assignment date, with at most one
  `list_assignable_project_staff` call for all internal members on that date.
- Flutter uses the backend `isAvailable` value as authoritative, displays only
  a generic unavailable state, and does not infer Marketing, leave, booking, or
  conflict rules.
- A disappeared/unavailable candidate, missing returned type, duplicate type,
  malformed date, or invalid identifier fails closed before mutation. The
  mutation RPC performs the authoritative atomic availability recheck for
  race protection.

## Catalog-driven UI

The manager and admin team screens now share the same mobile assignment flow.
Candidates come only from `getAssignableProjectStaff`; selectable type UUIDs,
codes, and Arabic labels come only from each candidate's returned catalog.
Multiple types per internal member are supported. The previous hardcoded role
labels and local workload/unavailability reasons are absent.

Changing an assignment date reloads the candidate contract and revalidates the
selection. Stale unavailable selections are flagged and cannot be saved.
Loading, retry, safe-error, save-loading, double-submit, and clear-team
confirmation states are covered. Manager reassignment is absent from the real
team flow because no trusted backend contract exists.

## Replace-all and post-write verification

Before mutation, the repository strictly loads the project and permits only
`active` or `in_progress`. It preserves persisted external members when
replacing the internal team. External names, nullable dates, values, and type
UUID/code metadata round-trip without reconstructing IDs from Arabic labels.
Existing external members are visible and read-only; creation of new external
members remains deferred.

After the RPC, the scalar result must exactly equal the project UUID. The
repository re-reads through RLS and compares normalized member/type sets
without depending on row order or regenerated association IDs. It also verifies
that serial, project type/status, manager, basics, and stages did not change.
Contradictory or malformed state fails as `invalidData`.

## Initial create behavior

The existing create-project team step now requires an assignment date before
candidate discovery, uses null project exclusion, displays backend catalog
types, disables unavailable candidates, supports multiple types, and passes a
strictly validated non-empty `p_members` array through the existing atomic
`create_project` RPC. Empty-team creation remains valid. Flutter does not
generate or send a project serial.

## Residual backend contract limitation

The current `_apply_project_team` contract:

1. accepts an empty `photographer_type_ids` array;
2. validates that referenced photographer-type catalog rows are active;
3. does not enforce that every selected type for an internal user belongs to
   that user's `user_photographer_types` rows.

Official Flutter constrains internal choices through
`list_assignable_project_staff`, but client-side constraint is not equivalent
to server-side enforcement. This limitation requires explicit backend
hardening or documented owner acceptance before the Step 11.6 real-provider
cutover.

## Automated verification

The focused checks cover exact RPC/payload behavior, date serialization,
normalization, unique-date preflight, safe failures/no retry, external-member
preservation, post-write verification, provider isolation, manager/admin team
UI, create-team compatibility, unavailable secrecy, date revalidation,
multiple catalog types, loading guards, and clear-team confirmation.

Final verification passed:

- `git diff --check`;
- `dart format --output=none --set-exit-if-changed lib test` with zero changes;
- full `flutter analyze` with no issues;
- all 121 tests in the eight focused repository, model, create, manager-team,
  admin-team, and project-details test files.

## Boundary confirmation

- No migration or existing SQL/RLS/RPC definition changed.
- No Edge Function, closure method, tracking flow, or Step 11.5 work changed.
- No remote Supabase command or DEV data/account action occurred.
- `projectRepositoryProvider` remains `MockProjectRepository`.
- `AGENTS.md` and `docs/engineering` remain untouched.
- Production remains untouched.
