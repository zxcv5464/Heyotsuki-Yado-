-- Phase 3 created (uuid, uuid default auth.uid()), so PostgreSQL also treats it
-- as callable with one argument. Remove every dependency before dropping that
-- signature, then install the hardened auth.uid()-only helper.
drop policy if exists "game_rooms_member_read" on public.game_rooms;
drop policy if exists "game_players_member_read" on public.game_players;
drop policy if exists "game_messages_member_read" on public.game_messages;

drop function if exists public.set_game_player_ready(uuid, boolean);
drop function if exists public.heartbeat_game_room(uuid);
drop function if exists public.leave_game_room(uuid);
drop function if exists public.game_room_snapshot(uuid);

drop function if exists public.is_game_room_member(uuid);
drop function if exists public.is_game_room_member(uuid, uuid);

create or replace function public.is_game_room_member(p_room_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and exists (
    select 1
    from public.game_players as player
    where player.room_id = p_room_id
      and player.user_id = auth.uid()
  );
$$;

create or replace function public.game_room_snapshot(p_room_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when not public.is_game_room_member(p_room_id)
    then null
    else jsonb_build_object(
      'room', jsonb_build_object(
        'id', room.id,
        'room_code', room.room_code,
        'host_player_id', (
          select host_player.id
          from public.game_players as host_player
          where host_player.room_id = room.id
            and host_player.user_id = room.host_user_id
        ),
        'status', room.status,
        'max_players', room.max_players,
        'created_at', room.created_at,
        'updated_at', room.updated_at,
        'last_activity_at', room.last_activity_at,
        'expires_at', room.expires_at
      ),
      'self_player_id', (
        select self_player.id
        from public.game_players as self_player
        where self_player.room_id = room.id
          and self_player.user_id = auth.uid()
      ),
      'players', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id', player.id,
            'nickname', player.nickname,
            'seat_no', player.seat_no,
            'is_ready', player.is_ready,
            'joined_at', player.joined_at,
            'last_seen_at', player.last_seen_at
          )
          order by player.seat_no
        )
        from public.game_players as player
        where player.room_id = room.id
      ), '[]'::jsonb),
      'messages', coalesce((
        select jsonb_agg(message_row.payload order by message_row.created_at)
        from (
          select
            message.created_at,
            jsonb_build_object(
              'id', message.id,
              'player_id', message.player_id,
              'nickname', coalesce(player.nickname, '已離席玩家'),
              'body', message.body,
              'created_at', message.created_at
            ) as payload
          from public.game_messages as message
          left join public.game_players as player on player.id = message.player_id
          where message.room_id = room.id
          order by message.created_at desc
          limit 100
        ) as message_row
      ), '[]'::jsonb)
    )
  end
  from public.game_rooms as room
  where room.id = p_room_id;
$$;

create or replace function public.set_game_player_ready(
  p_room_id uuid,
  p_is_ready boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;
  if not public.is_game_room_member(p_room_id) then
    raise exception using errcode = '42501', message = 'Room membership required.';
  end if;
  if not exists (
    select 1 from public.game_rooms
    where id = p_room_id and status = 'waiting' and expires_at > now()
  ) then
    raise exception using errcode = 'P0001', message = 'Room is not open.';
  end if;

  update public.game_players
  set is_ready = p_is_ready, last_seen_at = now()
  where room_id = p_room_id and user_id = auth.uid();

  update public.game_rooms
  set last_activity_at = now(), expires_at = now() + interval '6 hours'
  where id = p_room_id;

  return public.game_room_snapshot(p_room_id);
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
  where room_id = p_room_id and user_id = auth.uid();

  update public.game_rooms
  set last_activity_at = now(), expires_at = now() + interval '6 hours'
  where id = p_room_id and status = 'waiting';

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
  current_user_id uuid := auth.uid();
  room_record public.game_rooms;
  next_host uuid;
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;

  select room.* into room_record
  from public.game_rooms as room
  where room.id = p_room_id
  for update;

  if room_record.id is null or not public.is_game_room_member(p_room_id) then
    raise exception using errcode = '42501', message = 'Room membership required.';
  end if;

  delete from public.game_players
  where room_id = p_room_id and user_id = current_user_id;

  select player.user_id into next_host
  from public.game_players as player
  where player.room_id = p_room_id
  order by player.seat_no
  limit 1;

  if next_host is null then
    update public.game_rooms
    set status = 'closed', last_activity_at = clock_timestamp(), expires_at = now()
    where id = p_room_id;
  elsif room_record.host_user_id = current_user_id then
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

drop policy if exists "game_rooms_member_read" on public.game_rooms;
create policy "game_rooms_member_read" on public.game_rooms
for select to authenticated
using (public.is_game_room_member(id));

drop policy if exists "game_players_member_read" on public.game_players;
create policy "game_players_member_read" on public.game_players
for select to authenticated
using (public.is_game_room_member(room_id));

drop policy if exists "game_messages_member_read" on public.game_messages;
create policy "game_messages_member_read" on public.game_messages
for select to authenticated
using (public.is_game_room_member(room_id));

revoke all on function public.is_game_room_member(uuid) from public;
grant execute on function public.is_game_room_member(uuid) to authenticated;
revoke all on function public.game_room_snapshot(uuid) from public;
revoke all on function public.set_game_player_ready(uuid, boolean) from public;
grant execute on function public.set_game_player_ready(uuid, boolean)
  to authenticated;
revoke all on function public.heartbeat_game_room(uuid) from public;
grant execute on function public.heartbeat_game_room(uuid)
  to authenticated;
revoke all on function public.leave_game_room(uuid) from public;
grant execute on function public.leave_game_room(uuid)
  to authenticated;

drop function if exists public.is_game_room_member(uuid, uuid);
