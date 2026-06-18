create or replace function public.game_data_lifecycle_cleanup_dry_run(
  p_closed_room_age interval default interval '7 days',
  p_child_row_age interval default interval '30 days'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  stale_active_rooms integer;
  closed_rooms integer;
  old_messages integer;
  old_actions integer;
  old_states integer;
begin
  if coalesce(auth.role(), '') <> 'service_role'
    and session_user not in ('postgres', 'supabase_admin')
  then
    raise exception using errcode = '42501', message = 'Game lifecycle cleanup requires a trusted server role.';
  end if;

  select count(*) into stale_active_rooms
  from public.game_rooms as room
  where room.status <> 'closed'
    and (
      room.expires_at < now()
      or room.last_activity_at < now() - interval '6 hours'
    )
    and not exists (
      select 1
      from public.game_players as player
      where player.room_id = room.id
        and player.left_at is null
        and player.last_seen_at >= now() - interval '10 minutes'
    );

  select count(*) into old_messages
  from public.game_messages as message
  where message.created_at < now() - p_child_row_age
    and not exists (
      select 1
      from public.game_rooms as room
      where room.id = message.room_id
        and room.status in ('selecting', 'playing')
    );

  select count(*) into old_actions
  from public.game_actions as action
  join public.game_rooms as room on room.id = action.room_id
  where action.created_at < now() - p_child_row_age
    and room.status in ('finished', 'closed');

  select count(*) into old_states
  from public.game_states as game
  join public.game_rooms as room on room.id = game.room_id
  where game.updated_at < now() - p_child_row_age
    and room.status in ('finished', 'closed');

  select count(*) into closed_rooms
  from public.game_rooms as room
  where room.status = 'closed'
    and room.last_activity_at < now() - p_closed_room_age;

  return jsonb_build_object(
    'staleActiveRoomsToClose', stale_active_rooms,
    'closedRoomsToDelete', closed_rooms,
    'oldMessagesToDelete', old_messages,
    'oldActionsToDelete', old_actions,
    'oldGameStatesToDelete', old_states,
    'anonymousAuthUsers', 'not-managed-by-this-rpc'
  );
end;
$$;

create or replace function public.run_game_data_lifecycle_cleanup(
  p_closed_room_age interval default interval '7 days',
  p_child_row_age interval default interval '30 days'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  stale_active_rooms integer := 0;
  closed_rooms integer := 0;
  old_messages integer := 0;
  old_actions integer := 0;
  old_states integer := 0;
  old_closed_room_children integer := 0;
begin
  if coalesce(auth.role(), '') <> 'service_role'
    and session_user not in ('postgres', 'supabase_admin')
  then
    raise exception using errcode = '42501', message = 'Game lifecycle cleanup requires a trusted server role.';
  end if;

  update public.game_rooms as room
  set status = 'closed',
      last_activity_at = clock_timestamp(),
      expires_at = now()
  where room.status <> 'closed'
    and (
      room.expires_at < now()
      or room.last_activity_at < now() - interval '6 hours'
    )
    and not exists (
      select 1
      from public.game_players as player
      where player.room_id = room.id
        and player.left_at is null
        and player.last_seen_at >= now() - interval '10 minutes'
    );
  get diagnostics stale_active_rooms = row_count;

  delete from public.game_messages as message
  where message.created_at < now() - p_child_row_age
    and not exists (
      select 1
      from public.game_rooms as room
      where room.id = message.room_id
        and room.status in ('selecting', 'playing')
    );
  get diagnostics old_messages = row_count;

  delete from public.game_actions as action
  using public.game_rooms as room
  where action.room_id = room.id
    and action.created_at < now() - p_child_row_age
    and room.status in ('finished', 'closed');
  get diagnostics old_actions = row_count;

  delete from public.game_states as game
  using public.game_rooms as room
  where game.room_id = room.id
    and game.updated_at < now() - p_child_row_age
    and room.status in ('finished', 'closed');
  get diagnostics old_states = row_count;

  delete from public.game_messages as message
  using public.game_rooms as room
  where message.room_id = room.id
    and room.status = 'closed'
    and room.last_activity_at < now() - p_closed_room_age;
  get diagnostics old_closed_room_children = row_count;
  old_messages := old_messages + old_closed_room_children;

  delete from public.game_actions as action
  using public.game_rooms as room
  where action.room_id = room.id
    and room.status = 'closed'
    and room.last_activity_at < now() - p_closed_room_age;
  get diagnostics old_closed_room_children = row_count;
  old_actions := old_actions + old_closed_room_children;

  delete from public.game_states as game
  using public.game_rooms as room
  where game.room_id = room.id
    and room.status = 'closed'
    and room.last_activity_at < now() - p_closed_room_age;
  get diagnostics old_closed_room_children = row_count;
  old_states := old_states + old_closed_room_children;

  delete from public.game_rooms as room
  where room.status = 'closed'
    and room.last_activity_at < now() - p_closed_room_age;
  get diagnostics closed_rooms = row_count;

  return jsonb_build_object(
    'staleActiveRoomsClosed', stale_active_rooms,
    'closedRoomsDeleted', closed_rooms,
    'oldMessagesDeleted', old_messages,
    'oldActionsDeleted', old_actions,
    'oldGameStatesDeleted', old_states,
    'anonymousAuthUsers', 'not-managed-by-this-rpc'
  );
end;
$$;

revoke all on function public.game_data_lifecycle_cleanup_dry_run(interval, interval) from public;
revoke all on function public.run_game_data_lifecycle_cleanup(interval, interval) from public;
grant execute on function public.game_data_lifecycle_cleanup_dry_run(interval, interval) to service_role;
grant execute on function public.run_game_data_lifecycle_cleanup(interval, interval) to service_role;

comment on function public.game_data_lifecycle_cleanup_dry_run(interval, interval)
  is 'Trusted dry-run report for game room/message/action/state lifecycle cleanup. Does not delete data.';
comment on function public.run_game_data_lifecycle_cleanup(interval, interval)
  is 'Trusted cleanup for stale game data. Anonymous auth users must be cleaned by a separate server-side Auth Admin workflow.';
