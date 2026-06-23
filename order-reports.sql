-- Phase 2-B-3 order sales reports.
-- Run supabase/orders.sql before this file.

create or replace function public.get_order_report_default_business_date(
  p_shop_key text
)
returns date
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  open_state jsonb;
begin
  if p_shop_key not in ('menu', 'menu2') then
    raise exception 'Invalid shop key.';
  end if;
  if not public.can_view_shop_orders(p_shop_key) then
    raise exception 'You do not have permission to view this shop report.';
  end if;

  open_state := public.get_order_shop_open_state(p_shop_key);
  return coalesce(
    nullif(open_state->>'business_date', '')::date,
    (now() at time zone 'Asia/Taipei')::date
  );
end;
$$;

create or replace function public.get_order_sales_report(
  p_shop_key text,
  p_business_date_from date,
  p_business_date_to date,
  p_statuses text[] default array[
    'pending',
    'accepted',
    'preparing',
    'served'
  ]
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  shop_title_value text;
  order_count_value integer := 0;
  quantity_value integer := 0;
  grand_total_value bigint := 0;
  sections_value jsonb := '[]'::jsonb;
  warnings_value jsonb := '[]'::jsonb;
  unpriced_count integer := 0;
begin
  if p_shop_key not in ('menu', 'menu2') then
    raise exception 'Invalid shop key.';
  end if;
  if p_business_date_from is null or p_business_date_to is null then
    raise exception 'Business date range is required.';
  end if;
  if p_business_date_to < p_business_date_from then
    raise exception 'Business date end cannot be earlier than start.';
  end if;
  if p_statuses is null or cardinality(p_statuses) = 0 then
    raise exception 'At least one order status is required.';
  end if;
  if exists (
    select 1
    from unnest(p_statuses) as selected_status
    where selected_status not in (
      'pending',
      'accepted',
      'preparing',
      'served',
      'cancelled'
    )
  ) then
    raise exception 'Invalid order status.';
  end if;
  if not public.can_view_shop_orders(p_shop_key) then
    raise exception 'You do not have permission to view this shop report.';
  end if;

  select coalesce(
    nullif(trim(menus.title), ''),
    nullif(trim(menus.short_title), ''),
    menus.key
  )
  into shop_title_value
  from public.menus
  where menus.key = p_shop_key;

  if not found then
    raise exception 'Shop was not found.';
  end if;

  with filtered_orders as (
    select orders.id
    from public.orders
    where orders.shop_key = p_shop_key
      and orders.deleted_at is null
      and orders.status = any(p_statuses)
      and coalesce(
        orders.business_date,
        (orders.created_at at time zone 'Asia/Taipei')::date
      ) between p_business_date_from and p_business_date_to
  ),
  report_lines as (
    select
      order_items.id,
      coalesce(
        order_items.section_id_snapshot::text,
        menu_sections.id::text,
        'uncategorized'
      ) as section_key,
      coalesce(
        nullif(trim(order_items.section_title_snapshot), ''),
        nullif(trim(menu_sections.title), ''),
        '未分類'
      ) as section_title,
      coalesce(
        order_items.section_sort_order_snapshot,
        menu_sections.sort_order,
        2147483647
      ) as section_sort_order,
      coalesce(
        order_items.menu_item_id::text,
        order_items.item_name_snapshot
      ) as item_key,
      order_items.item_name_snapshot as item_name,
      coalesce(
        order_items.item_sort_order_snapshot,
        menu_items.sort_order,
        order_items.sort_order,
        2147483647
      ) as item_sort_order,
      order_items.quantity,
      coalesce(
        order_items.line_total_amount_snapshot::bigint,
        case
          when order_items.price_amount_snapshot is not null then
            (
              order_items.price_amount_snapshot +
              coalesce(order_items.options_amount_snapshot, 0)
            )::bigint * order_items.quantity
          else null
        end
      ) as line_amount
    from filtered_orders
    join public.order_items
      on order_items.order_id = filtered_orders.id
    left join public.menu_items
      on menu_items.id = order_items.menu_item_id
    left join public.menu_sections
      on menu_sections.id = menu_items.section_id
  ),
  item_totals as (
    select
      section_key,
      section_title,
      min(section_sort_order) as section_sort_order,
      item_key,
      item_name,
      min(item_sort_order) as item_sort_order,
      sum(quantity)::integer as quantity,
      sum(coalesce(line_amount, 0))::bigint as subtotal
    from report_lines
    group by
      section_key,
      section_title,
      item_key,
      item_name
  ),
  section_totals as (
    select
      section_key,
      section_title,
      min(section_sort_order) as sort_order,
      sum(quantity)::integer as quantity,
      sum(subtotal)::bigint as subtotal
    from item_totals
    group by section_key, section_title
  )
  select
    (select count(*)::integer from filtered_orders),
    coalesce((select sum(quantity)::integer from report_lines), 0),
    coalesce((select sum(coalesce(line_amount, 0))::bigint from report_lines), 0),
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'section_key', section_totals.section_key,
          'section_title', section_totals.section_title,
          'sort_order', section_totals.sort_order,
          'quantity', section_totals.quantity,
          'subtotal', section_totals.subtotal,
          'items', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'item_key', item_totals.item_key,
                'item_name', item_totals.item_name,
                'quantity', item_totals.quantity,
                'subtotal', item_totals.subtotal
              )
              order by
                item_totals.item_sort_order,
                item_totals.item_name
            )
            from item_totals
            where item_totals.section_key = section_totals.section_key
              and item_totals.section_title = section_totals.section_title
          ), '[]'::jsonb)
        )
        order by section_totals.sort_order, section_totals.section_title
      )
      from section_totals
    ), '[]'::jsonb),
    (select count(*)::integer from report_lines where line_amount is null)
  into
    order_count_value,
    quantity_value,
    grand_total_value,
    sections_value,
    unpriced_count;

  if unpriced_count > 0 then
    warnings_value := jsonb_build_array(
      format(
        '%s 筆品項明細缺少可計算金額，報表以 0 計入。',
        unpriced_count
      )
    );
  end if;

  return jsonb_build_object(
    'shop', jsonb_build_object(
      'key', p_shop_key,
      'title', shop_title_value
    ),
    'date_range', jsonb_build_object(
      'from', p_business_date_from,
      'to', p_business_date_to
    ),
    'statuses', to_jsonb(p_statuses),
    'generated_at', now(),
    'order_count', order_count_value,
    'quantity', quantity_value,
    'grand_total', grand_total_value,
    'sections', sections_value,
    'warnings', warnings_value
  );
end;
$$;

revoke all on function public.get_order_report_default_business_date(text)
  from public;
revoke all on function public.get_order_sales_report(
  text,
  date,
  date,
  text[]
) from public;

grant execute on function public.get_order_report_default_business_date(text)
  to authenticated;
grant execute on function public.get_order_sales_report(
  text,
  date,
  date,
  text[]
) to authenticated;
