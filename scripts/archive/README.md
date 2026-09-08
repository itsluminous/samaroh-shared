# scripts/archive — retired one-time alter scripts

One-time `alter-*.sql` scripts land in `scripts/` while a change is rolling out, and
move here once the change is **folded into the consolidated baseline**
(`supabase/migrations/001–004`) — a fresh `supabase db push` no longer needs them.
They are kept (not deleted) as the record of what was run against pre-baseline
deployments; earlier retirees (`alter-google-accounts.sql`,
`alter-event-type-kind.sql`) predate this folder and were deleted outright (commit
`4ee8029`) — recover them from git history if ever needed.

| Script | What it did | Folded into |
|---|---|---|
| `alter-gcal-calendar-id.sql` | Added `business_settings.gcal_calendar_id` (ADR-048 per-business calendar registry). Pure additive DDL; self-healing on Android until applied (PGRST204 hold-and-retry). | `001_schema.sql` (column present in baseline) |
| `alter-backup-daily.sql` | Default `business_settings.backup_frequency` weekly → daily (ADR-056) + a live-data `UPDATE` migrating existing 'weekly' rows. The data step is live-DB-only by nature. | `001_schema.sql` (default is `'daily'` in baseline) |

**Do not run these against a database built from the current baseline** — they are
no-ops at best. If a pre-baseline deployment still exists, both scripts remain safe
to run once (idempotent DDL; the backup-daily `UPDATE` is a one-way data migration).

The perennial operational scripts (`cleanup-data.sql`, `destroy-everything.sql`) stay
in `scripts/` and never move here. `alter-drop-image-path.sql` stays in `scripts/`
until the owner confirms the live DB has been converged on the Drive-referenced image
architecture; then it moves here too.
