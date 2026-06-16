create table if not exists public.game_staff_card_settings (
  staff_id uuid primary key
    references public.staff_members(id)
    on delete cascade,
  month_no smallint not null
    check (month_no between 1 and 12),
  mark text not null
    check (mark in ('moon', 'bell', 'fan', 'knot')),
  card_title text,
  card_image_url text,
  is_game_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists game_staff_card_settings_active_distribution_idx
  on public.game_staff_card_settings (is_game_enabled, month_no, mark);

drop trigger if exists game_staff_card_settings_set_updated_at
  on public.game_staff_card_settings;
create trigger game_staff_card_settings_set_updated_at
before update on public.game_staff_card_settings
for each row execute function public.set_updated_at();

create or replace function public.get_game_month_catalog()
returns table (
  month_no smallint,
  month_label text,
  season text
)
language sql
immutable
set search_path = ''
as $$
  values
    (1::smallint, '一月・松月'::text, 'spring'::text),
    (2::smallint, '二月・梅月'::text, 'spring'::text),
    (3::smallint, '三月・櫻月'::text, 'spring'::text),
    (4::smallint, '四月・藤月'::text, 'summer'::text),
    (5::smallint, '五月・菖蒲月'::text, 'summer'::text),
    (6::smallint, '六月・牡丹月'::text, 'summer'::text),
    (7::smallint, '七月・萩月'::text, 'autumn'::text),
    (8::smallint, '八月・芒月'::text, 'autumn'::text),
    (9::smallint, '九月・菊月'::text, 'autumn'::text),
    (10::smallint, '十月・楓月'::text, 'winter'::text),
    (11::smallint, '十一月・柳月'::text, 'winter'::text),
    (12::smallint, '十二月・雪月'::text, 'winter'::text);
$$;

create or replace function public.get_active_game_staff_cards()
returns table (
  staff_id uuid,
  name text,
  image_url text,
  month_no smallint,
  month_label text,
  season text,
  mark text,
  card_title text,
  sort_order integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    staff.id,
    staff.name,
    coalesce(
      nullif(btrim(settings.card_image_url), ''),
      nullif(btrim(staff.image_url), '')
    ) as image_url,
    settings.month_no,
    months.month_label,
    months.season,
    settings.mark,
    nullif(btrim(settings.card_title), '') as card_title,
    staff.sort_order
  from public.staff_members as staff
  join public.game_staff_card_settings as settings
    on settings.staff_id = staff.id
  join public.get_game_month_catalog() as months
    on months.month_no = settings.month_no
  where staff.is_visible = true
    and settings.is_game_enabled = true
    and coalesce(
      nullif(btrim(settings.card_image_url), ''),
      nullif(btrim(staff.image_url), '')
    ) is not null
  order by staff.sort_order, staff.id;
$$;

create or replace function public.auto_assign_unset_game_staff_cards()
returns table (
  staff_id uuid,
  month_no smallint,
  mark text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  staff_record record;
  selected_month smallint;
  selected_mark text;
begin
  if coalesce(auth.role(), '') <> 'service_role'
    and session_user not in ('postgres', 'supabase_admin')
    and not public.is_content_admin()
  then
    raise exception 'Game card administration permission denied.';
  end if;

  for staff_record in
    select staff.id
    from public.staff_members as staff
    where not exists (
      select 1
      from public.game_staff_card_settings as settings
      where settings.staff_id = staff.id
    )
    order by staff.sort_order, staff.id
    for update of staff
  loop
    select months.month_no
    into selected_month
    from public.get_game_month_catalog() as months
    left join public.game_staff_card_settings as settings
      on settings.month_no = months.month_no
      and settings.is_game_enabled = true
    group by months.month_no
    order by count(settings.staff_id), months.month_no
    limit 1;

    select marks.mark
    into selected_mark
    from (
      values
        ('moon'::text, 1),
        ('bell'::text, 2),
        ('fan'::text, 3),
        ('knot'::text, 4)
    ) as marks(mark, sort_order)
    left join public.game_staff_card_settings as settings
      on settings.mark = marks.mark
      and settings.is_game_enabled = true
    group by marks.mark, marks.sort_order
    order by count(settings.staff_id), marks.sort_order
    limit 1;

    insert into public.game_staff_card_settings (
      staff_id,
      month_no,
      mark
    ) values (
      staff_record.id,
      selected_month,
      selected_mark
    )
    on conflict on constraint game_staff_card_settings_pkey do nothing;

    if found then
      staff_id := staff_record.id;
      month_no := selected_month;
      mark := selected_mark;
      return next;
    end if;
  end loop;
end;
$$;

alter table public.game_staff_card_settings enable row level security;

drop policy if exists "game_staff_card_settings_admin_read"
  on public.game_staff_card_settings;
create policy "game_staff_card_settings_admin_read"
on public.game_staff_card_settings
for select
to authenticated
using (public.is_content_admin());

drop policy if exists "game_staff_card_settings_admin_insert"
  on public.game_staff_card_settings;
create policy "game_staff_card_settings_admin_insert"
on public.game_staff_card_settings
for insert
to authenticated
with check (public.is_content_admin());

drop policy if exists "game_staff_card_settings_admin_update"
  on public.game_staff_card_settings;
create policy "game_staff_card_settings_admin_update"
on public.game_staff_card_settings
for update
to authenticated
using (public.is_content_admin())
with check (public.is_content_admin());

drop policy if exists "game_staff_card_settings_admin_delete"
  on public.game_staff_card_settings;
create policy "game_staff_card_settings_admin_delete"
on public.game_staff_card_settings
for delete
to authenticated
using (public.is_content_admin());

revoke all on public.game_staff_card_settings from anon, authenticated;
grant select, insert, update, delete
  on public.game_staff_card_settings
  to authenticated;

revoke all on function public.get_game_month_catalog() from public;
grant execute on function public.get_game_month_catalog()
  to anon, authenticated;

revoke all on function public.get_active_game_staff_cards() from public;
grant execute on function public.get_active_game_staff_cards()
  to anon, authenticated;

revoke all on function public.auto_assign_unset_game_staff_cards() from public;
grant execute on function public.auto_assign_unset_game_staff_cards()
  to authenticated, service_role;
