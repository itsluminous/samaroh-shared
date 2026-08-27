-- 004_party_business_flag.sql — parties get a business/personal flag.
--
-- Requirement: a party can be marked business-related (default) or personal
-- ("Associated with {business}?" yes/no pill on the add-party screen).
-- Personal parties are excluded from the financial reports; a dedicated
-- personal-expenses report covers them.
--
-- RLS: unaffected. The parties policies in 002_rls.sql
-- (parties_select/insert/update/delete) gate on has_perm(business_id, …) and
-- do not enumerate columns, and no column-level grants exist — the new column
-- is covered automatically.

alter table parties
  add column business_related boolean not null default true;

comment on column parties.business_related is
  'true = counts in financial reports; false = personal party, shown only in the personal-expenses report.';
