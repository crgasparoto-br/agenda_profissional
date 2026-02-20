# Punctuality Push Dispatcher

Funcao: `punctuality-push-dispatcher`

Objetivo:
- Consumir notificacoes `notification_log` no canal `push` com status `queued`.
- Resolver destino (profissional da consulta -> `user_id` -> `device_push_tokens`).
- Enviar push por provider configurado.
- Atualizar status para `sent` ou `failed`.

## Fonte da fila

A fila e alimentada por `punctuality-monitor` em mudancas de status:
- `punctuality_late_ok`
- `punctuality_late_critical`

Com deduplicacao por janela (10 minutos por consulta/tipo/canal).

## Variaveis de ambiente

- `PUNCTUALITY_PUSH_DISPATCHER_SECRET`
- `PUSH_PROVIDER=none|expo`
- `EXPO_ACCESS_TOKEN` (quando `PUSH_PROVIDER=expo`)

## Payload (POST)

```json
{
  "secret": "opcional-se-nao-vier-no-header",
  "tenant_id": "uuid-opcional",
  "limit": 50
}
```

Header opcional:
- `x-push-dispatcher-secret: <PUNCTUALITY_PUSH_DISPATCHER_SECRET>`

## Retorno

```json
{
  "ok": true,
  "processed": 10,
  "sent": 8,
  "failed": 2,
  "provider": "expo"
}
```

