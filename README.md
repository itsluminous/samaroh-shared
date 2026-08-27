# samaroh-shared

Single source of truth for everything Samaroh's Android app and web app must agree on:
strings, database schema, brand assets, invoice layout, permission shapes and event types.
Both app repos consume this repo as a **git submodule** mounted at `shared/`.

## Layout

```
strings/                  canonical string catalog (en + hi) + key conventions
  catalog.<locale>.json   base catalog (shared/common keys)
  fragments/              per-namespace fragment catalogs, merged by codegen
codegen/                  catalog → platform resource generators (pure Node, no deps)
supabase/
  migrations/             canonical Postgres schema, RLS and storage policies
  seed.sql                demo data for local development
brand/                    logo + shared color palette tokens
invoice/                  invoice PDF layout contract (both renderers must match)
permissions/              JSON Schema for member permissions
event-types.json          built-in booking event types (key, emoji, catalog label key)
scripts/                  CI validators + operational SQL (see below)
```

## String catalog & codegen

String keys are added **only here**, always to every locale
(see `strings/README.md` for key, placeholder and plural conventions). The catalog is
split into a small base catalog plus **per-namespace fragment files**
(`strings/fragments/<namespace>.{en,hi}.json` — booking, expenses, inventory, menu,
onboarding, reports, sync-invoice, designsystem, polish, web-auth, web-expinv, web-menu).
Fragments exist so parallel feature work merges additively: each feature owns its own
fragment pair and never touches another feature's file. Codegen and the validator merge
base + all fragments into one catalog (currently **705 keys × 2 locales**).

App repos never hand-edit generated resources — they are git-ignored and regenerated at
build time:

```bash
# Android resources: values/strings.xml + values-hi/strings.xml
node codegen/gen-android.mjs <android-module>/src/main/res

# Web messages for the i18n runtime: en.json + hi.json
node codegen/gen-web.mjs <web-app>/messages
```

- Android wires this as the `generateStrings` Gradle task; web as the `gen:i18n` npm script.
- Both generators exit non-zero if the locale catalogs ever diverge in keys, so a missing
  translation breaks the build instead of shipping.
- `gen-android.mjs` escapes Android-format specifiers (including literal `%`) so
  placeholder strings survive `getString(...)` formatting.

## Database

`supabase/migrations/` is the canonical schema:

| File | Contents |
|---|---|
| `001_schema.sql` | extensions, enums, all tables, indexes, `updated_at` triggers, inventory helper |
| `002_rls.sql` | RLS helper functions, per-command policies on every table, invite activation |
| `003_storage.sql` | private storage buckets + membership-scoped object policies |
| `004_party_business_flag.sql` | `parties.business_related boolean not null default true` (personal-party support) |

Apply with the Supabase CLI (`supabase db push` against a linked project, or
`supabase db reset` locally — which also loads `seed.sql`). Schema changes are made only by
adding a new migration file here, plus a decision-log entry in the affected app repos.
Apply new migrations **before** deploying app versions that read the new columns.

## Operational scripts

| Script | Purpose |
|---|---|
| `scripts/cleanup-data.sql` | Wipe operational data for one business (or all): hard-deletes bookings/payments/reminders/date blocks, expenses/parties/attachments, inventory transactions/master items (child tables first, FK-safe). **Keeps** accounts and setup (`auth.users`, `businesses`, `business_members`, `business_settings`, `google_accounts`) and resets `businesses.invoice_counter` to 0. |
| `scripts/cleanup-all-data.sql` | Full pre-launch reset: everything `cleanup-data.sql` deletes **plus** stored files in the storage buckets, so real data can be re-imported from scratch. Accounts and business setup survive. |

Run either in the Supabase SQL editor (or `psql`) as a privileged role; both are
transactional and ordered to satisfy foreign keys.

## Invoice layout contract

`invoice/layout-spec.md` is the pixel-level contract both PDF renderers implement — the
Android renderer (platform PDF API in `core:invoice`) and the web renderer (`pdf-lib`).
A4 portrait, fixed margins/typography, brand accent `#6750A4`, Devanagari-capable font,
rendered in the app's current language from this catalog. Any layout change requires a
`docs/decisions.md` entry in **both** app repos.

## Permissions schema

`permissions/permissions-schema.json` (JSON Schema, draft-07) defines the shape of
`business_members.permissions`: per-section objects (`booking`, `expenses`, `inventory`,
`reports`, …) of boolean capabilities (e.g. `inventory.manage_master_items`). Every action
defaults to **false** when absent; owners bypass the object entirely (implicit full
access); backups are owner-only and deliberately not representable. Both clients gate UI
and writes from this shape.

## Validation

```bash
node scripts/validate-catalogs.mjs   # catalog shape, key parity, placeholder parity (base + fragments)
bash scripts/legal-check.sh          # repo-wide denylist scan (legal hygiene)
```

CI (`.github/workflows/ci.yml`) runs both, smoke-tests the generators, and applies the
migrations plus seed to a scratch Postgres.

## Making changes here

1. Commit in this repo first (Conventional Commits).
2. `git pull --ff-only` before pushing — multiple app repos bump this submodule, so the
   remote may have moved.
3. Push, then bump the `shared/` submodule pointer in each consuming app repo
   (`git -C shared pull origin main` there + a `chore(shared): bump …` commit).
