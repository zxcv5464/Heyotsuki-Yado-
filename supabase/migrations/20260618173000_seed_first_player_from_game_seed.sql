-- Derive the first player from the per-game seed instead of PostgreSQL random().
-- This keeps first-player selection random-looking across games while making a
-- specific game reproducible and easier to audit alongside deck/designation seeds.

create or replace function public.game_seeded_index(
  p_seed text,
  p_scope text,
  p_count integer
)
returns integer
language sql
immutable
strict
set search_path = ''
as $$
  select case
    when p_count <= 0 then 0
    else (
      (('x' || substr(md5(p_seed || ':' || p_scope), 1, 8))::bit(32)::bigint)
      % p_count
    )::integer
  end;
$$;

revoke all on function public.game_seeded_index(text, text, integer) from public;

do $$
declare
  function_sql text;
begin
  select pg_get_functiondef('public.start_game_room(uuid)'::regprocedure)
  into function_sql;

  if function_sql is null then
    raise exception 'start_game_room(uuid) does not exist.';
  end if;

  if position('public.game_seeded_index(game_seed, ''first-player'', player_count)' in function_sql) > 0 then
    return;
  end if;

  if position('floor(random() * player_count)::integer' in function_sql) = 0 then
    raise exception 'start_game_room seeded-first-player hotfix did not match expected function body.';
  end if;

  function_sql := replace(
    function_sql,
    'floor(random() * player_count)::integer',
    'public.game_seeded_index(game_seed, ''first-player'', player_count)'
  );

  execute function_sql;
end $$;

comment on function public.game_seeded_index(text, text, integer)
is 'Returns a deterministic zero-based index for a game seed and named randomization scope.';

comment on function public.start_game_room(uuid)
is 'Starts a server-authoritative Hanafuda game with seed-derived deck, designation choices, monthly theme, and first player.';
