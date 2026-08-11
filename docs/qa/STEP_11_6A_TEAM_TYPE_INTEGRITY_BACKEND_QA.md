# Sprint 11 — Step 11.6A Team Type Integrity Backend QA

## Scope and residual limitation

Step 11.6A prepares one forward-only migration that hardens only the existing
internal helper:

```sql
public._apply_project_team(p_project_id uuid, p_members jsonb)
returns integer
```

The previous contract accepted a member whose `photographer_type_ids` key was
missing, null, or an empty array. It also checked that selected catalog rows
were active but did not prove that an internal user actually held each selected
type through `public.user_photographer_types`.

The migration is:

`20260810204812_project_team_type_integrity_hardening.sql`

It was generated with the local Supabase CLI and prepared locally only. It was
not applied to DEV or any remote database.

## Preserved contract

The function remains `SECURITY DEFINER`, `VOLATILE`, uses
`SET search_path = ''`, and keeps the same signature and `integer` result. The
body starts from the latest repository source rather than a reconstructed
implementation.

The following behavior is unchanged:

- `p_members is null` normalizes to the outer empty array;
- the outer payload must be a JSON array;
- the entire proposed team is validated before replacement;
- internal UUID, duplicate-user, and assignment-date checks;
- external nonblank name and optional date support;
- numeric assignment-value metadata semantics;
- deterministic internal profile locking;
- active/non-deleted internal profile verification;
- the authoritative post-lock `public.is_available` check;
- replace-all deletion and insertion after successful validation;
- server-derived internal `person_name`;
- `project_team_members` and `project_team_types` inserts;
- one `project.team.assign` audit entry containing only `member_count`.

No booking, Marketing, leave, assignment-date, external-member, caller, or
audit rule changed. The public signatures and privileges of `create_project`,
`assign_team_roles`, and `is_available` are untouched.

## Empty-team and member-type distinction

An empty outer team remains a valid clear-team operation:

```json
[]
```

Every proposed member must explicitly contain a non-empty
`photographer_type_ids` JSON array. A missing key, JSON null, non-array value,
or empty array rejects the complete proposal with SQLSTATE `22023` before any
delete. Every array item must be a canonical-shape UUID string, and duplicate
UUID values—including values differing only by letter case—also fail with
`22023`.

## Internal type-membership rule

After internal profiles are locked in deterministic UUID order, each internal
member is checked as follows for every selected photographer type:

1. the `public.photographer_types` row exists and is active; and
2. `public.user_photographer_types` contains the exact `(user_id,
   photographer_type_id)` relation.

A missing or inactive catalog row and a missing internal membership relation
produce the same generic SQLSTATE `P0002` failure. The function does not reveal
which internal catalog or relationship condition failed.

## External-member rule

External members continue to use `user_id = null`, a required nonblank
`person_name`, an optional date, numeric value metadata, and one or more active
catalog types. They are not required to have `user_photographer_types` rows,
because they have no internal profile identity. Existing external-member
support is preserved.

## Validation and lock ordering

The migration preserves this order:

1. validate the outer JSON array and every proposed member, including mandatory
   non-empty, UUID-only, duplicate-free type arrays;
2. lock internal profiles in deterministic UUID order;
3. verify live profiles and re-run authoritative availability checks;
4. verify active catalog types and internal user/type membership;
5. only then delete and replace `public.project_team_members` and their type
   rows;
6. write the existing minimal member-count audit entry.

Therefore any malformed, unavailable, inactive, or mismatched proposal fails
before the replace-all delete and leaves the persisted team unchanged by the
transaction. No broad table lock or different profile-lock order was added.

## Execution boundary

The helper performs no caller authorization itself and remains internal. The
migration explicitly revokes execution of the exact `(uuid, jsonb)` signature
from:

- `PUBLIC`;
- `anon`;
- `authenticated`.

The prior `service_role` revocation remains intact because `CREATE OR REPLACE`
preserves the function ACL. Same-owner trusted `SECURITY DEFINER` callers such
as `create_project` and `assign_team_roles` retain owner execution. No direct
grant was added.

## Static verification

The repository has no established executable SQL migration-test framework, so
no new framework was introduced and no runtime SQL execution is claimed. Static
review confirmed:

- exact `_apply_project_team(uuid, jsonb)` signature and `integer` return;
- `SECURITY DEFINER`, `VOLATILE`, and empty fixed search path;
- fully qualified relations and no dynamic SQL;
- outer `p_members = []` remains valid;
- mandatory/non-empty member type arrays and `22023` malformed/duplicate
  failures;
- active catalog validation for every internal and external member;
- exact internal user/type membership validation with generic `P0002`;
- deterministic profile locking and post-lock availability recheck unchanged;
- all new checks precede the sole team delete;
- replace-all inserts and member-count-only audit remain unchanged;
- direct execution revoked from `PUBLIC`, `anon`, and `authenticated`;
- no change to the public `create_project`, `assign_team_roles`, or
  `is_available` definitions or signatures.

## Boundary confirmation

- Migration prepared locally only; DEV apply is pending owner action.
- No Flutter runtime or provider changed.
- `projectRepositoryProvider` and `trackingRepositoryProvider` remain
  mock-backed.
- Step 11.6B and tracking integration were not started.
- No existing migration, RLS policy, public RPC, table, index, role, permission,
  seed data, or Edge Function changed.
- No remote Supabase command or DEV data/account action occurred.
- `AGENTS.md` and `docs/engineering` remain untouched.
- No Finance, Payments, Rekaz, Notifications, FCM, push, or reminders were
  introduced.
- Production remains untouched.
