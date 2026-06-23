-- Phase 2-A availability and reservable staff migration.
-- Run once after supabase/reservations.sql on an existing project.
-- This migration does not delete or recreate reservation data.

alter table public.staff_members
  add column if not exists is_reservable boolean not null default true;

alter table public.reservation_form_settings
  add column if not exists booking_window_days integer not null default 60;
alter table public.reservation_form_settings
  drop constraint if exists reservation_form_settings_booking_window_check;
alter table public.reservation_form_settings
  add constraint reservation_form_settings_booking_window_check
  check (booking_window_days > 0);

alter table public.reservations
  add column if not exists preferred_staff_2_name text;
alter table public.reservations
  add column if not exists preferred_staff_2_id uuid
  references public.staff_members(id) on delete set null;

create unique index if not exists reservations_active_slot_unique_idx
  on public.reservations (reservation_date, reservation_time)
  where deleted_at is null
    and status in ('pending', 'confirmed');

create or replace function public.is_reservation_date_available(
  p_target_date date
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with settings as (
    select
      allowed_weekdays,
      min_days_before,
      booking_window_days,
      is_active
    from public.reservation_form_settings
    where id = 'default'
  ),
  override_row as (
    select mode
    from public.reservation_date_overrides
    where reservation_date_overrides.target_date = p_target_date
  )
  select coalesce(
    (
      select
        settings.is_active
        and p_target_date >=
          (now() at time zone 'Asia/Taipei')::date
            + settings.min_days_before
        and p_target_date <=
          (now() at time zone 'Asia/Taipei')::date
            + settings.booking_window_days
        and case
          when override_row.mode = 'closed' then false
          when override_row.mode = 'open' then true
          else extract(dow from p_target_date)::integer =
            any(settings.allowed_weekdays)
        end
      from settings
      left join override_row on true
    ),
    false
  );
$$;

create or replace function public.get_public_reservation_availability(
  p_days integer default 60
)
returns table (
  reservation_date date,
  display_label text,
  available_slots jsonb
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with settings as (
    select
      allowed_weekdays,
      min_days_before,
      booking_window_days,
      is_active
    from public.reservation_form_settings
    where id = 'default'
  ),
  candidate_dates as (
    select generated_date::date as reservation_date
    from settings
    cross join lateral generate_series(
      (now() at time zone 'Asia/Taipei')::date
        + settings.min_days_before,
      (now() at time zone 'Asia/Taipei')::date
        + least(
            settings.booking_window_days,
            greatest(coalesce(p_days, settings.booking_window_days), 1)
          ),
      interval '1 day'
    ) as generated_date
    where settings.is_active = true
  ),
  open_dates as (
    select candidate_dates.reservation_date
    from candidate_dates
    cross join settings
    left join public.reservation_date_overrides
      on reservation_date_overrides.target_date =
        candidate_dates.reservation_date
    where case
      when reservation_date_overrides.mode = 'closed' then false
      when reservation_date_overrides.mode = 'open' then true
      else extract(dow from candidate_dates.reservation_date)::integer =
        any(settings.allowed_weekdays)
    end
  ),
  slots_by_date as (
    select
      open_dates.reservation_date,
      jsonb_agg(
        jsonb_build_object(
          'label', reservation_time_slots.label,
          'value', reservation_time_slots.value
        )
        order by reservation_time_slots.sort_order,
          reservation_time_slots.value
      ) as available_slots
    from open_dates
    cross join public.reservation_time_slots
    where reservation_time_slots.is_visible = true
      and not exists (
        select 1
        from public.reservations
        where reservations.reservation_date = open_dates.reservation_date
          and reservations.reservation_time =
            reservation_time_slots.value
          and reservations.status in ('pending', 'confirmed')
          and reservations.deleted_at is null
      )
    group by open_dates.reservation_date
  )
  select
    slots_by_date.reservation_date,
    to_char(slots_by_date.reservation_date, 'YYYY/MM/DD')
      || '（'
      || (array['日', '一', '二', '三', '四', '五', '六'])[
        extract(dow from slots_by_date.reservation_date)::integer + 1
      ]
      || '）' as display_label,
    slots_by_date.available_slots
  from slots_by_date
  where jsonb_array_length(slots_by_date.available_slots) > 0
  order by slots_by_date.reservation_date;
$$;

revoke all on function public.get_public_reservation_availability(integer)
  from public;
grant execute on function public.get_public_reservation_availability(integer)
  to anon, authenticated;

drop policy if exists "reservation_date_overrides_public_read"
  on public.reservation_date_overrides;
revoke select on public.reservation_date_overrides from anon;
grant select on public.reservation_date_overrides to authenticated;

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

revoke insert on public.reservations from anon;
grant insert on public.reservations to anon;
grant select, insert, update, delete on public.reservations to authenticated;

insert into public.reservation_form_fields (
  id,
  field_key,
  label,
  help_text,
  field_type,
  required,
  is_visible,
  sort_order
) values (
  md5('reservation-field:contact')::uuid,
  'contact',
  '聯絡方式',
  '請填寫 Discord 名稱或其他可聯絡方式',
  'text',
  true,
  true,
  15
)
on conflict (field_key) do update set
  required = true,
  is_visible = true;
