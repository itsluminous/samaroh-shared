# String Catalog

The canonical, cross-platform string catalog for Samaroh. Every user-visible string in the
Android app and the web app comes from these files — **no string literals in app code, ever**.

## Files

| File | Purpose |
|---|---|
| `catalog.en.json` | Canonical catalog (English). The source of truth for keys, placeholders and descriptions. |
| `catalog.hi.json` | Hindi translation. Must have **exact key parity** with `catalog.en.json`. |

Each entry maps a key to an object:

```json
"booking.card.due_label": {
  "value": "Due",
  "description": "Label above the auto-calculated outstanding amount on the booking card."
}
```

- `value` — the translated string (may contain ICU placeholders, see below).
- `description` — translator/developer context: where the string appears and what
  placeholders mean. Required on every entry.

## Key convention: `module.screen.element`

Keys are flat, dot-separated, lowercase `snake_case` segments:

```
<module>.<screen-or-group>.<element>
```

Examples: `common.action.save`, `common.nav.booking`, `booking.card.due_label`,
`booking.event_type.wedding`, `app.placeholder.title`.

Module namespaces and their owners:

| Namespace | Owner |
|---|---|
| `common.*` | shared vocabulary (actions, states, nav) — integrator-owned |
| `app.*` | app shell (placeholders, top-level chrome) |
| `booking.*`, `expenses.*`, `inventory.*` | the respective feature |
| `onboarding.*`, `auth.*`, `sync.*`, `invoice.*`, `menu.*`, `settings.*`, `reports.*` | the respective feature/core module |

New keys are added **only in this repo**, always to **both** locale files, in the feature's
own namespace. CI enforces key parity and shape (`scripts/validate-catalogs.mjs`).

## Placeholders (ICU)

Use **named ICU arguments** in braces:

```
"Namaste {name}, ₹{amount} is pending for {event}."
```

- Placeholder **names must be identical across locales** for a given key (order may differ —
  Hindi word order is free to move them).
- Codegen converts named arguments to each platform's native form:
  - **Android** (`gen-android.mjs`): named args become positional `%1$s`, `%2$s`, …
    Positions are assigned from the argument's first-appearance order **in the English
    value**, so the same placeholder gets the same position in every locale.
  - **Web** (`gen-web.mjs`): ICU messages pass through unchanged (the web i18n runtime
    consumes ICU natively).
- Never concatenate translated fragments in code; make one key with placeholders instead.

## Plurals (ICU)

Use ICU plural syntax; `#` stands for the count:

```
"{count, plural, one {# pending change} other {# pending changes}}"
```

- The plural argument must be the **entire value** of the key (no text outside the
  `{count, plural, …}` block) — this is what allows Android codegen to emit a native
  `<plurals>` resource.
- Provide at minimum the `one` and `other` categories. Add more categories only when a
  target locale needs them.
- Android codegen maps each category to a `<plurals>/<item quantity="…">` and `#` to `%1$d`.
  Web codegen passes the ICU message through unchanged.

## What is NOT localized

- Emoji / event-type icons (they come from `event-types.json`).
- The invoice number format and currency symbol (see `../invoice/layout-spec.md`).
- Brand name spelling in Latin script contexts ("Samaroh").

## Consuming the catalog

- Android: the `generateStrings` Gradle task runs `codegen/gen-android.mjs`, emitting
  `res/values/strings.xml` and `res/values-hi/strings.xml`. Generated files are git-ignored.
- Web: the `gen:i18n` npm script runs `codegen/gen-web.mjs`, emitting
  `messages/en.json` and `messages/hi.json`. Generated files are git-ignored.
