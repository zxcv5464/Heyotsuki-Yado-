drop index if exists public.game_players_room_active_idx;
drop trigger if exists protect_game_player_history_before_delete
  on public.game_players;
drop function if exists public.protect_game_player_history();
alter table public.game_players drop column if exists left_at;

-- Reapply 20260615130000 and 20260615132000 to restore the previous RPCs,
-- including abort_game_room.
