-- Rollback for 20260622020000_payroll_direct_assignment_and_locked_entries.sql.
-- Run only after exporting payroll_source_assignments if draft overrides must be retained.

do $rollback_payroll_direct_assignment$
declare
  function_sql text;
  updated_sql text;
begin
  select pg_get_functiondef('public.regenerate_payroll_entries(uuid)'::regprocedure)
  into function_sql;

  updated_sql := replace(
    function_sql,
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
  where orders.shop_key = batch_record.shop_key$$,
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
  where orders.shop_key = batch_record.shop_key$$
  );

  if updated_sql = function_sql then
    raise exception 'regenerate_payroll_entries assignment rollback did not match expected function body.';
  end if;
  execute updated_sql;
end
$rollback_payroll_direct_assignment$;

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
    if tg_op = 'INSERT' and new.source_type = 'manual_adjustment' then
      return new;
    end if;
    raise exception 'Locked payroll entries cannot be changed; create a manual adjustment instead.';
  end if;
  return coalesce(new, old);
end;
$$;

drop trigger if exists payroll_source_assignments_prevent_locked_changes
  on public.payroll_source_assignments;
drop function if exists public.prevent_locked_payroll_source_assignment_changes();
drop function if exists public.set_payroll_source_assignment(uuid, text, uuid, uuid);
drop table if exists public.payroll_source_assignments;
