drop trigger if exists menu_item_order_option_staff_limit_consistency_guard
  on public.menu_item_order_option_staff;
drop trigger if exists menu_item_order_options_limit_consistency_guard
  on public.menu_item_order_options;
drop trigger if exists menu_items_order_limit_consistency_guard
  on public.menu_items;

drop function if exists public.validate_menu_item_order_option_staff_limit_consistency();
drop function if exists public.validate_menu_item_order_option_limit_consistency();
drop function if exists public.validate_menu_item_order_limit_consistency();
