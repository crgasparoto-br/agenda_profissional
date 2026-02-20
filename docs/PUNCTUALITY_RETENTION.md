# Punctuality Retention Cleanup (Edge Function)

Funcao: `punctuality-retention-cleanup`

Objetivo:
- Aplicar politica de retencao por tenant para dados de pontualidade.
- Remover dados antigos conforme LGPD/minimizacao de dados.

## Politica por tenant

Tabela: `data_retention_policies`

Campos principais:
- `keep_eta_snapshots_days`
- `keep_punctuality_events_days`
- `keep_notification_log_days`
- `delete_expired_consents_after_days`
- `enabled`

## Seguranca

- Requer `x-retention-secret` (ou `secret` no payload) igual a `PUNCTUALITY_RETENTION_SECRET`.

## Payload (POST)

```json
{
  "secret": "opcional-quando-nao-vier-no-header",
  "tenant_id": "uuid-opcional",
  "max_tenants": 200
}
```

## Escopo de limpeza

Por tenant com politica ativa:
- `appointment_eta_snapshots` por `captured_at`
- `punctuality_events` por `occurred_at`
- `notification_log` de pontualidade por `created_at`
- `client_location_consents` expirados por `expires_at` + janela de graça

## Retorno

```json
{
  "ok": true,
  "processed_tenants": 1,
  "totals": {
    "eta_snapshots_deleted": 10,
    "punctuality_events_deleted": 3,
    "notification_log_deleted": 5,
    "expired_consents_deleted": 2
  },
  "results": []
}
```
