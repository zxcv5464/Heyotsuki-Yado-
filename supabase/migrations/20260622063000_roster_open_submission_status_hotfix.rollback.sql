-- Rollback for 20260622063000_roster_open_submission_status_hotfix.sql.
-- Do not run this on a production database unless you intentionally restore
-- the prior workflow. It cannot safely identify which converted legacy draft
-- periods were created by the old default.

alter table public.roster_periods
  alter column status set default 'draft';

-- Restore public.save_roster_period from the previously deployed canonical
-- migration: 20260622061000_roster_period_workflow_hotfix.sql.
