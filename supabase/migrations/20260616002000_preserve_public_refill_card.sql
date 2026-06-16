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

  if position('jsonb_array_length(state -> ''deck'') - 1' in function_sql) = 0 then
    updated_sql := replace(
      function_sql,
      '      field_refill_count := least(
        greatest(
          0,
          public.game_minimum_field_cards(jsonb_array_length(state -> ''players''))
            - jsonb_array_length(state -> ''field'')
        ),
        jsonb_array_length(state -> ''deck'')
      );',
      '      field_refill_count := least(
        greatest(
          0,
          public.game_minimum_field_cards(jsonb_array_length(state -> ''players''))
            - jsonb_array_length(state -> ''field'')
        ),
        greatest(0, jsonb_array_length(state -> ''deck'') - 1)
      );'
    );

    if updated_sql = function_sql then
      raise exception 'apply_game_action preserve-public-refill hotfix did not match expected function body.';
    end if;

    execute updated_sql;
  end if;
end
$$;

comment on function public.apply_game_action(uuid, uuid, bigint, text, jsonb)
is 'Applies an authoritative action, refilling public cards first and preserving one deck card for a future public refill before topping up the field.';
