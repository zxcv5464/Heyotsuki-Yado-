begin;

create extension if not exists pgtap with schema extensions;
select plan(7);

select has_function(
  'public',
  'is_game_room_member',
  array['uuid'],
  'Membership helper accepts only a room id'
);
select hasnt_function(
  'public',
  'is_game_room_member',
  array['uuid', 'uuid'],
  'Arbitrary user-id membership helper was removed'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  (
    '91000000-0000-4000-8000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', null, '', now(),
    '{"provider":"anonymous","providers":["anonymous"]}', '{}', now(), now()
  ),
  (
    '91000000-0000-4000-8000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', null, '', now(),
    '{"provider":"anonymous","providers":["anonymous"]}', '{}', now(), now()
  );

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '91000000-0000-4000-8000-000000000001',
  true
);
create temp table phase31_context as
select public.create_game_room('Host', 4::smallint) as snapshot;

select ok(
  (select snapshot->'room' ? 'host_player_id' from phase31_context),
  'Snapshot returns host_player_id'
);
select ok(
  not (select snapshot->'room' ? 'host_user_id' from phase31_context),
  'Snapshot omits host auth user id'
);
select ok(
  not (
    select (snapshot->'players'->0) ? 'user_id'
    from phase31_context
  ),
  'Snapshot omits player auth user ids'
);

select set_config(
  'request.jwt.claim.sub',
  '91000000-0000-4000-8000-000000000002',
  true
);
select lives_ok(
  format(
    $$ select public.join_game_room(%L, 'Guest') $$,
    (select snapshot->'room'->>'room_code' from phase31_context)
  ),
  'A second player joins the room'
);

create temp table phase31_activity_before as
select room.last_activity_at
from public.game_rooms as room
where room.id = (
  select (snapshot->'room'->>'id')::uuid from phase31_context
);

select pg_sleep(0.01);
select public.leave_game_room(
  (select (snapshot->'room'->>'id')::uuid from phase31_context)
);

select cmp_ok(
  (
    select room.last_activity_at
    from public.game_rooms as room
    where room.id = (
      select (snapshot->'room'->>'id')::uuid from phase31_context
    )
  ),
  '>',
  (select last_activity_at from phase31_activity_before),
  'Non-host leave updates game_rooms.last_activity_at'
);

select * from finish();
rollback;
