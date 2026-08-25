# samaroh-shared

Single source of truth for everything Samaroh's Android app and web app must agree on:
strings, database schema, brand assets, invoice layout, permission shapes and event types.
Both app repos consume this repo as a **git submodule** mounted at `shared/`.

## Layout

```
strings/                  canonical string catalog (en + hi) + key conventions
codegen/                  catalog → platform resource generators (pure Node, no deps)
supabase/
  migrations/             canonical Postgres schema, RLS and storage policies
  seed.sql                demo data for local development
brand/                    logo + shared color palette tokens
invoice/                  invoice PDF layout contract (both renderers must match)
permissions/              JSON Schema for member permissions
event-types.json          built-in booking event types (key, emoji, catalog label key)
scripts/                  CI validators (catalog validation, legal-hygiene scan)
```

## String catalog & codegen

String keys are added **only here**, always to every `strings/catalog.<locale>.json`
(see `strings/README.md` for key, placeholder and plural conventions). App repos never
hand-edit generated resources — they are git-ignored and regenerated at build time:

```bash
# Android resources: values/strings.xml + values-hi/strings.xml
node codegen/gen-android.mjs <android-module>/src/main/res

# Web messages for the i18n runtime: en.json + hi.json
node codegen/gen-web.mjs <web-app>/messages
```

- Android wires this as the `generateStrings` Gradle task; web as the `gen:i18n` npm script.
- Both generators exit non-zero if the locale catalogs ever diverge in keys, so a missing
  translation breaks the build instead of shipping.

## Database

`supabase/migrations/` is the canonical schema:

| File | Contents |
|---|---|
| `001_schema.sql` | extensions, enums, all tables, indexes, `updated_at` triggers, inventory helper |
| `002_rls.sql` | RLS helper functions, per-command policies on every table, invite activation |
| `003_storage.sql` | private storage buckets + membership-scoped object policies |

Apply with the Supabase CLI (`supabase db push` against a linked project, or
`supabase db reset` locally — which also loads `seed.sql`). Schema changes are made only by
adding a new migration file here, plus a decision-log entry in the affected app repos.

## Validation

```bash
node scripts/validate-catalogs.mjs   # catalog shape, key parity, placeholder parity
bash scripts/legal-check.sh          # repo-wide denylist scan
```

CI (`.github/workflows/ci.yml`) runs both, smoke-tests the generators, and applies the
migrations plus seed to a scratch Postgres.
