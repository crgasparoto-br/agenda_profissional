-- 016_data_retention_policy.sql
-- Politica de retencao e protecao de dados (LGPD) para modulo de pontualidade.

create table if not exists data_retention_policies (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  keep_eta_snapshots_days integer not null default 90 check (keep_eta_snapshots_days between 1 and 3650),
  keep_punctuality_events_days integer not null default 180 check (keep_punctuality_events_days between 1 and 3650),
  keep_notification_log_days integer not null default 180 check (keep_notification_log_days between 1 and 3650),
  delete_expired_consents_after_days integer not null default 30 check (delete_expired_consents_after_days between 0 and 3650),
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id),
  unique (tenant_id, id)
);

create index if not exists idx_data_retention_policies_tenant_enabled
  on data_retention_policies(tenant_id, enabled);

alter table data_retention_policies enable row level security;

create policy data_retention_policies_select_tenant on data_retention_policies
for select
using (tenant_id = public.auth_tenant_id());

create policy data_retention_policies_mutate_admin on data_retention_policies
for all
using (tenant_id = public.auth_tenant_id() and public.is_tenant_admin())
with check (tenant_id = public.auth_tenant_id() and public.is_tenant_admin());
