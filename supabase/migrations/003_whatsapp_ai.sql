-- 003_whatsapp_ai.sql
-- Persistence for WhatsApp conversations handled by AI assistant.

create table if not exists whatsapp_conversations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  client_id uuid,
  wa_phone text not null,
  status text not null default 'open',
  last_message_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, wa_phone),
  constraint whatsapp_conversations_client_fk
    foreign key (tenant_id, client_id)
    references clients (tenant_id, id)
    on delete set null
);

create table if not exists whatsapp_messages (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  conversation_id uuid not null,
  client_id uuid,
  direction text not null check (direction in ('inbound', 'outbound', 'system')),
  provider_message_id text,
  message_text text not null,
  ai_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (tenant_id, id),
  constraint whatsapp_messages_conversation_fk
    foreign key (tenant_id, conversation_id)
    references whatsapp_conversations (tenant_id, id)
    on delete cascade,
  constraint whatsapp_messages_client_fk
    foreign key (tenant_id, client_id)
    references clients (tenant_id, id)
    on delete set null
);

create index if not exists idx_whatsapp_conversations_tenant_phone
  on whatsapp_conversations(tenant_id, wa_phone);
create index if not exists idx_whatsapp_messages_tenant_conversation_created
  on whatsapp_messages(tenant_id, conversation_id, created_at desc);
create index if not exists idx_whatsapp_messages_tenant_direction_created
  on whatsapp_messages(tenant_id, direction, created_at desc);

alter table whatsapp_conversations enable row level security;
alter table whatsapp_messages enable row level security;

create policy whatsapp_conversations_select_tenant on whatsapp_conversations
for select
using (tenant_id = public.auth_tenant_id());

create policy whatsapp_conversations_mutate_admin on whatsapp_conversations
for all
using (tenant_id = public.auth_tenant_id() and public.is_tenant_admin())
with check (tenant_id = public.auth_tenant_id() and public.is_tenant_admin());

create policy whatsapp_messages_select_tenant on whatsapp_messages
for select
using (tenant_id = public.auth_tenant_id());

create policy whatsapp_messages_mutate_admin on whatsapp_messages
for all
using (tenant_id = public.auth_tenant_id() and public.is_tenant_admin())
with check (tenant_id = public.auth_tenant_id() and public.is_tenant_admin());
