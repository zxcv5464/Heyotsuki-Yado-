begin;
select plan(1);

select is(
  position(
    '#variable_conflict use_variable'
    in pg_get_functiondef(
      'public.apply_game_action(uuid,uuid,bigint,text,jsonb)'::regprocedure
    )
  ) > 0,
  true,
  'apply_game_action resolves state as the local game snapshot variable'
);

select * from finish();
rollback;
