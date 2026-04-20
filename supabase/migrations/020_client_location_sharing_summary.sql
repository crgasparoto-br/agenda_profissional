alter table clients
  add column if not exists location_sharing_enabled boolean not null default false,
  add column if not exists location_sharing_authorized_at timestamptz;

with latest_consent as (
  select distinct on (tenant_id, client_id)
    tenant_id,
    client_id,
    consent_status,
    granted_at,
    expires_at,
    updated_at
  from client_location_consents
  order by tenant_id, client_id, updated_at desc
)
update clients as c
set
  location_sharing_enabled =
    latest_consent.consent_status = 'granted'
    and (
      latest_consent.expires_at is null
      or latest_consent.expires_at > now()
    ),
  location_sharing_authorized_at =
    case
      when latest_consent.consent_status = 'granted'
        and (
          latest_consent.expires_at is null
          or latest_consent.expires_at > now()
        )
      then coalesce(latest_consent.granted_at, latest_consent.updated_at)
      else null
    end
from latest_consent
where c.tenant_id = latest_consent.tenant_id
  and c.id = latest_consent.client_id;