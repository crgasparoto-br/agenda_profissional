import { createClient } from "npm:@supabase/supabase-js@2.49.1";
import { z } from "npm:zod@3.23.8";

const jsonHeaders = { "Content-Type": "application/json" };
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-push-dispatcher-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};
const responseHeaders = { ...jsonHeaders, ...corsHeaders };

const PayloadSchema = z.object({
  secret: z.string().optional(),
  tenant_id: z.string().uuid().optional(),
  limit: z.number().int().min(1).max(200).default(50)
});

type PushNotificationRow = {
  id: string;
  tenant_id: string;
  appointment_id: string;
  type: "punctuality_late_ok" | "punctuality_late_critical" | "punctuality_on_time";
  status: "queued" | "sent" | "failed" | "read";
  payload: Record<string, unknown> | null;
};

type AppointmentTargetRow = {
  id: string;
  professional_id: string;
  professionals: { user_id: string | null; name: string | null } | null;
  clients: { full_name: string | null } | null;
};

type DeviceTokenRow = {
  token: string;
  provider: string;
  platform: string;
};

function buildPushContent(type: PushNotificationRow["type"], payload: Record<string, unknown> | null, clientName?: string | null) {
  const delay = typeof payload?.predicted_arrival_delay === "number" ? payload.predicted_arrival_delay : null;
  const eta = typeof payload?.eta_minutes === "number" ? payload.eta_minutes : null;

  if (type === "punctuality_late_critical") {
    return {
      title: "Atraso critico previsto",
      body: `${clientName ?? "Cliente"} com atraso previsto de ${delay ?? "?"} min.`,
      priority: "high"
    };
  }

  if (type === "punctuality_late_ok") {
    return {
      title: "Atraso leve previsto",
      body: `${clientName ?? "Cliente"} com atraso previsto de ${delay ?? "?"} min. ETA ${eta ?? "?"} min.`,
      priority: "normal"
    };
  }

  return {
    title: "Atualizacao de pontualidade",
    body: `${clientName ?? "Cliente"} esta no horario.`,
    priority: "normal"
  };
}

async function sendExpoPush(token: string, title: string, body: string, data: Record<string, unknown>, priority: string) {
  const expoToken = Deno.env.get("EXPO_ACCESS_TOKEN");
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    Accept: "application/json"
  };
  if (expoToken) headers.Authorization = `Bearer ${expoToken}`;

  const resp = await fetch("https://exp.host/--/api/v2/push/send", {
    method: "POST",
    headers,
    body: JSON.stringify({
      to: token,
      title,
      body,
      sound: "default",
      priority,
      data
    })
  });

  const result = (await resp.json().catch(() => ({}))) as Record<string, unknown>;
  if (!resp.ok) {
    return { ok: false, providerMessageId: null, raw: result };
  }

  const dataArr = Array.isArray(result.data) ? result.data : [];
  const first = dataArr[0] as Record<string, unknown> | undefined;
  const status = (first?.status as string | undefined) ?? "ok";
  if (status !== "ok") {
    return { ok: false, providerMessageId: null, raw: result };
  }

  return {
    ok: true,
    providerMessageId: (first?.id as string | undefined) ?? null,
    raw: result
  };
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
  const dispatcherSecret = Deno.env.get("PUNCTUALITY_PUSH_DISPATCHER_SECRET") ?? "";
  const provider = (Deno.env.get("PUSH_PROVIDER") ?? "none").trim().toLowerCase();

  if (!supabaseUrl || !serviceRoleKey || !dispatcherSecret) {
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
  const providedSecret = req.headers.get("x-push-dispatcher-secret") ?? payload.secret ?? "";
  if (providedSecret !== dispatcherSecret) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: responseHeaders });
  }

  const admin = createClient(supabaseUrl, serviceRoleKey);
  let query = admin
    .from("notification_log")
    .select("id, tenant_id, appointment_id, type, status, payload")
    .eq("channel", "push")
    .eq("status", "queued")
    .in("type", ["punctuality_late_ok", "punctuality_late_critical", "punctuality_on_time"])
    .order("created_at", { ascending: true })
    .limit(payload.limit);

  if (payload.tenant_id) {
    query = query.eq("tenant_id", payload.tenant_id);
  }

  const { data: notificationRows, error: notificationError } = await query;
  if (notificationError) {
    return new Response(JSON.stringify({ error: "Could not load queued push notifications" }), {
      status: 500,
      headers: responseHeaders
    });
  }

  const rows = (notificationRows ?? []) as PushNotificationRow[];
  if (rows.length === 0) {
    return new Response(JSON.stringify({ ok: true, processed: 0, sent: 0, failed: 0 }), {
      status: 200,
      headers: responseHeaders
    });
  }

  let sent = 0;
  let failed = 0;

  for (const row of rows) {
    if (provider === "none") {
      await admin
        .from("notification_log")
        .update({
          status: "sent",
          provider_message_id: `mock-${row.id}`,
          payload: {
            ...(row.payload ?? {}),
            push_dispatch: {
              provider,
              sent_at: new Date().toISOString(),
              provider_message_id: `mock-${row.id}`,
              simulated: true
            }
          }
        })
        .eq("id", row.id);
      sent += 1;
      continue;
    }

    const { data: appointment } = await admin
      .from("appointments")
      .select("id, professional_id, professionals(user_id, name), clients(full_name)")
      .eq("tenant_id", row.tenant_id)
      .eq("id", row.appointment_id)
      .maybeSingle();

    const appointmentTarget = (appointment ?? null) as AppointmentTargetRow | null;
    const userId = appointmentTarget?.professionals?.user_id ?? null;
    if (!userId) {
      await admin
        .from("notification_log")
        .update({
          status: "failed",
          payload: {
            ...(row.payload ?? {}),
            push_dispatch: { reason: "professional_user_not_found", provider }
          }
        })
        .eq("id", row.id);
      failed += 1;
      continue;
    }

    const { data: tokenRows } = await admin
      .from("device_push_tokens")
      .select("token, provider, platform")
      .eq("tenant_id", row.tenant_id)
      .eq("user_id", userId)
      .eq("active", true)
      .order("last_seen_at", { ascending: false })
      .limit(5);

    const tokens = (tokenRows ?? []) as DeviceTokenRow[];
    if (tokens.length === 0) {
      await admin
        .from("notification_log")
        .update({
          status: "failed",
          payload: {
            ...(row.payload ?? {}),
            push_dispatch: { reason: "no_active_device_token", provider }
          }
        })
        .eq("id", row.id);
      failed += 1;
      continue;
    }

    const content = buildPushContent(row.type, row.payload, appointmentTarget?.clients?.full_name);
    let sentForRow = false;
    let providerMessageId: string | null = null;
    let lastRaw: Record<string, unknown> | null = null;

    for (const tokenItem of tokens) {
      if (provider === "expo" && tokenItem.provider === "expo") {
        const pushResult = await sendExpoPush(
          tokenItem.token,
          content.title,
          content.body,
          {
            appointment_id: row.appointment_id,
            type: row.type,
            ...(row.payload ?? {})
          },
          content.priority
        );
        lastRaw = pushResult.raw as Record<string, unknown>;
        if (pushResult.ok) {
          sentForRow = true;
          providerMessageId = pushResult.providerMessageId;
          break;
        }
      }
    }

    if (sentForRow) {
      await admin
        .from("notification_log")
        .update({
          status: "sent",
          provider_message_id: providerMessageId,
          payload: {
            ...(row.payload ?? {}),
            push_dispatch: {
              provider,
              sent_at: new Date().toISOString(),
              provider_message_id: providerMessageId,
              raw: lastRaw
            }
          }
        })
        .eq("id", row.id);
      sent += 1;
    } else {
      await admin
        .from("notification_log")
        .update({
          status: "failed",
          payload: {
            ...(row.payload ?? {}),
            push_dispatch: {
              provider,
              failed_at: new Date().toISOString(),
              reason: "provider_send_failed",
              raw: lastRaw
            }
          }
        })
        .eq("id", row.id);
      failed += 1;
    }
  }

  return new Response(
    JSON.stringify({ ok: true, processed: rows.length, sent, failed, provider }),
    {
      status: 200,
      headers: responseHeaders
    }
  );
});
