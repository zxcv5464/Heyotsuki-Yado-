alter table public.orders disable trigger orders_protect_staff_update;

update public.orders
set
  deleted_at = now(),
  delete_reason = 'Phase 2-B-4 automated Discord verification cleanup'
where id = 'c5582d60-5ece-49c3-8da1-9968a96b8d10'
  and customer_name = '系統推播測試';

alter table public.orders enable trigger orders_protect_staff_update;
