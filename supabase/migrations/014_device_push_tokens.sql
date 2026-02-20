-- 014_device_push_tokens.sql
-- Tokens de push para profissionais e dispatch de notificacoes mobile.

create table if not exists device_push_tokens (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  platform text not null check (platform in ('android', 'ios', 'web')),
  provider text not null default 'expo',
  token text not null,
  active boolean not null default true,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, user_id, provider, token)
);

create index if not exists idx_device_push_tokens_tenant_user_active
  on device_push_tokens(tenant_id, user_id, active);

create index if not exists idx_device_push_tokens_tenant_provider_active
  on device_push_tokens(tenant_id, provider, active);

alter table device_push_tokens enable row level security;

create policy device_push_tokens_select_tenant on device_push_tokens
for select
using (tenant_id = public.auth_tenant_id());

create policy device_push_tokens_mutate_admin on device_push_tokens
for all
using (tenant_id = public.auth_tenant_id() and public.is_tenant_admin())
with check (tenant_id = public.auth_tenant_id() and public.is_tenant_admin());

