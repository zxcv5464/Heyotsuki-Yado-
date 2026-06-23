-- Allow a manager to fill only one shift without replacing manual choices.

create or replace function public.generate_roster_shift_assignments(
  p_period_id uuid,
  p_shift_slot_id uuid,
  p_use_standby boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  requirement_record record;
  selected_staff_id uuid;
  required_count integer;
  assigned_count integer;
  period_status text;
  optional_candidate_exists boolean;
begin
  perform public.ensure_admin_permission('roster.manage');

  select status into period_status
  from public.roster_periods
  where id = p_period_id
  for update;

  if period_status not in ('draft', 'open') then
    raise exception 'Only draft or open periods can generate assignments.';
  end if;

  if not exists (
    select 1
    from public.roster_shift_slots
    where id = p_shift_slot_id
      and period_id = p_period_id
      and is_active
  ) then
    raise exception 'Shift slot does not belong to this active roster period.';
  end if;

  -- Only discard previous automatic rows for this exact shift. Manual rows are
  -- deliberately retained and count toward the position requirement.
  delete from public.roster_assignments
  where period_id = p_period_id
    and shift_slot_id = p_shift_slot_id
    and not is_manual;

  for requirement_record in
    select *
    from public.roster_period_role_requirements
    where period_id = p_period_id
      and is_required
    order by sort_order, role_name_snapshot
  loop
    select count(*) into assigned_count
    from public.roster_assignments
    where shift_slot_id = p_shift_slot_id
      and role_requirement_id = requirement_record.id
      and status = 'assigned';

    required_count := greatest(requirement_record.min_staff_count, 0);
    if required_count = 0 and assigned_count = 0 then
      select exists (
        select 1
        from public.roster_availability availability
        join public.staff_members staff on staff.id = availability.staff_id and staff.is_visible
        where availability.period_id = p_period_id
          and availability.shift_slot_id = p_shift_slot_id
          and availability.status in ('available', case when p_use_standby then 'standby' else 'available' end)
          and not exists (
            select 1
            from public.roster_assignments assigned
            where assigned.shift_slot_id = p_shift_slot_id
              and assigned.staff_id = availability.staff_id
              and assigned.status = 'assigned'
          )
      ) into optional_candidate_exists;
      if optional_candidate_exists then required_count := 1; end if;
    end if;

    while assigned_count < required_count loop
      select availability.staff_id into selected_staff_id
      from public.roster_availability availability
      join public.staff_members staff on staff.id = availability.staff_id and staff.is_visible
      where availability.period_id = p_period_id
        and availability.shift_slot_id = p_shift_slot_id
        and availability.status in ('available', case when p_use_standby then 'standby' else 'available' end)
        and not exists (
          select 1
          from public.roster_assignments assigned
          where assigned.shift_slot_id = p_shift_slot_id
            and assigned.staff_id = availability.staff_id
            and assigned.status = 'assigned'
        )
      order by case availability.status when 'available' then 0 else 1 end,
        (select count(*) from public.roster_assignments prior where prior.period_id = p_period_id and prior.staff_id = availability.staff_id and prior.status = 'assigned'),
        staff.sort_order,
        staff.name
      limit 1;

      if selected_staff_id is null then
        exit;
      end if;

      insert into public.roster_assignments(
        period_id, shift_slot_id, role_requirement_id, staff_id, assignment_order,
        is_manual, status, created_by, updated_by
      ) values (
        p_period_id, p_shift_slot_id, requirement_record.id, selected_staff_id, assigned_count,
        false, 'assigned', auth.uid(), auth.uid()
      );
      assigned_count := assigned_count + 1;
      selected_staff_id := null;
    end loop;
  end loop;

  return public.roster_snapshot(p_period_id);
end;
$$;

revoke all on function public.generate_roster_shift_assignments(uuid, uuid, boolean) from public;
grant execute on function public.generate_roster_shift_assignments(uuid, uuid, boolean) to authenticated;
