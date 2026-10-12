# Invoice layout — 2026-10-12 change set (both platforms render identically)

The pixel-level contract lives in [`../invoice/layout-spec.md`](../invoice/layout-spec.md);
this page is the change note for the owner-feedback round so the Android and web agents
implement the same four things and nothing else. Each app adds an ADR.

| # | Change | Where in the spec |
|---|---|---|
| 1 | **Business-type line removed** from the header (no more `Marriage Hall` under the name). Header text column = name, address, owner name; blank lines skipped. `businesses.business_type` is untouched in the schema/profile. | § Sections → 1. Header band |
| 2 | **Logo top-LEFT** (56×56 pt, 8 pt radius, flush with left+top margin) when `businesses.logo_path` is set — the sole Supabase Storage object (`logos` bucket; ADR-065). Name/address/owner to its right with a 12 pt gap; without a logo the text starts at the margin. (Both renderers already draw this; the spec now says it unambiguously and forbids a placeholder gap.) | § Sections → 1. Header band |
| 3 | **NOTES section** after the Event block, printed only when `bookings.notes` is non-blank: title `invoice.notes_title`, then `bookings.notes` verbatim (trimmed, newlines kept, wrapped, not truncated). Text receipt gets the same line after the event line. | § Sections → 3a. Notes block; § Text variant |
| 4 | **PDF file name = display invoice number** + `.pdf` (`INV-0088.pdf`, `SGH-2026-0042.pdf`), sanitised to `[A-Za-z0-9._-]`. | § File name |

## Why the owner saw "Imported" in the invoice notes

That text is **`booking_payments.notes`**, written by the one-time booking import
(`Imported — settled on event day`, `Imported — "rs"`, `Imported`) and printed in the
payment-history table's *Notes* column — the renderers were following the spec. It was never
`bookings.notes`; there was simply no section that printed the booking's own notes. Fix =
change 3 above (new section, correct source) + a one-time data clean-up the owner runs:
`scripts/clear-import-payment-notes.sql` nulls every `booking_payments.notes` that starts
with `Imported`. The payment table keeps its *Notes* column for genuine per-payment notes
(cheque numbers etc.).

## Why the file was `88.pdf`

Both renderers already name the file after `bookings.invoice_number`. The owner typed `88`
(paper-register number) into the manual invoice-number field (Android ADR-020), so the
stored — and therefore displayed and file-named — number IS `88`. The spec now defines a
**display form** `displayInvoiceNumber(stored, prefix)`: bare digits → `{prefix}-{n:04d}`
(`88` → `INV-0088`), everything else verbatim. Stored value unchanged; the display form is
used by the PDF header, text receipt, booking card line, calendar description and the file
name. Implement it as ONE pure helper per platform with the same test table:

| stored | prefix | display |
|---|---|---|
| `88` | `INV` | `INV-0088` |
| `0088` | `INV` | `INV-0088` |
| `12345` | `INV` | `INV-12345` |
| `INV-2026-0042` | `INV` | `INV-2026-0042` |
| `A-12` | `INV` | `A-12` |
| `88` | `SGH` | `SGH-0088` |

## String keys added

| Key | en | hi |
|---|---|---|
| `invoice.notes_title` | Notes | नोट्स |

## Out of scope

Amount formatting, payment table columns, balance band, footer, fonts — unchanged.
