# Expense against an event (booking) — cross-platform contract

Schema: `supabase/migrations/012_expense_booking_link.sql` (`expenses.booking_id uuid null
references bookings(id) on delete set null` + partial index `idx_expenses_booking`). Both
apps implement this document identically; each adds an ADR in its `docs/decisions.md`.

## 1. Entry point — "Record expense" on the booking card

A new action on the booking card/detail, next to *Record payment* / *Invoice*:
`booking.card.action_record_expense` ("Record expense" / "खर्च दर्ज करें").

**Visibility / gating.** Shown only when the member holds **`expenses.create`** (the
permission schema has no `expenses.add`; `create` is the key that lets a member add ledger
entries) **and** can see the card at all (`booking.view`). Owners always see it. Markers
(ADR-041 day-indicator bookings) and **cancelled** bookings do NOT get the action.

**Behaviour.** Opens the EXISTING add-ledger-entry form (Android `AddEntryScreen`, web
expenses entry dialog) pre-filled; nothing is written until the user saves:

| Field | Pre-fill |
|---|---|
| party | the booking's customer — see §2 (resolved/created on SAVE, not on open) |
| direction | `paid` ("You gave"); the switch stays editable |
| amount | empty (required, `> 0`) |
| expense_date | **today** (device-local date, same rule as the plain add-entry form) |
| notes | `expenses.entry.booking_notes_default` = `{eventType} · {dates}` — the localized event-type label (no emoji) and the booking's date or date range exactly as the booking card formats it. Editable; the user may clear it |
| attachments | none |
| booking_id | the booking's id (hidden; not editable) |

On save the client inserts ONE `expenses` row `{party_id, direction, amount, expense_date,
notes, booking_id, business_id, created_by}` through the normal expenses write path
(Android: Room + outbox; web: PostgREST insert). No other row is written for the expense.

## 2. Party resolution (the booking's customer)

Resolved at SAVE time, in this exact order:

1. **Match** an existing **live** party of the business whose `lower(trim(name)) =
   lower(trim(bookings.customer_name))` (tombstoned parties never match — migration 008
   lets a deleted name be re-created). If several live rows match (legacy mixed-case
   twins), take the one with the earliest `created_at`.
2. **Else create** a party `{ name = bookings.customer_name (trimmed), phone =
   bookings.customer_phone (null when blank), business_related = false, notes = null }`
   — a customer is a personal/event counterparty, not a supplier, so they stay out of the
   business financial reports (`parties.business_related` semantics, 001). Creating the
   party requires **`expenses.manage_parties`** (RLS `parties_insert`); a member who holds
   `expenses.create` but NOT `manage_parties`, whose customer has no live party yet, gets
   the blocking message `expenses.entry.party_create_forbidden` (below) and nothing is
   written. The action stays visible for them (they can record against customers who
   already exist as parties); the save is what fails fast, client-side, before any insert.
3. Phone is never back-filled onto an existing party (no silent edits of party data).

## 3. Rendering the link — the "event" chip

Wherever an expense entry is listed (party ledger on both platforms; web expenses home
entry rows if they list entries), a row with `booking_id != null` shows a **small chip**
`expenses.ledger.event_chip` = `Event: {label}` where `{label}` = the linked booking's
customer name (first name per `BookingTitleFormatter.firstName` / web `pillLabel`
convention) + ` · ` + its localized event type — e.g. *Event: Priya · Wedding*. The chip is
rendered as metadata-adjacent content (normal chip component, `labelSmall`/caption size,
tonal/outlined per platform), NOT via `MetadataText` (it is content, not a provenance stamp
— `docs/ui-conventions.md` §1).

- Tap → opens that booking's card (Android: the ADR-098 "open this booking's card" route;
  web: the booking detail dialog on the Booking page). Gated by `booking.view`: without it
  the chip is still shown but non-interactive.
- Booking not resolvable locally (tombstoned, or not yet pulled) → chip shows the label
  from the notes fallback: the first segment of the expense notes if they still start with
  the `booking_notes_default` shape, else the chip is omitted. Never crash, never show a
  bare id.
- Amounts on the row are masked per `expenses.view_amounts` exactly as today; the chip
  never leaks amounts.

The booking card does **not** list its expenses in this iteration (out of scope — no
"expenses of this event" total; reports unchanged).

## 4. Reports — no change

Reports keep rolling expenses up by party / `business_related` / date. `booking_id` is a
navigation back-reference only.

## 5. Sync, backup, model

- **Models**: Android `core:model Expense.bookingId: String? = null`
  (`@SerialName("booking_id")`), Room `expenses.booking_id TEXT` (new DB version +
  migration), entity⇄model mappers; web `Expense.booking_id: string | null` in
  `expenses/_lib` types + every explicit `select(...)` column list.
- **Wire**: additive nullable column; pulls select `*`; pushes include `booking_id`. The
  server column MUST exist before the app builds ship (PGRST204 otherwise) — the owner
  applies 012 first (`~/.luminous/handoff/shared-012-owner-ddl.md`).
- **Backup** (Android `BackupExporter`, `expenses.json`): rows are the serialized model,
  so `booking_id` is exported automatically once the model carries it; the restore path
  must accept its absence (older backups) → null. Update `docs/backup-format.md`.
- **Cleanup**: `scripts/cleanup-data.sql` deletes bookings before expenses — safe because
  the FK is `on delete set null`.

## 6. String keys (this repo, shipped with the contract)

| Key | en | hi |
|---|---|---|
| `booking.card.action_record_expense` | Record expense | खर्च दर्ज करें |
| `expenses.ledger.event_chip` | Event: {label} | कार्यक्रम: {label} |
| `expenses.entry.booking_notes_default` | {eventType} · {dates} | {eventType} · {dates} |
| `expenses.entry.party_create_forbidden` | You can record expenses but not add people. Ask the owner to add {name} first. | आप खर्च दर्ज कर सकते हैं, पर नया व्यक्ति नहीं जोड़ सकते। मालिक से {name} को पहले जोड़ने के लिए कहें। |
