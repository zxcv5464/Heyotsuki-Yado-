-- Payroll manual dance supplements.
-- These records are payroll-only and deliberately do not create or modify orders.

create table if not exists public.payroll_manual_dance_sessions (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.payroll_batches(id) on delete cascade,
  session_no integer not null check (session_no >= 1),
  amount integer not null check (amount <> 0),
  reason text not null check (nullif(trim(reason), '') is not null),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (batch_id, session_no)
);

create table if not exists public.payroll_manual_dance_participants (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.payroll_manual_dance_sessions(id) on delete cascade,
  staff_id uuid not null references public.staff_members(id) on delete restrict,
  allocation_order integer not null default 0,
  created_at timestamptz not null default now(),
  unique (session_id, staff_id)
);

create table if not exists public.payroll_manual_dance_allocations (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.payroll_batches(id) on delete cascade,
  session_id uuid not null references public.payroll_manual_dance_sessions(id) on delete restrict,
  staff_id uuid not null references public.staff_members(id) on delete restrict,
  amount integer not null check (amount <> 0),
  created_at timestamptz not null default now(),
  unique (session_id, staff_id)
);

create index if not exists payroll_manual_dance_sessions_batch_order_idx
  on public.payroll_manual_dance_sessions (batch_id, session_no, created_at);
create index if not exists payroll_manual_dance_participants_session_order_idx
  on public.payroll_manual_dance_participants (session_id, allocation_order, created_at);
create index if not exists payroll_manual_dance_allocations_batch_staff_idx
  on public.payroll_manual_dance_allocations (batch_id, staff_id, created_at);

create or replace function public.prevent_payroll_manual_dance_changes()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  raise exception 'Payroll manual dance supplements are append-only. Create an offsetting supplement instead.';
end;
$$;

drop trigger if exists payroll_manual_dance_sessions_prevent_changes
  on public.payroll_manual_dance_sessions;
create trigger payroll_manual_dance_sessions_prevent_changes
before update or delete on public.payroll_manual_dance_sessions
for each row execute function public.prevent_payroll_manual_dance_changes();

drop trigger if exists payroll_manual_dance_participants_prevent_changes
  on public.payroll_manual_dance_participants;
create trigger payroll_manual_dance_participants_prevent_changes
before update or delete on public.payroll_manual_dance_participants
for each row execute function public.prevent_payroll_manual_dance_changes();

drop trigger if exists payroll_manual_dance_allocations_prevent_changes
  on public.payroll_manual_dance_allocations;
create trigger payroll_manual_dance_allocations_prevent_changes
before update or delete on public.payroll_manual_dance_allocations
for each row execute function public.prevent_payroll_manual_dance_changes();

create or replace function public.create_payroll_manual_dance_supplement(
  p_batch_id uuid,
  p_amount integer,
  p_reason text,
  p_staff_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  batch_record public.payroll_batches%rowtype;
  session_record public.payroll_manual_dance_sessions%rowtype;
  participant_count integer;
  distinct_participant_count integer;
  known_participant_count integer;
  allocation_base integer;
  allocation_remainder integer;
  allocation_sign integer;
begin
  perform public.ensure_payroll_admin();

  if p_amount is null or p_amount = 0 then
    raise exception 'Manual dance supplement amount cannot be zero.';
  end if;
  if nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'Manual dance supplement reason is required.';
  end if;
  if cardinality(p_staff_ids) is null or cardinality(p_staff_ids) = 0 then
    raise exception 'Manual dance supplement needs at least one participant.';
  end if;

  select count(*), count(distinct staff_id)
  into participant_count, distinct_participant_count
  from unnest(p_staff_ids) as selected(staff_id);
  if participant_count <> distinct_participant_count then
    raise exception 'Manual dance supplement participants cannot repeat.';
  end if;

  select count(*) into known_participant_count
  from public.staff_members
  where id = any(p_staff_ids);
  if known_participant_count <> participant_count then
    raise exception 'Manual dance supplement participant was not found.';
  end if;

  select * into batch_record
  from public.payroll_batches
  where id = p_batch_id
  for update;
  if batch_record.id is null then
    raise exception 'Payroll batch not found.';
  end if;

  insert into public.payroll_manual_dance_sessions (
    batch_id, session_no, amount, reason, created_by
  ) values (
    p_batch_id,
    coalesce((
      select max(session_no) + 1
      from public.payroll_manual_dance_sessions
      where batch_id = p_batch_id
    ), 1),
    p_amount,
    trim(p_reason),
    auth.uid()
  ) returning * into session_record;

  insert into public.payroll_manual_dance_participants (
    session_id, staff_id, allocation_order
  )
  select session_record.id, selected.staff_id, selected.ordinality - 1
  from unnest(p_staff_ids) with ordinality as selected(staff_id, ordinality);

  allocation_sign := case when p_amount < 0 then -1 else 1 end;
  allocation_base := floor(abs(p_amount)::numeric / participant_count)::integer;
  allocation_remainder := abs(p_amount) % participant_count;

  insert into public.payroll_manual_dance_allocations (
    batch_id, session_id, staff_id, amount
  )
  select
    p_batch_id,
    session_record.id,
    selected.staff_id,
    allocation_sign * (
      allocation_base
      + case when selected.ordinality <= allocation_remainder then 1 else 0 end
    )
  from unnest(p_staff_ids) with ordinality as selected(staff_id, ordinality);

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
    'manualDanceSessions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', manual_sessions.id,
        'sessionNo', manual_sessions.session_no,
        'amount', manual_sessions.amount,
        'reason', manual_sessions.reason,
        'createdAt', manual_sessions.created_at,
        'participants', coalesce((
          select jsonb_agg(jsonb_build_object(
            'staffId', staff_members.id,
            'name', staff_members.name,
            'allocationOrder', manual_participants.allocation_order
          ) order by manual_participants.allocation_order, staff_members.name)
          from public.payroll_manual_dance_participants as manual_participants
          join public.staff_members on staff_members.id = manual_participants.staff_id
          where manual_participants.session_id = manual_sessions.id
        ), '[]'::jsonb)
      ) order by manual_sessions.session_no, manual_sessions.created_at)
      from public.payroll_manual_dance_sessions as manual_sessions
      where manual_sessions.batch_id = p_batch_id
    ), '[]'::jsonb),
    'entries', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', source_entries.id,
        'staffId', source_entries.staff_id,
        'staffName', staff_members.name,
        'sourceType', source_entries.source_type,
        'sourceId', source_entries.source_id,
        'sourceItemName', source_entries.source_item_name,
        'amount', source_entries.amount,
        'description', source_entries.description,
        'metadata', source_entries.metadata,
        'createdAt', source_entries.created_at
      ) order by source_entries.source_type, staff_members.name nulls last, source_entries.created_at)
      from (
        select
          payroll_entries.id,
          payroll_entries.staff_id,
          payroll_entries.source_type,
          payroll_entries.source_id,
          payroll_entries.source_item_name,
          payroll_entries.amount,
          payroll_entries.description,
          payroll_entries.metadata,
          payroll_entries.created_at
        from public.payroll_entries
        where payroll_entries.batch_id = p_batch_id

        union all

        select
          manual_allocations.id,
          manual_allocations.staff_id,
          'manual_dance_split'::text,
          manual_sessions.id,
          format('補登舞蹈 #%s', manual_sessions.session_no),
          manual_allocations.amount,
          manual_sessions.reason,
          jsonb_build_object(
            'manualDanceSessionNo', manual_sessions.session_no,
            'supplemental', true,
            'createdBy', manual_sessions.created_by
          ),
          manual_allocations.created_at
        from public.payroll_manual_dance_allocations as manual_allocations
        join public.payroll_manual_dance_sessions as manual_sessions
          on manual_sessions.id = manual_allocations.session_id
        where manual_allocations.batch_id = p_batch_id
      ) as source_entries
      left join public.staff_members on staff_members.id = source_entries.staff_id
    ), '[]'::jsonb),
    'totalsByStaff', coalesce((
      select jsonb_agg(jsonb_build_object(
        'staffId', totals.staff_id,
        'staffName', totals.staff_name,
        'amount', totals.amount
      ) order by totals.staff_name nulls last)
      from (
        select
          source_entries.staff_id,
          staff_members.name as staff_name,
          sum(source_entries.amount)::integer as amount
        from (
          select payroll_entries.staff_id, payroll_entries.amount
          from public.payroll_entries
          where payroll_entries.batch_id = p_batch_id
            and payroll_entries.staff_id is not null

          union all

          select manual_allocations.staff_id, manual_allocations.amount
          from public.payroll_manual_dance_allocations as manual_allocations
          where manual_allocations.batch_id = p_batch_id
        ) as source_entries
        join public.staff_members on staff_members.id = source_entries.staff_id
        group by source_entries.staff_id, staff_members.name
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

alter table public.payroll_manual_dance_sessions enable row level security;
alter table public.payroll_manual_dance_participants enable row level security;
alter table public.payroll_manual_dance_allocations enable row level security;

revoke all on public.payroll_manual_dance_sessions from anon, authenticated;
revoke all on public.payroll_manual_dance_participants from anon, authenticated;
revoke all on public.payroll_manual_dance_allocations from anon, authenticated;
revoke all on function public.prevent_payroll_manual_dance_changes() from public;
revoke all on function public.create_payroll_manual_dance_supplement(uuid, integer, text, uuid[]) from public;
grant execute on function public.create_payroll_manual_dance_supplement(uuid, integer, text, uuid[])
  to authenticated;
