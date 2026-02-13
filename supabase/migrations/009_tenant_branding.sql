-- 009_tenant_branding.sql
-- Tenant branding support (custom logo) and scoped storage policies.

alter table tenants
  add column if not exists logo_url text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'tenant-assets',
  'tenant-assets',
  true,
  5242880,
  array['image/png', 'image/jpeg', 'image/webp', 'image/svg+xml']
)
on conflict (id) do nothing;

create policy tenant_assets_select_tenant on storage.objects
for select
to authenticated
using (
  bucket_id = 'tenant-assets'
  and split_part(name, '/', 1) = public.auth_tenant_id()::text
);

create policy tenant_assets_insert_admin on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'tenant-assets'
  and split_part(name, '/', 1) = public.auth_tenant_id()::text
  and public.is_tenant_admin()
);

create policy tenant_assets_update_admin on storage.objects
for update
to authenticated
using (
  bucket_id = 'tenant-assets'
  and split_part(name, '/', 1) = public.auth_tenant_id()::text
  and public.is_tenant_admin()
)
with check (
  bucket_id = 'tenant-assets'
  and split_part(name, '/', 1) = public.auth_tenant_id()::text
  and public.is_tenant_admin()
);

create policy tenant_assets_delete_admin on storage.objects
for delete
to authenticated
using (
  bucket_id = 'tenant-assets'
  and split_part(name, '/', 1) = public.auth_tenant_id()::text
  and public.is_tenant_admin()
);
