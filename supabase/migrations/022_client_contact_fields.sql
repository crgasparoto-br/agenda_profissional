-- 022_client_contact_fields.sql
-- Add common optional contact fields for a simple client registration.

alter table clients
  add column if not exists email text,
  add column if not exists preferred_contact_channel text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'clients_preferred_contact_channel_check'
  ) then
    alter table clients
      add constraint clients_preferred_contact_channel_check
      check (
        preferred_contact_channel is null
        or preferred_contact_channel in ('whatsapp', 'phone', 'email')
      );
  end if;
end $$;

comment on column clients.email is
  'Email opcional do cliente para contato secundario e comunicacoes.';

comment on column clients.preferred_contact_channel is
  'Canal de contato preferido do cliente: whatsapp, phone ou email.';