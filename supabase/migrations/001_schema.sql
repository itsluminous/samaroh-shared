-- 001_schema.sql — canonical Samaroh schema.
-- All tables: client-generated UUID PKs (offline creation), updated_at for LWW conflict
-- resolution, deleted_at tombstones (soft delete; sync engines never hard-delete synced rows).

-- ============ EXTENSIONS ============
create extension if not exists "uuid-ossp";

-- ============ ENUMS ============
create type member_status as enum ('invited', 'active', 'revoked');
create type booking_status as enum ('tentative', 'confirmed', 'completed', 'cancelled');
create type payment_method as enum ('cash', 'upi', 'bank_transfer', 'cheque', 'other');
create type reminder_status as enum ('pending', 'confirmed', 'snoozed', 'dismissed');
create type txn_type as enum ('add', 'remove');
create type expense_direction as enum ('paid', 'received');
create type booking_source as enum ('walk_in', 'phone', 'referral', 'repeat', 'other');

-- ============ BUSINESS & MEMBERSHIP (RBAC core) ============
create table businesses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  business_type text not null default 'Marriage Hall', -- free text w/ suggestions
  address text,
  owner_name text not null,
  logo_path text,                     -- Supabase Storage path
  currency text not null default 'INR',
  invoice_prefix text not null default 'INV',
  invoice_counter int not null default 0,
  owner_user_id uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table business_members (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  invited_email text not null,               -- identity key for invites
  user_id uuid references auth.users(id),    -- null until invite accepted
  display_name text not null,                -- owner-assigned name
  is_owner boolean not null default false,
  status member_status not null default 'invited',
  permissions jsonb not null default '{}',   -- JSON Schema in permissions/permissions-schema.json
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (business_id, invited_email)
);

-- Google account linkage (tokens encrypted at rest via pgsodium/Vault;
-- NEVER expose refresh tokens to other members)
create table google_accounts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  refresh_token_cipher text not null,
  scopes text[] not null,
  drive_root_folder_id text,
  calendar_id text,
  updated_at timestamptz not null default now()
);

-- ============ BOOKING ============
create table bookings (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  event_type text not null,        -- key from event-types.json or custom label
  event_icon text not null,        -- emoji, from type default or user-picked for Custom
  customer_name text not null,
  customer_phone text,
  start_date date not null,
  end_date date not null,          -- >= start_date; multi-day events supported
  start_time time,                 -- optional
  end_time time,
  total_amount numeric(12,2) not null default 0,
  security_deposit numeric(12,2) not null default 0,  -- tracked separately, refundable
  source booking_source,                               -- optional
  notes text,
  status booking_status not null default 'confirmed',
  gcal_event_id text,              -- set when synced to Google Calendar
  invoice_number text,             -- assigned on first invoice generation, immutable after
  created_by uuid not null references auth.users(id),
  updated_by uuid references auth.users(id),           -- audit
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index idx_bookings_biz_date on bookings(business_id, start_date);

-- Maintenance/closure blocks — NOT bookings; render grey-striped on calendar
create table date_blocks (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  start_date date not null,
  end_date date not null,
  reason text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- Every payment (the "advance" is simply the first payment row)
create table booking_payments (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references bookings(id) on delete cascade,
  business_id uuid not null references businesses(id) on delete cascade,
  amount numeric(12,2) not null check (amount > 0),
  paid_on date not null,
  method payment_method not null default 'cash',
  notes text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
-- due = bookings.total_amount - sum(booking_payments.amount where deleted_at is null)
-- ALWAYS computed, never stored.

create table payment_reminders (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references bookings(id) on delete cascade,
  business_id uuid not null references businesses(id) on delete cascade,
  remind_on date not null,
  status reminder_status not null default 'pending',
  amount_due_snapshot numeric(12,2) not null,   -- due at reminder creation time
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- ============ EXPENSES ============
create table parties (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  name text not null,
  phone text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (business_id, name)
);

create table expenses (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  party_id uuid not null references parties(id) on delete cascade,
  direction expense_direction not null default 'paid',  -- 'paid' = you gave (default)
  amount numeric(12,2) not null check (amount > 0),
  expense_date date not null,
  notes text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table expense_attachments (
  id uuid primary key default gen_random_uuid(),
  expense_id uuid not null references expenses(id) on delete cascade,
  business_id uuid not null references businesses(id) on delete cascade,
  drive_file_id text,                -- Google Drive = AUTHORITATIVE store (saves Supabase
                                     -- space; invoices can't be compressed hard like
                                     -- inventory images). Null while upload is pending.
  mime_type text not null,
  file_name text not null,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);
-- The file itself never touches Supabase Storage; only this metadata row syncs.
-- Local device cache path is kept in the client DB only (not synced).

-- ============ INVENTORY ============
create table master_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  name text not null,
  unit text not null,                -- 'pcs' | 'qty' | 'kg' | free text
  image_path text,                   -- Supabase Storage, ≤320px WebP
  drive_image_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (business_id, name)
);

create table inventory_transactions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  master_item_id uuid not null references master_items(id) on delete cascade,
  transaction_type txn_type not null,
  quantity numeric(10,3) not null check (quantity > 0),
  unit_price numeric(10,2) not null check (unit_price >= 0),
  remaining_quantity numeric(10,3) not null default 0,  -- FIFO lot tracking
  transaction_date timestamptz not null default now(),
  notes text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index idx_invtxn_fifo on inventory_transactions
  (business_id, master_item_id, transaction_date asc)
  where transaction_type = 'add' and remaining_quantity > 0 and deleted_at is null;

-- ============ SETTINGS ============
create table business_settings (
  business_id uuid primary key references businesses(id) on delete cascade,
  gcal_sync_enabled boolean not null default false,
  backup_frequency text not null default 'weekly',  -- 'daily'|'weekly'|'monthly'|'manual'
  last_backup_at timestamptz,
  updated_at timestamptz not null default now()
);

-- ============ updated_at TRIGGER (LWW conflict resolution) ============
-- The server clock is authoritative: every write bumps updated_at to now(), so
-- clients can pull incrementally (updated_at > cursor) and resolve conflicts
-- with last-write-wins on server time.
create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Applied to every synced table that carries updated_at.
-- (expense_attachments has no updated_at by design: it is immutable metadata —
-- created once, tombstoned via deleted_at; there is nothing to LWW-merge.)
create trigger trg_businesses_updated_at
  before insert or update on businesses
  for each row execute function set_updated_at();
create trigger trg_business_members_updated_at
  before insert or update on business_members
  for each row execute function set_updated_at();
create trigger trg_google_accounts_updated_at
  before insert or update on google_accounts
  for each row execute function set_updated_at();
create trigger trg_bookings_updated_at
  before insert or update on bookings
  for each row execute function set_updated_at();
create trigger trg_date_blocks_updated_at
  before insert or update on date_blocks
  for each row execute function set_updated_at();
create trigger trg_booking_payments_updated_at
  before insert or update on booking_payments
  for each row execute function set_updated_at();
create trigger trg_payment_reminders_updated_at
  before insert or update on payment_reminders
  for each row execute function set_updated_at();
create trigger trg_parties_updated_at
  before insert or update on parties
  for each row execute function set_updated_at();
create trigger trg_expenses_updated_at
  before insert or update on expenses
  for each row execute function set_updated_at();
create trigger trg_master_items_updated_at
  before insert or update on master_items
  for each row execute function set_updated_at();
create trigger trg_inventory_transactions_updated_at
  before insert or update on inventory_transactions
  for each row execute function set_updated_at();
create trigger trg_business_settings_updated_at
  before insert or update on business_settings
  for each row execute function set_updated_at();

-- ============ FIFO HELPER (web app reads current stock server-side) ============
-- Current stock = Σ(add qty) − Σ(remove qty); current value = Σ(remaining_quantity ×
-- unit_price) over open add lots. Android computes the same in the client DB.
create or replace function get_current_inventory(p_business_id uuid)
returns table (
  master_item_id uuid,
  name text,
  unit text,
  image_path text,
  current_quantity numeric,
  current_value numeric,
  last_transaction_at timestamptz
)
language sql
stable
as $$
  select
    mi.id as master_item_id,
    mi.name,
    mi.unit,
    mi.image_path,
    coalesce(sum(
      case t.transaction_type when 'add' then t.quantity else -t.quantity end
    ), 0) as current_quantity,
    coalesce(sum(
      case when t.transaction_type = 'add' then t.remaining_quantity * t.unit_price else 0 end
    ), 0) as current_value,
    max(t.transaction_date) as last_transaction_at
  from master_items mi
  left join inventory_transactions t
    on t.master_item_id = mi.id and t.deleted_at is null
  where mi.business_id = p_business_id
    and mi.deleted_at is null
  group by mi.id, mi.name, mi.unit, mi.image_path;
$$;
