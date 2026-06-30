-- Rollback for per-staff daily limits on staff-gated menu add-on options.
-- Important: restore get_public_order_menu(text) and submit_order(...)
-- to definitions that do not reference
-- menu_item_order_option_staff.order_limit_quantity before dropping the column.

alter table public.menu_item_order_option_staff
  drop constraint if exists menu_item_order_option_staff_order_limit_quantity_check;

alter table public.menu_item_order_option_staff
  drop column if exists order_limit_quantity;
