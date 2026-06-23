-- Roster usability Hotfix: automatic role identifiers/order and explicit role deletion.

create or replace function public.save_roster_role(
  p_role_id uuid,
  p_code text,
  p_name text,
  p_description text,
  p_min_staff_count integer,
  p_max_staff_count integer,
  p_sort_order integer,
  p_is_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  generated_code text;
  generated_sort_order integer;
begin
  perform public.ensure_admin_permission('roster.manage');
  if nullif(trim(coalesce(p_name, '')), '') is null
    or coalesce(p_min_staff_count, -1) < 0
    or coalesce(p_max_staff_count, 0) < greatest(1, coalesce(p_min_staff_count, 0)) then
    raise exception 'Invalid roster role.';
  end if;

  if p_role_id is null then
    select 'role-' || lpad((coalesce(max(nullif(regexp_replace(code, '[^0-9]', '', 'g'), '')::integer), 0) + 1)::text, 4, '0'), coalesce(max(sort_order), 0) + 10
    into generated_code, generated_sort_order
    from public.roster_roles;
    insert into public.roster_roles (code, name, description, min_staff_count, max_staff_count, sort_order, is_active)
    values (generated_code, trim(p_name), nullif(trim(coalesce(p_description, '')), ''), p_min_staff_count, p_max_staff_count, generated_sort_order, coalesce(p_is_active, true));
  else
    update public.roster_roles
    set name = trim(p_name), description = nullif(trim(coalesce(p_description, '')), ''),
        min_staff_count = p_min_staff_count, max_staff_count = p_max_staff_count,
        is_active = coalesce(p_is_active, true)
    where id = p_role_id;
    if not found then raise exception 'Roster role not found.'; end if;
  end if;
  return public.roster_snapshot(null);
end;
$$;

create or replace function public.delete_roster_role(p_role_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  perform public.ensure_admin_permission('roster.manage');
  delete from public.roster_roles where id = p_role_id;
  if not found then raise exception 'Roster role not found.'; end if;
  return public.roster_snapshot(null);
end;
$$;

revoke all on function public.delete_roster_role(uuid) from public;
grant execute on function public.delete_roster_role(uuid) to authenticated;
