-- Phase 4 playtest hotfix:
-- - Replayed games in the same room must not reuse the room id as the only seed.
-- - The first player should be random per game.
-- - A player may change the selected public card before choosing a field match.

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

  if position('game_seed text' in function_sql) = 0 then
    updated_sql := function_sql;
    updated_sql := replace(
      updated_sql,
      '  monthly_theme smallint;',
      '  monthly_theme smallint;
  game_seed text := gen_random_uuid()::text;'
    );
    updated_sql := replace(
      updated_sql,
      $replace$order by md5(p_room_id::text || ':deck:' || card.staff_id::text)$replace$,
      $replace$order by md5(game_seed || ':deck:' || card.staff_id::text)$replace$
    );
    updated_sql := replace(
      updated_sql,
      $replace$order by md5(p_room_id::text || ':designation:' || card.staff_id::text)$replace$,
      $replace$order by md5(game_seed || ':designation:' || card.staff_id::text)$replace$
    );
    updated_sql := replace(
      updated_sql,
      $replace$order by md5(p_room_id::text || ':monthly:' || candidate.month_no::text)$replace$,
      $replace$order by md5(game_seed || ':monthly:' || candidate.month_no::text)$replace$
    );
    updated_sql := replace(
      updated_sql,
      $replace$'schemaVersion', 1,$replace$,
      $replace$'schemaVersion', 1,
    'gameSeed', game_seed,$replace$
    );
    updated_sql := replace(
      updated_sql,
      $replace$'currentPlayerIndex', 0,$replace$,
      $replace$'currentPlayerIndex', floor(random() * player_count)::integer,$replace$
    );

    if updated_sql = function_sql then
      raise exception 'start_game_room(uuid) hotfix did not match expected function body.';
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

  if position($replace$state ->> 'phase' not in ('awaiting-public', 'awaiting-match')$replace$ in function_sql) = 0 then
    updated_sql := replace(
      function_sql,
      $replace$state ->> 'phase' <> 'awaiting-public'$replace$,
      $replace$state ->> 'phase' not in ('awaiting-public', 'awaiting-match')$replace$
    );

    if updated_sql = function_sql then
      raise exception 'apply_game_action public-card reselect hotfix did not match expected function body.';
    end if;

    execute updated_sql;
  end if;
end
$$;

comment on function public.start_game_room(uuid)
is 'Starts a server-authoritative game with a per-game seed so replayed games in the same room receive fresh deck, designation, monthly theme, and first-player selection.';

comment on function public.apply_game_action(uuid, uuid, bigint, text, jsonb)
is 'Applies an authoritative game action; selecting a different public card is allowed before committing a field match.';
