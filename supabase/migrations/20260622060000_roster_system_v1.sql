-- Roster system v1. This is intentionally independent from payroll settlement.

insert into public.admin_permission_definitions (permission_key, label, description, category, sort_order, is_system) values
  ('roster.view', '查看班表', '查看已發布班表。', '排班', 240, true),
  ('roster.submit', '填寫可上班狀態', '填寫自己對應員工的可上班狀態。', '排班', 250, true),
  ('roster.manage', '管理排班', '管理期間、班別、職位、可上班矩陣與草稿。', '排班', 260, true),
  ('roster.publish', '發布班表', '發布正式班表與鎖定歷史班表。', '排班', 270, true)
on conflict (permission_key) do update set
  label = excluded.label, description = excluded.description, category = excluded.category,
  sort_order = excluded.sort_order, is_system = true;

create table if not exists public.roster_periods (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  date_from date not null,
  date_to date not null,
  status text not null default 'draft' check (status in ('draft', 'open', 'published', 'locked')),
  submission_open_at timestamptz,
  submission_closed_at timestamptz,
  published_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (date_to >= date_from)
);

create table if not exists public.roster_shift_slots (
  id uuid primary key default gen_random_uuid(),
  period_id uuid not null references public.roster_periods(id) on delete cascade,
  business_date date not null,
  label text not null,
  start_time time not null,
  end_time time not null,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (period_id, business_date, sort_order),
  check (end_time <> start_time)
);

create table if not exists public.roster_roles (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  min_staff_count integer not null default 0 check (min_staff_count >= 0),
  max_staff_count integer not null default 1 check (max_staff_count >= 1),
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (max_staff_count >= min_staff_count)
);

create table if not exists public.roster_period_role_requirements (
  id uuid primary key default gen_random_uuid(),
  period_id uuid not null references public.roster_periods(id) on delete cascade,
  role_id uuid references public.roster_roles(id) on delete set null,
  role_name_snapshot text not null,
  min_staff_count integer not null default 0 check (min_staff_count >= 0),
  max_staff_count integer not null default 1 check (max_staff_count >= 1),
  sort_order integer not null default 0,
  is_required boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (max_staff_count >= min_staff_count),
  unique (period_id, role_id)
);

create table if not exists public.roster_availability (
  id uuid primary key default gen_random_uuid(),
  period_id uuid not null references public.roster_periods(id) on delete cascade,
  shift_slot_id uuid not null references public.roster_shift_slots(id) on delete cascade,
  staff_id uuid not null references public.staff_members(id) on delete cascade,
  status text not null default 'unselected' check (status in ('unselected', 'available', 'unavailable', 'standby')),
  note text,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (shift_slot_id, staff_id)
);

create table if not exists public.roster_assignments (
  id uuid primary key default gen_random_uuid(),
  period_id uuid not null references public.roster_periods(id) on delete cascade,
  shift_slot_id uuid not null references public.roster_shift_slots(id) on delete cascade,
  role_requirement_id uuid not null references public.roster_period_role_requirements(id) on delete cascade,
  staff_id uuid references public.staff_members(id) on delete set null,
  assignment_order integer not null default 0,
  is_manual boolean not null default false,
  status text not null default 'assigned' check (status in ('assigned', 'pending')),
  note text,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((status = 'pending' and staff_id is null) or (status = 'assigned' and staff_id is not null))
);

create index if not exists roster_shift_slots_period_date_idx on public.roster_shift_slots(period_id, business_date, sort_order);
create index if not exists roster_availability_period_staff_idx on public.roster_availability(period_id, staff_id);
create index if not exists roster_assignments_period_slot_idx on public.roster_assignments(period_id, shift_slot_id, role_requirement_id);

do $triggers$
declare table_name text;
begin
  foreach table_name in array array['roster_periods', 'roster_shift_slots', 'roster_roles', 'roster_period_role_requirements', 'roster_availability', 'roster_assignments']
  loop
    execute format('drop trigger if exists %I on public.%I', table_name || '_set_updated_at', table_name);
    execute format('create trigger %I before update on public.%I for each row execute function public.set_updated_at()', table_name || '_set_updated_at', table_name);
  end loop;
end;
$triggers$;

insert into public.roster_roles (code, name, min_staff_count, max_staff_count, sort_order) values
  ('moon-welcome-lead', '月迎領班', 1, 1, 10),
  ('moon-record-lead', '月錄領班', 1, 1, 20),
  ('moon-guide', '月引娘', 0, 1, 30),
  ('banquet-attendant', '宴席娘', 1, 2, 40),
  ('banquet-chief', '月宴長', 0, 1, 50),
  ('banquet-deputy', '月宴副長', 0, 1, 60),
  ('meal-attendant', '奉膳娘', 0, 2, 70),
  ('bath-attendant', '湯娘', 0, 99, 80),
  ('moon-attendant', '月娘', 0, 99, 90),
  ('moon-poet', '月詠師', 0, 1, 100)
on conflict (code) do nothing;

-- Give the existing system templates their intended roster access, then propagate
-- those additions to profiles that are actually using the templates.
insert into public.admin_permission_template_items (template_id, permission_key)
select templates.id, permissions.permission_key
from public.admin_permission_templates as templates
join (values
  ('管理員', 'roster.view'), ('管理員', 'roster.submit'), ('管理員', 'roster.manage'), ('管理員', 'roster.publish'),
  ('櫃檯／營運', 'roster.view'), ('櫃檯／營運', 'roster.manage'),
  ('一般員工', 'roster.view'), ('一般員工', 'roster.submit')
) as permissions(template_name, permission_key) on templates.name = permissions.template_name
on conflict (template_id, permission_key) do update set is_enabled = true;

insert into public.admin_profile_permissions (profile_id, permission_key)
select profiles.id, items.permission_key
from public.admin_profiles as profiles
join public.admin_permission_template_items as items on items.template_id = profiles.permission_template_id and items.is_enabled
where items.permission_key like 'roster.%' and profiles.role <> 'owner'
on conflict (profile_id, permission_key) do update set is_enabled = true;

create or replace function public.roster_current_staff_id()
returns uuid language sql stable security definer set search_path = pg_catalog, public as $$
  select staff_id from public.admin_profiles where id = auth.uid() and is_active;
$$;

create or replace function public.roster_snapshot(p_period_id uuid default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  target_period public.roster_periods%rowtype;
  can_manage boolean := public.has_admin_permission('roster.manage');
  can_view boolean := public.has_admin_permission('roster.view');
  can_submit boolean := public.has_admin_permission('roster.submit');
  can_publish boolean := public.has_admin_permission('roster.publish');
  own_staff_id uuid := public.roster_current_staff_id();
begin
  if not can_manage and not can_view and not can_submit then raise exception 'Roster permission denied.'; end if;
  select * into target_period from public.roster_periods
  where (p_period_id is null or id = p_period_id)
    and (can_manage or (can_submit and status = 'open') or (can_view and status in ('published', 'locked')))
  order by case status when 'open' then 0 when 'draft' then 1 when 'published' then 2 else 3 end, date_from desc
  limit 1;
  return jsonb_build_object(
    'canManage', can_manage, 'canSubmit', can_submit, 'canPublish', can_publish, 'myStaffId', own_staff_id,
    'periods', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'title', title, 'dateFrom', date_from, 'dateTo', date_to, 'status', status, 'submissionOpenAt', submission_open_at, 'submissionClosedAt', submission_closed_at, 'publishedAt', published_at) order by date_from desc) from public.roster_periods where can_manage or (can_submit and status = 'open') or (can_view and status in ('published', 'locked'))), '[]'::jsonb),
    'period', case when target_period.id is null then null else jsonb_build_object('id', target_period.id, 'title', target_period.title, 'dateFrom', target_period.date_from, 'dateTo', target_period.date_to, 'status', target_period.status, 'submissionOpenAt', target_period.submission_open_at, 'submissionClosedAt', target_period.submission_closed_at, 'publishedAt', target_period.published_at) end,
    'slots', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'businessDate', business_date, 'label', label, 'startTime', start_time, 'endTime', end_time, 'sortOrder', sort_order, 'isActive', is_active) order by business_date, sort_order) from public.roster_shift_slots where period_id = target_period.id and (can_manage or is_active)), '[]'::jsonb),
    'staff', case when can_manage then coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'isVisible', is_visible, 'sortOrder', sort_order) order by sort_order, name) from public.staff_members where is_visible), '[]'::jsonb) else '[]'::jsonb end,
    'roles', case when can_manage then coalesce((select jsonb_agg(jsonb_build_object('id', id, 'code', code, 'name', name, 'description', description, 'minStaffCount', min_staff_count, 'maxStaffCount', max_staff_count, 'sortOrder', sort_order, 'isActive', is_active) order by sort_order, name) from public.roster_roles), '[]'::jsonb) else '[]'::jsonb end,
    'requirements', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'roleId', role_id, 'roleName', role_name_snapshot, 'minStaffCount', min_staff_count, 'maxStaffCount', max_staff_count, 'sortOrder', sort_order, 'isRequired', is_required) order by sort_order, role_name_snapshot) from public.roster_period_role_requirements where period_id = target_period.id), '[]'::jsonb),
    'availability', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'shiftSlotId', shift_slot_id, 'staffId', staff_id, 'status', status, 'note', note, 'updatedAt', updated_at) order by shift_slot_id, staff_id) from public.roster_availability where period_id = target_period.id and (can_manage or staff_id = own_staff_id)), '[]'::jsonb),
    'assignments', case when can_manage or (can_view and target_period.status in ('published', 'locked')) then coalesce((select jsonb_agg(jsonb_build_object('id', id, 'shiftSlotId', shift_slot_id, 'roleRequirementId', role_requirement_id, 'staffId', staff_id, 'assignmentOrder', assignment_order, 'isManual', is_manual, 'status', status, 'note', note) order by shift_slot_id, role_requirement_id, assignment_order) from public.roster_assignments where period_id = target_period.id), '[]'::jsonb) else '[]'::jsonb end
  );
end;
$$;

create or replace function public.save_roster_period(p_period_id uuid, p_title text, p_date_from date, p_date_to date, p_slots jsonb, p_requirements jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare target_id uuid; period_status text; slot jsonb; requirement jsonb;
begin
  perform public.ensure_admin_permission('roster.manage');
  if nullif(trim(coalesce(p_title, '')), '') is null or p_date_from is null or p_date_to is null or p_date_to < p_date_from then raise exception 'Invalid roster period.'; end if;
  if p_period_id is null then
    insert into public.roster_periods(title, date_from, date_to, created_by, updated_by) values (trim(p_title), p_date_from, p_date_to, auth.uid(), auth.uid()) returning id into target_id;
  else
    select status into period_status from public.roster_periods where id = p_period_id for update;
    if period_status is null then raise exception 'Roster period not found.'; end if;
    if period_status in ('published', 'locked') then raise exception 'Published or locked roster periods cannot change structure.'; end if;
    update public.roster_periods set title = trim(p_title), date_from = p_date_from, date_to = p_date_to, updated_by = auth.uid() where id = p_period_id;
    target_id := p_period_id;
    delete from public.roster_shift_slots where period_id = target_id;
    delete from public.roster_period_role_requirements where period_id = target_id;
  end if;
  for slot in select value from jsonb_array_elements(coalesce(p_slots, '[]'::jsonb)) loop
    insert into public.roster_shift_slots(period_id, business_date, label, start_time, end_time, sort_order, is_active)
    values (target_id, (slot->>'businessDate')::date, nullif(trim(slot->>'label'), ''), (slot->>'startTime')::time, (slot->>'endTime')::time, coalesce((slot->>'sortOrder')::integer, 0), coalesce((slot->>'isActive')::boolean, true));
  end loop;
  if not exists (select 1 from public.roster_shift_slots where period_id = target_id) then raise exception 'At least one shift slot is required.'; end if;
  for requirement in select value from jsonb_array_elements(coalesce(p_requirements, '[]'::jsonb)) loop
    insert into public.roster_period_role_requirements(period_id, role_id, role_name_snapshot, min_staff_count, max_staff_count, sort_order, is_required)
    values (target_id, nullif(requirement->>'roleId', '')::uuid, nullif(trim(requirement->>'roleName'), ''), coalesce((requirement->>'minStaffCount')::integer, 0), greatest(1, coalesce((requirement->>'maxStaffCount')::integer, 1)), coalesce((requirement->>'sortOrder')::integer, 0), coalesce((requirement->>'isRequired')::boolean, true));
  end loop;
  if not exists (select 1 from public.roster_period_role_requirements where period_id = target_id) then raise exception 'At least one role requirement is required.'; end if;
  return public.roster_snapshot(target_id);
end;
$$;

create or replace function public.set_roster_period_status(p_period_id uuid, p_status text)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare current_status text;
begin
  if p_status not in ('draft', 'open', 'published', 'locked') then raise exception 'Invalid roster status.'; end if;
  if p_status in ('published', 'locked') then perform public.ensure_admin_permission('roster.publish'); else perform public.ensure_admin_permission('roster.manage'); end if;
  select status into current_status from public.roster_periods where id = p_period_id for update;
  if current_status is null then raise exception 'Roster period not found.'; end if;
  if current_status = 'locked' then raise exception 'Locked roster periods cannot change.'; end if;
  update public.roster_periods set status = p_status, submission_open_at = case when p_status = 'open' then now() else submission_open_at end, submission_closed_at = case when p_status in ('published', 'locked') then now() else submission_closed_at end, published_at = case when p_status = 'published' then now() else published_at end, updated_by = auth.uid() where id = p_period_id;
  return public.roster_snapshot(p_period_id);
end;
$$;

create or replace function public.save_roster_availability(p_period_id uuid, p_entries jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare entry jsonb; period_status text; own_staff_id uuid := public.roster_current_staff_id(); can_manage boolean := public.has_admin_permission('roster.manage'); target_staff uuid; target_slot uuid; target_status text;
begin
  if not can_manage then perform public.ensure_admin_permission('roster.submit'); end if;
  select status into period_status from public.roster_periods where id = p_period_id;
  if period_status is null then raise exception 'Roster period not found.'; end if;
  if not can_manage and period_status <> 'open' then raise exception 'Availability submission is closed.'; end if;
  if not can_manage and own_staff_id is null then raise exception 'This account is not linked to a staff member.'; end if;
  for entry in select value from jsonb_array_elements(coalesce(p_entries, '[]'::jsonb)) loop
    target_staff := (entry->>'staffId')::uuid; target_slot := (entry->>'shiftSlotId')::uuid; target_status := coalesce(entry->>'status', 'unselected');
    if target_status not in ('unselected', 'available', 'unavailable', 'standby') then raise exception 'Invalid availability status.'; end if;
    if not can_manage and target_staff <> own_staff_id then raise exception 'You can only update your own availability.'; end if;
    if not exists (select 1 from public.roster_shift_slots where id = target_slot and period_id = p_period_id) then raise exception 'Shift slot does not belong to this period.'; end if;
    insert into public.roster_availability(period_id, shift_slot_id, staff_id, status, note, updated_by)
    values (p_period_id, target_slot, target_staff, target_status, nullif(trim(entry->>'note'), ''), auth.uid())
    on conflict (shift_slot_id, staff_id) do update set status = excluded.status, note = excluded.note, updated_by = auth.uid();
  end loop;
  return public.roster_snapshot(p_period_id);
end;
$$;

create or replace function public.save_roster_role(p_role_id uuid, p_code text, p_name text, p_description text, p_min_staff_count integer, p_max_staff_count integer, p_sort_order integer, p_is_active boolean)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
begin
  perform public.ensure_admin_permission('roster.manage');
  if nullif(trim(coalesce(p_code, '')), '') is null or nullif(trim(coalesce(p_name, '')), '') is null or coalesce(p_min_staff_count, -1) < 0 or coalesce(p_max_staff_count, 0) < greatest(1, coalesce(p_min_staff_count, 0)) then raise exception 'Invalid roster role.'; end if;
  if p_role_id is null then insert into public.roster_roles(code, name, description, min_staff_count, max_staff_count, sort_order, is_active) values (trim(p_code), trim(p_name), nullif(trim(coalesce(p_description, '')), ''), p_min_staff_count, p_max_staff_count, coalesce(p_sort_order, 0), coalesce(p_is_active, true));
  else update public.roster_roles set code = trim(p_code), name = trim(p_name), description = nullif(trim(coalesce(p_description, '')), ''), min_staff_count = p_min_staff_count, max_staff_count = p_max_staff_count, sort_order = coalesce(p_sort_order, 0), is_active = coalesce(p_is_active, true) where id = p_role_id; end if;
  return public.roster_snapshot(null);
end;
$$;

create or replace function public.save_roster_assignment(p_assignment_id uuid, p_period_id uuid, p_shift_slot_id uuid, p_role_requirement_id uuid, p_staff_id uuid, p_status text, p_is_manual boolean, p_note text)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare period_status text; next_order integer; maximum_count integer; current_count integer;
begin
  perform public.ensure_admin_permission('roster.manage');
  select status into period_status from public.roster_periods where id = p_period_id;
  if period_status not in ('draft', 'open') then raise exception 'Only draft or open periods can change assignments.'; end if;
  if p_status not in ('assigned', 'pending') or (p_status = 'assigned' and p_staff_id is null) or (p_status = 'pending' and p_staff_id is not null) then raise exception 'Invalid assignment.'; end if;
  if not exists (select 1 from public.roster_shift_slots where id = p_shift_slot_id and period_id = p_period_id) or not exists (select 1 from public.roster_period_role_requirements where id = p_role_requirement_id and period_id = p_period_id) then raise exception 'Assignment does not belong to this period.'; end if;
  if p_staff_id is not null and not exists (select 1 from public.staff_members where id = p_staff_id) then raise exception 'Staff member was not found.'; end if;
  if p_status = 'assigned' then
    select max_staff_count into maximum_count from public.roster_period_role_requirements where id = p_role_requirement_id;
    select count(*) into current_count from public.roster_assignments where shift_slot_id = p_shift_slot_id and role_requirement_id = p_role_requirement_id and status = 'assigned' and (p_assignment_id is null or id <> p_assignment_id);
    if current_count >= maximum_count then raise exception 'This role has reached its maximum staff count.'; end if;
  end if;
  if p_assignment_id is null then
    select coalesce(max(assignment_order), -1) + 1 into next_order from public.roster_assignments where shift_slot_id = p_shift_slot_id and role_requirement_id = p_role_requirement_id;
    insert into public.roster_assignments(period_id, shift_slot_id, role_requirement_id, staff_id, assignment_order, is_manual, status, note, created_by, updated_by) values (p_period_id, p_shift_slot_id, p_role_requirement_id, p_staff_id, next_order, coalesce(p_is_manual, true), p_status, nullif(trim(coalesce(p_note, '')), ''), auth.uid(), auth.uid());
  else
    update public.roster_assignments set staff_id = p_staff_id, status = p_status, is_manual = coalesce(p_is_manual, true), note = nullif(trim(coalesce(p_note, '')), ''), updated_by = auth.uid() where id = p_assignment_id and period_id = p_period_id;
  end if;
  return public.roster_snapshot(p_period_id);
end;
$$;

create or replace function public.delete_roster_assignment(p_assignment_id uuid)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare target_period_id uuid;
begin
  perform public.ensure_admin_permission('roster.manage');
  select period_id into target_period_id from public.roster_assignments where id = p_assignment_id;
  if target_period_id is null then raise exception 'Assignment not found.'; end if;
  if exists (select 1 from public.roster_periods where id = target_period_id and status not in ('draft', 'open')) then raise exception 'Only draft or open periods can change assignments.'; end if;
  delete from public.roster_assignments where id = p_assignment_id;
  return public.roster_snapshot(target_period_id);
end;
$$;

create or replace function public.generate_roster_assignments(p_period_id uuid, p_use_standby boolean default false, p_clear_existing boolean default false)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare slot_record record; requirement_record record; selected_staff_id uuid; required_count integer; assigned_count integer; period_status text;
begin
  perform public.ensure_admin_permission('roster.manage');
  select status into period_status from public.roster_periods where id = p_period_id for update;
  if period_status not in ('draft', 'open') then raise exception 'Only draft or open periods can generate assignments.'; end if;
  if p_clear_existing then delete from public.roster_assignments where period_id = p_period_id; else delete from public.roster_assignments where period_id = p_period_id and not is_manual; end if;
  for slot_record in select * from public.roster_shift_slots where period_id = p_period_id and is_active order by business_date, sort_order loop
    for requirement_record in select * from public.roster_period_role_requirements where period_id = p_period_id and is_required order by sort_order, role_name_snapshot loop
      select count(*) into assigned_count from public.roster_assignments where shift_slot_id = slot_record.id and role_requirement_id = requirement_record.id and status = 'assigned';
      required_count := greatest(requirement_record.min_staff_count, 0);
      while assigned_count < required_count loop
        select availability.staff_id into selected_staff_id
        from public.roster_availability as availability
        join public.staff_members as staff on staff.id = availability.staff_id and staff.is_visible
        where availability.period_id = p_period_id and availability.shift_slot_id = slot_record.id
          and availability.status in ('available', case when p_use_standby then 'standby' else 'available' end)
          and not exists (select 1 from public.roster_assignments as assigned where assigned.shift_slot_id = slot_record.id and assigned.staff_id = availability.staff_id and assigned.status = 'assigned')
        order by case availability.status when 'available' then 0 else 1 end,
          (select count(*) from public.roster_assignments as prior where prior.period_id = p_period_id and prior.staff_id = availability.staff_id and prior.status = 'assigned'),
          staff.sort_order, staff.name
        limit 1;
        if selected_staff_id is null then
          insert into public.roster_assignments(period_id, shift_slot_id, role_requirement_id, staff_id, assignment_order, is_manual, status, created_by, updated_by) values (p_period_id, slot_record.id, requirement_record.id, null, assigned_count, false, 'pending', auth.uid(), auth.uid());
        else
          insert into public.roster_assignments(period_id, shift_slot_id, role_requirement_id, staff_id, assignment_order, is_manual, status, created_by, updated_by) values (p_period_id, slot_record.id, requirement_record.id, selected_staff_id, assigned_count, false, 'assigned', auth.uid(), auth.uid());
        end if;
        assigned_count := assigned_count + 1; selected_staff_id := null;
      end loop;
    end loop;
  end loop;
  return public.roster_snapshot(p_period_id);
end;
$$;

alter table public.roster_periods enable row level security;
alter table public.roster_shift_slots enable row level security;
alter table public.roster_roles enable row level security;
alter table public.roster_period_role_requirements enable row level security;
alter table public.roster_availability enable row level security;
alter table public.roster_assignments enable row level security;

create policy "roster_periods_read" on public.roster_periods for select to authenticated using (public.has_admin_permission('roster.manage') or (public.has_admin_permission('roster.view') and status in ('published', 'locked')) or (public.has_admin_permission('roster.submit') and status = 'open'));
create policy "roster_slots_read" on public.roster_shift_slots for select to authenticated using (public.has_admin_permission('roster.manage') or exists (select 1 from public.roster_periods where id = roster_shift_slots.period_id and ((public.has_admin_permission('roster.view') and status in ('published', 'locked')) or (public.has_admin_permission('roster.submit') and status = 'open'))));
create policy "roster_availability_read" on public.roster_availability for select to authenticated using (public.has_admin_permission('roster.manage') or (staff_id = public.roster_current_staff_id() and public.has_admin_permission('roster.submit')));
create policy "roster_assignments_read" on public.roster_assignments for select to authenticated using (public.has_admin_permission('roster.manage') or (public.has_admin_permission('roster.view') and exists (select 1 from public.roster_periods where id = roster_assignments.period_id and status in ('published', 'locked'))));

revoke all on public.roster_periods, public.roster_shift_slots, public.roster_roles, public.roster_period_role_requirements, public.roster_availability, public.roster_assignments from anon, authenticated;
revoke all on function public.roster_current_staff_id(), public.roster_snapshot(uuid), public.save_roster_period(uuid, text, date, date, jsonb, jsonb), public.set_roster_period_status(uuid, text), public.save_roster_availability(uuid, jsonb), public.save_roster_role(uuid, text, text, text, integer, integer, integer, boolean), public.save_roster_assignment(uuid, uuid, uuid, uuid, uuid, text, boolean, text), public.delete_roster_assignment(uuid), public.generate_roster_assignments(uuid, boolean, boolean) from public;
grant execute on function public.roster_snapshot(uuid), public.save_roster_period(uuid, text, date, date, jsonb, jsonb), public.set_roster_period_status(uuid, text), public.save_roster_availability(uuid, jsonb), public.save_roster_role(uuid, text, text, text, integer, integer, integer, boolean), public.save_roster_assignment(uuid, uuid, uuid, uuid, uuid, text, boolean, text), public.delete_roster_assignment(uuid), public.generate_roster_assignments(uuid, boolean, boolean) to authenticated;
