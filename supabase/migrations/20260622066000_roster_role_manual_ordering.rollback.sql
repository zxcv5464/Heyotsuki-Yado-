-- Rollback for 20260622066000_roster_role_manual_ordering.sql.

drop function if exists public.move_roster_role(uuid, text);
