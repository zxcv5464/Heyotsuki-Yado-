create or replace function public.kick_game_player(
  p_room_id uuid,
  p_player_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  room_record public.game_rooms;
  host_player public.game_players;
  target_player public.game_players;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;

  select room.* into room_record
  from public.game_rooms as room
  where room.id = p_room_id
  for update;

  if room_record.id is null then
    raise exception using errcode = 'P0002', message = 'Room not found.';
  end if;

  select player.* into host_player
  from public.game_players as player
  where player.room_id = p_room_id
    and player.user_id = auth.uid()
    and player.left_at is null
  for update;

  if host_player.id is null then
    raise exception using errcode = '42501', message = 'Room membership required.';
  end if;

  if room_record.host_user_id <> auth.uid() then
    raise exception using errcode = '42501', message = 'not-host';
  end if;

  select player.* into target_player
  from public.game_players as player
  where player.room_id = p_room_id
    and player.id = p_player_id
    and player.left_at is null
  for update;

  if target_player.id is null then
    raise exception using errcode = 'P0002', message = 'Target player not found.';
  end if;

  if target_player.id = host_player.id then
    raise exception using errcode = 'P0001', message = 'Host cannot kick self.';
  end if;

  if room_record.status = 'waiting'
    and not exists (
      select 1
      from public.game_states as game
      where game.room_id = p_room_id
    )
  then
    delete from public.game_players
    where id = target_player.id;
  else
    update public.game_players
    set left_at = coalesce(left_at, now()),
        is_ready = false,
        last_seen_at = now()
    where id = target_player.id;
  end if;

  update public.game_rooms
  set last_activity_at = clock_timestamp(),
      expires_at = case
        when status in ('waiting', 'selecting', 'playing', 'finished')
        then now() + interval '6 hours'
        else expires_at
      end
  where id = p_room_id;

  return public.game_room_snapshot(p_room_id);
end;
$$;

revoke all on function public.kick_game_player(uuid, uuid) from public;
grant execute on function public.kick_game_player(uuid, uuid) to authenticated;
