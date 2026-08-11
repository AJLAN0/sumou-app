-- =============================================================================
-- Sprint 11 · Step 11.5A — Safe closure-request display hydration.
--
-- One authenticated, least-privilege read RPC reproduces the existing closure
-- visibility model while deriving the parent-project and retained submitter
-- display names behind RLS. It changes no table, policy, workflow RPC, project
-- link, audit, or public-tracking contract.
-- =============================================================================

create or replace function public.list_visible_closure_requests()
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

  -- Explicit caller gate is mandatory because SECURITY DEFINER bypasses RLS.
  if not public.is_active_user() then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  v_is_admin := public.is_admin();

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', c.id,
        'project_id', c.project_id,
        'project_name', p.name,
        'submitted_by', c.submitted_by,
        'submitted_by_name', s.full_name,
        'created_at', c.created_at,
        'report_file_url', c.report_file_url,
        'delivery_link', c.delivery_link,
        'notes', c.notes,
        'status', c.status::text,
        'reject_reason', c.reject_reason,
        'reviewed_at', c.reviewed_at
      )
      order by c.created_at desc, c.id
    ),
    '[]'::jsonb
  )
  into v_result
  from public.closure_requests c
  join public.projects p
    on p.id = c.project_id
   and p.is_active
   and p.deleted_at is null
  -- Profiles are soft-deleted and closure_requests.submitted_by uses
  -- ON DELETE RESTRICT. Do not filter on submitter active/deleted state: the
  -- retained row supplies the historical display name. The inner join fails
  -- closed if referential integrity is ever violated.
  join public.profiles s on s.id = c.submitted_by
  where c.status in (
      'pending'::public.closure_status,
      'approved'::public.closure_status,
      'rejected'::public.closure_status
    )
    and (
      p.manager_id = v_uid
      or c.submitted_by = v_uid
      or v_is_admin
    );

  return v_result;
end;
$$;

comment on function public.list_visible_closure_requests() is
  'Authenticated safe closure-history read. Active callers receive only requests on live projects when they own the project, submitted the request, or are an active admin. Returns only the allowlisted closure fields plus project and retained submitter display names; no reviewer, manager, team, profile, audit, permission, project-detail, assignment, or unavailability data.';

revoke all on function public.list_visible_closure_requests() from public;
revoke all on function public.list_visible_closure_requests() from anon;
grant execute on function public.list_visible_closure_requests()
  to authenticated;
