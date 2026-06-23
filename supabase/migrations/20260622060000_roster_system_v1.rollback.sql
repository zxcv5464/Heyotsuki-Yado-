-- Rollback for 20260622060000_roster_system_v1.sql.
-- Export roster_* records first. This permanently removes roster periods and assignments.

drop policy if exists "roster_assignments_read" on public.roster_assignments;
drop policy if exists "roster_availability_read" on public.roster_availability;
drop policy if exists "roster_slots_read" on public.roster_shift_slots;
drop policy if exists "roster_periods_read" on public.roster_periods;
drop function if exists public.generate_roster_assignments(uuid, boolean, boolean);
drop function if exists public.delete_roster_assignment(uuid);
drop function if exists public.save_roster_assignment(uuid, uuid, uuid, uuid, uuid, text, boolean, text);
drop function if exists public.save_roster_role(uuid, text, text, text, integer, integer, integer, boolean);
drop function if exists public.save_roster_availability(uuid, jsonb);
drop function if exists public.set_roster_period_status(uuid, text);
drop function if exists public.save_roster_period(uuid, text, date, date, jsonb, jsonb);
drop function if exists public.roster_snapshot(uuid);
drop function if exists public.roster_current_staff_id();
drop table if exists public.roster_assignments;
drop table if exists public.roster_availability;
drop table if exists public.roster_period_role_requirements;
drop table if exists public.roster_shift_slots;
drop table if exists public.roster_periods;
drop table if exists public.roster_roles;
delete from public.admin_profile_permissions where permission_key like 'roster.%';
delete from public.admin_permission_template_items where permission_key like 'roster.%';
delete from public.admin_permission_definitions where permission_key like 'roster.%';
