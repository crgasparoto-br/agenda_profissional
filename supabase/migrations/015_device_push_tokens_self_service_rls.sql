-- 015_device_push_tokens_self_service_rls.sql
-- Permite que o proprio usuario autenticado gerencie seus tokens de push.

create policy device_push_tokens_select_self on device_push_tokens
for select
using (
  tenant_id = public.auth_tenant_id()
  and user_id = auth.uid()
);

create policy device_push_tokens_insert_self on device_push_tokens
for insert
with check (
  tenant_id = public.auth_tenant_id()
  and user_id = auth.uid()
);

create policy device_push_tokens_update_self on device_push_tokens
for update
using (
  tenant_id = public.auth_tenant_id()
  and user_id = auth.uid()
)
with check (
  tenant_id = public.auth_tenant_id()
  and user_id = auth.uid()
);

