-- 017_whatsapp_audio_support.sql
-- Adds inbound audio support for WhatsApp conversations.

alter table if exists whatsapp_channel_settings
  add column if not exists audio_enabled boolean not null default false;

alter table if exists whatsapp_messages
  add column if not exists message_type text not null default 'text',
  add column if not exists media_id text,
  add column if not exists media_mime_type text,
  add column if not exists media_sha256 text,
  add column if not exists transcription_text text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'whatsapp_messages_message_type_check'
  ) then
    alter table whatsapp_messages
      add constraint whatsapp_messages_message_type_check
      check (message_type in ('text', 'audio'));
  end if;
end $$;
