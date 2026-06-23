-- Permission system Hotfix 1: normalize manage/view pairs in custom templates.
-- Existing migrations remain unchanged; this migration is safe to apply once in order.

-- Repair custom or legacy templates created before manage -> view normalization.
insert into public.admin_permission_template_items (template_id, permission_key, is_enabled)
select items.template_id, view_definitions.permission_key, true
from public.admin_permission_template_items as items
join public.admin_permission_definitions as view_definitions
  on view_definitions.permission_key = replace(items.permission_key, '.manage', '.view')
where items.is_enabled
  and items.permission_key like '%.manage'
on conflict (template_id, permission_key) do update
set is_enabled = true;

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
  required_keys text[];
begin
  perform public.ensure_admin_permission('permissions.manage');

  if nullif(trim(coalesce(p_name, '')), '') is null then
    raise exception 'Template name is required.';
  end if;
  if p_template_id is not null and exists (
    select 1 from public.admin_permission_templates
    where id = p_template_id and is_system
  ) then
    raise exception 'System templates cannot be edited.';
  end if;

  required_keys := array(
    select distinct permission_key
    from unnest(coalesce(p_permission_keys, '{}'::text[])) as requested(permission_key)
  );
  required_keys := required_keys || array(
    select replace(permission_key, '.manage', '.view')
    from unnest(required_keys) as requested(permission_key)
    where permission_key like '%.manage'
      and exists (
        select 1 from public.admin_permission_definitions
        where permission_key = replace(requested.permission_key, '.manage', '.view')
      )
  );
  required_keys := array(
    select distinct permission_key
    from unnest(required_keys) as requested(permission_key)
  );
  if exists (
    select 1
    from unnest(required_keys) as requested(permission_key)
    where not exists (
      select 1 from public.admin_permission_definitions
      where permission_key = requested.permission_key
    )
  ) then
    raise exception 'Unknown permission key.';
  end if;

  if p_template_id is null then
    insert into public.admin_permission_templates (name, description)
    values (trim(p_name), nullif(trim(coalesce(p_description, '')), ''))
    returning id into target_id;
  else
    update public.admin_permission_templates
    set name = trim(p_name), description = nullif(trim(coalesce(p_description, '')), '')
    where id = p_template_id
    returning id into target_id;
    if target_id is null then
      raise exception 'Permission template was not found.';
    end if;
  end if;

  delete from public.admin_permission_template_items where template_id = target_id;
  insert into public.admin_permission_template_items (template_id, permission_key)
  select target_id, permission_key
  from unnest(required_keys) as requested(permission_key);

  return public.get_admin_accounts_snapshot();
end;
$$;
