-- Phase 5 canonical gameplay migration.
-- This file intentionally does not rewrite prior hotfix migrations. It replaces
-- the final gameplay functions with explicit definitions and removes direct API
-- access to internal authoritative game_states.state.

revoke all on public.game_states from anon, authenticated;
revoke select on public.game_states from authenticated;

drop policy if exists "game_states_member_read" on public.game_states;
drop policy if exists "game_states_no_direct_api_read" on public.game_states;
create policy "game_states_no_direct_api_read" on public.game_states
for select to authenticated
using (false);

create or replace function public.game_minimum_field_cards(p_player_count integer)
returns integer
language sql
immutable
strict
set search_path = ''
as $$
  select case p_player_count
    when 2 then 4
    when 3 then 5
    when 4 then 6
    else null
  end;
$$;

create or replace function public.game_state_snapshot(p_room_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  game_record public.game_states;
  self_player_id uuid;
  raw_state jsonb;
  public_state jsonb;
  public_players jsonb;
  public_choices jsonb := '{}'::jsonb;
  game_phase text;
begin
  if not public.is_game_room_member(p_room_id) then
    return null;
  end if;

  select game.* into game_record
  from public.game_states as game
  where game.room_id = p_room_id;

  if game_record.room_id is null then
    return null;
  end if;

  select player.id into self_player_id
  from public.game_players as player
  where player.room_id = p_room_id
    and player.user_id = auth.uid()
    and player.left_at is null;

  if self_player_id is null then
    return null;
  end if;

  raw_state := game_record.state;
  game_phase := raw_state ->> 'phase';

  if game_phase = 'selecting-designation'
    and raw_state -> 'designationChoices' ? self_player_id::text
  then
    public_choices := jsonb_build_object(
      self_player_id::text,
      raw_state -> 'designationChoices' -> self_player_id::text
    );
  end if;

  select coalesce(jsonb_agg(
    case
      when game_phase = 'selecting-designation'
        and player.value ->> 'id' <> self_player_id::text
      then
        (player.value - 'designatedStaffId')
        || jsonb_build_object(
          'designatedStaffId', null,
          'hasDesignatedStaff', (player.value -> 'designatedStaffId') <> 'null'::jsonb
        )
      else
        player.value
        || jsonb_build_object(
          'hasDesignatedStaff', (player.value -> 'designatedStaffId') <> 'null'::jsonb
        )
    end
    order by player.ordinality
  ), '[]'::jsonb)
  into public_players
  from jsonb_array_elements(raw_state -> 'players') with ordinality as player(value, ordinality);

  public_state := raw_state - 'deck';
  public_state := jsonb_set(
    public_state,
    '{deckCount}',
    to_jsonb(jsonb_array_length(coalesce(raw_state -> 'deck', '[]'::jsonb))),
    true
  );
  public_state := jsonb_set(public_state, '{players}', public_players, true);
  public_state := jsonb_set(public_state, '{designationChoices}', public_choices, true);

  return jsonb_build_object(
    'room_id', game_record.room_id,
    'version', game_record.version,
    'state', public_state,
    'started_at', game_record.started_at,
    'updated_at', game_record.updated_at,
    'finished_at', game_record.finished_at
  );
end;
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
  game_seed text := gen_random_uuid()::text;
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
  where player.room_id = p_room_id
    and player.user_id = auth.uid()
    and player.left_at is null;

  if caller_player.id is null then
    raise exception using errcode = '42501', message = 'game-not-started: active room membership required';
  end if;

  select count(*) into player_count
  from public.game_players as player
  where player.room_id = p_room_id
    and player.left_at is null;

  if player_count not between 2 and 4 then
    raise exception using errcode = 'P0001', message = 'insufficient-players';
  end if;

  if exists (
    select 1
    from public.game_players
    where room_id = p_room_id
      and left_at is null
      and not is_ready
  ) then
    raise exception using errcode = 'P0001', message = 'players-not-ready';
  end if;

  select count(*) into card_count from public.get_active_game_staff_cards();
  turns_per_player := least(
    6,
    floor((card_count - 6 - player_count)::numeric / player_count)::integer
  );
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
    order by md5(game_seed || ':deck:' || card.staff_id::text)
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
  where player.room_id = p_room_id
    and player.left_at is null;

  for player_record in
    select player.id, player.seat_no
    from public.game_players as player
    where player.room_id = p_room_id
      and player.left_at is null
    order by player.seat_no
  loop
    select jsonb_agg(candidate.staff_id order by candidate.position)
    into candidate_ids
    from (
      select ordered.staff_id, row_number() over () as position
      from (
        select card.staff_id
        from public.get_active_game_staff_cards() as card
        order by md5(game_seed || ':designation:' || card.staff_id::text)
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
  order by md5(game_seed || ':monthly:' || candidate.month_no::text)
  limit 1;

  initial_state := jsonb_build_object(
    'schemaVersion', 1,
    'gameSeed', game_seed,
    'activeCards', cards,
    'players', players,
    'designationChoices', choices,
    'monthlyThemeMonth', monthly_theme,
    'deck', cards,
    'field', '[]'::jsonb,
    'publicSelection', '[]'::jsonb,
    'currentPlayerIndex', floor(random() * player_count)::integer,
    'selectedPublicCardId', null,
    'matchingFieldCardIds', '[]'::jsonb,
    'turnsPerPlayer', turns_per_player,
    'turnTimerEnabled', room_record.turn_timer_enabled,
    'turnTimerSeconds', room_record.turn_timer_seconds,
    'turnStartedAt', null,
    'completedTurns', '{}'::jsonb,
    'phase', 'selecting-designation',
    'scores', '[]'::jsonb,
    'winnerPlayerIds', '[]'::jsonb,
    'actionLog', '[]'::jsonb
  );

  insert into public.game_states (room_id, version, state)
  values (p_room_id, 0, initial_state);

  update public.game_rooms
  set status = 'selecting',
      last_activity_at = clock_timestamp(),
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
  next_state jsonb;
  players jsonb;
  actor_index integer;
  card_id text := btrim(coalesce(p_payload ->> 'cardId', ''));
  candidate_ids jsonb;
  selected_card jsonb;
  matching_ids jsonb := '[]'::jsonb;
  field_card jsonb;
  completed jsonb;
  next_index integer;
  all_finished boolean;
  refill_count integer;
  remaining_actions integer;
  field_refill_target integer;
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
  where player.room_id = p_room_id
    and player.user_id = auth.uid()
    and player.left_at is null;
  if actor.id is null or actor.left_at is not null then
    raise exception using errcode = '42501', message = 'room membership required';
  end if;
  if game_record.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'version-conflict';
  end if;

  next_state := game_record.state;
  players := next_state -> 'players';
  select ordinality - 1 into actor_index
  from jsonb_array_elements(players) with ordinality as entry(value, ordinality)
  where entry.value ->> 'id' = actor.id::text;

  if actor_index is null then
    raise exception using errcode = '42501', message = 'room membership required';
  end if;

  if p_action_type = 'choose-designation' then
    if next_state ->> 'phase' <> 'selecting-designation' then
      raise exception using errcode = 'P0001', message = 'designation-not-allowed';
    end if;
    candidate_ids := next_state -> 'designationChoices' -> actor.id::text;
    if card_id = '' or candidate_ids is null or not candidate_ids ? card_id then
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
    next_state := jsonb_set(next_state, '{players}', players);

    if not exists (
      select 1 from jsonb_array_elements(players) as player
      where player -> 'designatedStaffId' = 'null'::jsonb
    ) then
      next_state := jsonb_set(next_state, '{field}', (
        select coalesce(jsonb_agg(card.value order by card.ordinality), '[]'::jsonb)
        from jsonb_array_elements(next_state -> 'deck') with ordinality as card(value, ordinality)
        where card.ordinality between 1 and 6
      ));
      next_state := jsonb_set(next_state, '{publicSelection}', (
        select coalesce(jsonb_agg(card.value order by card.ordinality), '[]'::jsonb)
        from jsonb_array_elements(next_state -> 'deck') with ordinality as card(value, ordinality)
        where card.ordinality between 7 and 10
      ));
      next_state := jsonb_set(next_state, '{deck}', (
        select coalesce(jsonb_agg(card.value order by card.ordinality), '[]'::jsonb)
        from jsonb_array_elements(next_state -> 'deck') with ordinality as card(value, ordinality)
        where card.ordinality > 10
      ));
      completed := (
        select jsonb_object_agg(player ->> 'id', 0)
        from jsonb_array_elements(players) as player
      );
      next_state := jsonb_set(next_state, '{completedTurns}', completed);
      next_state := jsonb_set(next_state, '{phase}', '"awaiting-public"'::jsonb);
      next_state := jsonb_set(next_state, '{turnStartedAt}', to_jsonb(clock_timestamp()));
      update public.game_rooms
      set status = 'playing', last_activity_at = clock_timestamp()
      where id = p_room_id;
    end if;
  elsif p_action_type in ('select-public-card', 'select-field-match') then
    if room_record.status <> 'playing' then
      raise exception using errcode = 'P0001', message = 'game-not-started';
    end if;
    if (next_state -> 'players' -> (next_state ->> 'currentPlayerIndex')::integer ->> 'id') <> actor.id::text then
      raise exception using errcode = 'P0001', message = 'not-current-player';
    end if;

    if p_action_type = 'select-public-card' then
      if next_state ->> 'phase' not in ('awaiting-public', 'awaiting-match') then
        raise exception using errcode = 'P0001', message = 'invalid-action';
      end if;
      select card.value into selected_card
      from jsonb_array_elements(next_state -> 'publicSelection') as card(value)
      where card.value ->> 'staffId' = card_id;
      if selected_card is null then
        raise exception using errcode = 'P0001', message = 'invalid-card-zone';
      end if;
      select coalesce(jsonb_agg(card.value ->> 'staffId'), '[]'::jsonb)
      into matching_ids
      from jsonb_array_elements(next_state -> 'field') as card(value)
      where card.value ->> 'season' = selected_card ->> 'season';

      if jsonb_array_length(matching_ids) > 0 then
        next_state := jsonb_set(next_state, '{selectedPublicCardId}', to_jsonb(card_id));
        next_state := jsonb_set(next_state, '{matchingFieldCardIds}', matching_ids);
        next_state := jsonb_set(next_state, '{phase}', '"awaiting-match"'::jsonb);
      else
        next_state := jsonb_set(next_state, '{field}', (next_state -> 'field') || jsonb_build_array(selected_card));
        next_state := jsonb_set(next_state, '{publicSelection}', (
          select coalesce(jsonb_agg(card.value), '[]'::jsonb)
          from jsonb_array_elements(next_state -> 'publicSelection') as card(value)
          where card.value ->> 'staffId' <> card_id
        ));
        next_state := jsonb_set(next_state, '{actionLog}', (next_state -> 'actionLog') || jsonb_build_array(
          jsonb_build_object('playerId', actor.id, 'type', 'place', 'publicCardId', card_id, 'fieldCardId', null)
        ));
      end if;
    else
      if next_state ->> 'phase' <> 'awaiting-match'
        or not (next_state -> 'matchingFieldCardIds') ? card_id
      then
        raise exception using errcode = 'P0001', message = 'invalid-match';
      end if;
      select card.value into selected_card
      from jsonb_array_elements(next_state -> 'publicSelection') as card(value)
      where card.value ->> 'staffId' = next_state ->> 'selectedPublicCardId';
      select card.value into field_card
      from jsonb_array_elements(next_state -> 'field') as card(value)
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
      next_state := jsonb_set(next_state, '{players}', players);
      next_state := jsonb_set(next_state, '{field}', (
        select coalesce(jsonb_agg(card.value), '[]'::jsonb)
        from jsonb_array_elements(next_state -> 'field') as card(value)
        where card.value ->> 'staffId' <> card_id
      ));
      next_state := jsonb_set(next_state, '{publicSelection}', (
        select coalesce(jsonb_agg(card.value), '[]'::jsonb)
        from jsonb_array_elements(next_state -> 'publicSelection') as card(value)
        where card.value ->> 'staffId' <> next_state ->> 'selectedPublicCardId'
      ));
      next_state := jsonb_set(next_state, '{actionLog}', (next_state -> 'actionLog') || jsonb_build_array(
        jsonb_build_object(
          'playerId', actor.id, 'type', 'collect',
          'publicCardId', next_state ->> 'selectedPublicCardId', 'fieldCardId', card_id
        )
      ));
    end if;

    if p_action_type = 'select-field-match' or jsonb_array_length(matching_ids) = 0 then
      completed := jsonb_set(
        next_state -> 'completedTurns',
        array[actor.id::text],
        to_jsonb(coalesce((next_state -> 'completedTurns' ->> actor.id::text)::integer, 0) + 1)
      );
      next_state := jsonb_set(next_state, '{completedTurns}', completed);

      refill_count := least(
        4 - jsonb_array_length(next_state -> 'publicSelection'),
        jsonb_array_length(next_state -> 'deck')
      );
      if refill_count > 0 then
        next_state := jsonb_set(next_state, '{publicSelection}', (next_state -> 'publicSelection') || (
          select jsonb_agg(card.value order by card.ordinality)
          from jsonb_array_elements(next_state -> 'deck') with ordinality as card(value, ordinality)
          where card.ordinality <= refill_count
        ));
        next_state := jsonb_set(next_state, '{deck}', (
          select coalesce(jsonb_agg(card.value order by card.ordinality), '[]'::jsonb)
          from jsonb_array_elements(next_state -> 'deck') with ordinality as card(value, ordinality)
          where card.ordinality > refill_count
        ));
      end if;

      field_refill_target :=
        public.game_minimum_field_cards(jsonb_array_length(next_state -> 'players'));
      loop
        select coalesce(
          sum(greatest(
            0,
            (next_state ->> 'turnsPerPlayer')::integer
              - coalesce((completed ->> (player ->> 'id'))::integer, 0)
          )),
          0
        )
        into remaining_actions
        from jsonb_array_elements(next_state -> 'players') as player;

        exit when jsonb_array_length(next_state -> 'field') >= field_refill_target;
        exit when jsonb_array_length(next_state -> 'deck') = 0;
        exit when
          jsonb_array_length(next_state -> 'deck') - 1
            + jsonb_array_length(next_state -> 'publicSelection')
          < remaining_actions + 3;

        next_state := jsonb_set(next_state, '{field}', (next_state -> 'field') || (
          select jsonb_agg(card.value order by card.ordinality)
          from jsonb_array_elements(next_state -> 'deck') with ordinality as card(value, ordinality)
          where card.ordinality = 1
        ));
        next_state := jsonb_set(next_state, '{deck}', (
          select coalesce(jsonb_agg(card.value order by card.ordinality), '[]'::jsonb)
          from jsonb_array_elements(next_state -> 'deck') with ordinality as card(value, ordinality)
          where card.ordinality > 1
        ));
      end loop;

      select bool_and(
        coalesce((completed ->> (player ->> 'id'))::integer, 0)
          >= (next_state ->> 'turnsPerPlayer')::integer
      )
      into all_finished
      from jsonb_array_elements(next_state -> 'players') as player;

      next_state := jsonb_set(next_state, '{selectedPublicCardId}', 'null'::jsonb);
      next_state := jsonb_set(next_state, '{matchingFieldCardIds}', '[]'::jsonb);
      if all_finished then
        for actor_index in 0..jsonb_array_length(next_state -> 'players') - 1 loop
          collected := next_state -> 'players' -> actor_index -> 'collectedCards';
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
            where card ->> 'staffId' = next_state -> 'players' -> actor_index ->> 'designatedStaffId'
          ) then 2 else 0 end into designation_bonus;
          select count(*) into monthly_bonus
          from jsonb_array_elements(collected) as card
          where (card ->> 'monthNo')::integer = (next_state ->> 'monthlyThemeMonth')::integer;
          total_score := base_score + four_bonus + season_bonus + mark_bonus
            + designation_bonus + monthly_bonus;
          score_row := jsonb_build_object(
            'playerId', next_state -> 'players' -> actor_index ->> 'id',
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
        next_state := jsonb_set(next_state, '{scores}', score_rows);
        next_state := jsonb_set(next_state, '{winnerPlayerIds}', winner_ids);
        next_state := jsonb_set(next_state, '{phase}', '"finished"'::jsonb);
      else
        if jsonb_array_length(next_state -> 'publicSelection') = 0
          and jsonb_array_length(next_state -> 'deck') = 0
        then
          raise exception using errcode = 'P0001', message = 'state-invariant-violation';
        end if;

        next_index := (next_state ->> 'currentPlayerIndex')::integer;
        loop
          next_index := (next_index + 1) % jsonb_array_length(next_state -> 'players');
          exit when coalesce(
            (completed ->> (next_state -> 'players' -> next_index ->> 'id'))::integer, 0
          ) < (next_state ->> 'turnsPerPlayer')::integer;
        end loop;
        next_state := jsonb_set(next_state, '{currentPlayerIndex}', to_jsonb(next_index));
        next_state := jsonb_set(next_state, '{phase}', '"awaiting-public"'::jsonb);
        next_state := jsonb_set(next_state, '{turnStartedAt}', to_jsonb(clock_timestamp()));
      end if;
    end if;
  else
    raise exception using errcode = 'P0001', message = 'invalid-action';
  end if;

  result_version := game_record.version + 1;
  update public.game_states
  set version = result_version,
      state = next_state,
      finished_at = case
        when next_state ->> 'phase' = 'finished' then now()
        else game_states.finished_at
      end
  where room_id = p_room_id;

  insert into public.game_actions (
    action_id, room_id, player_id, expected_version,
    action_type, payload, result_version
  ) values (
    p_action_id, p_room_id, actor.id, p_expected_version,
    p_action_type, p_payload, result_version
  );

  update public.game_rooms
  set status = case
        when next_state ->> 'phase' = 'finished' then 'finished'
        else game_rooms.status
      end,
      last_activity_at = clock_timestamp()
  where id = p_room_id;

  return public.game_state_snapshot(p_room_id);
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

  return public.game_room_snapshot(p_room_id);
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
  set is_ready = false,
      last_seen_at = now(),
      left_at = null
  where room_id = p_room_id;

  update public.game_rooms
  set status = 'waiting',
      last_activity_at = clock_timestamp(),
      expires_at = now() + interval '6 hours'
  where id = p_room_id;

  return public.game_room_snapshot(p_room_id);
end;
$$;

revoke all on function public.game_minimum_field_cards(integer) from public;
grant execute on function public.game_minimum_field_cards(integer) to authenticated;
revoke all on function public.game_state_snapshot(uuid) from public;
grant execute on function public.game_state_snapshot(uuid) to authenticated;
revoke all on function public.start_game_room(uuid) from public;
grant execute on function public.start_game_room(uuid) to authenticated;
revoke all on function public.apply_game_action(uuid, uuid, bigint, text, jsonb) from public;
grant execute on function public.apply_game_action(uuid, uuid, bigint, text, jsonb) to authenticated;
revoke all on function public.heartbeat_game_room(uuid) from public;
grant execute on function public.heartbeat_game_room(uuid) to authenticated;
revoke all on function public.reset_finished_game_room(uuid) from public;
grant execute on function public.reset_finished_game_room(uuid) to authenticated;

comment on function public.game_state_snapshot(uuid)
is 'Returns a member-scoped public game snapshot: deckCount only, own designation choices only, hidden designations until the designation phase ends.';

comment on function public.start_game_room(uuid)
is 'Canonical Phase 5 server-authoritative game start function with active-player checks, per-game seed, timer settings, and hidden staff exclusion via get_active_game_staff_cards().';

comment on function public.apply_game_action(uuid, uuid, bigint, text, jsonb)
is 'Canonical Phase 5 authoritative action function with public-card priority refill, field target refill guard, idempotent action ids, version checks, and invariant violation on no-public/no-deck before all turns complete.';

comment on function public.heartbeat_game_room(uuid)
is 'Updates only the active player heartbeat; clients debounce Realtime reloads and room rows are not touched for routine heartbeat traffic.';
