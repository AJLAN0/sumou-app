# Sprint 11 — Step 11.4B Assignable Staff Flutter QA

## Scope and environment status

Step 11.4B integrates only the Flutter data contract for trusted assignable
staff discovery. The owner reports that migration
`20260809180755_assignable_project_staff_rpc.sql` is applied to SUMOU-DEV.
This step did not run a remote Supabase command, inspect or modify DEV data or
accounts, or perform live DEV UI QA. Production was untouched.

The normal `projectRepositoryProvider` remains backed by
`MockProjectRepository`. No assignment screen, date input, team mutation, or
`assign_team_roles` integration was added; those remain Step 11.4C work.

## Consumed backend contract

`ProjectGateway.listAssignableProjectStaff` invokes exactly:

```text
list_assignable_project_staff
```

with exactly:

```json
{
  "p_on_date": "YYYY-MM-DD",
  "p_exclude_project_id": "<uuid or null>"
}
```

The authenticated Supabase client performs the RPC. Flutter does not query
`profiles`, `user_unavailability`, roles, permissions, or `is_available` to
discover candidates and does not infer availability locally.

## Safe domain result

The repository returns immutable `AssignableProjectStaff` values containing
only:

- `userId`;
- `fullName`;
- immutable `photographerTypes` entries containing `id`, `code`, and `nameAr`;
- the backend-authoritative `isAvailable` boolean.

The only accepted photographer-type codes are `photo`, `video`, `instagram`,
and `design`. The result exposes no username, email, phone, permission, role,
leave information, booking conflict, project conflict, assignment value, or
reason for unavailability.

## Input and response validation

- `onDate` must be a local calendar value at midnight, including zero
  milliseconds and microseconds. It is serialized from its components without
  timezone conversion.
- A null exclusion is preserved as null. A non-null exclusion must be a strict
  UUID with no surrounding whitespace and is rejected before the gateway call
  when malformed.
- The RPC result must be a JSON array. Every candidate and nested type must be
  a map with exactly the allowlisted keys.
- UUIDs, nonblank display names, the boolean availability value, and a nonempty
  type list are mandatory.
- Duplicate candidate UUIDs and duplicate type UUIDs or codes within one
  candidate fail closed.
- Unknown codes and any malformed outer, candidate, or nested value fail as
  `ProjectRepositoryFailure.invalidData`; entries are never silently skipped.

## Safe failure mapping

Gateway failures map without retaining backend diagnostics:

- `28000` to `notAuthenticated`;
- `42501` to `forbidden`;
- `22023` to `invalidInput`;
- neutral exclusion `P0002` to `notFound`;
- availability `P0001` to `unavailable`;
- unexpected SDK, network, or server failures to `loadFailed`.

The read is attempted once and is not retried by repository code. SQLSTATE,
PostgREST messages, details, hints, SQL, payloads, tokens, and internal emails
are not exposed.

## Automated verification

Final verification passed:

- `git diff --check`;
- `dart format --output=none --set-exit-if-changed lib test` with zero changes;
- full `flutter analyze` with no issues;
- all 77 tests in the three requested focused test files.

## Boundary confirmation

- No migration, RLS policy, RPC SQL, or Edge Function was changed.
- No service role or direct Flutter table write was added.
- Marketing, leave, overlap, and conflict rules remain exclusively
  server-authoritative.
- `assign_team_roles`, assignment UI, and Step 11.4C were not started.
- Live DEV UI QA is not claimed.
- Production was untouched.
