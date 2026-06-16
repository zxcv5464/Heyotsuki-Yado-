alter table public.game_rooms
  drop constraint if exists game_rooms_status_check;
alter table public.game_rooms
  add constraint game_rooms_status_check
  check (status in ('waiting', 'selecting', 'playing', 'finished', 'closed'));

create table public.game_states (
  room_id uuid primary key references public.game_rooms(id) on delete cascade,
  version bigint not null default 0 check (version >= 0),
  state jsonb not null,
  started_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  finished_at timestamptz
);

create table public.game_actions (
  action_id uuid primary key,
  room_id uuid not null references public.game_rooms(id) on delete cascade,
  player_id uuid not null references public.game_players(id),
  expected_version bigint not null,
  action_type text not null check (
    action_type in (
      'choose-designation',
      'select-public-card',
      'select-field-match'
    )
  ),
  payload jsonb not null default '{}'::jsonb,
  result_version bigint not null,
  created_at timestamptz not null default now()
);

create index game_actions_room_created_idx
  on public.game_actions (room_id, created_at);

drop trigger if exists game_states_set_updated_at on public.game_states;
create trigger game_states_set_updated_at
before update on public.game_states
for each row execute function public.set_updated_at();

alter table public.game_states enable row level security;
alter table public.game_actions enable row level security;

create policy "game_states_member_read" on public.game_states
for select to authenticated
using (public.is_game_room_member(room_id));

revoke all on public.game_states, public.game_actions from anon, authenticated;
grant select on public.game_states to authenticated;

create or replace function public.game_state_snapshot(p_room_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when not public.is_game_room_member(p_room_id) then null
    else jsonb_build_object(
      'room_id', game.room_id,
      'version', game.version,
      'state', game.state,
      'started_at', game.started_at,
      'updated_at', game.updated_at,
      'finished_at', game.finished_at
    )
  end
  from public.game_states as game
  where game.room_id = p_room_id;
$$;

create or replace function public.start_game_room(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  room_record public.game_rooms;
  caller_player public.game_players;
  player_count integer;
  card_count integer;
  turns_per_player integer;
  cards jsonb;
  players jsonb;
  choices jsonb := '{}'::jsonb;
  player_record record;
  candidate_ids jsonb;
  monthly_theme smallint;
  initial_state jsonb;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'game-not-started: authentication required';
  end if;

  select room.* into room_record
  from public.game_rooms as room
  where room.id = p_room_id
  for update;

  if room_record.id is null or not public.is_game_room_member(p_room_id) then
    raise exception using errcode = '42501', message = 'game-not-started: room membership required';
  end if;
  if room_record.host_user_id <> auth.uid() then
    raise exception using errcode = '42501', message = 'not-host';
  end if;
  if room_record.status <> 'waiting' then
    raise exception using errcode = 'P0001', message = 'game-already-started';
  end if;

  select player.* into caller_player
  from public.game_players as player
  where player.room_id = p_room_id and player.user_id = auth.uid();

  select count(*) into player_count
  from public.game_players as player
  where player.room_id = p_room_id;
  if player_count not between 2 and 4 then
    raise exception using errcode = 'P0001', message = 'insufficient-players';
  end if;
  if exists (
    select 1 from public.game_players
    where room_id = p_room_id and not is_ready
  ) then
    raise exception using errcode = 'P0001', message = 'players-not-ready';
  end if;

  select count(*) into card_count from public.get_active_game_staff_cards();
  turns_per_player := least(6, floor((card_count - 6)::numeric / player_count)::integer);
  if turns_per_player <= 0 or card_count < player_count * 3 then
    raise exception using errcode = 'P0001', message = 'insufficient-card-pool';
  end if;

  select jsonb_agg(
    jsonb_build_object(
      'staffId', card.staff_id,
      'name', card.name,
      'imageUrl', card.image_url,
      'monthNo', card.month_no,
      'monthLabel', card.month_label,
      'season', card.season,
      'mark', card.mark,
      'cardTitle', card.card_title,
      'sortOrder', card.sort_order
    )
    order by md5(p_room_id::text || ':deck:' || card.staff_id::text)
  )
  into cards
  from public.get_active_game_staff_cards() as card
  where card.image_url ~ '^https://';

  if jsonb_array_length(coalesce(cards, '[]'::jsonb)) <> card_count then
    raise exception using errcode = 'P0001', message = 'insufficient-card-pool';
  end if;

  select jsonb_agg(
    jsonb_build_object(
      'id', player.id,
      'name', player.nickname,
      'seatNo', player.seat_no,
      'designatedStaffId', null,
      'collectedCards', '[]'::jsonb
    )
    order by player.seat_no
  )
  into players
  from public.game_players as player
  where player.room_id = p_room_id;

  for player_record in
    select player.id, player.seat_no
    from public.game_players as player
    where player.room_id = p_room_id
    order by player.seat_no
  loop
    select jsonb_agg(candidate.staff_id order by candidate.position)
    into candidate_ids
    from (
      select ordered.staff_id, row_number() over () as position
      from (
        select card.staff_id
        from public.get_active_game_staff_cards() as card
        order by md5(p_room_id::text || ':designation:' || card.staff_id::text)
        offset ((player_record.seat_no - 1) * 3)
        limit 3
      ) as ordered
    ) as candidate;
    choices := choices || jsonb_build_object(player_record.id::text, candidate_ids);
  end loop;

  select candidate.month_no into monthly_theme
  from (
    select distinct card.month_no
    from public.get_active_game_staff_cards() as card
  ) as candidate
  order by md5(p_room_id::text || ':monthly:' || candidate.month_no::text)
  limit 1;

  initial_state := jsonb_build_object(
    'schemaVersion', 1,
    'activeCards', cards,
    'players', players,
    'designationChoices', choices,
    'monthlyThemeMonth', monthly_theme,
    'deck', cards,
    'field', '[]'::jsonb,
    'publicSelection', '[]'::jsonb,
    'currentPlayerIndex', 0,
    'selectedPublicCardId', null,
    'matchingFieldCardIds', '[]'::jsonb,
    'turnsPerPlayer', turns_per_player,
    'completedTurns', '{}'::jsonb,
    'phase', 'selecting-designation',
    'scores', '[]'::jsonb,
    'winnerPlayerIds', '[]'::jsonb,
    'actionLog', '[]'::jsonb
  );

  insert into public.game_states (room_id, version, state)
  values (p_room_id, 0, initial_state);

  update public.game_rooms
  set status = 'selecting', last_activity_at = clock_timestamp(),
      expires_at = now() + interval '6 hours'
  where id = p_room_id;

  return public.game_state_snapshot(p_room_id);
end;
$$;

create or replace function public.apply_game_action(
  p_room_id uuid,
  p_action_id uuid,
  p_expected_version bigint,
  p_action_type text,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  game_record public.game_states;
  room_record public.game_rooms;
  actor public.game_players;
  prior_action public.game_actions;
  state jsonb;
  players jsonb;
  actor_index integer;
  card_id text := btrim(coalesce(p_payload ->> 'cardId', ''));
  candidate_ids jsonb;
  selected_card jsonb;
  matching_ids jsonb;
  field_card jsonb;
  completed jsonb;
  next_index integer;
  all_finished boolean;
  refill_count integer;
  score_rows jsonb := '[]'::jsonb;
  score_row jsonb;
  collected jsonb;
  season_count integer;
  mark_count integer;
  base_score integer;
  four_bonus integer;
  season_bonus integer;
  mark_bonus integer;
  designation_bonus integer;
  monthly_bonus integer;
  total_score integer;
  qualifying_seasons jsonb;
  qualifying_marks jsonb;
  best_score integer;
  winner_ids jsonb;
  result_version bigint;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'game-not-started';
  end if;
  if not public.is_game_room_member(p_room_id) then
    raise exception using errcode = '42501', message = 'room membership required';
  end if;

  select action.* into prior_action
  from public.game_actions as action
  where action.action_id = p_action_id;
  if prior_action.action_id is not null then
    if prior_action.room_id <> p_room_id then
      raise exception using errcode = 'P0001', message = 'invalid-action';
    end if;
    return public.game_state_snapshot(p_room_id);
  end if;

  select game.* into game_record
  from public.game_states as game
  where game.room_id = p_room_id
  for update;
  if game_record.room_id is null then
    raise exception using errcode = 'P0001', message = 'game-not-started';
  end if;

  select room.* into room_record
  from public.game_rooms as room
  where room.id = p_room_id;
  if room_record.status = 'closed' then
    raise exception using errcode = 'P0001', message = 'room-closed';
  end if;

  select player.* into actor
  from public.game_players as player
  where player.room_id = p_room_id and player.user_id = auth.uid();
  if actor.id is null then
    raise exception using errcode = '42501', message = 'room membership required';
  end if;
  if game_record.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'version-conflict';
  end if;

  state := game_record.state;
  players := state -> 'players';
  select ordinality - 1 into actor_index
  from jsonb_array_elements(players) with ordinality as entry(value, ordinality)
  where entry.value ->> 'id' = actor.id::text;

  if p_action_type = 'choose-designation' then
    if state ->> 'phase' <> 'selecting-designation' then
      raise exception using errcode = 'P0001', message = 'designation-not-allowed';
    end if;
    candidate_ids := state -> 'designationChoices' -> actor.id::text;
    if card_id = '' or not candidate_ids ? card_id then
      raise exception using errcode = 'P0001', message = 'designation-not-allowed';
    end if;
    if players -> actor_index ->> 'designatedStaffId' is not null then
      raise exception using errcode = 'P0001', message = 'designation-not-allowed';
    end if;
    if exists (
      select 1 from jsonb_array_elements(players) as player
      where player ->> 'designatedStaffId' = card_id
    ) then
      raise exception using errcode = 'P0001', message = 'designation-not-allowed';
    end if;

    players := jsonb_set(players, array[actor_index::text, 'designatedStaffId'], to_jsonb(card_id));
    state := jsonb_set(state, '{players}', players);

    if not exists (
      select 1 from jsonb_array_elements(players) as player
      where player -> 'designatedStaffId' = 'null'::jsonb
    ) then
      state := jsonb_set(state, '{field}', (
        select coalesce(jsonb_agg(card.value order by card.ordinality), '[]'::jsonb)
        from jsonb_array_elements(state -> 'deck') with ordinality as card(value, ordinality)
        where card.ordinality between 1 and 6
      ));
      state := jsonb_set(state, '{publicSelection}', (
        select coalesce(jsonb_agg(card.value order by card.ordinality), '[]'::jsonb)
        from jsonb_array_elements(state -> 'deck') with ordinality as card(value, ordinality)
        where card.ordinality between 7 and 10
      ));
      state := jsonb_set(state, '{deck}', (
        select coalesce(jsonb_agg(card.value order by card.ordinality), '[]'::jsonb)
        from jsonb_array_elements(state -> 'deck') with ordinality as card(value, ordinality)
        where card.ordinality > 10
      ));
      completed := (
        select jsonb_object_agg(player ->> 'id', 0)
        from jsonb_array_elements(players) as player
      );
      state := jsonb_set(state, '{completedTurns}', completed);
      state := jsonb_set(state, '{phase}', '"awaiting-public"'::jsonb);
      update public.game_rooms
      set status = 'playing', last_activity_at = clock_timestamp()
      where id = p_room_id;
    end if;
  elsif p_action_type in ('select-public-card', 'select-field-match') then
    if room_record.status <> 'playing' then
      raise exception using errcode = 'P0001', message = 'game-not-started';
    end if;
    if (state -> 'players' -> (state ->> 'currentPlayerIndex')::integer ->> 'id') <> actor.id::text then
      raise exception using errcode = 'P0001', message = 'not-current-player';
    end if;

    if p_action_type = 'select-public-card' then
      if state ->> 'phase' <> 'awaiting-public' then
        raise exception using errcode = 'P0001', message = 'invalid-action';
      end if;
      select card.value into selected_card
      from jsonb_array_elements(state -> 'publicSelection') as card(value)
      where card.value ->> 'staffId' = card_id;
      if selected_card is null then
        raise exception using errcode = 'P0001', message = 'invalid-card-zone';
      end if;
      select coalesce(jsonb_agg(card.value ->> 'staffId'), '[]'::jsonb)
      into matching_ids
      from jsonb_array_elements(state -> 'field') as card(value)
      where card.value ->> 'season' = selected_card ->> 'season';

      if jsonb_array_length(matching_ids) > 0 then
        state := jsonb_set(state, '{selectedPublicCardId}', to_jsonb(card_id));
        state := jsonb_set(state, '{matchingFieldCardIds}', matching_ids);
        state := jsonb_set(state, '{phase}', '"awaiting-match"'::jsonb);
      else
        state := jsonb_set(state, '{field}', (state -> 'field') || jsonb_build_array(selected_card));
        state := jsonb_set(state, '{publicSelection}', (
          select coalesce(jsonb_agg(card.value), '[]'::jsonb)
          from jsonb_array_elements(state -> 'publicSelection') as card(value)
          where card.value ->> 'staffId' <> card_id
        ));
        state := jsonb_set(state, '{actionLog}', (state -> 'actionLog') || jsonb_build_array(
          jsonb_build_object('playerId', actor.id, 'type', 'place', 'publicCardId', card_id, 'fieldCardId', null)
        ));
      end if;
    else
      if state ->> 'phase' <> 'awaiting-match'
        or not (state -> 'matchingFieldCardIds') ? card_id
      then
        raise exception using errcode = 'P0001', message = 'invalid-match';
      end if;
      select card.value into selected_card
      from jsonb_array_elements(state -> 'publicSelection') as card(value)
      where card.value ->> 'staffId' = state ->> 'selectedPublicCardId';
      select card.value into field_card
      from jsonb_array_elements(state -> 'field') as card(value)
      where card.value ->> 'staffId' = card_id;
      if selected_card is null or field_card is null then
        raise exception using errcode = 'P0001', message = 'invalid-card-zone';
      end if;
      collected := players -> actor_index -> 'collectedCards';
      players := jsonb_set(
        players,
        array[actor_index::text, 'collectedCards'],
        collected || jsonb_build_array(selected_card, field_card)
      );
      state := jsonb_set(state, '{players}', players);
      state := jsonb_set(state, '{field}', (
        select coalesce(jsonb_agg(card.value), '[]'::jsonb)
        from jsonb_array_elements(state -> 'field') as card(value)
        where card.value ->> 'staffId' <> card_id
      ));
      state := jsonb_set(state, '{publicSelection}', (
        select coalesce(jsonb_agg(card.value), '[]'::jsonb)
        from jsonb_array_elements(state -> 'publicSelection') as card(value)
        where card.value ->> 'staffId' <> state ->> 'selectedPublicCardId'
      ));
      state := jsonb_set(state, '{actionLog}', (state -> 'actionLog') || jsonb_build_array(
        jsonb_build_object(
          'playerId', actor.id, 'type', 'collect',
          'publicCardId', state ->> 'selectedPublicCardId', 'fieldCardId', card_id
        )
      ));
    end if;

    if p_action_type = 'select-field-match' or jsonb_array_length(matching_ids) = 0 then
      completed := jsonb_set(
        state -> 'completedTurns',
        array[actor.id::text],
        to_jsonb(coalesce((state -> 'completedTurns' ->> actor.id::text)::integer, 0) + 1)
      );
      state := jsonb_set(state, '{completedTurns}', completed);
      refill_count := least(
        4 - jsonb_array_length(state -> 'publicSelection'),
        jsonb_array_length(state -> 'deck')
      );
      if refill_count > 0 then
        state := jsonb_set(state, '{publicSelection}', (state -> 'publicSelection') || (
          select jsonb_agg(card.value order by card.ordinality)
          from jsonb_array_elements(state -> 'deck') with ordinality as card(value, ordinality)
          where card.ordinality <= refill_count
        ));
        state := jsonb_set(state, '{deck}', (
          select coalesce(jsonb_agg(card.value order by card.ordinality), '[]'::jsonb)
          from jsonb_array_elements(state -> 'deck') with ordinality as card(value, ordinality)
          where card.ordinality > refill_count
        ));
      end if;

      select bool_and(
        coalesce((completed ->> (player ->> 'id'))::integer, 0)
          >= (state ->> 'turnsPerPlayer')::integer
      )
      into all_finished
      from jsonb_array_elements(state -> 'players') as player;

      state := jsonb_set(state, '{selectedPublicCardId}', 'null'::jsonb);
      state := jsonb_set(state, '{matchingFieldCardIds}', '[]'::jsonb);
      if all_finished then
        for actor_index in 0..jsonb_array_length(state -> 'players') - 1 loop
          collected := state -> 'players' -> actor_index -> 'collectedCards';
          base_score := jsonb_array_length(collected);
          select count(*), coalesce(jsonb_agg(qualifying.season order by qualifying.season), '[]'::jsonb)
          into season_count, qualifying_seasons
          from (
            select card ->> 'season' as season
            from jsonb_array_elements(collected) as card
            group by card ->> 'season' having count(*) >= 3
          ) as qualifying;
          select count(*), coalesce(jsonb_agg(qualifying.mark order by qualifying.mark), '[]'::jsonb)
          into mark_count, qualifying_marks
          from (
            select card ->> 'mark' as mark
            from jsonb_array_elements(collected) as card
            group by card ->> 'mark' having count(*) >= 3
          ) as qualifying;
          select case when count(distinct card ->> 'season') = 4 then 4 else 0 end
          into four_bonus from jsonb_array_elements(collected) as card;
          season_bonus := season_count * 3;
          mark_bonus := mark_count * 3;
          select case when exists (
            select 1 from jsonb_array_elements(collected) as card
            where card ->> 'staffId' = state -> 'players' -> actor_index ->> 'designatedStaffId'
          ) then 2 else 0 end into designation_bonus;
          select count(*) into monthly_bonus
          from jsonb_array_elements(collected) as card
          where (card ->> 'monthNo')::integer = (state ->> 'monthlyThemeMonth')::integer;
          total_score := base_score + four_bonus + season_bonus + mark_bonus
            + designation_bonus + monthly_bonus;
          score_row := jsonb_build_object(
            'playerId', state -> 'players' -> actor_index ->> 'id',
            'baseCards', base_score,
            'fourSeasonsBonus', four_bonus,
            'qualifyingSeasons', qualifying_seasons,
            'seasonSetsBonus', season_bonus,
            'qualifyingMarks', qualifying_marks,
            'markSetsBonus', mark_bonus,
            'designatedStaffBonus', designation_bonus,
            'monthlyThemeCardCount', monthly_bonus,
            'monthlyThemeBonus', monthly_bonus,
            'total', total_score
          );
          score_rows := score_rows || jsonb_build_array(score_row);
        end loop;
        select max((score ->> 'total')::integer) into best_score
        from jsonb_array_elements(score_rows) as score;
        select jsonb_agg(score ->> 'playerId') into winner_ids
        from jsonb_array_elements(score_rows) as score
        where (score ->> 'total')::integer = best_score;
        state := jsonb_set(state, '{scores}', score_rows);
        state := jsonb_set(state, '{winnerPlayerIds}', winner_ids);
        state := jsonb_set(state, '{phase}', '"finished"'::jsonb);
      else
        next_index := (state ->> 'currentPlayerIndex')::integer;
        loop
          next_index := (next_index + 1) % jsonb_array_length(state -> 'players');
          exit when coalesce(
            (completed ->> (state -> 'players' -> next_index ->> 'id'))::integer, 0
          ) < (state ->> 'turnsPerPlayer')::integer;
        end loop;
        state := jsonb_set(state, '{currentPlayerIndex}', to_jsonb(next_index));
        state := jsonb_set(state, '{phase}', '"awaiting-public"'::jsonb);
      end if;
    end if;
  else
    raise exception using errcode = 'P0001', message = 'invalid-action';
  end if;

  result_version := game_record.version + 1;
  update public.game_states
  set version = result_version,
      state = state,
      finished_at = case when state ->> 'phase' = 'finished' then now() else finished_at end
  where room_id = p_room_id;

  insert into public.game_actions (
    action_id, room_id, player_id, expected_version,
    action_type, payload, result_version
  ) values (
    p_action_id, p_room_id, actor.id, p_expected_version,
    p_action_type, p_payload, result_version
  );

  update public.game_rooms
  set status = case when state ->> 'phase' = 'finished' then 'finished' else status end,
      last_activity_at = clock_timestamp()
  where id = p_room_id;

  return public.game_state_snapshot(p_room_id);
end;
$$;

create or replace function public.abort_game_room(p_room_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.game_rooms
    where id = p_room_id and host_user_id = auth.uid()
  ) then
    raise exception using errcode = '42501', message = 'not-host';
  end if;
  update public.game_rooms
  set status = 'closed', last_activity_at = clock_timestamp(), expires_at = now()
  where id = p_room_id and status in ('selecting', 'playing', 'finished');
  if not found then
    raise exception using errcode = 'P0001', message = 'game-not-started';
  end if;
  return true;
end;
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
    and (
      (room.status = 'waiting' and player.last_seen_at >= now() - interval '10 minutes' and room.expires_at > now())
      or room.status in ('selecting', 'playing', 'finished', 'closed')
    )
  order by player.last_seen_at desc
  limit 1;
  if current_player.id is null then return null; end if;
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
  update public.game_players set last_seen_at = now()
  where room_id = p_room_id and user_id = auth.uid();
  update public.game_rooms
  set last_activity_at = clock_timestamp(), expires_at = now() + interval '6 hours'
  where id = p_room_id and status in ('waiting', 'selecting', 'playing', 'finished');
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
  select room.* into room_record from public.game_rooms as room
  where room.id = p_room_id for update;
  if auth.uid() is null or room_record.id is null or not public.is_game_room_member(p_room_id) then
    raise exception using errcode = '42501', message = 'Room membership required.';
  end if;
  if room_record.status in ('selecting', 'playing', 'finished') then
    update public.game_players set last_seen_at = now()
    where room_id = p_room_id and user_id = auth.uid();
    update public.game_rooms set last_activity_at = clock_timestamp()
    where id = p_room_id;
    return true;
  end if;
  delete from public.game_players where room_id = p_room_id and user_id = auth.uid();
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
    update public.game_rooms set last_activity_at = clock_timestamp()
    where id = p_room_id;
  end if;
  return true;
end;
$$;

create or replace function public.send_game_message(p_room_id uuid, p_body text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_body text := btrim(p_body);
  current_player public.game_players;
  inserted_message public.game_messages;
begin
  if auth.uid() is null or char_length(normalized_body) not between 1 and 180 then
    raise exception using errcode = '22023', message = 'Message must contain 1 to 180 characters.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_room_id::text || auth.uid()::text, 0));
  select player.* into current_player
  from public.game_players as player
  join public.game_rooms as room on room.id = player.room_id
  where player.room_id = p_room_id and player.user_id = auth.uid()
    and room.status in ('waiting', 'selecting', 'playing', 'finished');
  if current_player.id is null then
    raise exception using errcode = '42501', message = 'Open room membership required.';
  end if;
  if exists (
    select 1 from public.game_messages
    where room_id = p_room_id and user_id = auth.uid()
      and created_at > now() - interval '2 seconds'
  ) or (
    select count(*) from public.game_messages
    where room_id = p_room_id and user_id = auth.uid()
      and created_at > now() - interval '30 seconds'
  ) >= 5 then
    raise exception using errcode = 'P0001', message = 'Message rate limit exceeded.';
  end if;
  insert into public.game_messages (room_id, player_id, user_id, body)
  values (p_room_id, current_player.id, auth.uid(), normalized_body)
  returning * into inserted_message;
  update public.game_rooms set last_activity_at = clock_timestamp() where id = p_room_id;
  return jsonb_build_object(
    'id', inserted_message.id, 'player_id', inserted_message.player_id,
    'nickname', current_player.nickname, 'body', inserted_message.body,
    'created_at', inserted_message.created_at
  );
end;
$$;

revoke all on function public.game_state_snapshot(uuid) from public;
revoke all on function public.start_game_room(uuid) from public;
revoke all on function public.apply_game_action(uuid, uuid, bigint, text, jsonb) from public;
revoke all on function public.abort_game_room(uuid) from public;
grant execute on function public.game_state_snapshot(uuid) to authenticated;
grant execute on function public.start_game_room(uuid) to authenticated;
grant execute on function public.apply_game_action(uuid, uuid, bigint, text, jsonb) to authenticated;
grant execute on function public.abort_game_room(uuid) to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'game_states'
  ) then
    alter publication supabase_realtime add table public.game_states;
  end if;
end
$$;
