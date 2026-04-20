-- 021_client_birthday.sql
-- Add birthday (date of birth) field to clients table.

alter table clients
  add column if not exists birthday date;

comment on column clients.birthday is
  'Data de aniversário do cliente. Útil para lembretes, mensagens personalizadas e fidelização.';
