# UI conventions shared by both apps

Cross-platform presentation rules that `samaroh-android` and `samaroh-web` both follow.
Each rule is a contract: change it here first, then both app repos follow with an ADR
(`docs/decisions.md`). Navigation / app-shell rules live in `files-tab-design.md` §6.

## 1. Metadata lines are small + monospace + muted (2026-10-02)

**Problem.** Text *about* a record ("Added by Priya on 2 Oct 2026", "Updated 30 Sep")
rendered in the same body style and colour as the record's own notes, so a card read as
one paragraph and the owner could not tell the note from the stamp.

**Rule.** Every metadata line is rendered through ONE component per platform — never an
ad-hoc Text/Typography with hand-picked style:

| | Android (`core:designsystem`) | Web (`src/components`) |
|---|---|---|
| Component | `MetadataText(text, modifier, maxLines, overflow)` | `<MetadataText>` (Typography `variant="metadata"`, `data-metadata`) |
| Size | `labelSmall` (11sp) — the only sub-16sp role the app uses | `0.75rem` (caption size) |
| Face | `FontFamily.Monospace` | `"Roboto Mono", SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace` |
| Colour | `colorScheme.outline` | `text.secondary` |
| Element | — | `span` by default (fits inside a ListItemText secondary), `component="div"` for a standalone line |

Content that sits **next to** a metadata line (notes, names) uses the primary text colour
(`onSurface` / `text.primary`), not the secondary one, so content vs metadata differs by
size + face **and** colour — never by colour alone.

**What is metadata** — provenance/attribution stamps: *who* recorded a record and *when*
it was recorded, last touched or stamped:

- "Added by {name} on {date}" audit line (booking card/detail, Files rows and grid tiles)
- "Updated {date}" / "last entry {relative time}" (inventory list row, expenses party row)
- the date stamp of a ledger entry (party ledger) and the timestamp of an inventory
  transaction (item history) — they sit directly above/next to free-text notes

**What is NOT metadata** — anything that *is* the record: booking notes and date range,
customer phone, amounts, quantities, file size, item counts, chip labels. Also not
covered: Menu "last sync" / "last backup" rows (system status, converge opportunistically)
and the Notes tab (renders no author/timestamp today).

**Applied screens (both platforms, same set):** Booking card/detail · Expenses home party
row · Party ledger entry row · Inventory list row · Inventory item transaction history ·
Files list row and grid tile.

**Localization.** No string keys are introduced by the style: callers pass an already
localized string (`files.file.added_by`, `booking.card.audit_added`, platform date/relative
time formatters). Rendering never adds text.

**References.** Android ADR-093 (`samaroh-android/docs/decisions.md`); web entry
"Metadata lines are small + MONOSPACE + muted (MetadataText)" (`samaroh-web/docs/decisions.md`).
