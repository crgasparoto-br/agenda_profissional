-- 002_rls.sql
-- RLS strategy:
-- - Users are always scoped by tenant_id from their own profile.
-- - owner/admin/receptionist can fully manage operational tables.
-- - staff has read visibility and can be extended for constrained updates.

create or replace function public.auth_tenant_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select p.tenant_id
  from public.profiles p
  where p.id = auth.uid()
  limit 1;
$$;

create or replace function public.auth_role()
returns user_role
language sql
stable
security definer
set search_path = public
as $$
  select p.role
  from public.profiles p
  where p.id = auth.uid()
  limit 1;
$$;

create or replace function public.is_tenant_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.auth_role() in ('owner', 'admin', 'receptionist'), false);
$$;

alter table tenants enable row level security;
alter table profiles enable row level security;
alter table professionals enable row level security;
alter table specialties enable row level security;
alter table services enable row level security;
alter table professional_services enable row level security;
alter table professional_specialties enable row level security;
alter table clients enable row level security;
alter table professional_schedule_settings enable row level security;
alter table appointments enable row level security;
alter table notification_log enable row level security;
alter table plans enable row level security;
alter table subscriptions enable row level security;
alter table payments enable row level security;

-- TENANTS
create policy tenants_select_own_tenant on tenants
for select
using (id = public.auth_tenant_id());

create policy tenants_insert_bootstrap on tenants
for insert
to authenticated
with check (auth.uid() is not null);

create policy tenants_update_admin on tenants
for update
using (id = public.auth_tenant_id() and public.auth_role() in ('owner', 'admin'))
with check (id = public.auth_tenant_id() and public.auth_role() in ('owner', 'admin'));

-- PROFILES
create policy profiles_select_self_or_admin on profiles
for select
using (
  id = auth.uid()
  or (tenant_id = public.auth_tenant_id() and public.auth_role() in ('owner', 'admin'))
);

-- First profile bootstrap: user can create own owner profile once.
create policy profiles_insert_bootstrap_owner on profiles
for insert
to authenticated
with check (
  id = auth.uid()
  and role = 'owner'
  and not exists (select 1 from profiles p where p.id = auth.uid())
  and not exists (select 1 from profiles p2 where p2.tenant_id = profiles.tenant_id)
);

-- Tenant admins can create additional users in their tenant.
create policy profiles_insert_admin on profiles
for insert
to authenticated
with check (
  tenant_id = public.auth_tenant_id()
  and public.auth_role() in ('owner', 'admin')
  and role in ('admin', 'staff', 'receptionist')
);

create policy profiles_update_self on profiles
for update
using (id = auth.uid())
with check (id = auth.uid() and tenant_id = public.auth_tenant_id());

-- PROFESSIONALS
create policy professionals_select_tenant on professionals
for select
using (tenant_id = public.auth_tenant_id());

create policy professionals_mutate_admin on professionals
for all
using (tenant_id = public.auth_tenant_id() and public.is_tenant_admin())
with check (tenant_id = public.auth_tenant_id() and public.is_tenant_admin());

-- SPECIALTIES
create policy specialties_select_tenant on specialties
for select
using (tenant_id = public.auth_tenant_id());

create policy specialties_mutate_admin on specialties
for all
using (tenant_id = public.auth_tenant_id() and public.is_tenant_admin())
with check (tenant_id = public.auth_tenant_id() and public.is_tenant_admin());

-- SERVICES
create policy services_select_tenant on services
for select
using (tenant_id = public.auth_tenant_id());

create policy services_mutate_admin on services
for all
using (tenant_id = public.auth_tenant_id() and public.is_tenant_admin())
with check (tenant_id = public.auth_tenant_id() and public.is_tenant_admin());

-- PROFESSIONAL_SERVICES
create policy professional_services_select_tenant on professional_services
for select
using (tenant_id = public.auth_tenant_id());

create policy professional_services_mutate_admin on professional_services
for all
using (tenant_id = public.auth_tenant_id() and public.is_tenant_admin())
with check (tenant_id = public.auth_tenant_id() and public.is_tenant_admin());

-- PROFESSIONAL_SPECIALTIES
create policy professional_specialties_select_tenant on professional_specialties
for select
using (tenant_id = public.auth_tenant_id());

create policy professional_specialties_mutate_admin on professional_specialties
for all
using (tenant_id = public.auth_tenant_id() and public.is_tenant_admin())
with check (tenant_id = public.auth_tenant_id() and public.is_tenant_admin());

-- CLIENTS
create policy clients_select_tenant on clients
for select
using (tenant_id = public.auth_tenant_id());

create policy clients_mutate_admin on clients
for all
using (tenant_id = public.auth_tenant_id() and public.is_tenant_admin())
with check (tenant_id = public.auth_tenant_id() and public.is_tenant_admin());

-- SCHEDULE SETTINGS
create policy professional_schedule_settings_select_tenant on professional_schedule_settings
for select
using (tenant_id = public.auth_tenant_id());

create policy professional_schedule_settings_mutate_admin on professional_schedule_settings
for all
using (tenant_id = public.auth_tenant_id() and public.is_tenant_admin())
with check (tenant_id = public.auth_tenant_id() and public.is_tenant_admin());

-- APPOINTMENTS
create policy appointments_select_tenant on appointments
for select
using (tenant_id = public.auth_tenant_id());

create policy appointments_mutate_admin on appointments
for all
using (tenant_id = public.auth_tenant_id() and public.is_tenant_admin())
with check (tenant_id = public.auth_tenant_id() and public.is_tenant_admin());

-- Optional staff write policy (disabled by default):
-- create policy appointments_update_staff_own on appointments
-- for update
-- using (
--   tenant_id = public.auth_tenant_id()
--   and public.auth_role() = 'staff'
--   and exists (
--     select 1 from professionals pr
--     where pr.tenant_id = appointments.tenant_id
--       and pr.id = appointments.professional_id
--       and pr.user_id = auth.uid()
--   )
-- )
-- with check (
--   tenant_id = public.auth_tenant_id()
--   and public.auth_role() = 'staff'
--   and exists (
--     select 1 from professionals pr
--     where pr.tenant_id = appointments.tenant_id
--       and pr.id = appointments.professional_id
--       and pr.user_id = auth.uid()
--   )
-- );

-- NOTIFICATION LOG
create policy notification_log_select_tenant on notification_log
for select
using (tenant_id = public.auth_tenant_id());

create policy notification_log_mutate_admin on notification_log
for all
using (tenant_id = public.auth_tenant_id() and public.is_tenant_admin())
with check (tenant_id = public.auth_tenant_id() and public.is_tenant_admin());

-- PLANS (global catalog, read-only for authenticated users)
create policy plans_select_authenticated on plans
for select
to authenticated
using (true);

-- SUBSCRIPTIONS
create policy subscriptions_select_tenant on subscriptions
for select
using (tenant_id = public.auth_tenant_id());

create policy subscriptions_mutate_owner_admin on subscriptions
for all
using (tenant_id = public.auth_tenant_id() and public.auth_role() in ('owner', 'admin'))
with check (tenant_id = public.auth_tenant_id() and public.auth_role() in ('owner', 'admin'));

-- PAYMENTS
create policy payments_select_tenant on payments
for select
using (tenant_id = public.auth_tenant_id());

create policy payments_mutate_owner_admin on payments
for all
using (tenant_id = public.auth_tenant_id() and public.auth_role() in ('owner', 'admin'))
with check (tenant_id = public.auth_tenant_id() and public.auth_role() in ('owner', 'admin'));
