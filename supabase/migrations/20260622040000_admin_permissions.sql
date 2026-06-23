-- Granular back-office permissions. This migration is additive and preserves owner access.

alter table public.admin_profiles
  add column if not exists staff_id uuid references public.staff_members(id) on delete set null,
  add column if not exists permission_template_id uuid;

create unique index if not exists admin_profiles_staff_id_unique_idx
  on public.admin_profiles (staff_id)
  where staff_id is not null;

create table if not exists public.admin_permission_definitions (
  permission_key text primary key,
  label text not null,
  description text,
  category text not null,
  sort_order integer not null default 0,
  is_system boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.admin_permission_templates (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  is_system boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.admin_profiles
  drop constraint if exists admin_profiles_permission_template_id_fkey;
alter table public.admin_profiles
  add constraint admin_profiles_permission_template_id_fkey
  foreign key (permission_template_id)
  references public.admin_permission_templates(id) on delete set null;

create table if not exists public.admin_permission_template_items (
  template_id uuid not null references public.admin_permission_templates(id) on delete cascade,
  permission_key text not null references public.admin_permission_definitions(permission_key) on delete cascade,
  is_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (template_id, permission_key)
);

create table if not exists public.admin_profile_permissions (
  profile_id uuid not null references public.admin_profiles(id) on delete cascade,
  permission_key text not null references public.admin_permission_definitions(permission_key) on delete cascade,
  is_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (profile_id, permission_key)
);

create index if not exists admin_profile_permissions_profile_enabled_idx
  on public.admin_profile_permissions (profile_id, permission_key)
  where is_enabled = true;

drop trigger if exists admin_permission_definitions_set_updated_at on public.admin_permission_definitions;
create trigger admin_permission_definitions_set_updated_at
before update on public.admin_permission_definitions
for each row execute function public.set_updated_at();
drop trigger if exists admin_permission_templates_set_updated_at on public.admin_permission_templates;
create trigger admin_permission_templates_set_updated_at
before update on public.admin_permission_templates
for each row execute function public.set_updated_at();
drop trigger if exists admin_permission_template_items_set_updated_at on public.admin_permission_template_items;
create trigger admin_permission_template_items_set_updated_at
before update on public.admin_permission_template_items
for each row execute function public.set_updated_at();
drop trigger if exists admin_profile_permissions_set_updated_at on public.admin_profile_permissions;
create trigger admin_profile_permissions_set_updated_at
before update on public.admin_profile_permissions
for each row execute function public.set_updated_at();

insert into public.admin_permission_definitions (permission_key, label, description, category, sort_order) values
  ('dashboard.view', '後台首頁', '查看後台首頁。', '後台首頁', 10),
  ('accounts.view', '查看帳號', '查看後台帳號與綁定資訊。', '帳號與權限', 20),
  ('accounts.manage', '管理帳號', '新增、編輯、停用後台帳號。', '帳號與權限', 30),
  ('permissions.manage', '管理權限模板', '維護權限模板與帳號個別權限。', '帳號與權限', 40),
  ('staff.view', '查看員工', '查看完整員工資料。', '員工管理', 50),
  ('staff.manage', '管理員工', '新增、編輯員工與圖片。', '員工管理', 60),
  ('reservations.view', '查看預約', '查看預約資料。', '預約', 70),
  ('reservations.manage', '管理預約', '修改或刪除預約。', '預約', 80),
  ('reservation_form.manage', '管理預約表單', '管理預約日期、時段與欄位。', '預約', 90),
  ('orders.view', '查看訂單', '查看點餐訂單。', '點餐', 100),
  ('orders.manage', '管理訂單', '更新或刪除點餐訂單。', '點餐', 110),
  ('order_specials.manage', '管理品項員工', '管理點餐品項可選員工。', '點餐', 120),
  ('menu.view', '查看菜單', '查看完整菜單設定。', '菜單', 130),
  ('menu.manage', '管理菜單', '管理菜單、品項與加購。', '菜單', 140),
  ('reports.view', '查看報表', '查看與匯出營業報表。', '報表', 150),
  ('payroll.view', '查看薪資', '查看薪資結算。', '薪資', 160),
  ('payroll.manage', '管理薪資', '重算、鎖定與調整薪資。', '薪資', 170),
  ('game_cards.view', '查看遊戲卡', '查看員工遊戲卡設定。', '花牌', 180),
  ('game_cards.manage', '管理遊戲卡', '管理員工遊戲卡設定。', '花牌', 190),
  ('scenery_cards.view', '查看月景牌', '查看月景牌設定。', '花牌', 200),
  ('scenery_cards.manage', '管理月景牌', '管理月景牌設定。', '花牌', 210),
  ('settings.view', '查看網站設定', '查看網站設定。', '系統設定', 220),
  ('settings.manage', '管理網站設定', '修改網站設定。', '系統設定', 230)
on conflict (permission_key) do update
set label = excluded.label,
    description = excluded.description,
    category = excluded.category,
    sort_order = excluded.sort_order,
    is_system = true;

insert into public.admin_permission_templates (name, description, is_system, sort_order) values
  ('Owner', '完整後台權限。', true, 10),
  ('管理員', '日常營運與內容管理，不含帳號、權限與系統最高設定。', true, 20),
  ('櫃檯／營運', '預約、點餐與報表。', true, 30),
  ('薪資管理', '薪資與報表。', true, 40),
  ('菜單管理', '菜單檢視與維護。', true, 50),
  ('卡牌管理', '遊戲卡與月景牌維護。', true, 60),
  ('一般員工', '僅可進入後台首頁。', true, 70)
on conflict (name) do update
set description = excluded.description,
    is_system = true,
    sort_order = excluded.sort_order;

delete from public.admin_permission_template_items
where template_id in (select id from public.admin_permission_templates where is_system = true);

insert into public.admin_permission_template_items (template_id, permission_key)
select templates.id, definitions.permission_key
from public.admin_permission_templates as templates
join public.admin_permission_definitions as definitions on true
where templates.name = 'Owner'
union all
select templates.id, permissions.permission_key
from public.admin_permission_templates as templates
join (values
  ('dashboard.view'), ('staff.view'), ('staff.manage'),
  ('reservations.view'), ('reservations.manage'), ('reservation_form.manage'),
  ('orders.view'), ('orders.manage'), ('order_specials.manage'),
  ('menu.view'), ('menu.manage'), ('reports.view'),
  ('payroll.view'), ('payroll.manage'),
  ('game_cards.view'), ('game_cards.manage'),
  ('scenery_cards.view'), ('scenery_cards.manage'), ('settings.view')
) as permissions(permission_key) on true
where templates.name = '管理員'
union all
select templates.id, permissions.permission_key
from public.admin_permission_templates as templates
join (values
  ('dashboard.view'), ('reservations.view'), ('reservations.manage'),
  ('orders.view'), ('orders.manage'), ('order_specials.manage'), ('reports.view')
) as permissions(permission_key) on true
where templates.name = '櫃檯／營運'
union all
select templates.id, permissions.permission_key
from public.admin_permission_templates as templates
join (values ('dashboard.view'), ('reports.view'), ('payroll.view'), ('payroll.manage')) as permissions(permission_key) on true
where templates.name = '薪資管理'
union all
select templates.id, permissions.permission_key
from public.admin_permission_templates as templates
join (values ('dashboard.view'), ('menu.view'), ('menu.manage')) as permissions(permission_key) on true
where templates.name = '菜單管理'
union all
select templates.id, permissions.permission_key
from public.admin_permission_templates as templates
join (values
  ('dashboard.view'), ('staff.view'),
  ('game_cards.view'), ('game_cards.manage'),
  ('scenery_cards.view'), ('scenery_cards.manage')
) as permissions(permission_key) on true
where templates.name = '卡牌管理'
union all
select templates.id, 'dashboard.view'
from public.admin_permission_templates as templates
where templates.name = '一般員工';

update public.admin_profiles as profiles
set permission_template_id = templates.id
from public.admin_permission_templates as templates
where templates.name = case profiles.role
  when 'owner' then 'Owner'
  when 'admin' then '管理員'
  else '一般員工'
end;

delete from public.admin_profile_permissions;
insert into public.admin_profile_permissions (profile_id, permission_key)
select profiles.id, items.permission_key
from public.admin_profiles as profiles
join public.admin_permission_template_items as items
  on items.template_id = profiles.permission_template_id
where items.is_enabled = true;

-- Preserve existing per-shop staff access when moving to the new global order permissions.
insert into public.admin_profile_permissions (profile_id, permission_key)
select distinct permissions.user_id, 'orders.view'
from public.admin_shop_permissions as permissions
where permissions.can_view_orders
on conflict (profile_id, permission_key) do nothing;
insert into public.admin_profile_permissions (profile_id, permission_key)
select distinct permissions.user_id, 'orders.manage'
from public.admin_shop_permissions as permissions
where permissions.can_update_orders or permissions.can_delete_orders
on conflict (profile_id, permission_key) do nothing;

create or replace function public.has_admin_permission(p_permission_key text)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1 from public.admin_profiles
    where id = auth.uid() and is_active = true and role = 'owner'
  ) or exists (
    select 1
    from public.admin_profiles
    join public.admin_profile_permissions
      on admin_profile_permissions.profile_id = admin_profiles.id
    where admin_profiles.id = auth.uid()
      and admin_profiles.is_active = true
      and admin_profile_permissions.permission_key = p_permission_key
      and admin_profile_permissions.is_enabled = true
  );
$$;

create or replace function public.has_any_admin_permission(p_permission_keys text[])
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1 from unnest(coalesce(p_permission_keys, '{}'::text[])) as requested(permission_key)
    where public.has_admin_permission(requested.permission_key)
  );
$$;

create or replace function public.ensure_admin_permission(p_permission_key text)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if not public.has_admin_permission(p_permission_key) then
    raise exception 'Administrative permission denied: %', p_permission_key;
  end if;
end;
$$;

-- Compatibility helper is deliberately owner-only after this migration.
create or replace function public.is_content_admin()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1 from public.admin_profiles
    where id = auth.uid() and is_active = true and role = 'owner'
  );
$$;

create or replace function public.get_admin_permission_context()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  profile_record public.admin_profiles%rowtype;
begin
  select * into profile_record from public.admin_profiles where id = auth.uid();
  if profile_record.id is null then
    raise exception 'Back-office profile not found.';
  end if;
  return jsonb_build_object(
    'profile', jsonb_build_object(
      'id', profile_record.id, 'displayName', profile_record.display_name,
      'role', profile_record.role, 'isActive', profile_record.is_active,
      'staffId', profile_record.staff_id, 'permissionTemplateId', profile_record.permission_template_id
    ),
    'permissions', case when profile_record.role = 'owner' and profile_record.is_active then
      (select coalesce(jsonb_agg(permission_key order by permission_key), '[]'::jsonb) from public.admin_permission_definitions)
    else (
      select coalesce(jsonb_agg(permission_key order by permission_key), '[]'::jsonb)
      from public.admin_profile_permissions
      where profile_id = profile_record.id and is_enabled
    ) end
  );
end;
$$;

create or replace function public.get_admin_accounts_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth
as $$
begin
  perform public.ensure_admin_permission('accounts.view');
  return jsonb_build_object(
    'accounts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', profiles.id, 'displayName', profiles.display_name, 'email', users.email,
        'role', profiles.role, 'isActive', profiles.is_active, 'staffId', profiles.staff_id,
        'staffName', staff_members.name, 'permissionTemplateId', profiles.permission_template_id,
        'updatedAt', profiles.updated_at,
        'permissions', coalesce((
          select jsonb_agg(profile_permissions.permission_key order by profile_permissions.permission_key)
          from public.admin_profile_permissions as profile_permissions
          where profile_permissions.profile_id = profiles.id and profile_permissions.is_enabled
        ), '[]'::jsonb)
      ) order by profiles.role, profiles.display_name)
      from public.admin_profiles as profiles
      left join auth.users as users on users.id = profiles.id
      left join public.staff_members on staff_members.id = profiles.staff_id
    ), '[]'::jsonb),
    'staffOptions', coalesce((
      select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'isVisible', is_visible) order by sort_order, name)
      from public.staff_members
    ), '[]'::jsonb),
    'definitions', coalesce((
      select jsonb_agg(jsonb_build_object('key', permission_key, 'label', label, 'description', description, 'category', category, 'sortOrder', sort_order) order by sort_order, permission_key)
      from public.admin_permission_definitions
    ), '[]'::jsonb),
    'templates', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', templates.id, 'name', templates.name, 'description', templates.description,
        'isSystem', templates.is_system, 'sortOrder', templates.sort_order,
        'permissions', coalesce((
          select jsonb_agg(items.permission_key order by items.permission_key)
          from public.admin_permission_template_items as items
          where items.template_id = templates.id and items.is_enabled
        ), '[]'::jsonb)
      ) order by templates.sort_order, templates.name)
      from public.admin_permission_templates as templates
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.update_admin_account_permissions(
  p_profile_id uuid,
  p_display_name text,
  p_role text,
  p_staff_id uuid,
  p_is_active boolean,
  p_template_id uuid,
  p_permission_keys text[]
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_profile public.admin_profiles%rowtype;
  target_profile public.admin_profiles%rowtype;
  required_keys text[];
  active_owner_count integer;
begin
  perform public.ensure_admin_permission('accounts.manage');
  select * into caller_profile from public.admin_profiles where id = auth.uid();
  select * into target_profile from public.admin_profiles where id = p_profile_id for update;
  if target_profile.id is null then raise exception 'Account not found.'; end if;
  if p_role not in ('owner', 'admin', 'staff') then raise exception 'Invalid account role.'; end if;
  if nullif(trim(coalesce(p_display_name, '')), '') is null then raise exception 'Display name is required.'; end if;
  if (target_profile.role = 'owner' or p_role = 'owner') and caller_profile.role <> 'owner' then
    raise exception 'Only an owner can change an owner account.';
  end if;
  if p_role = 'staff' and p_staff_id is null then
    raise exception 'Staff accounts must be linked to a staff member.';
  end if;
  if p_staff_id is not null and not exists (select 1 from public.staff_members where id = p_staff_id) then
    raise exception 'Linked staff member was not found.';
  end if;
  if p_staff_id is not null and exists (
    select 1 from public.admin_profiles where staff_id = p_staff_id and id <> p_profile_id
  ) then raise exception 'This staff member is already linked to another account.'; end if;
  if target_profile.role = 'owner' and (p_role <> 'owner' or not coalesce(p_is_active, false)) then
    select count(*) into active_owner_count from public.admin_profiles where role = 'owner' and is_active;
    if active_owner_count <= 1 then raise exception 'The last active owner cannot be changed or disabled.'; end if;
  end if;
  if p_template_id is not null and not exists (select 1 from public.admin_permission_templates where id = p_template_id) then
    raise exception 'Permission template was not found.';
  end if;
  required_keys := array(select distinct permission_key from unnest(coalesce(p_permission_keys, '{}'::text[])) as requested(permission_key));
  required_keys := required_keys || array(
    select replace(permission_key, '.manage', '.view')
    from unnest(required_keys) as requested(permission_key)
    where permission_key like '%.manage'
      and exists (select 1 from public.admin_permission_definitions where permission_key = replace(requested.permission_key, '.manage', '.view'))
  );
  required_keys := array(select distinct permission_key from unnest(required_keys) as requested(permission_key));
  if exists (select 1 from unnest(required_keys) as requested(permission_key) where not exists (select 1 from public.admin_permission_definitions where permission_key = requested.permission_key)) then
    raise exception 'Unknown permission key.';
  end if;
  if caller_profile.role <> 'owner' and ('permissions.manage' = any(required_keys) or 'accounts.manage' = any(required_keys)) then
    raise exception 'Only an owner can grant account or permission management.';
  end if;
  update public.admin_profiles
  set display_name = trim(p_display_name), role = p_role, staff_id = p_staff_id,
      is_active = coalesce(p_is_active, true), permission_template_id = p_template_id
  where id = p_profile_id;
  delete from public.admin_profile_permissions where profile_id = p_profile_id;
  if p_role <> 'owner' then
    insert into public.admin_profile_permissions (profile_id, permission_key)
    select p_profile_id, permission_key from unnest(required_keys) as requested(permission_key);
  end if;
  return public.get_admin_accounts_snapshot();
end;
$$;

create or replace function public.save_admin_permission_template(
  p_template_id uuid,
  p_name text,
  p_description text,
  p_permission_keys text[]
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_id uuid;
begin
  perform public.ensure_admin_permission('permissions.manage');
  if nullif(trim(coalesce(p_name, '')), '') is null then raise exception 'Template name is required.'; end if;
  if p_template_id is not null and exists (select 1 from public.admin_permission_templates where id = p_template_id and is_system) then
    raise exception 'System templates cannot be edited.';
  end if;
  if exists (select 1 from unnest(coalesce(p_permission_keys, '{}'::text[])) as requested(permission_key) where not exists (select 1 from public.admin_permission_definitions where permission_key = requested.permission_key)) then raise exception 'Unknown permission key.'; end if;
  if p_template_id is null then
    insert into public.admin_permission_templates (name, description) values (trim(p_name), nullif(trim(coalesce(p_description, '')), '')) returning id into target_id;
  else
    update public.admin_permission_templates set name = trim(p_name), description = nullif(trim(coalesce(p_description, '')), '') where id = p_template_id returning id into target_id;
  end if;
  delete from public.admin_permission_template_items where template_id = target_id;
  insert into public.admin_permission_template_items (template_id, permission_key)
  select target_id, permission_key from unnest(coalesce(p_permission_keys, '{}'::text[])) as requested(permission_key);
  return public.get_admin_accounts_snapshot();
end;
$$;

create or replace function public.delete_admin_permission_template(p_template_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  perform public.ensure_admin_permission('permissions.manage');
  if exists (select 1 from public.admin_permission_templates where id = p_template_id and is_system) then raise exception 'System templates cannot be deleted.'; end if;
  update public.admin_profiles set permission_template_id = null where permission_template_id = p_template_id;
  delete from public.admin_permission_templates where id = p_template_id;
  return public.get_admin_accounts_snapshot();
end;
$$;

-- Replace current policy helpers with granular permissions.
create or replace function public.can_view_shop_orders(p_shop_key text)
returns boolean language sql stable security definer set search_path = pg_catalog, public as $$
  select p_shop_key in ('menu', 'menu2') and public.has_admin_permission('orders.view');
$$;
create or replace function public.can_update_shop_orders(p_shop_key text)
returns boolean language sql stable security definer set search_path = pg_catalog, public as $$
  select p_shop_key in ('menu', 'menu2') and public.has_admin_permission('orders.manage');
$$;
create or replace function public.can_delete_shop_orders(p_shop_key text)
returns boolean language sql stable security definer set search_path = pg_catalog, public as $$
  select p_shop_key in ('menu', 'menu2') and public.has_admin_permission('orders.manage');
$$;
create or replace function public.is_payroll_admin()
returns boolean language sql stable security definer set search_path = pg_catalog, public as $$
  select public.has_admin_permission('payroll.manage');
$$;

-- Existing payroll snapshot is the sole read RPC; make it view-safe without opening write RPCs.
do $patch_payroll_snapshot$
declare function_sql text; updated_sql text;
begin
  select pg_get_functiondef('public.get_payroll_batch_snapshot(uuid)'::regprocedure) into function_sql;
  updated_sql := replace(function_sql, 'perform public.ensure_payroll_admin();', 'perform public.ensure_admin_permission(''payroll.view'');');
  if function_sql is null or updated_sql = function_sql then raise exception 'Payroll snapshot permission patch did not match expected function body.'; end if;
  execute updated_sql;
end $patch_payroll_snapshot$;

create or replace function public.get_payroll_batch_for_view(
  p_shop_key text,
  p_business_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare target_batch_id uuid;
begin
  perform public.ensure_admin_permission('payroll.view');
  select id into target_batch_id from public.payroll_batches
  where shop_key = p_shop_key and business_date = p_business_date;
  if target_batch_id is null then raise exception 'No payroll batch exists for this business date.'; end if;
  return public.get_payroll_batch_snapshot(target_batch_id);
end;
$$;

do $patch_menu_payroll_rule$
declare function_sql text; updated_sql text;
begin
  select pg_get_functiondef('public.upsert_menu_item_payroll_rule(uuid, text)'::regprocedure) into function_sql;
  updated_sql := replace(function_sql, 'perform public.ensure_payroll_admin();', 'perform public.ensure_admin_permission(''menu.manage'');');
  if function_sql is null or updated_sql = function_sql then raise exception 'Menu payroll rule permission patch did not match expected function body.'; end if;
  execute updated_sql;
end $patch_menu_payroll_rule$;

alter table public.admin_permission_definitions enable row level security;
alter table public.admin_permission_templates enable row level security;
alter table public.admin_permission_template_items enable row level security;
alter table public.admin_profile_permissions enable row level security;

revoke all on public.admin_permission_definitions, public.admin_permission_templates,
  public.admin_permission_template_items, public.admin_profile_permissions from anon, authenticated;
revoke all on function public.has_admin_permission(text), public.has_any_admin_permission(text[]),
  public.ensure_admin_permission(text), public.get_admin_permission_context(),
  public.get_admin_accounts_snapshot(), public.update_admin_account_permissions(uuid, text, text, uuid, boolean, uuid, text[]),
  public.save_admin_permission_template(uuid, text, text, text[]), public.delete_admin_permission_template(uuid) from public;
grant execute on function public.has_admin_permission(text), public.has_any_admin_permission(text[]),
  public.ensure_admin_permission(text), public.get_admin_permission_context(),
  public.get_admin_accounts_snapshot(), public.update_admin_account_permissions(uuid, text, text, uuid, boolean, uuid, text[]),
  public.save_admin_permission_template(uuid, text, text, text[]), public.delete_admin_permission_template(uuid) to authenticated;
revoke all on function public.get_payroll_batch_for_view(text, date) from public;
grant execute on function public.get_payroll_batch_for_view(text, date) to authenticated;

drop policy if exists "profiles_read_own_or_admin" on public.admin_profiles;
drop policy if exists "profiles_admin_insert" on public.admin_profiles;
drop policy if exists "profiles_admin_update" on public.admin_profiles;
drop policy if exists "profiles_admin_delete" on public.admin_profiles;
create policy "profiles_read_own_or_permission"
on public.admin_profiles for select to authenticated
using (id = auth.uid() or public.has_admin_permission('accounts.view'));

-- Content tables: keep public read policies, replace only back-office write controls.
drop policy if exists "site_settings_admin_insert" on public.site_settings;
drop policy if exists "site_settings_admin_update" on public.site_settings;
drop policy if exists "site_settings_admin_delete" on public.site_settings;
create policy "site_settings_permission_write" on public.site_settings for all to authenticated
using (public.has_admin_permission('settings.manage')) with check (public.has_admin_permission('settings.manage'));
drop policy if exists "staff_members_admin_read" on public.staff_members;
drop policy if exists "staff_members_admin_insert" on public.staff_members;
drop policy if exists "staff_members_admin_update" on public.staff_members;
drop policy if exists "staff_members_admin_delete" on public.staff_members;
create policy "staff_members_permission_read" on public.staff_members for select to authenticated using (public.has_admin_permission('staff.view'));
create policy "staff_members_permission_write" on public.staff_members for all to authenticated using (public.has_admin_permission('staff.manage')) with check (public.has_admin_permission('staff.manage'));
drop policy if exists "menus_admin_read" on public.menus;
drop policy if exists "menus_admin_insert" on public.menus;
drop policy if exists "menus_admin_update" on public.menus;
drop policy if exists "menus_admin_delete" on public.menus;
create policy "menus_permission_read" on public.menus for select to authenticated using (public.has_admin_permission('menu.view'));
create policy "menus_permission_write" on public.menus for all to authenticated using (public.has_admin_permission('menu.manage')) with check (public.has_admin_permission('menu.manage'));
drop policy if exists "menu_sections_admin_read" on public.menu_sections;
drop policy if exists "menu_sections_admin_insert" on public.menu_sections;
drop policy if exists "menu_sections_admin_update" on public.menu_sections;
drop policy if exists "menu_sections_admin_delete" on public.menu_sections;
create policy "menu_sections_permission_read" on public.menu_sections for select to authenticated using (public.has_admin_permission('menu.view'));
create policy "menu_sections_permission_write" on public.menu_sections for all to authenticated using (public.has_admin_permission('menu.manage')) with check (public.has_admin_permission('menu.manage'));
drop policy if exists "menu_items_admin_read" on public.menu_items;
drop policy if exists "menu_items_admin_insert" on public.menu_items;
drop policy if exists "menu_items_admin_update" on public.menu_items;
drop policy if exists "menu_items_admin_delete" on public.menu_items;
create policy "menu_items_permission_read" on public.menu_items for select to authenticated using (public.has_admin_permission('menu.view'));
create policy "menu_items_permission_write" on public.menu_items for all to authenticated using (public.has_admin_permission('menu.manage')) with check (public.has_admin_permission('menu.manage'));

-- Reservation and game-card policy replacements.
drop policy if exists "reservations_backoffice_read" on public.reservations;
drop policy if exists "reservations_admin_update" on public.reservations;
drop policy if exists "reservations_admin_delete" on public.reservations;
create policy "reservations_permission_read" on public.reservations for select to authenticated using (public.has_admin_permission('reservations.view'));
create policy "reservations_permission_write" on public.reservations for update to authenticated using (public.has_admin_permission('reservations.manage')) with check (public.has_admin_permission('reservations.manage'));
create policy "reservations_permission_delete" on public.reservations for delete to authenticated using (public.has_admin_permission('reservations.manage'));

create or replace function public.is_backoffice_user()
returns boolean language sql stable security definer set search_path = pg_catalog, public as $$
  select public.has_any_admin_permission(array['reservations.view', 'reservation_form.manage']);
$$;
drop policy if exists "reservation_form_settings_admin_write" on public.reservation_form_settings;
drop policy if exists "reservation_time_slots_admin_write" on public.reservation_time_slots;
drop policy if exists "reservation_date_overrides_admin_write" on public.reservation_date_overrides;
drop policy if exists "reservation_form_fields_admin_write" on public.reservation_form_fields;
drop policy if exists "reservation_form_options_admin_write" on public.reservation_form_options;
create policy "reservation_form_settings_permission_write" on public.reservation_form_settings for all to authenticated using (public.has_admin_permission('reservation_form.manage')) with check (public.has_admin_permission('reservation_form.manage'));
create policy "reservation_time_slots_permission_write" on public.reservation_time_slots for all to authenticated using (public.has_admin_permission('reservation_form.manage')) with check (public.has_admin_permission('reservation_form.manage'));
create policy "reservation_date_overrides_permission_write" on public.reservation_date_overrides for all to authenticated using (public.has_admin_permission('reservation_form.manage')) with check (public.has_admin_permission('reservation_form.manage'));
create policy "reservation_form_fields_permission_write" on public.reservation_form_fields for all to authenticated using (public.has_admin_permission('reservation_form.manage')) with check (public.has_admin_permission('reservation_form.manage'));
create policy "reservation_form_options_permission_write" on public.reservation_form_options for all to authenticated using (public.has_admin_permission('reservation_form.manage')) with check (public.has_admin_permission('reservation_form.manage'));

drop policy if exists "orders_admin_delete" on public.orders;
create policy "orders_permission_delete" on public.orders for delete to authenticated using (public.has_admin_permission('orders.manage'));
drop policy if exists "staff_order_specials_backoffice_read" on public.staff_order_specials;
drop policy if exists "staff_order_specials_admin_write" on public.staff_order_specials;
create policy "staff_order_specials_permission_read" on public.staff_order_specials for select to authenticated using (public.has_any_admin_permission(array['orders.view', 'order_specials.manage']));
create policy "staff_order_specials_permission_write" on public.staff_order_specials for all to authenticated using (public.has_admin_permission('order_specials.manage')) with check (public.has_admin_permission('order_specials.manage'));
drop policy if exists "menu_item_staff_options_admin_read" on public.menu_item_staff_options;
drop policy if exists "menu_item_staff_options_admin_write" on public.menu_item_staff_options;
create policy "menu_item_staff_options_permission_read" on public.menu_item_staff_options for select to authenticated using (public.has_any_admin_permission(array['menu.view', 'order_specials.manage']));
create policy "menu_item_staff_options_permission_write" on public.menu_item_staff_options for all to authenticated using (public.has_any_admin_permission(array['menu.manage', 'order_specials.manage'])) with check (public.has_any_admin_permission(array['menu.manage', 'order_specials.manage']));
drop policy if exists "menu_item_order_options_admin_read" on public.menu_item_order_options;
drop policy if exists "menu_item_order_options_admin_write" on public.menu_item_order_options;
create policy "menu_item_order_options_permission_read" on public.menu_item_order_options for select to authenticated using (public.has_admin_permission('menu.view'));
create policy "menu_item_order_options_permission_write" on public.menu_item_order_options for all to authenticated using (public.has_admin_permission('menu.manage')) with check (public.has_admin_permission('menu.manage'));
drop policy if exists "menu_item_order_option_staff_admin_read" on public.menu_item_order_option_staff;
drop policy if exists "menu_item_order_option_staff_admin_write" on public.menu_item_order_option_staff;
create policy "menu_item_order_option_staff_permission_read" on public.menu_item_order_option_staff for select to authenticated using (public.has_admin_permission('menu.view'));
create policy "menu_item_order_option_staff_permission_write" on public.menu_item_order_option_staff for all to authenticated using (public.has_admin_permission('menu.manage')) with check (public.has_admin_permission('menu.manage'));
drop policy if exists "admin_shop_permissions_read" on public.admin_shop_permissions;
drop policy if exists "admin_shop_permissions_owner_write" on public.admin_shop_permissions;
create policy "admin_shop_permissions_permission_read" on public.admin_shop_permissions for select to authenticated using (user_id = auth.uid() or public.has_admin_permission('accounts.view'));
create policy "admin_shop_permissions_permission_write" on public.admin_shop_permissions for all to authenticated using (public.has_admin_permission('accounts.manage')) with check (public.has_admin_permission('accounts.manage'));

drop policy if exists "game_staff_card_settings_admin_read" on public.game_staff_card_settings;
drop policy if exists "game_staff_card_settings_admin_insert" on public.game_staff_card_settings;
drop policy if exists "game_staff_card_settings_admin_update" on public.game_staff_card_settings;
drop policy if exists "game_staff_card_settings_admin_delete" on public.game_staff_card_settings;
create policy "game_staff_card_settings_permission_read" on public.game_staff_card_settings for select to authenticated using (public.has_admin_permission('game_cards.view'));
create policy "game_staff_card_settings_permission_write" on public.game_staff_card_settings for all to authenticated using (public.has_admin_permission('game_cards.manage')) with check (public.has_admin_permission('game_cards.manage'));
drop policy if exists "game_scenery_cards_admin_read" on public.game_scenery_cards;
drop policy if exists "game_scenery_cards_admin_insert" on public.game_scenery_cards;
drop policy if exists "game_scenery_cards_admin_update" on public.game_scenery_cards;
drop policy if exists "game_scenery_cards_admin_delete" on public.game_scenery_cards;
create policy "game_scenery_cards_permission_read" on public.game_scenery_cards for select to authenticated using (public.has_admin_permission('scenery_cards.view'));
create policy "game_scenery_cards_permission_write" on public.game_scenery_cards for all to authenticated using (public.has_admin_permission('scenery_cards.manage')) with check (public.has_admin_permission('scenery_cards.manage'));

do $patch_game_card_auto_assign$
declare function_sql text; updated_sql text;
begin
  select pg_get_functiondef('public.auto_assign_unset_game_staff_cards()'::regprocedure) into function_sql;
  updated_sql := replace(function_sql, 'and not public.is_content_admin()', 'and not public.has_admin_permission(''game_cards.manage'')');
  if function_sql is null or updated_sql = function_sql then raise exception 'Game card auto-assign permission patch did not match expected function body.'; end if;
  execute updated_sql;
end $patch_game_card_auto_assign$;

do $patch_order_reports$
declare function_sql text; updated_sql text;
begin
  select pg_get_functiondef('public.get_order_report_default_business_date(text)'::regprocedure) into function_sql;
  updated_sql := replace(function_sql, 'if not public.can_view_shop_orders(p_shop_key) then', 'if not public.has_admin_permission(''reports.view'') then');
  if function_sql is null or updated_sql = function_sql then raise exception 'Order report default-date permission patch did not match expected function body.'; end if;
  execute updated_sql;
  select pg_get_functiondef('public.get_order_sales_report(text, date, date, text[])'::regprocedure) into function_sql;
  updated_sql := replace(function_sql, 'if not public.can_view_shop_orders(p_shop_key) then', 'if not public.has_admin_permission(''reports.view'') then');
  if function_sql is null or updated_sql = function_sql then raise exception 'Order report permission patch did not match expected function body.'; end if;
  execute updated_sql;
end $patch_order_reports$;

drop policy if exists "heyotsuki_images_admin_insert" on storage.objects;
drop policy if exists "heyotsuki_images_admin_update" on storage.objects;
drop policy if exists "heyotsuki_images_admin_delete" on storage.objects;
create policy "heyotsuki_images_permission_insert"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'heyotsuki-images' and (
    ((storage.foldername(name))[1] = 'staff' and public.has_admin_permission('staff.manage'))
    or ((storage.foldername(name))[1] = 'game-cards' and (storage.foldername(name))[2] = 'scenery' and public.has_admin_permission('scenery_cards.manage'))
    or ((storage.foldername(name))[1] = 'game-cards' and coalesce((storage.foldername(name))[2], '') <> 'scenery' and public.has_admin_permission('game_cards.manage'))
  )
);
create policy "heyotsuki_images_permission_update"
on storage.objects for update to authenticated
using (
  bucket_id = 'heyotsuki-images' and (
    ((storage.foldername(name))[1] = 'staff' and public.has_admin_permission('staff.manage'))
    or ((storage.foldername(name))[1] = 'game-cards' and (storage.foldername(name))[2] = 'scenery' and public.has_admin_permission('scenery_cards.manage'))
    or ((storage.foldername(name))[1] = 'game-cards' and coalesce((storage.foldername(name))[2], '') <> 'scenery' and public.has_admin_permission('game_cards.manage'))
  )
)
with check (
  bucket_id = 'heyotsuki-images' and (
    ((storage.foldername(name))[1] = 'staff' and public.has_admin_permission('staff.manage'))
    or ((storage.foldername(name))[1] = 'game-cards' and (storage.foldername(name))[2] = 'scenery' and public.has_admin_permission('scenery_cards.manage'))
    or ((storage.foldername(name))[1] = 'game-cards' and coalesce((storage.foldername(name))[2], '') <> 'scenery' and public.has_admin_permission('game_cards.manage'))
  )
);
create policy "heyotsuki_images_permission_delete"
on storage.objects for delete to authenticated
using (
  bucket_id = 'heyotsuki-images' and (
    ((storage.foldername(name))[1] = 'staff' and public.has_admin_permission('staff.manage'))
    or ((storage.foldername(name))[1] = 'game-cards' and (storage.foldername(name))[2] = 'scenery' and public.has_admin_permission('scenery_cards.manage'))
    or ((storage.foldername(name))[1] = 'game-cards' and coalesce((storage.foldername(name))[2], '') <> 'scenery' and public.has_admin_permission('game_cards.manage'))
  )
);
