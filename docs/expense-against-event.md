# Expense against an event (booking) — cross-platform contract

**Revision 2 (2026-10-13)** — owner feedback on revision 1: the expense is the EVENT's,
not the customer's. §2 (party rule) is rewritten; §3 and §3b (Show event, Expenses
history on the booking card) are new. Both apps implement this document identically and
add an ADR in their `docs/decisions.md`.

Schema:
- `supabase/migrations/012_expense_booking_link.sql` — `expenses.booking_id uuid null
  references bookings(id) on delete set null` + partial index `idx_expenses_booking`.
  The **per-expense** link (unchanged by revision 2).
- `supabase/migrations/014_party_booking_link.sql` — `parties.booking_id uuid null
  references bookings(id) on delete set null` + partial index `idx_parties_booking`.
  The **per-party** link: the event party points at its booking. Additive, no RLS
  change, no uniqueness constraint (see the file header for why).

## 1. Entry point — "Record expense" on the booking card

A new action on the booking card/detail, next to *Record payment* / *Invoice*:
`booking.card.action_record_expense` ("Record expense" / "खर्च दर्ज करें").

**Visibility / gating (unchanged).** Shown only when the member holds **`expenses.create`**
(the permission schema has no `expenses.add`; `create` is the key that lets a member add
ledger entries) **and** can see the card at all (`booking.view`). Owners always see it.
Markers (ADR-041 day-indicator bookings) and **cancelled** bookings do NOT get the action.

**Behaviour.** Opens the EXISTING add-ledger-entry form (Android `AddEntryScreen`, web
expenses entry dialog) pre-filled; nothing is written until the user saves:

| Field | Pre-fill |
|---|---|
| party | the booking's **event party** — see §2 (resolved/created on SAVE, not on open; the form shows the event party NAME, read-only) |
| direction | `paid` ("You gave"); the switch stays editable |
| amount | empty (required, `> 0`) |
| expense_date | **today** (device-local date, same rule as the plain add-entry form) |
| notes | `expenses.entry.booking_notes_default` = `{eventType} · {dates}` — the localized event-type label (no emoji) and the booking's date or date range exactly as the booking card formats it. Editable; the user may clear it |
| attachments | none |
| booking_id | the booking's id (hidden; not editable) |

On save the client inserts ONE `expenses` row `{party_id, direction, amount, expense_date,
notes, booking_id, business_id, created_by}` through the normal expenses write path
(Android: Room + outbox; web: PostgREST insert) — plus, when §2 step 3 applies, ONE
`parties` row created first. No other row is written.

## 2. Party resolution — the EVENT PARTY

An expense recorded from a booking card is booked against a party that **represents the
event**, never against the customer as a person.

### 2.1 The event party name (deterministic, ENGLISH, device-independent)

```
{EventTypeLabel} - {dd-MMM-yyyy} - {CustomerName}
```

e.g. `Wedding - 20-Oct-2026 - Sandhya Upadhyay`. Separator is ` - ` (space, hyphen-minus
U+002D, space). Each segment:

| Segment | Rule |
|---|---|
| `{EventTypeLabel}` | `bookings.event_type` trimmed, as stored (it is the preset's label snapshot — user data, ADR-032 §5; a Hindi custom label stays Hindi because that IS the stored data). **Exception:** when the stored value is a legacy built-in KEY from `event-types.json` (`wedding`, `engagement`, … — `EventTypePresets.normalize` matches a key), use that preset's **English** catalog label (`booking.event_type.*` resolved with an English-forced context). Never the emoji. |
| `{dd-MMM-yyyy}` | `bookings.start_date`: two-digit day, **English** three-letter month abbreviation with an initial capital (`Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec`), four-digit year. Never the device locale's month name, never a Devanagari digit. |
| `{CustomerName}` | `bookings.customer_name` trimmed, internal whitespace runs collapsed to one space. |

**Why English, always.** The party name is STORED data that every device of the business
reads, like the seeded preset labels (ADR-032 §3, `docs/event-type-presets.md`): building
it from the device locale would mint `Wedding - 20-Oct-2026 - …` on one phone and `शादी -
20-अक्टू-2026 - …` on another for the same event — two parties, split ledgers. The label is
not shown as copy anywhere; it is the party's name in the ledger and is edited by the user
like any party name.

### 2.2 Resolution (at SAVE time, in this exact order)

1. **By link.** A **live** party of the business with `booking_id = bookings.id` → reuse
   it, whatever its current name (the owner may have renamed it; the booking's customer
   name or date may have been edited since — the party follows the booking, not the
   label). If several live rows match (offline race), take the earliest `created_at`.
2. **By name.** Else a live party whose `lower(trim(name)) = lower(name from §2.1)` →
   reuse it. Tombstoned parties never match (008). If several match (legacy mixed-case
   twins), earliest `created_at`. The party's `booking_id` is **not** back-filled here
   (no silent edits of party data; the name match exists for offline races and for
   parties typed by hand before the app linked them).
3. **Else create** `{ name = §2.1, phone = bookings.customer_phone (null when blank),
   business_related = true, booking_id = bookings.id, notes = null }`. `business_related
   = true` because event spend IS business spend: it rolls up in the business reports
   like any supplier ledger (revision 1 had `false`; that was wrong). Creating the party
   requires **`expenses.manage_parties`** (RLS `parties_insert`); a member who holds
   `expenses.create` but NOT `manage_parties`, whose booking has no event party yet, gets
   the blocking message `expenses.entry.party_create_forbidden` (`{name}` = the §2.1
   name) and nothing is written. The action stays visible for them; the save is what
   fails fast, client-side, before any insert.
4. Phone is never back-filled onto an existing party.
5. A `23505` on the party insert (the other device won the race on `uq_parties_biz_name`)
   is handled like any party-name collision: pull, re-resolve from step 1, retry the
   expense insert. Never dead-letter the expense.

The event party is an ordinary party afterwards: it appears in the parties list, can be
renamed, has a ledger, counts in reports. Deleting the booking (hard delete, scripts only)
nulls `booking_id` on both the party (014) and its expenses (012); tombstoning the booking
leaves both ids in place and the links simply stop resolving.

## 3. Expenses tab — "Show event"

Wherever a ledger entry is listed (party ledger on both platforms; web expenses home entry
rows if they list entries), a row with `expenses.booking_id != null` shows a **small chip /
text button** `expenses.ledger.show_event` = "Show event" / "कार्यक्रम देखें". The
**party ledger header** of an event party (`parties.booking_id != null`) shows the same
control once, next to the party name. It is an ACTION (chip or text button, `labelSmall` /
caption size, tonal/outlined per platform), not `MetadataText` (`docs/ui-conventions.md`
§1).

- Tap → opens that booking's card (Android: the ADR-098 "open this booking's card" route;
  web: the booking detail dialog on the Booking page). Gated by `booking.view`: without it
  the control is **not rendered** (an action a member cannot take is hidden, not disabled).
- Booking not resolvable locally (tombstoned, or not yet pulled) → the control is omitted.
  Never crash, never show a bare id.
- The previous `expenses.ledger.event_chip` (`Event: {label}`) is **retired** by this
  revision: the event party's name already carries event type · date · customer, so the
  extra label was noise. The key stays in the catalog (deprecated, marked in its
  description) so builds on revision 1 keep compiling; apps drop its use in their revision
  2 ADR and the key is removed from the catalog one shared release later.
- Amounts on the row are masked per `expenses.view_amounts` exactly as today.

## 3b. Booking card — "Expenses history"

The booking card/detail gains a section **`booking.card.expenses_history`** ("Expenses
history" / "खर्च का ब्योरा"), placed directly **below "Payment history"** and styled
exactly like it:

- Rows = **live** expenses (`deleted_at is null`) with `expenses.booking_id = this
  booking`, **newest first** (`expense_date desc`, then `created_at desc`). Each row:
  `date · amount · notes` in the same metadata style as a payment-history row (date as
  the card formats dates; amount formatted as the card formats money; notes verbatim,
  single line, ellipsised; `direction = received` rows show the amount with the ledger's
  received styling/sign exactly as the party ledger does).
- A footer line **`booking.card.expenses_total`** ("Total expenses" / "कुल खर्च") = sum of
  `paid` amounts minus sum of `received` amounts over the listed rows, same emphasis as
  the card's *Paid* line. The total is NOT subtracted from the booking's *Due* — it is
  informational; booking money math is unchanged.
- **Entirely hidden** (no heading, no empty-state text, no divider) when the booking has
  no live linked expense.
- Shown only with **`expenses.view`** (owners always); without it the section does not
  exist on the card. Amounts (rows and total) are masked per **`expenses.view_amounts`**
  exactly as the expenses tab masks them; notes and dates stay visible.
- Rows are read-only here: no tap target, no delete. Editing happens in the expenses tab
  (the row's party ledger).
- Expenses recorded against the **event party from the plain ledger** (no `booking_id`
  on the expense) are NOT listed — the section is strictly `expenses.booking_id`-based,
  so a user who wants an expense here records it from the card (or the apps may offer a
  "link to event" later; out of scope).

## 4. Reports — no change in shape

Reports keep rolling expenses up by party / `business_related` / date. Because the event
party is `business_related = true`, event expenses appear in the business reports under the
event party's name. Neither `expenses.booking_id` nor `parties.booking_id` is a reporting
dimension.

## 5. Sync, backup, model

- **Models**: Android `core:model Expense.bookingId: String? = null`
  (`@SerialName("booking_id")`) **and** `Party.bookingId: String? = null`; Room
  `expenses.booking_id TEXT`, `parties.booking_id TEXT` (new DB version + migration each
  time), entity⇄model mappers; web `Expense.booking_id` and `Party.booking_id: string |
  null` in `expenses/_lib` types + every explicit `select(...)` column list.
- **Wire**: additive nullable columns; pulls select `*`; pushes include `booking_id` on
  both tables. The server columns MUST exist before the app builds ship (PGRST204
  otherwise) — the owner applies 012 then 014 first
  (`~/.luminous/handoff/shared-012-owner-ddl.md`, `~/.luminous/handoff/shared-014-owner-ddl.md`).
- **Backup** (Android `BackupExporter`, `expenses.json`, `parties.json`): rows are the
  serialized model, so both `booking_id`s export automatically once the models carry them;
  the restore path must accept their absence (older backups) → null. Update
  `docs/backup-format.md`.
- **Cleanup**: `scripts/cleanup-data.sql` deletes bookings before parties/expenses — safe
  because both FKs are `on delete set null`.

## 6. String keys (this repo, shipped with the contract)

| Key | en | hi | Status |
|---|---|---|---|
| `booking.card.action_record_expense` | Record expense | खर्च दर्ज करें | rev 1 |
| `booking.card.expenses_history` | Expenses history | खर्च का ब्योरा | **rev 2** |
| `booking.card.expenses_total` | Total expenses | कुल खर्च | **rev 2** |
| `expenses.ledger.show_event` | Show event | कार्यक्रम देखें | **rev 2** |
| `expenses.ledger.event_chip` | Event: {label} | कार्यक्रम: {label} | rev 1 — **deprecated** by rev 2 (§3) |
| `expenses.entry.booking_notes_default` | {eventType} · {dates} | {eventType} · {dates} | rev 1 |
| `expenses.entry.party_create_forbidden` | You can record expenses but not add people. Ask the owner to add {name} first. | आप खर्च दर्ज कर सकते हैं, पर नया व्यक्ति नहीं जोड़ सकते। मालिक से {name} को पहले जोड़ने के लिए कहें। | rev 1 (`{name}` = event party name since rev 2) |

Key naming note: the Expenses-tab action lives in the `expenses` fragment under the
`expenses.ledger.*` namespace (one fragment per namespace — `AGENTS.md`); there is no
`expense.*` namespace.
