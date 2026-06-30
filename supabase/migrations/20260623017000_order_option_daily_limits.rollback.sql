-- Rollback for 20260623017000_order_option_daily_limits.sql
-- Important: restore get_public_order_menu(text) and submit_order(...)
-- from the previous deployed order SQL before dropping this column, because
-- the hotfix functions reference menu_item_order_options.order_limit_quantity.

alter table public.menu_item_order_options
  drop constraint if exists menu_item_order_options_order_limit_quantity_check;

alter table public.menu_item_order_options
  drop column if exists order_limit_quantity;
