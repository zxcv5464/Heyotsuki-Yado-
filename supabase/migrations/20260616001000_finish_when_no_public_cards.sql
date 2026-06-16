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

  if position('jsonb_array_length(state -> ''publicSelection'') = 0' in function_sql) = 0 then
    updated_sql := replace(
      function_sql,
      '      if all_finished then',
      '      if all_finished
        or (
          jsonb_array_length(state -> ''publicSelection'') = 0
          and jsonb_array_length(state -> ''deck'') = 0
        )
      then'
    );

    if updated_sql = function_sql then
      raise exception 'apply_game_action no-public-card finish hotfix did not match expected function body.';
    end if;

    execute updated_sql;
  end if;
end
$$;

comment on function public.apply_game_action(uuid, uuid, bigint, text, jsonb)
is 'Applies an authoritative action, ending the game when all turns are complete or no public cards can be played/refilled.';
