-- 014_party_booking_link.sql — an EVENT PARTY remembers the booking it stands for.
-- Contract: docs/expense-against-event.md §2 (revised 2026-10-13) + an ADR in both app repos.
--
-- WHY. Owner feedback on the first cut of "Record expense" (012): the expense must NOT be
-- booked against the customer as a person; it belongs to the EVENT. Every booking that has
-- expenses therefore gets its own party, named `{EventTypeLabel} - {dd-MMM-yyyy} - {Customer}`
-- (e.g. 'Wedding - 20-Oct-2026 - Sandhya Upadhyay'), `business_related = true`, so the event's
-- spend rolls up in the business reports like any supplier ledger. Resolving that party by
-- NAME alone is fragile: the owner may rename the party, the booking's customer name or
-- start date may be edited after the party exists, and two devices offline may spell the
-- label differently. This column makes the link STRUCTURAL: the party row points at its
-- booking, so clients resolve "the party of this booking" by id first and by name only as a
-- fallback, and any expense of that party (even one recorded from the plain ledger, with
-- `expenses.booking_id` NULL) can still offer "Show event".
--
-- WHAT. One nullable FK column + its partial index. Nothing else changes:
--   * RLS: parties policies (002_rls.sql) are row-level on business_id and already cover the
--     column. Creating the party still needs expenses.manage_parties (parties_insert).
--   * on delete set null, mirroring expenses.booking_id (012): bookings are hard-deleted only
--     by scripts/cleanup-data.sql; the party survives as a plain ledger party.
--   * NO unique index on booking_id. Dedup is a CLIENT rule (resolve by booking_id, then by
--     live name, then create); a server-side uniqueness constraint would turn an offline race
--     (two devices each minting the event party) into a 23505 that the outbox retries forever
--     — the same failure mode 008 fixed. The live-name index uq_parties_biz_name (008) still
--     catches the common race (same generated name) at the second insert, and clients treat
--     that 23505 like any party-name collision (re-resolve, then retry the expense).
--   * expenses.booking_id (012) is unchanged and remains the PER-EXPENSE link; this column is
--     the PER-PARTY link. Both are navigation back-references, never a reporting dimension.
--
-- CLIENT CONTRACT (sync). Older app builds never send parties.booking_id: PostgREST inserts
-- NULL for an absent column, so lagging devices keep syncing. Newer builds send
-- `"booking_id": null|uuid` in every party payload, which FAILS with PGRST204 until this
-- column exists — therefore this migration is applied BEFORE the app versions that carry the
-- revised contract are released (README: "apply new migrations before deploying app versions
-- that read the new columns").
--
-- IDEMPOTENT: add column if not exists / create index if not exists.

alter table parties
  add column if not exists booking_id uuid null references bookings(id) on delete set null;

-- "The event party of this booking" lookup (client resolution step 1) + "Show event" from a
-- party ledger header.
create index if not exists idx_parties_booking on parties (booking_id)
  where booking_id is not null;

comment on column parties.booking_id is
  'Set when this party IS the event party of a booking (name "{EventTypeLabel} - {dd-MMM-yyyy} - {Customer}", created by "Record expense" on the booking card). NULL = ordinary party. Structural link used to reuse the party across renames and to offer "Show event" from its ledger; reports never group by it. on delete set null (hard deletes happen only via scripts/cleanup-data.sql). Not unique: clients dedup (by booking_id, then live name) before inserting.';
