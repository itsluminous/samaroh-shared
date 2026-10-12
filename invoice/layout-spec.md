# Invoice Layout Contract

Both PDF renderers — the Android renderer (platform PDF API in `core:invoice`) and the web
renderer (`pdf-lib`) — MUST produce this exact layout. Pixel-equivalence is the goal; this
document is the contract. Any change requires a `docs/decisions.md` entry in both app repos.

## Page

- Size: **A4 portrait** (595 × 842 pt).
- Margins: 40 pt on all sides. Content width: 515 pt.
- Base font: platform default sans-serif with full Devanagari coverage (the PDF text renders
  in the app's **current language** from the string catalog — embed a font that covers both
  Latin and Devanagari).
- Base sizes: body 11 pt, section titles 13 pt bold, header business name 20 pt bold.
- Accent color: `primary` `#6750A4` (see `../brand/palette.md`); body text `#1C1B1F`.

## Invoice number

```
{prefix}-{YYYY}-{counter:04d}          e.g.  SGH-2026-0042
```

- `prefix` = `businesses.invoice_prefix` (default `INV`).
- `YYYY` = calendar year of first generation.
- `counter` = `businesses.invoice_counter` incremented atomically at first generation,
  zero-padded to 4 digits.
- Assigned **once** per booking on first invoice generation, stored in
  `bookings.invoice_number`, **immutable** afterwards — regenerating the PDF reuses it.
- **Manual numbers** (booking form, Android ADR-020): the owner may type a number from the
  paper register (e.g. `88`) before any PDF exists; it is stored verbatim and frozen.

### Display form (2026-10-12) — one rule, used EVERYWHERE the number is shown

`displayInvoiceNumber(stored, prefix)`:

- stored matches `^[0-9]+$` (a bare manual register number) → parse as an integer and
  format `{prefix}-{n:04d}`: `88` → `INV-0088`, `0088` → `INV-0088`, `12345` → `INV-12345`
  (zero-pad to at least 4 digits; never truncate).
- anything else → verbatim (auto numbers are already `{prefix}-{YYYY}-{counter:04d}`;
  manual alphanumerics are respected).

The STORED value never changes (uniqueness checks and the register mapping keep working).
The display form is used by: the PDF header, the text receipt, the booking card/detail
"Invoice no." line, the Google Calendar description line, and the **PDF file name** (§ File
name). Both platforms implement it as one pure helper with the same unit tests.

## File name

`{displayInvoiceNumber}.pdf` — e.g. `INV-0088.pdf`, `SGH-2026-0042.pdf`. Characters outside
`[A-Za-z0-9._-]` are replaced by `-` (defensive: manual numbers are free text). Android
writes the file under `files/invoices/`; web passes it as the download name. (Previously a
manual number `88` produced `88.pdf` on both platforms.)

## Amount formatting (both renderers, no exceptions)

- **Indian digit grouping**: `₹1,06,511` · `₹1,06,51,161` (last 3 digits, then groups of 2).
- Two decimals only when paise are non-zero (`₹500` not `₹500.00`; `₹500.50` kept).
- Rupee symbol `₹` immediately before the number, no space.
- Negative amounts never appear on invoices.

## Sections — exact top-to-bottom order

1. **Header band**
   - **Top-left: business logo** — only when the business has one (`businesses.logo_path`,
     the sole Supabase Storage object, bucket `logos`; Android renders its local copy, web
     downloads the PNG). 56 × 56 pt, rounded 8 pt corners, flush with the left margin and
     the top margin. No logo → the text column starts at the left margin (no gap).
   - Right of the logo (12 pt gap): business name (20 pt bold), then **address and owner
     name only** (11 pt, one per line, `onSurfaceVariant` grey `#49454F`). The
     **business-type line is REMOVED** (2026-10-12: the default `Marriage Hall` told the
     customer nothing; `businesses.business_type` stays in the schema for the profile
     screen). Blank address/owner lines are skipped, never printed empty.
   - Right-aligned column: localized "Invoice" title (13 pt bold, accent color),
     invoice number, issue date (locale-formatted).
   - 1 pt accent-colored rule under the band, 16 pt below content.

2. **Customer block**
   - Localized "Billed to" label (bold), customer name, customer phone (if present).

3. **Event block**
   - Localized event-type label — **no event icon/emoji in PDF output** (both renderers):
     emoji glyphs render inconsistently (or as tofu) across PDF fonts and viewers. The
     icon stays in the app UIs and in the text receipt.
   - Date or date range (locale-formatted; range with an en dash), times if set.

3a. **Notes block** (2026-10-12) — printed **only when `bookings.notes` is non-blank**.
   - Section title `invoice.notes_title` (13 pt bold, accent color), then **`bookings.notes`
     verbatim**: trimmed, line breaks preserved, word-wrapped to the content width, 11 pt
     body colour, emoji stripped like every other PDF text. No truncation (a long note may
     push later sections down / onto page 2).
   - Source of truth is the booking's own `notes` column — **not** `booking_payments.notes`
     and not any import tag. The "Imported — …" text the owner saw on invoices is the
     per-payment note written by the one-time booking import (`booking_payments.notes` =
     `Imported — settled on event day`, `Imported — "rs"` …) rendered in the payment table's
     *Notes* column (§5); it was never `bookings.notes`. That column keeps printing payment
     notes; the owner clears the import markers once with
     `scripts/clear-import-payment-notes.sql`.

4. **Amounts block**
   - Row: localized "Total amount" — right-aligned amount.
   - Row: localized "Security deposit" — right-aligned amount. Include the row **only when
     security_deposit > 0**; it is refundable and NOT part of total_amount.

5. **Payment history table**
   - Columns, in order: **Date | Method | Notes | Amount** (Amount right-aligned).
   - Rows: all non-deleted `booking_payments` ordered by `paid_on` ascending, then
     `created_at` ascending.
   - Header row: bold, accent-colored bottom border (1 pt).
   - Method values are localized labels, not enum literals.
   - Footer row: localized "Total paid" (bold) with the sum.

6. **Balance due**
   - `due = total_amount − Σ(payments)`. Computed at render time, never stored.
   - Full-width tonal band (`#EADDFF` fill, rounded 8 pt): localized "Balance due" left,
     amount right — 13 pt bold. Amount in error red `#B3261E` when due > 0, otherwise
     green `#146C2E` with the localized "Fully paid" note.

7. **Footer**
   - Centered, 9 pt, grey: localized "Generated by Samaroh" + generation date.

## Localization

- Every label above comes from `invoice.*` keys in the string catalog — zero hardcoded text.
- Dates: locale-formatted (e.g. `10 Jul 2026` / `१० जुलाई २०२६` per locale conventions).
- No event icons/emoji anywhere in the PDF output (see Event block) — both renderers.

## Text (non-PDF) variant

The "share as text" receipt mirrors the same order — business name, invoice number (display
form), customer, event + dates, **notes (when non-blank, after the event line)**, total /
deposit / paid / due, then one line per payment — using the same localized labels and the
same ₹ formatting. No business-type line here either. Unlike the PDF, the text receipt
KEEPS the event icon emoji on the event line (plain text renders emoji fine; it is sent
through a share intent, not embedded in a PDF font). Emoji render as-is (not localized).
