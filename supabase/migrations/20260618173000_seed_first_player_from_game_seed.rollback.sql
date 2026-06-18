do $$
declare
  function_sql text;
begin
  select pg_get_functiondef('public.start_game_room(uuid)'::regprocedure)
  into function_sql;

  if function_sql is null then
    raise exception 'start_game_room(uuid) does not exist.';
  end if;

  if position('floor(random() * player_count)::integer' in function_sql) > 0 then
    return;
  end if;

  if position('public.game_seeded_index(game_seed, ''first-player'', player_count)' in function_sql) = 0 then
    raise exception 'start_game_room seeded-first-player rollback did not match expected function body.';
  end if;

  function_sql := replace(
    function_sql,
    'public.game_seeded_index(game_seed, ''first-player'', player_count)',
    'floor(random() * player_count)::integer'
  );

  execute function_sql;
end $$;

drop function if exists public.game_seeded_index(text, text, integer);

comment on function public.start_game_room(uuid)
is 'Starts a server-authoritative Hanafuda game with seed-derived deck, designation choices, and monthly theme.';
