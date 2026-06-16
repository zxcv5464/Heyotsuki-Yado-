-- Restore the prior function bodies by re-applying:
-- 1. 20260615130000_server_authoritative_gameplay.sql
-- 2. 20260615135000_randomize_replayed_games_and_public_reselect.sql
-- 3. 20260615140000_game_room_turn_timer.sql
-- 4. 20260615141000_harden_active_room_identity.sql
--
-- Then remove the helper:
drop function if exists public.game_minimum_field_cards(integer);
