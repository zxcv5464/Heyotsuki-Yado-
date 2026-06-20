-- Staff payroll / revenue allocation settlement.
-- This migration is additive. It does not modify orders or order_items.

create table if not exists public.menu_item_payroll_rules (
  menu_item_id uuid primary key references public.menu_items(id) on delete cascade,
  payroll_rule text not null default 'excluded' check (
    payroll_rule in ('food_pool', 'direct_staff', 'dance_split', 'excluded')
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.payroll_batches (
  id uuid primary key default gen_random_uuid(),
  shop_key text not null check (shop_key in ('menu', 'menu2')),
  business_date date not null,
  status text not null default 'draft' check (status in ('draft', 'locked')),
  locked_at timestamptz,
  locked_by uuid references auth.users(id) on delete set null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (shop_key, business_date)
);

create table if not exists public.payroll_pool_members (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.payroll_batches(id) on delete cascade,
  staff_id uuid not null references public.staff_members(id) on delete restrict,
  allocation_order integer not null default 0,
  created_at timestamptz not null default now(),
  unique (batch_id, staff_id)
);

create table if not exists public.dance_sessions (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.payroll_batches(id) on delete cascade,
  order_item_id uuid not null references public.order_items(id) on delete restrict,
  session_no integer not null default 1 check (session_no >= 1),
  amount integer not null check (amount >= 0),
  status text not null default 'active' check (status in ('active', 'void')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (batch_id, order_item_id, session_no)
);

create table if not exists public.dance_session_participants (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.dance_sessions(id) on delete cascade,
  staff_id uuid not null references public.staff_members(id) on delete restrict,
  allocation_order integer not null default 0,
  created_at timestamptz not null default now(),
  unique (session_id, staff_id)
);

create table if not exists public.payroll_entries (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.payroll_batches(id) on delete cascade,
  staff_id uuid references public.staff_members(id) on delete restrict,
  source_type text not null check (
    source_type in (
      'food_pool',
      'direct_staff',
      'dance_split',
      'manual_adjustment',
      'unassigned_direct_staff',
      'unassigned_dance_split'
    )
  ),
  source_id uuid,
  source_item_name text,
  amount integer not null,
  description text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists payroll_batches_shop_date_idx
  on public.payroll_batches (shop_key, business_date desc);
create index if not exists payroll_pool_members_batch_order_idx
  on public.payroll_pool_members (batch_id, allocation_order, created_at);
create index if not exists dance_sessions_batch_item_idx
  on public.dance_sessions (batch_id, order_item_id);
create index if not exists dance_session_participants_session_order_idx
  on public.dance_session_participants (session_id, allocation_order, created_at);
create index if not exists payroll_entries_batch_staff_idx
  on public.payroll_entries (batch_id, staff_id);
create index if not exists payroll_entries_batch_source_idx
  on public.payroll_entries (batch_id, source_type, source_id);

drop trigger if exists menu_item_payroll_rules_set_updated_at
  on public.menu_item_payroll_rules;
create trigger menu_item_payroll_rules_set_updated_at
before update on public.menu_item_payroll_rules
for each row execute function public.set_updated_at();

drop trigger if exists payroll_batches_set_updated_at
  on public.payroll_batches;
create trigger payroll_batches_set_updated_at
before update on public.payroll_batches
for each row execute function public.set_updated_at();

drop trigger if exists dance_sessions_set_updated_at
  on public.dance_sessions;
create trigger dance_sessions_set_updated_at
before update on public.dance_sessions
for each row execute function public.set_updated_at();

create or replace function public.is_payroll_admin()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select public.is_owner() or public.is_admin();
$$;

create or replace function public.ensure_payroll_admin()
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if not public.is_payroll_admin() then
    raise exception 'Payroll administration permission denied.';
  end if;
end;
$$;

create or replace function public.prevent_locked_payroll_batch_changes()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_batch_id uuid;
  target_status text;
begin
  target_batch_id := coalesce(new.batch_id, old.batch_id);
  select payroll_batches.status
    into target_status
  from public.payroll_batches
  where payroll_batches.id = target_batch_id;

  if target_status = 'locked' then
    raise exception 'Locked payroll batch cannot be modified.';
  end if;

  return coalesce(new, old);
end;
$$;

create or replace function public.prevent_locked_payroll_batch_header_changes()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'DELETE' and old.status = 'locked' then
    raise exception 'Locked payroll batch cannot be deleted.';
  end if;

  if tg_op = 'UPDATE' and old.status = 'locked' then
    raise exception 'Locked payroll batch cannot be modified.';
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists payroll_batches_prevent_locked_changes
  on public.payroll_batches;
create trigger payroll_batches_prevent_locked_changes
before update or delete on public.payroll_batches
for each row execute function public.prevent_locked_payroll_batch_header_changes();

drop trigger if exists payroll_pool_members_prevent_locked_changes
  on public.payroll_pool_members;
create trigger payroll_pool_members_prevent_locked_changes
before insert or update or delete on public.payroll_pool_members
for each row execute function public.prevent_locked_payroll_batch_changes();

drop trigger if exists dance_sessions_prevent_locked_changes
  on public.dance_sessions;
create trigger dance_sessions_prevent_locked_changes
before insert or update or delete on public.dance_sessions
for each row execute function public.prevent_locked_payroll_batch_changes();

create or replace function public.prevent_locked_dance_participant_changes()
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
  from public.dance_sessions
  join public.payroll_batches
    on payroll_batches.id = dance_sessions.batch_id
  where dance_sessions.id = coalesce(new.session_id, old.session_id);

  if target_status = 'locked' then
    raise exception 'Locked payroll batch cannot be modified.';
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists dance_session_participants_prevent_locked_changes
  on public.dance_session_participants;
create trigger dance_session_participants_prevent_locked_changes
before insert or update or delete on public.dance_session_participants
for each row execute function public.prevent_locked_dance_participant_changes();

create or replace function public.prevent_locked_payroll_entry_changes()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_batch_id uuid;
  target_status text;
begin
  target_batch_id := coalesce(new.batch_id, old.batch_id);
  select payroll_batches.status
    into target_status
  from public.payroll_batches
  where payroll_batches.id = target_batch_id;

  if target_status = 'locked' then
    if tg_op = 'INSERT' and new.source_type = 'manual_adjustment' then
      return new;
    end if;
    raise exception 'Locked payroll entries cannot be changed; create a manual adjustment instead.';
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists payroll_entries_prevent_locked_changes
  on public.payroll_entries;
create trigger payroll_entries_prevent_locked_changes
before insert or update or delete on public.payroll_entries
for each row execute function public.prevent_locked_payroll_entry_changes();

create or replace function public.assert_payroll_batch_draft(p_batch_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  batch_status text;
begin
  select status into batch_status
  from public.payroll_batches
  where id = p_batch_id;

  if batch_status is null then
    raise exception 'Payroll batch not found.';
  end if;
  if batch_status <> 'draft' then
    raise exception 'Payroll batch is locked.';
  end if;
end;
$$;

create or replace function public.get_payroll_default_business_date(
  p_shop_key text
)
returns date
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  perform public.ensure_payroll_admin();
  return public.get_order_report_default_business_date(p_shop_key);
end;
$$;

create or replace function public.get_payroll_menu_rules(
  p_shop_key text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  result jsonb;
begin
  perform public.ensure_payroll_admin();
  if p_shop_key not in ('menu', 'menu2') then
    raise exception 'Invalid shop key.';
  end if;

  select jsonb_build_object(
    'shopKey', p_shop_key,
    'sections', coalesce(jsonb_agg(section_payload order by section_sort), '[]'::jsonb)
  )
  into result
  from (
    select
      menu_sections.sort_order as section_sort,
      jsonb_build_object(
        'id', menu_sections.id,
        'title', menu_sections.title,
        'sortOrder', menu_sections.sort_order,
        'items', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id', menu_items.id,
              'name', menu_items.name,
              'price', menu_items.price,
              'isVisible', menu_items.is_visible,
              'requiresStaffSelection', menu_items.requires_staff_selection,
              'payrollRule', coalesce(menu_item_payroll_rules.payroll_rule, 'excluded')
            )
            order by menu_items.sort_order, menu_items.created_at
          )
          from public.menu_items
          left join public.menu_item_payroll_rules
            on menu_item_payroll_rules.menu_item_id = menu_items.id
          where menu_items.section_id = menu_sections.id
        ), '[]'::jsonb)
      ) as section_payload
    from public.menu_sections
    where menu_sections.menu_key = p_shop_key
  ) sections;

  return coalesce(result, jsonb_build_object('shopKey', p_shop_key, 'sections', '[]'::jsonb));
end;
$$;

create or replace function public.upsert_menu_item_payroll_rule(
  p_menu_item_id uuid,
  p_payroll_rule text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  saved public.menu_item_payroll_rules%rowtype;
begin
  perform public.ensure_payroll_admin();
  if p_payroll_rule not in ('food_pool', 'direct_staff', 'dance_split', 'excluded') then
    raise exception 'Invalid payroll rule.';
  end if;

  insert into public.menu_item_payroll_rules (menu_item_id, payroll_rule)
  values (p_menu_item_id, p_payroll_rule)
  on conflict (menu_item_id) do update
    set payroll_rule = excluded.payroll_rule
  returning * into saved;

  return jsonb_build_object(
    'menuItemId', saved.menu_item_id,
    'payrollRule', saved.payroll_rule
  );
end;
$$;

create or replace function public.create_or_get_payroll_batch(
  p_shop_key text,
  p_business_date date
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  batch public.payroll_batches%rowtype;
begin
  perform public.ensure_payroll_admin();
  if p_shop_key not in ('menu', 'menu2') then
    raise exception 'Invalid shop key.';
  end if;
  if p_business_date is null then
    raise exception 'Business date is required.';
  end if;

  insert into public.payroll_batches (shop_key, business_date, created_by)
  values (p_shop_key, p_business_date, auth.uid())
  on conflict (shop_key, business_date) do nothing
  returning * into batch;

  if batch.id is null then
    select * into batch
    from public.payroll_batches
    where shop_key = p_shop_key
      and business_date = p_business_date;
  end if;

  return public.get_payroll_batch_snapshot(batch.id);
end;
$$;

create or replace function public.set_payroll_pool_members(
  p_batch_id uuid,
  p_staff_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  batch_shop_key text;
begin
  perform public.ensure_payroll_admin();
  perform public.assert_payroll_batch_draft(p_batch_id);

  select shop_key into batch_shop_key
  from public.payroll_batches
  where id = p_batch_id;

  delete from public.payroll_pool_members
  where batch_id = p_batch_id;

  insert into public.payroll_pool_members (batch_id, staff_id, allocation_order)
  select p_batch_id, staff_id, (ordinality::integer - 1) * 10
  from unnest(coalesce(p_staff_ids, array[]::uuid[])) with ordinality
    as selected(staff_id, ordinality)
  join public.staff_members
    on staff_members.id = selected.staff_id
  order by selected.ordinality;

  return public.get_payroll_batch_snapshot(p_batch_id);
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
  order_item_shop text;
begin
  perform public.ensure_payroll_admin();
  perform public.assert_payroll_batch_draft(p_batch_id);

  select * into batch_record
  from public.payroll_batches
  where id = p_batch_id;

  select orders.shop_key into order_item_shop
  from public.order_items
  join public.orders on orders.id = order_items.order_id
  where order_items.id = p_order_item_id
    and coalesce(orders.business_date, (orders.created_at at time zone 'Asia/Taipei')::date) = batch_record.business_date
    and orders.deleted_at is null
    and orders.status in ('pending', 'accepted', 'preparing', 'served');

  if order_item_shop is distinct from batch_record.shop_key then
    raise exception 'Order item does not belong to this payroll batch.';
  end if;

  if p_session_no is null or p_session_no < 1 then
    raise exception 'Session number must be positive.';
  end if;
  if p_amount is null or p_amount < 0 then
    raise exception 'Session amount must be zero or positive.';
  end if;
  if p_status not in ('active', 'void') then
    raise exception 'Invalid dance session status.';
  end if;

  insert into public.dance_sessions (
    batch_id, order_item_id, session_no, amount, status
  ) values (
    p_batch_id, p_order_item_id, p_session_no, p_amount, p_status
  )
  on conflict (batch_id, order_item_id, session_no) do update
    set amount = excluded.amount,
        status = excluded.status;

  return public.get_payroll_batch_snapshot(p_batch_id);
end;
$$;

create or replace function public.set_dance_session_participants(
  p_session_id uuid,
  p_staff_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_batch_id uuid;
begin
  perform public.ensure_payroll_admin();

  select batch_id into target_batch_id
  from public.dance_sessions
  where id = p_session_id;
  if target_batch_id is null then
    raise exception 'Dance session not found.';
  end if;
  perform public.assert_payroll_batch_draft(target_batch_id);

  delete from public.dance_session_participants
  where session_id = p_session_id;

  insert into public.dance_session_participants (
    session_id, staff_id, allocation_order
  )
  select p_session_id, staff_id, (ordinality::integer - 1) * 10
  from unnest(coalesce(p_staff_ids, array[]::uuid[])) with ordinality
    as selected(staff_id, ordinality)
  join public.staff_members
    on staff_members.id = selected.staff_id
  order by selected.ordinality;

  return public.get_payroll_batch_snapshot(target_batch_id);
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
  dance_record record;
  participant_count integer;
  participant_base integer;
  participant_remainder integer;
begin
  perform public.ensure_payroll_admin();
  perform public.assert_payroll_batch_draft(p_batch_id);

  select * into batch_record
  from public.payroll_batches
  where id = p_batch_id;

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

    insert into public.payroll_entries (
      batch_id, staff_id, source_type, amount, description, metadata
    )
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
    insert into public.payroll_entries (
      batch_id, source_type, amount, description, metadata
    ) values (
      p_batch_id,
      'unassigned_direct_staff',
      pool_total::integer,
      'Food pool has no members.',
      jsonb_build_object('reason', 'missing_pool_members')
    );
  end if;

  insert into public.payroll_entries (
    batch_id, staff_id, source_type, source_id, source_item_name,
    amount, description, metadata
  )
  select
    p_batch_id,
    order_items.selected_staff_id,
    case
      when order_items.selected_staff_id is null then 'unassigned_direct_staff'
      else 'direct_staff'
    end,
    order_items.id,
    order_items.item_name_snapshot,
    coalesce(
      order_items.line_total_amount_snapshot,
      (coalesce(order_items.price_amount_snapshot, 0) + coalesce(order_items.options_amount_snapshot, 0)) * order_items.quantity
    ),
    case
      when order_items.selected_staff_id is null then 'Direct staff item needs assignment.'
      else 'Direct staff allocation'
    end,
    jsonb_build_object(
      'orderId', orders.id,
      'selectedStaffNameSnapshot', order_items.selected_staff_name_snapshot
    )
  from public.orders
  join public.order_items on order_items.order_id = orders.id
  join public.menu_item_payroll_rules
    on menu_item_payroll_rules.menu_item_id = order_items.menu_item_id
  where orders.shop_key = batch_record.shop_key
    and coalesce(orders.business_date, (orders.created_at at time zone 'Asia/Taipei')::date) = batch_record.business_date
    and orders.deleted_at is null
    and orders.status in ('pending', 'accepted', 'preparing', 'served')
    and menu_item_payroll_rules.payroll_rule = 'direct_staff';

  for dance_record in
    select dance_sessions.*
    from public.dance_sessions
    where dance_sessions.batch_id = p_batch_id
      and dance_sessions.status = 'active'
    order by dance_sessions.created_at, dance_sessions.id
  loop
    select count(*) into participant_count
    from public.dance_session_participants
    where session_id = dance_record.id;

    if participant_count = 0 then
      insert into public.payroll_entries (
        batch_id, source_type, source_id, amount, description, metadata
      ) values (
        p_batch_id,
        'unassigned_dance_split',
        dance_record.id,
        dance_record.amount,
        'Dance session needs participants.',
        jsonb_build_object('orderItemId', dance_record.order_item_id)
      );
    else
      participant_base := floor(dance_record.amount::numeric / participant_count)::integer;
      participant_remainder := (dance_record.amount % participant_count)::integer;

      insert into public.payroll_entries (
        batch_id, staff_id, source_type, source_id, amount, description, metadata
      )
      select
        p_batch_id,
        staff_id,
        'dance_split',
        dance_record.id,
        participant_base + case when row_number() over (order by allocation_order, created_at, staff_id) <= participant_remainder then 1 else 0 end,
        'Dance split allocation',
        jsonb_build_object('orderItemId', dance_record.order_item_id, 'sessionNo', dance_record.session_no)
      from public.dance_session_participants
      where session_id = dance_record.id
      order by allocation_order, created_at, staff_id;
    end if;
  end loop;

  insert into public.payroll_entries (
    batch_id, source_type, source_id, source_item_name, amount, description, metadata
  )
  select
    p_batch_id,
    'unassigned_dance_split',
    order_items.id,
    order_items.item_name_snapshot,
    coalesce(
      order_items.line_total_amount_snapshot,
      (coalesce(order_items.price_amount_snapshot, 0) + coalesce(order_items.options_amount_snapshot, 0)) * order_items.quantity
    ),
    'Dance split item needs manual sessions.',
    jsonb_build_object('orderId', orders.id, 'reason', 'missing_dance_session')
  from public.orders
  join public.order_items on order_items.order_id = orders.id
  join public.menu_item_payroll_rules
    on menu_item_payroll_rules.menu_item_id = order_items.menu_item_id
  where orders.shop_key = batch_record.shop_key
    and coalesce(orders.business_date, (orders.created_at at time zone 'Asia/Taipei')::date) = batch_record.business_date
    and orders.deleted_at is null
    and orders.status in ('pending', 'accepted', 'preparing', 'served')
    and menu_item_payroll_rules.payroll_rule = 'dance_split'
    and not exists (
      select 1
      from public.dance_sessions
      where dance_sessions.batch_id = p_batch_id
        and dance_sessions.order_item_id = order_items.id
    );

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
  unassigned_count integer;
begin
  perform public.ensure_payroll_admin();
  perform public.assert_payroll_batch_draft(p_batch_id);

  select count(*) into unassigned_count
  from public.payroll_entries
  where batch_id = p_batch_id
    and source_type in ('unassigned_direct_staff', 'unassigned_dance_split');

  if unassigned_count > 0 then
    raise exception 'Payroll batch has unassigned entries.';
  end if;

  update public.payroll_batches
  set status = 'locked',
      locked_at = now(),
      locked_by = auth.uid()
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
declare
  batch_exists boolean;
begin
  perform public.ensure_payroll_admin();
  if p_amount is null or p_amount = 0 then
    raise exception 'Adjustment amount cannot be zero.';
  end if;
  if nullif(trim(coalesce(p_description, '')), '') is null then
    raise exception 'Adjustment description is required.';
  end if;

  select exists (
    select 1 from public.payroll_batches where id = p_batch_id
  ) into batch_exists;
  if not batch_exists then
    raise exception 'Payroll batch not found.';
  end if;

  insert into public.payroll_entries (
    batch_id, staff_id, source_type, amount, description, metadata
  ) values (
    p_batch_id,
    p_staff_id,
    'manual_adjustment',
    p_amount,
    trim(p_description),
    jsonb_build_object('createdBy', auth.uid())
  );

  return public.get_payroll_batch_snapshot(p_batch_id);
end;
$$;

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
  )
  into result;

  return result;
end;
$$;

alter table public.menu_item_payroll_rules enable row level security;
alter table public.payroll_batches enable row level security;
alter table public.payroll_pool_members enable row level security;
alter table public.dance_sessions enable row level security;
alter table public.dance_session_participants enable row level security;
alter table public.payroll_entries enable row level security;

drop policy if exists "menu_item_payroll_rules_admin_read"
  on public.menu_item_payroll_rules;
create policy "menu_item_payroll_rules_admin_read"
on public.menu_item_payroll_rules
for select
to authenticated
using (public.is_payroll_admin());

drop policy if exists "menu_item_payroll_rules_admin_write"
  on public.menu_item_payroll_rules;
create policy "menu_item_payroll_rules_admin_write"
on public.menu_item_payroll_rules
for all
to authenticated
using (public.is_payroll_admin())
with check (public.is_payroll_admin());

drop policy if exists "payroll_batches_admin_read"
  on public.payroll_batches;
create policy "payroll_batches_admin_read"
on public.payroll_batches
for select
to authenticated
using (public.is_payroll_admin());

drop policy if exists "payroll_batches_admin_write"
  on public.payroll_batches;
create policy "payroll_batches_admin_write"
on public.payroll_batches
for all
to authenticated
using (public.is_payroll_admin())
with check (public.is_payroll_admin());

drop policy if exists "payroll_pool_members_admin_read"
  on public.payroll_pool_members;
create policy "payroll_pool_members_admin_read"
on public.payroll_pool_members
for select
to authenticated
using (public.is_payroll_admin());

drop policy if exists "payroll_pool_members_admin_write"
  on public.payroll_pool_members;
create policy "payroll_pool_members_admin_write"
on public.payroll_pool_members
for all
to authenticated
using (public.is_payroll_admin())
with check (public.is_payroll_admin());

drop policy if exists "dance_sessions_admin_read"
  on public.dance_sessions;
create policy "dance_sessions_admin_read"
on public.dance_sessions
for select
to authenticated
using (public.is_payroll_admin());

drop policy if exists "dance_sessions_admin_write"
  on public.dance_sessions;
create policy "dance_sessions_admin_write"
on public.dance_sessions
for all
to authenticated
using (public.is_payroll_admin())
with check (public.is_payroll_admin());

drop policy if exists "dance_session_participants_admin_read"
  on public.dance_session_participants;
create policy "dance_session_participants_admin_read"
on public.dance_session_participants
for select
to authenticated
using (public.is_payroll_admin());

drop policy if exists "dance_session_participants_admin_write"
  on public.dance_session_participants;
create policy "dance_session_participants_admin_write"
on public.dance_session_participants
for all
to authenticated
using (public.is_payroll_admin())
with check (public.is_payroll_admin());

drop policy if exists "payroll_entries_admin_read"
  on public.payroll_entries;
create policy "payroll_entries_admin_read"
on public.payroll_entries
for select
to authenticated
using (public.is_payroll_admin());

drop policy if exists "payroll_entries_admin_write"
  on public.payroll_entries;
create policy "payroll_entries_admin_write"
on public.payroll_entries
for all
to authenticated
using (public.is_payroll_admin())
with check (public.is_payroll_admin());

revoke all on public.menu_item_payroll_rules from anon, authenticated;
revoke all on public.payroll_batches from anon, authenticated;
revoke all on public.payroll_pool_members from anon, authenticated;
revoke all on public.dance_sessions from anon, authenticated;
revoke all on public.dance_session_participants from anon, authenticated;
revoke all on public.payroll_entries from anon, authenticated;

grant select, insert, update, delete on public.menu_item_payroll_rules
  to authenticated;
grant select, insert, update, delete on public.payroll_batches
  to authenticated;
grant select, insert, update, delete on public.payroll_pool_members
  to authenticated;
grant select, insert, update, delete on public.dance_sessions
  to authenticated;
grant select, insert, update, delete on public.dance_session_participants
  to authenticated;
grant select, insert, update, delete on public.payroll_entries
  to authenticated;

revoke all on function public.is_payroll_admin() from public;
revoke all on function public.ensure_payroll_admin() from public;
revoke all on function public.prevent_locked_payroll_batch_changes() from public;
revoke all on function public.prevent_locked_payroll_batch_header_changes() from public;
revoke all on function public.prevent_locked_dance_participant_changes() from public;
revoke all on function public.prevent_locked_payroll_entry_changes() from public;
revoke all on function public.assert_payroll_batch_draft(uuid) from public;
revoke all on function public.get_payroll_default_business_date(text) from public;
revoke all on function public.get_payroll_menu_rules(text) from public;
revoke all on function public.upsert_menu_item_payroll_rule(uuid, text) from public;
revoke all on function public.create_or_get_payroll_batch(text, date) from public;
revoke all on function public.get_payroll_batch_snapshot(uuid) from public;
revoke all on function public.set_payroll_pool_members(uuid, uuid[]) from public;
revoke all on function public.upsert_dance_session(uuid, uuid, integer, integer, text) from public;
revoke all on function public.set_dance_session_participants(uuid, uuid[]) from public;
revoke all on function public.regenerate_payroll_entries(uuid) from public;
revoke all on function public.lock_payroll_batch(uuid) from public;
revoke all on function public.create_payroll_adjustment(uuid, uuid, integer, text) from public;

grant execute on function public.is_payroll_admin() to authenticated;
grant execute on function public.get_payroll_default_business_date(text)
  to authenticated;
grant execute on function public.get_payroll_menu_rules(text)
  to authenticated;
grant execute on function public.upsert_menu_item_payroll_rule(uuid, text)
  to authenticated;
grant execute on function public.create_or_get_payroll_batch(text, date)
  to authenticated;
grant execute on function public.get_payroll_batch_snapshot(uuid)
  to authenticated;
grant execute on function public.set_payroll_pool_members(uuid, uuid[])
  to authenticated;
grant execute on function public.upsert_dance_session(uuid, uuid, integer, integer, text)
  to authenticated;
grant execute on function public.set_dance_session_participants(uuid, uuid[])
  to authenticated;
grant execute on function public.regenerate_payroll_entries(uuid)
  to authenticated;
grant execute on function public.lock_payroll_batch(uuid)
  to authenticated;
grant execute on function public.create_payroll_adjustment(uuid, uuid, integer, text)
  to authenticated;
