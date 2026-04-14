-- 018_whatsapp_meta_integrations.sql
-- Stores the WhatsApp/Meta connection owned by each tenant.

create table if not exists whatsapp_meta_integrations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  provider text not null default 'meta',
  connection_method text not null default 'embedded_signup',
  connection_status text not null default 'not_connected',
  meta_business_account_id text,
  meta_phone_number_id text,
  whatsapp_number text,
  verified_name text,
  display_name text,
  account_label text,
  last_error text,
  connected_at timestamptz,
  last_synced_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id),
  constraint whatsapp_meta_integrations_provider_check
    check (provider in ('meta')),
  constraint whatsapp_meta_integrations_connection_method_check
    check (connection_method in ('embedded_signup', 'manual_import')),
  constraint whatsapp_meta_integrations_connection_status_check
    check (connection_status in ('not_connected', 'pending', 'connected', 'error', 'disconnected'))
);

create unique index if not exists idx_whatsapp_meta_integrations_phone_id
  on whatsapp_meta_integrations(meta_phone_number_id)
  where meta_phone_number_id is not null;

create index if not exists idx_whatsapp_meta_integrations_tenant_status
  on whatsapp_meta_integrations(tenant_id, connection_status);

alter table whatsapp_meta_integrations enable row level security;

create policy whatsapp_meta_integrations_select_tenant on whatsapp_meta_integrations
for select
using (tenant_id = public.auth_tenant_id());

create policy whatsapp_meta_integrations_mutate_admin on whatsapp_meta_integrations
for all
using (tenant_id = public.auth_tenant_id() and public.is_tenant_admin())
with check (tenant_id = public.auth_tenant_id() and public.is_tenant_admin());
