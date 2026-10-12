-- clear-import-payment-notes.sql — one-time: drop the import markers from payment notes.
-- ============================================================================
-- The 2026-08 booking import (Planning/import-bookings.sql, not in any repo) stamped
-- every imported advance / settlement with booking_payments.notes such as
--   'Imported — settled on event day', 'Imported — "rs"', 'Imported'
-- Those notes print in the invoice payment table's Notes column and in the text receipt
-- ("Imported" on a customer's bill — docs/invoice-layout.md). They carry no customer
-- meaning, so this script nulls them. Genuine per-payment notes (cheque numbers etc.) are
-- untouched: only notes that START with 'Imported' are cleared.
--
-- HOW TO RUN (Supabase SQL editor, runs as postgres): paste, optionally set
-- target_business, run. Idempotent — a second run clears 0 rows.
-- updated_at is bumped so synced clients pull the cleared notes (LWW).
-- ============================================================================
do $$
declare
  target_business uuid := null;   -- null = every business; or '00000000-0000-...'
  v_count int;
begin
  update booking_payments
     set notes = null,
         updated_at = now()
   where notes like 'Imported%'
     and (target_business is null or business_id = target_business)
  ;
  get diagnostics v_count = row_count;
  raise notice 'booking_payments: cleared import notes on % rows', v_count;
end
$$;
