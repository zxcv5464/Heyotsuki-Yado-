begin;

select plan(13);

select ok(
  not has_table_privilege('authenticated', 'public.game_states', 'select'),
  'authenticated cannot select internal game_states directly'
);

select has_function(
  'public',
  'game_state_snapshot',
  array['uuid'],
  'public snapshot RPC exists'
);

select has_function(
  'public',
  'start_game_room',
  array['uuid'],
  'canonical start_game_room exists'
);

select has_function(
  'public',
  'apply_game_action',
  array['uuid', 'uuid', 'bigint', 'text', 'jsonb'],
  'canonical apply_game_action exists'
);

select is(
  public.game_minimum_field_cards(2),
  4,
  '2-player field target is 4'
);

select is(
  public.game_minimum_field_cards(3),
  5,
  '3-player field target is 5'
);

select is(
  public.game_minimum_field_cards(4),
  6,
  '4-player field target is 6'
);

select ok(
  position('public_state := raw_state - ''deck''' in pg_get_functiondef('public.game_state_snapshot(uuid)'::regprocedure)) > 0,
  'public snapshot strips deck contents'
);

select ok(
  position('deckCount' in pg_get_functiondef('public.game_state_snapshot(uuid)'::regprocedure)) > 0,
  'public snapshot exposes deckCount'
);

select ok(
  position('self_player_id::text' in pg_get_functiondef('public.game_state_snapshot(uuid)'::regprocedure)) > 0,
  'public snapshot scopes designation choices to caller'
);

select ok(
  position('remaining_actions + 3' in pg_get_functiondef('public.apply_game_action(uuid,uuid,bigint,text,jsonb)'::regprocedure)) > 0,
  'field refill preserves public-card budget'
);

select ok(
  position('state-invariant-violation' in pg_get_functiondef('public.apply_game_action(uuid,uuid,bigint,text,jsonb)'::regprocedure)) > 0,
  'no-public/no-deck before planned turns throws invariant violation'
);

select ok(
  position('update public.game_rooms' in pg_get_functiondef('public.heartbeat_game_room(uuid)'::regprocedure)) = 0,
  'routine heartbeat does not update game_rooms'
);

select * from finish();

rollback;
