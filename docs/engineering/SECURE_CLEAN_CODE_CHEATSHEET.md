# Secure + Clean + Clear Code Cheat Sheet

A reusable engineering playbook distilled from real production patterns
(Supabase / Postgres / Deno Edge Functions / Flutter). Stack-specific snippets
are examples — the **rules** are portable to any client/server project.

> How to read this: each rule is **one line you can remember**, followed by
> *why*, then **Do / Don't**. Skim the bold lines; drop into a section when you
> need the snippet.

---

## Table of contents

1. [Secrets & configuration](#1-secrets--configuration)
2. [The trust boundary (client vs. server)](#2-the-trust-boundary-client-vs-server)
3. [Database: SECURITY DEFINER, search_path, grants, RLS](#3-database-security-definer-search_path-grants-rls)
4. [API / Edge Function layer](#4-api--edge-function-layer)
5. [Authentication & sessions](#5-authentication--sessions)
6. [Authorization (effective permissions)](#6-authorization-effective-permissions)
7. [Input validation (fail-closed)](#7-input-validation-fail-closed)
8. [Error handling & information disclosure](#8-error-handling--information-disclosure)
9. [Logging & privacy](#9-logging--privacy)
10. [Clean code — architecture & boundaries](#10-clean-code--architecture--boundaries)
11. [Clear code — comments & naming](#11-clear-code--comments--naming)
12. [Testing for security](#12-testing-for-security)
13. [Database migrations discipline](#13-database-migrations-discipline)
14. [Client (mobile/web) hardening](#14-client-mobileweb-hardening)
15. [Pre-commit / pre-merge checklist](#15-pre-commit--pre-merge-checklist)

---

## 1. Secrets & configuration

**Never hardcode a secret. Load every secret from the environment.**

Why: hardcoded keys leak through git history, logs, crash reports, and shared
screenshots. A leaked key is compromised forever, even after deletion.

```ts
// DON'T
const SERVICE_KEY = "eyJhbGciOi...";           // in source → in git → gone

// DO
const SERVICE_KEY = Deno.env.get("SERVICE_ROLE_KEY");
if (!SERVICE_KEY) throw new Error("SERVICE_ROLE_KEY is not set"); // fail fast
```

Rules:
- **Secrets go in `.env` / platform secret store, never in the repo.** Commit a
  `.env.example` with *keys only, no values*.
- **`.gitignore` the real env files** (`.env`, `.env.local`, `*.local`) and
  verify with `git check-ignore .env`.
- **Two grades of key.** A *publishable/anon* key is safe on the client. A
  *service-role / admin* key bypasses all access control — **server-only,
  never shipped to a client, never in a mobile binary.**
- **Rotate on exposure.** If a secret is pasted into chat, a ticket, a log, or a
  screenshot — treat it as burned and rotate it.
- **Validate config shape at boot**, not at first use, so misconfig fails
  immediately and loudly (see §4).

Detection: `git log -p | grep -Ei 'secret|api[_-]?key|password|token'`,
plus a pre-commit secret scanner (gitleaks / trufflehog).

---

## 2. The trust boundary (client vs. server)

**The client is attacker-controlled. Enforce every rule on the server.**

Why: anyone can bypass your UI and call the API directly with forged input.
Client-side checks are UX, not security.

| Concern | Client may | Server MUST |
|---|---|---|
| Validation | give fast feedback | re-validate everything, authoritatively |
| Authorization | hide/disable buttons | re-check permission on every request |
| Secrets | hold publishable/anon key only | hold service-role/admin keys |
| Business rules | assist | be the single source of truth |

- **Privileged work lives behind a server endpoint** (Edge Function / API
  route) that authenticates the caller and re-checks permission — the client
  never talks to an admin API directly.
- **Build the privileged client only *after* authorization passes** — don't
  instantiate a service-role client until you've confirmed the caller is
  allowed (limits blast radius of an early bug).

---

## 3. Database: SECURITY DEFINER, search_path, grants, RLS

**Row-Level Security is the backstop. Turn it on for every table with data.**

```sql
alter table public.profiles enable row level security;
-- then add explicit policies; default-deny is the safe default.
```

**A `SECURITY DEFINER` function runs with the owner's power — lock it down.**

Why: it bypasses RLS. A loose one is a privilege-escalation primitive.

```sql
create or replace function public.record_own_password_change(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''            -- ① pin search_path (see below)
as $$
begin
  -- ② re-verify the caller/subject INSIDE the function; never trust the arg
  if not exists (
    select 1 from public.profiles
    where id = p_user_id and is_active and deleted_at is null
  ) then
    raise exception 'subject not eligible';
  end if;
  -- ③ do the one narrow thing, fully-qualifying every object name
  update public.profiles set must_change_password = false where id = p_user_id;
  return jsonb_build_object('id', p_user_id, 'must_change_password', false);
end;
$$;

-- ④ least privilege on EXECUTE: revoke from the world, grant to one role
revoke all on function public.record_own_password_change(uuid) from public;
revoke all on function public.record_own_password_change(uuid) from anon, authenticated;
grant execute on function public.record_own_password_change(uuid) to service_role;
```

The four non-negotiables for a `SECURITY DEFINER` function:
1. **`set search_path = ''`** — otherwise a caller can prepend a schema and
   trick it into running *their* `profiles` table / *their* function. Empty
   path forces you to fully-qualify (`public.profiles`), which closes the hole.
2. **Re-verify eligibility inside the function.** Arguments are attacker input
   even when they come from your own Edge Function — validate the subject is
   active/permitted before mutating.
3. **Do one narrow thing.** A definer function should be a scalpel, not a
   Swiss-army knife. Narrow surface = narrow risk.
4. **`REVOKE` then `GRANT EXECUTE` to exactly one role** (usually
   `service_role`). Never leave it executable by `anon`/`authenticated`.

**RLS scoping trap — scope by *identity/relationship*, not by an attribute the
subject shares with others.** In this project, admin "oversight" policies let a
manager *read* many rows for legitimate reasons; deriving *permissions* from
"any row I can see" would leak elevated rights. Fix: compute effective
permissions from **the caller's own role IDs / own user id**, never from
"rows visible under an oversight policy." (See §6.)

---

## 4. API / Edge Function layer

The reusable shape of a secure privileged endpoint:

```ts
serve(async (req) => {
  // 0. Method + CORS/preflight allowlist (reject anything unexpected).
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  // 1. Parse + STRICTLY validate input (allowlist keys, see §7). Fail closed.
  const body = await safeJson(req);
  const input = validateInput(body);
  if (!input.ok) return json(400, { error: "invalid_input" });

  // 2. Authenticate the caller from THEIR token (a user-scoped client).
  const userClient = createClient(URL, ANON_KEY, { global: { headers: authHeader(req) }});
  const auth = await authorizeActiveStaff(userClient); // fail-closed, see below
  if (!auth.ok) return json(auth.status, { error: "forbidden" });

  // 3. ONLY NOW build the privileged (service-role) client.
  const service = createClient(URL, SERVICE_ROLE_KEY);

  // 4. Do the work. Order side effects so a partial failure is safe (see below).
  try {
    const result = await performChange(service, auth.userId, input.value);
    return json(200, result, NO_STORE);
  } catch (_e) {
    return json(500, { error: "internal_error" }, NO_STORE); // generic, no leak
  }
});
```

Rules that made our endpoints robust:

- **Keep JWT verification ON.** Never disable it / never `--no-verify-jwt` to
  "make it work." If it fails, fix the token flow, don't remove the guard.
- **Authenticate from the caller's own token**, then re-derive who they are
  server-side. Don't accept a `user_id`/`role` from the body and trust it.
- **Fail closed.** A query *error* is **not** an empty result. Treat "couldn't
  determine permission" as **deny**, never as allow.
  ```ts
  const { data, error } = await userClient.rpc("has_feature", { code });
  if (error) return { ok: false, status: 500 };   // deny on error
  if (data !== true) return { ok: false, status: 403 };
  ```
- **Wrap SDK/network calls in try/catch**; a thrown exception must map to a
  generic 500, never bubble raw SDK/Postgres text to the client.
- **Order side effects for safe partial failure.** With no distributed
  transaction, pick an order where a crash between steps leaves a *safe* state,
  and document it. (e.g. update auth password *before* writing the audit row;
  if the audit write fails you retry/repair, but you never leave a changed
  password unrecorded *and* claimed-success.)
- **`no-store` on anything sensitive:**
  ```ts
  const NO_STORE = { "Cache-Control": "no-store", "Content-Type": "application/json" };
  ```
- **Generic error bodies.** One shape `{ "error": "invalid_input" }`; never echo
  the exception, stack, SQL, or which field/DB row was involved.

---

## 5. Authentication & sessions

- **Normalize identifiers before use, and validate the normalized form.**
  ```ts
  const normalize = (u: string) => u.trim().toLowerCase();
  const VALID = /^[a-z0-9._-]{2,50}$/;              // allowlist, anchored
  if (!VALID.test(normalize(username))) return reject();
  ```
- **Keep internal identity internal.** If usernames map to a synthetic internal
  email (`<user>@users.internal`), that email is an implementation detail:
  **never display it, log it, or store it in the client user model.** Construct
  it only where auth needs it.
- **One generic failure message for login.** "Username or password is
  incorrect" — never reveal *which* was wrong, nor whether the account exists,
  is disabled, or is deleted (prevents user enumeration).
- **Re-authenticate before sensitive changes** (password change, email change).
  Verify the *current* password server-side; only a confirmed
  `invalid_credentials` is a 401 — a network/500 while checking is a 500, not a
  false "wrong password."
- **Distinguish "not restored yet" from "signed out."** On startup, hold the UI
  in an `isInitializing` state until session restoration finishes, so you never
  flash the login screen at an authenticated user (or vice-versa).
- **Wait for a usable (refreshed) session before RLS queries.** An expired
  access token must be refreshed first, or your authorized reads silently
  return empty and you mis-render "no data / signed out."
- **Session cleanup ≠ explicit logout.** If *explicit* logout fails, the session
  still exists — keep the authenticated state and surface an error; don't show
  "signed out" over a live session. Silent cleanup of a *bad* session is the
  opposite: clear it.

---

## 6. Authorization (effective permissions)

The model that avoided a privilege leak here:

```
effective(permission) =
    explicit user override, if present      // wins even when it is FALSE
  else OR over role defaults                 // for the caller's OWN active roles
  filtered to active permissions only
```

- **An explicit per-user override wins — including an explicit `false`.** A
  deny-override must be able to *remove* a role-granted capability.
- **Derive role defaults from the caller's own active role IDs**, not from
  "roles I can see" and not from a role *code* alone (codes can be duplicated /
  reused across active+inactive rows). Match on the specific active role IDs the
  user actually holds.
- **Only active permissions/roles count.** A deactivated role or permission
  grants nothing.
- **Hard-deny sensitive capabilities regardless of data.** Some flags (e.g. a
  finance capability that is out of scope) are forced `false` in code so no data
  state can ever turn them on.
- **Check permission by *capability*, not by role name** in call sites
  (`if (can('manage_users'))`, not `if (role === 'admin')`) — roles change,
  capabilities are stable.

---

## 7. Input validation (fail-closed)

**Allowlist what's permitted; reject everything else. Never blocklist.**

```ts
const ALLOWED = new Set(["current_password", "new_password"]);
const FORBIDDEN = new Set(["user_id", "role", "is_active", "must_change_password"]);

function validateInput(body: unknown) {
  if (typeof body !== "object" || body === null) return { ok: false };
  const keys = Object.keys(body);
  // ① reject unknown keys (mass-assignment defense)
  if (keys.some((k) => !ALLOWED.has(k))) return { ok: false };
  // ② explicitly reject privilege fields even if someone widens ALLOWED later
  if (keys.some((k) => FORBIDDEN.has(k))) return { ok: false };
  // ③ type + shape checks
  const b = body as Record<string, unknown>;
  if (typeof b.new_password !== "string") return { ok: false };
  // ④ content policy
  if (!isStrongPassword(b.new_password)) return { ok: false };
  return { ok: true, value: b as Input };
}
```

- **Reject unknown fields** → kills mass-assignment / parameter-pollution (a
  client can't sneak `is_active: true` into an update).
- **Validate type, length bounds, and format** (anchored regex `^...$`).
- **Bound everything** — max length on strings, max size on uploads, max items
  on arrays. Unbounded input is a DoS and a memory risk.
- **Canonicalize once, then validate the canonical form** (trim/lowercase/NFC),
  so `../`, mixed case, and unicode tricks can't slip past.
- Password policy that worked here: **12–72 chars, upper + lower + digit +
  symbol, no leading/trailing whitespace** (72 = bcrypt's byte ceiling).

---

## 8. Error handling & information disclosure

- **Two audiences, two messages.** Log the *detailed* cause server-side (with a
  correlation id); return a *generic* message to the client.
- **Never leak internals to the client:** no stack traces, SQL, exception text,
  file paths, library versions, or "user not found vs. wrong password."
- **Fail closed on the security path, fail loud on the config path.** Deny
  access when unsure; crash at boot when misconfigured.
- **Map errors to a small typed enum**, then translate at the edge — the core
  never string-matches error text to make decisions.
  ```dart
  enum AuthFailure { invalidCredentials, accountDisabled, notAuthenticated,
                     profileUnavailable, sessionRestoreFailed, /* ... */ }
  ```

---

## 9. Logging & privacy

**Never log a secret or a credential. Ever.**

Do not log: passwords, JWTs/access tokens, API keys, service-role keys,
session cookies, internal/synthetic emails, full PII, OTPs, reset tokens.

- **Redact by construction.** Give sensitive types a `toString()` that hides the
  value, so an accidental interpolation can't leak it:
  ```dart
  @override
  String toString() => 'SupabaseConfig(url: $url, anonKey: <redacted>)';
  ```
- **Log identifiers, not contents** — a user id, not the email; a request id,
  not the body.
- **Structured, minimal, purposeful.** Log security-relevant *events*
  (authz failures, admin actions) as audit rows; skip the noise.
- **Assume logs are readable by more people than you think** (support, vendors,
  aggregators). Write them accordingly.

---

## 10. Clean code — architecture & boundaries

- **Layer it: UI → controller/provider → repository/service → gateway → I/O.**
  The UI never calls the backend or SDK directly; it talks to a repository
  interface. This is what made the whole app unit-testable without a network.
- **Depend on interfaces, inject implementations.** Define an `AuthGateway`
  (or `Repository`) abstract type; the real impl wraps the SDK, the test impl is
  an in-memory fake. Wiring happens in one place (providers/DI).
- **One reason to change per unit.** A function that authenticates *and*
  validates *and* mutates *and* formats the response is four bugs waiting to
  merge; split them (`authorize()`, `validateInput()`, `performChange()`).
- **Immutable state + explicit transitions.** Model state as immutable objects
  with `copyWith`; use a sentinel to distinguish "leave unchanged" from
  "set to null" so nullable fields update correctly.
- **Idempotent, race-aware async.** Cache an in-flight future so concurrent
  callers await the *same* operation; guard state writes with a monotonic
  generation token so a stale async result can't overwrite a newer one.
- **Small, pure, total functions.** Prefer functions that take inputs and return
  outputs with no hidden side effects — they're the easy ones to test and reuse.
- **Delete dead code and don't build unrequested features.** Scope discipline is
  a security property: less surface, less risk.

---

## 11. Clear code — comments & naming

- **Names carry the meaning; comments carry the *why*.** Code says *what*; a good
  comment says *why this way* and *what breaks otherwise*.
  ```dart
  // Wait for a REFRESHED session before RLS queries — an expired access token
  // makes authorized reads return empty, which we'd mis-read as "signed out".
  await _awaitUsableSession();
  ```
- **Document the non-obvious invariant, the ordering, and the trap** — the
  things a future reader (or you in six months) would get wrong. Skip comments
  that restate the code.
- **Name by intent and domain**: `authorizeActiveStaff`, `effectivePermissions`,
  `requiresPasswordChange` — not `check`, `data2`, `doIt`.
- **Make impossible states unrepresentable.** Prefer an enum/sealed type over a
  bag of booleans; prefer a typed result (`success | invalidCredentials |
  serverError`) over `bool` + out-params.
- **Consistency over cleverness.** Match the file's existing idiom, spacing, and
  naming. A surprising-but-clever line costs more than it saves.
- **A comment that can lie, will.** When you change the code, change the comment.

---

## 12. Testing for security

- **Test the fail-closed paths, not just the happy path.** Assert that a query
  *error* denies, a thrown SDK exception → 500, an unknown field → 400, an
  expired session refreshes, a superseded async result is dropped.
- **Hand-rolled fakes at the gateway boundary** beat live network + heavy mocks:
  fast, deterministic, and they let you script errors/throws/timings that are
  hard to reproduce for real.
  ```dart
  class FakeAuthGateway implements AuthGateway {
    Set<String> errorOn = {};                 // script query failures by method
    void _maybeThrow(String m) { if (errorOn.contains(m)) throw StateError(m); }
  }
  ```
- **One assertion of intent per test**, named for the behavior
  (`deniesWhenPermissionQueryErrors`), so a red test names the broken guarantee.
- **Cover the abuse cases**: wrong method, missing token, forged body field,
  oversized input, replayed/stale request, partial-failure ordering.
- **Keep pre-existing failures visible.** If tests were already red before your
  change, confirm via `git stash` and don't silently absorb them.

---

## 13. Database migrations discipline

- **Forward-only. Never edit an already-applied migration** — write a new one.
- **One migration = one coherent change**, timestamped, reviewed like code.
- **Idempotent where possible** (`create ... if not exists`, guarded `do`
  blocks) so a re-run doesn't explode.
- **Include the grants/RLS in the same migration** that creates the object —
  never leave a new function/table world-executable "temporarily."
- **Verify before applying to a shared env**: read the real pending list
  (don't trust a spinner), diff, and apply deliberately. Never point a
  migration/DB tool at the wrong project.
- **Separate environments** (local → dev → prod); never test against production.

---

## 14. Client (mobile/web) hardening

- **Compile-time config, validated:** inject config via build flags
  (`--dart-define-from-file`, `import.meta.env`), read with a typed accessor,
  and validate shape at startup.
  ```dart
  static const _url = String.fromEnvironment('SUPABASE_URL');
  // strict allowlist regex — reject anything that isn't the expected host shape
  static final _valid = RegExp(r'^https://[a-z0-9]{20}\.supabase\.co/?$');
  ```
- **Pin dependency versions exactly** (`supabase_flutter: 2.15.4`, not `^`) for
  reproducible, reviewable builds; upgrade deliberately.
- **Only publishable/anon keys on the client.** If you ever feel the need for a
  service key in the app, the design is wrong — move that action to a server
  endpoint.
- **Don't trust client clocks, client validation, or client-provided ids** for
  anything that matters — re-check server-side.
- **Mind mobile-specific leaks:** secrets in the binary are extractable; avoid
  logging to the system log in release; be deliberate about what's cached.

---

## 15. Pre-commit / pre-merge checklist

```
[ ] No secret/key/password/token in the diff or in git history.
[ ] .env* is gitignored; .env.example has keys only, no values.
[ ] Every new table has RLS enabled + explicit policies.
[ ] Every SECURITY DEFINER fn: search_path='', re-checks subject,
    REVOKE from public/anon/authenticated, GRANT EXECUTE to one role.
[ ] Privileged action sits behind a server endpoint; JWT verify ON.
[ ] Caller authenticated from their own token; authz re-checked server-side.
[ ] Input strictly allowlisted; unknown/privilege fields rejected; bounds set.
[ ] Fail-closed: query error → deny; thrown → generic 500; no raw leak.
[ ] Side effects ordered so a partial failure is safe; documented.
[ ] no-store on sensitive responses; generic error bodies.
[ ] No password/JWT/key/internal-email logged; sensitive toString redacted.
[ ] New logic has fail-path tests (deny, throw, bad input, stale async).
[ ] Migration is forward-only, one change, ships its own grants/RLS.
[ ] Client holds only publishable keys; deps pinned; config validated at boot.
[ ] flutter analyze / linter clean; no dead code; scope not exceeded.
```

---

*Companion doc:* [SECURITY_AUDIT_OWASP_CHEATSHEET.md](SECURITY_AUDIT_OWASP_CHEATSHEET.md)
— how to *audit* code for RCE, XSS, SQLi, file-upload, and the full OWASP set.
