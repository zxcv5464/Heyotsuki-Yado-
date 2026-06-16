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

  if position('card_count - 6 - player_count' in function_sql) = 0 then
    updated_sql := replace(
      function_sql,
      'floor((card_count - 6)::numeric / player_count)::integer',
      'floor((card_count - 6 - player_count)::numeric / player_count)::integer'
    );

    if updated_sql = function_sql then
      raise exception 'start_game_room field-reserve hotfix did not match expected function body.';
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

  if position('field_refill_count integer' in function_sql) = 0 then
    updated_sql := replace(
      function_sql,
      '  refill_count integer;',
      '  refill_count integer;
  field_refill_count integer;'
    );
    updated_sql := replace(
      updated_sql,
      '      select bool_and(',
      '      field_refill_count := least(
        greatest(
          0,
          public.game_minimum_field_cards(jsonb_array_length(state -> ''players''))
            - jsonb_array_length(state -> ''field'')
        ),
        jsonb_array_length(state -> ''deck'')
      );
      if field_refill_count > 0 then
        state := jsonb_set(state, ''{field}'', (state -> ''field'') || (
          select jsonb_agg(card.value order by card.ordinality)
          from jsonb_array_elements(state -> ''deck'')
            with ordinality as card(value, ordinality)
          where card.ordinality <= field_refill_count
        ));
        state := jsonb_set(state, ''{deck}'', (
          select coalesce(jsonb_agg(card.value order by card.ordinality), ''[]''::jsonb)
          from jsonb_array_elements(state -> ''deck'')
            with ordinality as card(value, ordinality)
          where card.ordinality > field_refill_count
        ));
      end if;

      select bool_and('
    );

    if updated_sql = function_sql then
      raise exception 'apply_game_action dynamic-field hotfix did not match expected function body.';
    end if;

    execute updated_sql;
  end if;
end
$$;

revoke all on function public.game_minimum_field_cards(integer) from public;
grant execute on function public.game_minimum_field_cards(integer)
  to authenticated;

comment on function public.game_minimum_field_cards(integer)
is 'Returns the dynamic field minimum: 4 cards for 2 players, 5 for 3, and 6 for 4.';

comment on function public.apply_game_action(uuid, uuid, bigint, text, jsonb)
is 'Applies an authoritative action, refilling public cards first and then the field to its player-count minimum when the deck allows.';
