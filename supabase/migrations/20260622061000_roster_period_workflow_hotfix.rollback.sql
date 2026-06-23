-- Rollback for 20260622061000_roster_period_workflow_hotfix.sql.
-- Restores the original new-period default only. Restore the prior save_roster_period
-- definition from 20260622060000_roster_system_v1.sql if full function rollback is required.

alter table public.roster_periods
  alter column status set default 'draft';
