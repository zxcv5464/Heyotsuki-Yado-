-- Manual draft assignments may only use staff who marked this shift as
-- available or standby. The picker mirrors this rule, but the RPC enforces it.

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

    if target_staff_id is not null and not exists (
      select 1
      from public.roster_availability availability
      where availability.period_id = p_period_id
        and availability.shift_slot_id = target_slot_id
        and availability.staff_id = target_staff_id
        and availability.status in ('available', 'standby')
    ) then
      raise exception 'Staff member is not available for this shift.';
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
