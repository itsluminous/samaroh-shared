-- 003_storage.sql — private storage buckets, RLS'd by business membership.
--
-- ONE bucket (PRIVATE): logos — the business logo, the ONLY image that lives in
-- Supabase Storage. Every other image lives in Google Drive:
--   - inventory item photos  -> Drive files referenced by master_items.drive_image_id
--   - expense bill photos/PDFs -> Drive files referenced by expense_attachments.drive_file_id
--   - invoice PDFs -> generated on demand and shared directly; never persisted server-side
-- (The legacy 'inventory-images' and 'booking-invoices' buckets are gone — nothing
-- writes to them; scripts/alter-drop-image-path.sql retires them on an existing DB.)
--
-- Path convention: {business_id}/{filename} — the first path segment is the business
-- UUID, and every policy checks membership/permission against it.
--
-- Write-permission mapping:
--   logos -> settings.manage_business (business identity)
-- Reads require active membership.

insert into storage.buckets (id, name, public)
values
  ('logos', 'logos', false)
on conflict (id) do nothing;

-- Helper: extract the business id from the object path ({business_id}/...).
create or replace function storage_object_business_id(object_name text)
returns uuid
language sql
immutable
as $$
  select nullif((string_to_array(object_name, '/'))[1], '')::uuid;
$$;

-- ============ logos ============
create policy storage_logos_select on storage.objects
  for select using (
    bucket_id = 'logos'
    and is_active_member(storage_object_business_id(name))
  );
create policy storage_logos_insert on storage.objects
  for insert with check (
    bucket_id = 'logos'
    and has_perm(storage_object_business_id(name), 'settings', 'manage_business')
  );
create policy storage_logos_update on storage.objects
  for update using (
    bucket_id = 'logos'
    and has_perm(storage_object_business_id(name), 'settings', 'manage_business')
  )
  with check (
    bucket_id = 'logos'
    and has_perm(storage_object_business_id(name), 'settings', 'manage_business')
  );
create policy storage_logos_delete on storage.objects
  for delete using (
    bucket_id = 'logos'
    and has_perm(storage_object_business_id(name), 'settings', 'manage_business')
  );
