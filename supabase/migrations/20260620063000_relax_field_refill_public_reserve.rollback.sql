do $relax_field_refill_public_reserve_rollback$
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
          < remaining_actions;$$,
    $$        exit when
          jsonb_array_length(next_state -> 'deck') - 1
            + jsonb_array_length(next_state -> 'publicSelection')
          < remaining_actions + 3;$$
  );

  if updated_sql = function_sql then
    raise exception 'apply_game_action field-refill reserve rollback did not match expected function body.';
  end if;

  execute updated_sql;
end
$relax_field_refill_public_reserve_rollback$;

comment on function public.apply_game_action(uuid, uuid, bigint, text, jsonb)
is 'Canonical Phase 5 authoritative action function with public-card priority refill, field target refill guard, idempotent action ids, version checks, and invariant violation on no-public/no-deck before all turns complete.';
