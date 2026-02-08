# Agenda Profissional Monorepo

Monorepo MVP para agendamento multi-tenant (profissional individual ou clínica com múltiplos profissionais).

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

## Deploy das Edge Functions

```bash
npm run supabase:functions:deploy
```

## Scripts do monorepo

- `npm run dev:web`
- `npm run dev:supabase`
- `npm run dev:supabase:stop`
- `npm run supabase:migrate`
- `npm run supabase:functions:deploy`
- `npm run lint:web`
- `npm run typecheck`

## Fluxo MVP

1. Usuário faz login.
2. Onboarding chama `bootstrap-tenant` para criar `tenant + profile(owner) + professional + schedule`.
3. Operação diária no dashboard/clientes.
4. Novo agendamento chama `create-appointment` com profissional específico ou `any_available=true`.

## Segurança

- RLS habilitado nas tabelas de domínio.
- Escopo por `tenant_id` via helper `auth_tenant_id()`.
- Políticas por role (`owner/admin/receptionist` com CRUD do tenant).
- `staff` com leitura de agenda por padrão (update restrito opcional comentado em SQL).
- Nunca há acesso cruzado entre tenants.

## Observações MVP

- `client_id` em `appointments` é opcional no MVP.
- Anti-conflito é garantido por exclusion constraint (`appointments_no_overlap`) para status bloqueantes (`scheduled`/`confirmed`).
- Estrutura de billing (`plans/subscriptions/payments`) já criada, mas sem integração de gateway neste estágio.

