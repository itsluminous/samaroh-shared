-- alter-drop-image-path.sql — one-time convergence of an EXISTING deployment on the
-- final image architecture (Drive-referenced item photos; logos-only Storage).
--
-- HISTORY NOTE: this script was referenced by 003_storage.sql / README / AGENTS since
-- the baseline consolidation (commit cc89bb2) but was never committed — an existing
-- deployment may have been converged by hand instead. Every statement below is
-- idempotent, so running it against an already-converged database is a safe no-op.
-- Fresh databases built from the consolidated baseline do NOT need this script.
--
-- WHAT IT DOES (mirrors what the baseline no longer creates):
--   1. Recreates get_current_inventory WITHOUT the image_path output column.
--      (DROP + CREATE — `create or replace` cannot change a function's return type.)
--   2. Drops master_items.image_path — the column no longer syncs; item photos are
--      referenced by drive_image_id, the local path is device-only.
--   3. Drops the retired inventory-images / booking-invoices storage policies.
--   4. Deletes the retired inventory-images / booking-invoices bucket rows.
--
-- RUN AFTER all devices run an app version that no longer pushes image_path.
-- Run in the Supabase SQL editor (as postgres) or via psql.

begin;

-- 1. get_current_inventory without image_path (must match 001_schema.sql exactly).
drop function if exists get_current_inventory(uuid);
create or replace function get_current_inventory(p_business_id uuid)
returns table (
  master_item_id uuid,
  name text,
  unit text,
  current_quantity numeric,
  current_value numeric,
  last_transaction_at timestamptz
)
language sql
stable
as $$
  select
    mi.id as master_item_id,
    mi.name,
    mi.unit,
    coalesce(sum(
      case t.transaction_type when 'add' then t.quantity else -t.quantity end
    ), 0) as current_quantity,
    coalesce(sum(
      case when t.transaction_type = 'add' then t.remaining_quantity * t.unit_price else 0 end
    ), 0) as current_value,
    max(t.transaction_date) as last_transaction_at
  from master_items mi
  left join inventory_transactions t
    on t.master_item_id = mi.id and t.deleted_at is null
  where mi.business_id = p_business_id
    and mi.deleted_at is null
  group by mi.id, mi.name, mi.unit;
$$;

-- 2. Drop the retired column.
alter table master_items drop column if exists image_path;

-- 3. Retired storage policies (same list destroy-everything.sql clears).
drop policy if exists storage_inventory_images_select on storage.objects;
drop policy if exists storage_inventory_images_insert on storage.objects;
drop policy if exists storage_inventory_images_update on storage.objects;
drop policy if exists storage_inventory_images_delete on storage.objects;
drop policy if exists storage_booking_invoices_select on storage.objects;
drop policy if exists storage_booking_invoices_insert on storage.objects;
drop policy if exists storage_booking_invoices_update on storage.objects;
drop policy if exists storage_booking_invoices_delete on storage.objects;

-- 4. Retired bucket rows. Object rows must go first (FK). Hosted Supabase (and newer
--    local stacks) block direct SQL deletes on storage tables (42501, or the
--    storage.protect_delete() trigger) — both deletes are therefore guarded: on
--    failure the script still completes and tells you to remove the two buckets from
--    the dashboard instead (Storage → bucket → delete). Leftover empty bucket rows
--    are harmless; nothing in the app references them.
do $$
begin
  delete from storage.objects where bucket_id in ('inventory-images', 'booking-invoices');
  delete from storage.buckets where id in ('inventory-images', 'booking-invoices');
  raise notice 'Retired inventory-images / booking-invoices bucket rows removed.';
exception when others then
  raise notice 'Could not delete the retired buckets via SQL (%). Delete the inventory-images and booking-invoices buckets from the dashboard instead.', sqlerrm;
end $$;

commit;
