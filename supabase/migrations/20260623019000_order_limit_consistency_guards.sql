-- Guard menu item, add-on option, and per-staff add-on limits from
-- contradictory configurations.
--
-- Valid hierarchy:
-- menu_items.order_limit_quantity
--   >= menu_item_order_options.order_limit_quantity
--   >= menu_item_order_option_staff.order_limit_quantity
-- Null means unlimited and does not constrain lower levels.

create or replace function public.validate_menu_item_order_limit_consistency()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
begin
  if new.order_limit_quantity is null then
    return new;
  end if;

  if exists (
    select 1
    from public.menu_item_order_options
    where menu_item_order_options.menu_item_id = new.id
      and menu_item_order_options.order_limit_quantity is not null
      and menu_item_order_options.order_limit_quantity > new.order_limit_quantity
  ) or exists (
    select 1
    from public.menu_item_order_options
    join public.menu_item_order_option_staff
      on menu_item_order_option_staff.option_id = menu_item_order_options.id
    where menu_item_order_options.menu_item_id = new.id
      and menu_item_order_option_staff.order_limit_quantity is not null
      and menu_item_order_option_staff.order_limit_quantity > new.order_limit_quantity
  ) then
    raise exception 'Menu item daily limit cannot be lower than option limits.';
  end if;

  return new;
end;
$$;

create or replace function public.validate_menu_item_order_option_limit_consistency()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  item_limit integer;
begin
  select menu_items.order_limit_quantity
  into item_limit
  from public.menu_items
  where menu_items.id = new.menu_item_id;

  if new.order_limit_quantity is not null
    and item_limit is not null
    and new.order_limit_quantity > item_limit
  then
    raise exception 'Option daily limit cannot exceed menu item daily limit.';
  end if;

  if new.order_limit_quantity is not null and exists (
    select 1
    from public.menu_item_order_option_staff
    where menu_item_order_option_staff.option_id = new.id
      and menu_item_order_option_staff.order_limit_quantity is not null
      and menu_item_order_option_staff.order_limit_quantity > new.order_limit_quantity
  ) then
    raise exception 'Staff option daily limit cannot exceed option daily limit.';
  end if;

  return new;
end;
$$;

create or replace function public.validate_menu_item_order_option_staff_limit_consistency()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  option_limit integer;
  item_limit integer;
begin
  if new.order_limit_quantity is null then
    return new;
  end if;

  select
    menu_item_order_options.order_limit_quantity,
    menu_items.order_limit_quantity
  into option_limit, item_limit
  from public.menu_item_order_options
  join public.menu_items
    on menu_items.id = menu_item_order_options.menu_item_id
  where menu_item_order_options.id = new.option_id;

  if option_limit is not null and new.order_limit_quantity > option_limit then
    raise exception 'Staff option daily limit cannot exceed option daily limit.';
  end if;

  if item_limit is not null and new.order_limit_quantity > item_limit then
    raise exception 'Staff option daily limit cannot exceed menu item daily limit.';
  end if;

  return new;
end;
$$;

drop trigger if exists menu_items_order_limit_consistency_guard
  on public.menu_items;
create trigger menu_items_order_limit_consistency_guard
before insert or update of order_limit_quantity
on public.menu_items
for each row
execute function public.validate_menu_item_order_limit_consistency();

drop trigger if exists menu_item_order_options_limit_consistency_guard
  on public.menu_item_order_options;
create trigger menu_item_order_options_limit_consistency_guard
before insert or update of menu_item_id, order_limit_quantity
on public.menu_item_order_options
for each row
execute function public.validate_menu_item_order_option_limit_consistency();

drop trigger if exists menu_item_order_option_staff_limit_consistency_guard
  on public.menu_item_order_option_staff;
create trigger menu_item_order_option_staff_limit_consistency_guard
before insert or update of option_id, order_limit_quantity
on public.menu_item_order_option_staff
for each row
execute function public.validate_menu_item_order_option_staff_limit_consistency();
