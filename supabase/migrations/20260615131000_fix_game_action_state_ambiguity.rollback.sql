do $$
declare
  function_sql text;
begin
  select pg_get_functiondef(
    'public.apply_game_action(uuid,uuid,bigint,text,jsonb)'::regprocedure
  )
  into function_sql;

  if function_sql is not null then
    function_sql := replace(
      function_sql,
      E'#variable_conflict use_variable\n',
      ''
    );
    execute function_sql;
  end if;
end
$$;

comment on function public.apply_game_action(uuid, uuid, bigint, text, jsonb)
  is 'Applies a server-authoritative game action transactionally.';
