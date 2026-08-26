-- cleanup-data.sql — wipe operational data for a business (or all businesses)
-- ============================================================================
-- WHAT IT DOES
--   Hard-deletes ALL operational data while KEEPING accounts and setup:
--     kept   : auth.users, businesses, business_members, business_settings,
--              google_accounts
--     deleted: payment_reminders, booking_payments, bookings, date_blocks,
--              expense_attachments, expenses, parties, inventory_transactions,
--              master_items                     (child tables first, FK-safe)
--   Also resets bookings-dependent state on the kept tables:
--     - businesses.invoice_counter -> 0  (invoice numbers restart from scratch;
--       the numbers themselves lived on the deleted bookings.invoice_number)
--     - business_settings.last_backup_at -> null (any recorded backup described
--       data that no longer exists)
--
-- HOW TO RUN (Supabase SQL editor)
--   1. Open the project's SQL editor (runs as postgres, bypasses RLS).
--   2. Paste this file.
--   3. Set target_business below:
--        - ONE business : keep the uuid literal, paste the business id.
--        - ALL businesses (run-for-all variant): replace the line with
--              target_business uuid := null;
--          A null target makes every "matches(...)" check true, so the wipe
--          applies to EVERY business. Double-check before running!
--   4. Run. The NOTICE at the end reports per-table deleted row counts.
--
-- NOTES
--   - Deletions are HARD deletes (not deleted_at tombstones): synced clients
--     will not see tombstones, so clear their local store (sign out / clear
--     site data) after running this.
--   - expense_attachments rows are metadata pointing at files in the owner's
--     Google Drive; this script removes the rows only and never touches
--     Drive. Generated invoice PDFs / inventory photos in Supabase Storage
--     can optionally be removed with the storage.objects block at the bottom.
-- ============================================================================

do $$
declare
  -- >>> SET THIS: business id to clean, or null for ALL businesses <<<
  target_business uuid := 'PASTE-BUSINESS-ID-HERE';

  n bigint;
  total bigint := 0;
begin
  -- Child tables first so every FK parent is emptied after its children.

  -- 1. payment_reminders (-> bookings, businesses)
  delete from payment_reminders
    where target_business is null or business_id = target_business;
  get diagnostics n = row_count; total := total + n;
  raise notice 'payment_reminders: % deleted', n;

  -- 2. booking_payments (-> bookings, businesses)
  delete from booking_payments
    where target_business is null or business_id = target_business;
  get diagnostics n = row_count; total := total + n;
  raise notice 'booking_payments: % deleted', n;

  -- 3. bookings (-> businesses)
  delete from bookings
    where target_business is null or business_id = target_business;
  get diagnostics n = row_count; total := total + n;
  raise notice 'bookings: % deleted', n;

  -- 4. date_blocks (-> businesses)
  delete from date_blocks
    where target_business is null or business_id = target_business;
  get diagnostics n = row_count; total := total + n;
  raise notice 'date_blocks: % deleted', n;

  -- 5. expense_attachments (-> expenses, businesses)
  delete from expense_attachments
    where target_business is null or business_id = target_business;
  get diagnostics n = row_count; total := total + n;
  raise notice 'expense_attachments: % deleted', n;

  -- 6. expenses (-> parties, businesses)
  delete from expenses
    where target_business is null or business_id = target_business;
  get diagnostics n = row_count; total := total + n;
  raise notice 'expenses: % deleted', n;

  -- 7. parties (-> businesses)
  delete from parties
    where target_business is null or business_id = target_business;
  get diagnostics n = row_count; total := total + n;
  raise notice 'parties: % deleted', n;

  -- 8. inventory_transactions (-> master_items, businesses)
  delete from inventory_transactions
    where target_business is null or business_id = target_business;
  get diagnostics n = row_count; total := total + n;
  raise notice 'inventory_transactions: % deleted', n;

  -- 9. master_items (-> businesses)
  delete from master_items
    where target_business is null or business_id = target_business;
  get diagnostics n = row_count; total := total + n;
  raise notice 'master_items: % deleted', n;

  -- Reset bookings-dependent state on the KEPT tables.
  update businesses
    set invoice_counter = 0
    where (target_business is null or id = target_business)
      and invoice_counter <> 0;
  get diagnostics n = row_count;
  raise notice 'businesses: invoice_counter reset on % row(s)', n;

  update business_settings
    set last_backup_at = null
    where (target_business is null or business_id = target_business)
      and last_backup_at is not null;
  get diagnostics n = row_count;
  raise notice 'business_settings: last_backup_at cleared on % row(s)', n;

  raise notice 'DONE — % data row(s) deleted (accounts, businesses, members, settings and google_accounts kept).', total;
end $$;

-- OPTIONAL: also remove data-dependent FILES from Supabase Storage. The rows
-- above referenced generated invoice PDFs (booking-invoices) and item photos
-- (inventory-images); business logos are setup, not data, and are kept.
-- (Expense attachments live in Google Drive, not Supabase Storage — see
-- 003_storage.sql.) Files live under a "<business_id>/..." prefix. Uncomment
-- to run; drop the "and name like" line for the run-for-all variant.
-- delete from storage.objects
--   where bucket_id in ('booking-invoices', 'inventory-images')
--     and name like 'PASTE-BUSINESS-ID-HERE/%';
