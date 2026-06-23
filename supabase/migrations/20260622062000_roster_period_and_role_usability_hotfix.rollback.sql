-- Rollback for 20260622062000_roster_period_and_role_usability_hotfix.sql.
-- Restore save_roster_role from 20260622060000_roster_system_v1.sql if the prior
-- manual code/sort input behavior is required.

drop function if exists public.delete_roster_role(uuid);
