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
