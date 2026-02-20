import { createClient } from "npm:@supabase/supabase-js@2.49.1";
import { z } from "npm:zod@3.23.8";

const jsonHeaders = { "Content-Type": "application/json" };
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-scheduler-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};
const responseHeaders = { ...jsonHeaders, ...corsHeaders };

const SchedulerPayloadSchema = z.object({
  secret: z.string().optional(),
  tenant_id: z.string().uuid().optional(),
  source: z.string().trim().min(1).max(40).default("scheduler"),
  window_before_min: z.number().int().min(0).max(120).default(15),
  window_after_min: z.number().int().min(5).max(1440).default(180),
  max_tenants: z.number().int().min(1).max(500).default(200)
});

function addMinutes(base: Date, deltaMinutes: number): Date {
  return new Date(base.getTime() + deltaMinutes * 60 * 1000);
}

function asFiniteNumber(value: unknown): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
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
  const monitorSecret = Deno.env.get("PUNCTUALITY_MONITOR_SECRET") ?? "";
  const schedulerSecret = Deno.env.get("PUNCTUALITY_SCHEDULER_SECRET") ?? "";
  const pushDispatcherSecret = Deno.env.get("PUNCTUALITY_PUSH_DISPATCHER_SECRET") ?? "";
  const whatsappDispatcherSecret = Deno.env.get("PUNCTUALITY_WHATSAPP_DISPATCHER_SECRET") ?? "";

  if (!supabaseUrl || !serviceRoleKey || !monitorSecret || !schedulerSecret || !pushDispatcherSecret) {
    return new Response(JSON.stringify({ error: "Missing scheduler env" }), {
      status: 500,
      headers: responseHeaders
    });
  }

  const body = await req.json().catch(() => null);
  const parsed = SchedulerPayloadSchema.safeParse(body);
  if (!parsed.success) {
    return new Response(JSON.stringify({ error: "Invalid payload", details: parsed.error.flatten() }), {
      status: 400,
      headers: responseHeaders
    });
  }

  const payload = parsed.data;
  const providedSecret = req.headers.get("x-scheduler-secret") ?? payload.secret ?? "";
  if (providedSecret !== schedulerSecret) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: responseHeaders });
  }

  const admin = createClient(supabaseUrl, serviceRoleKey);

  let tenantIds: string[] = [];

  if (payload.tenant_id) {
    tenantIds = [payload.tenant_id];
  } else {
    const now = new Date();
    const rangeStart = addMinutes(now, -payload.window_before_min).toISOString();
    const rangeEnd = addMinutes(now, payload.window_after_min).toISOString();

    const { data: appointmentRows, error: appointmentError } = await admin
      .from("appointments")
      .select("tenant_id")
      .in("status", ["scheduled", "confirmed"])
      .gte("starts_at", rangeStart)
      .lte("starts_at", rangeEnd)
      .limit(5000);

    if (appointmentError) {
      return new Response(JSON.stringify({ error: "Could not load appointments for scheduler" }), {
        status: 500,
        headers: responseHeaders
      });
    }

    tenantIds = [...new Set((appointmentRows ?? []).map((row) => row.tenant_id as string))]
      .slice(0, payload.max_tenants);
  }

  if (tenantIds.length === 0) {
    return new Response(
      JSON.stringify({
        ok: true,
        triggered: 0,
        changed_total: 0,
        notifications_total: 0,
        push_processed_total: 0,
        push_sent_total: 0,
        push_failed_total: 0,
        whatsapp_processed_total: 0,
        whatsapp_sent_total: 0,
        whatsapp_failed_total: 0
      }),
      {
        status: 200,
        headers: responseHeaders
      }
    );
  }

  const functionUrl = `${supabaseUrl}/functions/v1/punctuality-monitor`;
  const pushDispatcherUrl = `${supabaseUrl}/functions/v1/punctuality-push-dispatcher`;
  const whatsappDispatcherUrl = `${supabaseUrl}/functions/v1/punctuality-whatsapp-dispatcher`;
  let changedTotal = 0;
  let notificationsTotal = 0;
  let pushProcessedTotal = 0;
  let pushSentTotal = 0;
  let pushFailedTotal = 0;
  let whatsappProcessedTotal = 0;
  let whatsappSentTotal = 0;
  let whatsappFailedTotal = 0;
  const results: Array<Record<string, unknown>> = [];

  for (const tenantId of tenantIds) {
    try {
      const monitorRes = await fetch(functionUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-monitor-secret": monitorSecret
        },
        body: JSON.stringify({
          tenant_id: tenantId,
          source: payload.source,
          window_before_min: payload.window_before_min,
          window_after_min: payload.window_after_min,
          snapshots: []
        })
      });

      const monitorData = await monitorRes.json().catch(() => ({}));
      const changed = asFiniteNumber((monitorData as Record<string, unknown>).changed);
      const notifications = asFiniteNumber((monitorData as Record<string, unknown>).notifications_queued);
      changedTotal += changed;
      notificationsTotal += notifications;

      const dispatcherRes = await fetch(pushDispatcherUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-push-dispatcher-secret": pushDispatcherSecret
        },
        body: JSON.stringify({
          tenant_id: tenantId,
          limit: 50
        })
      });
      const dispatcherData = await dispatcherRes.json().catch(() => ({}));
      const pushProcessed = asFiniteNumber((dispatcherData as Record<string, unknown>).processed);
      const pushSent = asFiniteNumber((dispatcherData as Record<string, unknown>).sent);
      const pushFailed = asFiniteNumber((dispatcherData as Record<string, unknown>).failed);
      pushProcessedTotal += pushProcessed;
      pushSentTotal += pushSent;
      pushFailedTotal += pushFailed;

      let whatsappDispatcherResult: Record<string, unknown> = {
        ok: false,
        status: 0,
        processed: 0,
        sent: 0,
        failed: 0,
        skipped: true,
        reason: "whatsapp_dispatcher_secret_missing"
      };

      if (whatsappDispatcherSecret) {
        const whatsappDispatcherRes = await fetch(whatsappDispatcherUrl, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "x-whatsapp-dispatcher-secret": whatsappDispatcherSecret
          },
          body: JSON.stringify({
            tenant_id: tenantId,
            limit: 50
          })
        });
        const whatsappDispatcherData = await whatsappDispatcherRes.json().catch(() => ({}));
        const whatsappProcessed = asFiniteNumber((whatsappDispatcherData as Record<string, unknown>).processed);
        const whatsappSent = asFiniteNumber((whatsappDispatcherData as Record<string, unknown>).sent);
        const whatsappFailed = asFiniteNumber((whatsappDispatcherData as Record<string, unknown>).failed);
        whatsappProcessedTotal += whatsappProcessed;
        whatsappSentTotal += whatsappSent;
        whatsappFailedTotal += whatsappFailed;
        whatsappDispatcherResult = {
          ok: whatsappDispatcherRes.ok,
          status: whatsappDispatcherRes.status,
          processed: whatsappProcessed,
          sent: whatsappSent,
          failed: whatsappFailed
        };
      }

      results.push({
        tenant_id: tenantId,
        ok:
          monitorRes.ok &&
          dispatcherRes.ok &&
          (whatsappDispatcherSecret
            ? Boolean((whatsappDispatcherResult as { ok?: boolean }).ok)
            : true),
        monitor: {
          ok: monitorRes.ok,
          status: monitorRes.status,
          changed,
          notifications_queued: notifications
        },
        push_dispatcher: {
          ok: dispatcherRes.ok,
          status: dispatcherRes.status,
          processed: pushProcessed,
          sent: pushSent,
          failed: pushFailed
        },
        whatsapp_dispatcher: whatsappDispatcherResult
      });
    } catch (error) {
      results.push({
        tenant_id: tenantId,
        ok: false,
        status: 500,
        error: error instanceof Error ? error.message : "unknown_error"
      });
    }
  }

  return new Response(
    JSON.stringify({
      ok: true,
      triggered: tenantIds.length,
      changed_total: changedTotal,
      notifications_total: notificationsTotal,
      push_processed_total: pushProcessedTotal,
      push_sent_total: pushSentTotal,
      push_failed_total: pushFailedTotal,
      whatsapp_processed_total: whatsappProcessedTotal,
      whatsapp_sent_total: whatsappSentTotal,
      whatsapp_failed_total: whatsappFailedTotal,
      results
    }),
    {
      status: 200,
      headers: responseHeaders
    }
  );
});
