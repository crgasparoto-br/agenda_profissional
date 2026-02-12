-- 006_unavailability_datetime_range.sql
-- Promote professional unavailability from date range to datetime range.

alter table professional_unavailability
  add column if not exists starts_at timestamptz,
  add column if not exists ends_at timestamptz;

update professional_unavailability
set
  starts_at = coalesce(starts_at, starts_on::timestamptz),
  ends_at = coalesce(ends_at, (ends_on::timestamptz + interval '1 day'));

alter table professional_unavailability
  alter column starts_at set not null,
  alter column ends_at set not null;

alter table professional_unavailability
  drop constraint if exists professional_unavailability_date_check;

alter table professional_unavailability
  add constraint professional_unavailability_time_check check (ends_at > starts_at);

drop index if exists idx_professional_unavailability_tenant_prof_dates;
create index if not exists idx_professional_unavailability_tenant_prof_starts
  on professional_unavailability(tenant_id, professional_id, starts_at);

alter table professional_unavailability
  drop column if exists starts_on,
  drop column if exists ends_on;
