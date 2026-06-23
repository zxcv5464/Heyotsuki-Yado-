-- Roster Hotfix: a closed submission period is read-only, not invisible.
-- Staff with roster.submit can view their own saved availability in both open
-- and draft (closed) periods. Writes remain restricted to open periods by
-- public.save_roster_availability.

create or replace function public.roster_snapshot(p_period_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_period public.roster_periods%rowtype;
  can_manage boolean := public.has_admin_permission('roster.manage');
  can_view boolean := public.has_admin_permission('roster.view');
  can_submit boolean := public.has_admin_permission('roster.submit');
  can_publish boolean := public.has_admin_permission('roster.publish');
  own_staff_id uuid := public.roster_current_staff_id();
begin
  if not can_manage and not can_view and not can_submit then
    raise exception 'Roster permission denied.';
  end if;

  select * into target_period
  from public.roster_periods
  where (p_period_id is null or id = p_period_id)
    and (
      can_manage
      or (can_submit and status in ('open', 'draft'))
      or (can_view and status in ('open', 'draft', 'published', 'locked'))
    )
  order by case status when 'open' then 0 when 'draft' then 1 when 'published' then 2 else 3 end,
           date_from desc
  limit 1;

  return jsonb_build_object(
    'canManage', can_manage,
    'canSubmit', can_submit,
    'canPublish', can_publish,
    'myStaffId', own_staff_id,
    'periods', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'title', title, 'dateFrom', date_from, 'dateTo', date_to,
        'status', status, 'submissionOpenAt', submission_open_at,
        'submissionClosedAt', submission_closed_at, 'publishedAt', published_at
      ) order by date_from desc)
      from public.roster_periods
      where can_manage
        or (can_submit and status in ('open', 'draft'))
        or (can_view and status in ('open', 'draft', 'published', 'locked'))
    ), '[]'::jsonb),
    'period', case when target_period.id is null then null else jsonb_build_object(
      'id', target_period.id, 'title', target_period.title,
      'dateFrom', target_period.date_from, 'dateTo', target_period.date_to,
      'status', target_period.status, 'submissionOpenAt', target_period.submission_open_at,
      'submissionClosedAt', target_period.submission_closed_at,
      'publishedAt', target_period.published_at
    ) end,
    'slots', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'businessDate', business_date, 'label', label,
        'startTime', start_time, 'endTime', end_time, 'sortOrder', sort_order,
        'isActive', is_active
      ) order by business_date, sort_order)
      from public.roster_shift_slots
      where period_id = target_period.id and (can_manage or is_active)
    ), '[]'::jsonb),
    'staff', case when can_manage then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'name', name, 'isVisible', is_visible, 'sortOrder', sort_order
      ) order by sort_order, name)
      from public.staff_members
      where is_visible
    ), '[]'::jsonb) else '[]'::jsonb end,
    'roles', case when can_manage then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'code', code, 'name', name, 'description', description,
        'minStaffCount', min_staff_count, 'maxStaffCount', max_staff_count,
        'sortOrder', sort_order, 'isActive', is_active
      ) order by sort_order, name)
      from public.roster_roles
    ), '[]'::jsonb) else '[]'::jsonb end,
    'requirements', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'roleId', role_id, 'roleName', role_name_snapshot,
        'minStaffCount', min_staff_count, 'maxStaffCount', max_staff_count,
        'sortOrder', sort_order, 'isRequired', is_required
      ) order by sort_order, role_name_snapshot)
      from public.roster_period_role_requirements
      where period_id = target_period.id
    ), '[]'::jsonb),
    'availability', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'shiftSlotId', shift_slot_id, 'staffId', staff_id,
        'status', status, 'note', note, 'updatedAt', updated_at
      ) order by shift_slot_id, staff_id)
      from public.roster_availability
      where period_id = target_period.id
        and (can_manage or staff_id = own_staff_id)
    ), '[]'::jsonb),
    'assignments', case when can_manage or (can_view and target_period.status in ('open', 'draft', 'published', 'locked')) then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'shiftSlotId', shift_slot_id, 'roleRequirementId', role_requirement_id,
        'staffId', staff_id, 'assignmentOrder', assignment_order, 'isManual', is_manual,
        'status', status, 'note', note
      ) order by shift_slot_id, role_requirement_id, assignment_order)
      from public.roster_assignments
      where period_id = target_period.id
    ), '[]'::jsonb) else '[]'::jsonb end
  );
end;
$$;

drop policy if exists "roster_periods_read" on public.roster_periods;
create policy "roster_periods_read" on public.roster_periods for select to authenticated
using (
  public.has_admin_permission('roster.manage')
  or (public.has_admin_permission('roster.submit') and status in ('open', 'draft'))
  or (public.has_admin_permission('roster.view') and status in ('open', 'draft', 'published', 'locked'))
);

drop policy if exists "roster_slots_read" on public.roster_shift_slots;
create policy "roster_slots_read" on public.roster_shift_slots for select to authenticated
using (
  public.has_admin_permission('roster.manage')
  or exists (
    select 1 from public.roster_periods
    where id = roster_shift_slots.period_id
      and (
        (public.has_admin_permission('roster.submit') and status in ('open', 'draft'))
        or (public.has_admin_permission('roster.view') and status in ('open', 'draft', 'published', 'locked'))
      )
  )
);

drop policy if exists "roster_assignments_read" on public.roster_assignments;
create policy "roster_assignments_read" on public.roster_assignments for select to authenticated
using (
  public.has_admin_permission('roster.manage')
  or (
    public.has_admin_permission('roster.view')
    and exists (
      select 1 from public.roster_periods
      where id = roster_assignments.period_id
        and status in ('open', 'draft', 'published', 'locked')
    )
  )
);

grant execute on function public.roster_snapshot(uuid) to authenticated;
