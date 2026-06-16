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
      and player.left_at is null
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
            and host_player.left_at is null
        ),
        'status', room.status,
        'max_players', room.max_players,
        'turn_timer_enabled', room.turn_timer_enabled,
        'turn_timer_seconds', room.turn_timer_seconds,
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
          and self_player.left_at is null
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
          and player.left_at is null
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
  order by player.last_seen_at desc, player.joined_at desc
  limit 1;

  if current_player.id is null then
    return null;
  end if;

  return public.game_room_snapshot(current_player.room_id);
end;
$$;

do $$
declare
  function_sql text;
  updated_sql text;
begin
  select pg_get_functiondef('public.join_game_room(text,text)'::regprocedure)
  into function_sql;

  if function_sql is null then
    raise exception 'join_game_room(text,text) does not exist.';
  end if;

  if position('session-already-seated' in function_sql) = 0 then
    updated_sql := replace(
      function_sql,
      $replace$if existing_player.id is not null then
    update public.game_players
    set last_seen_at = now()
    where id = existing_player.id;
    return public.game_room_snapshot(target_room.id);
  end if;$replace$,
      $replace$if existing_player.id is not null then
    if existing_player.nickname_key <> lower(normalized_nickname) then
      raise exception using
        errcode = 'P0001',
        message = 'session-already-seated:' || existing_player.nickname;
    end if;
    update public.game_players
    set last_seen_at = now(), left_at = null
    where id = existing_player.id;
    return public.game_room_snapshot(target_room.id);
  end if;$replace$
    );

    if updated_sql = function_sql then
      raise exception 'join_game_room identity hotfix did not match expected function body.';
    end if;

    execute updated_sql;
  end if;
end
$$;

do $$
declare
  function_sql text;
  updated_sql text;
begin
  select pg_get_functiondef('public.start_game_room(uuid)'::regprocedure)
  into function_sql;

  if function_sql is null then
    raise exception 'start_game_room(uuid) does not exist.';
  end if;

  if position('player.left_at is null' in function_sql) = 0 then
    updated_sql := function_sql;
    updated_sql := replace(
      updated_sql,
      'where player.room_id = p_room_id and player.user_id = auth.uid();',
      'where player.room_id = p_room_id
    and player.user_id = auth.uid()
    and player.left_at is null;'
    );
    updated_sql := replace(
      updated_sql,
      'where player.room_id = p_room_id;',
      'where player.room_id = p_room_id
    and player.left_at is null;'
    );
    updated_sql := replace(
      updated_sql,
      'where room_id = p_room_id and not is_ready',
      'where room_id = p_room_id and left_at is null and not is_ready'
    );
    updated_sql := replace(
      updated_sql,
      'where player.room_id = p_room_id
    order by player.seat_no',
      'where player.room_id = p_room_id
      and player.left_at is null
    order by player.seat_no'
    );

    if updated_sql = function_sql then
      raise exception 'start_game_room active-player hotfix did not match expected function body.';
    end if;

    execute updated_sql;
  end if;
end
$$;

do $$
declare
  function_sql text;
  updated_sql text;
begin
  select pg_get_functiondef(
    'public.apply_game_action(uuid,uuid,bigint,text,jsonb)'::regprocedure
  )
  into function_sql;

  if function_sql is null then
    raise exception 'apply_game_action(uuid,uuid,bigint,text,jsonb) does not exist.';
  end if;

  if position('actor.left_at is not null' in function_sql) = 0 then
    updated_sql := replace(
      function_sql,
      'where player.room_id = p_room_id and player.user_id = auth.uid();',
      'where player.room_id = p_room_id
    and player.user_id = auth.uid()
    and player.left_at is null;'
    );
    updated_sql := replace(
      updated_sql,
      'if actor.id is null then',
      'if actor.id is null or actor.left_at is not null then'
    );

    if updated_sql = function_sql then
      raise exception 'apply_game_action active-player hotfix did not match expected function body.';
    end if;

    execute updated_sql;
  end if;
end
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
    where room_id = p_room_id
      and user_id = auth.uid()
      and left_at is null;

    select player.user_id into next_host
    from public.game_players as player
    where player.room_id = p_room_id
      and player.left_at is null
    order by player.seat_no
    limit 1;

    if next_host is null then
      update public.game_rooms
      set status = 'closed',
          last_activity_at = clock_timestamp(),
          expires_at = now()
      where id = p_room_id;
    elsif room_record.host_user_id = auth.uid() then
      update public.game_rooms
      set host_user_id = next_host,
          last_activity_at = clock_timestamp()
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
    set status = 'closed',
        last_activity_at = clock_timestamp(),
        expires_at = now()
    where id = p_room_id;
  elsif room_record.host_user_id = auth.uid() then
    update public.game_rooms
    set host_user_id = next_host,
        last_activity_at = clock_timestamp()
    where id = p_room_id;
  else
    update public.game_rooms
    set last_activity_at = clock_timestamp()
    where id = p_room_id;
  end if;

  return true;
end;
$$;

revoke all on function public.is_game_room_member(uuid) from public;
grant execute on function public.is_game_room_member(uuid) to authenticated;
revoke all on function public.game_room_snapshot(uuid) from public;
grant execute on function public.game_room_snapshot(uuid) to authenticated;
revoke all on function public.get_current_game_room() from public;
grant execute on function public.get_current_game_room() to authenticated;
revoke all on function public.leave_game_room(uuid) from public;
grant execute on function public.leave_game_room(uuid) to authenticated;

comment on function public.game_room_snapshot(uuid)
is 'Returns only active room membership and active players; left_at rows remain historical and are excluded.';
