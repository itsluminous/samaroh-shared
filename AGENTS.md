# AGENTS.md — samaroh-shared

Instructions for AI agents (and humans) working in this repo. This is the **contracts
repo**: string catalogs, Supabase schema, brand, invoice layout, permissions schema and
event types consumed by `samaroh-android` and `samaroh-web` as a `shared/` git submodule.

## Commands

```bash
node scripts/validate-catalogs.mjs    # catalog shape, key parity (en↔hi), placeholder parity
bash scripts/legal-check.sh           # legal-hygiene denylist scan (base64-embedded list)

# codegen smoke (what the app repos run at build time):
node codegen/gen-android.mjs /tmp/res-out
node codegen/gen-web.mjs /tmp/msg-out
```

Run the validator + legal check before **every** commit. CI runs both, smoke-tests the
generators, and applies `supabase/migrations/` + `seed.sql` to a scratch Postgres.

## Hard rules

1. **Legal hygiene — never name third-party reference products** in strings, docs,
   comments or commit messages. Allowed third-party names: Google, Supabase, WhatsApp
   (share target), OSS attributions. `scripts/legal-check.sh` is CI-blocking.
2. **Key parity is absolute**: every key exists in both `en` and `hi` (base catalog and
   every fragment pair). The validator and both app builds fail otherwise.
3. **Schema changes are additive migrations only**: never edit an existing
   `supabase/migrations/00N_*.sql`; add the next-numbered file. Contract-level changes
   (schema, invoice layout, permissions shape, key-namespace structure) also require an
   ADR entry in the affected app repos' `docs/decisions.md`.

## Conventions

- **Fragments per namespace**: new feature strings go in
  `strings/fragments/<namespace>.{en,hi}.json` — one fragment pair per feature namespace
  (e.g. `booking`, `web-auth`). This keeps parallel feature agents merge-conflict-free;
  never add feature keys to another feature's fragment or to the base catalog.
- **Descriptions matter**: every entry carries a `description` used by translators and
  the app repos' catalog-usage audits.
- **Shared-push coordination**: commit and push here **first**, then bump the submodule
  in each app repo. Always `git pull --ff-only` before pushing — both app tracks bump
  this repo and the remote may have advanced mid-task. Never force-push.
- Conventional Commits, imperative, ≤50-char subject (`feat(strings): …`,
  `feat(schema): …`, `feat(scripts): …`).
- Operational scripts live in `scripts/` (`cleanup-data.sql` for data rows,
  `cleanup-storage.mjs` for storage files — SQL cannot touch storage tables on
  hosted Supabase, error 42501). Keep the header comments (what's kept vs
  deleted) accurate when editing.
