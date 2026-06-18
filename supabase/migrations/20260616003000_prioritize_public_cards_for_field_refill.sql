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

  if position('remaining_actions integer' in function_sql) = 0 then
    updated_sql := replace(
      function_sql,
      '  field_refill_count integer;',
      '  field_refill_count integer;
  remaining_actions integer;
  field_refill_target integer;'
    );
  else
    updated_sql := function_sql;
  end if;

  updated_sql := replace(
    updated_sql,
    '      field_refill_count := least(
        greatest(
          0,
          public.game_minimum_field_cards(jsonb_array_length(state -> ''players''))
            - jsonb_array_length(state -> ''field'')
        ),
        greatest(0, jsonb_array_length(state -> ''deck'') - 1)
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
      end if;',
    '      field_refill_target :=
        public.game_minimum_field_cards(jsonb_array_length(state -> ''players''));
      loop
        select coalesce(
          sum(greatest(
            0,
            (state ->> ''turnsPerPlayer'')::integer
              - coalesce((completed ->> (player ->> ''id''))::integer, 0)
          )),
          0
        )
        into remaining_actions
        from jsonb_array_elements(state -> ''players'') as player;

        exit when jsonb_array_length(state -> ''field'') >= field_refill_target;
        exit when jsonb_array_length(state -> ''deck'') = 0;
        exit when
          jsonb_array_length(state -> ''deck'') - 1
            + jsonb_array_length(state -> ''publicSelection'')
          < remaining_actions + 3;

        state := jsonb_set(state, ''{field}'', (state -> ''field'') || (
          select jsonb_agg(card.value order by card.ordinality)
          from jsonb_array_elements(state -> ''deck'')
            with ordinality as card(value, ordinality)
          where card.ordinality = 1
        ));
        state := jsonb_set(state, ''{deck}'', (
          select coalesce(jsonb_agg(card.value order by card.ordinality), ''[]''::jsonb)
          from jsonb_array_elements(state -> ''deck'')
            with ordinality as card(value, ordinality)
          where card.ordinality > 1
        ));
      end loop;'
  );

  updated_sql := replace(
    updated_sql,
    '      if all_finished
        or (
          jsonb_array_length(state -> ''publicSelection'') = 0
          and jsonb_array_length(state -> ''deck'') = 0
        )
      then',
    '      if all_finished then'
  );

  updated_sql := replace(
    updated_sql,
    '      else
        next_index := (state ->> ''currentPlayerIndex'')::integer;',
    '      else
        if jsonb_array_length(state -> ''publicSelection'') = 0
          and jsonb_array_length(state -> ''deck'') = 0
        then
          raise exception using errcode = ''P0001'', message = ''state-invariant-violation'';
        end if;

        next_index := (state ->> ''currentPlayerIndex'')::integer;'
  );

  if updated_sql = function_sql then
    if position('remaining_actions + 3' in function_sql) > 0
      and position('state-invariant-violation' in function_sql) > 0
    then
      return;
    end if;

    raise exception 'apply_game_action public-priority field refill hotfix did not match expected function body.';
  end if;

  if position('remaining_actions + 3' in updated_sql) = 0
    or position('state-invariant-violation' in updated_sql) = 0
  then
    raise exception 'apply_game_action public-priority field refill hotfix produced an incomplete function body.';
  end if;

  execute updated_sql;
end
$$;

comment on function public.apply_game_action(uuid, uuid, bigint, text, jsonb)
is 'Applies an authoritative action, always refilling public cards first, only topping up field cards when future public-card availability remains safe, and treating no-public/no-deck before all turns complete as an invariant violation.';
