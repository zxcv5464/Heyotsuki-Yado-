begin;
select plan(2);

select has_function('public', 'leave_game_room', array['uuid'],
  'leave_game_room remains available');
select has_function('public', 'get_current_game_room', array[]::text[],
  'get_current_game_room remains available');

select * from finish();
rollback;
