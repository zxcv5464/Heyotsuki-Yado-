-- This rollback removes only Phase 1 game-card database objects.
-- It does not delete staff_members rows or Storage objects.

revoke all on function public.auto_assign_unset_game_staff_cards() from public;
drop function if exists public.auto_assign_unset_game_staff_cards();

revoke all on function public.get_active_game_staff_cards() from public;
drop function if exists public.get_active_game_staff_cards();

drop trigger if exists game_staff_card_settings_set_updated_at
  on public.game_staff_card_settings;

drop table if exists public.game_staff_card_settings;

revoke all on function public.get_game_month_catalog() from public;
drop function if exists public.get_game_month_catalog();

