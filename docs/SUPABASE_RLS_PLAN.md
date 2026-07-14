# Supabase RLS Plan — Sprint 8

**Status:** DRAFT for review. **Not applied this sprint.** Policies below are reference to align on access rules; they become real policies in a later approved sprint.
**Principle:** RLS **enabled on every table**, **default deny**. Access is granted by explicit policies keyed on the caller's roles + project ownership/assignment. Sensitive actions additionally check feature flags.

**Excluded (no policies, because no tables):** finance, payments, Rekaz, notifications, FCM, push, reminders.

---

## 1. How identity & access are resolved

- Caller identity = `auth.uid()` (Supabase Auth).
- `auth.uid()` → `profiles` (must be `active = true` and `deleted_at is null`).
- Roles → `user_roles`; feature flags → `user_permissions.features` (jsonb).
- **Public client** = `anon` (no `auth.uid()`); reaches data **only** through `security definer` RPCs (never direct table access).

### Helper functions (SQL, `security definer`, `stable`)

```sql
-- DRAFT helpers
create function current_uid() returns uuid language sql stable
  as $$ select auth.uid() $$;

create function is_active_user() returns boolean language sql stable as $$
  select exists(select 1 from profiles p
    where p.id = auth.uid() and p.active and p.deleted_at is null) $$;

create function has_role(r role_type) returns boolean language sql stable as $$
  select exists(select 1 from user_roles ur where ur.user_id = auth.uid() and ur.role = r) $$;

create function is_admin() returns boolean language sql stable as $$
  select has_role('admin') $$;

create function has_feature(feature text) returns boolean language sql stable as $$
  select coalesce((select (features ->> feature)::boolean
                   from user_permissions where user_id = auth.uid()), false) $$;

create function manages_project(pid uuid) returns boolean language sql stable as $$
  select exists(select 1 from projects p where p.id = pid and p.manager_id = auth.uid()) $$;

create function assigned_to_project(pid uuid) returns boolean language sql stable as $$
  select exists(select 1 from project_team_roles t
                where t.project_id = pid and t.user_id = auth.uid()) $$;
```

> `has_feature('can_manage_finance')` is intentionally never used — finance is out of scope.

---

## 2. RLS matrix (per table × role × operation)

Legend: **A**=Admin, **M**=Manager (owns the project), **P**=Photographer (assigned), **anon**=public client (RPC only). ✅ allowed · ⛔ denied · *(feature)* = also requires that feature flag.

### `profiles`
| Op | A | M | P | anon |
|---|---|---|---|---|
| select | ✅ all | ✅ self + (project teammates) | ✅ self + teammates | ⛔ |
| insert | ✅ *(can_manage_users)* | ⛔ | ⛔ | ⛔ |
| update | ✅ *(can_manage_users)* | ✅ self (profile fields only) | ✅ self | ⛔ |
| delete | ✅ soft-delete *(can_manage_users)* | ⛔ | ⛔ | ⛔ |

### `user_roles` / `user_permissions`
| Op | A | M | P | anon |
|---|---|---|---|---|
| select | ✅ all | ✅ self | ✅ self | ⛔ |
| insert/update/delete | ✅ *(can_manage_permissions)* | ⛔ | ⛔ | ⛔ |

### `projects`
| Op | A | M | P | anon |
|---|---|---|---|---|
| select | ✅ all | ✅ `manager_id = uid` | ✅ assigned | ⛔ (RPC only) |
| insert | ✅ | ✅ *(can_add_project)*, `manager_id = uid` | ⛔ | ⛔ |
| update | ✅ | ✅ own *(can_edit_project)* | ⛔ | ⛔ |
| delete | ✅ soft-delete | ⛔ | ⛔ | ⛔ |

### `project_team_roles`
| Op | A | M | P | anon |
|---|---|---|---|---|
| select | ✅ | ✅ own project | ✅ own assignments + teammates on shared projects | ⛔ |
| insert/update/delete | ✅ | ✅ own project *(can_assign_photographers)* | ⛔ | ⛔ |

*(Writes normally go through the `assign_team_roles` RPC, which replaces the set atomically.)*

### `project_stages`
| Op | A | M | P | anon |
|---|---|---|---|---|
| select | ✅ | ✅ own project | ✅ assigned project | ⛔ |
| update | ✅ | ✅ own *(can_update_stages)* | ✅ assigned *(can_update_stages)* | ⛔ |
| insert/delete | ✅ (via project creation RPC) | seeded by RPC | ⛔ | ⛔ |

*(Stage transitions go through the `update_project_stage` RPC.)*

### `closure_requests`
| Op | A | M | P | anon |
|---|---|---|---|---|
| select | ✅ | ✅ own project | ✅ own submissions | ⛔ |
| insert | ✅ | ⛔ (managers approve, don't submit) | ✅ assigned *(can_request_closure)* | ⛔ |
| update (approve/reject) | ✅ | ✅ own project *(can_approve_closure)* | ⛔ | ⛔ |
| delete | ✅ | ⛔ | ⛔ | ⛔ |

*(Submit/approve/reject go through RPCs that also flip project status — see below.)*

### `project_deliverables`
| Op | A | M | P | anon |
|---|---|---|---|---|
| select | ✅ | ✅ own project | ✅ assigned project | ⛔ (only via tracking RPC, approved only) |
| insert/update (incl. approve) | ✅ | ✅ own project | ⛔ | ⛔ |
| delete | ✅ | ✅ own project | ⛔ | ⛔ |

### `client_reviews`
| Op | A | M | P | anon |
|---|---|---|---|---|
| select | ✅ | ✅ own project | ⛔ | ⛔ |
| insert | via RPC | via RPC | ⛔ | ✅ **via `submit_review` RPC only** |

---

## 3. Public (anon) access = RPC only

Public clients have **no direct table grants**. Two `security definer` RPCs expose exactly what the client screen needs:

```sql
-- DRAFT signatures (security definer, granted to anon)
-- Returns project public status + ONLY approved deliverable links for a serial.
create function track_by_serial(p_serial text) returns jsonb ...;

-- Inserts a client review (rating 1..5 + optional message) resolved by serial.
create function submit_review(p_serial text, p_rating int, p_message text) returns void ...;
```

Rules baked into these RPCs:
- Resolve `serial → project`; return `null`/empty when unknown.
- **Never** expose team, fees, internal notes, manager identity, or unapproved links.
- `submit_review` validates `rating between 1 and 5`.
- Rate-limit / basic abuse protection considered at the gateway (not a notification concern).

---

## 4. Write RPCs & the status invariants they protect

These enforce business rules that plain RLS can't (multi-row, multi-table transactions). All run `security definer` but **re-check the caller's role/feature inside** before mutating:

| RPC | Guard | Effect |
|---|---|---|
| `create_project(...)` | `is_admin() OR (has_role('manager') AND has_feature('can_add_project'))` | insert project + allocate serial + seed stages |
| `assign_team_roles(pid, rows)` | admin OR (manages_project(pid) AND `can_assign_photographers`) | replace team atomically |
| `update_project_stage(pid, sid, ...)` | admin OR ((manages_project OR assigned_to_project) AND `can_update_stages`) | cascade stage statuses |
| `submit_closure_request(pid, ...)` | assigned_to_project(pid) AND `can_request_closure`; reject if a pending one exists | insert + project → `pending_closure` |
| `approve_closure_request(rid)` | admin OR (manages own project AND `can_approve_closure`) | approve + project `completed` + all stages `done` |
| `reject_closure_request(rid, reason)` | same as approve | reject + project → `active` |

---

## 5. Enablement checklist (for the future apply-sprint)

- `alter table <t> enable row level security;` on **all** tables.
- Add a **default-deny** posture (no policy = no access) and then add the grants above.
- Create helper functions first (they're referenced by policies).
- Grant `execute` on public RPCs to `anon`; keep all other tables ungranted to `anon`.
- Verify with a **policy test matrix** (one test per row of §2) before pointing the app at it.

**Reminder:** this sprint documents the rules only. No RLS is enabled, no SQL is run.
