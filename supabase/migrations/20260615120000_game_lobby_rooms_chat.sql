create table if not exists public.game_rooms (
  id uuid primary key default gen_random_uuid(),
  room_code text not null unique
    check (room_code ~ '^[A-HJ-NP-Z2-9]{6}$'),
  host_user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'waiting'
    check (status in ('waiting', 'closed')),
  max_players smallint not null
    check (max_players between 2 and 4),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_activity_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '6 hours')
);

create table if not exists public.game_players (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.game_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  nickname text not null
    check (char_length(btrim(nickname)) between 1 and 20),
  nickname_key text generated always as (lower(btrim(nickname))) stored,
  seat_no smallint not null check (seat_no between 1 and 4),
  is_ready boolean not null default false,
  joined_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  unique (room_id, user_id),
  unique (room_id, seat_no),
  unique (room_id, nickname_key)
);

create table if not exists public.game_messages (
  id bigint generated always as identity primary key,
  room_id uuid not null references public.game_rooms(id) on delete cascade,
  player_id uuid references public.game_players(id) on delete set null,
  user_id uuid not null references auth.users(id) on delete cascade,
  body text not null
    check (
      char_length(btrim(body)) between 1 and 180
      and body = btrim(body)
    ),
  created_at timestamptz not null default now()
);

create index if not exists game_players_user_recent_idx
  on public.game_players (user_id, last_seen_at desc);
create index if not exists game_players_room_seen_idx
  on public.game_players (room_id, last_seen_at);
create index if not exists game_messages_room_created_idx
  on public.game_messages (room_id, created_at desc);

drop trigger if exists game_rooms_set_updated_at on public.game_rooms;
create trigger game_rooms_set_updated_at
before update on public.game_rooms
for each row execute function public.set_updated_at();

create or replace function public.is_game_room_member(
  p_room_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_user_id is not null and exists (
    select 1
    from public.game_players as player
    where player.room_id = p_room_id
      and player.user_id = p_user_id
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
    when auth.uid() is null
      or not public.is_game_room_member(p_room_id, auth.uid())
    then null
    else jsonb_build_object(
      'room', jsonb_build_object(
        'id', room.id,
        'room_code', room.room_code,
        'host_user_id', room.host_user_id,
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
            'user_id', player.user_id,
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

create or replace function public.create_game_room(
  p_nickname text,
  p_max_players smallint default 4
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  normalized_nickname text := btrim(p_nickname);
  generated_code text;
  created_room public.game_rooms;
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  existing_room_id uuid;
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;
  if char_length(normalized_nickname) not between 1 and 20 then
    raise exception using errcode = '22023', message = 'Nickname must contain 1 to 20 characters.';
  end if;
  if p_max_players not between 2 and 4 then
    raise exception using errcode = '22023', message = 'Room size must be between 2 and 4 players.';
  end if;

  delete from public.game_players
  where user_id = current_user_id
    and last_seen_at < now() - interval '10 minutes';

  select player.room_id into existing_room_id
  from public.game_players as player
  join public.game_rooms as room on room.id = player.room_id
  where player.user_id = current_user_id
    and room.status = 'waiting'
    and room.expires_at > now()
  order by player.last_seen_at desc
  limit 1;
  if existing_room_id is not null then
    return public.game_room_snapshot(existing_room_id);
  end if;

  for attempt in 1..20 loop
    generated_code := '';
    for position in 1..6 loop
      generated_code := generated_code || substr(
        alphabet,
        1 + floor(random() * char_length(alphabet))::integer,
        1
      );
    end loop;
    begin
      insert into public.game_rooms (room_code, host_user_id, max_players)
      values (generated_code, current_user_id, p_max_players)
      returning * into created_room;
      exit;
    exception when unique_violation then
      generated_code := null;
    end;
  end loop;

  if generated_code is null then
    raise exception using errcode = 'P0001', message = 'Unable to allocate a room code.';
  end if;

  insert into public.game_players (
    room_id, user_id, nickname, seat_no, is_ready
  ) values (
    created_room.id, current_user_id, normalized_nickname, 1, false
  );

  return public.game_room_snapshot(created_room.id);
end;
$$;

create or replace function public.join_game_room(
  p_room_code text,
  p_nickname text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  normalized_code text := upper(btrim(p_room_code));
  normalized_nickname text := btrim(p_nickname);
  target_room public.game_rooms;
  existing_player public.game_players;
  selected_seat smallint;
  replacement_host uuid;
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;
  if normalized_code !~ '^[A-HJ-NP-Z2-9]{6}$' then
    raise exception using errcode = '22023', message = 'Room code is invalid.';
  end if;
  if char_length(normalized_nickname) not between 1 and 20 then
    raise exception using errcode = '22023', message = 'Nickname must contain 1 to 20 characters.';
  end if;

  select room.*
  into target_room
  from public.game_rooms as room
  where room.room_code = normalized_code
  for update;

  if target_room.id is null
    or target_room.status <> 'waiting'
    or target_room.expires_at <= now()
  then
    raise exception using errcode = 'P0002', message = 'Room not found or unavailable.';
  end if;

  delete from public.game_players as stale
  where stale.room_id = target_room.id
    and stale.last_seen_at < now() - interval '10 minutes';

  if not exists (
    select 1 from public.game_players
    where room_id = target_room.id
      and user_id = target_room.host_user_id
  ) then
    select player.user_id into replacement_host
    from public.game_players as player
    where player.room_id = target_room.id
    order by player.seat_no
    limit 1;

    if replacement_host is null then
      update public.game_rooms
      set status = 'closed', last_activity_at = now(), expires_at = now()
      where id = target_room.id;
      raise exception using errcode = 'P0002', message = 'Room not found or unavailable.';
    end if;

    update public.game_rooms
    set host_user_id = replacement_host, last_activity_at = now()
    where id = target_room.id;
    target_room.host_user_id := replacement_host;
  end if;

  select player.*
  into existing_player
  from public.game_players as player
  where player.room_id = target_room.id
    and player.user_id = current_user_id;

  if existing_player.id is not null then
    update public.game_players
    set last_seen_at = now()
    where id = existing_player.id;
    return public.game_room_snapshot(target_room.id);
  end if;

  if exists (
    select 1 from public.game_players as player
    where player.room_id = target_room.id
      and player.nickname_key = lower(normalized_nickname)
  ) then
    raise exception using errcode = '23505', message = 'Nickname is already in use in this room.';
  end if;

  if (
    select count(*) from public.game_players as player
    where player.room_id = target_room.id
  ) >= target_room.max_players then
    raise exception using errcode = 'P0001', message = 'Room is full.';
  end if;

  select seat.seat_no::smallint
  into selected_seat
  from generate_series(1, target_room.max_players) as seat(seat_no)
  where not exists (
    select 1 from public.game_players as player
    where player.room_id = target_room.id
      and player.seat_no = seat.seat_no
  )
  order by seat.seat_no
  limit 1;

  insert into public.game_players (
    room_id, user_id, nickname, seat_no, is_ready
  ) values (
    target_room.id, current_user_id, normalized_nickname, selected_seat, false
  );

  update public.game_rooms
  set last_activity_at = now(), expires_at = now() + interval '6 hours'
  where id = target_room.id;

  return public.game_room_snapshot(target_room.id);
end;
$$;

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

  update public.game_players
  set last_seen_at = now()
  where id = current_player.id;

  return public.game_room_snapshot(current_player.room_id);
end;
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
  if not public.is_game_room_member(p_room_id, auth.uid()) then
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
  if auth.uid() is null
    or not public.is_game_room_member(p_room_id, auth.uid())
  then
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

  if room_record.id is null
    or not public.is_game_room_member(p_room_id, current_user_id)
  then
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
    set status = 'closed', last_activity_at = now(), expires_at = now()
    where id = p_room_id;
  elsif room_record.host_user_id = current_user_id then
    update public.game_rooms
    set host_user_id = next_host, last_activity_at = now()
    where id = p_room_id;
  end if;

  return true;
end;
$$;

create or replace function public.send_game_message(
  p_room_id uuid,
  p_body text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  normalized_body text := btrim(p_body);
  current_player public.game_players;
  inserted_message public.game_messages;
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;
  if char_length(normalized_body) not between 1 and 180 then
    raise exception using errcode = '22023', message = 'Message must contain 1 to 180 characters.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(p_room_id::text || current_user_id::text, 0)
  );

  select player.*
  into current_player
  from public.game_players as player
  join public.game_rooms as room on room.id = player.room_id
  where player.room_id = p_room_id
    and player.user_id = current_user_id
    and room.status = 'waiting'
    and room.expires_at > now();

  if current_player.id is null then
    raise exception using errcode = '42501', message = 'Open room membership required.';
  end if;
  if exists (
    select 1 from public.game_messages as message
    where message.room_id = p_room_id
      and message.user_id = current_user_id
      and message.created_at > now() - interval '2 seconds'
  ) or (
    select count(*) from public.game_messages as message
    where message.room_id = p_room_id
      and message.user_id = current_user_id
      and message.created_at > now() - interval '30 seconds'
  ) >= 5 then
    raise exception using errcode = 'P0001', message = 'Message rate limit exceeded.';
  end if;

  insert into public.game_messages (
    room_id, player_id, user_id, body
  ) values (
    p_room_id, current_player.id, current_user_id, normalized_body
  )
  returning * into inserted_message;

  update public.game_players set last_seen_at = now()
  where id = current_player.id;
  update public.game_rooms
  set last_activity_at = now(), expires_at = now() + interval '6 hours'
  where id = p_room_id;

  return jsonb_build_object(
    'id', inserted_message.id,
    'player_id', inserted_message.player_id,
    'nickname', current_player.nickname,
    'body', inserted_message.body,
    'created_at', inserted_message.created_at
  );
end;
$$;

alter table public.game_rooms enable row level security;
alter table public.game_players enable row level security;
alter table public.game_messages enable row level security;

create policy "game_rooms_member_read" on public.game_rooms
for select to authenticated
using (public.is_game_room_member(id, auth.uid()));

create policy "game_players_member_read" on public.game_players
for select to authenticated
using (public.is_game_room_member(room_id, auth.uid()));

create policy "game_messages_member_read" on public.game_messages
for select to authenticated
using (public.is_game_room_member(room_id, auth.uid()));

revoke all on public.game_rooms, public.game_players, public.game_messages
  from anon, authenticated;
grant select on public.game_rooms, public.game_players, public.game_messages
  to authenticated;

revoke all on function public.is_game_room_member(uuid, uuid) from public;
grant execute on function public.is_game_room_member(uuid, uuid) to authenticated;
revoke all on function public.game_room_snapshot(uuid) from public;
grant execute on function public.game_room_snapshot(uuid) to authenticated;
revoke all on function public.create_game_room(text, smallint) from public;
grant execute on function public.create_game_room(text, smallint) to authenticated;
revoke all on function public.join_game_room(text, text) from public;
grant execute on function public.join_game_room(text, text) to authenticated;
revoke all on function public.get_current_game_room() from public;
grant execute on function public.get_current_game_room() to authenticated;
revoke all on function public.set_game_player_ready(uuid, boolean) from public;
grant execute on function public.set_game_player_ready(uuid, boolean) to authenticated;
revoke all on function public.heartbeat_game_room(uuid) from public;
grant execute on function public.heartbeat_game_room(uuid) to authenticated;
revoke all on function public.leave_game_room(uuid) from public;
grant execute on function public.leave_game_room(uuid) to authenticated;
revoke all on function public.send_game_message(uuid, text) from public;
grant execute on function public.send_game_message(uuid, text) to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'game_rooms'
  ) then
    alter publication supabase_realtime add table public.game_rooms;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'game_players'
  ) then
    alter publication supabase_realtime add table public.game_players;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'game_messages'
  ) then
    alter publication supabase_realtime add table public.game_messages;
  end if;
end
$$;
