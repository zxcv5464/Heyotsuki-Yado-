-- Rollback for 20260620050000_staff_payroll_settlement.sql.
-- This removes only the payroll settlement module.

revoke all on public.menu_item_payroll_rules from anon, authenticated;
revoke all on public.payroll_batches from anon, authenticated;
revoke all on public.payroll_pool_members from anon, authenticated;
revoke all on public.dance_sessions from anon, authenticated;
revoke all on public.dance_session_participants from anon, authenticated;
revoke all on public.payroll_entries from anon, authenticated;

revoke all on function public.create_payroll_adjustment(uuid, uuid, integer, text) from public;
revoke all on function public.lock_payroll_batch(uuid) from public;
revoke all on function public.regenerate_payroll_entries(uuid) from public;
revoke all on function public.set_dance_session_participants(uuid, uuid[]) from public;
revoke all on function public.upsert_dance_session(uuid, uuid, integer, integer, text) from public;
revoke all on function public.set_payroll_pool_members(uuid, uuid[]) from public;
revoke all on function public.get_payroll_batch_snapshot(uuid) from public;
revoke all on function public.create_or_get_payroll_batch(text, date) from public;
revoke all on function public.upsert_menu_item_payroll_rule(uuid, text) from public;
revoke all on function public.get_payroll_menu_rules(text) from public;
revoke all on function public.get_payroll_default_business_date(text) from public;
revoke all on function public.assert_payroll_batch_draft(uuid) from public;
revoke all on function public.prevent_locked_payroll_entry_changes() from public;
revoke all on function public.prevent_locked_dance_participant_changes() from public;
revoke all on function public.prevent_locked_payroll_batch_header_changes() from public;
revoke all on function public.prevent_locked_payroll_batch_changes() from public;
revoke all on function public.ensure_payroll_admin() from public;
revoke all on function public.is_payroll_admin() from public;

drop trigger if exists payroll_entries_prevent_locked_changes
  on public.payroll_entries;
drop trigger if exists dance_session_participants_prevent_locked_changes
  on public.dance_session_participants;
drop trigger if exists dance_sessions_prevent_locked_changes
  on public.dance_sessions;
drop trigger if exists payroll_pool_members_prevent_locked_changes
  on public.payroll_pool_members;
drop trigger if exists payroll_batches_prevent_locked_changes
  on public.payroll_batches;
drop trigger if exists dance_sessions_set_updated_at
  on public.dance_sessions;
drop trigger if exists payroll_batches_set_updated_at
  on public.payroll_batches;
drop trigger if exists menu_item_payroll_rules_set_updated_at
  on public.menu_item_payroll_rules;

drop policy if exists "payroll_entries_admin_write"
  on public.payroll_entries;
drop policy if exists "payroll_entries_admin_read"
  on public.payroll_entries;
drop policy if exists "dance_session_participants_admin_write"
  on public.dance_session_participants;
drop policy if exists "dance_session_participants_admin_read"
  on public.dance_session_participants;
drop policy if exists "dance_sessions_admin_write"
  on public.dance_sessions;
drop policy if exists "dance_sessions_admin_read"
  on public.dance_sessions;
drop policy if exists "payroll_pool_members_admin_write"
  on public.payroll_pool_members;
drop policy if exists "payroll_pool_members_admin_read"
  on public.payroll_pool_members;
drop policy if exists "payroll_batches_admin_write"
  on public.payroll_batches;
drop policy if exists "payroll_batches_admin_read"
  on public.payroll_batches;
drop policy if exists "menu_item_payroll_rules_admin_write"
  on public.menu_item_payroll_rules;
drop policy if exists "menu_item_payroll_rules_admin_read"
  on public.menu_item_payroll_rules;

drop function if exists public.create_payroll_adjustment(uuid, uuid, integer, text);
drop function if exists public.lock_payroll_batch(uuid);
drop function if exists public.regenerate_payroll_entries(uuid);
drop function if exists public.set_dance_session_participants(uuid, uuid[]);
drop function if exists public.upsert_dance_session(uuid, uuid, integer, integer, text);
drop function if exists public.set_payroll_pool_members(uuid, uuid[]);
drop function if exists public.get_payroll_batch_snapshot(uuid);
drop function if exists public.create_or_get_payroll_batch(text, date);
drop function if exists public.upsert_menu_item_payroll_rule(uuid, text);
drop function if exists public.get_payroll_menu_rules(text);
drop function if exists public.get_payroll_default_business_date(text);
drop function if exists public.assert_payroll_batch_draft(uuid);
drop function if exists public.prevent_locked_payroll_entry_changes();
drop function if exists public.prevent_locked_dance_participant_changes();
drop function if exists public.prevent_locked_payroll_batch_header_changes();
drop function if exists public.prevent_locked_payroll_batch_changes();
drop function if exists public.ensure_payroll_admin();
drop function if exists public.is_payroll_admin();

drop table if exists public.payroll_entries;
drop table if exists public.dance_session_participants;
drop table if exists public.dance_sessions;
drop table if exists public.payroll_pool_members;
drop table if exists public.payroll_batches;
drop table if exists public.menu_item_payroll_rules;
