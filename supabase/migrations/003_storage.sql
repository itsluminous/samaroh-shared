-- 003_storage.sql — private storage buckets, RLS'd by business membership.
--
-- Buckets (all PRIVATE): logos, inventory-images, booking-invoices.
-- Path convention: {business_id}/{entity_id}/{filename} — the first path segment is the
-- business UUID, and every policy checks membership/permission against it.
-- Expense invoice attachments do NOT get a bucket — they live in Google Drive; only
-- metadata rows sync (see expense_attachments in 001_schema.sql).
--
-- Write-permission mapping per bucket:
--   logos             -> settings.manage_business (business identity)
--   inventory-images  -> inventory.manage_master_items (item photos)
--   booking-invoices  -> booking.generate_invoice (invoice PDFs)
-- Reads require active membership plus the module's view permission where one exists.

insert into storage.buckets (id, name, public)
values
  ('logos', 'logos', false),
  ('inventory-images', 'inventory-images', false),
  ('booking-invoices', 'booking-invoices', false)
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

-- ============ inventory-images ============
create policy storage_inventory_images_select on storage.objects
  for select using (
    bucket_id = 'inventory-images'
    and has_perm(storage_object_business_id(name), 'inventory', 'view')
  );
create policy storage_inventory_images_insert on storage.objects
  for insert with check (
    bucket_id = 'inventory-images'
    and has_perm(storage_object_business_id(name), 'inventory', 'manage_master_items')
  );
create policy storage_inventory_images_update on storage.objects
  for update using (
    bucket_id = 'inventory-images'
    and has_perm(storage_object_business_id(name), 'inventory', 'manage_master_items')
  )
  with check (
    bucket_id = 'inventory-images'
    and has_perm(storage_object_business_id(name), 'inventory', 'manage_master_items')
  );
create policy storage_inventory_images_delete on storage.objects
  for delete using (
    bucket_id = 'inventory-images'
    and has_perm(storage_object_business_id(name), 'inventory', 'manage_master_items')
  );

-- ============ booking-invoices ============
create policy storage_booking_invoices_select on storage.objects
  for select using (
    bucket_id = 'booking-invoices'
    and has_perm(storage_object_business_id(name), 'booking', 'view')
  );
create policy storage_booking_invoices_insert on storage.objects
  for insert with check (
    bucket_id = 'booking-invoices'
    and has_perm(storage_object_business_id(name), 'booking', 'generate_invoice')
  );
create policy storage_booking_invoices_update on storage.objects
  for update using (
    bucket_id = 'booking-invoices'
    and has_perm(storage_object_business_id(name), 'booking', 'generate_invoice')
  )
  with check (
    bucket_id = 'booking-invoices'
    and has_perm(storage_object_business_id(name), 'booking', 'generate_invoice')
  );
create policy storage_booking_invoices_delete on storage.objects
  for delete using (
    bucket_id = 'booking-invoices'
    and has_perm(storage_object_business_id(name), 'booking', 'delete')
  );
