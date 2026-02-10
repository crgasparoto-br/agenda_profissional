import { createClient } from "npm:@supabase/supabase-js@2.49.1";

const jsonHeaders = { "Content-Type": "application/json" };
const ACTIVE_APPOINTMENT_STATUSES = ["scheduled", "confirmed"];

type ConversationMessage = {
  direction: "inbound" | "outbound" | "system";
  message_text: string;
};

type IncomingWhatsappMessage = {
  id?: string;
  from?: string;
  timestamp?: string;
  type?: string;
  text?: { body?: string };
};

type ServiceItem = {
  id: string;
  name: string;
  duration_min: number;
  specialty_id: string | null;
};

type ProfessionalItem = {
  id: string;
  name: string;
};

type ProfessionalServiceLink = {
  professional_id: string;
  service_id: string;
};

type TenantCatalog = {
  services: ServiceItem[];
  professionals: ProfessionalItem[];
  links: ProfessionalServiceLink[];
};

type IntentDecision = {
  intent: "collect_info" | "create_appointment" | "reschedule_appointment";
  confidence: number;
  reply_text: string;
  service_id: string | null;
  service_name: string | null;
  professional_id: string | null;
  professional_name: string | null;
  starts_at_iso: string | null;
  ends_at_iso: string | null;
  duration_min: number | null;
  any_available: boolean;
  target_appointment_id: string | null;
};

type AppointmentExecutionResult = {
  ok: boolean;
  message: string;
  appointmentId?: string;
  startsAtIso?: string;
  professionalName?: string;
  serviceName?: string;
};

function normalizePhone(value: string | null | undefined): string {
  if (!value) return "";
  return value.replace(/[^\d+]/g, "");
}

function sanitizeWhatsappText(value: string): string {
  return value.trim().replace(/\s+/g, " ").slice(0, 4096);
}

function normalizeText(value: string): string {
  return value
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

function resolveTenantId(phoneNumberId: string | null): string | null {
  const mapRaw = Deno.env.get("WHATSAPP_TENANT_MAP_JSON");
  if (mapRaw) {
    try {
      const parsed = JSON.parse(mapRaw) as Record<string, string>;
      if (phoneNumberId && parsed[phoneNumberId]) {
        return parsed[phoneNumberId];
      }
    } catch (_) {
      // Ignore invalid map and fallback to default tenant.
    }
  }

  return Deno.env.get("WHATSAPP_DEFAULT_TENANT_ID") ?? null;
}

async function verifyMetaSignature(req: Request, rawBody: string): Promise<boolean> {
  const appSecret = Deno.env.get("WHATSAPP_APP_SECRET");
  if (!appSecret) return true;

  const signature = req.headers.get("x-hub-signature-256");
  if (!signature || !signature.startsWith("sha256=")) return false;

  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(appSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const digest = await crypto.subtle.sign("HMAC", key, encoder.encode(rawBody));
  const hashHex = Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");

  return `sha256=${hashHex}` === signature;
}

function extractIncomingMessages(payload: unknown): Array<{ phoneNumberId: string | null; message: IncomingWhatsappMessage }> {
  const result: Array<{ phoneNumberId: string | null; message: IncomingWhatsappMessage }> = [];
  if (!payload || typeof payload !== "object") return result;

  const entries = (payload as { entry?: Array<{ changes?: Array<{ value?: Record<string, unknown> }> }> }).entry ?? [];
  for (const entry of entries) {
    const changes = entry.changes ?? [];
    for (const change of changes) {
      const value = change.value ?? {};
      const metadata = (value.metadata ?? {}) as { phone_number_id?: string };
      const messages = (value.messages ?? []) as IncomingWhatsappMessage[];
      for (const message of messages) {
        result.push({ phoneNumberId: metadata.phone_number_id ?? null, message });
      }
    }
  }

  return result;
}

function formatConversationForAI(history: ConversationMessage[]): string {
  const lines = history.map((item) =>
    `${item.direction === "inbound" ? "Cliente" : "Assistente"}: ${item.message_text}`
  );
  return lines.join("\n");
}

function extractJsonObject(text: string): string | null {
  const first = text.indexOf("{");
  if (first < 0) return null;
  let depth = 0;
  for (let i = first; i < text.length; i += 1) {
    const ch = text[i];
    if (ch === "{") depth += 1;
    if (ch === "}") {
      depth -= 1;
      if (depth === 0) return text.slice(first, i + 1);
    }
  }
  return null;
}

function toIsoOrNull(value: unknown): string | null {
  if (typeof value !== "string" || !value.trim()) return null;
  const dt = new Date(value);
  if (Number.isNaN(dt.getTime())) return null;
  return dt.toISOString();
}

function toNullableString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

function parseIntentDecision(raw: unknown): IntentDecision | null {
  if (!raw || typeof raw !== "object") return null;
  const item = raw as Record<string, unknown>;
  const intent = item.intent;
  if (intent !== "collect_info" && intent !== "create_appointment" && intent !== "reschedule_appointment") {
    return null;
  }

  const confidenceRaw = Number(item.confidence ?? 0);
  const confidence = Number.isFinite(confidenceRaw)
    ? Math.min(Math.max(confidenceRaw, 0), 1)
    : 0;

  return {
    intent,
    confidence,
    reply_text:
      toNullableString(item.reply_text) ??
      "Perfeito. Pode me dizer servico e horario que voce prefere?",
    service_id: toNullableString(item.service_id),
    service_name: toNullableString(item.service_name),
    professional_id: toNullableString(item.professional_id),
    professional_name: toNullableString(item.professional_name),
    starts_at_iso: toIsoOrNull(item.starts_at_iso),
    ends_at_iso: toIsoOrNull(item.ends_at_iso),
    duration_min: Number.isFinite(Number(item.duration_min))
      ? Number(item.duration_min)
      : null,
    any_available: Boolean(item.any_available),
    target_appointment_id: toNullableString(item.target_appointment_id)
  };
}

async function loadTenantCatalog(admin: ReturnType<typeof createClient>, tenantId: string): Promise<TenantCatalog> {
  const [{ data: servicesRows }, { data: professionalsRows }, { data: linksRows }] = await Promise.all([
    admin
      .from("services")
      .select("id, name, duration_min, specialty_id")
      .eq("tenant_id", tenantId)
      .eq("active", true),
    admin
      .from("professionals")
      .select("id, name")
      .eq("tenant_id", tenantId)
      .eq("active", true),
    admin
      .from("professional_services")
      .select("professional_id, service_id")
      .eq("tenant_id", tenantId)
  ]);

  return {
    services: (servicesRows ?? []) as ServiceItem[],
    professionals: (professionalsRows ?? []) as ProfessionalItem[],
    links: (linksRows ?? []) as ProfessionalServiceLink[]
  };
}

function resolveService(catalog: TenantCatalog, decision: IntentDecision): ServiceItem | null {
  if (decision.service_id) {
    const byId = catalog.services.find((item) => item.id === decision.service_id);
    if (byId) return byId;
  }

  if (!decision.service_name) return null;
  const query = normalizeText(decision.service_name);
  if (!query) return null;

  return (
    catalog.services.find((item) => normalizeText(item.name) === query) ??
    catalog.services.find((item) => normalizeText(item.name).includes(query) || query.includes(normalizeText(item.name))) ??
    null
  );
}

function resolveProfessional(catalog: TenantCatalog, decision: IntentDecision): ProfessionalItem | null {
  if (decision.professional_id) {
    const byId = catalog.professionals.find((item) => item.id === decision.professional_id);
    if (byId) return byId;
  }

  if (!decision.professional_name) return null;
  const query = normalizeText(decision.professional_name);
  if (!query) return null;

  return (
    catalog.professionals.find((item) => normalizeText(item.name) === query) ??
    catalog.professionals.find(
      (item) => normalizeText(item.name).includes(query) || query.includes(normalizeText(item.name))
    ) ??
    null
  );
}

async function hasAppointmentConflict(
  admin: ReturnType<typeof createClient>,
  tenantId: string,
  professionalId: string,
  startsAtIso: string,
  endsAtIso: string
): Promise<boolean> {
  const { data } = await admin
    .from("appointments")
    .select("id")
    .eq("tenant_id", tenantId)
    .eq("professional_id", professionalId)
    .in("status", ACTIVE_APPOINTMENT_STATUSES)
    .lt("starts_at", endsAtIso)
    .gt("ends_at", startsAtIso)
    .limit(1);

  return Boolean(data && data.length > 0);
}

async function chooseProfessional(
  admin: ReturnType<typeof createClient>,
  tenantId: string,
  catalog: TenantCatalog,
  serviceId: string,
  startsAtIso: string,
  endsAtIso: string,
  preferredProfessionalId: string | null,
  anyAvailable: boolean
): Promise<ProfessionalItem | null> {
  const linkedIds = new Set(
    catalog.links.filter((link) => link.service_id === serviceId).map((link) => link.professional_id)
  );
  if (linkedIds.size === 0) return null;

  if (preferredProfessionalId && !anyAvailable) {
    if (!linkedIds.has(preferredProfessionalId)) return null;
    const preferred = catalog.professionals.find((item) => item.id === preferredProfessionalId) ?? null;
    if (!preferred) return null;
    const conflict = await hasAppointmentConflict(admin, tenantId, preferred.id, startsAtIso, endsAtIso);
    return conflict ? null : preferred;
  }

  const candidates = catalog.professionals.filter((professional) => linkedIds.has(professional.id));
  for (const candidate of candidates) {
    const conflict = await hasAppointmentConflict(admin, tenantId, candidate.id, startsAtIso, endsAtIso);
    if (!conflict) return candidate;
  }

  return null;
}

function formatDateTimePtBr(iso: string): string {
  const dt = new Date(iso);
  const dd = String(dt.getDate()).padStart(2, "0");
  const mm = String(dt.getMonth() + 1).padStart(2, "0");
  const yyyy = dt.getFullYear();
  const hh = String(dt.getHours()).padStart(2, "0");
  const min = String(dt.getMinutes()).padStart(2, "0");
  return `${dd}/${mm}/${yyyy} ${hh}:${min}`;
}

async function createAppointmentFromDecision(
  admin: ReturnType<typeof createClient>,
  tenantId: string,
  clientId: string,
  catalog: TenantCatalog,
  decision: IntentDecision
): Promise<AppointmentExecutionResult> {
  const service = resolveService(catalog, decision);
  if (!service) {
    return {
      ok: false,
      message:
        "Nao consegui identificar o servico. Pode me dizer exatamente qual servico voce quer agendar?"
    };
  }

  if (!decision.starts_at_iso) {
    return {
      ok: false,
      message:
        "Perfeito. Me diga a data e horario desejados para eu confirmar seu agendamento."
    };
  }

  const startsAt = new Date(decision.starts_at_iso);
  if (Number.isNaN(startsAt.getTime())) {
    return { ok: false, message: "Nao consegui entender o horario. Pode enviar novamente?" };
  }

  const durationMin = decision.duration_min && decision.duration_min > 0
    ? decision.duration_min
    : service.duration_min;

  const endsAtIso =
    decision.ends_at_iso ??
    new Date(startsAt.getTime() + durationMin * 60_000).toISOString();

  const preferredProfessional = resolveProfessional(catalog, decision);
  const selectedProfessional = await chooseProfessional(
    admin,
    tenantId,
    catalog,
    service.id,
    startsAt.toISOString(),
    endsAtIso,
    preferredProfessional?.id ?? null,
    decision.any_available || !preferredProfessional
  );

  if (!selectedProfessional) {
    return {
      ok: false,
      message:
        "Nao encontrei profissional disponivel nesse horario. Posso buscar a proxima opcao para voce?"
    };
  }

  const { data: inserted, error } = await admin
    .from("appointments")
    .insert({
      tenant_id: tenantId,
      client_id: clientId,
      service_id: service.id,
      specialty_id: service.specialty_id,
      professional_id: selectedProfessional.id,
      starts_at: startsAt.toISOString(),
      ends_at: endsAtIso,
      status: "scheduled",
      source: "client_link",
      assigned_at: new Date().toISOString()
    })
    .select("id, starts_at")
    .single();

  if (error || !inserted) {
    return { ok: false, message: "Nao consegui confirmar agora. Pode tentar novamente em instantes?" };
  }

  return {
    ok: true,
    message: `Agendamento confirmado para ${formatDateTimePtBr(inserted.starts_at)} com ${selectedProfessional.name} (${service.name}).`,
    appointmentId: inserted.id,
    startsAtIso: inserted.starts_at,
    professionalName: selectedProfessional.name,
    serviceName: service.name
  };
}

async function rescheduleAppointmentFromDecision(
  admin: ReturnType<typeof createClient>,
  tenantId: string,
  clientId: string,
  catalog: TenantCatalog,
  decision: IntentDecision
): Promise<AppointmentExecutionResult> {
  const targetQuery = admin
    .from("appointments")
    .select("id, service_id, professional_id, starts_at, ends_at, status")
    .eq("tenant_id", tenantId)
    .eq("client_id", clientId)
    .in("status", ACTIVE_APPOINTMENT_STATUSES)
    .order("starts_at", { ascending: true })
    .limit(1);

  const { data: targetRows } = decision.target_appointment_id
    ? await targetQuery.eq("id", decision.target_appointment_id)
    : await targetQuery.gte("starts_at", new Date().toISOString());

  const target = targetRows?.[0];
  if (!target) {
    return {
      ok: false,
      message:
        "Nao encontrei agendamento ativo para remarcar. Quer que eu crie um novo?"
    };
  }

  const enrichedDecision: IntentDecision = {
    ...decision,
    service_id: decision.service_id ?? target.service_id,
    professional_id: decision.professional_id ?? target.professional_id,
    any_available: decision.any_available || !decision.professional_id
  };

  const created = await createAppointmentFromDecision(
    admin,
    tenantId,
    clientId,
    catalog,
    enrichedDecision
  );
  if (!created.ok || !created.appointmentId) return created;

  await admin
    .from("appointments")
    .update({
      status: "rescheduled",
      cancellation_reason: `Remarcado via WhatsApp para ${created.appointmentId}`
    })
    .eq("tenant_id", tenantId)
    .eq("id", target.id);

  return {
    ...created,
    message: `Remarcacao concluida. ${created.message}`
  };
}

function buildCatalogPrompt(catalog: TenantCatalog): string {
  return JSON.stringify(
    {
      services: catalog.services.map((item) => ({
        id: item.id,
        name: item.name,
        duration_min: item.duration_min
      })),
      professionals: catalog.professionals.map((item) => ({ id: item.id, name: item.name })),
      links: catalog.links
    },
    null,
    2
  );
}

async function decideIntentWithAI(
  conversationText: string,
  catalog: TenantCatalog
): Promise<IntentDecision> {
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) {
    return {
      intent: "collect_info",
      confidence: 0,
      reply_text: "Recebi sua mensagem. Pode me enviar servico e horario desejado?",
      service_id: null,
      service_name: null,
      professional_id: null,
      professional_name: null,
      starts_at_iso: null,
      ends_at_iso: null,
      duration_min: null,
      any_available: true,
      target_appointment_id: null
    };
  }

  const model = Deno.env.get("OPENAI_MODEL") ?? "gpt-4.1-mini";
  const basePrompt =
    Deno.env.get("OPENAI_WHATSAPP_SYSTEM_PROMPT") ??
    "Voce e o assistente virtual da Agenda Profissional. Responda em portugues do Brasil com linguagem natural e objetiva.";

  const systemPrompt = `${basePrompt}
Sua tarefa e retornar SOMENTE um JSON valido com este formato:
{
  "intent": "collect_info|create_appointment|reschedule_appointment",
  "confidence": 0.0,
  "reply_text": "texto para o cliente",
  "service_id": "uuid|null",
  "service_name": "texto|null",
  "professional_id": "uuid|null",
  "professional_name": "texto|null",
  "starts_at_iso": "ISO 8601|null",
  "ends_at_iso": "ISO 8601|null",
  "duration_min": 30,
  "any_available": true,
  "target_appointment_id": "uuid|null"
}
Regras:
- Nao invente IDs.
- Se faltar dado para executar agendamento/remarcacao, use intent=collect_info e reply_text pedindo so o que falta.
- Use o catalogo abaixo para mapear nomes:
${buildCatalogPrompt(catalog)}
Agora atual: ${new Date().toISOString()}`;

  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model,
      input: [
        { role: "system", content: [{ type: "input_text", text: systemPrompt }] },
        { role: "user", content: [{ type: "input_text", text: conversationText }] }
      ],
      max_output_tokens: 500
    })
  });

  if (!response.ok) {
    return {
      intent: "collect_info",
      confidence: 0,
      reply_text:
        "Consegui registrar sua mensagem. Pode me informar servico e horario para seguir com o agendamento?",
      service_id: null,
      service_name: null,
      professional_id: null,
      professional_name: null,
      starts_at_iso: null,
      ends_at_iso: null,
      duration_min: null,
      any_available: true,
      target_appointment_id: null
    };
  }

  const data = (await response.json()) as { output_text?: string };
  const outputText = (data.output_text ?? "").trim();
  const jsonText = extractJsonObject(outputText);
  if (!jsonText) {
    return {
      intent: "collect_info",
      confidence: 0,
      reply_text:
        "Entendi. Pode confirmar servico e horario desejado para eu finalizar?",
      service_id: null,
      service_name: null,
      professional_id: null,
      professional_name: null,
      starts_at_iso: null,
      ends_at_iso: null,
      duration_min: null,
      any_available: true,
      target_appointment_id: null
    };
  }

  const parsed = (() => {
    try {
      return JSON.parse(jsonText) as unknown;
    } catch (_) {
      return null;
    }
  })();
  const intent = parseIntentDecision(parsed);
  if (!intent) {
    return {
      intent: "collect_info",
      confidence: 0,
      reply_text:
        "Perfeito. Me diga servico, data e horario preferidos para eu continuar.",
      service_id: null,
      service_name: null,
      professional_id: null,
      professional_name: null,
      starts_at_iso: null,
      ends_at_iso: null,
      duration_min: null,
      any_available: true,
      target_appointment_id: null
    };
  }

  return intent;
}

async function sendWhatsappMessage(
  to: string,
  message: string,
  phoneNumberIdFromWebhook: string | null
): Promise<string | null> {
  const accessToken = Deno.env.get("WHATSAPP_ACCESS_TOKEN");
  const defaultPhoneNumberId = Deno.env.get("WHATSAPP_PHONE_NUMBER_ID");
  const apiVersion = Deno.env.get("WHATSAPP_API_VERSION") ?? "v22.0";

  const phoneNumberId = phoneNumberIdFromWebhook ?? defaultPhoneNumberId ?? "";
  if (!accessToken || !phoneNumberId) return null;

  const response = await fetch(
    `https://graph.facebook.com/${apiVersion}/${phoneNumberId}/messages`,
    {
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
    }
  );

  if (!response.ok) return null;
  const data = (await response.json()) as { messages?: Array<{ id?: string }> };
  return data.messages?.[0]?.id ?? null;
}

Deno.serve(async (req) => {
  if (req.method === "GET") {
    const verifyToken = Deno.env.get("WHATSAPP_VERIFY_TOKEN");
    const url = new URL(req.url);
    const mode = url.searchParams.get("hub.mode");
    const token = url.searchParams.get("hub.verify_token");
    const challenge = url.searchParams.get("hub.challenge");

    if (mode === "subscribe" && verifyToken && token === verifyToken && challenge) {
      return new Response(challenge, { status: 200 });
    }

    return new Response("Forbidden", { status: 403 });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: jsonHeaders
    });
  }

  const rawBody = await req.text();
  const signatureOk = await verifyMetaSignature(req, rawBody);
  if (!signatureOk) {
    return new Response(JSON.stringify({ error: "Invalid signature" }), {
      status: 401,
      headers: jsonHeaders
    });
  }

  const payload = (() => {
    try {
      return JSON.parse(rawBody) as unknown;
    } catch (_) {
      return null;
    }
  })();

  if (!payload) {
    return new Response(JSON.stringify({ error: "Invalid JSON payload" }), {
      status: 400,
      headers: jsonHeaders
    });
  }

  const incoming = extractIncomingMessages(payload);
  if (incoming.length === 0) {
    return new Response(JSON.stringify({ ok: true, processed: 0 }), {
      status: 200,
      headers: jsonHeaders
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? Deno.env.get("APP_SUPABASE_URL");
  const serviceRoleKey =
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("APP_SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return new Response(JSON.stringify({ error: "Missing Supabase env" }), {
      status: 500,
      headers: jsonHeaders
    });
  }

  const admin = createClient(supabaseUrl, serviceRoleKey);
  let processed = 0;

  for (const item of incoming) {
    try {
      const rawPhone = normalizePhone(item.message.from);
      const rawText = sanitizeWhatsappText(item.message.text?.body ?? "");
      if (!rawPhone || !rawText) continue;

      const tenantId = resolveTenantId(item.phoneNumberId);
      if (!tenantId) continue;

      const { data: existingClient } = await admin
        .from("clients")
        .select("id, full_name")
        .eq("tenant_id", tenantId)
        .eq("phone", rawPhone)
        .order("created_at", { ascending: true })
        .limit(1)
        .maybeSingle();

      let clientId = existingClient?.id ?? null;
      if (!clientId) {
        const { data: createdClient } = await admin
          .from("clients")
          .insert({
            tenant_id: tenantId,
            full_name: "Cliente WhatsApp",
            phone: rawPhone
          })
          .select("id")
          .single();
        clientId = createdClient?.id ?? null;
      }
      if (!clientId) continue;

      const { data: conversation } = await admin
        .from("whatsapp_conversations")
        .upsert(
          {
            tenant_id: tenantId,
            client_id: clientId,
            wa_phone: rawPhone,
            status: "open",
            last_message_at: new Date().toISOString()
          },
          { onConflict: "tenant_id,wa_phone" }
        )
        .select("id")
        .single();

      const conversationId = conversation?.id;
      if (!conversationId) continue;

      await admin.from("whatsapp_messages").insert({
        tenant_id: tenantId,
        conversation_id: conversationId,
        client_id: clientId,
        direction: "inbound",
        provider_message_id: item.message.id ?? null,
        message_text: rawText,
        ai_payload: {}
      });

      const { data: historyRows } = await admin
        .from("whatsapp_messages")
        .select("direction, message_text")
        .eq("tenant_id", tenantId)
        .eq("conversation_id", conversationId)
        .order("created_at", { ascending: false })
        .limit(12);

      const history = ((historyRows ?? []) as ConversationMessage[]).reverse();
      const conversationText = formatConversationForAI(history);
      const catalog = await loadTenantCatalog(admin, tenantId);
      const decision = await decideIntentWithAI(conversationText, catalog);

      let finalReply = decision.reply_text;
      let actionResult: AppointmentExecutionResult | null = null;

      if (decision.confidence >= 0.6 && decision.intent === "create_appointment") {
        actionResult = await createAppointmentFromDecision(
          admin,
          tenantId,
          clientId,
          catalog,
          decision
        );
        if (actionResult.ok) {
          finalReply = actionResult.message;
        } else if (decision.intent !== "collect_info") {
          finalReply = actionResult.message;
        }
      }

      if (decision.confidence >= 0.6 && decision.intent === "reschedule_appointment") {
        actionResult = await rescheduleAppointmentFromDecision(
          admin,
          tenantId,
          clientId,
          catalog,
          decision
        );
        if (actionResult.ok) {
          finalReply = actionResult.message;
        } else {
          finalReply = actionResult.message;
        }
      }

      const providerReplyMessageId = await sendWhatsappMessage(
        rawPhone,
        finalReply,
        item.phoneNumberId
      );

      await admin.from("whatsapp_messages").insert({
        tenant_id: tenantId,
        conversation_id: conversationId,
        client_id: clientId,
        direction: "outbound",
        provider_message_id: providerReplyMessageId,
        message_text: finalReply,
        ai_payload: {
          model: Deno.env.get("OPENAI_MODEL") ?? "gpt-4.1-mini",
          source: "openai-responses",
          decision,
          action_result: actionResult
        }
      });

      processed += 1;
    } catch (_) {
      // Keep webhook resilient by processing remaining messages.
      continue;
    }
  }

  return new Response(JSON.stringify({ ok: true, processed }), {
    status: 200,
    headers: jsonHeaders
  });
});
