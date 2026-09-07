-- Backup frequency default weekly → daily (ADR-056). Run once against an existing
-- Supabase project (SQL editor). New projects get the default from 001_schema.sql.
alter table business_settings alter column backup_frequency set default 'daily';
update business_settings set backup_frequency = 'daily', updated_at = now() where backup_frequency = 'weekly';
