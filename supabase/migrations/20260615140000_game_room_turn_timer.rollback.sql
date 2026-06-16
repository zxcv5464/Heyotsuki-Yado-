drop function if exists public.update_game_room_settings(uuid, boolean, smallint);

-- Restore the prior function bodies by re-applying the Phase 4 migrations
-- through 20260615135000, then remove the room columns:
--
--   20260615130000_server_authoritative_gameplay.sql
--   20260615131000_fix_game_action_state_ambiguity.sql
--   20260615132000_preserve_game_history_on_leave.sql
--   20260615133000_reset_finished_game_room.sql
--   20260615134000_explicit_game_exit_and_auto_close.sql
--   20260615135000_randomize_replayed_games_and_public_reselect.sql

alter table public.game_rooms
  drop constraint if exists game_rooms_turn_timer_seconds_check,
  drop column if exists turn_timer_seconds,
  drop column if exists turn_timer_enabled;
