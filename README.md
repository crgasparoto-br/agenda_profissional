# Agenda Profissional Monorepo

Monorepo MVP para agendamento multi-tenant (profissional individual ou equipe/empresa com múltiplos profissionais).

## Stack

- `apps/web`: Next.js (TypeScript, App Router)
- `apps/mobile`: Flutter (Dart)
- `supabase/`: Postgres + Auth + RLS + Edge Functions
- `packages/shared`: schemas Zod e tipos compartilhados

## Requisitos

- Node.js 20+
- npm 10+
- Flutter 3.24+
- Supabase CLI
- Docker (para `supabase start`)

## Setup

```bash
npm install
```

### 1) Subir Supabase local

```bash
npm run dev:supabase
```

### 2) Aplicar migrations

```bash
npm run supabase:migrate
```

### 3) Configurar variáveis de ambiente

- Web: copiar `apps/web/.env.example` para `apps/web/.env.local`
- Functions: copiar `supabase/functions/.env.example` para `supabase/functions/.env`

### 4) Rodar web

```bash
npm run dev:web
```

### 5) Rodar mobile

```bash
cd apps/mobile
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

Para Android físico na mesma rede da máquina, use o IP local do host no lugar de `127.0.0.1`:

```bash
cd apps/mobile
flutter run -d <DEVICE_ID> \
  --dart-define=SUPABASE_URL=http://<SEU_IP_LOCAL>:54321 \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

## Deploy das Edge Functions

```bash
npm run supabase:functions:deploy
```

## Integração WhatsApp + IA

1. Configure variáveis em `supabase/functions/.env` (veja `supabase/functions/.env.example`):
- `WHATSAPP_VERIFY_TOKEN`
- `WHATSAPP_ACCESS_TOKEN`
- `OPENAI_API_KEY`
- `WHATSAPP_PHONE_NUMBER_ID` (fallback opcional)
- `WHATSAPP_AUDIO_ENABLED` (fallback opcional para aceitar audio)
- `OPENAI_AUDIO_TRANSCRIPTION_MODEL` (opcional, padrao `gpt-4o-mini-transcribe`)
- `WHATSAPP_DEFAULT_TENANT_ID` (fallback opcional)
- `WHATSAPP_TENANT_MAP_JSON` (fallback opcional)

2. Publique a função:
```bash
supabase functions deploy whatsapp-webhook
```

3. No painel web (`/whatsapp`), cadastre o número oficial do profissional/organização com o `Phone Number ID` do Meta e habilite a IA.

4. Configure webhook no Meta WhatsApp:
- Verificação (`GET`): `.../functions/v1/whatsapp-webhook`
- Eventos (`POST`): `.../functions/v1/whatsapp-webhook`

## Scripts do monorepo

- `npm run dev:web`
- `npm run dev:supabase`
- `npm run dev:supabase:stop`
- `npm run supabase:migrate`
- `npm run supabase:functions:deploy`
- `npm run lint:web`
- `npm run typecheck`
- `npm run jira`
- `npm run jira:check`
- `npm run jira:plan`

## Automacao Jira

Ha um CLI local em `scripts/jira-cli.mjs` para operar backlog e execucao diretamente no Jira Cloud.

Setup rapido:

1. Copie `.env.example` para `.env.local`
2. Preencha `JIRA_BASE_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN` e `JIRA_PROJECT_KEY`
3. Para trocar de espaco/projeto, altere apenas `JIRA_PROJECT_KEY`
4. Rode:

```bash
npm run jira:check
```

Exemplos:

```bash
npm run jira -- project:info
npm run jira -- project:info --project OUTRO
npm run jira -- epic:create --summary "Onboarding MVP" --description "Fluxo inicial"
npm run jira -- issue:create --type Task --summary "Criar dashboard"
npm run jira -- transition:list AP-123
npm run jira -- issue:transition AP-123 --to "In Progress"
npm run jira -- plan:apply --file scripts/jira-plan.example.json --dry-run
```

Documentacao completa: [docs/jira-workflow.md](/d:/SolverIT/agenda_profissional/docs/jira-workflow.md)

## Extensao VS Code para Jira

Existe uma extensao local em `.tools/integracao_jira` que usa o CLI do Jira do projeto para operar tudo pelo VS Code.

Ela oferece:
- menu rapido no Command Palette
- status bar com acesso ao Jira do projeto
- criacao de epic, issue e subtask
- edicao de issue existente
- comentarios, transicoes, busca e aplicacao de plano JSON
- atribuicao de responsavel e link entre issues

Para desenvolver ou testar:

1. Abra a pasta da extensao no VS Code
2. Pressione `F5`
3. Na janela de Extension Development Host, abra este workspace
4. Execute `Integracao Jira: Menu`

## Fluxo MVP

1. Usuário faz login.
2. Onboarding chama `bootstrap-tenant` para criar `organizacao + profile(owner) + professional + schedule`.
3. Operação diária no dashboard/clientes.
4. Novo agendamento chama `create-appointment` com profissional específico ou `any_available=true`.

## Segurança

- RLS habilitado nas tabelas de domínio.
- Escopo por `tenant_id` via helper `auth_tenant_id()`.
- Políticas por role (`owner/admin/receptionist` com CRUD da organizacao).
- `staff` com leitura de agenda por padrão (update restrito opcional comentado em SQL).
- Nunca há acesso cruzado entre tenants.

## Observações MVP

- `client_id` em `appointments` é opcional no MVP.
- Anti-conflito é garantido por exclusion constraint (`appointments_no_overlap`) para status bloqueantes (`scheduled`/`confirmed`).
- Estrutura de billing (`plans/subscriptions/payments`) já criada, mas sem integração de gateway neste estágio.

