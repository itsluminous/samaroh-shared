-- destroy-everything.sql — DROP THE ENTIRE SAMAROH SCHEMA
-- ============================================================================
-- ██████████████████████████████████████████████████████████████████████████
-- ██                                                                      ██
-- ██   ⚠️⚠️⚠️  DANGER — TOTAL, IRREVERSIBLE DESTRUCTION  ⚠️⚠️⚠️           ██
-- ██                                                                      ██
-- ██   This script DROPS EVERY Samaroh database object:                   ██
-- ██     • ALL public tables (CASCADE — every row of every business,      ██
-- ██       every booking, payment, expense, inventory record, member,     ██
-- ██       preset ... GONE, plus all their policies/indexes/triggers)     ██
-- ██     • ALL Samaroh enums/types and functions                          ██
-- ██     • the invite-activation trigger on auth.users                    ██
-- ██     • ALL Samaroh policies on storage.objects                        ██
-- ██     • the supabase_migrations history (so `supabase db push`         ██
-- ██       re-applies the consolidated baseline from scratch)             ██
-- ██                                                                      ██
-- ██   THERE IS NO UNDO. Take a backup first if in ANY doubt.             ██
-- ██                                                                      ██
-- ██████████████████████████████████████████████████████████████████████████
--
-- WHAT IT DELIBERATELY DOES **NOT** TOUCH
--   • auth.users            — accounts survive; sign-ins keep working.
--   • storage.buckets       — bucket rows stay; the baseline 003_storage.sql
--                             creates them idempotently (on conflict do nothing),
--                             so leaving them is safe.
--   • storage OBJECTS       — SQL cannot delete files on hosted Supabase
--                             (error 42501). Wipe the files separately with the
--                             companion script:
--                               node scripts/cleanup-storage.mjs --dry-run   # preview
--                               SUPABASE_URL=... SUPABASE_SERVICE_KEY=... \
--                                 node scripts/cleanup-storage.mjs
--   • Google Drive          — expense attachment files live in the owner's
--                             Drive; never touched from here.
--
-- INTENDED SEQUENCE (full clean-slate reset)
--   1. Run THIS script in the Supabase SQL editor (runs as postgres).
--   2. Wipe storage files:  node scripts/cleanup-storage.mjs
--   3. Re-apply the consolidated baseline:  supabase db push
--   4. Recreate the business via app onboarding (the app seeds the
--      event-type presets client-side at business creation).
--   5. Re-run the import scripts.
--   Also clear every device's local store (sign out / clear site data) —
--   synced clients will not see tombstones for dropped rows.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Trigger on auth.users (the table itself is NOT touched)
-- ---------------------------------------------------------------------------
drop trigger if exists trg_activate_pending_invites on auth.users;

-- ---------------------------------------------------------------------------
-- 2. Samaroh policies on storage.objects (the objects/buckets tables stay;
--    dropping the policies lets the baseline 003_storage.sql recreate them
--    without "already exists" errors)
-- ---------------------------------------------------------------------------
drop policy if exists storage_logos_select            on storage.objects;
drop policy if exists storage_logos_insert            on storage.objects;
drop policy if exists storage_logos_update            on storage.objects;
drop policy if exists storage_logos_delete            on storage.objects;
drop policy if exists storage_inventory_images_select on storage.objects;
drop policy if exists storage_inventory_images_insert on storage.objects;
drop policy if exists storage_inventory_images_update on storage.objects;
drop policy if exists storage_inventory_images_delete on storage.objects;
drop policy if exists storage_booking_invoices_select on storage.objects;
drop policy if exists storage_booking_invoices_insert on storage.objects;
drop policy if exists storage_booking_invoices_update on storage.objects;
drop policy if exists storage_booking_invoices_delete on storage.objects;

-- ---------------------------------------------------------------------------
-- 3. Every public table, CASCADE (drops their RLS policies, indexes,
--    updated_at triggers and FKs with them). Order doesn't matter w/ cascade.
-- ---------------------------------------------------------------------------
drop table if exists payment_reminders      cascade;
drop table if exists booking_payments       cascade;
drop table if exists bookings               cascade;
drop table if exists date_blocks            cascade;
drop table if exists expense_attachments    cascade;
drop table if exists expenses               cascade;
drop table if exists parties                cascade;
drop table if exists inventory_transactions cascade;
drop table if exists master_items           cascade;
drop table if exists event_types            cascade;
drop table if exists business_settings      cascade;
drop table if exists business_members       cascade;
drop table if exists google_accounts        cascade;
drop table if exists businesses             cascade;

-- ---------------------------------------------------------------------------
-- 4. Functions (after tables/policies so nothing still references them)
-- ---------------------------------------------------------------------------
drop function if exists activate_pending_invites()             cascade;
drop function if exists has_perm(uuid, text, text)             cascade;
drop function if exists is_owner(uuid)                         cascade;
drop function if exists is_active_member(uuid)                 cascade;
drop function if exists storage_object_business_id(text)       cascade;
drop function if exists get_current_inventory(uuid)            cascade;
drop function if exists set_updated_at()                       cascade;

-- ---------------------------------------------------------------------------
-- 5. Enums / types
-- ---------------------------------------------------------------------------
drop type if exists member_status     cascade;
drop type if exists booking_status    cascade;
drop type if exists payment_method    cascade;
drop type if exists reminder_status   cascade;
drop type if exists txn_type          cascade;
drop type if exists expense_direction cascade;
drop type if exists booking_source    cascade;

-- ---------------------------------------------------------------------------
-- 6. Migration history — cleared so `supabase db push` treats the
--    consolidated files as a fresh baseline and applies all three.
--    Guarded: the table only exists on databases the CLI has pushed to.
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    delete from supabase_migrations.schema_migrations;
    raise notice 'supabase_migrations.schema_migrations cleared.';
  else
    raise notice 'supabase_migrations.schema_migrations not present — skipped.';
  end if;
end $$;

commit;

-- Done. Next steps: cleanup-storage.mjs → supabase db push → app onboarding → imports.
