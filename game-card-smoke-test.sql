-- Run after 20260615090000_game_staff_card_settings.sql.
-- Use a disposable Supabase project or wrap data-changing checks in a
-- transaction and roll them back.

-- 1. Month labels and fixed, evenly distributed seasons.
select *
from public.get_game_month_catalog()
order by month_no;

-- Expected:
-- spring 1-3, summer 4-6, autumn 7-9, winter 10-12.

-- 2. Settings distribution, including disabled and hidden staff.
select
  settings.month_no,
  settings.mark,
  settings.is_game_enabled,
  count(*) as card_count
from public.game_staff_card_settings as settings
group by settings.month_no, settings.mark, settings.is_game_enabled
order by settings.month_no, settings.mark, settings.is_game_enabled desc;

-- 3. Active RPC must return only visible, enabled, configured cards with an
-- effective image. card_image_url must take precedence over staff image_url.
select *
from public.get_active_game_staff_cards();

-- 4. Find rows that must never be returned by the active RPC.
select
  staff.id,
  staff.name,
  staff.is_visible,
  settings.is_game_enabled,
  staff.image_url,
  settings.card_image_url
from public.staff_members as staff
left join public.game_staff_card_settings as settings
  on settings.staff_id = staff.id
where staff.is_visible is distinct from true
   or settings.staff_id is null
   or settings.is_game_enabled is distinct from true
   or coalesce(
     nullif(btrim(settings.card_image_url), ''),
     nullif(btrim(staff.image_url), '')
   ) is null
order by staff.sort_order, staff.id;

-- Verify none of the IDs above occur below.
select staff_id
from public.get_active_game_staff_cards()
order by staff_id;

-- 5. In Dashboard SQL Editor, or as an owner/admin browser session, run twice.
-- Dashboard SQL Editor uses a trusted postgres/supabase_admin database role.
-- The second call must return zero rows and existing settings must remain
-- unchanged.
select * from public.auto_assign_unset_game_staff_cards();
select * from public.auto_assign_unset_game_staff_cards();

-- 6. Permission checks to perform with the API:
-- anon:
--   - get_active_game_staff_cards succeeds.
--   - direct select from game_staff_card_settings is denied.
-- authenticated staff:
--   - direct reads/writes and auto assignment are denied.
-- authenticated owner/admin:
--   - direct CRUD and auto assignment succeed.
-- Dashboard SQL Editor / service_role:
--   - auto assignment succeeds for deployment and maintenance.
