create extension if not exists pgcrypto;

create table if not exists public.admin_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  role text not null check (role in ('owner', 'admin', 'staff')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.site_settings (
  key text primary key,
  value text not null,
  description text,
  updated_at timestamptz not null default now()
);

create table if not exists public.staff_members (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  subtitle text,
  quote text,
  role text,
  image_url text,
  is_visible boolean not null default true,
  is_reservable boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.menus (
  key text primary key,
  title text not null,
  short_title text not null,
  english_title text,
  description text,
  href text not null,
  theme text,
  is_visible boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.menu_sections (
  id uuid primary key default gen_random_uuid(),
  menu_key text not null references public.menus(key) on update cascade on delete cascade,
  title text not null,
  subtitle text,
  notice text,
  layout_type text not null default 'detailed',
  is_visible boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.menu_items (
  id uuid primary key default gen_random_uuid(),
  section_id uuid not null references public.menu_sections(id) on delete cascade,
  name text not null,
  description text,
  price text not null,
  featured boolean not null default false,
  is_visible boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists staff_members_public_order_idx
  on public.staff_members (is_visible, sort_order);
create index if not exists menus_public_order_idx
  on public.menus (is_visible, sort_order);
create index if not exists menu_sections_menu_order_idx
  on public.menu_sections (menu_key, is_visible, sort_order);
create index if not exists menu_items_section_order_idx
  on public.menu_items (section_id, is_visible, sort_order);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists admin_profiles_set_updated_at on public.admin_profiles;
create trigger admin_profiles_set_updated_at
before update on public.admin_profiles
for each row execute function public.set_updated_at();

drop trigger if exists site_settings_set_updated_at on public.site_settings;
create trigger site_settings_set_updated_at
before update on public.site_settings
for each row execute function public.set_updated_at();

drop trigger if exists staff_members_set_updated_at on public.staff_members;
create trigger staff_members_set_updated_at
before update on public.staff_members
for each row execute function public.set_updated_at();

drop trigger if exists menus_set_updated_at on public.menus;
create trigger menus_set_updated_at
before update on public.menus
for each row execute function public.set_updated_at();

drop trigger if exists menu_sections_set_updated_at on public.menu_sections;
create trigger menu_sections_set_updated_at
before update on public.menu_sections
for each row execute function public.set_updated_at();

drop trigger if exists menu_items_set_updated_at on public.menu_items;
create trigger menu_items_set_updated_at
before update on public.menu_items
for each row execute function public.set_updated_at();

create or replace function public.is_content_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.admin_profiles
    where id = auth.uid()
      and role in ('owner', 'admin')
      and is_active = true
  );
$$;

revoke all on function public.is_content_admin() from public;
grant execute on function public.is_content_admin() to authenticated;

alter table public.admin_profiles enable row level security;
alter table public.site_settings enable row level security;
alter table public.staff_members enable row level security;
alter table public.menus enable row level security;
alter table public.menu_sections enable row level security;
alter table public.menu_items enable row level security;

drop policy if exists "profiles_read_own_or_admin" on public.admin_profiles;
create policy "profiles_read_own_or_admin"
on public.admin_profiles
for select
to authenticated
using (id = auth.uid() or public.is_content_admin());

drop policy if exists "profiles_admin_insert" on public.admin_profiles;
create policy "profiles_admin_insert"
on public.admin_profiles
for insert
to authenticated
with check (public.is_content_admin());

drop policy if exists "profiles_admin_update" on public.admin_profiles;
create policy "profiles_admin_update"
on public.admin_profiles
for update
to authenticated
using (public.is_content_admin())
with check (public.is_content_admin());

drop policy if exists "profiles_admin_delete" on public.admin_profiles;
create policy "profiles_admin_delete"
on public.admin_profiles
for delete
to authenticated
using (public.is_content_admin());

drop policy if exists "site_settings_public_read" on public.site_settings;
create policy "site_settings_public_read"
on public.site_settings
for select
to anon, authenticated
using (true);

drop policy if exists "site_settings_admin_write" on public.site_settings;
drop policy if exists "site_settings_admin_read" on public.site_settings;
create policy "site_settings_admin_read"
on public.site_settings
for select
to authenticated
using (public.is_content_admin());

drop policy if exists "site_settings_admin_insert" on public.site_settings;
create policy "site_settings_admin_insert"
on public.site_settings
for insert
to authenticated
with check (public.is_content_admin());

drop policy if exists "site_settings_admin_update" on public.site_settings;
create policy "site_settings_admin_update"
on public.site_settings
for update
to authenticated
using (public.is_content_admin())
with check (public.is_content_admin());

drop policy if exists "site_settings_admin_delete" on public.site_settings;
create policy "site_settings_admin_delete"
on public.site_settings
for delete
to authenticated
using (public.is_content_admin());

drop policy if exists "staff_members_public_read" on public.staff_members;
create policy "staff_members_public_read"
on public.staff_members
for select
to anon, authenticated
using (is_visible = true);

drop policy if exists "staff_members_admin_write" on public.staff_members;
drop policy if exists "staff_members_admin_read" on public.staff_members;
create policy "staff_members_admin_read"
on public.staff_members
for select
to authenticated
using (public.is_content_admin());

drop policy if exists "staff_members_admin_insert" on public.staff_members;
create policy "staff_members_admin_insert"
on public.staff_members
for insert
to authenticated
with check (public.is_content_admin());

drop policy if exists "staff_members_admin_update" on public.staff_members;
create policy "staff_members_admin_update"
on public.staff_members
for update
to authenticated
using (public.is_content_admin())
with check (public.is_content_admin());

drop policy if exists "staff_members_admin_delete" on public.staff_members;
create policy "staff_members_admin_delete"
on public.staff_members
for delete
to authenticated
using (public.is_content_admin());

drop policy if exists "menus_public_read" on public.menus;
create policy "menus_public_read"
on public.menus
for select
to anon, authenticated
using (is_visible = true);

drop policy if exists "menus_admin_write" on public.menus;
drop policy if exists "menus_admin_read" on public.menus;
create policy "menus_admin_read"
on public.menus
for select
to authenticated
using (public.is_content_admin());

drop policy if exists "menus_admin_insert" on public.menus;
create policy "menus_admin_insert"
on public.menus
for insert
to authenticated
with check (public.is_content_admin());

drop policy if exists "menus_admin_update" on public.menus;
create policy "menus_admin_update"
on public.menus
for update
to authenticated
using (public.is_content_admin())
with check (public.is_content_admin());

drop policy if exists "menus_admin_delete" on public.menus;
create policy "menus_admin_delete"
on public.menus
for delete
to authenticated
using (public.is_content_admin());

drop policy if exists "menu_sections_public_read" on public.menu_sections;
create policy "menu_sections_public_read"
on public.menu_sections
for select
to anon, authenticated
using (
  is_visible = true
  and exists (
    select 1
    from public.menus
    where menus.key = menu_sections.menu_key
      and menus.is_visible = true
  )
);

drop policy if exists "menu_sections_admin_write" on public.menu_sections;
drop policy if exists "menu_sections_admin_read" on public.menu_sections;
create policy "menu_sections_admin_read"
on public.menu_sections
for select
to authenticated
using (public.is_content_admin());

drop policy if exists "menu_sections_admin_insert" on public.menu_sections;
create policy "menu_sections_admin_insert"
on public.menu_sections
for insert
to authenticated
with check (public.is_content_admin());

drop policy if exists "menu_sections_admin_update" on public.menu_sections;
create policy "menu_sections_admin_update"
on public.menu_sections
for update
to authenticated
using (public.is_content_admin())
with check (public.is_content_admin());

drop policy if exists "menu_sections_admin_delete" on public.menu_sections;
create policy "menu_sections_admin_delete"
on public.menu_sections
for delete
to authenticated
using (public.is_content_admin());

drop policy if exists "menu_items_public_read" on public.menu_items;
create policy "menu_items_public_read"
on public.menu_items
for select
to anon, authenticated
using (
  is_visible = true
  and exists (
    select 1
    from public.menu_sections
    join public.menus on menus.key = menu_sections.menu_key
    where menu_sections.id = menu_items.section_id
      and menu_sections.is_visible = true
      and menus.is_visible = true
  )
);

drop policy if exists "menu_items_admin_write" on public.menu_items;
drop policy if exists "menu_items_admin_read" on public.menu_items;
create policy "menu_items_admin_read"
on public.menu_items
for select
to authenticated
using (public.is_content_admin());

drop policy if exists "menu_items_admin_insert" on public.menu_items;
create policy "menu_items_admin_insert"
on public.menu_items
for insert
to authenticated
with check (public.is_content_admin());

drop policy if exists "menu_items_admin_update" on public.menu_items;
create policy "menu_items_admin_update"
on public.menu_items
for update
to authenticated
using (public.is_content_admin())
with check (public.is_content_admin());

drop policy if exists "menu_items_admin_delete" on public.menu_items;
create policy "menu_items_admin_delete"
on public.menu_items
for delete
to authenticated
using (public.is_content_admin());

revoke all on public.admin_profiles from anon, authenticated;
revoke all on public.site_settings from anon, authenticated;
revoke all on public.staff_members from anon, authenticated;
revoke all on public.menus from anon, authenticated;
revoke all on public.menu_sections from anon, authenticated;
revoke all on public.menu_items from anon, authenticated;

grant select on public.site_settings to anon, authenticated;
grant select on public.staff_members to anon, authenticated;
grant select on public.menus to anon, authenticated;
grant select on public.menu_sections to anon, authenticated;
grant select on public.menu_items to anon, authenticated;

grant select, insert, update, delete on public.admin_profiles to authenticated;
grant insert, update, delete on public.site_settings to authenticated;
grant insert, update, delete on public.staff_members to authenticated;
grant insert, update, delete on public.menus to authenticated;
grant insert, update, delete on public.menu_sections to authenticated;
grant insert, update, delete on public.menu_items to authenticated;
