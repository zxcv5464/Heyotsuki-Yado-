-- Roster Hotfix: closed submission periods are structurally read-only.
-- Reopening a period changes only its status, then the normal period-save RPC
-- can update dates, shift slots, and role requirement snapshots.

create or replace function public.prevent_closed_roster_period_structure_changes()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_period_id uuid;
  target_status text;
begin
  if tg_table_name = 'roster_periods' then
    if coalesce(to_jsonb(old)->>'status', '') <> 'open'
      and (
        to_jsonb(new)->>'title' is distinct from to_jsonb(old)->>'title'
        or to_jsonb(new)->>'date_from' is distinct from to_jsonb(old)->>'date_from'
        or to_jsonb(new)->>'date_to' is distinct from to_jsonb(old)->>'date_to'
      ) then
      raise exception 'Closed roster periods must be reopened before their structure can change.';
    end if;
    return new;
  end if;

  target_period_id := coalesce(
    nullif(to_jsonb(new)->>'period_id', '')::uuid,
    nullif(to_jsonb(old)->>'period_id', '')::uuid
  );
  select status into target_status
  from public.roster_periods
  where id = target_period_id;

  if target_status is null then
    raise exception 'Roster period not found.';
  end if;
  if target_status <> 'open' then
    raise exception 'Closed roster periods must be reopened before their structure can change.';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists roster_periods_open_structure_only on public.roster_periods;
create trigger roster_periods_open_structure_only
before update of title, date_from, date_to on public.roster_periods
for each row execute function public.prevent_closed_roster_period_structure_changes();

drop trigger if exists roster_shift_slots_open_structure_only on public.roster_shift_slots;
create trigger roster_shift_slots_open_structure_only
before insert or update or delete on public.roster_shift_slots
for each row execute function public.prevent_closed_roster_period_structure_changes();

drop trigger if exists roster_requirements_open_structure_only on public.roster_period_role_requirements;
create trigger roster_requirements_open_structure_only
before insert or update or delete on public.roster_period_role_requirements
for each row execute function public.prevent_closed_roster_period_structure_changes();
