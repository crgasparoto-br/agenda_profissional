-- 008_unavailability_reason_visibility.sql
-- Controls whether absence reason can be shown to clients by the WhatsApp bot.

alter table professional_unavailability
  add column if not exists share_reason_with_client boolean not null default false;
