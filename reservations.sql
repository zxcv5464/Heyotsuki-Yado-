-- Phase 2-A reservation system.
-- Run after supabase/schema.sql.

create extension if not exists pgcrypto;

create table if not exists public.reservation_form_settings (
  id text primary key default 'default',
  title text not null,
  description text,
  allowed_weekdays integer[] not null default array[5, 6, 0],
  min_days_before integer not null default 1 check (min_days_before >= 0),
  booking_window_days integer not null default 60,
  is_active boolean not null default true,
  updated_at timestamptz not null default now(),
  constraint reservation_form_settings_weekdays_check
    check (allowed_weekdays <@ array[0, 1, 2, 3, 4, 5, 6])
);

create table if not exists public.reservation_time_slots (
  id uuid primary key default gen_random_uuid(),
  label text not null,
  value text not null unique,
  is_visible boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.reservation_date_overrides (
  id uuid primary key default gen_random_uuid(),
  target_date date not null unique,
  mode text not null check (mode in ('open', 'closed')),
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.reservation_form_fields (
  id uuid primary key default gen_random_uuid(),
  field_key text not null unique,
  label text not null,
  help_text text,
  field_type text not null check (
    field_type in (
      'text',
      'textarea',
      'date',
      'select',
      'radio',
      'number',
      'staff_select'
    )
  ),
  required boolean not null default false,
  is_visible boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.reservation_form_options (
  id uuid primary key default gen_random_uuid(),
  field_id uuid not null references public.reservation_form_fields(id) on delete cascade,
  label text not null,
  value text not null,
  is_visible boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (field_id, value)
);

create table if not exists public.reservations (
  id uuid primary key default gen_random_uuid(),
  customer_name text not null,
  contact text,
  reservation_date date not null,
  reservation_time text not null,
  party_size integer not null default 1 check (party_size > 0),
  changing_together text,
  plan text,
  preferred_staff_name text,
  preferred_staff_id uuid references public.staff_members(id) on delete set null,
  preferred_staff_2_name text,
  preferred_staff_2_id uuid references public.staff_members(id) on delete set null,
  photo_service text,
  dessert_service text,
  note text,
  form_answers jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (
    status in ('pending', 'confirmed', 'cancelled', 'completed', 'no_show')
  ),
  admin_note text,
  discord_status text not null default 'pending' check (
    discord_status in ('pending', 'sent', 'failed', 'skipped')
  ),
  discord_attempts integer not null default 0 check (discord_attempts >= 0),
  discord_last_error text,
  discord_notified_at timestamptz,
  deleted_at timestamptz,
  deleted_by uuid references auth.users(id) on delete set null,
  delete_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

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

create index if not exists reservations_status_date_idx
  on public.reservations (status, reservation_date, reservation_time)
  where deleted_at is null;
create index if not exists reservations_customer_search_idx
  on public.reservations (lower(customer_name));
create index if not exists reservations_deleted_at_idx
  on public.reservations (deleted_at);
create unique index if not exists reservations_active_slot_unique_idx
  on public.reservations (reservation_date, reservation_time)
  where deleted_at is null
    and status in ('pending', 'confirmed');
create index if not exists reservation_time_slots_order_idx
  on public.reservation_time_slots (is_visible, sort_order);
create index if not exists reservation_form_fields_order_idx
  on public.reservation_form_fields (is_visible, sort_order);
create index if not exists reservation_form_options_order_idx
  on public.reservation_form_options (field_id, is_visible, sort_order);

drop trigger if exists reservation_form_settings_set_updated_at
  on public.reservation_form_settings;
create trigger reservation_form_settings_set_updated_at
before update on public.reservation_form_settings
for each row execute function public.set_updated_at();

drop trigger if exists reservation_time_slots_set_updated_at
  on public.reservation_time_slots;
create trigger reservation_time_slots_set_updated_at
before update on public.reservation_time_slots
for each row execute function public.set_updated_at();

drop trigger if exists reservation_date_overrides_set_updated_at
  on public.reservation_date_overrides;
create trigger reservation_date_overrides_set_updated_at
before update on public.reservation_date_overrides
for each row execute function public.set_updated_at();

drop trigger if exists reservation_form_fields_set_updated_at
  on public.reservation_form_fields;
create trigger reservation_form_fields_set_updated_at
before update on public.reservation_form_fields
for each row execute function public.set_updated_at();

drop trigger if exists reservation_form_options_set_updated_at
  on public.reservation_form_options;
create trigger reservation_form_options_set_updated_at
before update on public.reservation_form_options
for each row execute function public.set_updated_at();

drop trigger if exists reservations_set_updated_at on public.reservations;
create trigger reservations_set_updated_at
before update on public.reservations
for each row execute function public.set_updated_at();

create or replace function public.is_backoffice_user()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.admin_profiles
    where id = auth.uid()
      and role in ('owner', 'admin', 'staff')
      and is_active = true
  );
$$;

create or replace function public.is_reservation_date_available(p_target_date date)
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

revoke all on function public.is_backoffice_user() from public;
grant execute on function public.is_backoffice_user() to authenticated;
revoke all on function public.is_reservation_date_available(date) from public;
grant execute on function public.is_reservation_date_available(date)
  to anon, authenticated;
revoke all on function public.get_public_reservation_availability(integer)
  from public;
grant execute on function public.get_public_reservation_availability(integer)
  to anon, authenticated;

alter table public.reservations enable row level security;
alter table public.reservation_form_settings enable row level security;
alter table public.reservation_time_slots enable row level security;
alter table public.reservation_date_overrides enable row level security;
alter table public.reservation_form_fields enable row level security;
alter table public.reservation_form_options enable row level security;

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

drop policy if exists "reservations_backoffice_read" on public.reservations;
create policy "reservations_backoffice_read"
on public.reservations
for select
to authenticated
using (public.is_backoffice_user());

drop policy if exists "reservations_admin_update" on public.reservations;
create policy "reservations_admin_update"
on public.reservations
for update
to authenticated
using (public.is_content_admin())
with check (public.is_content_admin());

drop policy if exists "reservations_admin_delete" on public.reservations;
create policy "reservations_admin_delete"
on public.reservations
for delete
to authenticated
using (public.is_content_admin());

drop policy if exists "reservation_form_settings_public_read"
  on public.reservation_form_settings;
create policy "reservation_form_settings_public_read"
on public.reservation_form_settings
for select
to anon
using (is_active = true);

drop policy if exists "reservation_form_settings_backoffice_read"
  on public.reservation_form_settings;
create policy "reservation_form_settings_backoffice_read"
on public.reservation_form_settings
for select
to authenticated
using (public.is_backoffice_user());

drop policy if exists "reservation_form_settings_admin_write"
  on public.reservation_form_settings;
create policy "reservation_form_settings_admin_write"
on public.reservation_form_settings
for all
to authenticated
using (public.is_content_admin())
with check (public.is_content_admin());

drop policy if exists "reservation_time_slots_public_read"
  on public.reservation_time_slots;
create policy "reservation_time_slots_public_read"
on public.reservation_time_slots
for select
to anon
using (is_visible = true);

drop policy if exists "reservation_time_slots_backoffice_read"
  on public.reservation_time_slots;
create policy "reservation_time_slots_backoffice_read"
on public.reservation_time_slots
for select
to authenticated
using (public.is_backoffice_user());

drop policy if exists "reservation_time_slots_admin_write"
  on public.reservation_time_slots;
create policy "reservation_time_slots_admin_write"
on public.reservation_time_slots
for all
to authenticated
using (public.is_content_admin())
with check (public.is_content_admin());

drop policy if exists "reservation_date_overrides_public_read"
  on public.reservation_date_overrides;

drop policy if exists "reservation_date_overrides_backoffice_read"
  on public.reservation_date_overrides;
create policy "reservation_date_overrides_backoffice_read"
on public.reservation_date_overrides
for select
to authenticated
using (public.is_backoffice_user());

drop policy if exists "reservation_date_overrides_admin_write"
  on public.reservation_date_overrides;
create policy "reservation_date_overrides_admin_write"
on public.reservation_date_overrides
for all
to authenticated
using (public.is_content_admin())
with check (public.is_content_admin());

drop policy if exists "reservation_form_fields_public_read"
  on public.reservation_form_fields;
create policy "reservation_form_fields_public_read"
on public.reservation_form_fields
for select
to anon
using (is_visible = true);

drop policy if exists "reservation_form_fields_backoffice_read"
  on public.reservation_form_fields;
create policy "reservation_form_fields_backoffice_read"
on public.reservation_form_fields
for select
to authenticated
using (public.is_backoffice_user());

drop policy if exists "reservation_form_fields_admin_write"
  on public.reservation_form_fields;
create policy "reservation_form_fields_admin_write"
on public.reservation_form_fields
for all
to authenticated
using (public.is_content_admin())
with check (public.is_content_admin());

drop policy if exists "reservation_form_options_public_read"
  on public.reservation_form_options;
create policy "reservation_form_options_public_read"
on public.reservation_form_options
for select
to anon
using (
  is_visible = true
  and exists (
    select 1
    from public.reservation_form_fields
    where reservation_form_fields.id = reservation_form_options.field_id
      and reservation_form_fields.is_visible = true
  )
);

drop policy if exists "reservation_form_options_backoffice_read"
  on public.reservation_form_options;
create policy "reservation_form_options_backoffice_read"
on public.reservation_form_options
for select
to authenticated
using (public.is_backoffice_user());

drop policy if exists "reservation_form_options_admin_write"
  on public.reservation_form_options;
create policy "reservation_form_options_admin_write"
on public.reservation_form_options
for all
to authenticated
using (public.is_content_admin())
with check (public.is_content_admin());

revoke all on public.reservations from anon, authenticated;
revoke all on public.reservation_form_settings from anon, authenticated;
revoke all on public.reservation_time_slots from anon, authenticated;
revoke all on public.reservation_date_overrides from anon, authenticated;
revoke all on public.reservation_form_fields from anon, authenticated;
revoke all on public.reservation_form_options from anon, authenticated;

grant insert on public.reservations to anon;
grant select, insert, update, delete on public.reservations to authenticated;

grant select on public.reservation_form_settings to anon, authenticated;
grant select on public.reservation_time_slots to anon, authenticated;
grant select on public.reservation_date_overrides to authenticated;
grant select on public.reservation_form_fields to anon, authenticated;
grant select on public.reservation_form_options to anon, authenticated;

grant insert, update, delete on public.reservation_form_settings to authenticated;
grant insert, update, delete on public.reservation_time_slots to authenticated;
grant insert, update, delete on public.reservation_date_overrides to authenticated;
grant insert, update, delete on public.reservation_form_fields to authenticated;
grant insert, update, delete on public.reservation_form_options to authenticated;

insert into public.reservation_form_settings (
  id,
  title,
  description,
  allowed_weekdays,
  min_days_before,
  booking_window_days,
  is_active
) values (
  'default',
  '嘿月湯宿 預約表',
  E'歡迎預約 嘿月湯宿 ♨️\n利維坦 白銀鄉 15區 7號房\n營業時間為每週五、六、日 晚上 21:00 至凌晨 24:00\n請填寫以下資訊，我們將依照您的預約內容為您安排時段與接待流程！\n預約成功與否會再 Discord 顯示並回復，請務必加入群組確認！\n如有重複預約依照預約時間點較早優先為主！',
  array[5, 6, 0],
  1,
  60,
  true
)
on conflict (id) do nothing;

insert into public.reservation_time_slots (
  id,
  label,
  value,
  is_visible,
  sort_order
) values
  (md5('reservation-slot:21:30')::uuid, '21:30', '21:30', true, 10),
  (md5('reservation-slot:22:30')::uuid, '22:30', '22:30', true, 20),
  (md5('reservation-slot:23:30')::uuid, '23:30', '23:30', true, 30)
on conflict (value) do nothing;

insert into public.reservation_form_fields (
  id,
  field_key,
  label,
  help_text,
  field_type,
  required,
  is_visible,
  sort_order
) values
  (md5('reservation-field:customer_name')::uuid, 'customer_name', '預約人姓名', null, 'text', true, true, 10),
  (md5('reservation-field:contact')::uuid, 'contact', '聯絡方式', '請填寫 Discord 名稱或其他可聯絡方式', 'text', true, true, 15),
  (md5('reservation-field:reservation_date')::uuid, 'reservation_date', '預約日期', null, 'date', true, true, 20),
  (md5('reservation-field:reservation_time')::uuid, 'reservation_time', '預約時段', null, 'select', true, true, 30),
  (md5('reservation-field:party_size')::uuid, 'party_size', '預約人數', null, 'radio', true, true, 40),
  (md5('reservation-field:changing_together')::uuid, 'changing_together', '雙人入湯時請先確定是否能同時更衣', '如果是單人預約可以略過', 'radio', false, true, 50),
  (md5('reservation-field:plan')::uuid, 'plan', '預約方案', null, 'radio', true, true, 60),
  (md5('reservation-field:preferred_staff_name')::uuid, 'preferred_staff_name', '指定湯娘姓名', '若無指定可留空', 'staff_select', false, true, 70),
  (md5('reservation-field:photo_service')::uuid, 'photo_service', '是否需要拍照服務', null, 'radio', true, true, 80),
  (md5('reservation-field:dessert_service')::uuid, 'dessert_service', '是否需要茶點安排', null, 'radio', true, true, 90),
  (md5('reservation-field:note')::uuid, 'note', '特殊需求或備註', '如有其他安排請填寫，例如生日包場、舉辦特殊活動等', 'textarea', false, true, 100)
on conflict (field_key) do nothing;

insert into public.reservation_form_options (
  id,
  field_id,
  label,
  value,
  is_visible,
  sort_order
) values
  (md5('reservation-option:party_size:1')::uuid, md5('reservation-field:party_size')::uuid, '1人', '1', true, 10),
  (md5('reservation-option:party_size:2')::uuid, md5('reservation-field:party_size')::uuid, '2人', '2', true, 20),
  (md5('reservation-option:changing_together:yes')::uuid, md5('reservation-field:changing_together')::uuid, '是', '是', true, 10),
  (md5('reservation-option:changing_together:no')::uuid, md5('reservation-field:changing_together')::uuid, '否', '否', true, 20),
  (md5('reservation-option:plan:moon-shadow')::uuid, md5('reservation-field:plan')::uuid, '月影方案（一對一服務）', '月影方案（一對一服務）', true, 10),
  (md5('reservation-option:plan:night-moon')::uuid, md5('reservation-field:plan')::uuid, '夜月尊享（一人兩位湯娘服務）（僅限單人月影使用）', '夜月尊享（一人兩位湯娘服務）（僅限單人月影使用）', true, 20),
  (md5('reservation-option:plan:other')::uuid, md5('reservation-field:plan')::uuid, '其他需求洽詢', '其他需求洽詢', true, 30),
  (md5('reservation-option:photo:yes')::uuid, md5('reservation-field:photo_service')::uuid, '需要', '需要', true, 10),
  (md5('reservation-option:photo:no')::uuid, md5('reservation-field:photo_service')::uuid, '不需要', '不需要', true, 20),
  (md5('reservation-option:photo:on-site')::uuid, md5('reservation-field:photo_service')::uuid, '依現場安排', '依現場安排', true, 30),
  (md5('reservation-option:dessert:yes')::uuid, md5('reservation-field:dessert_service')::uuid, '需要', '需要', true, 10),
  (md5('reservation-option:dessert:no')::uuid, md5('reservation-field:dessert_service')::uuid, '不需要', '不需要', true, 20)
on conflict (field_id, value) do nothing;
