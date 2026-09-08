# String Catalog

The canonical, cross-platform string catalog for Samaroh. Every user-visible string in the
Android app and the web app comes from these files - **no string literals in app code, ever**.

## Files

| File | Purpose |
|---|---|
| `catalog.en.json` | Canonical catalog (English). The source of truth for keys, placeholders and descriptions. |
| `catalog.hi.json` | Hindi translation. Must have **exact key parity** with `catalog.en.json`. |
| `fragments/<namespace>.{en,hi}.json` | Per-feature **fragment catalogs** (see below). Merged with the base catalog by codegen and the validator. |

Each entry maps a key to an object:

```json
"booking.card.due_label": {
  "value": "Due",
  "description": "Label above the auto-calculated outstanding amount on the booking card."
}
```

- `value` - the translated string (may contain ICU placeholders, see below).
- `description` - translator/developer context: where the string appears and what
  placeholders mean. Required on every entry.
- `translatable` *(optional)* - set to `false` for data-like values that must never be
  localized (see below). Any value other than `false` (or omitting the field) is a
  validation error.

## Non-translatable entries (`"translatable": false`)

Some catalog values are **data, not copy**: URIs, technical identifiers, payment deep
links. Localizing them would break them. Mark those entries `"translatable": false`:

```json
"menu.about.donate_upi_uri": {
  "value": "upi://pay?pa=someone@bank&cn=App&tn=App%20donation",
  "description": "Data, not copy: the UPI payment deep link the Donate row fires.",
  "translatable": false
}
```

Rules:

- The entry lives **only in the canonical `en` catalog/fragment**. It is exempt from key
  parity; adding a matching entry to `hi` (or any other locale) is a **hard error** - a
  silently-ignored translation would drift from the canonical value, so the validator
  refuses it outright.
- The value must not be an ICU plural (nothing locale-varying to pluralize).
- **Android** (`gen-android.mjs`): emitted once, in the default `values/strings.xml`,
  with `android:translatable="false"` - every locale falls back to it. A value containing
  a literal `%` (percent-encoding in a URI) also gets `formatted="false"` so AAPT does
  not format-validate it.
- **Web** (`gen-web.mjs`): the `en` value is copied into **every** locale's messages
  file, so lookups never miss.
- Tested by `scripts/test-catalogs.mjs` (fixture-driven; run it with the validator).

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
| `common.*` | shared vocabulary (actions, states, nav) - integrator-owned |
| `app.*` | app shell (placeholders, top-level chrome) |
| `booking.*`, `expenses.*`, `inventory.*` | the respective feature |
| `onboarding.*`, `auth.*`, `sync.*`, `invoice.*`, `menu.*`, `settings.*`, `reports.*` | the respective feature/core module |
| `guest.*` | web guest mode (lives in `fragments/web-auth`) |

New keys are added **only in this repo**, always to **both** locale files, in the feature's
own namespace. CI enforces key parity and shape (`scripts/validate-catalogs.mjs`).

## Fragment catalogs (`fragments/`) - parallel-agent workflow

To let Wave-1 agents add keys **without merge conflicts** in the base catalog, each agent
owns exactly **one fragment namespace file pair** under `strings/fragments/`:

```
fragments/booking.en.json       fragments/booking.hi.json      # bookings (incl. calendar a11y)
fragments/designsystem.en.json  fragments/designsystem.hi.json # shared UI components (viewer, cropper)
fragments/expenses.en.json      fragments/expenses.hi.json     # expenses
fragments/inventory.en.json     fragments/inventory.hi.json    # inventory
fragments/menu.en.json          fragments/menu.hi.json         # menu (settings.* keys too)
fragments/onboarding.en.json    fragments/onboarding.hi.json   # onboarding (auth.* keys too)
fragments/reports.en.json       fragments/reports.hi.json      # reports
fragments/sync-invoice.en.json  fragments/sync-invoice.hi.json # sync.* + invoice.* keys
fragments/web-auth.en.json      fragments/web-auth.hi.json     # web track: auth + guest.*
fragments/web-booking.en.json   fragments/web-booking.hi.json  # web track: booking one-offs
fragments/web-expinv.en.json    fragments/web-expinv.hi.json   # web track: expenses + inventory
fragments/web-menu.en.json      fragments/web-menu.hi.json     # web track: menu/settings/reports
fragments/web-perms.en.json     fragments/web-perms.hi.json    # web track: permissions vocabulary
```

The `web-*` pairs are deliberately kept separate (not folded into the feature
fragments): the Android repo's catalog-usage audit skips `web-*.json` by filename so
web-only keys don't pollute its unused-key signal.

Rules:

- File name shape: `<namespace>.<locale>.json` (namespace: lowercase `[a-z0-9_-]`). Entry
  shape is identical to the base catalog (`key → {value, description}`).
- Codegen (`gen-android.mjs`, `gen-web.mjs`) and the validator **merge** the base catalog
  with all fragments per locale. Generated output is indistinguishable from keys living in
  the base catalog.
- A key defined in **more than one file** (base or fragment, same locale) is a **hard
  error** - namespaces are exclusively owned; never redefine another module's key.
- **Key parity is enforced across the merged set**: every key must exist in every locale.
  Adding a key to `booking.en.json` without `booking.hi.json` fails validation and codegen.
- A fragment file for a locale that has no base `catalog.<locale>.json` is an error (it
  would otherwise be silently ignored).
- Do not create/edit another agent's fragment files. The integrator folds fragments into
  the base catalog (or keeps them) at wave merge time - either is valid.

## Placeholders (ICU)

Use **named ICU arguments** in braces:

```
"Namaste {name}, ₹{amount} is pending for {event}."
```

- Placeholder **names must be identical across locales** for a given key (order may differ -
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
  `{count, plural, …}` block) - this is what allows Android codegen to emit a native
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
