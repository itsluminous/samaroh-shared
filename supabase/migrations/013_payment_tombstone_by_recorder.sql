-- 013_payment_tombstone_by_recorder.sql — whoever may RECORD a payment may also DELETE one.
-- Decision: samaroh-android docs/decisions.md ADR-105 (2026-10-13); web mirrors the gate.
--
-- WHY. The booking card gains a trash icon per payment-history row ("Delete payment",
-- confirmation dialog, due recalculated). The client gate is the SAME permission that
-- allows recording — `booking.record_payment` (or owner): a member who can add a payment
-- must be able to take a wrong one back without owning the whole booking. The app
-- soft-deletes: a DELETE outbox op becomes a PostgREST PATCH setting `deleted_at`
-- (+ `updated_at`) — an SQL UPDATE, never a row delete. 002_rls.sql only lets
-- `booking.edit` holders UPDATE `booking_payments`, so a record_payment-only member's
-- tombstone would be rejected with 42501 and the outbox would retry forever.
--
-- WHAT. One ADDITIONAL permissive policy (policies OR together), scoped to the tombstone
-- transition only:
--   * USING      — the row is still live and the caller holds `booking.record_payment`;
--   * WITH CHECK — the resulting row IS a tombstone (`deleted_at is not null`) and the
--                  caller holds `booking.record_payment`.
-- So a record_payment-only member can turn a live payment into a tombstone and nothing
-- else: not edit a live amount (new row must be tombstoned), not un-delete (old row must
-- be live). `booking.edit` holders keep the unrestricted `booking_payments_update` policy
-- from 002. SELECT / INSERT / DELETE policies are untouched; no column, index or trigger
-- changes. Idempotent (drop policy if exists, then create).
--
-- CLIENT CONTRACT. Apply BEFORE installing the Android build / deploying the web build
-- that carry the trash icon (README: "apply new migrations before deploying app versions
-- that read the new columns" — here: that issue the new write). Older clients never issue
-- a payment tombstone, so applying it early is harmless; owners and `booking.edit` holders
-- already pass the 002 policy, so only record_payment-only members depend on this file.

drop policy if exists booking_payments_tombstone_by_recorder on booking_payments;
create policy booking_payments_tombstone_by_recorder on booking_payments
  for update
  using (
    deleted_at is null
    and has_perm(business_id, 'booking', 'record_payment')
  )
  with check (
    deleted_at is not null
    and has_perm(business_id, 'booking', 'record_payment')
  );

comment on policy booking_payments_tombstone_by_recorder on booking_payments is
  'ADR-105 (android, 2026-10-13): booking.record_payment holders may soft-delete (tombstone) a live payment — the only UPDATE they may perform on this table; booking.edit keeps the unrestricted booking_payments_update policy.';
