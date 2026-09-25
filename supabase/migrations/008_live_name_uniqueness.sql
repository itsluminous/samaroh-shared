-- 008_live_name_uniqueness.sql — parties / master_items: name uniqueness over LIVE rows only.
--
-- BUG (proven on the live DB 2026-09-25 with owner-JWT probes): deleting a party or a
-- master item is a soft delete (deleted_at tombstone; sync engines never hard-delete),
-- but the 001 baseline declared `unique (business_id, name)` on both tables as a plain
-- NON-PARTIAL constraint (parties_business_id_name_key, master_items_business_id_name_key).
-- A tombstoned row therefore keeps OWNING its name forever. Both clients mint a fresh id
-- for a re-created name and dedup against LIVE rows only, so every attempt to re-create a
-- deleted party/item name — "Ganga Bhog" again after deleting "Ganga Bhog" — is rejected
-- by Postgres with 23505 (PostgREST 409) and the outbox item retries forever.
--
-- note_tags (005: uq_note_tags_biz_name on (business_id, lower(name)) WHERE deleted_at IS
-- NULL) and event_types (001: uq_event_types_biz_label WHERE deleted_at IS NULL) already
-- follow the right pattern; this migration brings parties and master_items in line.
--
-- CONTRACT (ADR in both app repos' docs/decisions.md):
--   * clients NEVER reuse / resurrect a tombstoned id — a re-created name is a brand-new row;
--   * the server enforces uniqueness of a name per business over LIVE rows only, and does
--     so CASE-INSENSITIVELY (lower(name)), matching note_tags. This is stricter than the
--     old constraint for mixed-case twins ('Ram Sweets' vs 'ram sweets'); the pre-check
--     below fails loudly (listing the offending names) if any such LIVE pair exists, so
--     the owner can rename first. Verified on the live DB at authoring time: 0 collisions.
--
-- IDEMPOTENT: safe to re-run (drop … if exists / create … if not exists). Transactional:
-- the whole file is one statement batch in the SQL editor / psql; the pre-check aborting
-- leaves the old constraints untouched.

-- ---------- PRE-CHECK: no case-insensitive collisions among LIVE rows ----------
do $$
declare
  v_bad text;
begin
  select string_agg(format('%s: %s', business_id, names), E'\n' order by business_id)
    into v_bad
  from (
    select business_id, lower(name) as lname,
           string_agg(quote_literal(name), ' / ' order by name) as names
    from parties
    where deleted_at is null
    group by business_id, lower(name)
    having count(*) > 1
  ) c;
  if v_bad is not null then
    raise exception using
      message = 'migration 008 aborted: LIVE parties collide case-insensitively — rename first',
      detail  = v_bad;
  end if;

  select string_agg(format('%s: %s', business_id, names), E'\n' order by business_id)
    into v_bad
  from (
    select business_id, lower(name) as lname,
           string_agg(quote_literal(name), ' / ' order by name) as names
    from master_items
    where deleted_at is null
    group by business_id, lower(name)
    having count(*) > 1
  ) c;
  if v_bad is not null then
    raise exception using
      message = 'migration 008 aborted: LIVE master_items collide case-insensitively — rename first',
      detail  = v_bad;
  end if;
end
$$;

-- ---------- PARTIES ----------
alter table parties
  drop constraint if exists parties_business_id_name_key;

-- Live parties: case-insensitive uniqueness per business; tombstones do not block reuse.
create unique index if not exists uq_parties_biz_name
  on parties (business_id, lower(name))
  where deleted_at is null;

comment on table parties is
  'Expense counterparties. Name is unique per business CASE-INSENSITIVELY over LIVE rows only (uq_parties_biz_name) — a tombstoned party''s name can be re-created as a new row.';

-- ---------- MASTER ITEMS ----------
alter table master_items
  drop constraint if exists master_items_business_id_name_key;

-- Live items: case-insensitive uniqueness per business; tombstones do not block reuse.
create unique index if not exists uq_master_items_biz_name
  on master_items (business_id, lower(name))
  where deleted_at is null;

comment on table master_items is
  'Inventory master items. Name is unique per business CASE-INSENSITIVELY over LIVE rows only (uq_master_items_biz_name) — a tombstoned item''s name can be re-created as a new row.';
