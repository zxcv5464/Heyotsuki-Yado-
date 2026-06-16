alter table public.game_players
  add column if not exists left_at timestamptz;

create index if not exists game_players_room_active_idx
  on public.game_players (room_id, left_at);

create or replace function public.protect_game_player_history()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.game_states as game
    where game.room_id = old.room_id
  ) or exists (
    select 1
    from public.game_actions as action
    where action.player_id = old.id
  ) then
    return null;
  end if;

  return old;
end;
$$;

drop trigger if exists protect_game_player_history_before_delete
  on public.game_players;
create trigger protect_game_player_history_before_delete
before delete on public.game_players
for each row execute function public.protect_game_player_history();

create or replace function public.get_current_game_room()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_player public.game_players;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;

  select player.* into current_player
  from public.game_players as player
  join public.game_rooms as room on room.id = player.room_id
  where player.user_id = auth.uid()
    and player.left_at is null
    and (
      (
        room.status = 'waiting'
        and player.last_seen_at >= now() - interval '10 minutes'
        and room.expires_at > now()
      )
      or room.status in ('selecting', 'playing', 'finished')
    )
  order by player.last_seen_at desc
  limit 1;

  if current_player.id is null then
    return null;
  end if;

  return public.game_room_snapshot(current_player.room_id);
end;
$$;

create or replace function public.heartbeat_game_room(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.is_game_room_member(p_room_id) then
    raise exception using errcode = '42501', message = 'Room membership required.';
  end if;

  update public.game_players
  set last_seen_at = now()
  where room_id = p_room_id
    and user_id = auth.uid()
    and left_at is null;

  if not found then
    raise exception using errcode = '42501', message = 'Player has left the room.';
  end if;

  update public.game_rooms
  set last_activity_at = clock_timestamp(),
      expires_at = now() + interval '6 hours'
  where id = p_room_id
    and status in ('waiting', 'selecting', 'playing', 'finished');

  return public.game_room_snapshot(p_room_id);
end;
$$;

create or replace function public.leave_game_room(p_room_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  room_record public.game_rooms;
  next_host uuid;
begin
  select room.* into room_record
  from public.game_rooms as room
  where room.id = p_room_id
  for update;

  if auth.uid() is null
    or room_record.id is null
    or not public.is_game_room_member(p_room_id)
  then
    raise exception using errcode = '42501', message = 'Room membership required.';
  end if;

  if room_record.status in ('selecting', 'playing', 'finished', 'closed')
    or exists (
      select 1 from public.game_states as game where game.room_id = p_room_id
    )
  then
    update public.game_players
    set left_at = coalesce(left_at, now()),
        last_seen_at = now()
    where room_id = p_room_id and user_id = auth.uid();

    if not exists (
      select 1
      from public.game_players as player
      where player.room_id = p_room_id
        and player.left_at is null
    ) then
      update public.game_rooms
      set status = 'closed',
          last_activity_at = clock_timestamp(),
          expires_at = now()
      where id = p_room_id;
    else
      update public.game_rooms
      set last_activity_at = clock_timestamp()
      where id = p_room_id;
    end if;

    return true;
  end if;

  delete from public.game_players
  where room_id = p_room_id and user_id = auth.uid();

  select player.user_id into next_host
  from public.game_players as player
  where player.room_id = p_room_id
  order by player.seat_no
  limit 1;

  if next_host is null then
    update public.game_rooms
    set status = 'closed', last_activity_at = clock_timestamp(), expires_at = now()
    where id = p_room_id;
  elsif room_record.host_user_id = auth.uid() then
    update public.game_rooms
    set host_user_id = next_host, last_activity_at = clock_timestamp()
    where id = p_room_id;
  else
    update public.game_rooms
    set last_activity_at = clock_timestamp()
    where id = p_room_id;
  end if;

  return true;
end;
$$;

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
  delete from public.game_players
  where room_id = p_room_id and left_at is not null;

  update public.game_players
  set is_ready = false, last_seen_at = now(), left_at = null
  where room_id = p_room_id;

  update public.game_rooms
  set status = 'waiting',
      last_activity_at = clock_timestamp(),
      expires_at = now() + interval '6 hours'
  where id = p_room_id;

  return public.game_room_snapshot(p_room_id);
end;
$$;

drop function if exists public.abort_game_room(uuid);

revoke all on function public.get_current_game_room() from public;
grant execute on function public.get_current_game_room() to authenticated;
revoke all on function public.heartbeat_game_room(uuid) from public;
grant execute on function public.heartbeat_game_room(uuid) to authenticated;
revoke all on function public.leave_game_room(uuid) from public;
grant execute on function public.leave_game_room(uuid) to authenticated;
revoke all on function public.reset_finished_game_room(uuid) from public;
grant execute on function public.reset_finished_game_room(uuid)
  to authenticated;
