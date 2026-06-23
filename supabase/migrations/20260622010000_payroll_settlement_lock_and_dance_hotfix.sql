-- Payroll settlement hotfix.
-- Keeps the existing schema and makes draft calculation the single source of truth
-- before a batch may be locked.

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

  select coalesce(array_agg(distinct designated.staff_id), array[]::uuid[])
  into staff_ids
  from public.reservations
  cross join lateral (
    values
      (reservations.preferred_staff_id),
      (reservations.preferred_staff_2_id)
  ) as designated(staff_id)
  where reservations.reservation_date = batch_record.business_date
    and reservations.deleted_at is null
    and reservations.status not in ('cancelled', 'no_show')
    and designated.staff_id is not null;

  return staff_ids;
end;
$$;

create or replace function public.upsert_dance_session(
  p_batch_id uuid,
  p_order_item_id uuid,
  p_session_no integer,
  p_amount integer,
  p_status text default 'active'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  batch_record public.payroll_batches%rowtype;
  order_record record;
  session_amount integer;
begin
  perform public.ensure_payroll_admin();
  perform public.assert_payroll_batch_draft(p_batch_id);

  select * into batch_record
  from public.payroll_batches
  where id = p_batch_id;

  select
    orders.shop_key,
    order_items.quantity,
    coalesce(
      order_items.line_total_amount_snapshot,
      (coalesce(order_items.price_amount_snapshot, 0) + coalesce(order_items.options_amount_snapshot, 0)) * order_items.quantity
    )::integer as line_total
  into order_record
  from public.order_items
  join public.orders on orders.id = order_items.order_id
  join public.menu_item_payroll_rules
    on menu_item_payroll_rules.menu_item_id = order_items.menu_item_id
  where order_items.id = p_order_item_id
    and orders.shop_key = batch_record.shop_key
    and coalesce(orders.business_date, (orders.created_at at time zone 'Asia/Taipei')::date) = batch_record.business_date
    and orders.deleted_at is null
    and orders.status in ('pending', 'accepted', 'preparing', 'served')
    and menu_item_payroll_rules.payroll_rule = 'dance_split';

  if order_record.shop_key is null then
    raise exception 'Dance order item does not belong to this payroll batch.';
  end if;
  if p_session_no is null or p_session_no < 1 then
    raise exception 'Session number must be positive.';
  end if;
  if p_status not in ('active', 'void') then
    raise exception 'Invalid dance session status.';
  end if;
  if p_status = 'active' and p_session_no > order_record.quantity then
    raise exception 'Dance session number exceeds the order quantity.';
  end if;

  -- The stored amount is derived from the order-line snapshot. p_amount is
  -- retained only for backwards-compatible browser RPC calls.
  session_amount := floor(order_record.line_total::numeric / order_record.quantity)::integer
    + case when p_session_no <= (order_record.line_total % order_record.quantity) then 1 else 0 end;

  insert into public.dance_sessions (
    batch_id, order_item_id, session_no, amount, status
  ) values (
    p_batch_id, p_order_item_id, p_session_no, session_amount, p_status
  )
  on conflict (batch_id, order_item_id, session_no) do update
    set amount = excluded.amount,
        status = excluded.status;

  return public.get_payroll_batch_snapshot(p_batch_id);
end;
$$;

create or replace function public.regenerate_payroll_entries(
  p_batch_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  batch_record public.payroll_batches%rowtype;
  pool_total bigint;
  pool_count integer;
  pool_base integer;
  pool_remainder integer;
  dance_item record;
  dance_session record;
  participant_count integer;
  participant_base integer;
  participant_remainder integer;
  session_amount integer;
  missing_amount integer;
  active_session_count integer;
begin
  perform public.ensure_payroll_admin();
  perform public.assert_payroll_batch_draft(p_batch_id);

  select * into batch_record
  from public.payroll_batches
  where id = p_batch_id
  for update;

  if batch_record.id is null then
    raise exception 'Payroll batch not found.';
  end if;

  delete from public.payroll_entries
  where batch_id = p_batch_id
    and source_type <> 'manual_adjustment';

  select coalesce(sum(
    coalesce(
      order_items.line_total_amount_snapshot,
      (coalesce(order_items.price_amount_snapshot, 0) + coalesce(order_items.options_amount_snapshot, 0)) * order_items.quantity
    )
  ), 0)
  into pool_total
  from public.orders
  join public.order_items on order_items.order_id = orders.id
  join public.menu_item_payroll_rules
    on menu_item_payroll_rules.menu_item_id = order_items.menu_item_id
  where orders.shop_key = batch_record.shop_key
    and coalesce(orders.business_date, (orders.created_at at time zone 'Asia/Taipei')::date) = batch_record.business_date
    and orders.deleted_at is null
    and orders.status in ('pending', 'accepted', 'preparing', 'served')
    and menu_item_payroll_rules.payroll_rule = 'food_pool';

  select count(*) into pool_count
  from public.payroll_pool_members
  where batch_id = p_batch_id;

  if pool_total > 0 and pool_count > 0 then
    pool_base := floor(pool_total::numeric / pool_count)::integer;
    pool_remainder := (pool_total % pool_count)::integer;
    insert into public.payroll_entries (batch_id, staff_id, source_type, amount, description, metadata)
    select
      p_batch_id,
      staff_id,
      'food_pool',
      pool_base + case when row_number() over (order by allocation_order, created_at, staff_id) <= pool_remainder then 1 else 0 end,
      'Food pool allocation',
      jsonb_build_object('poolTotal', pool_total, 'poolMembers', pool_count)
    from public.payroll_pool_members
    where batch_id = p_batch_id
    order by allocation_order, created_at, staff_id;
  elsif pool_total > 0 then
    insert into public.payroll_entries (batch_id, source_type, amount, description, metadata)
    values (p_batch_id, 'unassigned_direct_staff', pool_total::integer, 'Food pool has no members.', jsonb_build_object('reason', 'missing_pool_members'));
  end if;

  insert into public.payroll_entries (
    batch_id, staff_id, source_type, source_id, source_item_name, amount, description, metadata
  )
  select
    p_batch_id,
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
  where orders.shop_key = batch_record.shop_key
    and coalesce(orders.business_date, (orders.created_at at time zone 'Asia/Taipei')::date) = batch_record.business_date
    and orders.deleted_at is null
    and orders.status in ('pending', 'accepted', 'preparing', 'served')
    and menu_item_payroll_rules.payroll_rule = 'direct_staff';

  for dance_item in
    select
      order_items.id as order_item_id,
      orders.id as order_id,
      order_items.item_name_snapshot,
      order_items.quantity::integer as quantity,
      coalesce(order_items.line_total_amount_snapshot, (coalesce(order_items.price_amount_snapshot, 0) + coalesce(order_items.options_amount_snapshot, 0)) * order_items.quantity)::integer as line_total
    from public.orders
    join public.order_items on order_items.order_id = orders.id
    join public.menu_item_payroll_rules on menu_item_payroll_rules.menu_item_id = order_items.menu_item_id
    where orders.shop_key = batch_record.shop_key
      and coalesce(orders.business_date, (orders.created_at at time zone 'Asia/Taipei')::date) = batch_record.business_date
      and orders.deleted_at is null
      and orders.status in ('pending', 'accepted', 'preparing', 'served')
      and menu_item_payroll_rules.payroll_rule = 'dance_split'
  loop
    select count(*) into active_session_count
    from public.dance_sessions
    where batch_id = p_batch_id
      and order_item_id = dance_item.order_item_id
      and status = 'active'
      and session_no between 1 and dance_item.quantity;

    if active_session_count < dance_item.quantity then
      select coalesce(sum(
        floor(dance_item.line_total::numeric / dance_item.quantity)::integer
        + case when slot_no <= (dance_item.line_total % dance_item.quantity) then 1 else 0 end
      ), 0)
      into missing_amount
      from generate_series(1, dance_item.quantity) as slots(slot_no)
      where not exists (
        select 1
        from public.dance_sessions
        where batch_id = p_batch_id
          and order_item_id = dance_item.order_item_id
          and session_no = slots.slot_no
          and status = 'active'
      );

      insert into public.payroll_entries (
        batch_id, source_type, source_id, source_item_name, amount, description, metadata
      ) values (
        p_batch_id,
        'unassigned_dance_split',
        dance_item.order_item_id,
        dance_item.item_name_snapshot,
        missing_amount,
        'Dance order item is missing required sessions.',
        jsonb_build_object(
          'orderId', dance_item.order_id,
          'requiredSessions', dance_item.quantity,
          'activeSessions', active_session_count,
          'reason', 'missing_dance_sessions'
        )
      );
    end if;

    if exists (
      select 1 from public.dance_sessions
      where batch_id = p_batch_id
        and order_item_id = dance_item.order_item_id
        and status = 'active'
        and session_no > dance_item.quantity
    ) then
      insert into public.payroll_entries (
        batch_id, source_type, source_id, source_item_name, amount, description, metadata
      ) values (
        p_batch_id,
        'unassigned_dance_split',
        dance_item.order_item_id,
        dance_item.item_name_snapshot,
        0,
        'Dance order item has extra active sessions.',
        jsonb_build_object('reason', 'extra_dance_sessions')
      );
    end if;

    for dance_session in
      select *
      from public.dance_sessions
      where batch_id = p_batch_id
        and order_item_id = dance_item.order_item_id
        and status = 'active'
        and session_no between 1 and dance_item.quantity
      order by session_no, id
    loop
      session_amount := floor(dance_item.line_total::numeric / dance_item.quantity)::integer
        + case when dance_session.session_no <= (dance_item.line_total % dance_item.quantity) then 1 else 0 end;

      update public.dance_sessions
      set amount = session_amount
      where id = dance_session.id
        and amount is distinct from session_amount;

      select count(*) into participant_count
      from public.dance_session_participants
      where session_id = dance_session.id;

      if participant_count = 0 then
        insert into public.payroll_entries (batch_id, source_type, source_id, amount, description, metadata)
        values (
          p_batch_id,
          'unassigned_dance_split',
          dance_session.id,
          session_amount,
          'Dance session needs participants.',
          jsonb_build_object('orderItemId', dance_item.order_item_id, 'sessionNo', dance_session.session_no)
        );
      else
        participant_base := floor(session_amount::numeric / participant_count)::integer;
        participant_remainder := (session_amount % participant_count)::integer;
        insert into public.payroll_entries (batch_id, staff_id, source_type, source_id, amount, description, metadata)
        select
          p_batch_id,
          staff_id,
          'dance_split',
          dance_session.id,
          participant_base + case when row_number() over (order by allocation_order, created_at, staff_id) <= participant_remainder then 1 else 0 end,
          'Dance split allocation',
          jsonb_build_object('orderItemId', dance_item.order_item_id, 'sessionNo', dance_session.session_no)
        from public.dance_session_participants
        where session_id = dance_session.id
        order by allocation_order, created_at, staff_id;
      end if;
    end loop;
  end loop;

  return public.get_payroll_batch_snapshot(p_batch_id);
end;
$$;

create or replace function public.lock_payroll_batch(
  p_batch_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  batch_record public.payroll_batches%rowtype;
  unassigned_count integer;
  generated_entry_count integer;
  source_total bigint;
  generated_total bigint;
begin
  perform public.ensure_payroll_admin();

  select * into batch_record
  from public.payroll_batches
  where id = p_batch_id
  for update;

  if batch_record.id is null then
    raise exception 'Payroll batch not found.';
  end if;
  if batch_record.status <> 'draft' then
    raise exception 'Payroll batch is already locked.';
  end if;

  perform public.regenerate_payroll_entries(p_batch_id);

  select count(*) into unassigned_count
  from public.payroll_entries
  where batch_id = p_batch_id
    and source_type in ('unassigned_direct_staff', 'unassigned_dance_split');
  if unassigned_count > 0 then
    raise exception 'Payroll batch has unassigned entries.';
  end if;

  select count(*), coalesce(sum(amount), 0)
  into generated_entry_count, generated_total
  from public.payroll_entries
  where batch_id = p_batch_id
    and source_type in ('food_pool', 'direct_staff', 'dance_split');
  if generated_entry_count = 0 then
    raise exception 'Payroll batch has no generated entries.';
  end if;

  select coalesce(sum(coalesce(order_items.line_total_amount_snapshot, (coalesce(order_items.price_amount_snapshot, 0) + coalesce(order_items.options_amount_snapshot, 0)) * order_items.quantity)), 0)
  into source_total
  from public.orders
  join public.order_items on order_items.order_id = orders.id
  join public.menu_item_payroll_rules on menu_item_payroll_rules.menu_item_id = order_items.menu_item_id
  where orders.shop_key = batch_record.shop_key
    and coalesce(orders.business_date, (orders.created_at at time zone 'Asia/Taipei')::date) = batch_record.business_date
    and orders.deleted_at is null
    and orders.status in ('pending', 'accepted', 'preparing', 'served')
    and menu_item_payroll_rules.payroll_rule in ('food_pool', 'direct_staff', 'dance_split');

  if generated_total <> source_total then
    raise exception 'Payroll allocation total does not match source total.';
  end if;

  update public.payroll_batches
  set status = 'locked', locked_at = now(), locked_by = auth.uid()
  where id = p_batch_id;

  return public.get_payroll_batch_snapshot(p_batch_id);
end;
$$;

create or replace function public.create_payroll_adjustment(
  p_batch_id uuid,
  p_staff_id uuid,
  p_amount integer,
  p_description text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  perform public.ensure_payroll_admin();
  perform public.assert_payroll_batch_draft(p_batch_id);
  if p_amount is null or p_amount = 0 then
    raise exception 'Adjustment amount cannot be zero.';
  end if;
  if nullif(trim(coalesce(p_description, '')), '') is null then
    raise exception 'Adjustment description is required.';
  end if;
  if not exists (select 1 from public.staff_members where id = p_staff_id) then
    raise exception 'Staff member not found.';
  end if;

  insert into public.payroll_entries (batch_id, staff_id, source_type, amount, description, metadata)
  values (
    p_batch_id,
    p_staff_id,
    'manual_adjustment',
    p_amount,
    trim(p_description),
    jsonb_build_object('createdBy', auth.uid(), 'exception', true)
  );

  return public.get_payroll_batch_snapshot(p_batch_id);
end;
$$;

create or replace function public.prevent_payroll_entry_changes_when_locked()
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

revoke all on function public.get_payroll_direct_staff_ids(uuid) from public;
grant execute on function public.get_payroll_direct_staff_ids(uuid) to authenticated;
revoke all on function public.upsert_dance_session(uuid, uuid, integer, integer, text) from public;
grant execute on function public.upsert_dance_session(uuid, uuid, integer, integer, text) to authenticated;
revoke all on function public.regenerate_payroll_entries(uuid) from public;
grant execute on function public.regenerate_payroll_entries(uuid) to authenticated;
revoke all on function public.lock_payroll_batch(uuid) from public;
grant execute on function public.lock_payroll_batch(uuid) to authenticated;
revoke all on function public.create_payroll_adjustment(uuid, uuid, integer, text) from public;
grant execute on function public.create_payroll_adjustment(uuid, uuid, integer, text) to authenticated;
