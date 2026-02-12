-- 005_professional_unavailability.sql
-- Planned absences for professionals (vacations, events, leaves).

create table if not exists professional_unavailability (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  professional_id uuid not null,
  starts_on date not null,
  ends_on date not null,
  reason text,
  created_at timestamptz not null default now(),
  constraint professional_unavailability_date_check check (ends_on >= starts_on),
  constraint professional_unavailability_professional_fk
    foreign key (tenant_id, professional_id)
    references professionals (tenant_id, id)
    on delete cascade
);

create index if not exists idx_professional_unavailability_tenant_prof_dates
  on professional_unavailability(tenant_id, professional_id, starts_on, ends_on);

alter table professional_unavailability enable row level security;

create policy professional_unavailability_select_tenant on professional_unavailability
for select
using (tenant_id = public.auth_tenant_id());

create policy professional_unavailability_mutate_admin on professional_unavailability
for all
using (tenant_id = public.auth_tenant_id() and public.is_tenant_admin())
with check (tenant_id = public.auth_tenant_id() and public.is_tenant_admin());
