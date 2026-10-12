# Reports date-range quick filter — contract (2026-10-12)

Replaces the three-chip row (This month / 3 months / 12 months / Custom) on every report
page, both platforms. Each app adds an ADR.

## Options, in this order

| # | Chip | key | range (inclusive, device-local `today`) |
|---|---|---|---|
| 1 | −12 months | `reports.range.minus_12m` | `today − 12 months` … `today` |
| 2 | −3 months | `reports.range.minus_3m` | `today − 3 months` … `today` |
| 3 | This month | `reports.range.this_month` (existing) | `1st of this month` … `last day of this month` (whole calendar month, so dues falling later this month stay visible) |
| 4 | +3 months | `reports.range.plus_3m` | `today` … `today + 3 months` |
| 5 | +12 months | `reports.range.plus_12m` | `today` … `today + 12 months` |
| 6 | Custom | `reports.range.custom` (existing) | from–to picker, as today |

- `today ± N months` = the same day-of-month N months away, clamped to the last day of
  that month when it does not exist (Java `LocalDate.plusMonths` / JS: set month then clamp
  — write the helper, do not rely on `Date` overflow). Device-local date, same "today" rule
  as the expenses summary (Android ADR-091).
- "−" ranges are backward-looking (what happened); "+" ranges are forward-looking
  (upcoming bookings and dues). Both ends inclusive.
- **Default: `minus_12m`** — both apps default to the trailing-12-months preset today
  (Android `RangePreset.LAST_12_MONTHS`, web `'last_12_months'`); the default keeps that
  meaning. Note the END changes from "end of current month" (Android) / "today" (web) to
  **today** on both — identical ranges on both platforms is the point.
- Persisted preset ids (if a platform remembers the choice): `minus_12m | minus_3m |
  this_month | plus_3m | plus_12m | custom`.
- The chip row scrolls horizontally when it does not fit (`ChipRow` convention, ADR-091);
  it never wraps or shrinks labels.

## Strings

New (en / hi): `reports.range.minus_12m` (−12 months / −12 महीने), `reports.range.minus_3m`
(−3 months / −3 महीने), `reports.range.plus_3m` (+3 months / +3 महीने),
`reports.range.plus_12m` (+12 months / +12 महीने). Reused: `reports.range.this_month`,
`reports.range.custom`, `reports.range.summary`, `reports.range.picker_title`.
`reports.range.last_3_months` / `last_12_months` are **deprecated** — the integrator deletes
them once both apps have switched (their descriptions say so).

Labels use the typographic minus `−` (U+2212), not a hyphen, so the chips read as signed
offsets and align with `+`.
