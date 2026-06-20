-- v1.0.1 hotfix: keep internal shuffle data out of public snapshots.
-- Internal game_states.state still stores the authoritative deck and gameSeed.
-- Players must read games through this sanitized RPC only.

revoke all on public.game_states from anon, authenticated;
revoke select on public.game_states from authenticated;

drop policy if exists "game_states_member_read" on public.game_states;
drop policy if exists "game_states_no_direct_api_read" on public.game_states;
create policy "game_states_no_direct_api_read" on public.game_states
for select to authenticated
using (false);

create or replace function public.game_state_snapshot(p_room_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  game_record public.game_states;
  self_player_id uuid;
  raw_state jsonb;
  public_state jsonb;
  public_players jsonb;
  public_choices jsonb := '{}'::jsonb;
  public_active_cards jsonb := '[]'::jsonb;
  game_phase text;
begin
  if not public.is_game_room_member(p_room_id) then
    return null;
  end if;

  select game.* into game_record
  from public.game_states as game
  where game.room_id = p_room_id;

  if game_record.room_id is null then
    return null;
  end if;

  select player.id into self_player_id
  from public.game_players as player
  where player.room_id = p_room_id
    and player.user_id = auth.uid()
    and player.left_at is null;

  if self_player_id is null then
    return null;
  end if;

  raw_state := game_record.state;
  game_phase := raw_state ->> 'phase';

  if game_phase = 'selecting-designation'
    and raw_state -> 'designationChoices' ? self_player_id::text
  then
    public_choices := jsonb_build_object(
      self_player_id::text,
      raw_state -> 'designationChoices' -> self_player_id::text
    );
  end if;

  select coalesce(jsonb_agg(
    case
      when game_phase = 'selecting-designation'
        and player.value ->> 'id' <> self_player_id::text
      then
        (player.value - 'designatedStaffId')
        || jsonb_build_object(
          'designatedStaffId', null,
          'hasDesignatedStaff', (player.value -> 'designatedStaffId') <> 'null'::jsonb
        )
      else
        player.value
        || jsonb_build_object(
          'hasDesignatedStaff', (player.value -> 'designatedStaffId') <> 'null'::jsonb
        )
    end
    order by player.ordinality
  ), '[]'::jsonb)
  into public_players
  from jsonb_array_elements(raw_state -> 'players') with ordinality as player(value, ordinality);

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'staffId', card.value ->> 'staffId',
      'name', card.value ->> 'name',
      'imageUrl', card.value ->> 'imageUrl',
      'monthNo', (card.value ->> 'monthNo')::integer,
      'monthLabel', card.value ->> 'monthLabel',
      'season', card.value ->> 'season',
      'mark', card.value ->> 'mark',
      'cardTitle', card.value -> 'cardTitle',
      'cardType', coalesce(card.value ->> 'cardType', 'staff'),
      'sourceStaffId', card.value -> 'sourceStaffId',
      'sceneryId', card.value -> 'sceneryId',
      'sortOrder', coalesce(nullif(card.value ->> 'sortOrder', '')::integer, 0)
    )
    order by
      coalesce(nullif(card.value ->> 'sortOrder', '')::integer, 0),
      coalesce(card.value ->> 'cardType', 'staff'),
      card.value ->> 'staffId'
  ), '[]'::jsonb)
  into public_active_cards
  from jsonb_array_elements(coalesce(raw_state -> 'activeCards', '[]'::jsonb)) as card(value);

  public_state := raw_state - 'deck' - 'gameSeed';
  public_state := jsonb_set(
    public_state,
    '{deckCount}',
    to_jsonb(jsonb_array_length(coalesce(raw_state -> 'deck', '[]'::jsonb))),
    true
  );
  public_state := jsonb_set(public_state, '{activeCards}', public_active_cards, true);
  public_state := jsonb_set(public_state, '{players}', public_players, true);
  public_state := jsonb_set(public_state, '{designationChoices}', public_choices, true);

  return jsonb_build_object(
    'room_id', game_record.room_id,
    'version', game_record.version,
    'state', public_state,
    'started_at', game_record.started_at,
    'updated_at', game_record.updated_at,
    'finished_at', game_record.finished_at
  );
end;
$$;

revoke all on function public.game_state_snapshot(uuid) from public;
grant execute on function public.game_state_snapshot(uuid) to authenticated;

comment on function public.game_state_snapshot(uuid)
is 'Returns a member-scoped public game snapshot without deck, gameSeed, or shuffle-ordered activeCards; designation choices are only visible to their owner during selection.';
