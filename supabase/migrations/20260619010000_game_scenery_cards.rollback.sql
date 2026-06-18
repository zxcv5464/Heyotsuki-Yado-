do $scenery_apply_game_action_rollback$
declare
  function_sql text;
begin
  select pg_get_functiondef('public.apply_game_action(uuid, uuid, bigint, text, jsonb)'::regprocedure)
  into function_sql;

  if function_sql is not null
    and position('coalesce(card ->> ''cardType'', ''staff'') = ''staff''' in function_sql) > 0
  then
    function_sql := replace(
      function_sql,
      $$where coalesce(card ->> 'cardType', 'staff') = 'staff'
              and coalesce(card ->> 'sourceStaffId', card ->> 'staffId')
                = next_state -> 'players' -> actor_index ->> 'designatedStaffId'$$,
      $$where card ->> 'staffId' = next_state -> 'players' -> actor_index ->> 'designatedStaffId'$$
    );
    execute function_sql;
  end if;
end $scenery_apply_game_action_rollback$;

-- If active games already contain scenery cards, finish or clear them before
-- rolling this back. Reverting start_game_room returns future games to staff-only
-- card pools.
do $scenery_start_game_room_rollback$
declare
  function_sql text;
begin
  select pg_get_functiondef('public.start_game_room(uuid)'::regprocedure)
  into function_sql;

  if function_sql is not null
    and position('public.get_active_game_cards()' in function_sql) > 0
  then
    function_sql := replace(
      function_sql,
      'designation_card_count integer;
  ',
      ''
    );
    function_sql := replace(
      function_sql,
      'select count(*) into card_count from public.get_active_game_cards();
  select count(*) into designation_card_count from public.get_active_game_staff_cards();',
      'select count(*) into card_count from public.get_active_game_staff_cards();'
    );
    function_sql := replace(
      function_sql,
      'turns_per_player <= 0 or designation_card_count < player_count * 3',
      'turns_per_player <= 0 or card_count < player_count * 3'
    );
    function_sql := replace(
      function_sql,
      $$'staffId', card.card_id,
      'cardType', card.card_type,
      'sourceStaffId', card.staff_id,
      'sceneryId', card.scenery_id,
      'name', card.name,$$,
      $$'staffId', card.staff_id,
      'name', card.name,$$
    );
    function_sql := replace(
      function_sql,
      'order by md5(game_seed || '':deck:'' || card.card_id::text)',
      'order by md5(game_seed || '':deck:'' || card.staff_id::text)'
    );
    function_sql := replace(
      function_sql,
      'from public.get_active_game_cards() as card
  where card.image_url ~ ''^https://''',
      'from public.get_active_game_staff_cards() as card
  where card.image_url ~ ''^https://'''
    );
    function_sql := replace(
      function_sql,
      'select distinct card.month_no
    from public.get_active_game_cards() as card',
      'select distinct card.month_no
    from public.get_active_game_staff_cards() as card'
    );
    execute function_sql;
  end if;
end $scenery_start_game_room_rollback$;

revoke all on function public.get_active_game_cards() from public;
drop function if exists public.get_active_game_cards();

drop trigger if exists game_scenery_cards_set_updated_at
  on public.game_scenery_cards;
drop table if exists public.game_scenery_cards;
