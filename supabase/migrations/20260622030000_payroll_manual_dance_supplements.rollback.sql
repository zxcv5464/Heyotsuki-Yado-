-- Rollback for 20260622030000_payroll_manual_dance_supplements.sql.
-- Export payroll_manual_dance_sessions and payroll_manual_dance_allocations first.
-- This rollback removes payroll-only supplement history; it never changes orders.

drop trigger if exists payroll_manual_dance_allocations_prevent_changes
  on public.payroll_manual_dance_allocations;
drop trigger if exists payroll_manual_dance_participants_prevent_changes
  on public.payroll_manual_dance_participants;
drop trigger if exists payroll_manual_dance_sessions_prevent_changes
  on public.payroll_manual_dance_sessions;

revoke all on function public.create_payroll_manual_dance_supplement(uuid, integer, text, uuid[]) from authenticated;
drop function if exists public.create_payroll_manual_dance_supplement(uuid, integer, text, uuid[]);
drop function if exists public.prevent_payroll_manual_dance_changes();

drop table if exists public.payroll_manual_dance_allocations;
drop table if exists public.payroll_manual_dance_participants;
drop table if exists public.payroll_manual_dance_sessions;

-- Restore the pre-supplement snapshot shape.
create or replace function public.get_payroll_batch_snapshot(
  p_batch_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  batch_record public.payroll_batches%rowtype;
  result jsonb;
begin
  perform public.ensure_payroll_admin();

  select * into batch_record
  from public.payroll_batches
  where id = p_batch_id;
  if batch_record.id is null then
    raise exception 'Payroll batch not found.';
  end if;

  select jsonb_build_object(
    'batch', jsonb_build_object(
      'id', batch_record.id,
      'shopKey', batch_record.shop_key,
      'businessDate', batch_record.business_date,
      'status', batch_record.status,
      'lockedAt', batch_record.locked_at,
      'lockedBy', batch_record.locked_by,
      'createdAt', batch_record.created_at,
      'updatedAt', batch_record.updated_at
    ),
    'poolMembers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', payroll_pool_members.id,
        'staffId', staff_members.id,
        'name', staff_members.name,
        'allocationOrder', payroll_pool_members.allocation_order
      ) order by payroll_pool_members.allocation_order, payroll_pool_members.created_at, staff_members.name)
      from public.payroll_pool_members
      join public.staff_members on staff_members.id = payroll_pool_members.staff_id
      where payroll_pool_members.batch_id = p_batch_id
    ), '[]'::jsonb),
    'staffOptions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', staff_members.id,
        'name', staff_members.name,
        'isVisible', staff_members.is_visible
      ) order by staff_members.sort_order, staff_members.name)
      from public.staff_members
    ), '[]'::jsonb),
    'danceItems', coalesce((
      select jsonb_agg(jsonb_build_object(
        'orderItemId', order_items.id,
        'itemName', order_items.item_name_snapshot,
        'customerName', orders.customer_name,
        'amount', coalesce(
          order_items.line_total_amount_snapshot,
          (coalesce(order_items.price_amount_snapshot, 0) + coalesce(order_items.options_amount_snapshot, 0)) * order_items.quantity
        ),
        'quantity', order_items.quantity
      ) order by orders.created_at, order_items.sort_order)
      from public.orders
      join public.order_items on order_items.order_id = orders.id
      join public.menu_item_payroll_rules
        on menu_item_payroll_rules.menu_item_id = order_items.menu_item_id
      where orders.shop_key = batch_record.shop_key
        and coalesce(orders.business_date, (orders.created_at at time zone 'Asia/Taipei')::date) = batch_record.business_date
        and orders.deleted_at is null
        and orders.status in ('pending', 'accepted', 'preparing', 'served')
        and menu_item_payroll_rules.payroll_rule = 'dance_split'
    ), '[]'::jsonb),
    'danceSessions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', dance_sessions.id,
        'orderItemId', dance_sessions.order_item_id,
        'sessionNo', dance_sessions.session_no,
        'amount', dance_sessions.amount,
        'status', dance_sessions.status,
        'participants', coalesce((
          select jsonb_agg(jsonb_build_object(
            'staffId', staff_members.id,
            'name', staff_members.name,
            'allocationOrder', dance_session_participants.allocation_order
          ) order by dance_session_participants.allocation_order, staff_members.name)
          from public.dance_session_participants
          join public.staff_members
            on staff_members.id = dance_session_participants.staff_id
          where dance_session_participants.session_id = dance_sessions.id
        ), '[]'::jsonb)
      ) order by dance_sessions.created_at, dance_sessions.id)
      from public.dance_sessions
      where dance_sessions.batch_id = p_batch_id
    ), '[]'::jsonb),
    'entries', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', payroll_entries.id,
        'staffId', payroll_entries.staff_id,
        'staffName', staff_members.name,
        'sourceType', payroll_entries.source_type,
        'sourceId', payroll_entries.source_id,
        'sourceItemName', payroll_entries.source_item_name,
        'amount', payroll_entries.amount,
        'description', payroll_entries.description,
        'metadata', payroll_entries.metadata,
        'createdAt', payroll_entries.created_at
      ) order by payroll_entries.source_type, staff_members.name nulls last, payroll_entries.created_at)
      from public.payroll_entries
      left join public.staff_members on staff_members.id = payroll_entries.staff_id
      where payroll_entries.batch_id = p_batch_id
    ), '[]'::jsonb),
    'totalsByStaff', coalesce((
      select jsonb_agg(jsonb_build_object(
        'staffId', totals.staff_id,
        'staffName', totals.staff_name,
        'amount', totals.amount
      ) order by totals.staff_name nulls last)
      from (
        select
          payroll_entries.staff_id,
          staff_members.name as staff_name,
          sum(payroll_entries.amount)::integer as amount
        from public.payroll_entries
        left join public.staff_members on staff_members.id = payroll_entries.staff_id
        where payroll_entries.batch_id = p_batch_id
          and payroll_entries.staff_id is not null
        group by payroll_entries.staff_id, staff_members.name
      ) totals
    ), '[]'::jsonb),
    'unassigned', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', payroll_entries.id,
        'sourceType', payroll_entries.source_type,
        'sourceId', payroll_entries.source_id,
        'sourceItemName', payroll_entries.source_item_name,
        'amount', payroll_entries.amount,
        'description', payroll_entries.description,
        'metadata', payroll_entries.metadata
      ) order by payroll_entries.created_at)
      from public.payroll_entries
      where payroll_entries.batch_id = p_batch_id
        and payroll_entries.source_type in ('unassigned_direct_staff', 'unassigned_dance_split')
    ), '[]'::jsonb)
  ) into result;

  return result;
end;
$$;
