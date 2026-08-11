-- =============================================================================
-- Sprint 11 · Step 11.4A — Manager-safe assignable-staff discovery.
--
-- One authenticated, least-privilege RPC returns only the internal staff ID,
-- display name, active photographer types, and an authoritative availability
-- boolean needed by the future assignment UI. It intentionally exposes no
-- identity, role, permission, leave, conflict, workload, assignment, audit, or
-- timestamp detail. No table/RLS/write contract changes are made here.
-- =============================================================================

create or replace function public.list_assignable_project_staff(
  p_on_date            date,
  p_exclude_project_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := auth.uid();
  v_is_admin boolean;
  v_result   jsonb;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;

  -- Explicit active-caller gate. The helper reads behind profile RLS and fails
  -- closed for disabled or soft-deleted staff.
  if not public.is_active_user() then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  v_is_admin := public.is_admin();
  if not (
    v_is_admin
    or public.has_feature('can_assign_photographers')
  ) then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  if p_on_date is null then
    raise exception 'assignment date is required' using errcode = '22023';
  end if;

  -- Exclusion is permitted only for a live project whose assignments can
  -- currently conflict, and only for an admin or that project's owner. One
  -- neutral predicate makes nonexistent, hidden, deleted, completed, rejected,
  -- and unrelated projects indistinguishable to the caller.
  if p_exclude_project_id is not null then
    perform 1
    from public.projects p
    where p.id = p_exclude_project_id
      and p.is_active
      and p.deleted_at is null
      and p.status in (
        'active'::public.project_status,
        'in_progress'::public.project_status
      )
      and (v_is_admin or p.manager_id = v_uid);
    if not found then
      raise exception 'project unavailable' using errcode = 'P0002';
    end if;
  end if;

  with eligible_types as (
    select distinct
      p.id as user_id,
      btrim(p.full_name) as full_name,
      lower(btrim(p.full_name)) collate "C" as normalized_name,
      pt.id as type_id,
      pt.code as type_code,
      pt.name_ar as type_name_ar
    from public.profiles p
    join public.user_photographer_types upt on upt.user_id = p.id
    join public.photographer_types pt on pt.id = upt.photographer_type_id
    where p.is_active
      and p.deleted_at is null
      and pt.is_active
      and pt.code in ('photo', 'video', 'instagram', 'design')
  ), candidates as (
    select
      et.user_id,
      et.full_name,
      et.normalized_name,
      jsonb_agg(
        jsonb_build_object(
          'id', et.type_id,
          'code', et.type_code,
          'name_ar', et.type_name_ar
        )
        order by et.type_code, et.type_id
      ) as photographer_types
    from eligible_types et
    group by et.user_id, et.full_name, et.normalized_name
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'user_id', c.user_id,
        'full_name', c.full_name,
        'photographer_types', c.photographer_types,
        'is_available', public.is_available(
          c.user_id,
          p_on_date,
          p_exclude_project_id
        )
      )
      order by c.normalized_name, c.user_id
    ),
    '[]'::jsonb
  )
  into v_result
  from candidates c;

  return v_result;
end;
$$;

comment on function public.list_assignable_project_staff(date, uuid) is
  'Authenticated manager-safe assignable-staff lookup. Caller must be active and either an active admin or hold effective can_assign_photographers. Returns only user_id, full_name, active allowlisted photographer_types (id/code/name_ar), and authoritative is_available; availability reasons and all identity/role/permission/leave/conflict/workload/assignment/audit details remain secret. A non-null exclusion project must be live in a team-editable working state and owned by the caller unless the caller is admin; inaccessible and nonexistent projects fail identically.';

revoke all on function public.list_assignable_project_staff(date, uuid)
  from public;
revoke all on function public.list_assignable_project_staff(date, uuid)
  from anon;
grant execute on function public.list_assignable_project_staff(date, uuid)
  to authenticated;
