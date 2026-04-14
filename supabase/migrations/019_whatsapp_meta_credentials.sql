-- 019_whatsapp_meta_credentials.sql
-- Stores tenant-specific Meta access tokens outside tenant-readable tables.

create table if not exists whatsapp_meta_credentials (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  access_token text not null,
  token_type text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id)
);

alter table whatsapp_meta_credentials enable row level security;
