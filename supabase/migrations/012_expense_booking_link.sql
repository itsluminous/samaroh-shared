-- 012_expense_booking_link.sql — an expense may be recorded AGAINST a booking (event).
-- Contract: docs/expense-against-event.md (shared) + an ADR in both app repos.
--
-- WHY. The owner records event-specific spend (decoration, catering advance, generator
-- hire) while looking at the booking card. Today that means leaving the card, finding or
-- creating the customer as a party, and typing the event into the notes by hand — and the
-- expense row never remembers which event it belonged to. "Record expense" on the booking
-- card creates a normal ledger entry (party = the booking's customer, direction = paid)
-- and stamps the booking id on it, so the expense list can show an "Event: …" chip that
-- jumps back to the booking.
--
-- WHAT. One nullable FK column + its index. Nothing else changes:
--   * RLS: the expenses policies (002_rls.sql) are row-level on business_id and already
--     cover the new column — no policy touched. Visibility of the LINKED booking is still
--     governed by the bookings policies: a member with expenses.view but not booking.view
--     sees the chip label (event type + dates are copied into the expense notes at
--     creation) but the chip is inert for them (clients gate the navigation).
--   * on delete set null: bookings are only ever HARD-deleted by the operational scripts
--     (scripts/cleanup-data.sql deletes bookings before expenses); the expense row must
--     survive as a plain ledger entry. Soft deletes (deleted_at tombstones) are untouched
--     by FKs — a tombstoned booking keeps its id and the chip simply stops resolving.
--   * Reports: unchanged. booking_id is a back-reference for navigation, not a reporting
--     dimension (expenses still roll up by party / business_related).
--
-- CLIENT CONTRACT (sync). Older app builds never send booking_id: PostgREST inserts
-- NULL for an absent column, so lagging devices keep syncing. Newer builds send
-- `"booking_id": null|uuid` in every expense payload (encodeDefaults), which FAILS with
-- PGRST204 until this column exists — therefore this migration is applied BEFORE the
-- app versions that carry the feature are released (README: "apply new migrations
-- before deploying app versions that read the new columns").
--
-- IDEMPOTENT: add column if not exists / create index if not exists.

alter table expenses
  add column if not exists booking_id uuid null references bookings(id) on delete set null;

-- Expense list "Event" chip resolution + "expenses of this booking" lookups.
create index if not exists idx_expenses_booking on expenses (booking_id)
  where booking_id is not null;

comment on column expenses.booking_id is
  'Optional back-reference to the booking (event) this expense was recorded against from the booking card. NULL = plain ledger entry. Navigation aid only: reports do not group by it. on delete set null (hard deletes happen only via scripts/cleanup-data.sql).';
