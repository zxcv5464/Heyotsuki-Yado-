create or replace function public.reset_finished_game_room(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  room_record public.game_rooms;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;

  select room.* into room_record
  from public.game_rooms as room
  where room.id = p_room_id
  for update;

  if room_record.id is null or not public.is_game_room_member(p_room_id) then
    raise exception using errcode = '42501', message = 'Room membership required.';
  end if;
  if room_record.host_user_id <> auth.uid() then
    raise exception using errcode = '42501', message = 'not-host';
  end if;
  if room_record.status <> 'finished' then
    raise exception using errcode = 'P0001', message = 'game-not-finished';
  end if;

  delete from public.game_actions where room_id = p_room_id;
  delete from public.game_states where room_id = p_room_id;

  update public.game_players
  set is_ready = false, last_seen_at = now()
  where room_id = p_room_id;

  update public.game_rooms
  set status = 'waiting',
      last_activity_at = clock_timestamp(),
      expires_at = now() + interval '6 hours'
  where id = p_room_id;

  return public.game_room_snapshot(p_room_id);
end;
$$;

revoke all on function public.reset_finished_game_room(uuid) from public;
grant execute on function public.reset_finished_game_room(uuid) to authenticated;

