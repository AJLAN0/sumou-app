-- =============================================================================
-- Sprint 11 · Step 11.6A — close the residual project-team type-integrity gap.
--
-- Forward-only hardening of the existing internal helper. Its signature,
-- return type, caller contracts, replace-all behavior, profile lock order,
-- availability rules, external-member behavior, value metadata, and audit
-- payload remain unchanged. The only behavioral hardening is that every member
-- must select at least one active photographer type and every internal member
-- must actually hold each selected type in user_photographer_types.
--
-- All validation still completes before the existing team is deleted. The
-- helper remains internal and is not executable by API roles.
-- =============================================================================

create or replace function public._apply_project_team(
  p_project_id uuid,
  p_members    jsonb
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid       uuid := auth.uid();
  v_members   jsonb := coalesce(p_members, '[]'::jsonb);
  m           jsonb;
  v_user_ids  uuid[] := '{}';
  v_muid      uuid;
  v_pname     text;
  v_value     numeric;
  v_date      date;
  v_member_id uuid;
  v_tid       uuid;
  v_count     integer := 0;
begin
  if jsonb_typeof(v_members) <> 'array' then
    raise exception 'invalid team payload' using errcode = '22023';
  end if;

  -- ---- validate the complete proposed team BEFORE any delete --------------
  -- The outer array may be empty: [] remains the approved clear-team command.
  for m in select value from jsonb_array_elements(v_members) loop
    v_count := v_count + 1;

    -- each member must be a JSON object.
    if jsonb_typeof(m) <> 'object' then
      raise exception 'each team member must be a JSON object' using errcode = '22023';
    end if;

    -- Every proposed member must explicitly select at least one type. Missing,
    -- JSON null, non-array, and empty arrays all fail before any team deletion.
    if not (m ? 'photographer_type_ids')
       or jsonb_typeof(m->'photographer_type_ids') <> 'array' then
      raise exception 'invalid photographer type selection' using errcode = '22023';
    end if;
    if jsonb_array_length(m->'photographer_type_ids') = 0 then
      raise exception 'invalid photographer type selection' using errcode = '22023';
    end if;
    -- Every photographer type id must be a JSON string containing a
    -- well-formed UUID. JSON null and other scalar/object values fail closed.
    if exists (
      select 1
      from jsonb_array_elements(m->'photographer_type_ids') as e(v)
      where jsonb_typeof(e.v) <> 'string'
         or (e.v #>> '{}') !~*
            '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    ) then
      raise exception 'invalid photographer type selection' using errcode = '22023';
    end if;
    -- UUID equality, rather than JSON text equality, also rejects duplicate
    -- spellings that differ only by letter case.
    if (select count(*)
          from jsonb_array_elements_text(m->'photographer_type_ids'))
       <> (select count(distinct (value)::uuid)
             from jsonb_array_elements_text(m->'photographer_type_ids')) then
      raise exception 'invalid photographer type selection' using errcode = '22023';
    end if;

    -- value, if present, must be a JSON number (or null → treated as 0).
    if (m ? 'value') and jsonb_typeof(m->'value') not in ('number', 'null') then
      raise exception 'value must be numeric' using errcode = '22023';
    end if;

    if m->>'user_id' is not null then
      -- INTERNAL member: user_id must be a well-formed UUID; the stored
      -- person_name is derived from the profile (never the client input).
      if (m->>'user_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
        raise exception 'invalid user_id' using errcode = '22023';
      end if;
      v_muid := (m->>'user_id')::uuid;
      if v_muid = any (v_user_ids) then
        raise exception 'a user is assigned more than once' using errcode = '22023';
      end if;
      v_user_ids := array_append(v_user_ids, v_muid);
      if m->>'date' is null or btrim(m->>'date') = '' then
        raise exception 'assignment date is required for internal members'
          using errcode = '22023';
      end if;
    else
      -- EXTERNAL member: user_id null; a non-blank person_name is required and is
      -- stored as given (no profile/Auth account is created).
      if btrim(coalesce(m->>'person_name', '')) = '' then
        raise exception 'person_name is required for external members'
          using errcode = '22023';
      end if;
    end if;
  end loop;

  -- ---- lock internal profiles in deterministic uuid order ----------------
  -- Serializes concurrent assignments of the same user across projects, so two
  -- transactions cannot both pass availability for the same user. Ordered
  -- locking also reduces deadlock risk.
  perform 1 from public.profiles p
    where p.id = any (v_user_ids)
    order by p.id
    for update;

  -- ---- verify members + types + availability (post-lock) -----------------
  for m in select value from jsonb_array_elements(v_members) loop
    if (m->>'user_id') is not null then
      v_muid := (m->>'user_id')::uuid;
      v_date := (m->>'date')::date;
      perform 1 from public.profiles p
        where p.id = v_muid and p.is_active and p.deleted_at is null;
      if not found then
        raise exception 'an assigned member is not an active profile'
          using errcode = 'P0002';
      end if;
      -- availability re-checked AFTER the profile lock; exclude THIS project so
      -- the member's own existing row here is not a self-conflict.
      if not public.is_available(v_muid, v_date, p_project_id) then
        raise exception 'an assigned member is not available on the assignment date'
          using errcode = 'P0001';
      end if;
    else
      -- External members have no user/type membership relation.
      v_muid := null;
    end if;

    -- Every selected type must be active. Internal members must additionally
    -- hold that exact UUID relation. One generic P0002 hides whether the catalog
    -- row is missing/inactive or the internal membership relation is absent.
    for v_tid in
      select (value)::uuid
      from jsonb_array_elements_text(m->'photographer_type_ids')
    loop
      perform 1
      from public.photographer_types pt
      where pt.id = v_tid
        and pt.is_active
        and (
          v_muid is null
          or exists (
            select 1
            from public.user_photographer_types upt
            where upt.user_id = v_muid
              and upt.photographer_type_id = v_tid
          )
        );
      if not found then
        raise exception 'a selected photographer type is not available'
          using errcode = 'P0002';
      end if;
    end loop;
  end loop;

  -- ---- replace-all: delete existing (cascade drops types) then insert -----
  delete from public.project_team_members where project_id = p_project_id;

  for m in select value from jsonb_array_elements(v_members) loop
    v_value := coalesce((m->>'value')::numeric, 0);
    if m->>'user_id' is not null then
      -- INTERNAL: authoritative name from the locked+verified profile — the
      -- client-supplied person_name is never used for an internal member.
      v_muid := (m->>'user_id')::uuid;
      select p.full_name into v_pname from public.profiles p where p.id = v_muid;
      v_date := (m->>'date')::date;
    else
      -- EXTERNAL: normalized input name; date optional (no availability check).
      v_muid  := null;
      v_pname := btrim(m->>'person_name');
      v_date  := nullif(btrim(coalesce(m->>'date', '')), '')::date;
    end if;

    insert into public.project_team_members (project_id, user_id, person_name, value, date)
    values (p_project_id, v_muid, v_pname, v_value, v_date)
    returning id into v_member_id;

    insert into public.project_team_types (team_member_id, photographer_type_id)
    select v_member_id, (value)::uuid
    from jsonb_array_elements_text(m->'photographer_type_ids');
  end loop;

  -- audit: member count only (never names/values/dates/types/leave).
  insert into public.audit_logs (actor_id, action, entity, entity_id, meta)
  values (v_uid, 'project.team.assign', 'projects', p_project_id,
          jsonb_build_object('member_count', v_count));

  return v_count;
end;
$$;

-- Internal helper: same-owner SECURITY DEFINER callers retain owner execution,
-- while no API caller can invoke this authorization-free function directly.
revoke all on function public._apply_project_team(uuid, jsonb) from public;
revoke all on function public._apply_project_team(uuid, jsonb) from anon;
revoke all on function public._apply_project_team(uuid, jsonb) from authenticated;
