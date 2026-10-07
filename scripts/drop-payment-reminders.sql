-- drop-payment-reminders.sql — ONE-TIME retirement of the `payment_reminders` table.
-- ============================================================================
-- Context: samaroh-android ADR-095 / migration 011_retire_payment_reminders.sql.
-- Reminder rows are device-local on Android >= 0.20.1 and web never used the table.
--
-- RUN ONLY AFTER EVERY DEVICE RUNS ANDROID >= 0.20.1. A device on an older build still
-- pulls this table on every sync; once it is gone that pull fails (PostgREST 404), the
-- sync engine marks the replica inconsistent and stops planning reminders (ADR-060) —
-- it recovers only by updating the app. Check Menu → About on each phone first.
--
-- WHAT IT DOES (transactional, idempotent):
--   * drops the table (policies and the updated_at trigger go with it, cascade);
--   * drops the `reminder_status` enum (payment_reminders was its only user);
--   * nothing else — bookings, payments and every other table are untouched. Row counts
--     are reported so the owner sees how many stale server rows disappeared.
--
-- Afterwards also delete the seed row in supabase/seed.sql and the step in
-- scripts/cleanup-data.sql (both are already guarded with IF EXISTS / to_regclass, so
-- leaving them is harmless).
-- ============================================================================

begin;

do $$
declare
  n bigint;
begin
  if to_regclass('public.payment_reminders') is not null then
    execute 'select count(*) from public.payment_reminders' into n;
    raise notice 'payment_reminders: dropping table with % rows', n;
    execute 'drop table public.payment_reminders cascade';
  else
    raise notice 'payment_reminders: already gone';
  end if;
end $$;

drop type if exists reminder_status;

commit;
