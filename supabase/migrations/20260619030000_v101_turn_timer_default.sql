alter table public.game_rooms
  alter column turn_timer_enabled set default false;

update public.game_rooms
set turn_timer_enabled = false,
    updated_at = now(),
    last_activity_at = clock_timestamp()
where status = 'waiting'
  and turn_timer_enabled is true;

comment on column public.game_rooms.turn_timer_enabled
is 'v1.0.1: turn timer is retained as future infrastructure but new rooms default to disabled; no timeout rule is currently enforced.';
