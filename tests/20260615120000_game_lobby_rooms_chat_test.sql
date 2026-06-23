begin;

create extension if not exists pgtap with schema extensions;
select plan(19);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  (
    '90000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', null, '', now(), '{"provider":"anonymous","providers":["anonymous"]}',
    '{}', now(), now()
  ),
  (
    '90000000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', null, '', now(), '{"provider":"anonymous","providers":["anonymous"]}',
    '{}', now(), now()
  ),
  (
    '90000000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', null, '', now(), '{"provider":"anonymous","providers":["anonymous"]}',
    '{}', now(), now()
  );

set local role anon;
select throws_ok(
  $$ select public.create_game_room('Guest', 2::smallint) $$,
  '42501',
  'Authentication required.',
  'Unauthenticated users cannot create rooms'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '90000000-0000-4000-8000-000000000001', true);
create temp table lobby_test_context as
select public.create_game_room('Moon', 2::smallint) as snapshot;

select ok(
  (select snapshot->'room'->>'room_code' ~ '^[A-HJ-NP-Z2-9]{6}$' from lobby_test_context),
  'Authenticated anonymous users receive a readable six-character code'
);
select is(
  (select jsonb_array_length(snapshot->'players') from lobby_test_context),
  1,
  'Room creator occupies one seat'
);
select throws_ok(
  $$ select public.create_game_room('Bad size', 1::smallint) $$,
  '22023',
  'Room size must be between 2 and 4 players.',
  'Room size is restricted to two through four'
);

select set_config('request.jwt.claim.sub', '90000000-0000-4000-8000-000000000002', true);
select lives_ok(
  format(
    $$ select public.join_game_room(%L, 'Star') $$,
    (select snapshot->'room'->>'room_code' from lobby_test_context)
  ),
  'A second anonymous user can join by room code'
);
select throws_ok(
  format(
    $$ select public.join_game_room(%L, 'MOON') $$,
    (select snapshot->'room'->>'room_code' from lobby_test_context)
  ),
  '23505',
  'Nickname is already in use in this room.',
  'Nicknames are unique per room without case sensitivity'
);
select is(
  (
    select public.join_game_room(
      (select snapshot->'room'->>'room_code' from lobby_test_context),
      'Ignored'
    )->>'self_player_id'
  ),
  (
    select id::text from public.game_players
    where user_id = '90000000-0000-4000-8000-000000000002'
  ),
  'Joining twice restores the existing seat'
);
select throws_ok(
  format(
    $$ update public.game_rooms set status = 'closed' where id = %L::uuid $$,
    (select snapshot->'room'->>'id' from lobby_test_context)
  ),
  '42501',
  null,
  'A non-host room member cannot directly modify room state'
);

select set_config('request.jwt.claim.sub', '90000000-0000-4000-8000-000000000003', true);
select is(
  (
    select count(*)::integer from public.game_players
    where room_id = (
      select (snapshot->'room'->>'id')::uuid from lobby_test_context
    )
  ),
  0,
  'Non-members cannot read the player list'
);
select is(
  (
    select count(*)::integer from public.game_messages
    where room_id = (
      select (snapshot->'room'->>'id')::uuid from lobby_test_context
    )
  ),
  0,
  'Non-members cannot read chat'
);
select throws_ok(
  format(
    $$ select public.send_game_message(%L::uuid, 'No access') $$,
    (select snapshot->'room'->>'id' from lobby_test_context)
  ),
  '42501',
  'Open room membership required.',
  'Non-members cannot send chat'
);
select throws_ok(
  format(
    $$ select public.join_game_room(%L, 'Third') $$,
    (select snapshot->'room'->>'room_code' from lobby_test_context)
  ),
  'P0001',
  'Room is full.',
  'Joining a full room is rejected'
);
reset role;
update public.game_players
set last_seen_at = now() - interval '11 minutes'
where user_id = '90000000-0000-4000-8000-000000000002';

set local role authenticated;
select set_config('request.jwt.claim.sub', '90000000-0000-4000-8000-000000000003', true);
select lives_ok(
  format(
    $$ select public.join_game_room(%L, 'Third') $$,
    (select snapshot->'room'->>'room_code' from lobby_test_context)
  ),
  'Seats older than ten minutes can be released during join'
);

select set_config('request.jwt.claim.sub', '90000000-0000-4000-8000-000000000001', true);
select isnt(
  public.get_current_game_room(),
  null::jsonb,
  'A session seen within ten minutes restores its current room'
);
select throws_ok(
  format(
    $$ select public.send_game_message(%L::uuid, '   ') $$,
    (select snapshot->'room'->>'id' from lobby_test_context)
  ),
  '22023',
  'Message must contain 1 to 180 characters.',
  'Empty trimmed messages are rejected'
);
select throws_ok(
  format(
    $$ select public.send_game_message(%L::uuid, repeat('x', 181)) $$,
    (select snapshot->'room'->>'id' from lobby_test_context)
  ),
  '22023',
  'Message must contain 1 to 180 characters.',
  'Messages over 180 characters are rejected'
);
select lives_ok(
  format(
    $$ select public.send_game_message(%L::uuid, '<script>alert(1)</script>') $$,
    (select snapshot->'room'->>'id' from lobby_test_context)
  ),
  'HTML-like chat is stored as plain text'
);
select throws_ok(
  format(
    $$ select public.send_game_message(%L::uuid, 'too fast') $$,
    (select snapshot->'room'->>'id' from lobby_test_context)
  ),
  'P0001',
  'Message rate limit exceeded.',
  'Database chat rate limiting is active'
);

reset role;
update public.game_rooms
set status = 'closed'
where id = (select (snapshot->'room'->>'id')::uuid from lobby_test_context);
set local role authenticated;
select set_config('request.jwt.claim.sub', '90000000-0000-4000-8000-000000000001', true);
select throws_ok(
  format(
    $$ select public.send_game_message(%L::uuid, 'closed') $$,
    (select snapshot->'room'->>'id' from lobby_test_context)
  ),
  '42501',
  'Open room membership required.',
  'Closed rooms reject new chat messages'
);

select * from finish();
rollback;
