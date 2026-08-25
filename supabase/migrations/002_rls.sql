-- 002_rls.sql — Row Level Security: authoritative permission enforcement.
--
-- Three helper functions read business_members for the calling user (auth.uid()):
--   is_active_member(biz) — any active membership (owner or employee)
--   is_owner(biz)         — business owner (implicit full access, cannot be revoked)
--   has_perm(biz, module, action) — owner OR active member whose permissions jsonb
--                                    grants {module: {action: true}}
--
-- Permission mapping per table (module.action):
--   bookings            -> booking.view/create/edit/delete
--   date_blocks         -> booking.view/edit (blocking dates is a booking-edit power)
--   booking_payments    -> booking.view/record_payment/edit/delete
--   payment_reminders   -> booking.view/record_payment/delete
--   parties             -> expenses.view/manage_parties
--   expenses            -> expenses.view/create/edit/delete
--   expense_attachments -> expenses.view/create/edit/delete
--   master_items        -> inventory.view/manage_master_items
--   inventory_transactions -> inventory.view/create/edit/delete
--   businesses          -> member SELECT; settings.manage_business for writes
--   business_settings   -> member SELECT; settings.manage_business for writes
--   business_members    -> owner-managed; members may SELECT their own row
--   google_accounts     -> row owner only (refresh tokens NEVER visible to others)
--
-- NOTE: the app soft-deletes (sets deleted_at) via UPDATE; the DELETE policies below
-- exist so that even a hard delete is permission-guarded.

-- ============ HELPER FUNCTIONS ============
-- security definer so they can read business_members regardless of the caller's own
-- RLS visibility; search_path pinned to prevent hijacking.

create or replace function is_active_member(biz uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from business_members m
    where m.business_id = biz
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.deleted_at is null
  );
$$;

create or replace function is_owner(biz uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from businesses b
    where b.id = biz
      and b.owner_user_id = auth.uid()
      and b.deleted_at is null
  ) or exists (
    select 1
    from business_members m
    where m.business_id = biz
      and m.user_id = auth.uid()
      and m.is_owner
      and m.status = 'active'
      and m.deleted_at is null
  );
$$;

create or replace function has_perm(biz uuid, module text, action text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select is_owner(biz) or exists (
    select 1
    from business_members m
    where m.business_id = biz
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.deleted_at is null
      and coalesce((m.permissions -> module ->> action)::boolean, false)
  );
$$;

-- ============ ENABLE RLS ON EVERY TABLE ============
alter table businesses enable row level security;
alter table business_members enable row level security;
alter table google_accounts enable row level security;
alter table bookings enable row level security;
alter table date_blocks enable row level security;
alter table booking_payments enable row level security;
alter table payment_reminders enable row level security;
alter table parties enable row level security;
alter table expenses enable row level security;
alter table expense_attachments enable row level security;
alter table master_items enable row level security;
alter table inventory_transactions enable row level security;
alter table business_settings enable row level security;

-- ============ businesses ============
create policy businesses_select on businesses
  for select using (is_active_member(id) or owner_user_id = auth.uid());
create policy businesses_insert on businesses
  for insert with check (owner_user_id = auth.uid());
create policy businesses_update on businesses
  for update using (has_perm(id, 'settings', 'manage_business'))
  with check (has_perm(id, 'settings', 'manage_business'));
create policy businesses_delete on businesses
  for delete using (is_owner(id));

-- ============ business_settings ============
create policy business_settings_select on business_settings
  for select using (is_active_member(business_id));
create policy business_settings_insert on business_settings
  for insert with check (has_perm(business_id, 'settings', 'manage_business'));
create policy business_settings_update on business_settings
  for update using (has_perm(business_id, 'settings', 'manage_business'))
  with check (has_perm(business_id, 'settings', 'manage_business'));
create policy business_settings_delete on business_settings
  for delete using (is_owner(business_id));

-- ============ business_members (owner-managed; self-SELECT) ============
create policy business_members_select on business_members
  for select using (is_owner(business_id) or user_id = auth.uid());
create policy business_members_insert on business_members
  for insert with check (is_owner(business_id));
create policy business_members_update on business_members
  for update using (is_owner(business_id))
  with check (is_owner(business_id));
create policy business_members_delete on business_members
  for delete using (is_owner(business_id));

-- ============ google_accounts (row owner ONLY — token secrecy) ============
create policy google_accounts_select on google_accounts
  for select using (user_id = auth.uid());
create policy google_accounts_insert on google_accounts
  for insert with check (user_id = auth.uid());
create policy google_accounts_update on google_accounts
  for update using (user_id = auth.uid())
  with check (user_id = auth.uid());
create policy google_accounts_delete on google_accounts
  for delete using (user_id = auth.uid());

-- ============ bookings ============
create policy bookings_select on bookings
  for select using (has_perm(business_id, 'booking', 'view'));
create policy bookings_insert on bookings
  for insert with check (has_perm(business_id, 'booking', 'create'));
create policy bookings_update on bookings
  for update using (has_perm(business_id, 'booking', 'edit'))
  with check (has_perm(business_id, 'booking', 'edit'));
create policy bookings_delete on bookings
  for delete using (has_perm(business_id, 'booking', 'delete'));

-- ============ date_blocks (blocking dates needs booking.edit) ============
create policy date_blocks_select on date_blocks
  for select using (has_perm(business_id, 'booking', 'view'));
create policy date_blocks_insert on date_blocks
  for insert with check (has_perm(business_id, 'booking', 'edit'));
create policy date_blocks_update on date_blocks
  for update using (has_perm(business_id, 'booking', 'edit'))
  with check (has_perm(business_id, 'booking', 'edit'));
create policy date_blocks_delete on date_blocks
  for delete using (has_perm(business_id, 'booking', 'delete'));

-- ============ booking_payments ============
create policy booking_payments_select on booking_payments
  for select using (has_perm(business_id, 'booking', 'view'));
create policy booking_payments_insert on booking_payments
  for insert with check (has_perm(business_id, 'booking', 'record_payment'));
create policy booking_payments_update on booking_payments
  for update using (has_perm(business_id, 'booking', 'edit'))
  with check (has_perm(business_id, 'booking', 'edit'));
create policy booking_payments_delete on booking_payments
  for delete using (has_perm(business_id, 'booking', 'delete'));

-- ============ payment_reminders (created/confirmed by whoever can record payments) ============
create policy payment_reminders_select on payment_reminders
  for select using (has_perm(business_id, 'booking', 'view'));
create policy payment_reminders_insert on payment_reminders
  for insert with check (has_perm(business_id, 'booking', 'record_payment'));
create policy payment_reminders_update on payment_reminders
  for update using (has_perm(business_id, 'booking', 'record_payment'))
  with check (has_perm(business_id, 'booking', 'record_payment'));
create policy payment_reminders_delete on payment_reminders
  for delete using (has_perm(business_id, 'booking', 'delete'));

-- ============ parties ============
create policy parties_select on parties
  for select using (has_perm(business_id, 'expenses', 'view'));
create policy parties_insert on parties
  for insert with check (has_perm(business_id, 'expenses', 'manage_parties'));
create policy parties_update on parties
  for update using (has_perm(business_id, 'expenses', 'manage_parties'))
  with check (has_perm(business_id, 'expenses', 'manage_parties'));
create policy parties_delete on parties
  for delete using (has_perm(business_id, 'expenses', 'delete'));

-- ============ expenses ============
create policy expenses_select on expenses
  for select using (has_perm(business_id, 'expenses', 'view'));
create policy expenses_insert on expenses
  for insert with check (has_perm(business_id, 'expenses', 'create'));
create policy expenses_update on expenses
  for update using (has_perm(business_id, 'expenses', 'edit'))
  with check (has_perm(business_id, 'expenses', 'edit'));
create policy expenses_delete on expenses
  for delete using (has_perm(business_id, 'expenses', 'delete'));

-- ============ expense_attachments ============
create policy expense_attachments_select on expense_attachments
  for select using (has_perm(business_id, 'expenses', 'view'));
create policy expense_attachments_insert on expense_attachments
  for insert with check (has_perm(business_id, 'expenses', 'create'));
create policy expense_attachments_update on expense_attachments
  for update using (has_perm(business_id, 'expenses', 'edit'))
  with check (has_perm(business_id, 'expenses', 'edit'));
create policy expense_attachments_delete on expense_attachments
  for delete using (has_perm(business_id, 'expenses', 'delete'));

-- ============ master_items ============
create policy master_items_select on master_items
  for select using (has_perm(business_id, 'inventory', 'view'));
create policy master_items_insert on master_items
  for insert with check (has_perm(business_id, 'inventory', 'manage_master_items'));
create policy master_items_update on master_items
  for update using (has_perm(business_id, 'inventory', 'manage_master_items'))
  with check (has_perm(business_id, 'inventory', 'manage_master_items'));
create policy master_items_delete on master_items
  for delete using (has_perm(business_id, 'inventory', 'manage_master_items'));

-- ============ inventory_transactions ============
create policy inventory_transactions_select on inventory_transactions
  for select using (has_perm(business_id, 'inventory', 'view'));
create policy inventory_transactions_insert on inventory_transactions
  for insert with check (has_perm(business_id, 'inventory', 'create'));
create policy inventory_transactions_update on inventory_transactions
  for update using (has_perm(business_id, 'inventory', 'edit'))
  with check (has_perm(business_id, 'inventory', 'edit'));
create policy inventory_transactions_delete on inventory_transactions
  for delete using (has_perm(business_id, 'inventory', 'delete'));

-- ============ INVITE ACTIVATION ============
-- Invite flow: owner creates business_members(status='invited', invited_email=...).
-- When a user signs up (row appears in auth.users) with a matching email, the
-- membership auto-activates: user_id is set and status flips to 'active'.
create or replace function activate_pending_invites()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update business_members
     set user_id = new.id,
         status = 'active'
   where lower(invited_email) = lower(new.email)
     and status = 'invited'
     and user_id is null
     and deleted_at is null;
  return new;
end;
$$;

create trigger trg_activate_pending_invites
  after insert on auth.users
  for each row execute function activate_pending_invites();
