-- 013_notification_read_status.sql
-- Permite status de leitura para notificacoes in-app.

alter type notification_status add value if not exists 'read';

create index if not exists idx_notification_log_tenant_channel_status_created
  on notification_log(tenant_id, channel, status, created_at desc);

