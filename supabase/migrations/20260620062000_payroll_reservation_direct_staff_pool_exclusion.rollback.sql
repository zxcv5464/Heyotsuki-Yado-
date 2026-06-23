-- Rollback for 20260620062000_payroll_reservation_direct_staff_pool_exclusion.sql.
-- Restores the previous order-item selected-staff exclusion behavior.

create or replace function public.get_payroll_direct_staff_ids(
  p_batch_id uuid
)
returns uuid[]
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  batch_record public.payroll_batches%rowtype;
  staff_ids uuid[];
begin
  perform public.ensure_payroll_admin();

  select * into batch_record
  from public.payroll_batches
  where id = p_batch_id;

  if batch_record.id is null then
    raise exception 'Payroll batch not found.';
  end if;

  select coalesce(array_agg(distinct order_items.selected_staff_id), array[]::uuid[])
    into staff_ids
  from public.orders
  join public.order_items on order_items.order_id = orders.id
  join public.menu_item_payroll_rules
    on menu_item_payroll_rules.menu_item_id = order_items.menu_item_id
  where orders.shop_key = batch_record.shop_key
    and coalesce(orders.business_date, (orders.created_at at time zone 'Asia/Taipei')::date) = batch_record.business_date
    and orders.deleted_at is null
    and orders.status in ('pending', 'accepted', 'preparing', 'served')
    and menu_item_payroll_rules.payroll_rule = 'direct_staff'
    and order_items.selected_staff_id is not null;

  return staff_ids;
end;
$$;

revoke all on function public.get_payroll_direct_staff_ids(uuid) from public;
grant execute on function public.get_payroll_direct_staff_ids(uuid)
  to authenticated;
