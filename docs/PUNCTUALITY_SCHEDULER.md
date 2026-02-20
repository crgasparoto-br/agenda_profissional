# Punctuality Scheduler (Edge Function)

Funcao: `punctuality-scheduler`

Objetivo:
- Executar monitoramento periodico automatico.
- Descobrir tenants com consultas ativas na janela configurada.
- Disparar `punctuality-monitor` para cada tenant.
- Disparar `punctuality-push-dispatcher` para cada tenant apos o monitor.
- Disparar `punctuality-whatsapp-dispatcher` para cada tenant apos o monitor.

## Seguranca

- Requer `x-scheduler-secret` (ou `secret` no payload) igual a `PUNCTUALITY_SCHEDULER_SECRET`.
- `punctuality-monitor` e chamado internamente com `x-monitor-secret`.
- `punctuality-push-dispatcher` e chamado internamente com `x-push-dispatcher-secret`.
- `punctuality-whatsapp-dispatcher` e chamado internamente com `x-whatsapp-dispatcher-secret`.

Variaveis obrigatorias de ambiente:
- `PUNCTUALITY_SCHEDULER_SECRET`
- `PUNCTUALITY_MONITOR_SECRET`
- `PUNCTUALITY_PUSH_DISPATCHER_SECRET`
- `PUNCTUALITY_WHATSAPP_DISPATCHER_SECRET` (opcional, recomendado)

## Payload (POST)

```json
{
  "secret": "opcional-quando-nao-vier-no-header",
  "tenant_id": "uuid-opcional",
  "source": "scheduler",
  "window_before_min": 15,
  "window_after_min": 180,
  "max_tenants": 200
}
```

## Retorno

```json
{
  "ok": true,
  "triggered": 12,
  "changed_total": 7,
  "notifications_total": 5,
  "push_processed_total": 5,
  "push_sent_total": 5,
  "push_failed_total": 0,
  "whatsapp_processed_total": 2,
  "whatsapp_sent_total": 2,
  "whatsapp_failed_total": 0,
  "results": []
}
```

Exemplo de `results` por tenant:

```json
{
  "tenant_id": "uuid",
  "ok": true,
  "monitor": {
    "ok": true,
    "status": 200,
    "changed": 1,
    "notifications_queued": 1
  },
  "push_dispatcher": {
    "ok": true,
    "status": 200,
    "processed": 1,
    "sent": 1,
    "failed": 0
  },
  "whatsapp_dispatcher": {
    "ok": true,
    "status": 200,
    "processed": 1,
    "sent": 1,
    "failed": 0
  }
}
```

## Agendamento sugerido

- Criar trigger agendada no Supabase para executar `punctuality-scheduler` a cada 5 minutos.
- Header recomendado:
  - `x-scheduler-secret: <PUNCTUALITY_SCHEDULER_SECRET>`
