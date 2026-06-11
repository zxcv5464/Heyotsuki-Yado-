-- Phase 2-B-1: shop-scoped ordering MVP.
-- Run after supabase/schema.sql. This script is idempotent.

create extension if not exists pgcrypto;

alter table public.menu_items
  add column if not exists is_orderable boolean not null default true;
alter table public.menu_items
  add column if not exists requires_staff_selection boolean not null default false;
alter table public.menu_items
  add column if not exists staff_selection_label text
  default '請選擇湯娘的獨門料理';
alter table public.menu_items
  add column if not exists order_limit_quantity integer;
alter table public.menu_items
  add column if not exists allow_item_note boolean not null default true;

alter table public.menus
  add column if not exists order_customer_label text default '角色 ID';
alter table public.menus
  add column if not exists order_contact_visible boolean not null default true;
alter table public.menus
  add column if not exists order_contact_required boolean not null default false;
alter table public.menus
  add column if not exists order_note_visible boolean not null default true;
alter table public.menus
  add column if not exists order_note_required boolean not null default false;
alter table public.menus
  add column if not exists order_acceptance_mode text not null default 'auto';
alter table public.menus
  add column if not exists order_open_weekdays integer[]
  not null default array[5, 6, 0];
alter table public.menus
  add column if not exists order_open_minute integer not null default 1260;
alter table public.menus
  add column if not exists order_close_minute integer not null default 1440;
alter table public.menus
  add column if not exists order_time_slot_minutes integer not null default 30;
alter table public.menus
  add column if not exists order_time_label text not null default '用餐時間';
alter table public.menus
  add column if not exists order_time_required boolean not null default true;
alter table public.menus
  add column if not exists order_time_visible boolean not null default true;
alter table public.menus
  add column if not exists order_closed_message text;
alter table public.menus
  add column if not exists order_manual_notice text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'menu_items_order_limit_quantity_check'
      and conrelid = 'public.menu_items'::regclass
  ) then
    alter table public.menu_items
      add constraint menu_items_order_limit_quantity_check
      check (order_limit_quantity is null or order_limit_quantity >= 0);
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'menus_order_acceptance_mode_check'
      and conrelid = 'public.menus'::regclass
  ) then
    alter table public.menus
      add constraint menus_order_acceptance_mode_check
      check (order_acceptance_mode in ('auto', 'open', 'closed'));
  end if;
  if not exists (
    select 1
    from pg_constraint
    where conname = 'menus_order_open_weekdays_check'
      and conrelid = 'public.menus'::regclass
  ) then
    alter table public.menus
      add constraint menus_order_open_weekdays_check
      check (
        order_open_weekdays <@ array[0, 1, 2, 3, 4, 5, 6]
      );
  end if;
  if not exists (
    select 1
    from pg_constraint
    where conname = 'menus_order_minutes_check'
      and conrelid = 'public.menus'::regclass
  ) then
    alter table public.menus
      add constraint menus_order_minutes_check
      check (
        order_open_minute >= 0
        and order_close_minute > order_open_minute
        and order_close_minute <= 2880
      );
  end if;
  if not exists (
    select 1
    from pg_constraint
    where conname = 'menus_order_time_slot_minutes_check'
      and conrelid = 'public.menus'::regclass
  ) then
    alter table public.menus
      add constraint menus_order_time_slot_minutes_check
      check (order_time_slot_minutes between 5 and 180);
  end if;
end;
$$;

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  shop_key text not null check (shop_key in ('menu', 'menu2')),
  customer_name text not null,
  contact text,
  note text,
  status text not null default 'pending' check (
    status in ('pending', 'accepted', 'preparing', 'served', 'cancelled')
  ),
  admin_note text,
  total_amount_snapshot integer,
  discord_status text not null default 'pending' check (
    discord_status in ('pending', 'sent', 'failed', 'skipped')
  ),
  discord_attempts integer not null default 0 check (discord_attempts >= 0),
  discord_last_error text,
  discord_notified_at timestamptz,
  deleted_at timestamptz,
  deleted_by uuid references auth.users(id) on delete set null,
  delete_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.orders
  add column if not exists requested_time text;
alter table public.orders
  add column if not exists business_date date;

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  menu_item_id uuid references public.menu_items(id) on delete set null,
  item_name_snapshot text not null,
  price_snapshot text,
  price_amount_snapshot integer,
  quantity integer not null default 1 check (quantity >= 1),
  item_note text,
  selected_staff_id uuid references public.staff_members(id) on delete set null,
  selected_staff_name_snapshot text,
  selected_staff_special_label_snapshot text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.staff_order_specials (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.staff_members(id) on delete cascade,
  shop_key text not null check (shop_key in ('menu', 'menu2')),
  display_name text,
  special_label text,
  note text,
  is_visible boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (staff_id, shop_key)
);

create table if not exists public.menu_item_staff_options (
  id uuid primary key default gen_random_uuid(),
  menu_item_id uuid not null references public.menu_items(id) on delete cascade,
  staff_id uuid not null references public.staff_members(id) on delete cascade,
  display_name text,
  option_label text,
  note text,
  is_visible boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (menu_item_id, staff_id)
);

create table if not exists public.menu_item_order_options (
  id uuid primary key default gen_random_uuid(),
  menu_item_id uuid not null references public.menu_items(id) on delete cascade,
  label text not null,
  description text,
  price_delta_amount integer not null default 0,
  price_delta_text text,
  requires_staff_capability boolean not null default false,
  is_visible boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.menu_item_order_option_staff (
  id uuid primary key default gen_random_uuid(),
  option_id uuid not null
    references public.menu_item_order_options(id) on delete cascade,
  staff_id uuid not null references public.staff_members(id) on delete cascade,
  is_visible boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (option_id, staff_id)
);

alter table public.order_items
  add column if not exists selected_options_snapshot jsonb
  not null default '[]'::jsonb;
alter table public.order_items
  add column if not exists options_amount_snapshot integer not null default 0;
alter table public.order_items
  add column if not exists line_total_amount_snapshot integer;
alter table public.order_items
  add column if not exists menu_key_snapshot text;
alter table public.order_items
  add column if not exists menu_title_snapshot text;
alter table public.order_items
  add column if not exists section_id_snapshot uuid;
alter table public.order_items
  add column if not exists section_title_snapshot text;
alter table public.order_items
  add column if not exists section_sort_order_snapshot integer;
alter table public.order_items
  add column if not exists item_sort_order_snapshot integer;

create table if not exists public.admin_shop_permissions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.admin_profiles(id) on delete cascade,
  shop_key text not null check (shop_key in ('menu', 'menu2')),
  can_view_orders boolean not null default false,
  can_update_orders boolean not null default false,
  can_delete_orders boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, shop_key)
);

create index if not exists orders_shop_status_created_idx
  on public.orders (shop_key, status, created_at desc);
create index if not exists orders_deleted_at_idx
  on public.orders (deleted_at);
create index if not exists order_items_order_idx
  on public.order_items (order_id, sort_order);
create index if not exists staff_order_specials_shop_order_idx
  on public.staff_order_specials (shop_key, is_visible, sort_order);
create index if not exists menu_item_staff_options_item_order_idx
  on public.menu_item_staff_options (menu_item_id, is_visible, sort_order);
create index if not exists menu_item_order_options_item_order_idx
  on public.menu_item_order_options (menu_item_id, is_visible, sort_order);
create index if not exists menu_item_order_option_staff_option_idx
  on public.menu_item_order_option_staff (option_id, is_visible, sort_order);
create index if not exists admin_shop_permissions_user_shop_idx
  on public.admin_shop_permissions (user_id, shop_key);

drop trigger if exists orders_set_updated_at on public.orders;
create trigger orders_set_updated_at
before update on public.orders
for each row execute function public.set_updated_at();

drop trigger if exists staff_order_specials_set_updated_at
  on public.staff_order_specials;
create trigger staff_order_specials_set_updated_at
before update on public.staff_order_specials
for each row execute function public.set_updated_at();

drop trigger if exists menu_item_staff_options_set_updated_at
  on public.menu_item_staff_options;
create trigger menu_item_staff_options_set_updated_at
before update on public.menu_item_staff_options
for each row execute function public.set_updated_at();

drop trigger if exists menu_item_order_options_set_updated_at
  on public.menu_item_order_options;
create trigger menu_item_order_options_set_updated_at
before update on public.menu_item_order_options
for each row execute function public.set_updated_at();

drop trigger if exists menu_item_order_option_staff_set_updated_at
  on public.menu_item_order_option_staff;
create trigger menu_item_order_option_staff_set_updated_at
before update on public.menu_item_order_option_staff
for each row execute function public.set_updated_at();

drop trigger if exists admin_shop_permissions_set_updated_at
  on public.admin_shop_permissions;
create trigger admin_shop_permissions_set_updated_at
before update on public.admin_shop_permissions
for each row execute function public.set_updated_at();

create or replace function public.is_owner()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.admin_profiles
    where id = auth.uid()
      and role = 'owner'
      and is_active = true
  );
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.admin_profiles
    where id = auth.uid()
      and role = 'admin'
      and is_active = true
  );
$$;

create or replace function public.is_staff()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.admin_profiles
    where id = auth.uid()
      and role = 'staff'
      and is_active = true
  );
$$;

create or replace function public.can_view_shop_orders(p_shop_key text)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select
    p_shop_key in ('menu', 'menu2')
    and (
      public.is_owner()
      or public.is_admin()
      or (
        public.is_staff()
        and exists (
          select 1
          from public.admin_shop_permissions
          where user_id = auth.uid()
            and shop_key = p_shop_key
            and can_view_orders = true
        )
      )
    );
$$;

create or replace function public.can_update_shop_orders(p_shop_key text)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select
    p_shop_key in ('menu', 'menu2')
    and (
      public.is_owner()
      or public.is_admin()
      or (
        public.is_staff()
        and exists (
          select 1
          from public.admin_shop_permissions
          where user_id = auth.uid()
            and shop_key = p_shop_key
            and can_update_orders = true
        )
      )
    );
$$;

create or replace function public.can_delete_shop_orders(p_shop_key text)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select
    p_shop_key in ('menu', 'menu2')
    and (
      public.is_owner()
      or public.is_admin()
      or (
        public.is_staff()
        and exists (
          select 1
          from public.admin_shop_permissions
          where user_id = auth.uid()
            and shop_key = p_shop_key
            and can_delete_orders = true
        )
      )
    );
$$;

create or replace function public.protect_order_update()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if auth.role() = 'service_role' then
    return new;
  end if;

  if current_setting('heyotsuki.order_submit', true) = 'on' then
    return new;
  end if;

  -- Keep older deployed submit_order versions working while anon remains
  -- unable to update orders directly through grants or RLS.
  if auth.role() = 'anon'
    and old.shop_key = new.shop_key
    and old.customer_name is not distinct from new.customer_name
    and old.contact is not distinct from new.contact
    and old.note is not distinct from new.note
    and old.requested_time is not distinct from new.requested_time
    and old.business_date is not distinct from new.business_date
    and old.status is not distinct from new.status
    and old.admin_note is not distinct from new.admin_note
    and old.discord_status is not distinct from new.discord_status
    and old.discord_attempts is not distinct from new.discord_attempts
    and old.discord_last_error is not distinct from new.discord_last_error
    and old.discord_notified_at is not distinct from new.discord_notified_at
    and old.deleted_at is not distinct from new.deleted_at
    and old.deleted_by is not distinct from new.deleted_by
    and old.delete_reason is not distinct from new.delete_reason
    and old.created_at is not distinct from new.created_at
  then
    return new;
  end if;

  if public.is_owner() or public.is_admin() then
    return new;
  end if;

  if not public.is_staff() then
    raise exception 'Order update permission denied.';
  end if;

  if old.deleted_at is not null then
    raise exception 'Deleted orders cannot be changed by staff.';
  end if;

  if old.shop_key <> new.shop_key
    or old.customer_name is distinct from new.customer_name
    or old.contact is distinct from new.contact
    or old.note is distinct from new.note
    or old.requested_time is distinct from new.requested_time
    or old.business_date is distinct from new.business_date
    or old.total_amount_snapshot is distinct from new.total_amount_snapshot
    or old.discord_status is distinct from new.discord_status
    or old.discord_attempts is distinct from new.discord_attempts
    or old.discord_last_error is distinct from new.discord_last_error
    or old.discord_notified_at is distinct from new.discord_notified_at
    or old.created_at is distinct from new.created_at
  then
    raise exception 'Staff may only update order status and admin note.';
  end if;

  if old.deleted_at is null and new.deleted_at is not null then
    if not public.can_delete_shop_orders(old.shop_key) then
      raise exception 'Order delete permission denied.';
    end if;
    if new.deleted_by is distinct from auth.uid() then
      raise exception 'Deleted order must record the current user.';
    end if;
  elsif old.deleted_at is distinct from new.deleted_at
    or old.deleted_by is distinct from new.deleted_by
    or old.delete_reason is distinct from new.delete_reason
  then
    raise exception 'Order delete fields cannot be changed.';
  end if;

  if not public.can_update_shop_orders(old.shop_key)
    and (
      old.status is distinct from new.status
      or old.admin_note is distinct from new.admin_note
    )
  then
    raise exception 'Order update permission denied.';
  end if;

  return new;
end;
$$;

drop trigger if exists orders_protect_staff_update on public.orders;
create trigger orders_protect_staff_update
before update on public.orders
for each row execute function public.protect_order_update();

create or replace function public.get_order_shop_open_state(p_shop_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  shop record;
  taipei_now timestamp := now() at time zone 'Asia/Taipei';
  today_date date;
  current_minute integer;
  effective_minute integer;
  business_day date;
  business_weekday integer;
  accepting boolean := false;
  closed_reason text;
  open_label_value text;
  slots jsonb := '[]'::jsonb;
begin
  if p_shop_key not in ('menu', 'menu2') then
    raise exception 'Invalid shop key.';
  end if;

  select
    menus.order_acceptance_mode,
    menus.order_open_weekdays,
    menus.order_open_minute,
    menus.order_close_minute,
    menus.order_time_slot_minutes,
    menus.order_closed_message,
    menus.order_manual_notice
  into shop
  from public.menus
  where menus.key = p_shop_key
    and menus.is_visible = true;

  if not found then
    raise exception 'Shop is not available.';
  end if;

  today_date := taipei_now::date;
  current_minute :=
    extract(hour from taipei_now)::integer * 60 +
    extract(minute from taipei_now)::integer;
  business_day := today_date;
  effective_minute := current_minute;

  if shop.order_close_minute > 1440
    and current_minute < shop.order_close_minute - 1440
  then
    business_day := today_date - 1;
    effective_minute := current_minute + 1440;
  end if;

  business_weekday := extract(dow from business_day)::integer;
  open_label_value :=
    case
      when shop.order_open_minute = 1440 then '24:00'
      else
        lpad(((shop.order_open_minute / 60) % 24)::text, 2, '0') || ':' ||
        lpad((shop.order_open_minute % 60)::text, 2, '0')
    end || ' - ' ||
    case
      when shop.order_close_minute = 1440 then '24:00'
      else
        lpad(((shop.order_close_minute / 60) % 24)::text, 2, '0') || ':' ||
        lpad((shop.order_close_minute % 60)::text, 2, '0')
    end;

  select coalesce(
    jsonb_agg(
      to_char(
        time '00:00' + ((slot_minute % 1440) * interval '1 minute'),
        'HH24:MI'
      )
      order by slot_minute
    ),
    '[]'::jsonb
  )
  into slots
  from generate_series(
    shop.order_open_minute,
    shop.order_close_minute - 1,
    shop.order_time_slot_minutes
  ) as generated(slot_minute);

  if shop.order_acceptance_mode = 'closed' then
    accepting := false;
    closed_reason := coalesce(
      nullif(trim(shop.order_closed_message), ''),
      '目前未開放點餐'
    );
  elsif shop.order_acceptance_mode = 'open' then
    accepting := true;
    closed_reason := coalesce(
      nullif(trim(shop.order_manual_notice), ''),
      '目前開放點餐'
    );
  else
    accepting :=
      business_weekday = any(shop.order_open_weekdays)
      and effective_minute >= shop.order_open_minute
      and effective_minute < shop.order_close_minute;
    closed_reason := case
      when accepting then null
      else coalesce(
        nullif(trim(shop.order_closed_message), ''),
        '目前非營業時間，暫不開放點餐'
      )
    end;
  end if;

  return jsonb_build_object(
    'is_accepting', accepting,
    'mode', shop.order_acceptance_mode,
    'reason', closed_reason,
    'business_date', business_day,
    'open_label', open_label_value,
    'time_slots', slots
  );
end;
$$;

create or replace function public.get_public_order_menu(p_shop_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  result jsonb;
  open_state jsonb;
begin
  if p_shop_key not in ('menu', 'menu2') then
    raise exception 'Invalid shop key.';
  end if;

  open_state := public.get_order_shop_open_state(p_shop_key);

  select jsonb_build_object(
    'shop', jsonb_build_object(
      'key', menus.key,
      'title', menus.title,
      'short_title', menus.short_title,
      'description', menus.description,
      'href', menus.href,
      'order_customer_label',
        coalesce(nullif(trim(menus.order_customer_label), ''), '角色 ID'),
      'order_contact_visible', menus.order_contact_visible,
      'order_contact_required',
        menus.order_contact_visible and menus.order_contact_required,
      'order_note_visible', menus.order_note_visible,
      'order_note_required',
        menus.order_note_visible and menus.order_note_required,
      'order_accepting', (open_state->>'is_accepting')::boolean,
      'order_acceptance_mode', open_state->>'mode',
      'order_closed_reason', open_state->>'reason',
      'business_date', open_state->>'business_date',
      'order_time_label',
        coalesce(nullif(trim(menus.order_time_label), ''), '用餐時間'),
      'order_time_visible', menus.order_time_visible,
      'order_time_required',
        menus.order_time_visible and menus.order_time_required,
      'order_time_slots', coalesce(open_state->'time_slots', '[]'::jsonb)
    ),
    'sections', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', menu_sections.id,
          'title', menu_sections.title,
          'subtitle', menu_sections.subtitle,
          'notice', menu_sections.notice,
          'layout_type', menu_sections.layout_type,
          'sort_order', menu_sections.sort_order,
          'items', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'id', menu_items.id,
                'name', menu_items.name,
                'description', menu_items.description,
                'price', menu_items.price,
                'featured', menu_items.featured,
                'sort_order', menu_items.sort_order,
                'order_limit_quantity', menu_items.order_limit_quantity,
                'remaining_quantity',
                  case
                    when menu_items.order_limit_quantity is null then null
                    else greatest(
                      menu_items.order_limit_quantity - coalesce((
                        select sum(order_items.quantity)::integer
                        from public.order_items
                        join public.orders
                          on orders.id = order_items.order_id
                        where order_items.menu_item_id = menu_items.id
                          and orders.deleted_at is null
                          and orders.status in (
                            'pending',
                            'accepted',
                            'preparing',
                            'served'
                          )
                          and coalesce(
                            orders.business_date,
                            (
                              orders.created_at at time zone 'Asia/Taipei'
                            )::date
                          ) = (open_state->>'business_date')::date
                      ), 0),
                      0
                    )
                  end,
                'allow_item_note', menu_items.allow_item_note,
                'requires_staff_selection',
                  menu_items.requires_staff_selection,
                'staff_selection_label',
                  coalesce(
                    nullif(trim(menu_items.staff_selection_label), ''),
                    '請選擇湯娘的獨門料理'
                  ),
                'staff_options', coalesce((
                  select jsonb_agg(
                    jsonb_build_object(
                      'id', menu_item_staff_options.id,
                      'staff_id', menu_item_staff_options.staff_id,
                      'display_name', coalesce(
                        nullif(trim(menu_item_staff_options.display_name), ''),
                        staff_members.name
                      ),
                      'option_label', coalesce(
                        nullif(trim(menu_item_staff_options.option_label), ''),
                        nullif(trim(menu_item_staff_options.display_name), ''),
                        staff_members.name
                      ),
                      'sort_order', menu_item_staff_options.sort_order
                    )
                    order by
                      menu_item_staff_options.sort_order,
                      staff_members.name
                  )
                  from public.menu_item_staff_options
                  join public.staff_members
                    on staff_members.id = menu_item_staff_options.staff_id
                  where menu_item_staff_options.menu_item_id = menu_items.id
                    and menu_item_staff_options.is_visible = true
                    and staff_members.is_visible = true
                ), '[]'::jsonb),
                'order_options', coalesce((
                  select jsonb_agg(
                    jsonb_build_object(
                      'id', menu_item_order_options.id,
                      'label', menu_item_order_options.label,
                      'description', menu_item_order_options.description,
                      'price_delta_amount',
                        menu_item_order_options.price_delta_amount,
                      'price_delta_text', coalesce(
                        nullif(
                          trim(menu_item_order_options.price_delta_text),
                          ''
                        ),
                        case
                          when menu_item_order_options.price_delta_amount >= 0
                            then '+'
                          else ''
                        end ||
                        to_char(
                          menu_item_order_options.price_delta_amount,
                          'FM999,999,999,990'
                        ) || ' Gil'
                      ),
                      'requires_staff_capability',
                        menu_item_order_options.requires_staff_capability,
                      'eligible_staff_ids',
                        case
                          when
                            menu_item_order_options.requires_staff_capability
                          then coalesce((
                            select jsonb_agg(
                              menu_item_order_option_staff.staff_id
                              order by
                                menu_item_order_option_staff.sort_order,
                                staff_members.name
                            )
                            from public.menu_item_order_option_staff
                            join public.staff_members
                              on staff_members.id =
                                menu_item_order_option_staff.staff_id
                            where
                              menu_item_order_option_staff.option_id =
                                menu_item_order_options.id
                              and
                                menu_item_order_option_staff.is_visible = true
                              and staff_members.is_visible = true
                          ), '[]'::jsonb)
                          else '[]'::jsonb
                        end
                    )
                    order by
                      menu_item_order_options.sort_order,
                      menu_item_order_options.label
                  )
                  from public.menu_item_order_options
                  where
                    menu_item_order_options.menu_item_id = menu_items.id
                    and menu_item_order_options.is_visible = true
                ), '[]'::jsonb)
              )
              order by menu_items.sort_order, menu_items.name
            )
            from public.menu_items
            where menu_items.section_id = menu_sections.id
              and menu_items.is_visible = true
              and menu_items.is_orderable = true
          ), '[]'::jsonb)
        )
        order by menu_sections.sort_order, menu_sections.title
      )
      from public.menu_sections
      where menu_sections.menu_key = menus.key
        and menu_sections.is_visible = true
        and exists (
          select 1
          from public.menu_items
          where menu_items.section_id = menu_sections.id
            and menu_items.is_visible = true
            and menu_items.is_orderable = true
        )
    ), '[]'::jsonb)
  )
  into result
  from public.menus
  where menus.key = p_shop_key
    and menus.is_visible = true;

  if result is null then
    raise exception 'Shop is not available.';
  end if;

  return result;
end;
$$;

create or replace function public.submit_order(
  p_shop_key text,
  p_customer_name text,
  p_contact text,
  p_note text,
  p_requested_time text,
  p_items jsonb
)
returns table (
  order_id uuid,
  status text
)
language plpgsql
volatile
security definer
set search_path = pg_catalog, public
as $$
declare
  new_order_id uuid;
  item jsonb;
  item_row record;
  special_staff_id uuid;
  special_display_name text;
  special_label text;
  selected_option_ids jsonb;
  selected_option_id uuid;
  option_row record;
  options_snapshot_value jsonb;
  options_amount_value integer;
  line_total_value integer;
  locked_item_id uuid;
  item_quantity integer;
  item_price_amount integer;
  item_used_quantity integer;
  shop_settings record;
  open_state jsonb;
  order_business_date date;
  normalized_requested_time text;
  total_amount integer := 0;
  has_parsed_amount boolean := false;
  item_index integer := 0;
begin
  if p_shop_key not in ('menu', 'menu2') then
    raise exception 'Invalid shop key.';
  end if;
  if nullif(trim(p_customer_name), '') is null then
    raise exception 'Customer name is required.';
  end if;
  if p_items is null
    or jsonb_typeof(p_items) <> 'array'
    or jsonb_array_length(p_items) < 1
  then
    raise exception 'At least one order item is required.';
  end if;

  open_state := public.get_order_shop_open_state(p_shop_key);
  if not coalesce((open_state->>'is_accepting')::boolean, false) then
    raise exception '目前非營業時間，暫不開放點餐。';
  end if;
  order_business_date := (open_state->>'business_date')::date;
  normalized_requested_time := nullif(trim(p_requested_time), '');

  select
    menus.order_contact_visible,
    menus.order_contact_required,
    menus.order_note_visible,
    menus.order_note_required,
    menus.order_time_visible,
    menus.order_time_required
  into shop_settings
  from public.menus
  where menus.key = p_shop_key
    and menus.is_visible = true;

  if not found then
    raise exception 'Shop is not available.';
  end if;
  if shop_settings.order_contact_visible
    and shop_settings.order_contact_required
    and nullif(trim(p_contact), '') is null
  then
    raise exception 'Contact is required.';
  end if;
  if shop_settings.order_note_visible
    and shop_settings.order_note_required
    and nullif(trim(p_note), '') is null
  then
    raise exception 'Order note is required.';
  end if;
  if not shop_settings.order_time_visible then
    normalized_requested_time := null;
  end if;
  if shop_settings.order_time_visible
    and shop_settings.order_time_required
    and normalized_requested_time is null
  then
    raise exception 'Requested time is required.';
  end if;
  if shop_settings.order_time_visible
    and normalized_requested_time is not null
    and not exists (
      select 1
      from jsonb_array_elements_text(
        coalesce(open_state->'time_slots', '[]'::jsonb)
      ) as available(value)
      where available.value = normalized_requested_time
    )
  then
    raise exception 'Requested time is unavailable.';
  end if;

  for locked_item_id in
    select distinct (value->>'menu_item_id')::uuid as menu_item_id
    from jsonb_array_elements(p_items)
    where nullif(value->>'menu_item_id', '') is not null
    order by menu_item_id
  loop
    perform pg_advisory_xact_lock(
      hashtextextended(
        locked_item_id::text || ':' || order_business_date::text,
        0
      )
    );
  end loop;

  insert into public.orders (
    shop_key,
    customer_name,
    contact,
    note,
    requested_time,
    business_date
  ) values (
    p_shop_key,
    trim(p_customer_name),
    case
      when shop_settings.order_contact_visible
        then nullif(trim(p_contact), '')
      else null
    end,
    case
      when shop_settings.order_note_visible
        then nullif(trim(p_note), '')
      else null
    end,
    normalized_requested_time,
    order_business_date
  )
  returning id into new_order_id;

  for item in select value from jsonb_array_elements(p_items)
  loop
    item_index := item_index + 1;
    begin
      item_quantity := coalesce((item->>'quantity')::integer, 0);
    exception when others then
      raise exception 'Invalid item quantity.';
    end;
    if item_quantity < 1 then
      raise exception 'Item quantity must be at least 1.';
    end if;

    select
      menu_items.id,
      menu_items.name,
      menu_items.price,
      menu_items.requires_staff_selection,
      menu_items.staff_selection_label,
      menu_items.order_limit_quantity,
      menu_items.allow_item_note,
      menu_items.sort_order as item_sort_order,
      menu_sections.id as section_id,
      menu_sections.title as section_title,
      menu_sections.sort_order as section_sort_order,
      menu_sections.menu_key,
      coalesce(
        nullif(trim(menus.title), ''),
        nullif(trim(menus.short_title), ''),
        menus.key
      ) as menu_title
    into item_row
    from public.menu_items
    join public.menu_sections
      on menu_sections.id = menu_items.section_id
    join public.menus
      on menus.key = menu_sections.menu_key
    where menu_items.id = (item->>'menu_item_id')::uuid
      and menu_sections.menu_key = p_shop_key
      and menus.is_visible = true
      and menu_sections.is_visible = true
      and menu_items.is_visible = true
      and menu_items.is_orderable = true;

    if not found then
      raise exception 'Order item is invalid or unavailable.';
    end if;

    if item_row.order_limit_quantity is not null then
      select coalesce(sum(order_items.quantity), 0)::integer
      into item_used_quantity
      from public.order_items
      join public.orders
        on orders.id = order_items.order_id
      where order_items.menu_item_id = item_row.id
        and orders.deleted_at is null
        and orders.status in ('pending', 'accepted', 'preparing', 'served')
        and coalesce(
          orders.business_date,
          (orders.created_at at time zone 'Asia/Taipei')::date
        ) = order_business_date;

      if item_row.order_limit_quantity - item_used_quantity < item_quantity then
        raise exception '此品項已售完或剩餘數量不足。';
      end if;
    end if;

    item_price_amount := null;
    if coalesce(item_row.price, '') ~ '[0-9]' then
      begin
        item_price_amount :=
          nullif(regexp_replace(item_row.price, '[^0-9]', '', 'g'), '')::integer;
      exception when numeric_value_out_of_range then
        item_price_amount := null;
      end;
    end if;

    special_staff_id := null;
    special_display_name := null;
    special_label := null;
    if item_row.requires_staff_selection then
      if nullif(item->>'selected_staff_id', '') is null then
        raise exception 'This item requires a staff selection.';
      end if;
      select
        menu_item_staff_options.staff_id,
        coalesce(
          nullif(trim(menu_item_staff_options.display_name), ''),
          staff_members.name
        ) as display_name,
        coalesce(
          nullif(trim(menu_item_staff_options.option_label), ''),
          nullif(trim(menu_item_staff_options.display_name), ''),
          staff_members.name
        ) as option_label
      into special_staff_id, special_display_name, special_label
      from public.menu_item_staff_options
      join public.staff_members
        on staff_members.id = menu_item_staff_options.staff_id
      where menu_item_staff_options.staff_id =
          (item->>'selected_staff_id')::uuid
        and menu_item_staff_options.menu_item_id = item_row.id
        and menu_item_staff_options.is_visible = true
        and staff_members.is_visible = true;
      if not found then
        raise exception 'Selected staff is unavailable for this item.';
      end if;
    end if;

    selected_option_ids := coalesce(
      item->'selected_option_ids',
      '[]'::jsonb
    );
    if jsonb_typeof(selected_option_ids) <> 'array' then
      raise exception 'Selected option ids must be an array.';
    end if;
    if jsonb_array_length(selected_option_ids) <> (
      select count(distinct value)
      from jsonb_array_elements_text(selected_option_ids)
    ) then
      raise exception 'Duplicate order option is not allowed.';
    end if;

    options_snapshot_value := '[]'::jsonb;
    options_amount_value := 0;
    for selected_option_id in
      select value::uuid
      from jsonb_array_elements_text(selected_option_ids)
    loop
      select
        menu_item_order_options.id,
        menu_item_order_options.label,
        menu_item_order_options.price_delta_amount,
        coalesce(
          nullif(trim(menu_item_order_options.price_delta_text), ''),
          case
            when menu_item_order_options.price_delta_amount >= 0 then '+'
            else ''
          end ||
          to_char(
            menu_item_order_options.price_delta_amount,
            'FM999,999,999,990'
          ) || ' Gil'
        ) as price_delta_text,
        menu_item_order_options.requires_staff_capability
      into option_row
      from public.menu_item_order_options
      where menu_item_order_options.id = selected_option_id
        and menu_item_order_options.menu_item_id = item_row.id
        and menu_item_order_options.is_visible = true;

      if not found then
        raise exception 'Selected order option is invalid for this item.';
      end if;

      if option_row.requires_staff_capability then
        if special_staff_id is null then
          raise exception 'This order option requires a staff selection.';
        end if;
        if not exists (
          select 1
          from public.menu_item_order_option_staff
          join public.staff_members
            on staff_members.id = menu_item_order_option_staff.staff_id
          where menu_item_order_option_staff.option_id = option_row.id
            and menu_item_order_option_staff.staff_id = special_staff_id
            and menu_item_order_option_staff.is_visible = true
            and staff_members.is_visible = true
        ) then
          raise exception 'Selected staff cannot provide this order option.';
        end if;
      end if;

      options_amount_value :=
        options_amount_value + option_row.price_delta_amount;
      options_snapshot_value := options_snapshot_value ||
        jsonb_build_array(
          jsonb_build_object(
            'option_id', option_row.id,
            'label', option_row.label,
            'price_delta_amount', option_row.price_delta_amount,
            'price_delta_text', option_row.price_delta_text
          )
        );
    end loop;

    line_total_value := case
      when item_price_amount is null then null
      else (item_price_amount + options_amount_value) * item_quantity
    end;

    insert into public.order_items (
      order_id,
      menu_item_id,
      item_name_snapshot,
      price_snapshot,
      price_amount_snapshot,
      quantity,
      item_note,
      selected_staff_id,
      selected_staff_name_snapshot,
      selected_staff_special_label_snapshot,
      selected_options_snapshot,
      options_amount_snapshot,
      line_total_amount_snapshot,
      menu_key_snapshot,
      menu_title_snapshot,
      section_id_snapshot,
      section_title_snapshot,
      section_sort_order_snapshot,
      item_sort_order_snapshot,
      sort_order
    ) values (
      new_order_id,
      item_row.id,
      item_row.name,
      item_row.price,
      item_price_amount,
      item_quantity,
      case
        when item_row.allow_item_note
          then nullif(trim(item->>'item_note'), '')
        else null
      end,
      case
        when item_row.requires_staff_selection then special_staff_id
        else null
      end,
      case
        when item_row.requires_staff_selection then special_display_name
        else null
      end,
      case
        when item_row.requires_staff_selection then special_label
        else null
      end,
      options_snapshot_value,
      options_amount_value,
      line_total_value,
      item_row.menu_key,
      item_row.menu_title,
      item_row.section_id,
      item_row.section_title,
      item_row.section_sort_order,
      item_row.item_sort_order,
      item_index * 10
    );

    if line_total_value is not null then
      total_amount := total_amount + line_total_value;
      has_parsed_amount := true;
    end if;
  end loop;

  perform set_config('heyotsuki.order_submit', 'on', true);

  update public.orders
  set total_amount_snapshot =
    case when has_parsed_amount then total_amount else null end
  where id = new_order_id;

  return query select new_order_id, 'ok'::text;
end;
$$;

create or replace function public.submit_order(
  p_shop_key text,
  p_customer_name text,
  p_contact text,
  p_note text,
  p_items jsonb
)
returns table (
  order_id uuid,
  status text
)
language sql
volatile
security definer
set search_path = pg_catalog, public
as $$
  select *
  from public.submit_order(
    p_shop_key,
    p_customer_name,
    p_contact,
    p_note,
    null,
    p_items
  );
$$;

revoke all on function public.is_owner() from public;
revoke all on function public.is_admin() from public;
revoke all on function public.is_staff() from public;
revoke all on function public.can_view_shop_orders(text) from public;
revoke all on function public.can_update_shop_orders(text) from public;
revoke all on function public.can_delete_shop_orders(text) from public;
grant execute on function public.is_owner() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.is_staff() to authenticated;
grant execute on function public.can_view_shop_orders(text) to authenticated;
grant execute on function public.can_update_shop_orders(text) to authenticated;
grant execute on function public.can_delete_shop_orders(text) to authenticated;

revoke all on function public.get_public_order_menu(text) from public;
revoke all on function public.get_order_shop_open_state(text) from public;
revoke all on function public.submit_order(text, text, text, text, jsonb)
  from public;
revoke all on function public.submit_order(
  text, text, text, text, text, jsonb
) from public;
grant execute on function public.get_public_order_menu(text)
  to anon, authenticated;
grant execute on function public.get_order_shop_open_state(text)
  to anon, authenticated;
grant execute on function public.submit_order(text, text, text, text, jsonb)
  to anon, authenticated;
grant execute on function public.submit_order(
  text, text, text, text, text, jsonb
) to anon, authenticated;

alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.staff_order_specials enable row level security;
alter table public.menu_item_staff_options enable row level security;
alter table public.menu_item_order_options enable row level security;
alter table public.menu_item_order_option_staff enable row level security;
alter table public.admin_shop_permissions enable row level security;

drop policy if exists "orders_backoffice_read" on public.orders;
create policy "orders_backoffice_read"
on public.orders
for select
to authenticated
using (public.can_view_shop_orders(shop_key));

drop policy if exists "orders_backoffice_update" on public.orders;
create policy "orders_backoffice_update"
on public.orders
for update
to authenticated
using (
  public.can_update_shop_orders(shop_key)
  or public.can_delete_shop_orders(shop_key)
)
with check (
  public.can_update_shop_orders(shop_key)
  or public.can_delete_shop_orders(shop_key)
);

drop policy if exists "orders_admin_delete" on public.orders;
create policy "orders_admin_delete"
on public.orders
for delete
to authenticated
using (public.is_owner() or public.is_admin());

drop policy if exists "order_items_backoffice_read" on public.order_items;
create policy "order_items_backoffice_read"
on public.order_items
for select
to authenticated
using (
  exists (
    select 1
    from public.orders
    where orders.id = order_items.order_id
      and public.can_view_shop_orders(orders.shop_key)
  )
);

drop policy if exists "staff_order_specials_backoffice_read"
  on public.staff_order_specials;
create policy "staff_order_specials_backoffice_read"
on public.staff_order_specials
for select
to authenticated
using (
  public.is_owner()
  or public.is_admin()
  or public.is_staff()
);

drop policy if exists "staff_order_specials_admin_write"
  on public.staff_order_specials;
create policy "staff_order_specials_admin_write"
on public.staff_order_specials
for all
to authenticated
using (public.is_owner() or public.is_admin())
with check (public.is_owner() or public.is_admin());

drop policy if exists "menu_item_staff_options_admin_read"
  on public.menu_item_staff_options;
create policy "menu_item_staff_options_admin_read"
on public.menu_item_staff_options
for select
to authenticated
using (public.is_owner() or public.is_admin());

drop policy if exists "menu_item_staff_options_admin_write"
  on public.menu_item_staff_options;
create policy "menu_item_staff_options_admin_write"
on public.menu_item_staff_options
for all
to authenticated
using (public.is_owner() or public.is_admin())
with check (public.is_owner() or public.is_admin());

drop policy if exists "menu_item_order_options_admin_read"
  on public.menu_item_order_options;
create policy "menu_item_order_options_admin_read"
on public.menu_item_order_options
for select
to authenticated
using (public.is_owner() or public.is_admin());

drop policy if exists "menu_item_order_options_admin_write"
  on public.menu_item_order_options;
create policy "menu_item_order_options_admin_write"
on public.menu_item_order_options
for all
to authenticated
using (public.is_owner() or public.is_admin())
with check (public.is_owner() or public.is_admin());

drop policy if exists "menu_item_order_option_staff_admin_read"
  on public.menu_item_order_option_staff;
create policy "menu_item_order_option_staff_admin_read"
on public.menu_item_order_option_staff
for select
to authenticated
using (public.is_owner() or public.is_admin());

drop policy if exists "menu_item_order_option_staff_admin_write"
  on public.menu_item_order_option_staff;
create policy "menu_item_order_option_staff_admin_write"
on public.menu_item_order_option_staff
for all
to authenticated
using (public.is_owner() or public.is_admin())
with check (public.is_owner() or public.is_admin());

drop policy if exists "admin_shop_permissions_read"
  on public.admin_shop_permissions;
create policy "admin_shop_permissions_read"
on public.admin_shop_permissions
for select
to authenticated
using (
  public.is_owner()
  or public.is_admin()
  or user_id = auth.uid()
);

drop policy if exists "admin_shop_permissions_owner_write"
  on public.admin_shop_permissions;
create policy "admin_shop_permissions_owner_write"
on public.admin_shop_permissions
for all
to authenticated
using (public.is_owner())
with check (public.is_owner());

revoke all on public.orders from anon, authenticated;
revoke all on public.order_items from anon, authenticated;
revoke all on public.staff_order_specials from anon, authenticated;
revoke all on public.menu_item_staff_options from anon, authenticated;
revoke all on public.menu_item_order_options from anon, authenticated;
revoke all on public.menu_item_order_option_staff from anon, authenticated;
revoke all on public.admin_shop_permissions from anon, authenticated;

grant select, update, delete on public.orders to authenticated;
grant select on public.order_items to authenticated;
grant select, insert, update, delete
  on public.staff_order_specials to authenticated;
grant select, insert, update, delete
  on public.menu_item_staff_options to authenticated;
grant select, insert, update, delete
  on public.menu_item_order_options to authenticated;
grant select, insert, update, delete
  on public.menu_item_order_option_staff to authenticated;
grant select, insert, update, delete
  on public.admin_shop_permissions to authenticated;

-- Existing hidden-menu item defaults.
update public.menu_items
set
  requires_staff_selection = true,
  staff_selection_label = coalesce(
    nullif(trim(staff_selection_label), ''),
    '請選擇湯娘的獨門料理'
  )
where name = '湯娘隱藏版';
