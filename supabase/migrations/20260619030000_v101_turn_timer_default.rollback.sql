alter table public.game_rooms
  alter column turn_timer_enabled set default true;

comment on column public.game_rooms.turn_timer_enabled
is 'Turn timer flag for future gameplay rules. Rollback restores the pre-v1.0.1 default for new rooms.';
