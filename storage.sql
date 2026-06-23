-- Run this after supabase/schema.sql.
-- The bucket must already exist and be named "heyotsuki-images".
-- Mark the bucket as public in Supabase Dashboard so getPublicUrl() works.
-- staff/ stores normal website photos; game-cards/ stores game-only card art.

drop policy if exists "heyotsuki_images_public_read" on storage.objects;
create policy "heyotsuki_images_public_read"
on storage.objects
for select
to anon, authenticated
using (bucket_id = 'heyotsuki-images');

drop policy if exists "heyotsuki_images_admin_insert" on storage.objects;
create policy "heyotsuki_images_admin_insert"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'heyotsuki-images'
  and (storage.foldername(name))[1] in ('staff', 'game-cards')
  and public.is_content_admin()
);

drop policy if exists "heyotsuki_images_admin_update" on storage.objects;
create policy "heyotsuki_images_admin_update"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'heyotsuki-images'
  and (storage.foldername(name))[1] in ('staff', 'game-cards')
  and public.is_content_admin()
)
with check (
  bucket_id = 'heyotsuki-images'
  and (storage.foldername(name))[1] in ('staff', 'game-cards')
  and public.is_content_admin()
);

drop policy if exists "heyotsuki_images_admin_delete" on storage.objects;
create policy "heyotsuki_images_admin_delete"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'heyotsuki-images'
  and (storage.foldername(name))[1] in ('staff', 'game-cards')
  and public.is_content_admin()
);
