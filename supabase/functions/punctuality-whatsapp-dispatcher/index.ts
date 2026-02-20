import { createClient } from "npm:@supabase/supabase-js@2.49.1";
import { z } from "npm:zod@3.23.8";

const jsonHeaders = { "Content-Type": "application/json" };
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-whatsapp-dispatcher-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};
const responseHeaders = { ...jsonHeaders, ...corsHeaders };

const PayloadSchema = z.object({
  secret: z.string().optional(),
  tenant_id: z.string().uuid().optional(),
  limit: z.number().int().min(1).max(200).default(50)
});

type WhatsappNotificationRow = {
  id: string;
  tenant_id: string;
  appointment_id: string;
  type: "punctuality_late_ok" | "punctuality_late_critical" | "punctuality_on_time";
  status: "queued" | "sent" | "failed" | "read";
  payload: Record<string, unknown> | null;
};

type AppointmentTargetRow = {
  id: string;
  starts_at: string;
  professionals: { id: string; name: string | null; user_id: string | null } | null;
  clients: { full_name: string | null } | null;
};

function normalizeWhatsappTo(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const digits = raw.replace(/\D/g, "");
  if (!digits) return null;
  if (digits.length < 10) return null;
  return digits;
}

function formatStartsAtPtBr(startsAtIso: string): string {
  const dt = new Date(startsAtIso);
  if (Number.isNaN(dt.getTime())) return startsAtIso;
  return new Intl.DateTimeFormat("pt-BR", {
    dateStyle: "short",
    timeStyle: "short",
    timeZone: "America/Sao_Paulo"
  }).format(dt);
}

function buildWhatsappMessage(row: WhatsappNotificationRow, appointment: AppointmentTargetRow): string {
  const clientName = appointment.clients?.full_name ?? "Cliente";
  const professionalName = appointment.professionals?.name ?? "Profissional";
  const startsAt = formatStartsAtPtBr(appointment.starts_at);
  const delay =
    typeof row.payload?.predicted_arrival_delay === "number"
      ? Math.max(0, Math.round(row.payload.predicted_arrival_delay))
      : null;
  const eta =
    typeof row.payload?.eta_minutes === "number" ? Math.max(0, Math.round(row.payload.eta_minutes)) : null;

  if (row.type === "punctuality_late_critical") {
    return (
      `[Agenda Profissional]\n` +
      `Alerta de atraso critico na consulta ${startsAt}.\n` +
      `Cliente: ${clientName}\n` +
      `Atraso previsto: ${delay ?? "n/d"} min.\n` +
      `Avaliacao sugerida: considerar remarcacao.`
    );
  }

  if (row.type === "punctuality_late_ok") {
    return (
      `[Agenda Profissional]\n` +
      `Alerta de atraso previsto na consulta ${startsAt}.\n` +
      `Cliente: ${clientName}\n` +
      `Atraso previsto: ${delay ?? "n/d"} min.\n` +
      `ETA atual: ${eta ?? "n/d"} min.`
    );
  }

  return (
    `[Agenda Profissional]\n` +
    `${clientName} esta no horario para a consulta ${startsAt} com ${professionalName}.`
  );
}

async function sendWhatsappMessage(
  to: string,
  message: string,
  phoneNumberId: string
): Promise<{ messageId: string | null; error: string | null; raw?: Record<string, unknown> }> {
  const accessToken = Deno.env.get("WHATSAPP_ACCESS_TOKEN");
  const apiVersion = Deno.env.get("WHATSAPP_API_VERSION") ?? "v22.0";
  if (!accessToken || !phoneNumberId) {
    return { messageId: null, error: "Missing WHATSAPP_ACCESS_TOKEN or phone_number_id" };
  }

  const response = await fetch(`https://graph.facebook.com/${apiVersion}/${phoneNumberId}/messages`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      messaging_product: "whatsapp",
      to,
      type: "text",
      text: { body: message }
    })
  });

  const rawBody = (await response.json().catch(() => ({}))) as Record<string, unknown>;
  if (!response.ok) {
    return {
      messageId: null,
      error: `Meta send failed (${response.status})`,
      raw: rawBody
    };
  }
  const messages = Array.isArray(rawBody.messages) ? rawBody.messages : [];
  const first = messages[0] as Record<string, unknown> | undefined;
  return {
    messageId: (first?.id as string | undefined) ?? null,
    error: null,
    raw: rawBody
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
  const dispatcherSecret = Deno.env.get("PUNCTUALITY_WHATSAPP_DISPATCHER_SECRET") ?? "";
  const dispatchProvider = (Deno.env.get("WHATSAPP_DISPATCH_PROVIDER") ?? "none").trim().toLowerCase();
  const defaultPhoneNumberId = (Deno.env.get("WHATSAPP_PHONE_NUMBER_ID") ?? "").trim();

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
  const providedSecret = req.headers.get("x-whatsapp-dispatcher-secret") ?? payload.secret ?? "";
  if (providedSecret !== dispatcherSecret) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: responseHeaders });
  }

  const admin = createClient(supabaseUrl, serviceRoleKey);
  let query = admin
    .from("notification_log")
    .select("id, tenant_id, appointment_id, type, status, payload")
    .eq("channel", "whatsapp")
    .eq("status", "queued")
    .in("type", ["punctuality_late_ok", "punctuality_late_critical", "punctuality_on_time"])
    .order("created_at", { ascending: true })
    .limit(payload.limit);

  if (payload.tenant_id) {
    query = query.eq("tenant_id", payload.tenant_id);
  }

  const { data: notificationRows, error: notificationError } = await query;
  if (notificationError) {
    return new Response(JSON.stringify({ error: "Could not load queued whatsapp notifications" }), {
      status: 500,
      headers: responseHeaders
    });
  }

  const rows = (notificationRows ?? []) as WhatsappNotificationRow[];
  if (rows.length === 0) {
    return new Response(
      JSON.stringify({ ok: true, processed: 0, sent: 0, failed: 0, provider: dispatchProvider }),
      { status: 200, headers: responseHeaders }
    );
  }

  let sent = 0;
  let failed = 0;

  for (const row of rows) {
    const { data: appointment } = await admin
      .from("appointments")
      .select("id, starts_at, professional_id, client_id, professionals(id, name, user_id), clients(full_name)")
      .eq("tenant_id", row.tenant_id)
      .eq("id", row.appointment_id)
      .maybeSingle();

    const appointmentTarget = (appointment ?? null) as AppointmentTargetRow | null;
    const userId = appointmentTarget?.professionals?.user_id ?? null;
    if (!appointmentTarget || !userId) {
      await admin
        .from("notification_log")
        .update({
          status: "failed",
          payload: {
            ...(row.payload ?? {}),
            whatsapp_dispatch: {
              provider: dispatchProvider,
              reason: "professional_target_not_found"
            }
          }
        })
        .eq("id", row.id);
      failed += 1;
      continue;
    }

    const { data: profile } = await admin
      .from("profiles")
      .select("phone")
      .eq("tenant_id", row.tenant_id)
      .eq("id", userId)
      .maybeSingle();
    const to = normalizeWhatsappTo((profile as { phone?: string | null } | null)?.phone ?? null);
    if (!to) {
      await admin
        .from("notification_log")
        .update({
          status: "failed",
          payload: {
            ...(row.payload ?? {}),
            whatsapp_dispatch: {
              provider: dispatchProvider,
              reason: "professional_phone_not_found"
            }
          }
        })
        .eq("id", row.id);
      failed += 1;
      continue;
    }

    const { data: channelSetting } = await admin
      .from("whatsapp_channel_settings")
      .select("phone_number_id")
      .eq("tenant_id", row.tenant_id)
      .eq("active", true)
      .or(`professional_id.eq.${appointmentTarget.professionals?.id},professional_id.is.null`)
      .order("professional_id", { ascending: false, nullsFirst: false })
      .limit(1)
      .maybeSingle();

    const phoneNumberId = ((channelSetting as { phone_number_id?: string } | null)?.phone_number_id ?? defaultPhoneNumberId).trim();
    if (!phoneNumberId) {
      await admin
        .from("notification_log")
        .update({
          status: "failed",
          payload: {
            ...(row.payload ?? {}),
            whatsapp_dispatch: {
              provider: dispatchProvider,
              reason: "phone_number_id_not_found"
            }
          }
        })
        .eq("id", row.id);
      failed += 1;
      continue;
    }

    const message = buildWhatsappMessage(row, appointmentTarget);

    if (dispatchProvider === "none") {
      await admin
        .from("notification_log")
        .update({
          status: "sent",
          provider_message_id: `mock-wa-${row.id}`,
          payload: {
            ...(row.payload ?? {}),
            whatsapp_dispatch: {
              provider: dispatchProvider,
              sent_at: new Date().toISOString(),
              provider_message_id: `mock-wa-${row.id}`,
              simulated: true,
              to,
              message_preview: message.slice(0, 300)
            }
          }
        })
        .eq("id", row.id);
      sent += 1;
      continue;
    }

    const sendResult = await sendWhatsappMessage(to, message, phoneNumberId);
    if (sendResult.error) {
      await admin
        .from("notification_log")
        .update({
          status: "failed",
          payload: {
            ...(row.payload ?? {}),
            whatsapp_dispatch: {
              provider: dispatchProvider,
              failed_at: new Date().toISOString(),
              reason: "provider_send_failed",
              error: sendResult.error,
              raw: sendResult.raw ?? null
            }
          }
        })
        .eq("id", row.id);
      failed += 1;
      continue;
    }

    await admin
      .from("notification_log")
      .update({
        status: "sent",
        provider_message_id: sendResult.messageId,
        payload: {
          ...(row.payload ?? {}),
          whatsapp_dispatch: {
            provider: dispatchProvider,
            sent_at: new Date().toISOString(),
            provider_message_id: sendResult.messageId,
            to,
            raw: sendResult.raw ?? null
          }
        }
      })
      .eq("id", row.id);
    sent += 1;
  }

  return new Response(
    JSON.stringify({ ok: true, processed: rows.length, sent, failed, provider: dispatchProvider }),
    { status: 200, headers: responseHeaders }
  );
});
