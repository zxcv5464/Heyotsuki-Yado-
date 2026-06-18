create table if not exists public.game_scenery_cards (
  id uuid primary key default gen_random_uuid(),
  name text not null check (btrim(name) <> ''),
  month_no smallint not null check (month_no between 1 and 12),
  mark text not null check (mark in ('moon', 'bell', 'fan', 'knot')),
  card_title text,
  image_url text not null check (btrim(image_url) ~ '^https://'),
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists game_scenery_cards_active_distribution_idx
  on public.game_scenery_cards (is_active, month_no, mark);

drop trigger if exists game_scenery_cards_set_updated_at
  on public.game_scenery_cards;
create trigger game_scenery_cards_set_updated_at
before update on public.game_scenery_cards
for each row execute function public.set_updated_at();

alter table public.game_scenery_cards enable row level security;

drop policy if exists "game_scenery_cards_admin_read"
  on public.game_scenery_cards;
create policy "game_scenery_cards_admin_read"
on public.game_scenery_cards
for select
to authenticated
using (public.is_content_admin());

drop policy if exists "game_scenery_cards_admin_insert"
  on public.game_scenery_cards;
create policy "game_scenery_cards_admin_insert"
on public.game_scenery_cards
for insert
to authenticated
with check (public.is_content_admin());

drop policy if exists "game_scenery_cards_admin_update"
  on public.game_scenery_cards;
create policy "game_scenery_cards_admin_update"
on public.game_scenery_cards
for update
to authenticated
using (public.is_content_admin())
with check (public.is_content_admin());

drop policy if exists "game_scenery_cards_admin_delete"
  on public.game_scenery_cards;
create policy "game_scenery_cards_admin_delete"
on public.game_scenery_cards
for delete
to authenticated
using (public.is_content_admin());

revoke all on public.game_scenery_cards from anon, authenticated;
grant select, insert, update, delete
  on public.game_scenery_cards
  to authenticated;

create or replace function public.get_active_game_cards()
returns table (
  card_id uuid,
  card_type text,
  staff_id uuid,
  scenery_id uuid,
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
    staff.id as card_id,
    'staff'::text as card_type,
    staff.id as staff_id,
    null::uuid as scenery_id,
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

  union all

  select
    scenery.id as card_id,
    'scenery'::text as card_type,
    null::uuid as staff_id,
    scenery.id as scenery_id,
    scenery.name,
    btrim(scenery.image_url) as image_url,
    scenery.month_no,
    months.month_label,
    months.season,
    scenery.mark,
    nullif(btrim(scenery.card_title), '') as card_title,
    scenery.sort_order
  from public.game_scenery_cards as scenery
  join public.get_game_month_catalog() as months
    on months.month_no = scenery.month_no
  where scenery.is_active = true
    and btrim(scenery.image_url) ~ '^https://'
  order by sort_order, card_type, card_id;
$$;

revoke all on function public.get_active_game_cards() from public;
grant execute on function public.get_active_game_cards()
  to anon, authenticated;

do $scenery_start_game_room$
declare
  function_sql text;
begin
  select pg_get_functiondef('public.start_game_room(uuid)'::regprocedure)
  into function_sql;

  if function_sql is null then
    raise exception 'start_game_room(uuid) does not exist.';
  end if;

  if position('public.get_active_game_cards()' in function_sql) = 0 then
    function_sql := replace(
      function_sql,
      'card_count integer;',
      'card_count integer;
  designation_card_count integer;'
    );

    function_sql := replace(
      function_sql,
      'select count(*) into card_count from public.get_active_game_staff_cards();',
      'select count(*) into card_count from public.get_active_game_cards();
  select count(*) into designation_card_count from public.get_active_game_staff_cards();'
    );

    function_sql := replace(
      function_sql,
      'turns_per_player <= 0 or card_count < player_count * 3',
      'turns_per_player <= 0 or designation_card_count < player_count * 3'
    );

    function_sql := replace(
      function_sql,
      $$'staffId', card.staff_id,
      'name', card.name,$$,
      $$'staffId', card.card_id,
      'cardType', card.card_type,
      'sourceStaffId', card.staff_id,
      'sceneryId', card.scenery_id,
      'name', card.name,$$
    );

    function_sql := replace(
      function_sql,
      'order by md5(game_seed || '':deck:'' || card.staff_id::text)',
      'order by md5(game_seed || '':deck:'' || card.card_id::text)'
    );

    function_sql := replace(
      function_sql,
      'from public.get_active_game_staff_cards() as card
  where card.image_url ~ ''^https://''',
      'from public.get_active_game_cards() as card
  where card.image_url ~ ''^https://'''
    );

    function_sql := replace(
      function_sql,
      'select distinct card.month_no
    from public.get_active_game_staff_cards() as card',
      'select distinct card.month_no
    from public.get_active_game_cards() as card'
    );

    execute function_sql;
  end if;
end $scenery_start_game_room$;

do $scenery_apply_game_action$
declare
  function_sql text;
begin
  select pg_get_functiondef('public.apply_game_action(uuid, uuid, bigint, text, jsonb)'::regprocedure)
  into function_sql;

  if function_sql is null then
    raise exception 'apply_game_action(uuid, uuid, bigint, text, jsonb) does not exist.';
  end if;

  if position('coalesce(card ->> ''cardType'', ''staff'') = ''staff''' in function_sql) = 0 then
    function_sql := replace(
      function_sql,
      $$where card ->> 'staffId' = next_state -> 'players' -> actor_index ->> 'designatedStaffId'$$,
      $$where coalesce(card ->> 'cardType', 'staff') = 'staff'
              and coalesce(card ->> 'sourceStaffId', card ->> 'staffId')
                = next_state -> 'players' -> actor_index ->> 'designatedStaffId'$$
    );

    execute function_sql;
  end if;
end $scenery_apply_game_action$;

comment on table public.game_scenery_cards
is 'Game-only scenery cards used to increase Hanafuda deck size without creating staff designation targets.';

comment on function public.get_active_game_cards()
is 'Returns active staff cards and scenery cards for newly created Hanafuda games. Staff cards remain the only designation targets.';
