-- 004_service_interval_and_schedule_cleanup.sql
-- Move interval responsibility to services and simplify professional schedule settings.

alter table services
  add column if not exists interval_min integer not null default 0
  check (interval_min >= 0 and interval_min <= 240);

alter table professional_schedule_settings
  drop column if exists slot_min,
  drop column if exists buffer_min;
