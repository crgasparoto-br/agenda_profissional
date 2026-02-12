-- 007_whatsapp_channel_settings.sql
-- Per-tenant WhatsApp channel and AI assistant configuration.

create table if not exists whatsapp_channel_settings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  professional_id uuid,
  label text not null default 'Canal principal',
  whatsapp_number text not null,
  phone_number_id text not null,
  active boolean not null default true,
  ai_enabled boolean not null default true,
  ai_model text not null default 'gpt-4.1-mini',
  ai_system_prompt text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (phone_number_id),
  unique (tenant_id, professional_id),
  constraint whatsapp_channel_settings_professional_fk
    foreign key (tenant_id, professional_id)
    references professionals (tenant_id, id)
    on delete set null
);

create index if not exists idx_whatsapp_channel_settings_tenant_active
  on whatsapp_channel_settings(tenant_id, active);

create index if not exists idx_whatsapp_channel_settings_phone_number_id
  on whatsapp_channel_settings(phone_number_id);

alter table whatsapp_channel_settings enable row level security;

create policy whatsapp_channel_settings_select_tenant on whatsapp_channel_settings
for select
using (tenant_id = public.auth_tenant_id());

create policy whatsapp_channel_settings_mutate_admin on whatsapp_channel_settings
for all
using (tenant_id = public.auth_tenant_id() and public.is_tenant_admin())
with check (tenant_id = public.auth_tenant_id() and public.is_tenant_admin());
