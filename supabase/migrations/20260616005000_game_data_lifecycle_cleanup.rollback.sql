drop function if exists public.run_game_data_lifecycle_cleanup(interval, interval);
drop function if exists public.game_data_lifecycle_cleanup_dry_run(interval, interval);

-- Data deleted by run_game_data_lifecycle_cleanup cannot be restored by SQL rollback.
-- Before running cleanup in production, export or snapshot:
-- public.game_rooms, public.game_players, public.game_messages,
-- public.game_actions and public.game_states.
