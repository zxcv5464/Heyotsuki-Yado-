-- Payroll Hotfix 2.
-- Draft-only direct-staff overrides live outside the original order record.

create table if not exists public.payroll_source_assignments (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.payroll_batches(id) on delete cascade,
  source_type text not null check (source_type = 'direct_staff'),
  source_id uuid not null references public.order_items(id) on delete restrict,
  assigned_staff_id uuid not null references public.staff_members(id) on delete restrict,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (batch_id, source_type, source_id)
);

create index if not exists payroll_source_assignments_batch_source_idx
  on public.payroll_source_assignments (batch_id, source_type, source_id);

drop trigger if exists payroll_source_assignments_set_updated_at
  on public.payroll_source_assignments;
create trigger payroll_source_assignments_set_updated_at
before update on public.payroll_source_assignments
for each row execute function public.set_updated_at();

create or replace function public.prevent_locked_payroll_entry_changes()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_status text;
begin
  select payroll_batches.status into target_status
  from public.payroll_batches
  where payroll_batches.id = coalesce(new.batch_id, old.batch_id);

  if target_status = 'locked' then
    raise exception 'Locked payroll entries cannot be changed.';
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists payroll_entries_prevent_locked_changes
  on public.payroll_entries;
create trigger payroll_entries_prevent_locked_changes
before insert or update or delete on public.payroll_entries
for each row execute function public.prevent_locked_payroll_entry_changes();

create or replace function public.prevent_locked_payroll_source_assignment_changes()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_status text;
begin
  select payroll_batches.status into target_status
  from public.payroll_batches
  where payroll_batches.id = coalesce(new.batch_id, old.batch_id);

  if target_status = 'locked' then
    raise exception 'Locked payroll source assignments cannot be changed.';
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists payroll_source_assignments_prevent_locked_changes
  on public.payroll_source_assignments;
create trigger payroll_source_assignments_prevent_locked_changes
before insert or update or delete on public.payroll_source_assignments
for each row execute function public.prevent_locked_payroll_source_assignment_changes();

create or replace function public.set_payroll_source_assignment(
  p_batch_id uuid,
  p_source_type text,
  p_source_id uuid,
  p_assigned_staff_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  batch_record public.payroll_batches%rowtype;
begin
  perform public.ensure_payroll_admin();
  perform public.assert_payroll_batch_draft(p_batch_id);

  if p_source_type <> 'direct_staff' then
    raise exception 'Only direct_staff payroll sources can be assigned.';
  end if;
  if not exists (select 1 from public.staff_members where id = p_assigned_staff_id) then
    raise exception 'Assigned staff member not found.';
  end if;

  select * into batch_record
  from public.payroll_batches
  where id = p_batch_id;
  if batch_record.id is null then
    raise exception 'Payroll batch not found.';
  end if;

  if not exists (
    select 1
    from public.order_items
    join public.orders on orders.id = order_items.order_id
    join public.menu_item_payroll_rules
      on menu_item_payroll_rules.menu_item_id = order_items.menu_item_id
    where order_items.id = p_source_id
      and orders.shop_key = batch_record.shop_key
      and coalesce(orders.business_date, (orders.created_at at time zone 'Asia/Taipei')::date) = batch_record.business_date
      and orders.deleted_at is null
      and orders.status in ('pending', 'accepted', 'preparing', 'served')
      and menu_item_payroll_rules.payroll_rule = 'direct_staff'
  ) then
    raise exception 'Payroll source does not belong to this draft batch.';
  end if;

  insert into public.payroll_source_assignments (
    batch_id, source_type, source_id, assigned_staff_id, created_by, updated_by
  ) values (
    p_batch_id, p_source_type, p_source_id, p_assigned_staff_id, auth.uid(), auth.uid()
  )
  on conflict (batch_id, source_type, source_id) do update
    set assigned_staff_id = excluded.assigned_staff_id,
        updated_by = auth.uid();

  return public.get_payroll_batch_snapshot(p_batch_id);
end;
$$;

do $patch_payroll_direct_assignment$
declare
  function_sql text;
  updated_sql text;
begin
  select pg_get_functiondef('public.regenerate_payroll_entries(uuid)'::regprocedure)
  into function_sql;

  if function_sql is null then
    raise exception 'regenerate_payroll_entries(uuid) does not exist.';
  end if;

  updated_sql := replace(
    function_sql,
    $$    p_batch_id,
    order_items.selected_staff_id,
    case when order_items.selected_staff_id is null then 'unassigned_direct_staff' else 'direct_staff' end,
    order_items.id,
    order_items.item_name_snapshot,
    coalesce(order_items.line_total_amount_snapshot, (coalesce(order_items.price_amount_snapshot, 0) + coalesce(order_items.options_amount_snapshot, 0)) * order_items.quantity),
    case when order_items.selected_staff_id is null then 'Direct staff item needs assignment.' else 'Direct staff allocation' end,
    jsonb_build_object('orderId', orders.id, 'selectedStaffNameSnapshot', order_items.selected_staff_name_snapshot)
  from public.orders
  join public.order_items on order_items.order_id = orders.id
  join public.menu_item_payroll_rules on menu_item_payroll_rules.menu_item_id = order_items.menu_item_id
  where orders.shop_key = batch_record.shop_key$$,
    $$    p_batch_id,
    coalesce(assignments.assigned_staff_id, order_items.selected_staff_id),
    case when coalesce(assignments.assigned_staff_id, order_items.selected_staff_id) is null then 'unassigned_direct_staff' else 'direct_staff' end,
    order_items.id,
    order_items.item_name_snapshot,
    coalesce(order_items.line_total_amount_snapshot, (coalesce(order_items.price_amount_snapshot, 0) + coalesce(order_items.options_amount_snapshot, 0)) * order_items.quantity),
    case when coalesce(assignments.assigned_staff_id, order_items.selected_staff_id) is null then 'Direct staff item needs assignment.' else 'Direct staff allocation' end,
    jsonb_build_object(
      'orderId', orders.id,
      'selectedStaffNameSnapshot', order_items.selected_staff_name_snapshot,
      'payrollAssignmentStaffId', assignments.assigned_staff_id
    )
  from public.orders
  join public.order_items on order_items.order_id = orders.id
  join public.menu_item_payroll_rules on menu_item_payroll_rules.menu_item_id = order_items.menu_item_id
  left join public.payroll_source_assignments as assignments
    on assignments.batch_id = p_batch_id
    and assignments.source_type = 'direct_staff'
    and assignments.source_id = order_items.id
  where orders.shop_key = batch_record.shop_key$$
  );

  if updated_sql = function_sql then
    raise exception 'regenerate_payroll_entries direct-staff assignment patch did not match expected function body.';
  end if;

  execute updated_sql;
end
$patch_payroll_direct_assignment$;

alter table public.payroll_source_assignments enable row level security;
revoke all on public.payroll_source_assignments from anon, authenticated;
revoke all on function public.set_payroll_source_assignment(uuid, text, uuid, uuid) from public;
grant execute on function public.set_payroll_source_assignment(uuid, text, uuid, uuid) to authenticated;
