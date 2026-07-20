# Supabase RLS Plan — Sprint 8 (Decisions Frozen)

**Status:** DRAFT for review, aligned to `SUPABASE_CORE_PLAN.md` §1. **Not applied this sprint.**
**Principle:** RLS **enabled on every table**, **default deny**. Access is granted by explicit policies keyed on the caller's roles (D1) + ownership/assignment, with **soft-delete filtering** (D6) and **server-enforced permissions** (D5). Public clients reach data only through `security definer` RPCs (D4).

**Excluded (no tables → no policies):** finance, payments, Rekaz, notifications, FCM, push, reminders.

---

## 1. Identity, roles & permission resolution

- Caller = `auth.uid()` → `profiles` (must be `is_active = true` and `deleted_at is null`).
- Roles via `user_roles` → `roles.code` (**lookup, not enum** — D1).
- Effective permission (D5) = **user override if present, else OR of role defaults** across the user's roles.
- Public client = `anon` → RPC only.

### Helper functions (SQL, `security definer`, `stable`)

```sql
-- DRAFT helpers (frozen-decision aligned)

create function is_active_user() returns boolean language sql stable as $$
  select exists(select 1 from profiles p
    where p.id = auth.uid() and p.is_active and p.deleted_at is null) $$;

-- role by CODE via the roles lookup (D1)
create function has_role(role_code text) returns boolean language sql stable as $$
  select exists(
    select 1 from user_roles ur join roles r on r.id = ur.role_id
    where ur.user_id = auth.uid() and r.code = role_code and r.is_active) $$;

create function is_admin() returns boolean language sql stable as $$
  select has_role('admin') $$;

-- normalized permission resolution (D5): user override wins, else OR of role defaults
create function has_feature(perm_code text) returns boolean language sql stable as $$
  with p as (select id from permissions where code = perm_code)
  select coalesce(
    (select up.granted from user_permissions up join p on p.id = up.permission_id
      where up.user_id = auth.uid()),
    (select bool_or(rp.granted) from role_permissions rp
      join p on p.id = rp.permission_id
      join user_roles ur on ur.role_id = rp.role_id
      where ur.user_id = auth.uid()),
    false) $$;

create function manages_project(pid uuid) returns boolean language sql stable as $$
  select exists(select 1 from projects p
    where p.id = pid and p.manager_id = auth.uid() and p.deleted_at is null) $$;

create function assigned_to_project(pid uuid) returns boolean language sql stable as $$
  select exists(select 1 from project_team_members t
    where t.project_id = pid and t.user_id = auth.uid()) $$;

-- Marketing availability exemption (D1): marketing users bypass same-date conflicts;
-- everyone else is subject to overlapping-project (and, later, leave) conflicts.
create function is_available(uid uuid, on_date date) returns boolean language sql stable as $$
  select case
    when exists (select 1 from user_roles ur join roles r on r.id = ur.role_id
                 where ur.user_id = uid and r.code = 'marketing') then true
    else not exists (
      select 1 from project_team_members t
      join projects p on p.id = t.project_id
      where t.user_id = uid and t.date = on_date
        and p.status in ('active','in_progress','pending_closure')
        and p.deleted_at is null)
    -- Leave/permission conflicts read public.user_unavailability (Step 3):
    --   overlap on `on_date` where is_active. (Enforced in the assignment RPC in
    --   the project-team step; not a notifications concern.)
  end $$;
```

> `has_feature('can_manage_finance')` is intentionally never used — finance is out of scope.

---

## 2. Soft-delete filtering (D6)

Every **SELECT** policy (and every read view) on soft-deletable tables adds `is_active AND deleted_at IS NULL`:
- `profiles`, `projects`, `project_links`.

Retained-history tables (`project_stages`, `closure_requests`, `client_reviews`, `audit_logs`) are **never deleted**; visibility is scoped by their parent project's policies.

---

## 3. RLS matrix (per table × role × operation)

Legend: **A**=Admin · **M**=Manager (owns project) · **P**=Photographer (assigned) · **MK**=Marketing · **anon**=public (RPC only). ✅ allowed · ⛔ denied · *(feature)* = also requires that permission via `has_feature()`.

### `roles`, `permissions` (lookups)
| Op | A | others | anon |
|---|---|---|---|
| select | ✅ | ✅ (read-only reference) | ⛔ |
| insert/update/delete | ✅ *(can_manage_permissions)* | ⛔ | ⛔ |

### `profiles`
| Op | A | M / P / MK | anon |
|---|---|---|---|
| select | ✅ all (non-deleted) | ✅ self + teammates | ⛔ |
| insert | via `admin_create_user` Edge Function | ⛔ | ⛔ |
| update | ✅ *(can_manage_users)* | ✅ self (profile fields) | ⛔ |
| delete | ✅ **soft-delete** *(can_manage_users)* | ⛔ | ⛔ |

### `user_roles`, `role_permissions`, `user_permissions`
| Op | A | others | anon |
|---|---|---|---|
| select | ✅ | ✅ self | ⛔ |
| insert/update/delete | ✅ *(can_manage_permissions)* | ⛔ | ⛔ |

*(The "apply role permissions" action runs through the `apply_role_permissions` RPC, admin-gated.)*

### `photographer_types`, `user_photographer_types`
| Op | A | M/MK | P | anon |
|---|---|---|---|---|
| select | ✅ | ✅ | ✅ self | ⛔ |
| write | ✅ *(can_manage_users)* | ⛔ | ⛔ | ⛔ |

### `projects`
| Op | A | M | P | MK | anon |
|---|---|---|---|---|---|
| select | ✅ all | ✅ own | ✅ assigned | ✅ assigned | ⛔ (RPC) |
| insert | ✅ | ✅ *(can_add_project)*, `manager_id=uid` | ⛔ | *(per perms)* | ⛔ |
| update | ✅ | ✅ own *(can_edit_project)* | ⛔ | ⛔ | ⛔ |
| delete | ✅ **soft-delete** | ⛔ | ⛔ | ⛔ | ⛔ |

### `project_team_members` + `project_team_types`
| Op | A | M | P/MK | anon |
|---|---|---|---|---|
| select | ✅ | ✅ own project | ✅ own/teammates | ⛔ |
| write | ✅ | ✅ own *(can_assign_photographers)* | ⛔ | ⛔ |

*(Writes go through `assign_team_roles` RPC, which replaces the member + its types atomically and applies the `is_available` guard — marketing exempt, D1.)*

### `project_stages`
| Op | A | M | P/MK | anon |
|---|---|---|---|---|
| select | ✅ | ✅ own | ✅ assigned | ⛔ |
| update | ✅ | ✅ own *(can_update_stages)* | ✅ assigned *(can_update_stages)* | ⛔ |
| insert/delete | via project-create RPC | seeded | ⛔ | ⛔ |

### `closure_requests`
| Op | A | M | P | anon |
|---|---|---|---|---|
| select | ✅ | ✅ own project | ✅ own submissions | ⛔ |
| insert | ✅ | ⛔ | ✅ assigned *(can_request_closure)* | ⛔ |
| update (approve/reject) | ✅ | ✅ own *(can_approve_closure)* | ⛔ | ⛔ |
| delete | ⛔ (retained history) | ⛔ | ⛔ | ⛔ |

### `project_links` (D4, D6)
| Op | A | M | P/MK | anon |
|---|---|---|---|---|
| select | ✅ | ✅ own project | ✅ assigned project | ⛔ (tracking RPC, approved+client-visible only) |
| insert/update (approve, set visibility) | ✅ | ✅ own project | ⛔ | ⛔ |
| delete | ✅ **soft-delete** | ✅ own project **soft-delete** | ⛔ | ⛔ |

### `client_reviews`
| Op | A | M | P/MK | anon |
|---|---|---|---|---|
| select | ✅ | ✅ own project | ⛔ | ⛔ |
| insert | via RPC | via RPC | ⛔ | ✅ **`submit_review` RPC only** |

### `audit_logs`
| Op | A | others | anon |
|---|---|---|---|
| select | ✅ | ⛔ | ⛔ |
| insert | via RPCs/triggers (system) | — | ⛔ |
| update/delete | ⛔ (immutable history) | ⛔ | ⛔ |

---

## 4. Public (anon) access — RPC only (D4)

No direct table grants to `anon`. Two `security definer` RPCs:

```sql
-- track_by_serial: project public status + ONLY approved & client-visible links,
-- for a non-deleted project. Never exposes team, fees, notes, or manager identity.
create function track_by_serial(p_serial text) returns jsonb ...;
-- returns links where is_approved and is_client_visible and is_active and deleted_at is null

-- submit_review: insert rating (1..5) + optional message, resolved by serial.
create function submit_review(p_serial text, p_rating int, p_message text) returns void ...;
```

Rules baked in: unknown serial → empty; deleted project → empty; validate `rating between 1 and 5`; expose nothing beyond public status + eligible links.

---

## 5. Write RPCs & invariants (server-enforced)

All run `security definer` but **re-check role/feature inside** before mutating:

| RPC | Guard | Effect |
|---|---|---|
| `create_project` | `is_admin() OR (has_role('manager') AND has_feature('can_add_project'))` | project + serial + seed stages |
| `assign_team_roles` | admin OR (manages_project AND `can_assign_photographers`); per-member `is_available(user,date)` (marketing exempt) | replace members + types atomically |
| `update_project_stage` | admin OR ((manages_project OR assigned_to_project) AND `can_update_stages`) | cascade stage statuses |
| `submit_closure_request` | assigned_to_project AND `can_request_closure`; reject if a pending exists | insert + project → `pending_closure` |
| `approve_closure_request` | admin OR (manages own project AND `can_approve_closure`) | approve + project `completed` + all stages `done` |
| `reject_closure_request` | same as approve | reject + project → `active` |
| `apply_role_permissions` | admin *(can_manage_permissions)* | copy `role_permissions` → `user_permissions` overrides (D5) |

**Account creation / password flows (D2):** `admin_create_user` is an **Edge Function** (service role, not RLS-bound) that creates the Auth user with the internal email, no email confirmation, then seeds `profiles`/`user_roles`/`user_permissions`. Admin password reset/change is a **secure internal/admin flow**. Documented only.

---

## 6. Enablement checklist (future apply-sprint)

- `enable row level security` on **all** tables; default-deny posture.
- Create `roles`/`permissions`/`role_permissions` seed rows first, then helper functions, then policies, then RPCs, then the `admin_create_user` Edge Function.
- Grant `execute` on `track_by_serial` + `submit_review` to `anon`; grant nothing else to `anon`.
- Verify with a **policy test matrix** (one case per row of §3) including soft-deleted-row invisibility and the marketing availability exemption, before pointing the app at it.

**This sprint documents rules only. No RLS enabled, no SQL run.**

---

## 7. Step 6.1 implementation notes (helpers + identity/access READ RLS)

Migration `supabase/migrations/20260714160000_identity_access_rls.sql` implements
the shared security helpers and the identity/access **read** policies. Runs after
Steps 2–5. Statically reviewed, **not** applied. This is a **subset** of §3
(reads only); writes and the project/closure/tracking layers come later.

**Helper functions** (SQL, `stable`, schema-qualified, `set search_path = ''`;
default PUBLIC execute revoked, `execute` granted to `authenticated` only —
never `anon`):

| Function | Security | Reads | Purpose |
|---|---|---|---|
| `current_profile_id()` | **invoker** | — (`auth.uid()`) | caller's profile id; no table access |
| `is_active_user()` | **definer** | `profiles` | caller is active + not soft-deleted |
| `has_role(text)` | **definer** | `user_roles`,`roles` | holds an **active** role by code |
| `is_admin()` | **definer** | (via `has_role`) | holds active `admin` |
| `has_feature(text)` | **definer** | `permissions`,`user_permissions`,`role_permissions`,`user_roles`,`roles` | effective permission (D5) |

`SECURITY DEFINER` on the table-reading helpers is deliberate: called inside a
policy they **bypass RLS** on the tables they read, so a policy on
`profiles`/`user_roles` never re-enters those tables' policies → **no RLS
recursion**. `current_profile_id()` reads nothing, so it stays `invoker`.

**Fail-closed on inactive/deleted profiles (internal gate):** `has_role()` and
`has_feature()` each begin with `is_active_user() AND …`, and `is_admin()`
inherits it through `has_role('admin')`. So a disabled or soft-deleted user
(including a disabled admin) gets `false` **even when a future SECURITY DEFINER
RPC calls these helpers directly** — safety does not depend on a separate
`is_active_user()` call at the call site. The chain `has_role → is_active_user`
(both DEFINER, both bypass RLS) reads `profiles`/`user_roles`/`roles` without
re-entering RLS, so the internal gate adds **no recursion**.

**Active-only resolution:** `has_feature()` counts **active permissions only**
(`permissions.is_active`) and **active roles only** for role defaults; `has_role()`
requires `roles.is_active`. So `can_manage_finance` (inactive) and the
`finance`/`wedding_finance` roles resolve to **false / never match** — zero
behavior. `has_feature()` does **not** copy role defaults into `user_permissions`.

**Execution locked:** default PUBLIC execute is revoked and `anon` is revoked
explicitly; only `authenticated` is granted `execute`. Functions are owned by the
migration role, so `authenticated` can execute but cannot replace/alter/drop them.

**Policies added — all `FOR SELECT TO authenticated` (no anon, no writes):**

| Table | Self / active-user read | Admin read |
|---|---|---|
| `profiles` | own row, `is_active AND deleted_at IS NULL` | all non-deleted (active+inactive), active admin |
| `roles` | active rows | + inactive (oversight) |
| `permissions` | active rows | + inactive (oversight) |
| `user_roles` | own `user_id` | all |
| `role_permissions` | defaults for the caller's own roles | all |
| `user_permissions` | own `user_id` | all |
| `photographer_types` | active rows | + inactive (oversight) |
| `user_photographer_types` | own `user_id` | all |
| `audit_logs` | — (none) | admin read only |

**Writes deferred:** no INSERT/UPDATE/DELETE policy on any table → all mutations
stay **default-deny**. Identity/access writes (admin user/role/permission
management, profile self-edit, `deleteUser` soft-delete) go through admin-gated
RPCs / the `admin_create_user` Edge Function in later steps (§5) — not here, so a
user cannot alter their own roles/permissions/status and no escalation path
exists. `audit_logs` writes come from future `SECURITY DEFINER` RPCs (bypass RLS);
none created here.

**Disabled/soft-deleted users:** every authenticated policy is gated by
`is_active_user()` (or, for `profiles` self, the row's own `is_active AND
deleted_at IS NULL`). A disabled or soft-deleted user — including a disabled
admin — fails all of them and cannot even read their own profile (the Sprint-10
auth layer treats an unreadable post-login profile as "disabled" and signs out).

**Not in this step:** `user_unavailability`, project/team/stages/closure/links
policies; the `manages_project` / `assigned_to_project` / `is_available` helpers;
any RPC/Edge Function; anon access; Flutter.

---

## 8. Step 6.2 implementation notes (project-domain READ RLS)

Migration `supabase/migrations/20260714170000_project_domain_rls.sql` adds the
project-domain authorization helpers and the **read** policies for `projects`,
`project_team_members`, `project_team_types`, `project_stages`,
`user_unavailability`. Runs after Step 6.1. Statically reviewed, **not** applied.

**Helpers** (SQL, `stable`, schema-qualified, `set search_path = ''`, **SECURITY
DEFINER**; PUBLIC + anon execute revoked, `execute` granted to `authenticated`
only). Both **fail closed** via `is_active_user()`, so a disabled/soft-deleted
caller gets false even inside a future RPC. Canonical param name is `pid` (per §1)
— chosen over `project_id` to avoid a parameter/column collision.

| Function | Security | Reads | Returns true when |
|---|---|---|---|
| `manages_project(pid)` | definer | `projects` | active caller owns a **live** project `pid` |
| `assigned_to_project(pid)` | definer | `project_team_members`,`projects` | active caller is a team member of a **live** project `pid` |

**Policies — all `FOR SELECT TO authenticated` (no anon, no writes):**

| Table | Rule |
|---|---|
| `projects` | `manages_project(id)` OR `assigned_to_project(id)` OR (`is_admin()` AND live) |
| `project_team_members` | parent project visible (delegates to `projects` RLS) |
| `project_team_types` | parent team member visible (delegates to member → project RLS) |
| `project_stages` | parent project visible (delegates to `projects` RLS) |
| `user_unavailability` | self (own rows, incl. cancelled history) **or** admin (all) |

**Delegation pattern:** child tables use "visible iff the parent project (or team
member) is visible", which reproduces the frozen matrix and inherently hides
soft-deleted/inactive projects' children. It is **recursion-free**: parents'
policies use only the SECURITY DEFINER helpers (which bypass RLS) and plain
columns, so `team_types → team_members → projects → (definer helpers)` is acyclic.

**Assignment-`value` exposure (reported):** RLS is row-level, so assigned staff
who can see a project see **all** teammate rows including `value`. This matches
both the frozen matrix (P/MK read own/teammates) **and** the current Flutter UI
(`project_details_screen` shows every teammate's `value` as «… ر.س», ungated), so
it is the approved visibility, not an over-exposure. `value` is assignment
metadata, never finance. Restricting `value` to manager/admin would need a
column-masking read view/RPC — **deferred**, not created here.

**`user_unavailability` privacy:** notes/reasons are visible only to the record's
owner and to admins. Managers have **no** direct table access; their availability
checks will use a restricted boolean availability function/RPC in the later
assignment step.

**Marketing (deferred rule):** resolved via `user_roles → roles.code =
'marketing'` (never mapped to `designer`). Assigned Marketing users get the same
project read visibility as other assigned staff. The double-booking **exemption**
is not implemented here; future availability enforcement must exempt Marketing
only from project overlaps, **not** from explicit leave/unavailability, unless the
frozen business rule says otherwise.

**Writes:** none. No INSERT/UPDATE/DELETE (incl. soft-delete) policy on any of the
five tables → all mutations stay default-deny; project/team/stage writes go
through the transactional RPCs in a later step.

**Not in this step:** `is_available()`, assignment/overlap validation, Marketing
exemption logic, booking/assignment RPCs, closure/links/tracking policies or RPCs,
Edge Functions, anon access, Flutter. Step 6.1 helpers unchanged.
