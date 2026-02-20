import { createClient } from "npm:@supabase/supabase-js@2.49.1";
import { z } from "npm:zod@3.23.8";

const jsonHeaders = { "Content-Type": "application/json" };
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-monitor-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};
const responseHeaders = { ...jsonHeaders, ...corsHeaders };

const SnapshotInputSchema = z.object({
  appointment_id: z.string().uuid(),
  eta_minutes: z.number().int().min(0).max(1440).nullable().optional(),
  captured_at: z.string().datetime().optional(),
  client_lat: z.number().min(-90).max(90).optional(),
  client_lng: z.number().min(-180).max(180).optional(),
  traffic_level: z.string().trim().max(20).optional(),
  provider: z.string().trim().max(40).optional(),
  raw_response: z.record(z.unknown()).optional()
});

const MonitorPayloadSchema = z.object({
  tenant_id: z.string().uuid().optional(),
  appointment_id: z.string().uuid().optional(),
  source: z.string().trim().min(1).max(40).default("monitor"),
  window_before_min: z.number().int().min(0).max(120).default(15),
  window_after_min: z.number().int().min(5).max(1440).default(180),
  snapshots: z.array(SnapshotInputSchema).default([])
});

type AppointmentRow = {
  id: string;
  tenant_id: string;
  professional_id: string;
  starts_at: string;
  punctuality_status: "no_data" | "on_time" | "late_ok" | "late_critical" | null;
  punctuality_eta_min: number | null;
  punctuality_predicted_delay_min: number | null;
};

type DelayPolicyRow = {
  tempo_maximo_atraso_min: number;
  fallback_whatsapp_for_professional: boolean;
};

type Coordinates = {
  lat: number;
  lng: number;
};

type ServiceLocationRow = {
  latitude: number | null;
  longitude: number | null;
};

type ConsentRow = {
  consent_status: "granted" | "denied" | "revoked" | "expired";
  expires_at: string | null;
};

type SnapshotRow = {
  status: "no_data" | "on_time" | "late_ok" | "late_critical";
  eta_minutes: number | null;
  predicted_arrival_delay: number | null;
  captured_at: string;
};

type NotificationType =
  | "punctuality_on_time"
  | "punctuality_late_ok"
  | "punctuality_late_critical";

function classifyPunctualityStatus(
  etaMinutes: number | null | undefined,
  minutesToStart: number,
  maxAllowedDelay: number
): "no_data" | "on_time" | "late_ok" | "late_critical" {
  if (etaMinutes === null || etaMinutes === undefined) return "no_data";
  const predictedDelay = etaMinutes - minutesToStart;
  if (predictedDelay <= 0) return "on_time";
  if (predictedDelay <= maxAllowedDelay) return "late_ok";
  return "late_critical";
}

function toNotificationType(status: string): NotificationType | null {
  if (status === "on_time") return "punctuality_on_time";
  if (status === "late_ok") return "punctuality_late_ok";
  if (status === "late_critical") return "punctuality_late_critical";
  return null;
}

function addMinutes(base: Date, deltaMinutes: number): Date {
  return new Date(base.getTime() + deltaMinutes * 60 * 1000);
}

function minutesUntil(now: Date, targetIso: string): number {
  const target = new Date(targetIso);
  return Math.floor((target.getTime() - now.getTime()) / 60000);
}

function resolveProviderName() {
  return (Deno.env.get("PUNCTUALITY_ETA_PROVIDER") ?? "none").trim().toLowerCase();
}

function classifyTrafficLevel(durationSec: number, durationTrafficSec: number | null): string | null {
  if (!durationTrafficSec || durationSec <= 0) return null;
  const ratio = durationTrafficSec / durationSec;
  if (ratio <= 1.1) return "low";
  if (ratio <= 1.35) return "medium";
  return "high";
}

async function fetchWithTimeout(url: string, timeoutMs = 4500, init?: RequestInit): Promise<Response> {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort("timeout"), timeoutMs);
  try {
    return await fetch(url, { ...init, signal: ctrl.signal });
  } finally {
    clearTimeout(timer);
  }
}

async function estimateEtaGoogle(origin: Coordinates, destination: Coordinates): Promise<{
  etaMinutes: number;
  trafficLevel: string | null;
  rawResponse: Record<string, unknown>;
  provider: string;
} | null> {
  const apiKey = Deno.env.get("GOOGLE_MAPS_API_KEY");
  if (!apiKey) return null;
  const origins = `${origin.lat},${origin.lng}`;
  const destinations = `${destination.lat},${destination.lng}`;
  const url =
    "https://maps.googleapis.com/maps/api/distancematrix/json" +
    `?origins=${encodeURIComponent(origins)}` +
    `&destinations=${encodeURIComponent(destinations)}` +
    "&mode=driving&departure_time=now&traffic_model=best_guess" +
    `&key=${encodeURIComponent(apiKey)}`;

  const timeoutMs = Number(Deno.env.get("PUNCTUALITY_ETA_TIMEOUT_MS") ?? "4500");
  const resp = await fetchWithTimeout(url, Number.isFinite(timeoutMs) ? timeoutMs : 4500);
  if (!resp.ok) return null;
  const data = (await resp.json()) as Record<string, unknown>;
  const rows = Array.isArray(data.rows) ? data.rows : [];
  const firstRow = rows[0] as Record<string, unknown> | undefined;
  const elements = firstRow && Array.isArray(firstRow.elements) ? firstRow.elements : [];
  const firstElement = elements[0] as Record<string, unknown> | undefined;
  if (!firstElement || firstElement.status !== "OK") return null;
  const duration = firstElement.duration as Record<string, unknown> | undefined;
  const durationInTraffic = firstElement.duration_in_traffic as Record<string, unknown> | undefined;
  const durationSec = Number(duration?.value ?? 0);
  const durationTrafficSec = Number(durationInTraffic?.value ?? durationSec);
  if (!Number.isFinite(durationTrafficSec) || durationTrafficSec <= 0) return null;
  return {
    etaMinutes: Math.max(1, Math.ceil(durationTrafficSec / 60)),
    trafficLevel: classifyTrafficLevel(durationSec, durationTrafficSec),
    rawResponse: data,
    provider: "google_distance_matrix"
  };
}

async function estimateEtaMapbox(origin: Coordinates, destination: Coordinates): Promise<{
  etaMinutes: number;
  trafficLevel: string | null;
  rawResponse: Record<string, unknown>;
  provider: string;
} | null> {
  const token = Deno.env.get("MAPBOX_ACCESS_TOKEN");
  if (!token) return null;
  const coords = `${origin.lng},${origin.lat};${destination.lng},${destination.lat}`;
  const url =
    `https://api.mapbox.com/directions-matrix/v1/mapbox/driving-traffic/${coords}` +
    `?annotations=duration&access_token=${encodeURIComponent(token)}`;
  const timeoutMs = Number(Deno.env.get("PUNCTUALITY_ETA_TIMEOUT_MS") ?? "4500");
  const resp = await fetchWithTimeout(url, Number.isFinite(timeoutMs) ? timeoutMs : 4500);
  if (!resp.ok) return null;
  const data = (await resp.json()) as Record<string, unknown>;
  const durations = Array.isArray(data.durations) ? data.durations : [];
  const row = Array.isArray(durations[0]) ? (durations[0] as unknown[]) : [];
  const sec = Number(row[1] ?? 0);
  if (!Number.isFinite(sec) || sec <= 0) return null;
  return {
    etaMinutes: Math.max(1, Math.ceil(sec / 60)),
    trafficLevel: null,
    rawResponse: data,
    provider: "mapbox_driving_traffic"
  };
}

async function estimateEtaOsrm(origin: Coordinates, destination: Coordinates): Promise<{
  etaMinutes: number;
  trafficLevel: string | null;
  rawResponse: Record<string, unknown>;
  provider: string;
} | null> {
  const url =
    "https://router.project-osrm.org/route/v1/driving/" +
    `${origin.lng},${origin.lat};${destination.lng},${destination.lat}` +
    "?overview=false";
  const timeoutMs = Number(Deno.env.get("PUNCTUALITY_ETA_TIMEOUT_MS") ?? "4500");
  const resp = await fetchWithTimeout(url, Number.isFinite(timeoutMs) ? timeoutMs : 4500);
  if (!resp.ok) return null;
  const data = (await resp.json()) as Record<string, unknown>;
  const routes = Array.isArray(data.routes) ? data.routes : [];
  const firstRoute = routes[0] as Record<string, unknown> | undefined;
  const sec = Number(firstRoute?.duration ?? 0);
  if (!Number.isFinite(sec) || sec <= 0) return null;
  return {
    etaMinutes: Math.max(1, Math.ceil(sec / 60)),
    trafficLevel: null,
    rawResponse: data,
    provider: "osrm"
  };
}

async function estimateEtaWithRetry(origin: Coordinates, destination: Coordinates): Promise<{
  etaMinutes: number;
  trafficLevel: string | null;
  rawResponse: Record<string, unknown>;
  provider: string;
} | null> {
  const provider = resolveProviderName();
  if (provider === "none") return null;
  const maxAttempts = Number(Deno.env.get("PUNCTUALITY_ETA_RETRY_MAX") ?? "2");
  for (let attempt = 1; attempt <= Math.max(1, maxAttempts); attempt += 1) {
    try {
      if (provider === "google") {
        const result = await estimateEtaGoogle(origin, destination);
        if (result) return result;
      } else if (provider === "mapbox") {
        const result = await estimateEtaMapbox(origin, destination);
        if (result) return result;
      } else if (provider === "osrm") {
        const result = await estimateEtaOsrm(origin, destination);
        if (result) return result;
      }
    } catch (_) {
      // retry
    }
  }
  return null;
}

async function resolveServiceLocation(
  admin: ReturnType<typeof createClient>,
  tenantId: string,
  professionalId: string,
  cache: Map<string, Coordinates | null>
): Promise<Coordinates | null> {
  const cached = cache.get(professionalId);
  if (cached !== undefined) return cached;

  const selectFields = "latitude, longitude";
  const { data: professionalLocation } = await admin
    .from("service_locations")
    .select(selectFields)
    .eq("tenant_id", tenantId)
    .eq("professional_id", professionalId)
    .eq("is_active", true)
    .order("updated_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  const parseCoords = (row: ServiceLocationRow | null | undefined): Coordinates | null => {
    const lat = Number(row?.latitude ?? NaN);
    const lng = Number(row?.longitude ?? NaN);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
    return { lat, lng };
  };

  let resolved = parseCoords((professionalLocation ?? null) as ServiceLocationRow | null);
  if (!resolved) {
    const { data: tenantLocation } = await admin
      .from("service_locations")
      .select(selectFields)
      .eq("tenant_id", tenantId)
      .is("professional_id", null)
      .eq("is_active", true)
      .order("updated_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    resolved = parseCoords((tenantLocation ?? null) as ServiceLocationRow | null);
  }

  cache.set(professionalId, resolved);
  return resolved;
}

async function resolveDelayPolicy(
  admin: ReturnType<typeof createClient>,
  tenantId: string,
  professionalId: string
): Promise<DelayPolicyRow> {
  const { data: professionalPolicy } = await admin
    .from("delay_policies")
    .select("tempo_maximo_atraso_min, fallback_whatsapp_for_professional")
    .eq("tenant_id", tenantId)
    .eq("professional_id", professionalId)
    .maybeSingle();

  if (professionalPolicy?.tempo_maximo_atraso_min !== undefined) {
    return {
      tempo_maximo_atraso_min: Number(professionalPolicy.tempo_maximo_atraso_min),
      fallback_whatsapp_for_professional: Boolean(
        (professionalPolicy as Record<string, unknown>).fallback_whatsapp_for_professional ?? false
      )
    };
  }

  const { data: tenantPolicy } = await admin
    .from("delay_policies")
    .select("tempo_maximo_atraso_min, fallback_whatsapp_for_professional")
    .eq("tenant_id", tenantId)
    .is("professional_id", null)
    .maybeSingle();

  if (tenantPolicy?.tempo_maximo_atraso_min !== undefined) {
    return {
      tempo_maximo_atraso_min: Number(tenantPolicy.tempo_maximo_atraso_min),
      fallback_whatsapp_for_professional: Boolean(
        (tenantPolicy as Record<string, unknown>).fallback_whatsapp_for_professional ?? false
      )
    };
  }

  return { tempo_maximo_atraso_min: 10, fallback_whatsapp_for_professional: false };
}

async function hasActiveConsent(
  admin: ReturnType<typeof createClient>,
  tenantId: string,
  appointmentId: string,
  referenceDate: Date,
  cache: Map<string, boolean>
): Promise<boolean> {
  const cached = cache.get(appointmentId);
  if (cached !== undefined) return cached;

  const { data: consentData } = await admin
    .from("client_location_consents")
    .select("consent_status, expires_at")
    .eq("tenant_id", tenantId)
    .eq("appointment_id", appointmentId)
    .order("updated_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  const consent = (consentData ?? null) as ConsentRow | null;
  const isGranted = consent?.consent_status === "granted";
  const notExpired =
    !consent?.expires_at || new Date(consent.expires_at).getTime() > referenceDate.getTime();
  const allowed = Boolean(isGranted && notExpired);

  cache.set(appointmentId, allowed);
  return allowed;
}

async function assertAdminAccessForUserToken(
  supabaseUrl: string,
  anonKey: string,
  authHeader: string
): Promise<string | null> {
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } }
  });

  const {
    data: { user },
    error: userError
  } = await userClient.auth.getUser();

  if (userError || !user) return null;

  const { data: isAdmin } = await userClient.rpc("is_tenant_admin");
  if (!isAdmin) return null;

  const { data: tenantId } = await userClient.rpc("auth_tenant_id");
  return tenantId ?? null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 405, headers: responseHeaders });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? Deno.env.get("APP_SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("APP_SUPABASE_ANON_KEY");
  const serviceRoleKey =
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("APP_SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return new Response(JSON.stringify({ error: "Missing Supabase env" }), { status: 500, headers: responseHeaders });
  }

  const body = await req.json().catch(() => null);
  const parsed = MonitorPayloadSchema.safeParse(body);
  if (!parsed.success) {
    return new Response(JSON.stringify({ error: "Invalid payload", details: parsed.error.flatten() }), {
      status: 400,
      headers: responseHeaders
    });
  }

  const payload = parsed.data;
  const authHeader = req.headers.get("Authorization");
  const monitorSecret = Deno.env.get("PUNCTUALITY_MONITOR_SECRET") ?? "";
  const secretHeader = req.headers.get("x-monitor-secret") ?? "";

  let scopedTenantId: string | null = null;
  if (authHeader) {
    scopedTenantId = await assertAdminAccessForUserToken(supabaseUrl, anonKey, authHeader);
  }

  if (!scopedTenantId && monitorSecret && secretHeader === monitorSecret) {
    scopedTenantId = payload.tenant_id ?? null;
  }

  if (!scopedTenantId) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: responseHeaders });
  }

  const admin = createClient(supabaseUrl, serviceRoleKey);
  const now = new Date();
  const touchedAppointmentIds = new Set<string>();
  const serviceLocationCache = new Map<string, Coordinates | null>();
  const consentCache = new Map<string, boolean>();
  const source = payload.source;
  let skippedNoConsent = 0;

  for (const snapshotInput of payload.snapshots) {
    const { data: appointment } = await admin
      .from("appointments")
      .select("id, tenant_id, professional_id, starts_at")
      .eq("tenant_id", scopedTenantId)
      .eq("id", snapshotInput.appointment_id)
      .maybeSingle();

    if (!appointment) continue;
    const canMonitor = await hasActiveConsent(
      admin,
      scopedTenantId,
      appointment.id,
      now,
      consentCache
    );
    if (!canMonitor) {
      skippedNoConsent += 1;
      continue;
    }

    const policy = await resolveDelayPolicy(admin, scopedTenantId, appointment.professional_id);
    const capturedAt = snapshotInput.captured_at ? new Date(snapshotInput.captured_at) : now;
    const minutesToStart = minutesUntil(capturedAt, appointment.starts_at);
    let etaMinutes = snapshotInput.eta_minutes ?? null;
    let provider = snapshotInput.provider ?? null;
    let trafficLevel = snapshotInput.traffic_level ?? null;
    let rawResponse = snapshotInput.raw_response ?? {};
    const hasClientCoords =
      snapshotInput.client_lat !== undefined && snapshotInput.client_lng !== undefined;

    if (etaMinutes === null && hasClientCoords) {
      const destination = await resolveServiceLocation(
        admin,
        scopedTenantId,
        appointment.professional_id,
        serviceLocationCache
      );
      if (destination) {
        const origin = { lat: snapshotInput.client_lat as number, lng: snapshotInput.client_lng as number };
        const providerResult = await estimateEtaWithRetry(origin, destination);
        if (providerResult) {
          etaMinutes = providerResult.etaMinutes;
          provider = providerResult.provider;
          trafficLevel = providerResult.trafficLevel;
          rawResponse = providerResult.rawResponse;
        } else {
          provider = provider ?? `${resolveProviderName()}_failed`;
        }
      }
    }

    const predictedDelay = etaMinutes === null ? null : etaMinutes - minutesToStart;
    const status = classifyPunctualityStatus(
      etaMinutes,
      minutesToStart,
      policy.tempo_maximo_atraso_min
    );

    await admin.from("appointment_eta_snapshots").insert({
      tenant_id: scopedTenantId,
      appointment_id: appointment.id,
      captured_at: capturedAt.toISOString(),
      eta_minutes: etaMinutes,
      minutes_to_start: minutesToStart,
      predicted_arrival_delay: predictedDelay,
      status,
      client_lat: snapshotInput.client_lat,
      client_lng: snapshotInput.client_lng,
      traffic_level: trafficLevel,
      provider,
      raw_response: rawResponse
    });

    touchedAppointmentIds.add(appointment.id);
  }

  if (payload.appointment_id) {
    touchedAppointmentIds.add(payload.appointment_id);
  }

  const rangeStart = addMinutes(now, -payload.window_before_min).toISOString();
  const rangeEnd = addMinutes(now, payload.window_after_min).toISOString();

  if (touchedAppointmentIds.size === 0) {
    const { data: rows } = await admin
      .from("appointments")
      .select("id")
      .eq("tenant_id", scopedTenantId)
      .in("status", ["scheduled", "confirmed"])
      .gte("starts_at", rangeStart)
      .lte("starts_at", rangeEnd)
      .order("starts_at", { ascending: true })
      .limit(400);

    for (const row of rows ?? []) {
      if (row.id) touchedAppointmentIds.add(row.id as string);
    }
  }

  if (touchedAppointmentIds.size === 0) {
    return new Response(JSON.stringify({ ok: true, processed: 0, changed: 0 }), {
      status: 200,
      headers: responseHeaders
    });
  }

  const { data: appointmentsData, error: appointmentsError } = await admin
    .from("appointments")
    .select(
      "id, tenant_id, professional_id, starts_at, punctuality_status, punctuality_eta_min, punctuality_predicted_delay_min"
    )
    .eq("tenant_id", scopedTenantId)
    .in("id", [...touchedAppointmentIds]);

  if (appointmentsError) {
    return new Response(JSON.stringify({ error: "Could not load appointments" }), {
      status: 500,
      headers: responseHeaders
    });
  }

  const appointments = (appointmentsData ?? []) as AppointmentRow[];
  let changed = 0;
  let notificationsQueued = 0;
  let pushQueued = 0;
  let whatsappQueued = 0;

  for (const appointment of appointments) {
    const canMonitor = await hasActiveConsent(admin, scopedTenantId, appointment.id, now, consentCache);
    if (!canMonitor) {
      const needsReset =
        appointment.punctuality_status !== "no_data" ||
        appointment.punctuality_eta_min !== null ||
        appointment.punctuality_predicted_delay_min !== null;
      if (needsReset) {
        await admin
          .from("appointments")
          .update({
            punctuality_status: "no_data",
            punctuality_eta_min: null,
            punctuality_predicted_delay_min: null,
            punctuality_last_calculated_at: now.toISOString()
          })
          .eq("tenant_id", scopedTenantId)
          .eq("id", appointment.id);
      }
      continue;
    }

    const policy = await resolveDelayPolicy(admin, scopedTenantId, appointment.professional_id);

    const { data: latestCoordsSnapshot } = await admin
      .from("appointment_eta_snapshots")
      .select("client_lat, client_lng")
      .eq("tenant_id", scopedTenantId)
      .eq("appointment_id", appointment.id)
      .not("client_lat", "is", null)
      .not("client_lng", "is", null)
      .order("captured_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (
      latestCoordsSnapshot?.client_lat !== null &&
      latestCoordsSnapshot?.client_lat !== undefined &&
      latestCoordsSnapshot?.client_lng !== null &&
      latestCoordsSnapshot?.client_lng !== undefined
    ) {
      const destination = await resolveServiceLocation(
        admin,
        scopedTenantId,
        appointment.professional_id,
        serviceLocationCache
      );
      if (destination) {
        const providerResult = await estimateEtaWithRetry(
          { lat: Number(latestCoordsSnapshot.client_lat), lng: Number(latestCoordsSnapshot.client_lng) },
          destination
        );
        if (providerResult) {
          const capturedAt = now.toISOString();
          const minutesToStartCurrent = minutesUntil(now, appointment.starts_at);
          const predictedDelayCurrent = providerResult.etaMinutes - minutesToStartCurrent;
          const statusCurrent = classifyPunctualityStatus(
            providerResult.etaMinutes,
            minutesToStartCurrent,
            policy.tempo_maximo_atraso_min
          );
          await admin.from("appointment_eta_snapshots").insert({
            tenant_id: scopedTenantId,
            appointment_id: appointment.id,
            captured_at: capturedAt,
            eta_minutes: providerResult.etaMinutes,
            minutes_to_start: minutesToStartCurrent,
            predicted_arrival_delay: predictedDelayCurrent,
            status: statusCurrent,
            client_lat: Number(latestCoordsSnapshot.client_lat),
            client_lng: Number(latestCoordsSnapshot.client_lng),
            traffic_level: providerResult.trafficLevel,
            provider: providerResult.provider,
            raw_response: providerResult.rawResponse
          });
        }
      }
    }

    const { data: snapshotsData } = await admin
      .from("appointment_eta_snapshots")
      .select("status, eta_minutes, predicted_arrival_delay, captured_at")
      .eq("tenant_id", scopedTenantId)
      .eq("appointment_id", appointment.id)
      .order("captured_at", { ascending: false })
      .limit(2);

    const snapshots = (snapshotsData ?? []) as SnapshotRow[];
    const latest = snapshots[0] ?? null;

    let stableStatus = (appointment.punctuality_status ?? "no_data") as
      | "no_data"
      | "on_time"
      | "late_ok"
      | "late_critical";

    if (snapshots.length >= 2 && snapshots[0].status === snapshots[1].status) {
      stableStatus = snapshots[0].status;
    }

    const etaMin = latest?.eta_minutes ?? null;
    const predictedDelay = latest?.predicted_arrival_delay ?? null;

    const currentStatus = (appointment.punctuality_status ?? "no_data") as
      | "no_data"
      | "on_time"
      | "late_ok"
      | "late_critical";

    const statusChanged = stableStatus !== currentStatus;
    const numericChanged =
      appointment.punctuality_eta_min !== etaMin ||
      appointment.punctuality_predicted_delay_min !== predictedDelay;

    if (!statusChanged && !numericChanged) continue;

    await admin
      .from("appointments")
      .update({
        punctuality_status: stableStatus,
        punctuality_eta_min: etaMin,
        punctuality_predicted_delay_min: predictedDelay,
        punctuality_last_calculated_at: now.toISOString()
      })
      .eq("tenant_id", scopedTenantId)
      .eq("id", appointment.id);

    if (!statusChanged) continue;

    changed += 1;
    const minutesToStart = minutesUntil(now, appointment.starts_at);

    await admin.from("punctuality_events").insert({
      tenant_id: scopedTenantId,
      appointment_id: appointment.id,
      old_status: currentStatus,
      new_status: stableStatus,
      eta_minutes: etaMin,
      minutes_to_start: minutesToStart,
      predicted_arrival_delay: predictedDelay,
      max_allowed_delay: policy.tempo_maximo_atraso_min,
      source,
      payload: {
        appointment_id: appointment.id,
        old_status: currentStatus,
        new_status: stableStatus,
        eta_minutes: etaMin,
        minutes_to_start: minutesToStart,
        predicted_arrival_delay: predictedDelay,
        max_allowed_delay: policy.tempo_maximo_atraso_min,
        occurred_at: now.toISOString()
      }
    });

    const notificationType = toNotificationType(stableStatus);
    if (!notificationType) continue;

    const dedupeWindowStart = addMinutes(now, -10).toISOString();
    const { data: existingNotif } = await admin
      .from("notification_log")
      .select("id")
      .eq("tenant_id", scopedTenantId)
      .eq("appointment_id", appointment.id)
      .eq("channel", "in_app")
      .eq("type", notificationType)
      .gte("created_at", dedupeWindowStart)
      .limit(1)
      .maybeSingle();

    if (existingNotif?.id) continue;

    await admin.from("notification_log").insert({
      tenant_id: scopedTenantId,
      appointment_id: appointment.id,
      channel: "in_app",
      type: notificationType,
      status: "queued",
      payload: {
        appointment_id: appointment.id,
        status: stableStatus,
        eta_minutes: etaMin,
        predicted_arrival_delay: predictedDelay,
        max_allowed_delay: policy.tempo_maximo_atraso_min,
        source
      }
    });

    notificationsQueued += 1;

    const shouldQueuePush =
      stableStatus === "late_ok" || stableStatus === "late_critical";

    if (!shouldQueuePush) continue;

    const { data: existingPushNotif } = await admin
      .from("notification_log")
      .select("id")
      .eq("tenant_id", scopedTenantId)
      .eq("appointment_id", appointment.id)
      .eq("channel", "push")
      .eq("type", notificationType)
      .gte("created_at", dedupeWindowStart)
      .limit(1)
      .maybeSingle();

    if (!existingPushNotif?.id) {
      await admin.from("notification_log").insert({
        tenant_id: scopedTenantId,
        appointment_id: appointment.id,
        channel: "push",
        type: notificationType,
        status: "queued",
        payload: {
          appointment_id: appointment.id,
          status: stableStatus,
          eta_minutes: etaMin,
          predicted_arrival_delay: predictedDelay,
          max_allowed_delay: policy.tempo_maximo_atraso_min,
          source,
          priority: stableStatus === "late_critical" ? "high" : "normal",
          actions: ["KEEP", "RESCHEDULE", "OPEN_AGENDA"]
        }
      });

      pushQueued += 1;
    }

    const shouldQueueWhatsapp =
      policy.fallback_whatsapp_for_professional &&
      (stableStatus === "late_ok" || stableStatus === "late_critical");

    if (!shouldQueueWhatsapp) continue;

    const { data: existingWhatsappNotif } = await admin
      .from("notification_log")
      .select("id")
      .eq("tenant_id", scopedTenantId)
      .eq("appointment_id", appointment.id)
      .eq("channel", "whatsapp")
      .eq("type", notificationType)
      .gte("created_at", dedupeWindowStart)
      .limit(1)
      .maybeSingle();

    if (existingWhatsappNotif?.id) continue;

    await admin.from("notification_log").insert({
      tenant_id: scopedTenantId,
      appointment_id: appointment.id,
      channel: "whatsapp",
      type: notificationType,
      status: "queued",
      payload: {
        appointment_id: appointment.id,
        status: stableStatus,
        eta_minutes: etaMin,
        predicted_arrival_delay: predictedDelay,
        max_allowed_delay: policy.tempo_maximo_atraso_min,
        source,
        fallback_whatsapp_for_professional: true
      }
    });

    whatsappQueued += 1;
  }

  return new Response(
    JSON.stringify({
      ok: true,
      processed: appointments.length,
      changed,
      notifications_queued: notificationsQueued,
      push_queued: pushQueued,
      whatsapp_queued: whatsappQueued,
      skipped_no_consent: skippedNoConsent,
      tenant_id: scopedTenantId
    }),
    {
      status: 200,
      headers: responseHeaders
    }
  );
});
