-- Rollback for 20260622040000_admin_permissions.sql.
-- Export admin_profiles and all admin_permission_* tables before running.
-- Re-run the repository's original schema / orders / reservations policy SQL afterwards
-- to restore the former coarse owner/admin policy model.

drop function if exists public.delete_admin_permission_template(uuid);
drop function if exists public.save_admin_permission_template(uuid, text, text, text[]);
drop function if exists public.update_admin_account_permissions(uuid, text, text, uuid, boolean, uuid, text[]);
drop function if exists public.get_payroll_batch_for_view(text, date);
drop function if exists public.get_admin_accounts_snapshot();
drop function if exists public.get_admin_permission_context();
drop function if exists public.ensure_admin_permission(text);
drop function if exists public.has_any_admin_permission(text[]);
drop function if exists public.has_admin_permission(text);

drop table if exists public.admin_profile_permissions;
drop table if exists public.admin_permission_template_items;
drop table if exists public.admin_permission_templates;
drop table if exists public.admin_permission_definitions;

alter table public.admin_profiles drop constraint if exists admin_profiles_permission_template_id_fkey;
drop index if exists public.admin_profiles_staff_id_unique_idx;
alter table public.admin_profiles drop column if exists permission_template_id;
alter table public.admin_profiles drop column if exists staff_id;
