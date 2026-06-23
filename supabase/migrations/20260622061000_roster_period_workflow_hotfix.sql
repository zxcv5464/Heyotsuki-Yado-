-- Roster workflow Hotfix: periods are date-named and open for staff submission by default.

alter table public.roster_periods
  alter column status set default 'open';

create or replace function public.save_roster_period(
  p_period_id uuid,
  p_title text,
  p_date_from date,
  p_date_to date,
  p_slots jsonb,
  p_requirements jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_id uuid;
  period_status text;
  slot jsonb;
  requirement jsonb;
  generated_title text;
begin
  perform public.ensure_admin_permission('roster.manage');
  if p_date_from is null or p_date_to is null or p_date_to < p_date_from then
    raise exception 'Invalid roster period.';
  end if;
  generated_title := to_char(p_date_from, 'YYYY/MM/DD') || ' - ' || to_char(p_date_to, 'YYYY/MM/DD');

  if p_period_id is null then
    insert into public.roster_periods (title, date_from, date_to, status, submission_open_at, created_by, updated_by)
    values (generated_title, p_date_from, p_date_to, 'open', now(), auth.uid(), auth.uid())
    returning id into target_id;
  else
    select status into period_status from public.roster_periods where id = p_period_id for update;
    if period_status is null then raise exception 'Roster period not found.'; end if;
    if period_status in ('published', 'locked') then raise exception 'Published or locked roster periods cannot change structure.'; end if;
    update public.roster_periods
    set title = generated_title, date_from = p_date_from, date_to = p_date_to, updated_by = auth.uid()
    where id = p_period_id;
    target_id := p_period_id;
    delete from public.roster_shift_slots where period_id = target_id;
    delete from public.roster_period_role_requirements where period_id = target_id;
  end if;

  for slot in select value from jsonb_array_elements(coalesce(p_slots, '[]'::jsonb)) loop
    if (slot->>'businessDate')::date < p_date_from or (slot->>'businessDate')::date > p_date_to then
      raise exception 'Shift date is outside the roster period.';
    end if;
    insert into public.roster_shift_slots (period_id, business_date, label, start_time, end_time, sort_order, is_active)
    values (target_id, (slot->>'businessDate')::date, nullif(trim(slot->>'label'), ''), (slot->>'startTime')::time, (slot->>'endTime')::time, coalesce((slot->>'sortOrder')::integer, 0), coalesce((slot->>'isActive')::boolean, true));
  end loop;
  if not exists (select 1 from public.roster_shift_slots where period_id = target_id) then
    raise exception 'At least one shift slot is required.';
  end if;
  for requirement in select value from jsonb_array_elements(coalesce(p_requirements, '[]'::jsonb)) loop
    insert into public.roster_period_role_requirements (period_id, role_id, role_name_snapshot, min_staff_count, max_staff_count, sort_order, is_required)
    values (target_id, nullif(requirement->>'roleId', '')::uuid, nullif(trim(requirement->>'roleName'), ''), coalesce((requirement->>'minStaffCount')::integer, 0), greatest(1, coalesce((requirement->>'maxStaffCount')::integer, 1)), coalesce((requirement->>'sortOrder')::integer, 0), coalesce((requirement->>'isRequired')::boolean, true));
  end loop;
  if not exists (select 1 from public.roster_period_role_requirements where period_id = target_id) then
    raise exception 'At least one role requirement is required.';
  end if;
  return public.roster_snapshot(target_id);
end;
$$;

-- With the publish workflow removed, the current open period is the visible roster.
do $roster_open_schedule_visibility$
declare
  function_sql text;
  updated_sql text;
begin
  select pg_get_functiondef('public.roster_snapshot(uuid)'::regprocedure) into function_sql;
  updated_sql := replace(
    function_sql,
    'can_view and target_period.status in (''published'', ''locked'')',
    'can_view and target_period.status in (''open'', ''published'', ''locked'')'
  );
  if function_sql is null or updated_sql = function_sql then
    raise exception 'Roster snapshot visibility hotfix did not match expected function body.';
  end if;
  execute updated_sql;
end;
$roster_open_schedule_visibility$;
