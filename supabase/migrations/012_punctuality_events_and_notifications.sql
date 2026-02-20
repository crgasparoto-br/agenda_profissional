-- 012_punctuality_events_and_notifications.sql
-- Eventos de mudanca de pontualidade + canais/tipos de notificacao no app.

alter type notification_channel add value if not exists 'push';
alter type notification_channel add value if not exists 'in_app';

alter type notification_type add value if not exists 'punctuality_on_time';
alter type notification_type add value if not exists 'punctuality_late_ok';
alter type notification_type add value if not exists 'punctuality_late_critical';

create table if not exists punctuality_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  appointment_id uuid not null,
  old_status punctuality_status not null,
  new_status punctuality_status not null,
  eta_minutes integer,
  minutes_to_start integer,
  predicted_arrival_delay integer,
  max_allowed_delay integer,
  source text not null default 'monitor',
  occurred_at timestamptz not null default now(),
  payload jsonb not null default '{}'::jsonb,
  constraint punctuality_events_appointment_fk
    foreign key (tenant_id, appointment_id)
    references appointments (tenant_id, id)
    on delete cascade
);

create index if not exists idx_punctuality_events_tenant_appointment_occurred
  on punctuality_events(tenant_id, appointment_id, occurred_at desc);

create index if not exists idx_punctuality_events_tenant_new_status
  on punctuality_events(tenant_id, new_status, occurred_at desc);

alter table punctuality_events enable row level security;

create policy punctuality_events_select_tenant on punctuality_events
for select
using (tenant_id = public.auth_tenant_id());

create policy punctuality_events_mutate_admin on punctuality_events
for all
using (tenant_id = public.auth_tenant_id() and public.is_tenant_admin())
with check (tenant_id = public.auth_tenant_id() and public.is_tenant_admin());

