# Punctuality WhatsApp Dispatcher (Edge Function)

Funcao: `punctuality-whatsapp-dispatcher`

Objetivo:
- Consumir notificacoes `notification_log` no canal `whatsapp` com status `queued`.
- Enviar alerta de pontualidade para o profissional via WhatsApp.
- Atualizar status da notificacao para `sent` ou `failed`.

## Seguranca

- Requer `x-whatsapp-dispatcher-secret` (ou `secret` no payload) igual a `PUNCTUALITY_WHATSAPP_DISPATCHER_SECRET`.

## Payload (POST)

```json
{
  "secret": "opcional-quando-nao-vier-no-header",
  "tenant_id": "uuid-opcional",
  "limit": 50
}
```

## Canais e tipos processados

- `channel = whatsapp`
- `status = queued`
- `type in (punctuality_late_ok, punctuality_late_critical, punctuality_on_time)`

## Variaveis de ambiente

- `PUNCTUALITY_WHATSAPP_DISPATCHER_SECRET` (obrigatoria)
- `WHATSAPP_DISPATCH_PROVIDER`:
  - `none` (padrao): simulacao, marca como `sent` sem chamada ao Meta
  - `meta`: envio real para API WhatsApp Cloud
- `WHATSAPP_ACCESS_TOKEN` (obrigatoria em `meta`)
- `WHATSAPP_API_VERSION` (opcional, padrao `v22.0`)
- `WHATSAPP_PHONE_NUMBER_ID` (fallback quando nao houver em `whatsapp_channel_settings`)

## Retorno

```json
{
  "ok": true,
  "processed": 4,
  "sent": 3,
  "failed": 1,
  "provider": "none"
}
```
