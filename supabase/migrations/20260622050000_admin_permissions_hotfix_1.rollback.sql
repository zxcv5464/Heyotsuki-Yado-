-- Rollback for 20260622050000_admin_permissions_hotfix_1.sql.
-- This restores the prior template-save function. It intentionally does not remove
-- already-added view permissions because they are required by corresponding manage permissions.

create or replace function public.save_admin_permission_template(
  p_template_id uuid,
  p_name text,
  p_description text,
  p_permission_keys text[]
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_id uuid;
begin
  perform public.ensure_admin_permission('permissions.manage');
  if nullif(trim(coalesce(p_name, '')), '') is null then raise exception 'Template name is required.'; end if;
  if p_template_id is not null and exists (select 1 from public.admin_permission_templates where id = p_template_id and is_system) then
    raise exception 'System templates cannot be edited.';
  end if;
  if exists (select 1 from unnest(coalesce(p_permission_keys, '{}'::text[])) as requested(permission_key) where not exists (select 1 from public.admin_permission_definitions where permission_key = requested.permission_key)) then raise exception 'Unknown permission key.'; end if;
  if p_template_id is null then
    insert into public.admin_permission_templates (name, description) values (trim(p_name), nullif(trim(coalesce(p_description, '')), '')) returning id into target_id;
  else
    update public.admin_permission_templates set name = trim(p_name), description = nullif(trim(coalesce(p_description, '')), '') where id = p_template_id returning id into target_id;
  end if;
  delete from public.admin_permission_template_items where template_id = target_id;
  insert into public.admin_permission_template_items (template_id, permission_key)
  select target_id, permission_key from unnest(coalesce(p_permission_keys, '{}'::text[])) as requested(permission_key);
  return public.get_admin_accounts_snapshot();
end;
$$;
