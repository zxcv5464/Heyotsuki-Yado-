do $$
declare
  function_sql text;
begin
  select pg_get_functiondef(
    'public.apply_game_action(uuid,uuid,bigint,text,jsonb)'::regprocedure
  )
  into function_sql;

  if function_sql is null then
    raise exception 'apply_game_action function does not exist.';
  end if;

  if position('#variable_conflict use_variable' in function_sql) = 0 then
    function_sql := replace(
      function_sql,
      'AS $function$',
      E'AS $function$\n#variable_conflict use_variable'
    );
    execute function_sql;
  end if;
end
$$;

comment on function public.apply_game_action(uuid, uuid, bigint, text, jsonb)
  is 'Applies a server-authoritative game action transactionally. The function-local state snapshot takes precedence over the same-named table column.';
