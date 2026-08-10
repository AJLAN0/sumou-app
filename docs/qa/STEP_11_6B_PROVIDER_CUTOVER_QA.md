# Sprint 11 — Step 11.6B Provider Cutover QA

## Scope and deployment prerequisite

Step 11.6B connects the normal Flutter application to the trusted project and
public-tracking data layers. The owner confirmed that
`20260810204812_project_team_type_integrity_hardening.sql` and the Step 11.5A
closure-read migration are present on SUMOU-DEV. This step did not run a remote
Supabase command or alter DEV data.

Step 11.6C remains responsible for the full Flutter regression suite,
owner-controlled role QA on DEV, mobile/iPad workflow QA, final security scans,
and the Sprint 11 completion decision. No live DEV UI result is claimed here.

## Public tracking contract

`SupabaseTrackingRepository` uses an injected, fakeable `TrackingGateway`. The
production gateway uses the existing `SupabaseClient` and calls only:

```text
track_project_by_serial
```

with exactly:

```json
{"project_serial": "<TRIMMED-UPPERCASE-SERIAL>"}
```

No authenticated session is required. The same publishable-client instance can
therefore invoke the RPC as `anon` on public routes. There are no direct reads
of projects, project links, profiles, closure requests, roles, permissions, or
unavailability data, and there are no tracking table writes.

Input is trimmed and uppercased. Only
`^(FLD|SOC|WED)-[A-Z0-9]{4}-[A-Z0-9]{2}$` proceeds to the RPC. Blank or malformed
input returns the same neutral `null` result as an unknown, inactive, or
soft-deleted project and does not create a user-visible existence oracle.

## Strict public result boundary

An RPC `null` maps to `ClientTrackingModel? = null`. A successful response must
contain exactly these outer fields:

- `serial`;
- `project_name`;
- `client_name`;
- `status` (`active` or `done` only);
- `links`.

Every link must contain exactly `label` and `url`; labels must be nonblank and
URLs must be absolute HTTP or HTTPS URLs with a host. The returned serial must
be valid and exactly match the normalized request. Missing, extra, blank,
unknown, mismatched, or malformed data fails closed as the same safe
`loadFailed` repository failure. No automatic retry occurs.

The hydrated public model receives only serial, project name, client name,
coarse status, and approved links. `message` and `rating` are always null. It
does not receive project or user UUIDs, manager/team identities, assignment
values or dates, project notes/dates/type/internal status/stages, closure data,
roles, permissions, availability details, leave, audit data, username, phone,
or internal Auth email.

## Failure and review behavior

SDK, PostgREST, network, parser, and server failures map to a diagnostic-free
Arabic `loadFailed` message. Raw SQLSTATE, message, details, hint, query,
payload, token, or email values are not exposed. The screen provides an
explicit retry action; the repository never retries implicitly.

There is no trusted retained client-review contract. The real
`submitReview(...)` implementation performs zero gateway/Supabase calls and
returns `unsupportedOperation`. The current public result screen contains no
rating or review submission control, so the normal real flow exposes no enabled
action that can fail or pretend to persist a review. The mock repository retains
its isolated legacy behavior only for explicit tests.

## Provider cutover and test boundary

The normal providers now resolve as follows:

- `projectRepositoryProvider` → `SupabaseProjectRepository` using
  `supabaseClientProvider`;
- `trackingRepositoryProvider` → `SupabaseTrackingRepository` using the same
  provider.

There is no build-mode, debug-mode, platform, environment, or test-detection
fallback. `MockProjectRepository` and `MockTrackingRepository` remain available
as test doubles. Shared test helpers and directly affected tests now override
both providers explicitly, and provider tests prove normal real resolution and
explicit mock replacement without network access.

## Project runtime review

The provider cutover retains RLS-partial project graphs. Assigned staff may see
their project, stages, and only their own visible team rows. Missing RLS-hidden
teammates are not treated as deleted data and no placeholder identities are
fabricated.

Enabled operations retain UX gates matching the trusted backend state and
permission model:

- create: active admin or `can_add_project` UX gate, with backend authorization
  authoritative;
- basics edit: owning manager/admin in `active` or `in_progress`; type and
  status are read-only and the RPC preserves both;
- stage update: working project plus ownership/assignment and permission UX
  gates; the trusted RPC remains authoritative;
- team: working project, owning manager/admin, trusted candidate discovery,
  and server-side availability/type-membership rechecks;
- closure submit: assigned caller with permission on a working project;
- closure review: pending request and `pending_closure` project for an owning
  manager/admin with the required gate;
- delivery links: read-only for the backend-visible manager/admin scope.

Manager reassignment, project-link mutation, project soft delete, and generic
status override remain absent or disabled. No missing contract was replaced by
a direct Flutter write.

## Automated and static verification

Step 11.6B verification covers strict tracking input/result parsing, exact RPC
name/body, neutral not-found behavior, no retry, safe error mapping, unsupported
review behavior, real provider resolution, explicit mock overrides, project
reads and partial graphs, create/edit/stage/team workflows, closure workflows,
delivery links, manager/admin/photographer details, public tracking UI, and
permission/state action gates.

Recorded gates:

- `git diff --check`: passed;
- `dart format --output=none --set-exit-if-changed lib test`: passed;
- `flutter analyze`: passed with no issues;
- focused Flutter suite: **279 passed, 0 failed** across the tracking,
  provider, project repository/model, routing, create/edit/stage/team,
  closure/link, manager/admin/photographer details, dashboard/calendar, and
  availability files selected for this cutover.

Static scans found no service-role secret in Flutter, no direct Supabase table
write in the repository/provider layer, and no direct table access in the
tracking implementation. Project mutations remain RPC-only and public tracking
uses only `track_project_by_serial`. Existing comments that explicitly prohibit
`service_role` remain; no credential or key was introduced.

## Boundary confirmation

- Step 11.6A was applied to DEV by the owner; this step did not apply or modify
  a migration.
- No SQL, RLS policy, RPC definition, or Edge Function changed.
- No Supabase remote command or DEV data/account action occurred.
- No client review, project-link write, manager reassignment, project soft
  delete, or generic project-status override was implemented.
- Finance, Payments, Rekaz, Notifications, FCM, push, and reminders remain out
  of scope.
- `AGENTS.md` and `docs/engineering` remain untouched.
- Step 11.6C was not started and Sprint 11 is not marked complete.
- Production remains untouched.
