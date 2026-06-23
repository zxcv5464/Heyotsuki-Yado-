-- Run this in Supabase SQL Editor only after creating the user in
-- Authentication > Users.
--
-- Replace the placeholder id with the user's UUID shown in Auth.
-- This privileged SQL Editor bootstrap is necessary because no content
-- administrator exists yet to satisfy the normal RLS write policy.

insert into public.admin_profiles (
  id,
  display_name,
  role,
  is_active
) values (
  '這裡填入 Supabase Auth user id',
  '吹雪',
  'owner',
  true
);
