-- Roster usability hotfix:
-- 1. Manual draft edits are saved as one validated transaction.
-- 2. Active roles with a minimum of zero still receive one automatic attempt.

create or replace function public.save_roster_assignment_draft(
  p_period_id uuid,
  p_assignments jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  period_status text;
  entry jsonb;
  entry_index integer := 0;
  target_slot_id uuid;
  target_requirement_id uuid;
  target_staff_id uuid;
  target_status text;
begin
  perform public.ensure_admin_permission('roster.manage');
  select status into period_status
  from public.roster_periods
  where id = p_period_id
  for update;

  if period_status is null then raise exception 'Roster period not found.'; end if;
  if period_status not in ('draft', 'open') then raise exception 'Only draft or open periods can change assignments.'; end if;
  if jsonb_typeof(coalesce(p_assignments, '[]'::jsonb)) <> 'array' then raise exception 'Assignments must be an array.'; end if;

  delete from public.roster_assignments where period_id = p_period_id;

  for entry in select value from jsonb_array_elements(coalesce(p_assignments, '[]'::jsonb)) loop
    target_slot_id := nullif(entry->>'shiftSlotId', '')::uuid;
    target_requirement_id := nullif(entry->>'roleRequirementId', '')::uuid;
    target_staff_id := nullif(entry->>'staffId', '')::uuid;
    target_status := coalesce(entry->>'status', case when target_staff_id is null then 'pending' else 'assigned' end);

    if target_status not in ('assigned', 'pending')
      or (target_status = 'assigned' and target_staff_id is null)
      or (target_status = 'pending' and target_staff_id is not null) then
      raise exception 'Invalid draft assignment.';
    end if;
    if not exists (select 1 from public.roster_shift_slots where id = target_slot_id and period_id = p_period_id)
      or not exists (select 1 from public.roster_period_role_requirements where id = target_requirement_id and period_id = p_period_id) then
      raise exception 'Assignment does not belong to this period.';
    end if;
    if target_staff_id is not null and not exists (select 1 from public.staff_members where id = target_staff_id) then
      raise exception 'Staff member was not found.';
    end if;

    insert into public.roster_assignments (
      period_id, shift_slot_id, role_requirement_id, staff_id, assignment_order,
      is_manual, status, created_by, updated_by
    ) values (
      p_period_id, target_slot_id, target_requirement_id, target_staff_id, entry_index,
      coalesce((entry->>'isManual')::boolean, true), target_status, auth.uid(), auth.uid()
    );
    entry_index := entry_index + 1;
  end loop;

  if exists (
    select 1
    from public.roster_assignments assignment
    join public.roster_period_role_requirements requirement on requirement.id = assignment.role_requirement_id
    where assignment.period_id = p_period_id and assignment.status = 'assigned'
    group by assignment.shift_slot_id, assignment.role_requirement_id, requirement.max_staff_count
    having count(*) > requirement.max_staff_count
  ) then raise exception 'A role exceeds its maximum staff count.'; end if;

  if exists (
    select 1
    from public.roster_assignments
    where period_id = p_period_id and status = 'assigned'
    group by shift_slot_id, staff_id
    having count(*) > 1
  ) then raise exception 'A staff member cannot hold multiple roles in the same shift.'; end if;

  return public.roster_snapshot(p_period_id);
end;
$$;

create or replace function public.generate_roster_assignments(
  p_period_id uuid,
  p_use_standby boolean default false,
  p_clear_existing boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  slot_record record;
  requirement_record record;
  selected_staff_id uuid;
  required_count integer;
  assigned_count integer;
  period_status text;
begin
  perform public.ensure_admin_permission('roster.manage');
  select status into period_status from public.roster_periods where id = p_period_id for update;
  if period_status not in ('draft', 'open') then raise exception 'Only draft or open periods can generate assignments.'; end if;
  if p_clear_existing then delete from public.roster_assignments where period_id = p_period_id;
  else delete from public.roster_assignments where period_id = p_period_id and not is_manual; end if;

  for slot_record in select * from public.roster_shift_slots where period_id = p_period_id and is_active order by business_date, sort_order loop
    for requirement_record in select * from public.roster_period_role_requirements where period_id = p_period_id and is_required order by sort_order, role_name_snapshot loop
      select count(*) into assigned_count from public.roster_assignments where shift_slot_id = slot_record.id and role_requirement_id = requirement_record.id and status = 'assigned';
      required_count := greatest(requirement_record.min_staff_count, 1);
      while assigned_count < required_count loop
        select availability.staff_id into selected_staff_id
        from public.roster_availability as availability
        join public.staff_members as staff on staff.id = availability.staff_id and staff.is_visible
        where availability.period_id = p_period_id and availability.shift_slot_id = slot_record.id
          and availability.status in ('available', case when p_use_standby then 'standby' else 'available' end)
          and not exists (
            select 1 from public.roster_assignments as assigned
            where assigned.shift_slot_id = slot_record.id
              and assigned.staff_id = availability.staff_id
              and assigned.status = 'assigned'
          )
        order by case availability.status when 'available' then 0 else 1 end,
          (select count(*) from public.roster_assignments as prior where prior.period_id = p_period_id and prior.staff_id = availability.staff_id and prior.status = 'assigned'),
          staff.sort_order, staff.name
        limit 1;
        if selected_staff_id is null then
          insert into public.roster_assignments(period_id, shift_slot_id, role_requirement_id, staff_id, assignment_order, is_manual, status, created_by, updated_by)
          values (p_period_id, slot_record.id, requirement_record.id, null, assigned_count, false, 'pending', auth.uid(), auth.uid());
        else
          insert into public.roster_assignments(period_id, shift_slot_id, role_requirement_id, staff_id, assignment_order, is_manual, status, created_by, updated_by)
          values (p_period_id, slot_record.id, requirement_record.id, selected_staff_id, assigned_count, false, 'assigned', auth.uid(), auth.uid());
        end if;
        assigned_count := assigned_count + 1;
        selected_staff_id := null;
      end loop;
    end loop;
  end loop;
  return public.roster_snapshot(p_period_id);
end;
$$;

revoke all on function public.save_roster_assignment_draft(uuid, jsonb) from public;
grant execute on function public.save_roster_assignment_draft(uuid, jsonb) to authenticated;
