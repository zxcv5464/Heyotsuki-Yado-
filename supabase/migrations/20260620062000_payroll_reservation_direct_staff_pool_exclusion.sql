-- Payroll pool exclusion hotfix.
-- Public pool candidates should exclude same-day reservation-designated staff,
-- not order-item selected staff.

create or replace function public.get_payroll_direct_staff_ids(
  p_batch_id uuid
)
returns uuid[]
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  batch_record public.payroll_batches%rowtype;
  staff_ids uuid[];
begin
  perform public.ensure_payroll_admin();

  select * into batch_record
  from public.payroll_batches
  where id = p_batch_id;

  if batch_record.id is null then
    raise exception 'Payroll batch not found.';
  end if;

  select coalesce(array_agg(distinct designated.staff_id), array[]::uuid[])
    into staff_ids
  from public.reservations
  cross join lateral (
    values
      (reservations.preferred_staff_id),
      (reservations.preferred_staff_2_id)
  ) as designated(staff_id)
  where reservations.reservation_date = batch_record.business_date
    and reservations.deleted_at is null
    and reservations.status in ('pending', 'confirmed', 'completed')
    and designated.staff_id is not null;

  return staff_ids;
end;
$$;

revoke all on function public.get_payroll_direct_staff_ids(uuid) from public;
grant execute on function public.get_payroll_direct_staff_ids(uuid)
  to authenticated;
