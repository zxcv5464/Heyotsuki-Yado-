-- Payroll admin usability hotfix.
-- - Expose same-day direct-staff ids for default pool exclusion.
-- - Allow manual adjustments after a payroll batch is locked, while keeping
--   every other locked-batch mutation blocked.

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

create or replace function public.prevent_payroll_entry_changes_when_locked()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_status text;
begin
  select payroll_batches.status
    into target_status
  from public.payroll_batches
  where payroll_batches.id = coalesce(new.batch_id, old.batch_id);

  if target_status = 'locked' then
    if tg_op = 'INSERT' and new.source_type = 'manual_adjustment' then
      return new;
    end if;

    raise exception 'Locked payroll entries cannot be changed.';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;
