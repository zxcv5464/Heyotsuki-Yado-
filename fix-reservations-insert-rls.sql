-- Apply this idempotent hotfix in the Supabase SQL Editor.
-- The reservation form may run with either the anon role or an existing
-- authenticated admin session, so both roles need the same restricted policy.

begin;

alter table public.reservations enable row level security;

drop policy if exists "reservations_public_insert" on public.reservations;

create policy "reservations_public_insert"
on public.reservations
for insert
to anon, authenticated
with check (
  deleted_at is null
  and coalesce(status, 'pending') = 'pending'
  and coalesce(discord_status, 'pending') = 'pending'
  and customer_name is not null
  and contact is not null
  and reservation_date is not null
  and reservation_time is not null
  and party_size >= 1
);

grant insert on public.reservations to anon;
grant select, insert, update, delete on public.reservations to authenticated;

commit;

-- Optional verification:
select
  policyname,
  roles,
  cmd,
  with_check
from pg_policies
where schemaname = 'public'
  and tablename = 'reservations'
order by policyname;
