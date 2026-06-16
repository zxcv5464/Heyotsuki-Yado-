do $$
begin
  if exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'game_states'
  ) then
    alter publication supabase_realtime drop table public.game_states;
  end if;
end
$$;

drop function if exists public.abort_game_room(uuid);
drop function if exists public.apply_game_action(uuid, uuid, bigint, text, jsonb);
drop function if exists public.start_game_room(uuid);
drop function if exists public.game_state_snapshot(uuid);
drop table if exists public.game_actions;
drop table if exists public.game_states;

update public.game_rooms
set status = 'closed', expires_at = now()
where status in ('selecting', 'playing', 'finished');

alter table public.game_rooms
  drop constraint if exists game_rooms_status_check;
alter table public.game_rooms
  add constraint game_rooms_status_check
  check (status in ('waiting', 'closed'));

-- Reapply 20260615124500 after rollback to restore the Phase 3.1 RPC bodies.
