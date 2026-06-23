do $relax_field_refill_public_reserve$
declare
  function_sql text;
  updated_sql text;
begin
  select pg_get_functiondef(
    'public.apply_game_action(uuid, uuid, bigint, text, jsonb)'::regprocedure
  )
  into function_sql;

  if function_sql is null then
    raise exception 'apply_game_action(uuid, uuid, bigint, text, jsonb) does not exist.';
  end if;

  updated_sql := replace(
    function_sql,
    $$        exit when
          jsonb_array_length(next_state -> 'deck') - 1
            + jsonb_array_length(next_state -> 'publicSelection')
          < remaining_actions + 3;$$,
    $$        exit when
          jsonb_array_length(next_state -> 'deck') - 1
            + jsonb_array_length(next_state -> 'publicSelection')
          < remaining_actions;$$
  );

  if updated_sql = function_sql then
    raise exception 'apply_game_action field-refill reserve hotfix did not match expected function body.';
  end if;

  execute updated_sql;
end
$relax_field_refill_public_reserve$;

comment on function public.apply_game_action(uuid, uuid, bigint, text, jsonb)
is 'Authoritative action function with public-card-first refill and field target refill. Field refill reserves enough public cards for remaining actions rather than forcing every future turn to start with four public cards.';
