-- 011_punctuality_module.sql
-- Base estrutural para previsao de pontualidade com localizacao.

create type punctuality_status as enum ('no_data', 'on_time', 'late_ok', 'late_critical');
create type consent_status as enum ('granted', 'denied', 'revoked', 'expired');

create table if not exists service_locations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  professional_id uuid,
  name text not null,
  address_line text not null,
  city text not null,
  state text not null,
  postal_code text,
  country text not null default 'BR',
  latitude numeric(10, 7),
  longitude numeric(10, 7),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  constraint service_locations_professional_fk
    foreign key (tenant_id, professional_id)
    references professionals (tenant_id, id)
    on delete cascade
);

create table if not exists delay_policies (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  professional_id uuid,
  tempo_maximo_atraso_min integer not null default 10 check (tempo_maximo_atraso_min between 0 and 180),
  janela_aviso_antes_consulta_min integer not null default 90 check (janela_aviso_antes_consulta_min between 5 and 1440),
  monitor_interval_min integer not null default 5 check (monitor_interval_min between 1 and 60),
  notify_client_on_late_ok boolean not null default true,
  notify_client_on_late_critical boolean not null default true,
  fallback_whatsapp_for_professional boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, professional_id),
  unique (tenant_id, id),
  constraint delay_policies_professional_fk
    foreign key (tenant_id, professional_id)
    references professionals (tenant_id, id)
    on delete cascade
);

create table if not exists client_location_consents (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  client_id uuid not null,
  appointment_id uuid not null,
  consent_status consent_status not null,
  consent_text_version text not null,
  granted_at timestamptz,
  expires_at timestamptz,
  source_channel text not null default 'whatsapp',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  constraint client_location_consents_client_fk
    foreign key (tenant_id, client_id)
    references clients (tenant_id, id)
    on delete cascade,
  constraint client_location_consents_appointment_fk
    foreign key (tenant_id, appointment_id)
    references appointments (tenant_id, id)
    on delete cascade
);

create table if not exists appointment_eta_snapshots (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  appointment_id uuid not null,
  captured_at timestamptz not null default now(),
  eta_minutes integer,
  minutes_to_start integer not null,
  predicted_arrival_delay integer,
  status punctuality_status not null default 'no_data',
  client_lat numeric(10, 7),
  client_lng numeric(10, 7),
  traffic_level text,
  provider text,
  raw_response jsonb not null default '{}'::jsonb,
  constraint appointment_eta_snapshots_appointment_fk
    foreign key (tenant_id, appointment_id)
    references appointments (tenant_id, id)
    on delete cascade
);

alter table appointments
  add column if not exists punctuality_status punctuality_status not null default 'no_data',
  add column if not exists punctuality_eta_min integer,
  add column if not exists punctuality_predicted_delay_min integer,
  add column if not exists punctuality_last_calculated_at timestamptz;

create index if not exists idx_service_locations_tenant_professional
  on service_locations(tenant_id, professional_id);
create index if not exists idx_delay_policies_tenant_professional
  on delay_policies(tenant_id, professional_id);
create index if not exists idx_client_location_consents_tenant_appointment
  on client_location_consents(tenant_id, appointment_id);
create index if not exists idx_eta_snapshots_appointment_captured
  on appointment_eta_snapshots(tenant_id, appointment_id, captured_at desc);
create index if not exists idx_appointments_tenant_punctuality_status
  on appointments(tenant_id, punctuality_status);

alter table service_locations enable row level security;
alter table delay_policies enable row level security;
alter table client_location_consents enable row level security;
alter table appointment_eta_snapshots enable row level security;

create policy service_locations_select_tenant on service_locations
for select
using (tenant_id = public.auth_tenant_id());

create policy service_locations_mutate_admin on service_locations
for all
using (tenant_id = public.auth_tenant_id() and public.is_tenant_admin())
with check (tenant_id = public.auth_tenant_id() and public.is_tenant_admin());

create policy delay_policies_select_tenant on delay_policies
for select
using (tenant_id = public.auth_tenant_id());

create policy delay_policies_mutate_admin on delay_policies
for all
using (tenant_id = public.auth_tenant_id() and public.is_tenant_admin())
with check (tenant_id = public.auth_tenant_id() and public.is_tenant_admin());

create policy client_location_consents_select_tenant on client_location_consents
for select
using (tenant_id = public.auth_tenant_id());

create policy client_location_consents_mutate_admin on client_location_consents
for all
using (tenant_id = public.auth_tenant_id() and public.is_tenant_admin())
with check (tenant_id = public.auth_tenant_id() and public.is_tenant_admin());

create policy appointment_eta_snapshots_select_tenant on appointment_eta_snapshots
for select
using (tenant_id = public.auth_tenant_id());

create policy appointment_eta_snapshots_mutate_admin on appointment_eta_snapshots
for all
using (tenant_id = public.auth_tenant_id() and public.is_tenant_admin())
with check (tenant_id = public.auth_tenant_id() and public.is_tenant_admin());
