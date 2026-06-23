begin;
select plan(5);

select has_column('public', 'game_players', 'left_at',
  'explicit game exits are persisted');
select has_index('public', 'game_players', 'game_players_room_active_idx',
  'active players can be checked by room');
select has_function('public', 'protect_game_player_history', array[]::text[],
  'historical players are protected from stale cleanup');
select trigger_is(
  'public', 'game_players', 'protect_game_player_history_before_delete',
  'public', 'protect_game_player_history',
  'stale cleanup cannot delete referenced game players'
);
select hasnt_function('public', 'abort_game_room', array['uuid'],
  'manual game abort is removed');

select * from finish();
rollback;
