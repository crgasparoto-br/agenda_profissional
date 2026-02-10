# Architecture

## Visão Geral

O repositório segue arquitetura de monorepo com separação por apps, pacote compartilhado e backend Supabase.

- `apps/web`: painel de operação (profissional/recepção)
- `apps/mobile`: app operacional para profissional
- `packages/shared`: contratos de entrada/saída e validação (`zod`)
- `supabase/migrations`: schema SQL + RLS
- `supabase/functions`: regras de domínio sensíveis (bootstrap e criação de agendamento)

## Camadas

1. `UI Layer`
- Next.js e Flutter com formulários e listagens.
- Responsável por autenticação e interação com Supabase.

2. `Domain/API Layer`
- Edge Functions:
  - `bootstrap-tenant`: inicialização idempotente do tenant.
  - `create-appointment`: validação e seleção de profissional com opção `any_available`.
  - `whatsapp-webhook`: recebe mensagens do WhatsApp, persiste contexto e responde via IA.

3. `Data Layer`
- PostgreSQL com schema multi-tenant.
- Integridade por FK compostas (`tenant_id + id`) e constraints.
- RLS obrigatória por tenant e role.

## Segurança

- `auth_tenant_id()` resolve tenant do usuário autenticado.
- Políticas RLS filtram `tenant_id` em `select/insert/update/delete`.
- `owner/admin/receptionist`: gestão completa do tenant.
- `staff`: leitura de agenda; política opcional para update do próprio atendimento já comentada.
- `bootstrap-tenant` usa `service_role` apenas para viabilizar primeiro vínculo atômico de identidade.

## Fluxo de Onboarding

1. Usuário autenticado chama `bootstrap-tenant`.
2. Função verifica se `profiles` já existe para `auth.uid()`.
3. Se não existir: cria `tenants`, `profiles(owner)`, `professionals` e `professional_schedule_settings`.
4. Retorna `tenant_id` e `professional_id`.

## Fluxo de Agendamento

1. UI envia payload para `create-appointment`.
2. Função valida payload com schema compartilhado.
3. Resolve `tenant_id` por `auth_tenant_id()`.
4. Se `any_available=true`, busca profissionais ativos habilitados ao serviço.
5. Verifica conflito por janela de horário e escolhe o primeiro livre.
6. Insere `appointments` com `status=scheduled`.
7. Constraint no banco impede race condition de overlap por profissional.

## Fluxo WhatsApp + IA

1. Meta WhatsApp chama `whatsapp-webhook` (GET de verificação e POST de eventos).
2. A função valida assinatura (quando `WHATSAPP_APP_SECRET` está configurado).
3. Resolve organização via `WHATSAPP_TENANT_MAP_JSON` ou `WHATSAPP_DEFAULT_TENANT_ID`.
4. Faz upsert de cliente por telefone WhatsApp.
5. Persiste histórico em `whatsapp_conversations` e `whatsapp_messages`.
6. Envia contexto recente para a API da OpenAI e gera resposta natural.
7. Publica resposta no WhatsApp Cloud API.

