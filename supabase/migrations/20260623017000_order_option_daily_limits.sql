-- Add independent daily limits for menu add-on options.
-- Item-level limits remain unchanged. Option limits are enforced in submit_order
-- with transaction advisory locks to avoid concurrent overselling.

alter table public.menu_item_order_options
  add column if not exists order_limit_quantity integer;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'menu_item_order_options_order_limit_quantity_check'
      and conrelid = 'public.menu_item_order_options'::regclass
  ) then
    alter table public.menu_item_order_options
      add constraint menu_item_order_options_order_limit_quantity_check
      check (order_limit_quantity is null or order_limit_quantity >= 0);
  end if;
end;
$$;

do $order_option_menu_patch$
declare
  function_sql text;
  updated_sql text;
begin
  select pg_get_functiondef('public.get_public_order_menu(text)'::regprocedure)
    into function_sql;

  if position('menu_item_order_options.order_limit_quantity' in function_sql) > 0 then
    return;
  end if;

  updated_sql := replace(
    function_sql,
$$                      'requires_staff_capability',
                        menu_item_order_options.requires_staff_capability,
                      'eligible_staff_ids',$$,
$$                      'requires_staff_capability',
                        menu_item_order_options.requires_staff_capability,
                      'order_limit_quantity',
                        menu_item_order_options.order_limit_quantity,
                      'remaining_quantity',
                        case
                          when menu_item_order_options.order_limit_quantity is null
                            then null
                          else greatest(
                            menu_item_order_options.order_limit_quantity - coalesce((
                              select sum(order_items.quantity)::integer
                              from public.order_items
                              join public.orders
                                on orders.id = order_items.order_id
                              where orders.deleted_at is null
                                and orders.status in ('pending', 'accepted', 'preparing', 'served')
                                and coalesce(
                                  orders.business_date,
                                  (orders.created_at at time zone 'Asia/Taipei')::date
                                ) = (open_state->>'business_date')::date
                                and exists (
                                  select 1
                                  from jsonb_array_elements(
                                    coalesce(order_items.selected_options_snapshot, '[]'::jsonb)
                                  ) as selected_option(value)
                                  where selected_option.value->>'option_id' =
                                    menu_item_order_options.id::text
                                )
                            ), 0),
                            0
                          )
                        end,
                      'eligible_staff_ids',$$
  );

  if updated_sql = function_sql then
    if position('menu_item_order_options.order_limit_quantity' in function_sql) > 0 then
      updated_sql := null;
    else
      raise exception 'get_public_order_menu option limit patch did not match expected function body.';
    end if;
  end if;

  if updated_sql is not null then
    execute updated_sql;
  end if;
end;
$order_option_menu_patch$;

do $order_option_submit_patch$
declare
  function_sql text;
  updated_sql text;
begin
  select pg_get_functiondef('public.submit_order(text,text,text,text,text,jsonb)'::regprocedure)
    into function_sql;

  if position('Selected order option is sold out or insufficient.' in function_sql) > 0 then
    return;
  end if;

  updated_sql := function_sql;

  updated_sql := replace(
    updated_sql,
$$  item_used_quantity integer;
  shop_settings record;$$,
$$  item_used_quantity integer;
  option_used_quantity integer;
  locked_option_id uuid;
  shop_settings record;$$
  );

  updated_sql := replace(
    updated_sql,
$$  end loop;

  insert into public.orders ($$,
$$  end loop;

  for locked_option_id in
    select distinct option_value.value::uuid as option_id
    from jsonb_array_elements(p_items) as item_outer(item_value)
    cross join lateral jsonb_array_elements_text(
      case
        when jsonb_typeof(item_outer.item_value->'selected_option_ids') = 'array'
          then item_outer.item_value->'selected_option_ids'
        else '[]'::jsonb
      end
    ) as option_value(value)
    order by option_id
  loop
    perform pg_advisory_xact_lock(
      hashtextextended(
        'order-option:' || locked_option_id::text || ':' ||
          order_business_date::text,
        0
      )
    );
  end loop;

  insert into public.orders ($$
  );

  updated_sql := replace(
    updated_sql,
$$        menu_item_order_options.requires_staff_capability
      into option_row$$,
$$        menu_item_order_options.requires_staff_capability,
        menu_item_order_options.order_limit_quantity
      into option_row$$
  );

  updated_sql := replace(
    updated_sql,
$$      if not found then
        raise exception 'Selected order option is invalid for this item.';
      end if;

      if option_row.requires_staff_capability then$$,
$$      if not found then
        raise exception 'Selected order option is invalid for this item.';
      end if;

      if option_row.order_limit_quantity is not null then
        select coalesce(sum(order_items.quantity), 0)::integer
        into option_used_quantity
        from public.order_items
        join public.orders
          on orders.id = order_items.order_id
        where orders.deleted_at is null
          and orders.status in ('pending', 'accepted', 'preparing', 'served')
          and coalesce(
            orders.business_date,
            (orders.created_at at time zone 'Asia/Taipei')::date
          ) = order_business_date
          and exists (
            select 1
            from jsonb_array_elements(
              coalesce(order_items.selected_options_snapshot, '[]'::jsonb)
            ) as selected_option(value)
            where selected_option.value->>'option_id' = option_row.id::text
          );

        if option_row.order_limit_quantity - option_used_quantity < item_quantity then
          raise exception 'Selected order option is sold out or insufficient.';
        end if;
      end if;

      if option_row.requires_staff_capability then$$
  );

  if updated_sql = function_sql then
    if position('Selected order option is sold out or insufficient.' in function_sql) > 0 then
      updated_sql := null;
    else
      raise exception 'submit_order option limit patch did not match expected function body.';
    end if;
  elsif position('locked_option_id uuid' in updated_sql) = 0
    or position('Selected order option is sold out or insufficient.' in updated_sql) = 0
  then
    raise exception 'submit_order option limit patch did not match expected function body.';
  end if;

  if updated_sql is not null then
    execute updated_sql;
  end if;
end;
$order_option_submit_patch$;
