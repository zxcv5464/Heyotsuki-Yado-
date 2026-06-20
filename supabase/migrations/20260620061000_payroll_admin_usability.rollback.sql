-- Rollback for 20260620061000_payroll_admin_usability.sql.

drop function if exists public.get_payroll_direct_staff_ids(uuid);

create or replace function public.prevent_payroll_entry_changes_when_locked()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_status text;
begin
  select payroll_batches.status
    into target_status
  from public.payroll_batches
  where payroll_batches.id = coalesce(new.batch_id, old.batch_id);

  if target_status = 'locked' then
    raise exception 'Locked payroll entries cannot be changed; create a manual adjustment instead.';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;
