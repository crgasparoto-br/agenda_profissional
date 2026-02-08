-- 001_init.sql
-- Core schema for agenda-profissional MVP.
-- Decisions:
-- 1) Every domain table has tenant_id for strict tenant scoping.
-- 2) Appointments use an exclusion constraint with an is_blocking generated column
--    so cancelled/done do not block timeslots.

create extension if not exists "pgcrypto";
create extension if not exists "btree_gist";

create type tenant_type as enum ('individual', 'group');
create type user_role as enum ('owner', 'admin', 'staff', 'receptionist');
create type appointment_status as enum ('pending', 'scheduled', 'confirmed', 'cancelled', 'rescheduled', 'no_show', 'done');
create type appointment_source as enum ('professional', 'client_link', 'ai');
create type notification_channel as enum ('whatsapp', 'sms');
create type notification_type as enum ('confirmation', 'reminder_24h', 'reminder_2h', 'cancellation', 'reschedule');
create type notification_status as enum ('queued', 'sent', 'failed');

create table if not exists tenants (
  id uuid primary key default gen_random_uuid(),
  type tenant_type not null,
  name text not null,
  default_timezone text not null default 'America/Sao_Paulo',
  plan_code text not null default 'free',
  created_at timestamptz not null default now()
);

create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  tenant_id uuid not null references tenants(id) on delete cascade,
  role user_role not null default 'staff',
  full_name text not null,
  phone text,
  created_at timestamptz not null default now(),
  unique (tenant_id, id)
);

create table if not exists professionals (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  name text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, user_id)
);

create table if not exists specialties (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  name text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, name)
);

create table if not exists services (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  specialty_id uuid,
  name text not null,
  duration_min integer not null check (duration_min > 0 and duration_min <= 1440),
  price_cents integer,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, name),
  constraint services_specialty_fk
    foreign key (tenant_id, specialty_id)
    references specialties (tenant_id, id)
    on delete set null,
  constraint services_price_cents_check
    check (price_cents is null or price_cents >= 0)
);

create table if not exists professional_services (
  tenant_id uuid not null,
  professional_id uuid not null,
  service_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (tenant_id, professional_id, service_id),
  constraint professional_services_professional_fk
    foreign key (tenant_id, professional_id)
    references professionals (tenant_id, id)
    on delete cascade,
  constraint professional_services_service_fk
    foreign key (tenant_id, service_id)
    references services (tenant_id, id)
    on delete cascade
);

create table if not exists professional_specialties (
  tenant_id uuid not null,
  professional_id uuid not null,
  specialty_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (tenant_id, professional_id, specialty_id),
  constraint professional_specialties_professional_fk
    foreign key (tenant_id, professional_id)
    references professionals (tenant_id, id)
    on delete cascade,
  constraint professional_specialties_specialty_fk
    foreign key (tenant_id, specialty_id)
    references specialties (tenant_id, id)
    on delete cascade
);

create table if not exists clients (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  full_name text not null,
  phone text,
  notes text,
  created_at timestamptz not null default now(),
  unique (tenant_id, id)
);

create table if not exists professional_schedule_settings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  professional_id uuid not null,
  timezone text not null default 'America/Sao_Paulo',
  workdays jsonb not null default '[1,2,3,4,5]'::jsonb,
  work_hours jsonb not null default '{"start":"09:00","end":"18:00"}'::jsonb,
  slot_min integer not null default 30 check (slot_min > 0 and slot_min <= 240),
  buffer_min integer not null default 0 check (buffer_min >= 0 and buffer_min <= 240),
  created_at timestamptz not null default now(),
  unique (tenant_id, professional_id),
  unique (tenant_id, id),
  constraint professional_schedule_settings_professional_fk
    foreign key (tenant_id, professional_id)
    references professionals (tenant_id, id)
    on delete cascade
);

create table if not exists appointments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  client_id uuid,
  service_id uuid not null,
  specialty_id uuid,
  professional_id uuid not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status appointment_status not null default 'scheduled',
  source appointment_source not null default 'professional',
  created_by uuid references auth.users(id),
  assigned_at timestamptz,
  assigned_by uuid references auth.users(id),
  cancellation_reason text,
  created_at timestamptz not null default now(),
  is_blocking boolean generated always as (status in ('scheduled', 'confirmed')) stored,
  unique (tenant_id, id),
  constraint appointments_time_range_check check (ends_at > starts_at),
  constraint appointments_client_fk
    foreign key (tenant_id, client_id)
    references clients (tenant_id, id)
    on delete set null,
  constraint appointments_service_fk
    foreign key (tenant_id, service_id)
    references services (tenant_id, id)
    on delete restrict,
  constraint appointments_specialty_fk
    foreign key (tenant_id, specialty_id)
    references specialties (tenant_id, id)
    on delete set null,
  constraint appointments_professional_fk
    foreign key (tenant_id, professional_id)
    references professionals (tenant_id, id)
    on delete restrict
);

-- Blocks overlaps only for active statuses (scheduled/confirmed).
alter table appointments
  add constraint appointments_no_overlap
  exclude using gist (
    tenant_id with =,
    professional_id with =,
    tstzrange(starts_at, ends_at, '[)') with &&
  )
  where (is_blocking);

create table if not exists notification_log (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  appointment_id uuid not null,
  channel notification_channel not null,
  type notification_type not null,
  status notification_status not null default 'queued',
  provider_message_id text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint notification_log_appointment_fk
    foreign key (tenant_id, appointment_id)
    references appointments (tenant_id, id)
    on delete cascade
);

create table if not exists plans (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  billing_cycle text not null default 'monthly',
  price_cents integer not null default 0 check (price_cents >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists subscriptions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  plan_id uuid not null references plans(id),
  status text not null default 'trialing',
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  external_ref text,
  created_at timestamptz not null default now(),
  unique (tenant_id, id)
);

create table if not exists payments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  subscription_id uuid references subscriptions(id) on delete set null,
  amount_cents integer not null check (amount_cents >= 0),
  currency text not null default 'BRL',
  status text not null default 'pending',
  paid_at timestamptz,
  external_ref text,
  created_at timestamptz not null default now(),
  unique (tenant_id, id)
);

-- Important indexes.
create index if not exists idx_profiles_tenant_id on profiles(tenant_id);
create index if not exists idx_professionals_tenant_id on professionals(tenant_id);
create index if not exists idx_specialties_tenant_id on specialties(tenant_id);
create index if not exists idx_services_tenant_id on services(tenant_id);
create index if not exists idx_services_tenant_specialty on services(tenant_id, specialty_id);
create index if not exists idx_professional_services_tenant_service on professional_services(tenant_id, service_id);
create index if not exists idx_professional_specialties_tenant_specialty on professional_specialties(tenant_id, specialty_id);
create index if not exists idx_clients_tenant_id on clients(tenant_id);
create index if not exists idx_clients_tenant_phone on clients(tenant_id, phone);
create index if not exists idx_schedule_settings_tenant_id on professional_schedule_settings(tenant_id);
create index if not exists idx_appointments_tenant_prof_starts on appointments(tenant_id, professional_id, starts_at);
create index if not exists idx_appointments_tenant_starts on appointments(tenant_id, starts_at);
create index if not exists idx_appointments_tenant_status on appointments(tenant_id, status);
create index if not exists idx_notification_log_tenant_id on notification_log(tenant_id);
create index if not exists idx_subscriptions_tenant_id on subscriptions(tenant_id);
create index if not exists idx_payments_tenant_id on payments(tenant_id);

-- Helpful default plan seed (safe upsert behavior).
insert into plans (code, name, billing_cycle, price_cents, active)
values
  ('free', 'Plano Free', 'monthly', 0, true),
  ('pro', 'Plano Pro', 'monthly', 12900, true)
on conflict (code) do nothing;
