begin;
select plan(1);

select has_function('public', 'reset_finished_game_room', array['uuid'],
  'finished games can return to the waiting lobby');

select * from finish();
rollback;
