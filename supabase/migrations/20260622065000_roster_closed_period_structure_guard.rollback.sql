-- Rollback for 20260622065000_roster_closed_period_structure_guard.sql.

drop trigger if exists roster_requirements_open_structure_only on public.roster_period_role_requirements;
drop trigger if exists roster_shift_slots_open_structure_only on public.roster_shift_slots;
drop trigger if exists roster_periods_open_structure_only on public.roster_periods;
drop function if exists public.prevent_closed_roster_period_structure_changes();
