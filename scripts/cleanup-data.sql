-- cleanup-data.sql — THE data-wipe script: reset all operational data
-- ============================================================================
-- Full reset of operational data for one business (or all businesses), so real
-- data can be re-imported from scratch. Accounts and business setup survive.
--
-- WHAT IT DOES
--   Hard-deletes ALL operational data rows:
--     deleted: payment_reminders, booking_payments, bookings, date_blocks,
--              expense_attachments, expenses, parties, inventory_transactions,
--              master_items                      (child tables first, FK-safe)
--     kept   : auth.users, businesses, business_members, business_settings,
--              google_accounts, event_types
--   event_types are deliberately KEPT: they are per-business
--   user CONFIGURATION (like the business profile / settings), not
--   operational data — a data reset must not wipe the user's preset list.
--   Resets bookings-dependent state on the KEPT tables:
--     - businesses.invoice_counter -> 0 (invoice numbers restart from scratch;
--       the numbers themselves lived on the deleted bookings.invoice_number)
--     - business_settings.last_backup_at -> null (recorded backups described
--       data that no longer exists)
--
-- STORAGE FILES — nothing to wipe
--   Item photos and expense bills live in Google Drive (referenced by
--   master_items.drive_image_id / expense_attachments.drive_file_id) — only
--   metadata rows are removed here; Drive is never touched. Invoice PDFs are
--   generated on demand and never persisted server-side. The only Supabase
--   Storage bucket is 'logos' (business logo = setup, not data), which this
--   script deliberately keeps.
--
-- HOW TO RUN (Supabase SQL editor)
--   1. Open the project's SQL editor (runs as postgres, bypasses RLS).
--   2. Paste this file.
--   3. Set target_business below:
--        - ALL businesses (the default, the full-reset case):
--              target_business uuid := null;
--        - ONE business only: replace null with the business id in quotes:
--              target_business uuid := '00000000-0000-...';
--   4. Run. NOTICEs report per-table deleted row counts.
--
-- NOTES
--   - Deletions are HARD deletes (no deleted_at tombstones): synced clients
--     will not see tombstones, so clear their local store (sign out / clear
--     site data) on every device after running this.
-- ============================================================================

do $$
declare
  -- >>> null = ALL businesses (full reset); or paste one business id <<<
  target_business uuid := null;

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

  raise notice 'DONE — % data row(s) deleted. Kept: auth.users, businesses, business_members, business_settings, google_accounts, event_types.', total;
  raise notice 'Item photos/bills live in Google Drive (not deleted here); the only Storage bucket (logos) is setup and kept.';
end $$;
