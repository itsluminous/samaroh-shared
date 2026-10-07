-- 011_retire_payment_reminders.sql — `payment_reminders` is RETIRED as a synced table.
-- Decision: samaroh-android docs/decisions.md ADR-095 (2026-10-07).
--
-- WHY. Reminder state is per USER and per DEVICE by the owner's requirement: the same
-- account on two phones keeps independent reminder state (dismissing on one must not
-- dismiss on the other) and two members must never share or overwrite each other's
-- reminder rows. The table never fit that: it was ONE business-wide row set, planned by
-- EVERY device that pulled the bookings (including members with only `booking.view`) and
-- pushed back — where RLS (`booking.record_payment`, 002_rls.sql) rejected a viewer's
-- insert/update forever (Postgres 42501 on a member phone, 2026-10-07). Android ≥ 0.20.1
-- therefore keeps reminder rows DEVICE-LOCAL (Room only; derived from the synced
-- bookings + payments; no outbox op, no pull; wiped on sign-out). Web never read or wrote
-- the table. Nothing consumes it any more.
--
-- WHAT THIS MIGRATION DOES — deliberately NON-destructive:
--   * marks the table retired in the catalog (comment) so the schema itself documents the
--     contract; the rows, the `reminder_status` enum and the RLS policies stay in place.
--   Devices still on Android ≤ 0.20.0 (manually side-loaded releases can lag) keep
--   pushing/pulling until they update, and must not start failing because of this file;
--   0.20.1 drops any queued legacy op on its first sync.
--
-- FOLLOW-UP (owner, one-time, AFTER every device runs ≥ 0.20.1):
--   `scripts/drop-payment-reminders.sql` drops the table, its policies/triggers and the
--   `reminder_status` enum, and removes the seed row. Never fold that into a numbered
--   migration before all devices have moved — a lagging device's pull would then fail
--   (unknown table → PostgREST 404 → the sync engine marks the replica inconsistent and
--   skips every mutating pass, ADR-060).
--
-- IDEMPOTENT: `comment on` only.

comment on table payment_reminders is
  'RETIRED 2026-10-07 (samaroh-android ADR-095): payment/follow-up reminder rows are '
  'device-local on Android >= 0.20.1 and were never used by web; no client reads or '
  'writes this table any more. Kept only so devices on older builds keep syncing until '
  'they update; drop via scripts/drop-payment-reminders.sql once every device is >= 0.20.1.';
