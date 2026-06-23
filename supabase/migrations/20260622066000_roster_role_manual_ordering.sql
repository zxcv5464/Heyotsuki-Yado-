-- Roster Hotfix: keep automatic ordering for new roles while allowing
-- administrators to move an existing role up or down safely.

create or replace function public.move_roster_role(
  p_role_id uuid,
  p_direction text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  ordered_role_ids uuid[];
  current_index integer;
  replacement_index integer;
  replacement_role_id uuid;
begin
  perform public.ensure_admin_permission('roster.manage');
  if p_direction not in ('up', 'down') then
    raise exception 'Invalid roster role direction.';
  end if;

  select array_agg(id) into ordered_role_ids
  from (
    select id
    from public.roster_roles
    order by sort_order, name, id
    for update
  ) as ordered_roles;

  current_index := array_position(ordered_role_ids, p_role_id);
  if current_index is null then
    raise exception 'Roster role not found.';
  end if;

  replacement_index := current_index + case when p_direction = 'up' then -1 else 1 end;
  if replacement_index < 1 or replacement_index > coalesce(array_length(ordered_role_ids, 1), 0) then
    return public.roster_snapshot(null);
  end if;

  replacement_role_id := ordered_role_ids[replacement_index];
  update public.roster_roles
  set sort_order = case
    when id = p_role_id then replacement_index * 10
    when id = replacement_role_id then current_index * 10
    else sort_order
  end
  where id in (p_role_id, replacement_role_id);

  return public.roster_snapshot(null);
end;
$$;

revoke all on function public.move_roster_role(uuid, text) from public;
grant execute on function public.move_roster_role(uuid, text) to authenticated;
