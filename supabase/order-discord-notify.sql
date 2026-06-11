-- Allow the order Discord Edge Function service role to update notification
-- metadata while retaining the existing owner/admin/staff restrictions.

create or replace function public.protect_order_update()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if auth.role() = 'service_role' then
    return new;
  end if;

  if current_setting('heyotsuki.order_submit', true) = 'on' then
    return new;
  end if;

  -- Compatibility for an older submit_order RPC that updates only the
  -- calculated total before the transaction-local flag was introduced.
  if auth.role() = 'anon'
    and old.shop_key = new.shop_key
    and old.customer_name is not distinct from new.customer_name
    and old.contact is not distinct from new.contact
    and old.note is not distinct from new.note
    and old.requested_time is not distinct from new.requested_time
    and old.business_date is not distinct from new.business_date
    and old.status is not distinct from new.status
    and old.admin_note is not distinct from new.admin_note
    and old.discord_status is not distinct from new.discord_status
    and old.discord_attempts is not distinct from new.discord_attempts
    and old.discord_last_error is not distinct from new.discord_last_error
    and old.discord_notified_at is not distinct from new.discord_notified_at
    and old.deleted_at is not distinct from new.deleted_at
    and old.deleted_by is not distinct from new.deleted_by
    and old.delete_reason is not distinct from new.delete_reason
    and old.created_at is not distinct from new.created_at
  then
    return new;
  end if;

  if public.is_owner() or public.is_admin() then
    return new;
  end if;

  if not public.is_staff() then
    raise exception 'Order update permission denied.';
  end if;

  if old.deleted_at is not null then
    raise exception 'Deleted orders cannot be changed by staff.';
  end if;

  if old.shop_key <> new.shop_key
    or old.customer_name is distinct from new.customer_name
    or old.contact is distinct from new.contact
    or old.note is distinct from new.note
    or old.requested_time is distinct from new.requested_time
    or old.business_date is distinct from new.business_date
    or old.total_amount_snapshot is distinct from new.total_amount_snapshot
    or old.discord_status is distinct from new.discord_status
    or old.discord_attempts is distinct from new.discord_attempts
    or old.discord_last_error is distinct from new.discord_last_error
    or old.discord_notified_at is distinct from new.discord_notified_at
    or old.created_at is distinct from new.created_at
  then
    raise exception 'Staff may only update order status and admin note.';
  end if;

  if old.deleted_at is null and new.deleted_at is not null then
    if not public.can_delete_shop_orders(old.shop_key) then
      raise exception 'Order delete permission denied.';
    end if;
    if new.deleted_by is distinct from auth.uid() then
      raise exception 'Deleted order must record the current user.';
    end if;
  elsif old.deleted_at is distinct from new.deleted_at
    or old.deleted_by is distinct from new.deleted_by
    or old.delete_reason is distinct from new.delete_reason
  then
    raise exception 'Order delete fields cannot be changed.';
  end if;

  if not public.can_update_shop_orders(old.shop_key)
    and (
      old.status is distinct from new.status
      or old.admin_note is distinct from new.admin_note
    )
  then
    raise exception 'Order update permission denied.';
  end if;

  return new;
end;
$$;
