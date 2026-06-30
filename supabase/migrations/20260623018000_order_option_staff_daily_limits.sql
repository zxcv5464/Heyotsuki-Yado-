-- Add per-staff daily limits for staff-gated menu add-on options.
-- This extends the existing option-level daily limit. Both limits can coexist:
-- an order must satisfy the global option remaining quantity and the selected
-- staff member's remaining quantity.

alter table public.menu_item_order_option_staff
  add column if not exists order_limit_quantity integer;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'menu_item_order_option_staff_order_limit_quantity_check'
      and conrelid = 'public.menu_item_order_option_staff'::regclass
  ) then
    alter table public.menu_item_order_option_staff
      add constraint menu_item_order_option_staff_order_limit_quantity_check
      check (order_limit_quantity is null or order_limit_quantity >= 0);
  end if;
end;
$$;

do $order_option_staff_menu_patch$
declare
  function_sql text;
  updated_sql text;
begin
  select pg_get_functiondef('public.get_public_order_menu(text)'::regprocedure)
    into function_sql;

  if position('eligible_staff_limits' in function_sql) > 0 then
    return;
  end if;

  updated_sql := replace(
    function_sql,
$$                      'eligible_staff_ids',
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
                        end$$,
$$                      'eligible_staff_ids',
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
                        end,
                      'eligible_staff_limits',
                        case
                          when
                            menu_item_order_options.requires_staff_capability
                          then coalesce((
                            select jsonb_agg(
                              jsonb_build_object(
                                'staff_id',
                                  menu_item_order_option_staff.staff_id,
                                'order_limit_quantity',
                                  menu_item_order_option_staff.order_limit_quantity,
                                'remaining_quantity',
                                  case
                                    when menu_item_order_option_staff.order_limit_quantity is null
                                      then null
                                    else greatest(
                                      menu_item_order_option_staff.order_limit_quantity - coalesce((
                                        select sum(order_items.quantity)::integer
                                        from public.order_items
                                        join public.orders
                                          on orders.id = order_items.order_id
                                        where orders.deleted_at is null
                                          and orders.status in ('pending', 'accepted', 'preparing', 'served')
                                          and order_items.selected_staff_id =
                                            menu_item_order_option_staff.staff_id
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
                                  end
                              )
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
                        end$$
  );

  if updated_sql = function_sql then
    raise exception 'get_public_order_menu staff option limit patch did not match expected function body.';
  end if;

  execute updated_sql;
end;
$order_option_staff_menu_patch$;

do $order_option_staff_submit_patch$
declare
  function_sql text;
  updated_sql text;
begin
  select pg_get_functiondef('public.submit_order(text,text,text,text,text,jsonb)'::regprocedure)
    into function_sql;

  if position('Selected staff order option is sold out or insufficient.' in function_sql) > 0 then
    return;
  end if;

  updated_sql := function_sql;

  updated_sql := replace(
    updated_sql,
$$  option_used_quantity integer;
  locked_option_id uuid;$$,
$$  option_used_quantity integer;
  option_staff_limit_quantity integer;
  option_staff_used_quantity integer;
  locked_option_id uuid;$$
  );

  updated_sql := replace(
    updated_sql,
$$        if not exists (
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
        end if;$$,
$$        select menu_item_order_option_staff.order_limit_quantity
        into option_staff_limit_quantity
        from public.menu_item_order_option_staff
        join public.staff_members
          on staff_members.id = menu_item_order_option_staff.staff_id
        where menu_item_order_option_staff.option_id = option_row.id
          and menu_item_order_option_staff.staff_id = special_staff_id
          and menu_item_order_option_staff.is_visible = true
          and staff_members.is_visible = true;

        if not found then
          raise exception 'Selected staff cannot provide this order option.';
        end if;

        if option_staff_limit_quantity is not null then
          select coalesce(sum(order_items.quantity), 0)::integer
          into option_staff_used_quantity
          from public.order_items
          join public.orders
            on orders.id = order_items.order_id
          where orders.deleted_at is null
            and orders.status in ('pending', 'accepted', 'preparing', 'served')
            and order_items.selected_staff_id = special_staff_id
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

          if option_staff_limit_quantity - option_staff_used_quantity < item_quantity then
            raise exception 'Selected staff order option is sold out or insufficient.';
          end if;
        end if;$$
  );

  if updated_sql = function_sql
    or position('option_staff_limit_quantity integer' in updated_sql) = 0
    or position('Selected staff order option is sold out or insufficient.' in updated_sql) = 0
  then
    raise exception 'submit_order staff option limit patch did not match expected function body.';
  end if;

  execute updated_sql;
end;
$order_option_staff_submit_patch$;
