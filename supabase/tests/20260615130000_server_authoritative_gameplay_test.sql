begin;
select plan(10);

select has_table('public', 'game_states', 'game_states exists');
select has_table('public', 'game_actions', 'game_actions exists');
select has_pk('public', 'game_states', 'game_states has a primary key');
select has_pk('public', 'game_actions', 'game_actions has a primary key');
select has_index('public', 'game_actions', 'game_actions_room_created_idx',
  'game actions have a room timeline index');
select has_function('public', 'start_game_room', array['uuid'],
  'start_game_room exists');
select has_function('public', 'apply_game_action',
  array['uuid', 'uuid', 'bigint', 'text', 'jsonb'],
  'apply_game_action exists');
select has_function('public', 'game_state_snapshot', array['uuid'],
  'game_state_snapshot exists');
select has_function('public', 'abort_game_room', array['uuid'],
  'abort_game_room exists');
select policies_are(
  'public', 'game_states', array['game_states_member_read'],
  'only room members can read game state'
);

select * from finish();
rollback;
