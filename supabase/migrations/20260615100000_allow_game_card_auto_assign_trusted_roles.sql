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

revoke all on function public.auto_assign_unset_game_staff_cards() from public;
grant execute on function public.auto_assign_unset_game_staff_cards()
  to authenticated, service_role;
