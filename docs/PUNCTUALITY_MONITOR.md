# Punctuality Monitor (Edge Function)

Funcao: `punctuality-monitor`

Titulo recomendado para UI (fora da Agenda): `Auditoria de Pontualidade`

Objetivo:
- Receber snapshots de ETA por consulta.
- Classificar pontualidade (`no_data`, `on_time`, `late_ok`, `late_critical`).
- Aplicar anti-oscilacao (troca de status somente com 2 snapshots consecutivos no mesmo estado).
- Atualizar `appointments.punctuality_*`.
- Registrar evento em `punctuality_events`.
- Enfileirar notificacao `in_app` em `notification_log`.
- Enfileirar notificacao `push` para `late_ok` e `late_critical` (com deduplicacao).
- Enfileirar notificacao `whatsapp` para profissional (opcional) quando a politica `fallback_whatsapp_for_professional` estiver habilitada.
- Opcionalmente calcular ETA automatico por provider (Google/Mapbox/OSRM) quando houver coordenadas de origem e destino.
- Bloquear monitoramento sem consentimento ativo em `client_location_consents` (`granted` e nao expirado).

## Autorizacao

1. `Authorization: Bearer <jwt>` de usuario admin/receptionist/owner do tenant.
2. Ou `x-monitor-secret: <PUNCTUALITY_MONITOR_SECRET>` com `tenant_id` no payload.

## Uso pelo app (snapshot por consulta)

O app pode enviar snapshot pontual por consulta usando:

- `appointment_id` no corpo
- `snapshots` com `eta_minutes` e metadados opcionais

Exemplo minimo:

```json
{
  "appointment_id": "uuid",
  "source": "mobile_app",
  "snapshots": [
    {
      "appointment_id": "uuid",
      "eta_minutes": 18
    }
  ]
}
```

## Payload (POST)

```json
{
  "tenant_id": "uuid-opcional-com-secret",
  "appointment_id": "uuid-opcional",
  "source": "monitor",
  "window_before_min": 15,
  "window_after_min": 180,
  "snapshots": [
    {
      "appointment_id": "uuid",
      "eta_minutes": 24,
      "captured_at": "2026-02-19T15:10:00Z",
      "client_lat": -23.56,
      "client_lng": -46.66,
      "traffic_level": "high",
      "provider": "maps",
      "raw_response": {}
    }
  ]
}
```

## Politica de atraso (configuravel)

A classificacao de pontualidade usa `delay_policies` por tenant/profissional:

- `tempo_maximo_atraso_min`
- `janela_aviso_antes_consulta_min`
- `monitor_interval_min`
- `fallback_whatsapp_for_professional`

Regra de prioridade:

1. policy do profissional (`professional_id`)
2. policy padrao do tenant (`professional_id = null`)
3. fallback interno (`tempo_maximo_atraso_min = 10`)

## ETA por provider (opcional)

Quando `eta_minutes` nao e enviado, a funcao tenta calcular ETA automatico se houver:

- origem (`client_lat`, `client_lng`) no snapshot atual
- ou ultima origem conhecida no historico da consulta
- destino configurado em `service_locations` (prioriza profissional, fallback tenant)

Variaveis de ambiente:

- `PUNCTUALITY_ETA_PROVIDER`: `none` | `google` | `mapbox` | `osrm`
- `PUNCTUALITY_ETA_RETRY_MAX`: tentativas de chamada (padrao `2`)
- `PUNCTUALITY_ETA_TIMEOUT_MS`: timeout por tentativa (padrao `4500`)
- `GOOGLE_MAPS_API_KEY` para provider `google`
- `MAPBOX_ACCESS_TOKEN` para provider `mapbox`

## Retorno

```json
{
  "ok": true,
  "processed": 12,
  "changed": 3,
  "notifications_queued": 2,
  "tenant_id": "uuid"
}
```

## Teste de integracao ETA -> monitor

Script disponivel no repositorio:

```bash
npm run test:integration:eta-monitor
```

Variaveis esperadas:

- `APP_SUPABASE_URL` (ou `SUPABASE_URL`)
- `APP_SUPABASE_SERVICE_ROLE_KEY` (ou `SUPABASE_SERVICE_ROLE_KEY`)
- `PUNCTUALITY_MONITOR_SECRET`
- `TEST_TENANT_ID` (ou `WHATSAPP_DEFAULT_TENANT_ID`)
- `TEST_APPOINTMENT_ID` (consulta de teste valida)
- `TEST_CLIENT_LAT` e `TEST_CLIENT_LNG` (opcionais)

O script:

- executa 2 chamadas ao `punctuality-monitor` sem enviar `eta_minutes`
- valida persistencia em `appointment_eta_snapshots`
- exige pelo menos 1 snapshot com `provider` e `eta_minutes` preenchidos
- consulta `appointments.punctuality_*` para confirmar atualizacao do monitor

## Teste E2E do fluxo completo

Script:

```bash
npm run test:e2e:punctuality
```

Cobre os cenarios:

- `SEM_CONSENTIMENTO` (consulta ignorada pelo monitor)
- `NO_DATA`
- `LATE_OK`
- `LATE_CRITICAL`
- retorno `ON_TIME`
- dedupe/throttling de notificacoes por tipo/canal
