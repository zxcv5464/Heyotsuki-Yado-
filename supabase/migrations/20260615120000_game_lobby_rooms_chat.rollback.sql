-- Removes only Phase 3 lobby/chat objects. Apply only after stopping the game client.

drop function if exists public.send_game_message(uuid, text);
drop function if exists public.leave_game_room(uuid);
drop function if exists public.heartbeat_game_room(uuid);
drop function if exists public.set_game_player_ready(uuid, boolean);
drop function if exists public.get_current_game_room();
drop function if exists public.join_game_room(text, text);
drop function if exists public.create_game_room(text, smallint);
drop function if exists public.game_room_snapshot(uuid);
drop function if exists public.is_game_room_member(uuid, uuid);

drop trigger if exists game_rooms_set_updated_at on public.game_rooms;
drop table if exists public.game_messages;
drop table if exists public.game_players;
drop table if exists public.game_rooms;
