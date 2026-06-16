create or replace function public.get_current_game_room()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  current_player public.game_players;
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;

  select player.*
  into current_player
  from public.game_players as player
  join public.game_rooms as room on room.id = player.room_id
  where player.user_id = current_user_id
    and player.last_seen_at >= now() - interval '10 minutes'
    and (
      (room.status = 'waiting' and room.expires_at > now())
      or room.status = 'closed'
    )
  order by player.last_seen_at desc
  limit 1;

  if current_player.id is null then
    return null;
  end if;

  -- Reading the authoritative snapshot must not emit another Realtime event.
  -- heartbeat_game_room() remains responsible for last_seen_at updates.
  return public.game_room_snapshot(current_player.room_id);
end;
$$;

revoke all on function public.get_current_game_room() from public;
grant execute on function public.get_current_game_room() to authenticated;
