import { createClient } from "npm:@supabase/supabase-js@2.49.1";
import { z } from "npm:zod@3.23.8";

const jsonHeaders = { "Content-Type": "application/json" };
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-retention-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};
const responseHeaders = { ...jsonHeaders, ...corsHeaders };

const PayloadSchema = z.object({
  secret: z.string().optional(),
  tenant_id: z.string().uuid().optional(),
  max_tenants: z.number().int().min(1).max(500).default(200)
});

type RetentionPolicyRow = {
  tenant_id: string;
  keep_eta_snapshots_days: number;
  keep_punctuality_events_days: number;
  keep_notification_log_days: number;
  delete_expired_consents_after_days: number;
  enabled: boolean;
};

function daysAgoIso(days: number): string {
  const now = new Date();
  now.setDate(now.getDate() - days);
  return now.toISOString();
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 405, headers: responseHeaders });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? Deno.env.get("APP_SUPABASE_URL");
  const serviceRoleKey =
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("APP_SUPABASE_SERVICE_ROLE_KEY");
  const retentionSecret = Deno.env.get("PUNCTUALITY_RETENTION_SECRET") ?? "";
  if (!supabaseUrl || !serviceRoleKey || !retentionSecret) {
    return new Response(JSON.stringify({ error: "Missing env" }), { status: 500, headers: responseHeaders });
  }

  const body = await req.json().catch(() => null);
  const parsed = PayloadSchema.safeParse(body);
  if (!parsed.success) {
    return new Response(JSON.stringify({ error: "Invalid payload", details: parsed.error.flatten() }), {
      status: 400,
      headers: responseHeaders
    });
  }

  const payload = parsed.data;
  const providedSecret = req.headers.get("x-retention-secret") ?? payload.secret ?? "";
  if (providedSecret !== retentionSecret) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: responseHeaders });
  }

  const admin = createClient(supabaseUrl, serviceRoleKey);

  let policyQuery = admin
    .from("data_retention_policies")
    .select(
      "tenant_id, keep_eta_snapshots_days, keep_punctuality_events_days, keep_notification_log_days, delete_expired_consents_after_days, enabled"
    )
    .eq("enabled", true)
    .limit(payload.max_tenants);

  if (payload.tenant_id) {
    policyQuery = policyQuery.eq("tenant_id", payload.tenant_id);
  }

  const { data: policyRows, error: policyError } = await policyQuery;
  if (policyError) {
    return new Response(JSON.stringify({ error: "Could not load retention policies" }), {
      status: 500,
      headers: responseHeaders
    });
  }

  const policies = (policyRows ?? []) as RetentionPolicyRow[];
  if (policies.length === 0) {
    return new Response(JSON.stringify({ ok: true, processed_tenants: 0, totals: {} }), {
      status: 200,
      headers: responseHeaders
    });
  }

  const totals = {
    eta_snapshots_deleted: 0,
    punctuality_events_deleted: 0,
    notification_log_deleted: 0,
    expired_consents_deleted: 0
  };
  const results: Array<Record<string, unknown>> = [];

  for (const policy of policies) {
    const tenantId = policy.tenant_id;
    const etaBefore = daysAgoIso(policy.keep_eta_snapshots_days);
    const eventsBefore = daysAgoIso(policy.keep_punctuality_events_days);
    const notifBefore = daysAgoIso(policy.keep_notification_log_days);
    const consentExpiredBefore = daysAgoIso(policy.delete_expired_consents_after_days);

    const tenantResult = {
      tenant_id: tenantId,
      eta_snapshots_deleted: 0,
      punctuality_events_deleted: 0,
      notification_log_deleted: 0,
      expired_consents_deleted: 0
    };

    const { data: deletedSnapshots, error: snapshotError } = await admin
      .from("appointment_eta_snapshots")
      .delete()
      .eq("tenant_id", tenantId)
      .lt("captured_at", etaBefore)
      .select("id");
    if (!snapshotError) {
      const count = deletedSnapshots?.length ?? 0;
      tenantResult.eta_snapshots_deleted = count;
      totals.eta_snapshots_deleted += count;
    }

    const { data: deletedEvents, error: eventError } = await admin
      .from("punctuality_events")
      .delete()
      .eq("tenant_id", tenantId)
      .lt("occurred_at", eventsBefore)
      .select("id");
    if (!eventError) {
      const count = deletedEvents?.length ?? 0;
      tenantResult.punctuality_events_deleted = count;
      totals.punctuality_events_deleted += count;
    }

    const { data: deletedNotifications, error: notificationError } = await admin
      .from("notification_log")
      .delete()
      .eq("tenant_id", tenantId)
      .lt("created_at", notifBefore)
      .in("type", ["punctuality_on_time", "punctuality_late_ok", "punctuality_late_critical"])
      .select("id");
    if (!notificationError) {
      const count = deletedNotifications?.length ?? 0;
      tenantResult.notification_log_deleted = count;
      totals.notification_log_deleted += count;
    }

    const { data: deletedConsents, error: consentError } = await admin
      .from("client_location_consents")
      .delete()
      .eq("tenant_id", tenantId)
      .not("expires_at", "is", null)
      .lt("expires_at", consentExpiredBefore)
      .select("id");
    if (!consentError) {
      const count = deletedConsents?.length ?? 0;
      tenantResult.expired_consents_deleted = count;
      totals.expired_consents_deleted += count;
    }

    results.push(tenantResult);
  }

  return new Response(
    JSON.stringify({
      ok: true,
      processed_tenants: policies.length,
      totals,
      results
    }),
    { status: 200, headers: responseHeaders }
  );
});
