begin;

create extension if not exists pgtap with schema extensions;
select plan(1);

select function_returns(
  'public',
  'get_current_game_room',
  array[]::text[],
  'jsonb',
  'Current-room RPC remains available after removing the read-side heartbeat'
);

select * from finish();
rollback;
