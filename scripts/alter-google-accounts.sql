-- Fix: google_accounts sync push rejected with
--   null value in column "refresh_token_cipher" of relation "google_accounts"
--   violates not-null constraint
--
-- The client links Google accounts on-device (Credential Manager) and NEVER sends
-- a token cipher (ADR-003) — but the baseline schema declared the column NOT NULL,
-- so every google_accounts insert from the app was rejected.
--
-- Paste the line below into the Supabase SQL editor and run it once.
-- The stuck outbox row on the phone retries automatically on the next sync.

alter table google_accounts alter column refresh_token_cipher drop not null;
