# Data Model

## Entidades principais

- `tenants`: organização (individual ou equipe/empresa)
- `profiles`: usuário autenticado (mapeado a `auth.users`)
- `professionals`: profissionais de atendimento (com ou sem `user_id`)
- `specialties`: especialidades do tenant
- `services`: serviços ofertados
- `professional_services`: quais serviços cada profissional executa
- `professional_specialties`: quais especialidades cada profissional cobre
- `clients`: pacientes/clientes
- `professional_schedule_settings`: configuração de agenda e slots
- `appointments`: agendamentos
- `notification_log`: histórico de notificações
- `plans/subscriptions/payments`: camada de billing preparada para evolução

## Diagrama textual (resumo)

- `tenants 1:N profiles`
- `tenants 1:N professionals`
- `tenants 1:N specialties`
- `tenants 1:N services`
- `professionals N:N services` via `professional_services`
- `professionals N:N specialties` via `professional_specialties`
- `tenants 1:N clients`
- `professionals 1:1 professional_schedule_settings` (por tenant)
- `appointments` referencia `tenant + client/service/specialty/professional`
- `notification_log N:1 appointments`

## Multi-tenant

Todas as tabelas de domínio carregam `tenant_id`. FKs compostas (`tenant_id`, `id`) evitam referência cruzada entre tenants no nível de banco.

## Anti-conflito de horário

`appointments` possui:

- `is_blocking` gerada por status (`scheduled`/`confirmed`)
- constraint `EXCLUDE USING gist` com:
  - `tenant_id`
  - `professional_id`
  - `tstzrange(starts_at, ends_at, '[)')`
- filtro `WHERE (is_blocking)`

Com isso, agendamentos `cancelled/done` deixam de bloquear horário automaticamente.

## Índices críticos

- Índices por `tenant_id` em tabelas operacionais
- `appointments(tenant_id, professional_id, starts_at)`
- `professional_services(tenant_id, service_id)`
- `clients(tenant_id, phone)`

## RLS

- Funções helper:
  - `auth_tenant_id()`
  - `auth_role()`
  - `is_tenant_admin()`
- Políticas garantem isolamento por tenant e permissões por role.

