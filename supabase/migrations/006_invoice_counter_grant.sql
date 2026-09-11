-- 006_invoice_counter_grant.sql — let booking.generate_invoice bump invoice_counter.
--
-- THE FLAG: invoice numbers are allocated OFFLINE on the client (by design — invoice
-- generation must work without connectivity) and the client then pushes the bumped
-- businesses.invoice_counter. The 002 baseline gates ALL businesses UPDATEs behind
-- settings.manage_business, so a member who holds booking.generate_invoice but NOT
-- settings.manage_business gets the counter push RLS-rejected: their invoice numbers
-- never reserve server-side and collide with the next device's allocation.
--
-- Fix (server-side, keeping the offline-allocation design), invite-activation pattern
-- from 004 — RLS decides WHICH rows, a BEFORE UPDATE guard trigger pins WHAT may change:
--   * businesses_update policy is REPLACED: owner OR settings.manage_business OR
--     booking.generate_invoice may UPDATE.
--   * guard trigger: an updater who lacks owner/manage_business but holds
--     generate_invoice may ONLY bump invoice_counter (strictly increasing; updated_at
--     is server-set by trg_businesses_updated_at and therefore exempt). Every other
--     column is compared OLD vs NEW and any drift raises.
--   * Server-side paths (service role / no JWT uid) stay unrestricted, same as 004.
--
-- NOTE: businesses has no updated_by column (audit columns exist on bookings only),
-- so the exemption list is exactly invoice_counter + updated_at.

-- ============ POLICY: extend businesses UPDATE ============
-- Replaced (not layered) so the row-visibility rule reads as one expression.
drop policy if exists businesses_update on businesses;
create policy businesses_update on businesses
  for update using (
    is_owner(id)
    or has_perm(id, 'settings', 'manage_business')
    or has_perm(id, 'booking', 'generate_invoice')
  )
  with check (
    is_owner(id)
    or has_perm(id, 'settings', 'manage_business')
    or has_perm(id, 'booking', 'generate_invoice')
  );

-- ============ GUARD: generate_invoice-only updaters may ONLY bump the counter ============
create or replace function guard_business_invoice_counter_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Server-side paths (service role, triggers — no JWT uid) and fully-privileged
  -- members stay unrestricted. is_owner is implied by has_perm but checked first
  -- to short-circuit the common owner path.
  if auth.uid() is null
     or is_owner(old.id)
     or has_perm(old.id, 'settings', 'manage_business') then
    return new;
  end if;

  -- From here the updater passed RLS only via booking.generate_invoice:
  -- the ONLY permitted change is a strictly increasing invoice_counter.
  -- (updated_at is exempt: trg_businesses_updated_at rewrites it server-side.)
  if new.id <> old.id
     or new.name <> old.name
     or new.business_type <> old.business_type
     or new.address is distinct from old.address
     or new.owner_name <> old.owner_name
     or new.logo_path is distinct from old.logo_path
     or new.currency <> old.currency
     or new.invoice_prefix <> old.invoice_prefix
     or new.owner_user_id <> old.owner_user_id
     or new.created_at <> old.created_at
     or new.deleted_at is distinct from old.deleted_at
  then
    raise exception 'businesses: booking.generate_invoice may only update invoice_counter';
  end if;

  if new.invoice_counter <= old.invoice_counter then
    raise exception 'businesses: invoice_counter may only increase (old %, new %)',
      old.invoice_counter, new.invoice_counter;
  end if;

  return new;
end;
$$;

create trigger trg_guard_business_invoice_counter
  before update on businesses
  for each row execute function guard_business_invoice_counter_update();
