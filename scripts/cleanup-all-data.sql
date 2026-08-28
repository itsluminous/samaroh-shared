-- cleanup-all-data.sql — FULL RESET: wipe all operational data AND stored files
-- ============================================================================
-- Pre-launch full reset: wipe EVERYTHING except accounts and business setup,
-- so real data can be re-imported from scratch.
--
-- WHAT IT DOES
--   Hard-deletes ALL operational data rows:
--     deleted: payment_reminders, booking_payments, bookings, date_blocks,
--              expense_attachments, expenses, parties, inventory_transactions,
--              master_items                      (child tables first, FK-safe)
--     kept   : auth.users, businesses, business_members, business_settings,
--              google_accounts, event_types
--   event_types (migration 006) are deliberately KEPT: they are per-business
--   user CONFIGURATION (like the business profile / settings), not
--   operational data — a full data reset must not wipe the user's preset list.
--   Resets bookings-dependent state on the KEPT tables:
--     - businesses.invoice_counter -> 0 (invoice numbers restart from scratch)
--     - business_settings.last_backup_at -> null (recorded backups described
--       data that no longer exists)
--   ALSO deletes stored FILES (unlike cleanup-data.sql, where this is an
--   opt-in footer):
--     wiped: storage.objects in 'booking-invoices' (generated invoice PDFs)
--            and 'inventory-images' (item photos) — both describe deleted rows
--     kept : the 'logos' bucket, untouched — business logos are setup, not
--            data. (Expense attachment files live in the owner's Google
--            Drive, not Supabase Storage; this script never touches Drive —
--            only the expense_attachments metadata rows are removed.)
--
-- HOW TO RUN (Supabase SQL editor, service role)
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
--   - Storage objects live under a "<business_id>/..." name prefix, which is
--     what the per-business filter matches on.
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

  -- Stored FILES for the deleted rows: invoice PDFs + inventory photos.
  -- The 'logos' bucket is deliberately NOT listed — logos are business setup.
  delete from storage.objects
    where bucket_id in ('booking-invoices', 'inventory-images')
      and (target_business is null or name like target_business::text || '/%');
  get diagnostics n = row_count;
  raise notice 'storage.objects (booking-invoices, inventory-images): % deleted (logos kept)', n;

  raise notice 'DONE — % data row(s) deleted. Kept: auth.users, businesses, business_members, business_settings, google_accounts, event_types, logos bucket.', total;
end $$;
