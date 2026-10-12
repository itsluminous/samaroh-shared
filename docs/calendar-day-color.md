# Calendar day colour — one rule for both platforms (2026-10-12)

## The bug the owner saw

Two **red** bookings on one day rendered the day **purple**. Nothing blended: Android's
`CalendarMonthMapper` (ADR-030 rule 5) sets the cell's custom fill only when **exactly one**
firm booking covers the day (`shown.singleOrNull()`); any multi-booking day falls back to the
themed default fill `tertiaryContainer` (`#FFD8E4` light / `#633B48` dark — the "purple").
Web paints one pill per booking (no day fill), so it never showed the problem — but it has
no shared rule either for any future aggregated indicator.

## The rule

Inputs for a date: the **live, non-cancelled** bookings covering it, after the marker rule
(ADR-041: real bookings own the cell; markers paint only dates nothing real covers).
Each booking's **effective colour** is resolved as today (README "Booking calendar
colors"): `bookings.color` → event-type preset default → `null` (themed default).

1. **Never blend, never use a "multiple" colour.** The cell shows exactly one booking
   colour (or the themed default). No alpha mixing, no stripes, no "+N" palette.
2. **Tentative bookings never fill.** They contribute only the amber outline + 👤 (Android)
   / the outlined amber pill (web), as today. The fill decision below runs over the
   **firm** bookings (confirmed/completed) of the day. A day with only tentative bookings
   has no fill.
3. **All firm bookings resolve to the same colour → that colour** (including "all `null`"
   → themed default). Two red bookings → red.
4. **Mixed colours → the most severe colour wins.** Severity = the order of
   `booking-colors.json` (`tomato` first … `graphite` last); the themed default (`null`)
   ranks after every palette colour. The palette is ordered warm→cool, so an
   attention-coloured booking is never hidden behind a calm one. **Do not reorder
   `booking-colors.json`** — its order is now contractual (noted in its `$comment`).
5. Status does not influence colour choice among firm bookings (confirmed vs completed
   look the same; completion is history, not severity).
6. The date number's on-colour follows the winning fill (`on_hex`), as today.

Pseudo:

```
firm   = covering.filter(status != tentative)
colours = firm.map(effectiveColourKey)              // key | null
if firm.isEmpty            -> fill = none
else if colours.allEqual   -> fill = colours[0]      // null = themed default
else                       -> fill = colours.filterNotNull().minBy(paletteIndex)
                              // non-null set is non-empty here (mixed ⇒ ≥1 non-null)
```

Web: pills stay per-booking (unchanged). If web ever renders a single per-day colour
(compact month view, dots), it uses this exact function. Android: replace the
`singleOrNull()` rule with the function above (`CalendarMonthMapper.fillColorKey`); the
`hasFirmBooking` / `hasTentativeBooking` flags and the amber outline are unchanged.

## Tests both platforms carry

| case | expected fill |
|---|---|
| one firm red | tomato |
| two firm red | tomato |
| red + sage | tomato (palette index 0 < 4) |
| sage + graphite | sage |
| sage + null (type without colour) | sage |
| null + null | themed default |
| red + tentative(any) | tomato + amber outline |
| tentative only | none + amber outline |
| marker red + real sage | sage (marker loses, ADR-041) |

ADR required in both app repos (`docs/decisions.md`): Android supersedes ADR-030 rule 5.
