alter table public.game_rooms
  add column if not exists turn_timer_enabled boolean not null default true,
  add column if not exists turn_timer_seconds smallint not null default 30;

alter table public.game_rooms
  drop constraint if exists game_rooms_turn_timer_seconds_check;
alter table public.game_rooms
  add constraint game_rooms_turn_timer_seconds_check
  check (turn_timer_seconds between 10 and 120);

do $$
declare
  function_sql text;
  updated_sql text;
begin
  select pg_get_functiondef('public.game_room_snapshot(uuid)'::regprocedure)
  into function_sql;

  if function_sql is null then
    raise exception 'game_room_snapshot(uuid) does not exist.';
  end if;

  if position('turn_timer_enabled' in function_sql) = 0 then
    updated_sql := replace(
      function_sql,
      $replace$'max_players', room.max_players,$replace$,
      $replace$'max_players', room.max_players,
        'turn_timer_enabled', room.turn_timer_enabled,
        'turn_timer_seconds', room.turn_timer_seconds,$replace$
    );

    if updated_sql = function_sql then
      raise exception 'game_room_snapshot timer hotfix did not match expected function body.';
    end if;

    execute updated_sql;
  end if;
end
$$;

create or replace function public.update_game_room_settings(
  p_room_id uuid,
  p_turn_timer_enabled boolean,
  p_turn_timer_seconds smallint
)
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
  if p_turn_timer_seconds not between 10 and 120 then
    raise exception using errcode = '22023', message = 'Turn timer must be between 10 and 120 seconds.';
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
  if room_record.status <> 'waiting' then
    raise exception using errcode = 'P0001', message = 'Room settings can only be changed while waiting.';
  end if;

  update public.game_rooms
  set turn_timer_enabled = p_turn_timer_enabled,
      turn_timer_seconds = p_turn_timer_seconds,
      last_activity_at = clock_timestamp(),
      expires_at = now() + interval '6 hours'
  where id = p_room_id;

  return public.game_room_snapshot(p_room_id);
end;
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

  if position($replace$'turnTimerEnabled'$replace$ in function_sql) = 0 then
    updated_sql := replace(
      function_sql,
      $replace$'turnsPerPlayer', turns_per_player,$replace$,
      $replace$'turnsPerPlayer', turns_per_player,
    'turnTimerEnabled', room_record.turn_timer_enabled,
    'turnTimerSeconds', room_record.turn_timer_seconds,
    'turnStartedAt', null,$replace$
    );

    if updated_sql = function_sql then
      raise exception 'start_game_room timer hotfix did not match expected function body.';
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

  if position($replace$'{turnStartedAt}'$replace$ in function_sql) = 0 then
    updated_sql := replace(
      function_sql,
      $replace$state := jsonb_set(state, '{phase}', '"awaiting-public"'::jsonb);$replace$,
      $replace$state := jsonb_set(state, '{phase}', '"awaiting-public"'::jsonb);
      state := jsonb_set(state, '{turnStartedAt}', to_jsonb(clock_timestamp()));$replace$
    );

    if updated_sql = function_sql then
      raise exception 'apply_game_action turn timer hotfix did not match expected function body.';
    end if;

    execute updated_sql;
  end if;
end
$$;

revoke all on function public.update_game_room_settings(uuid, boolean, smallint)
  from public;
grant execute on function public.update_game_room_settings(uuid, boolean, smallint)
  to authenticated;

comment on function public.update_game_room_settings(uuid, boolean, smallint)
is 'Allows only the room host to configure the optional 10-120 second turn timer while the room is waiting.';
