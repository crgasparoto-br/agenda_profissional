import { createClient } from "npm:@supabase/supabase-js@2.49.1";
const jsonHeaders = {
  "Content-Type": "application/json"
};
const ACTIVE_APPOINTMENT_STATUSES = [
  "scheduled",
  "confirmed"
];
const ACTIVE_APPOINTMENT_STATUSES_SET = new Set(ACTIVE_APPOINTMENT_STATUSES);
function normalizePhone(value) {
  if (!value) return "";
  return value.replace(/[^\d+]/g, "");
}
function sanitizeWhatsappText(value) {
  return value.trim().replace(/\s+/g, " ").slice(0, 4096);
}
function isTruthyEnv(value) {
  if (!value) return false;
  return [
    "1",
    "true",
    "yes",
    "on"
  ].includes(value.trim().toLowerCase());
}
function parseEnvInteger(value, fallback) {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}
function extensionFromMimeType(mimeType) {
  if (!mimeType) return "bin";
  if (mimeType.includes("ogg")) return "ogg";
  if (mimeType.includes("mpeg")) return "mp3";
  if (mimeType.includes("mp4")) return "mp4";
  if (mimeType.includes("wav")) return "wav";
  if (mimeType.includes("webm")) return "webm";
  return "bin";
}
function normalizeText(value) {
  return value.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/\s+/g, " ").trim();
}
function parseMinutes(value) {
  const [hour, minute] = value.split(":").map((item)=>Number.parseInt(item, 10));
  if (Number.isNaN(hour) || Number.isNaN(minute)) return null;
  return hour * 60 + minute;
}
function parseWorkdays(raw) {
  if (!Array.isArray(raw)) return [];
  return raw.map((item)=>Number(item)).filter((item)=>Number.isInteger(item) && item >= 0 && item <= 6);
}
function parseBreakConfig(raw, fallbackStart, fallbackEnd) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return {
      enabled: false,
      start: fallbackStart,
      end: fallbackEnd
    };
  }
  const value = raw;
  const enabled = value.enabled === true;
  const start = typeof value.start === "string" ? value.start : fallbackStart;
  const end = typeof value.end === "string" ? value.end : fallbackEnd;
  return {
    enabled,
    start,
    end
  };
}
function getWeekdayAndMinutesInTimezone(isoValue, timezone) {
  const date = new Date(isoValue);
  if (Number.isNaN(date.getTime())) return null;
  const weekdayFormat = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone,
    weekday: "short"
  });
  const hourFormat = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone,
    hour: "2-digit",
    hour12: false
  });
  const minuteFormat = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone,
    minute: "2-digit"
  });
  const weekdayMap = {
    Sun: 0,
    Mon: 1,
    Tue: 2,
    Wed: 3,
    Thu: 4,
    Fri: 5,
    Sat: 6
  };
  const weekdayLabel = weekdayFormat.format(date);
  const weekday = weekdayMap[weekdayLabel];
  const hour = Number.parseInt(hourFormat.format(date), 10);
  const minute = Number.parseInt(minuteFormat.format(date), 10);
  if (weekday === undefined || Number.isNaN(hour) || Number.isNaN(minute)) return null;
  return {
    weekday,
    minutes: hour * 60 + minute
  };
}
function overlaps(startA, endA, startB, endB) {
  return startA < endB && startB < endA;
}
function hasUnavailabilityOverlap(unavailabilityRows, startsAtIso, endsAtIso) {
  if (!unavailabilityRows || unavailabilityRows.length === 0) return false;
  const startsAt = new Date(startsAtIso);
  const endsAt = new Date(endsAtIso);
  if (Number.isNaN(startsAt.getTime()) || Number.isNaN(endsAt.getTime())) return true;
  return unavailabilityRows.some((item)=>{
    const absenceStart = new Date(item.starts_at);
    const absenceEnd = new Date(item.ends_at);
    if (Number.isNaN(absenceStart.getTime()) || Number.isNaN(absenceEnd.getTime())) return true;
    return startsAt < absenceEnd && absenceStart < endsAt;
  });
}
function findOverlappingUnavailability(unavailabilityRows, startsAtIso, endsAtIso) {
  if (!unavailabilityRows || unavailabilityRows.length === 0) return null;
  const startsAt = new Date(startsAtIso);
  const endsAt = new Date(endsAtIso);
  if (Number.isNaN(startsAt.getTime()) || Number.isNaN(endsAt.getTime())) return null;
  for (const item of unavailabilityRows){
    const absenceStart = new Date(item.starts_at);
    const absenceEnd = new Date(item.ends_at);
    if (Number.isNaN(absenceStart.getTime()) || Number.isNaN(absenceEnd.getTime())) continue;
    if (startsAt < absenceEnd && absenceStart < endsAt) {
      return item;
    }
  }
  return null;
}
function isWithinSchedule(settings, startsAtIso, endsAtIso) {
  if (!settings) return true;
  const timezone = settings.timezone || "America/Sao_Paulo";
  const startInTz = getWeekdayAndMinutesInTimezone(startsAtIso, timezone);
  const endInTz = getWeekdayAndMinutesInTimezone(endsAtIso, timezone);
  if (!startInTz || !endInTz) return false;
  if (startInTz.weekday !== endInTz.weekday) return false;
  if (endInTz.minutes <= startInTz.minutes) return false;
  const workdays = parseWorkdays(settings.workdays);
  if (workdays.length > 0 && !workdays.includes(startInTz.weekday)) return false;
  const workHours = settings.work_hours && typeof settings.work_hours === "object" && !Array.isArray(settings.work_hours) ? settings.work_hours : {};
  const dailyOverrides = workHours.daily_overrides && typeof workHours.daily_overrides === "object" && !Array.isArray(workHours.daily_overrides) ? workHours.daily_overrides : {};
  const overrideForWeekday = dailyOverrides[String(startInTz.weekday)];
  const dayRule = overrideForWeekday && typeof overrideForWeekday === "object" && !Array.isArray(overrideForWeekday) ? overrideForWeekday : workHours;
  const workStart = typeof dayRule.start === "string" ? parseMinutes(dayRule.start) : parseMinutes("09:00");
  const workEnd = typeof dayRule.end === "string" ? parseMinutes(dayRule.end) : parseMinutes("18:00");
  if (workStart === null || workEnd === null || workStart >= workEnd) return false;
  if (startInTz.minutes < workStart || endInTz.minutes > workEnd) return false;
  const lunchBreak = parseBreakConfig(dayRule.lunch_break, "12:00", "13:00");
  if (lunchBreak.enabled) {
    const lunchStart = parseMinutes(lunchBreak.start);
    const lunchEnd = parseMinutes(lunchBreak.end);
    if (lunchStart === null || lunchEnd === null || lunchStart >= lunchEnd) return false;
    if (overlaps(startInTz.minutes, endInTz.minutes, lunchStart, lunchEnd)) return false;
  }
  const snackBreak = parseBreakConfig(dayRule.snack_break, "16:00", "16:15");
  if (snackBreak.enabled) {
    const snackStart = parseMinutes(snackBreak.start);
    const snackEnd = parseMinutes(snackBreak.end);
    if (snackStart === null || snackEnd === null || snackStart >= snackEnd) return false;
    if (overlaps(startInTz.minutes, endInTz.minutes, snackStart, snackEnd)) return false;
  }
  return true;
}
function hasAppointmentOverlapInMemory(rows, startsAtIso, endsAtIso) {
  if (!rows || rows.length === 0) return false;
  const startsAt = new Date(startsAtIso);
  const endsAt = new Date(endsAtIso);
  if (Number.isNaN(startsAt.getTime()) || Number.isNaN(endsAt.getTime())) return true;
  return rows.some((item)=>{
    const itemStart = new Date(item.starts_at);
    const itemEnd = new Date(item.ends_at);
    if (Number.isNaN(itemStart.getTime()) || Number.isNaN(itemEnd.getTime())) return true;
    return startsAt < itemEnd && itemStart < endsAt;
  });
}
function resolveTenantIdFromEnv(phoneNumberId) {
  const mapRaw = Deno.env.get("WHATSAPP_TENANT_MAP_JSON");
  if (mapRaw) {
    try {
      const parsed = JSON.parse(mapRaw);
      if (phoneNumberId && parsed[phoneNumberId]) {
        return parsed[phoneNumberId];
      }
    } catch (_) {
    // Ignore invalid map and fallback to default tenant.
    }
  }
  return Deno.env.get("WHATSAPP_DEFAULT_TENANT_ID") ?? null;
}
async function resolveTenantChannelConfig(admin, phoneNumberId) {
  if (phoneNumberId) {
    const { data: channelSetting } = await admin.from("whatsapp_channel_settings").select("tenant_id, phone_number_id, ai_enabled, audio_enabled, ai_model, ai_system_prompt").eq("phone_number_id", phoneNumberId).eq("active", true).limit(1).maybeSingle();
    if (channelSetting) {
      const typed = channelSetting;
      return {
        tenantId: typed.tenant_id,
        outboundPhoneNumberId: typed.phone_number_id,
        accessToken: await resolveWhatsappAccessToken(admin, typed.tenant_id),
        aiEnabled: typed.ai_enabled,
        audioEnabled: typed.audio_enabled,
        aiModel: typed.ai_model,
        aiSystemPrompt: typed.ai_system_prompt
      };
    }
  }
  const fallbackTenantId = resolveTenantIdFromEnv(phoneNumberId);
  if (!fallbackTenantId) return null;
  return {
    tenantId: fallbackTenantId,
    outboundPhoneNumberId: phoneNumberId ?? Deno.env.get("WHATSAPP_PHONE_NUMBER_ID") ?? null,
    accessToken: Deno.env.get("WHATSAPP_ACCESS_TOKEN") ?? null,
    aiEnabled: true,
    audioEnabled: isTruthyEnv(Deno.env.get("WHATSAPP_AUDIO_ENABLED")),
    aiModel: null,
    aiSystemPrompt: null
  };
}
async function resolveWhatsappAccessToken(admin, tenantId) {
  const { data: credential } = await admin.from("whatsapp_meta_credentials").select("access_token").eq("tenant_id", tenantId).limit(1).maybeSingle();
  const tenantToken = credential?.access_token?.trim() ?? "";
  if (tenantToken) return tenantToken;
  return Deno.env.get("WHATSAPP_ACCESS_TOKEN") ?? null;
}
async function fetchWhatsappMediaDetails(mediaId, accessToken) {
  const apiVersion = Deno.env.get("WHATSAPP_API_VERSION") ?? "v22.0";
  if (!accessToken) {
    throw new Error("Missing WHATSAPP_ACCESS_TOKEN");
  }
  const detailsResponse = await fetch(`https://graph.facebook.com/${apiVersion}/${mediaId}`, {
    headers: {
      Authorization: `Bearer ${accessToken}`
    }
  });
  if (!detailsResponse.ok) {
    const errorBody = await detailsResponse.text().catch(()=>"");
    throw new Error(`Meta media lookup failed (${detailsResponse.status}): ${errorBody.slice(0, 300)}`);
  }
  const payload = await detailsResponse.json();
  const url = typeof payload.url === "string" ? payload.url : "";
  if (!url) {
    throw new Error("Meta media lookup did not return a URL");
  }
  return {
    id: typeof payload.id === "string" ? payload.id : mediaId,
    url,
    mimeType: typeof payload.mime_type === "string" ? payload.mime_type : null,
    sha256: typeof payload.sha256 === "string" ? payload.sha256 : null,
    fileSizeBytes: typeof payload.file_size === "number" && Number.isFinite(payload.file_size) ? payload.file_size : null
  };
}
async function downloadWhatsappMedia(details, accessToken) {
  if (!accessToken) {
    throw new Error("Missing WHATSAPP_ACCESS_TOKEN");
  }
  const maxBytes = parseEnvInteger(Deno.env.get("WHATSAPP_AUDIO_MAX_BYTES"), 16 * 1024 * 1024);
  if (details.fileSizeBytes && details.fileSizeBytes > maxBytes) {
    throw new Error(`Audio exceeds max allowed size (${details.fileSizeBytes} bytes)`);
  }
  const mediaResponse = await fetch(details.url, {
    headers: {
      Authorization: `Bearer ${accessToken}`
    }
  });
  if (!mediaResponse.ok) {
    const errorBody = await mediaResponse.text().catch(()=>"");
    throw new Error(`Meta media download failed (${mediaResponse.status}): ${errorBody.slice(0, 300)}`);
  }
  const mediaBlob = await mediaResponse.blob();
  if (mediaBlob.size > maxBytes) {
    throw new Error(`Audio exceeds max allowed size (${mediaBlob.size} bytes)`);
  }
  return mediaBlob;
}
async function transcribeAudioBlob(audioBlob, mimeType) {
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) {
    throw new Error("Missing OPENAI_API_KEY");
  }
  const transcriptionModel = Deno.env.get("OPENAI_AUDIO_TRANSCRIPTION_MODEL") ?? "gpt-4o-mini-transcribe";
  const formData = new FormData();
  formData.append("model", transcriptionModel);
  formData.append("file", audioBlob, `whatsapp-audio.${extensionFromMimeType(mimeType)}`);
  const response = await fetch("https://api.openai.com/v1/audio/transcriptions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`
    },
    body: formData
  });
  if (!response.ok) {
    const errorBody = await response.text().catch(()=>"");
    throw new Error(`OpenAI transcription failed (${response.status}): ${errorBody.slice(0, 300)}`);
  }
  const payload = await response.json();
  const text = typeof payload.text === "string" ? payload.text : "";
  return sanitizeWhatsappText(text);
}
async function resolveInboundMessageContent(message, channelConfig) {
  const rawText = sanitizeWhatsappText(message.text?.body ?? "");
  if (rawText) {
    return {
      messageType: "text",
      messageText: rawText,
      transcriptionText: null,
      mediaId: null,
      mediaMimeType: null,
      mediaSha256: null,
      aiPayload: {},
      autoReply: null
    };
  }
  const audioId = message.audio?.id?.trim() ?? "";
  if (message.type !== "audio" || !audioId) {
    return null;
  }
  const basePayload = {
    audio: {
      id: audioId,
      mime_type: message.audio?.mime_type ?? null,
      sha256: message.audio?.sha256 ?? null,
      voice: message.audio?.voice ?? false
    }
  };
  if (!channelConfig.audioEnabled) {
    return {
      messageType: "audio",
      messageText: "[audio recebido sem processamento]",
      transcriptionText: null,
      mediaId: audioId,
      mediaMimeType: message.audio?.mime_type ?? null,
      mediaSha256: message.audio?.sha256 ?? null,
      aiPayload: {
        ...basePayload,
        audio_processing: {
          supported: false
        }
      },
      autoReply: "Recebi seu audio, mas este canal ainda nao aceita mensagens de voz. Pode me enviar por texto?"
    };
  }
  try {
    const details = await fetchWhatsappMediaDetails(audioId, channelConfig.accessToken);
    const audioBlob = await downloadWhatsappMedia(details, channelConfig.accessToken);
    const transcriptionText = await transcribeAudioBlob(audioBlob, details.mimeType);
    if (!transcriptionText) {
      return {
        messageType: "audio",
        messageText: "[audio sem transcricao legivel]",
        transcriptionText: null,
        mediaId: details.id,
        mediaMimeType: details.mimeType,
        mediaSha256: details.sha256,
        aiPayload: {
          ...basePayload,
          audio_processing: {
            supported: true,
            transcribed: false
          }
        },
        autoReply: "Recebi seu audio, mas nao consegui entender o conteudo. Pode reenviar um audio mais curto ou escrever por texto?"
      };
    }
    return {
      messageType: "audio",
      messageText: transcriptionText,
      transcriptionText,
      mediaId: details.id,
      mediaMimeType: details.mimeType,
      mediaSha256: details.sha256,
      aiPayload: {
        ...basePayload,
        audio_processing: {
          supported: true,
          transcribed: true,
          mime_type: details.mimeType,
          file_size_bytes: details.fileSizeBytes
        }
      },
      autoReply: null
    };
  } catch (error) {
    const reason = error instanceof Error ? error.message : "audio_processing_failed";
    return {
      messageType: "audio",
      messageText: "[audio com falha na transcricao]",
      transcriptionText: null,
      mediaId: audioId,
      mediaMimeType: message.audio?.mime_type ?? null,
      mediaSha256: message.audio?.sha256 ?? null,
      aiPayload: {
        ...basePayload,
        audio_processing: {
          supported: true,
          transcribed: false,
          error: reason
        }
      },
      autoReply: "Recebi seu audio, mas nao consegui transcreve-lo agora. Pode reenviar um audio mais curto ou escrever por texto?"
    };
  }
}
async function verifyMetaSignature(req, rawBody) {
  const appSecret = Deno.env.get("WHATSAPP_APP_SECRET");
  if (!appSecret) return true;
  const signature = req.headers.get("x-hub-signature-256");
  if (!signature || !signature.startsWith("sha256=")) return false;
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey("raw", encoder.encode(appSecret), {
    name: "HMAC",
    hash: "SHA-256"
  }, false, [
    "sign"
  ]);
  const digest = await crypto.subtle.sign("HMAC", key, encoder.encode(rawBody));
  const hashHex = Array.from(new Uint8Array(digest)).map((byte)=>byte.toString(16).padStart(2, "0")).join("");
  return `sha256=${hashHex}` === signature;
}
function extractIncomingMessages(payload) {
  const result = [];
  if (!payload || typeof payload !== "object") return result;
  const entries = payload.entry ?? [];
  for (const entry of entries){
    const changes = entry.changes ?? [];
    for (const change of changes){
      const value = change.value ?? {};
      const metadata = value.metadata ?? {};
      const messages = value.messages ?? [];
      const contacts = value.contacts ?? [];
      for (const message of messages){
        const contactMatch = contacts.find((item)=>item.wa_id === message.from) ?? contacts[0] ?? null;
        const contactName = contactMatch?.profile?.name?.trim() || null;
        result.push({
          phoneNumberId: metadata.phone_number_id ?? null,
          message: {
            ...message,
            contact_name: contactName
          }
        });
      }
    }
  }
  return result;
}
function resolveClientDisplayName(rawName) {
  if (!rawName) return null;
  const cleaned = rawName.replace(/\s+/g, " ").trim();
  if (!cleaned) return null;
  return cleaned.slice(0, 120);
}
function formatConversationForAI(history) {
  const lines = history.map((item)=>`${item.direction === "inbound" ? "Cliente" : "Assistente"}: ${item.message_text}`);
  return lines.join("\n");
}
function extractJsonObject(text) {
  const first = text.indexOf("{");
  if (first < 0) return null;
  let depth = 0;
  for(let i = first; i < text.length; i += 1){
    const ch = text[i];
    if (ch === "{") depth += 1;
    if (ch === "}") {
      depth -= 1;
      if (depth === 0) return text.slice(first, i + 1);
    }
  }
  return null;
}
function extractResponseText(payload) {
  if (!payload || typeof payload !== "object") return "";
  const data = payload;
  if (typeof data.output_text === "string" && data.output_text.trim()) {
    return data.output_text.trim();
  }
  const output = Array.isArray(data.output) ? data.output : [];
  const parts = [];
  for (const item of output){
    if (!item || typeof item !== "object") continue;
    const content = Array.isArray(item.content) ? item.content : [];
    for (const block of content){
      if (!block || typeof block !== "object") continue;
      const blockRecord = block;
      const textValue = blockRecord.text;
      if (typeof textValue === "string" && textValue.trim()) {
        parts.push(textValue.trim());
      }
    }
  }
  return parts.join("\n").trim();
}
function toIsoOrNull(value) {
  if (typeof value !== "string" || !value.trim()) return null;
  const dt = new Date(value);
  if (Number.isNaN(dt.getTime())) return null;
  return dt.toISOString();
}
function toNullableString(value) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  const normalized = normalizeText(trimmed);
  if (normalized === "null" || normalized === "undefined" || normalized === "nenhum" || normalized === "none") {
    return null;
  }
  return trimmed;
}
function buildServicesReply(catalog, shouldGreet) {
  if (catalog.services.length === 0) {
    const prefix = shouldGreet ? "Olá! " : "";
    return `${prefix}No momento não encontrei serviços cadastrados. Pode me dizer qual atendimento você deseja para eu confirmar aqui?`;
  }
  const top = catalog.services.slice(0, 8);
  const lines = top.map((item, index)=>`${index + 1}) ${item.name} (${item.duration_min} min)`);
  const more = catalog.services.length > top.length ? "\nSe quiser, envio mais opções." : "";
  const prefix = shouldGreet ? "Olá! " : "";
  return `${prefix}Claro! Estes são os serviços disponíveis:\n${lines.join("\n")}${more}\nQual deles você quer agendar e para quando?`;
}
function buildCollectInfoReply(rawText, catalog, shouldGreet) {
  const normalized = normalizeText(rawText);
  const asksServices = normalized.includes("quais servicos") || normalized.includes("quais servico") || normalized.includes("servicos voces tem") || normalized.includes("servico voces tem") || normalized.includes("lista de servicos") || normalized.includes("servico");
  if (asksServices) {
    return buildServicesReply(catalog, shouldGreet);
  }
  const isGreeting = normalized === "oi" || normalized === "ola" || normalized === "bom dia" || normalized === "boa tarde" || normalized === "boa noite";
  if (isGreeting) {
    return "Para eu te ajudar com o agendamento, me diga qual serviço você procura e sua preferência de dia/horário.";
  }
  const prefix = shouldGreet ? "Olá! " : "";
  return `${prefix}Perfeito. Me diga o serviço desejado e sua preferência de dia e horário para eu te enviar as melhores opções.`;
}
function looksLikeRescheduleRequest(rawText) {
  const normalized = normalizeText(rawText);
  if (!normalized) return false;
  return normalized.includes("remarcar") || normalized.includes("remarcacao") || normalized.includes("remarcacao") || normalized.includes("alterar meu horario") || normalized.includes("alterar horario") || normalized.includes("alterar minha consulta") || normalized.includes("alterar a minha consulta") || normalized.includes("alterar consulta") || normalized.includes("alterar meu agendamento") || normalized.includes("alterar meu horario") || normalized.includes("alterar agendamento") || normalized.includes("mudar consulta") || normalized.includes("trocar consulta") || normalized.includes("mudar agendamento") || normalized.includes("trocar agendamento") || normalized.includes("mudar horario") || normalized.includes("trocar horario");
}
function looksLikeCancelRequest(rawText) {
  const normalized = normalizeText(rawText);
  if (!normalized) return false;
  return normalized.includes("cancelar") || normalized.includes("cancele") || normalized.includes("cancelamento") || normalized.includes("desmarcar") || normalized.includes("desmarque");
}
function looksLikeCancelAllRequest(rawText) {
  const normalized = normalizeText(rawText);
  if (!normalized) return false;
  const hasCancelVerb = normalized.includes("cancelar") || normalized.includes("cancele") || normalized.includes("desmarcar") || normalized.includes("desmarque");
  const hasAllWord = normalized.includes("todas") || normalized.includes("todos") || normalized.includes("tudo");
  return hasCancelVerb && hasAllWord;
}
function looksLikeAfterMyAppointmentRequest(rawText) {
  const normalized = normalizeText(rawText);
  if (!normalized) return false;
  return normalized.includes("logo apos a minha") || normalized.includes("logo apos da minha") || normalized.includes("apos a minha") || normalized.includes("depois da minha") || normalized.includes("depois da minha consulta") || normalized.includes("depois do meu horario") || normalized.includes("apos meu horario");
}
function shouldPreserveAiCollectReply(decision) {
  const reply = (decision.reply_text ?? "").trim();
  if (!reply) return false;
  if (decision.confidence < 0.6) return false;
  const normalized = normalizeText(reply);
  const asksToConfirm = normalized.includes("confirm") || normalized.includes("corr") || normalized.includes("quis dizer") || normalized.includes("ano") || normalized.includes("data");
  const hasDatePattern = /\d{1,2}\/\d{1,2}\/\d{2,4}/.test(reply);
  return asksToConfirm || hasDatePattern;
}
function parseIntentDecision(raw) {
  if (!raw || typeof raw !== "object") return null;
  const item = raw;
  const intent = item.intent;
  if (intent !== "collect_info" && intent !== "create_appointment" && intent !== "reschedule_appointment") {
    return null;
  }
  const confidenceRaw = Number(item.confidence ?? 0);
  const confidence = Number.isFinite(confidenceRaw) ? Math.min(Math.max(confidenceRaw, 0), 1) : 0;
  return {
    intent,
    confidence,
    reply_text: toNullableString(item.reply_text) ?? "Perfeito. Pode me dizer o serviço e o horário que você prefere?",
    service_id: toNullableString(item.service_id),
    service_name: toNullableString(item.service_name),
    professional_id: toNullableString(item.professional_id),
    professional_name: toNullableString(item.professional_name),
    starts_at_iso: toIsoOrNull(item.starts_at_iso),
    ends_at_iso: toIsoOrNull(item.ends_at_iso),
    duration_min: Number.isFinite(Number(item.duration_min)) ? Number(item.duration_min) : null,
    any_available: Boolean(item.any_available),
    target_appointment_id: toNullableString(item.target_appointment_id)
  };
}
async function loadTenantCatalog(admin, tenantId) {
  const [{ data: servicesRows }, { data: professionalsRows }, { data: linksRows }] = await Promise.all([
    admin.from("services").select("id, name, duration_min, interval_min, specialty_id").eq("tenant_id", tenantId).eq("active", true),
    admin.from("professionals").select("id, name").eq("tenant_id", tenantId).eq("active", true),
    admin.from("professional_services").select("professional_id, service_id").eq("tenant_id", tenantId)
  ]);
  return {
    services: servicesRows ?? [],
    professionals: professionalsRows ?? [],
    links: linksRows ?? []
  };
}
async function loadAvailabilityContext(admin, tenantId, professionalIds) {
  const [scheduleResult, unavailabilityResult, appointmentsResult] = await Promise.all([
    admin.from("professional_schedule_settings").select("professional_id, timezone, workdays, work_hours").eq("tenant_id", tenantId),
    admin.from("professional_unavailability").select("professional_id, starts_at, ends_at, reason, share_reason_with_client").eq("tenant_id", tenantId),
    professionalIds.length > 0 ? admin.from("appointments").select("professional_id, starts_at, ends_at, status").eq("tenant_id", tenantId).in("professional_id", professionalIds).in("status", ACTIVE_APPOINTMENT_STATUSES).lt("starts_at", new Date(Date.now() + 21 * 24 * 60 * 60 * 1000).toISOString()) : Promise.resolve({
      data: [],
      error: null
    })
  ]);
  const scheduleByProfessional = new Map();
  for (const row of scheduleResult.data ?? []){
    scheduleByProfessional.set(row.professional_id, row);
  }
  const unavailabilityByProfessional = new Map();
  for (const row of unavailabilityResult.data ?? []){
    if (!unavailabilityByProfessional.has(row.professional_id)) {
      unavailabilityByProfessional.set(row.professional_id, []);
    }
    unavailabilityByProfessional.get(row.professional_id)?.push(row);
  }
  const appointmentsByProfessional = new Map();
  const appointmentRows = appointmentsResult.data ?? [];
  for (const row of appointmentRows){
    if (row.status && !ACTIVE_APPOINTMENT_STATUSES_SET.has(row.status)) continue;
    if (!appointmentsByProfessional.has(row.professional_id)) {
      appointmentsByProfessional.set(row.professional_id, []);
    }
    appointmentsByProfessional.get(row.professional_id)?.push({
      professional_id: row.professional_id,
      starts_at: row.starts_at,
      ends_at: row.ends_at
    });
  }
  return {
    scheduleByProfessional,
    unavailabilityByProfessional,
    appointmentsByProfessional
  };
}
function isProfessionalSlotAvailable(availability, professionalId, startsAtIso, endsAtIso) {
  const schedule = availability.scheduleByProfessional.get(professionalId);
  if (!isWithinSchedule(schedule, startsAtIso, endsAtIso)) return false;
  if (hasUnavailabilityOverlap(availability.unavailabilityByProfessional.get(professionalId), startsAtIso, endsAtIso)) {
    return false;
  }
  if (hasAppointmentOverlapInMemory(availability.appointmentsByProfessional.get(professionalId), startsAtIso, endsAtIso)) {
    return false;
  }
  return true;
}
function resolveService(catalog, decision) {
  if (decision.service_id) {
    const byId = catalog.services.find((item)=>item.id === decision.service_id);
    if (byId) return byId;
  }
  if (!decision.service_name) return null;
  const query = normalizeText(decision.service_name);
  if (!query) return null;
  return catalog.services.find((item)=>normalizeText(item.name) === query) ?? catalog.services.find((item)=>normalizeText(item.name).includes(query) || query.includes(normalizeText(item.name))) ?? null;
}
function resolveProfessional(catalog, decision) {
  if (decision.professional_id) {
    const byId = catalog.professionals.find((item)=>item.id === decision.professional_id);
    if (byId) return byId;
  }
  if (!decision.professional_name) return null;
  const query = normalizeText(decision.professional_name);
  if (!query) return null;
  return catalog.professionals.find((item)=>normalizeText(item.name) === query) ?? catalog.professionals.find((item)=>normalizeText(item.name).includes(query) || query.includes(normalizeText(item.name))) ?? null;
}
async function hasAppointmentConflict(admin, tenantId, professionalId, startsAtIso, endsAtIso) {
  const { data } = await admin.from("appointments").select("id").eq("tenant_id", tenantId).eq("professional_id", professionalId).in("status", ACTIVE_APPOINTMENT_STATUSES).lt("starts_at", endsAtIso).gt("ends_at", startsAtIso).limit(1);
  return Boolean(data && data.length > 0);
}
async function chooseProfessional(admin, tenantId, catalog, serviceId, startsAtIso, endsAtIso, preferredProfessionalId, anyAvailable, availability) {
  const linkedIds = new Set(catalog.links.filter((link)=>link.service_id === serviceId).map((link)=>link.professional_id));
  if (linkedIds.size === 0) return null;
  if (preferredProfessionalId && !anyAvailable) {
    if (!linkedIds.has(preferredProfessionalId)) return null;
    const preferred = catalog.professionals.find((item)=>item.id === preferredProfessionalId) ?? null;
    if (!preferred) return null;
    const conflict = availability ? !isProfessionalSlotAvailable(availability, preferred.id, startsAtIso, endsAtIso) : await hasAppointmentConflict(admin, tenantId, preferred.id, startsAtIso, endsAtIso);
    return conflict ? null : preferred;
  }
  const candidates = catalog.professionals.filter((professional)=>linkedIds.has(professional.id));
  for (const candidate of candidates){
    const conflict = availability ? !isProfessionalSlotAvailable(availability, candidate.id, startsAtIso, endsAtIso) : await hasAppointmentConflict(admin, tenantId, candidate.id, startsAtIso, endsAtIso);
    if (!conflict) return candidate;
  }
  return null;
}
function formatDateTimePtBr(iso) {
  const dt = new Date(iso);
  const dd = String(dt.getDate()).padStart(2, "0");
  const mm = String(dt.getMonth() + 1).padStart(2, "0");
  const yyyy = dt.getFullYear();
  const hh = String(dt.getHours()).padStart(2, "0");
  const min = String(dt.getMinutes()).padStart(2, "0");
  return `${dd}/${mm}/${yyyy} ${hh}:${min}`;
}
function formatDateTimePtBrInTimezone(iso, timezone) {
  const dt = new Date(iso);
  return new Intl.DateTimeFormat("pt-BR", {
    timeZone: timezone,
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit"
  }).format(dt);
}
function looksLikeSameTimeRequest(rawText) {
  const normalized = normalizeText(rawText);
  if (!normalized) return false;
  return normalized.includes("mesmo horario") || normalized.includes("mesmo horário") || normalized.includes("no mesmo horario") || normalized.includes("no mesmo horário");
}
function mergeDateWithReferenceTimeInTimezone(dateIso, referenceTimeIso, timezone) {
  const date = new Date(dateIso);
  const reference = new Date(referenceTimeIso);
  if (Number.isNaN(date.getTime()) || Number.isNaN(reference.getTime())) return null;
  const dayParts = getDateTimePartsInTimezone(date, timezone);
  const refParts = getDateTimePartsInTimezone(reference, timezone);
  if (!Number.isFinite(dayParts.year) || !Number.isFinite(dayParts.month) || !Number.isFinite(dayParts.day) || !Number.isFinite(refParts.hour) || !Number.isFinite(refParts.minute)) {
    return null;
  }
  const yyyy = String(dayParts.year).padStart(4, "0");
  const mm = String(dayParts.month).padStart(2, "0");
  const dd = String(dayParts.day).padStart(2, "0");
  const hh = String(refParts.hour).padStart(2, "0");
  const mi = String(refParts.minute).padStart(2, "0");
  return localDateTimeInTimezoneToIso(`${yyyy}-${mm}-${dd}T${hh}:${mi}`, timezone);
}
function mergeDateWithTimeInTimezone(dateIso, hour, minute, timezone) {
  const date = new Date(dateIso);
  if (Number.isNaN(date.getTime())) return null;
  if (!Number.isFinite(hour) || !Number.isFinite(minute)) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  const dayParts = getDateTimePartsInTimezone(date, timezone);
  if (!Number.isFinite(dayParts.year) || !Number.isFinite(dayParts.month) || !Number.isFinite(dayParts.day)) {
    return null;
  }
  const yyyy = String(dayParts.year).padStart(4, "0");
  const mm = String(dayParts.month).padStart(2, "0");
  const dd = String(dayParts.day).padStart(2, "0");
  const hh = String(hour).padStart(2, "0");
  const mi = String(minute).padStart(2, "0");
  return localDateTimeInTimezoneToIso(`${yyyy}-${mm}-${dd}T${hh}:${mi}`, timezone);
}
function getDateTimePartsInTimezone(date, timezone) {
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false
  });
  const parts = formatter.formatToParts(date);
  const map = {};
  for (const part of parts){
    if (part.type !== "literal") map[part.type] = part.value;
  }
  return {
    year: Number.parseInt(map.year, 10),
    month: Number.parseInt(map.month, 10),
    day: Number.parseInt(map.day, 10),
    hour: Number.parseInt(map.hour, 10),
    minute: Number.parseInt(map.minute, 10),
    second: Number.parseInt(map.second, 10)
  };
}
function getTimezoneOffsetMs(date, timezone) {
  const parts = getDateTimePartsInTimezone(date, timezone);
  const asUtc = Date.UTC(parts.year, parts.month - 1, parts.day, parts.hour, parts.minute, parts.second);
  return asUtc - date.getTime();
}
function localDateTimeInTimezoneToIso(localValue, timezone) {
  const match = localValue.match(/^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?$/);
  if (!match) return null;
  const [, y, m, d, hh, mm, ss = "00"] = match;
  const year = Number.parseInt(y, 10);
  const month = Number.parseInt(m, 10);
  const day = Number.parseInt(d, 10);
  const hour = Number.parseInt(hh, 10);
  const minute = Number.parseInt(mm, 10);
  const second = Number.parseInt(ss, 10);
  if (!Number.isFinite(year) || !Number.isFinite(month) || !Number.isFinite(day) || !Number.isFinite(hour) || !Number.isFinite(minute) || !Number.isFinite(second)) {
    return null;
  }
  const baseUtc = Date.UTC(year, month - 1, day, hour, minute, second);
  let utcMs = baseUtc - getTimezoneOffsetMs(new Date(baseUtc), timezone);
  utcMs = baseUtc - getTimezoneOffsetMs(new Date(utcMs), timezone);
  return new Date(utcMs).toISOString();
}
function reinterpretIsoAsLocalTimezone(isoValue, timezone) {
  const dt = new Date(isoValue);
  if (Number.isNaN(dt.getTime())) return null;
  const y = dt.getUTCFullYear();
  const m = String(dt.getUTCMonth() + 1).padStart(2, "0");
  const d = String(dt.getUTCDate()).padStart(2, "0");
  const hh = String(dt.getUTCHours()).padStart(2, "0");
  const mm = String(dt.getUTCMinutes()).padStart(2, "0");
  return localDateTimeInTimezoneToIso(`${y}-${m}-${d} ${hh}:${mm}:00`, timezone);
}
function roundUpToNextStep(date, stepMinutes) {
  const stepMs = stepMinutes * 60_000;
  const roundedMs = Math.ceil(date.getTime() / stepMs) * stepMs;
  return new Date(roundedMs);
}
function parseSelectedOptionIndex(rawText) {
  const normalized = normalizeText(rawText);
  if (!normalized) return null;
  const strictSingle = normalized.match(/^([1-9])$/);
  if (strictSingle) return Number(strictSingle[1]);
  const hasOptionKeyword = /(opcao|opção|numero|número|item)/.test(normalized);
  const keywordNumber = normalized.match(/(?:opcao|opção|numero|número|item)\s*([1-9])/);
  if (hasOptionKeyword && keywordNumber) {
    return Number(keywordNumber[1]);
  }
  if (normalized.length <= 24) {
    const loose = normalized.match(/\b([1-9])\b/);
    if (loose) return Number(loose[1]);
  }
  return null;
}
function looksLikeAffirmativeContinuation(rawText) {
  const normalized = normalizeText(rawText);
  if (!normalized) return false;
  return normalized === "sim" || normalized === "ss" || normalized === "ok" || normalized === "pode" || normalized === "pode sim" || normalized === "claro" || normalized === "isso" || normalized === "pode ser" || normalized.includes("sim pode") || normalized.includes("pode buscar") || normalized.includes("pode procurar");
}
function detectPeriodPreference(rawText) {
  const normalized = normalizeText(rawText);
  if (!normalized) return null;
  if (normalized.includes("fim do dia") || normalized.includes("final do dia") || normalized.includes("fim da tarde") || normalized.includes("final da tarde") || normalized.includes("fim de tarde") || normalized.includes("fim do expediente") || normalized.includes("mais para o fim do dia")) {
    return "late_day";
  }
  if (normalized.includes("manha") || normalized.includes("manhã") || normalized.includes("de manha") || normalized.includes("de manhã")) {
    return "morning";
  }
  if (normalized.includes("tarde")) {
    return "afternoon";
  }
  if (normalized.includes("noite") || normalized.includes("noturno") || normalized.includes("noturna")) {
    return "evening";
  }
  return null;
}
function detectRelativeDayPreference(rawText) {
  const normalized = normalizeText(rawText);
  if (!normalized) return null;
  if (normalized.includes("amanha") || normalized.includes("amanhã")) return "tomorrow";
  if (normalized.includes("hoje")) return "today";
  return null;
}
function hasExplicitDateInText(rawText) {
  const normalized = normalizeText(rawText);
  if (!normalized) return false;
  if (/\b\d{1,2}[\/-]\d{1,2}(?:[\/-]\d{2,4})?\b/.test(normalized)) return true;
  if (/\b\d{4}[\/-]\d{1,2}[\/-]\d{1,2}\b/.test(normalized)) return true;
  if (/\bdia\s+\d{1,2}\b/.test(normalized)) return true;
  if (/\bdi\s+\d{1,2}\b/.test(normalized)) return true;
  if (/\b\d{1,2}\s+de\s+[a-zç]+\b/.test(normalized)) return true;
  return false;
}
function extractExplicitTimeInText(rawText) {
  const normalized = normalizeText(rawText);
  if (!normalized) return null;
  const hourMinute = normalized.match(/\b([01]?\d|2[0-3])\s*[:h]\s*([0-5]\d)\b/);
  if (hourMinute) {
    return {
      hour: Number.parseInt(hourMinute[1], 10),
      minute: Number.parseInt(hourMinute[2], 10)
    };
  }
  const hourOnlyWithH = normalized.match(/\b([01]?\d|2[0-3])\s*h(?:s)?\b/);
  if (hourOnlyWithH) {
    return {
      hour: Number.parseInt(hourOnlyWithH[1], 10),
      minute: 0
    };
  }
  const hourOnlyWithWords = normalized.match(/\b([01]?\d|2[0-3])\s*horas?\b/);
  if (hourOnlyWithWords) {
    return {
      hour: Number.parseInt(hourOnlyWithWords[1], 10),
      minute: 0
    };
  }
  const hourOnlyWithAs = normalized.match(/\bas\s+([01]?\d|2[0-3])\b/);
  if (hourOnlyWithAs) {
    return {
      hour: Number.parseInt(hourOnlyWithAs[1], 10),
      minute: 0
    };
  }
  return null;
}
function extractExplicitDateIsoInTimezone(rawText, timezone) {
  const normalized = normalizeText(rawText);
  if (!normalized) return null;
  const nowParts = getDateTimePartsInTimezone(new Date(), timezone);
  let year = nowParts.year;
  let month = nowParts.month;
  let day = null;
  const dateSlash = normalized.match(/\b(\d{1,2})[\/-](\d{1,2})(?:[\/-](\d{2,4}))?\b/);
  if (dateSlash) {
    day = Number.parseInt(dateSlash[1], 10);
    month = Number.parseInt(dateSlash[2], 10);
    if (dateSlash[3]) {
      const yy = Number.parseInt(dateSlash[3], 10);
      year = yy < 100 ? 2000 + yy : yy;
    }
  } else {
    const dayOnly = normalized.match(/\b(?:dia|di)\s+(\d{1,2})\b/);
    if (dayOnly) {
      day = Number.parseInt(dayOnly[1], 10);
    }
  }
  if (!day || day < 1 || day > 31 || month < 1 || month > 12) return null;
  // If the user says only day number and it's already passed in current month, roll to next month.
  if (!dateSlash && day < nowParts.day) {
    month += 1;
    if (month > 12) {
      month = 1;
      year += 1;
    }
  }
  const yyyy = String(year).padStart(4, "0");
  const mm = String(month).padStart(2, "0");
  const dd = String(day).padStart(2, "0");
  return localDateTimeInTimezoneToIso(`${yyyy}-${mm}-${dd}T09:00`, timezone);
}
function detectWeekdayPreference(rawText) {
  const normalized = normalizeText(rawText);
  if (!normalized) return null;
  if (/\b(dom|domingo)\b/.test(normalized)) return 0;
  if (/\b(seg|segunda|segunda-feira)\b/.test(normalized)) return 1;
  if (/\b(ter|terca|terca-feira)\b/.test(normalized)) return 2;
  if (/\b(qua|quarta|quarta-feira)\b/.test(normalized)) return 3;
  if (/\b(qui|quinta|quinta-feira)\b/.test(normalized)) return 4;
  if (/\b(sex|sexta|sexta-feira)\b/.test(normalized)) return 5;
  if (/\b(sab|sabado)\b/.test(normalized)) return 6;
  return null;
}
function isWithinPreferredPeriod(isoValue, timezone, period) {
  if (!period) return true;
  const date = new Date(isoValue);
  if (Number.isNaN(date.getTime())) return false;
  const parts = getDateTimePartsInTimezone(date, timezone);
  if (!Number.isFinite(parts.hour)) return false;
  const hour = parts.hour;
  if (period === "morning") return hour >= 5 && hour < 12;
  if (period === "afternoon") return hour >= 12 && hour < 18;
  if (period === "evening") return hour >= 18 && hour <= 23;
  if (period === "late_day") return hour >= 16 && hour <= 23;
  return true;
}
function isPreferredAlternativePeriod(isoValue, timezone, requested) {
  if (!requested) return true;
  const date = new Date(isoValue);
  if (Number.isNaN(date.getTime())) return false;
  const parts = getDateTimePartsInTimezone(date, timezone);
  if (!Number.isFinite(parts.hour)) return false;
  const hour = parts.hour;
  // Avoid suggesting "morning" as first alternative for end-of-day requests.
  if (requested === "late_day" || requested === "evening") {
    return hour >= 12;
  }
  // For afternoon requests, keep options outside afternoon but avoid very early morning first.
  if (requested === "afternoon") {
    return hour >= 9;
  }
  // For morning requests, afternoon/evening are acceptable alternatives.
  if (requested === "morning") {
    return hour >= 12;
  }
  return true;
}
function isWithinRelativeDay(isoValue, timezone, day) {
  if (!day) return true;
  const slotDate = new Date(isoValue);
  if (Number.isNaN(slotDate.getTime())) return false;
  const now = new Date();
  const nowParts = getDateTimePartsInTimezone(now, timezone);
  const slotParts = getDateTimePartsInTimezone(slotDate, timezone);
  if (!Number.isFinite(nowParts.year) || !Number.isFinite(nowParts.month) || !Number.isFinite(nowParts.day) || !Number.isFinite(slotParts.year) || !Number.isFinite(slotParts.month) || !Number.isFinite(slotParts.day)) {
    return false;
  }
  const nowLocalDateMs = Date.UTC(nowParts.year, nowParts.month - 1, nowParts.day);
  const slotLocalDateMs = Date.UTC(slotParts.year, slotParts.month - 1, slotParts.day);
  const diffDays = Math.round((slotLocalDateMs - nowLocalDateMs) / (24 * 60 * 60 * 1000));
  if (day === "today") return diffDays === 0;
  if (day === "tomorrow") return diffDays === 1;
  return true;
}
function isSameLocalDayInTimezone(isoA, isoB, timezone) {
  const dateA = new Date(isoA);
  const dateB = new Date(isoB);
  if (Number.isNaN(dateA.getTime()) || Number.isNaN(dateB.getTime())) return false;
  const a = getDateTimePartsInTimezone(dateA, timezone);
  const b = getDateTimePartsInTimezone(dateB, timezone);
  return a.year === b.year && a.month === b.month && a.day === b.day;
}
function isOnOrAfterLocalDayInTimezone(isoValue, anchorIso, timezone) {
  const date = new Date(isoValue);
  const anchorDate = new Date(anchorIso);
  if (Number.isNaN(date.getTime()) || Number.isNaN(anchorDate.getTime())) return false;
  const valueParts = getDateTimePartsInTimezone(date, timezone);
  const anchorParts = getDateTimePartsInTimezone(anchorDate, timezone);
  const valueDay = Date.UTC(valueParts.year, valueParts.month - 1, valueParts.day);
  const anchorDay = Date.UTC(anchorParts.year, anchorParts.month - 1, anchorParts.day);
  return valueDay >= anchorDay;
}
function isWeekdayInTimezone(isoValue, timezone, weekday) {
  if (weekday === null) return true;
  const parts = getWeekdayAndMinutesInTimezone(isoValue, timezone);
  if (!parts) return false;
  return parts.weekday === weekday;
}
function normalizeOutgoingPortuguese(text) {
  if (!text) return text;
  return text.replaceAll("OlÃ¡", "Olá").replaceAll("olÃ¡", "olá").replaceAll("VocÃª", "Você").replaceAll("vocÃª", "você").replaceAll("NÃ£o", "Não").replaceAll("nÃ£o", "não").replaceAll("horÃ¡rio", "horário").replaceAll("horÃ¡rios", "horários").replaceAll("disponÃ­vel", "disponível").replaceAll("disponÃ­veis", "disponíveis").replaceAll("opÃ§Ã£o", "opção").replaceAll("opÃ§Ãµes", "opções").replaceAll("preferÃªncia", "preferência").replaceAll("prÃ³xima", "próxima").replaceAll("prÃ³ximas", "próximas").replaceAll("perÃ­odo", "período").replaceAll("perÃ­odos", "períodos").replaceAll("serviÃ§o", "serviço").replaceAll("serviÃ§os", "serviços").replaceAll("manhÃ£", "manhã").replaceAll("Ã ", "à");
}
async function loadLatestSuggestedOptions(admin, tenantId, conversationId) {
  const { data } = await admin.from("whatsapp_messages").select("ai_payload").eq("tenant_id", tenantId).eq("conversation_id", conversationId).eq("direction", "outbound").order("created_at", {
    ascending: false
  }).limit(6);
  const rows = data ?? [];
  for (const row of rows){
    const payload = row.ai_payload;
    if (!payload || typeof payload !== "object" || Array.isArray(payload)) continue;
    const suggested = payload.suggested_options;
    if (!Array.isArray(suggested) || suggested.length === 0) continue;
    const parsed = suggested.map((item)=>{
      if (!item || typeof item !== "object" || Array.isArray(item)) return null;
      const value = item;
      const optionIndex = Number(value.option_index);
      const serviceId = toNullableString(value.service_id);
      const serviceName = toNullableString(value.service_name);
      const professionalId = toNullableString(value.professional_id);
      const professionalName = toNullableString(value.professional_name);
      const startsAtIso = toIsoOrNull(value.starts_at_iso);
      const endsAtIso = toIsoOrNull(value.ends_at_iso);
      if (!Number.isInteger(optionIndex) || optionIndex <= 0 || !serviceId || !serviceName || !professionalId || !professionalName || !startsAtIso || !endsAtIso) {
        return null;
      }
      return {
        option_index: optionIndex,
        service_id: serviceId,
        service_name: serviceName,
        professional_id: professionalId,
        professional_name: professionalName,
        starts_at_iso: startsAtIso,
        ends_at_iso: endsAtIso
      };
    }).filter((item)=>item !== null);
    if (parsed.length > 0) return parsed;
  }
  return [];
}
async function loadLatestCancellationOptions(admin, tenantId, conversationId) {
  const { data } = await admin.from("whatsapp_messages").select("ai_payload").eq("tenant_id", tenantId).eq("conversation_id", conversationId).eq("direction", "outbound").order("created_at", {
    ascending: false
  }).limit(6);
  const rows = data ?? [];
  for (const row of rows){
    const payload = row.ai_payload;
    if (!payload || typeof payload !== "object" || Array.isArray(payload)) continue;
    const options = payload.cancellation_options;
    if (!Array.isArray(options) || options.length === 0) continue;
    const parsed = options.map((item)=>{
      if (!item || typeof item !== "object" || Array.isArray(item)) return null;
      const value = item;
      const optionIndex = Number(value.option_index);
      const appointmentId = toNullableString(value.appointment_id);
      const serviceName = toNullableString(value.service_name);
      const professionalName = toNullableString(value.professional_name);
      const startsAtIso = toIsoOrNull(value.starts_at_iso);
      if (!Number.isInteger(optionIndex) || optionIndex <= 0 || !appointmentId || !serviceName || !professionalName || !startsAtIso) {
        return null;
      }
      return {
        option_index: optionIndex,
        appointment_id: appointmentId,
        service_id: toNullableString(value.service_id),
        service_name: serviceName,
        professional_id: toNullableString(value.professional_id),
        professional_name: professionalName,
        starts_at_iso: startsAtIso
      };
    }).filter((item)=>item !== null);
    if (parsed.length > 0) return parsed;
  }
  return [];
}
async function inferRescheduleContext(admin, tenantId, clientId, catalog) {
  const { data } = await admin.from("appointments").select("id, service_id, professional_id, starts_at, ends_at").eq("tenant_id", tenantId).eq("client_id", clientId).in("status", ACTIVE_APPOINTMENT_STATUSES).gte("starts_at", new Date().toISOString()).order("starts_at", {
    ascending: true
  }).limit(1).maybeSingle();
  if (!data) return null;
  const row = data;
  const service = row.service_id ? catalog.services.find((item)=>item.id === row.service_id) ?? null : null;
  const professional = row.professional_id ? catalog.professionals.find((item)=>item.id === row.professional_id) ?? null : null;
  return {
    appointmentId: row.id,
    startsAtIso: row.starts_at,
    endsAtIso: row.ends_at,
    service,
    professional
  };
}
async function inferAfterMyAppointmentContext(admin, tenantId, clientId, catalog, rawText, preferredStartsAtIso) {
  const { data } = await admin.from("appointments").select("id, service_id, professional_id, starts_at, ends_at").eq("tenant_id", tenantId).eq("client_id", clientId).in("status", ACTIVE_APPOINTMENT_STATUSES).gte("starts_at", new Date().toISOString()).order("starts_at", {
    ascending: true
  }).limit(10);
  const rows = data ?? [];
  if (rows.length === 0) return null;
  const normalizedText = normalizeText(rawText);
  const matching = rows.filter((row)=>{
    if (!row.service_id) return false;
    const service = catalog.services.find((item)=>item.id === row.service_id);
    if (!service) return false;
    return normalizedText.includes(normalizeText(service.name));
  });
  const pool = matching.length > 0 ? matching : rows;
  const timezone = "America/Sao_Paulo";
  const sameDayPool = preferredStartsAtIso ? pool.filter((row)=>isSameLocalDayInTimezone(row.starts_at, preferredStartsAtIso, timezone)) : [];
  const selectionPool = sameDayPool.length > 0 ? sameDayPool : pool;
  let selected = selectionPool[0];
  if (preferredStartsAtIso) {
    let bestDiff = Number.POSITIVE_INFINITY;
    const preferredMs = new Date(preferredStartsAtIso).getTime();
    for (const row of selectionPool){
      const rowMs = new Date(row.starts_at).getTime();
      if (!Number.isFinite(rowMs) || !Number.isFinite(preferredMs)) continue;
      const diff = Math.abs(rowMs - preferredMs);
      if (diff < bestDiff) {
        bestDiff = diff;
        selected = row;
      }
    }
  }
  const service = selected.service_id ? catalog.services.find((item)=>item.id === selected.service_id) ?? null : null;
  const professional = selected.professional_id ? catalog.professionals.find((item)=>item.id === selected.professional_id) ?? null : null;
  return {
    appointmentId: selected.id,
    startsAtIso: selected.starts_at,
    endsAtIso: selected.ends_at,
    service,
    professional
  };
}
async function inferConversationAnchorStartsAtIso(admin, tenantId, conversationId) {
  const { data } = await admin.from("whatsapp_messages").select("ai_payload").eq("tenant_id", tenantId).eq("conversation_id", conversationId).eq("direction", "outbound").order("created_at", {
    ascending: false
  }).limit(10);
  const rows = data ?? [];
  for (const row of rows){
    const payload = row.ai_payload;
    if (!payload || typeof payload !== "object" || Array.isArray(payload)) continue;
    const rec = payload;
    const decision = rec.decision;
    if (decision && typeof decision === "object" && !Array.isArray(decision)) {
      const decisionStarts = toIsoOrNull(decision.starts_at_iso);
      if (decisionStarts) return decisionStarts;
    }
    const action = rec.action_result;
    if (action && typeof action === "object" && !Array.isArray(action)) {
      const actionStarts = toIsoOrNull(action.startsAtIso);
      if (actionStarts) return actionStarts;
    }
  }
  return null;
}
async function inferRecentDecisionContext(admin, tenantId, conversationId, catalog) {
  const { data } = await admin.from("whatsapp_messages").select("ai_payload").eq("tenant_id", tenantId).eq("conversation_id", conversationId).eq("direction", "outbound").order("created_at", {
    ascending: false
  }).limit(8);
  const rows = data ?? [];
  for (const row of rows){
    const payload = row.ai_payload;
    if (!payload || typeof payload !== "object" || Array.isArray(payload)) continue;
    const decision = payload.decision;
    if (!decision || typeof decision !== "object" || Array.isArray(decision)) continue;
    const rec = decision;
    const serviceId = toNullableString(rec.service_id);
    const professionalId = toNullableString(rec.professional_id);
    const service = serviceId ? catalog.services.find((item)=>item.id === serviceId) ?? null : null;
    const professional = professionalId ? catalog.professionals.find((item)=>item.id === professionalId) ?? null : null;
    if (service || professional) {
      return {
        service,
        professional
      };
    }
  }
  return null;
}
async function inferPendingNextOptionContext(admin, tenantId, conversationId, catalog) {
  const { data } = await admin.from("whatsapp_messages").select("message_text, ai_payload").eq("tenant_id", tenantId).eq("conversation_id", conversationId).eq("direction", "outbound").order("created_at", {
    ascending: false
  }).limit(6);
  const rows = data ?? [];
  for (const row of rows){
    const messageText = normalizeText(row.message_text ?? "");
    const payload = row.ai_payload;
    if (!payload || typeof payload !== "object" || Array.isArray(payload)) continue;
    const rec = payload;
    const decisionRaw = rec.decision;
    const actionRaw = rec.action_result;
    if (!decisionRaw || typeof decisionRaw !== "object" || Array.isArray(decisionRaw)) continue;
    if (!actionRaw || typeof actionRaw !== "object" || Array.isArray(actionRaw)) continue;
    const decision = decisionRaw;
    const action = actionRaw;
    const actionOk = action.ok === true;
    if (actionOk) continue;
    const actionMessage = normalizeText(toNullableString(action.message) ?? "");
    const asksNextOption = messageText.includes("posso buscar a proxima opcao") || actionMessage.includes("posso buscar a proxima opcao");
    if (!asksNextOption) continue;
    const serviceId = toNullableString(decision.service_id);
    if (!serviceId) continue;
    const service = catalog.services.find((item)=>item.id === serviceId) ?? null;
    if (!service) continue;
    const professionalId = toNullableString(decision.professional_id);
    const professional = professionalId ? catalog.professionals.find((item)=>item.id === professionalId) ?? null : null;
    const targetAppointmentId = toNullableString(decision.target_appointment_id);
    const requestedStartsAtIso = toIsoOrNull(decision.starts_at_iso);
    let targetStartsAtIso = null;
    if (targetAppointmentId) {
      const { data: targetRow } = await admin.from("appointments").select("starts_at").eq("tenant_id", tenantId).eq("id", targetAppointmentId).limit(1).maybeSingle();
      targetStartsAtIso = toIsoOrNull(targetRow?.starts_at ?? null);
    }
    return {
      service,
      professional,
      anyAvailable: professional ? false : true,
      targetAppointmentId,
      requestedStartsAtIso,
      targetStartsAtIso
    };
  }
  return null;
}
async function findNextAvailabilityOptions(catalog, availability, service, preferredProfessionalId, anyAvailable, maxOptions = 3) {
  const linkedIds = new Set(catalog.links.filter((link)=>link.service_id === service.id).map((link)=>link.professional_id));
  if (linkedIds.size === 0) return [];
  const pool = catalog.professionals.filter((item)=>linkedIds.has(item.id));
  const candidates = preferredProfessionalId && !anyAvailable ? pool.filter((item)=>item.id === preferredProfessionalId) : pool;
  if (candidates.length === 0) return [];
  const durationMin = service.duration_min > 0 ? service.duration_min : 30;
  const intervalMin = service.interval_min >= 0 ? service.interval_min : 0;
  const blockMinutes = durationMin + intervalMin;
  const now = new Date();
  const cursorBase = roundUpToNextStep(new Date(now.getTime() + 30 * 60_000), 30);
  const options = [];
  const seen = new Set();
  for(let i = 0; i < 21 * 24 * 2 && options.length < maxOptions; i += 1){
    const startsAt = new Date(cursorBase.getTime() + i * 30 * 60_000);
    const endsAt = new Date(startsAt.getTime() + blockMinutes * 60_000);
    const startsAtIso = startsAt.toISOString();
    const endsAtIso = endsAt.toISOString();
    for (const professional of candidates){
      const available = isProfessionalSlotAvailable(availability, professional.id, startsAtIso, endsAtIso);
      if (!available) continue;
      const key = `${startsAtIso}-${professional.id}`;
      if (seen.has(key)) continue;
      seen.add(key);
      options.push({
        startsAtIso,
        endsAtIso,
        professional
      });
      if (!availability.appointmentsByProfessional.has(professional.id)) {
        availability.appointmentsByProfessional.set(professional.id, []);
      }
      availability.appointmentsByProfessional.get(professional.id)?.push({
        professional_id: professional.id,
        starts_at: startsAtIso,
        ends_at: endsAtIso
      });
      if (options.length >= maxOptions) break;
    }
  }
  return options;
}
async function createAppointmentFromDecision(admin, tenantId, clientId, catalog, decision, availability, options) {
  const service = resolveService(catalog, decision);
  if (!service) {
    return {
      ok: false,
      message: "Não consegui identificar o serviço. Pode me dizer exatamente qual serviço você quer agendar?"
    };
  }
  if (!decision.starts_at_iso) {
    return {
      ok: false,
      message: "Perfeito. Me diga a data e o horário desejados para eu confirmar seu agendamento."
    };
  }
  const startsAt = new Date(decision.starts_at_iso);
  if (Number.isNaN(startsAt.getTime())) {
    return {
      ok: false,
      message: "Não consegui entender o horário. Pode enviar novamente?"
    };
  }
  const durationMin = service.duration_min > 0 ? service.duration_min : 30;
  const intervalMin = service.interval_min >= 0 ? service.interval_min : 0;
  const preferredProfessional = resolveProfessional(catalog, decision);
  const defaultTimezone = (preferredProfessional && availability?.scheduleByProfessional.get(preferredProfessional.id)?.timezone) ?? "America/Sao_Paulo";
  const trySlots = [];
  const originalStartsAtIso = startsAt.toISOString();
  trySlots.push({
    startsAtIso: originalStartsAtIso,
    endsAtIso: new Date(startsAt.getTime() + (durationMin + intervalMin) * 60_000).toISOString()
  });
  if (!options?.disableTimezoneReinterpretation) {
    const reinterpretedStartsAtIso = reinterpretIsoAsLocalTimezone(originalStartsAtIso, defaultTimezone);
    if (reinterpretedStartsAtIso && reinterpretedStartsAtIso !== originalStartsAtIso) {
      const reinterpretedStartsAt = new Date(reinterpretedStartsAtIso);
      trySlots.push({
        startsAtIso: reinterpretedStartsAtIso,
        endsAtIso: new Date(reinterpretedStartsAt.getTime() + (durationMin + intervalMin) * 60_000).toISOString()
      });
    }
  }
  let selectedProfessional = null;
  let finalStartsAtIso = trySlots[0].startsAtIso;
  let finalEndsAtIso = trySlots[0].endsAtIso;
  for (const slot of trySlots){
    const candidate = await chooseProfessional(admin, tenantId, catalog, service.id, slot.startsAtIso, slot.endsAtIso, preferredProfessional?.id ?? null, decision.any_available || !preferredProfessional, availability);
    if (candidate) {
      selectedProfessional = candidate;
      finalStartsAtIso = slot.startsAtIso;
      finalEndsAtIso = slot.endsAtIso;
      break;
    }
  }
  if (!selectedProfessional) {
    if (preferredProfessional && availability) {
      const overlappingAbsence = findOverlappingUnavailability(availability.unavailabilityByProfessional.get(preferredProfessional.id), finalStartsAtIso, finalEndsAtIso);
      const reasonText = overlappingAbsence?.reason?.trim() ?? "";
      if (overlappingAbsence?.share_reason_with_client && reasonText) {
        return {
          ok: false,
          message: `Não encontrei ${preferredProfessional.name} nesse horário porque está ausente (${reasonText}). Posso buscar a próxima opção para você?`
        };
      }
    }
    return {
      ok: false,
      message: "Não encontrei profissional disponível nesse horário. Posso buscar a próxima opção para você?"
    };
  }
  const { data: inserted, error } = await admin.from("appointments").insert({
    tenant_id: tenantId,
    client_id: clientId,
    service_id: service.id,
    specialty_id: service.specialty_id,
    professional_id: selectedProfessional.id,
    starts_at: finalStartsAtIso,
    ends_at: finalEndsAtIso,
    status: "scheduled",
    source: "client_link",
    assigned_at: new Date().toISOString()
  }).select("id, starts_at").single();
  if (error || !inserted) {
    return {
      ok: false,
      message: "Não consegui confirmar agora. Pode tentar novamente em instantes?"
    };
  }
  const selectedTimezone = availability?.scheduleByProfessional.get(selectedProfessional.id)?.timezone ?? "America/Sao_Paulo";
  return {
    ok: true,
    message: `Agendamento confirmado para ${formatDateTimePtBrInTimezone(inserted.starts_at, selectedTimezone)} com ${selectedProfessional.name} (${service.name}).`,
    appointmentId: inserted.id,
    startsAtIso: inserted.starts_at,
    professionalName: selectedProfessional.name,
    serviceName: service.name
  };
}
async function rescheduleAppointmentFromDecision(admin, tenantId, clientId, catalog, decision, availability, rawText) {
  const hasExplicitTimeRequest = Boolean(extractExplicitTimeInText(rawText));
  const activeTargetQuery = admin.from("appointments").select("id, service_id, professional_id, starts_at, ends_at, status").eq("tenant_id", tenantId).eq("client_id", clientId).in("status", ACTIVE_APPOINTMENT_STATUSES).order("starts_at", {
    ascending: true
  }).limit(1);
  const { data: targetRows } = decision.target_appointment_id ? await activeTargetQuery.eq("id", decision.target_appointment_id) : await activeTargetQuery.gte("starts_at", new Date().toISOString());
  const target = targetRows?.[0];
  if (!target) {
    const { data: latestRows } = await admin.from("appointments").select("id, service_id, professional_id, starts_at, ends_at, status").eq("tenant_id", tenantId).eq("client_id", clientId).order("starts_at", {
      ascending: false
    }).limit(1);
    const latest = latestRows?.[0];
    if (!latest) {
      return {
        ok: false,
        message: "Não encontrei agendamento anterior para remarcar. Quer que eu crie um novo?"
      };
    }
    const inferredDecision = {
      ...decision,
      intent: "create_appointment",
      service_id: decision.service_id ?? latest.service_id ?? null,
      professional_id: decision.professional_id ?? latest.professional_id ?? null,
      any_available: decision.any_available || !decision.professional_id
    };
    const createdFromHistory = await createAppointmentFromDecision(admin, tenantId, clientId, catalog, inferredDecision, availability, {
      disableTimezoneReinterpretation: hasExplicitTimeRequest
    });
    if (createdFromHistory.ok) {
      return {
        ...createdFromHistory,
        message: `Não havia agendamento ativo para remarcar. Criei um novo: ${createdFromHistory.message}`
      };
    }
    return createdFromHistory;
  }
  const enrichedDecision = {
    ...decision,
    service_id: decision.service_id ?? target.service_id,
    professional_id: decision.professional_id ?? target.professional_id,
    any_available: decision.any_available || !decision.professional_id
  };
  const decisionForReschedule = {
    ...enrichedDecision
  };
  const timezone = availability?.scheduleByProfessional.get(target.professional_id)?.timezone ?? "America/Sao_Paulo";
  const explicitTime = extractExplicitTimeInText(rawText);
  if (explicitTime) {
    const explicitDateIso = hasExplicitDateInText(rawText) ? extractExplicitDateIsoInTimezone(rawText, timezone) : null;
    const baseDateIso = decisionForReschedule.starts_at_iso ?? explicitDateIso ?? target.starts_at;
    const startsAtWithExplicitTime = mergeDateWithTimeInTimezone(baseDateIso, explicitTime.hour, explicitTime.minute, timezone);
    if (startsAtWithExplicitTime) {
      decisionForReschedule.starts_at_iso = startsAtWithExplicitTime;
      decisionForReschedule.ends_at_iso = null;
    }
  } else if (looksLikeSameTimeRequest(rawText) && enrichedDecision.starts_at_iso) {
    const startsAtKeepingTime = mergeDateWithReferenceTimeInTimezone(enrichedDecision.starts_at_iso, target.starts_at, timezone);
    if (startsAtKeepingTime) {
      decisionForReschedule.starts_at_iso = startsAtKeepingTime;
      decisionForReschedule.ends_at_iso = null;
    }
  }
  const created = await createAppointmentFromDecision(admin, tenantId, clientId, catalog, decisionForReschedule, availability, {
    disableTimezoneReinterpretation: hasExplicitTimeRequest
  });
  if (!created.ok || !created.appointmentId) return created;
  const { error: closeError } = await admin.from("appointments").update({
    status: "rescheduled",
    cancellation_reason: `Remarcado via WhatsApp para ${created.appointmentId}`
  }).eq("tenant_id", tenantId).eq("id", target.id);
  if (closeError) {
    return {
      ...created,
      ok: false,
      message: "Consegui criar o novo horário, mas não consegui desmarcar o anterior. Vou sinalizar para ajuste manual."
    };
  }
  return {
    ...created,
    message: `Remarcação concluída. ${created.message}`
  };
}
async function cancelAppointmentFromRequest(admin, tenantId, clientId, catalog, availability, rawText) {
  const { data: activeRows } = await admin.from("appointments").select("id, service_id, professional_id, starts_at, status").eq("tenant_id", tenantId).eq("client_id", clientId).in("status", ACTIVE_APPOINTMENT_STATUSES).gte("starts_at", new Date().toISOString()).order("starts_at", {
    ascending: true
  }).limit(10);
  const rows = activeRows ?? [];
  if (rows.length === 0) {
    return {
      ok: false,
      message: "Não encontrei agendamento ativo para cancelar."
    };
  }
  const normalizedText = normalizeText(rawText);
  const cancelAllRequested = looksLikeCancelAllRequest(rawText);
  const byServiceMention = rows.filter((row)=>{
    if (!row.service_id) return false;
    const service = catalog.services.find((item)=>item.id === row.service_id);
    if (!service) return false;
    return normalizedText.includes(normalizeText(service.name));
  });
  const candidates = byServiceMention.length > 0 ? byServiceMention : rows;
  const explicitDateIso = hasExplicitDateInText(rawText) ? extractExplicitDateIsoInTimezone(rawText, "America/Sao_Paulo") : null;
  const scopedCandidates = explicitDateIso ? candidates.filter((item)=>{
    const timezone = item.professional_id && availability?.scheduleByProfessional.get(item.professional_id)?.timezone || "America/Sao_Paulo";
    return isSameLocalDayInTimezone(item.starts_at, explicitDateIso, timezone);
  }) : candidates;
  if (scopedCandidates.length === 0 && explicitDateIso) {
    return {
      ok: false,
      message: "Não encontrei agendamentos ativos para cancelar na data informada."
    };
  }
  const effectiveCandidates = scopedCandidates.length > 0 ? scopedCandidates : candidates;
  if (cancelAllRequested) {
    const candidateIds = effectiveCandidates.map((item)=>item.id);
    const { error: cancelAllError } = await admin.from("appointments").update({
      status: "cancelled",
      cancellation_reason: "Cancelado via WhatsApp pelo cliente"
    }).eq("tenant_id", tenantId).eq("client_id", clientId).in("id", candidateIds);
    if (cancelAllError) {
      return {
        ok: false,
        message: "Não consegui cancelar todos agora. Pode tentar novamente em instantes?"
      };
    }
    const previewLines = effectiveCandidates.slice(0, 3).map((item)=>{
      const serviceName = item.service_id && catalog.services.find((svc)=>svc.id === item.service_id)?.name || "serviço";
      const professionalName = item.professional_id && catalog.professionals.find((pro)=>pro.id === item.professional_id)?.name || "profissional";
      const timezone = item.professional_id && availability?.scheduleByProfessional.get(item.professional_id)?.timezone || "America/Sao_Paulo";
      return `- ${serviceName} em ${formatDateTimePtBrInTimezone(item.starts_at, timezone)} com ${professionalName}`;
    });
    const extraCount = effectiveCandidates.length - previewLines.length;
    const extraSuffix = extraCount > 0 ? `\n... e mais ${extraCount}.` : "";
    return {
      ok: true,
      message: `Cancelamento concluído. Cancelei ${effectiveCandidates.length} agendamento(s):\n` + `${previewLines.join("\n")}${extraSuffix}`
    };
  }
  if (effectiveCandidates.length > 1) {
    const options = effectiveCandidates.slice(0, 5).map((row, index)=>{
      const serviceName = row.service_id && catalog.services.find((item)=>item.id === row.service_id)?.name || "serviço";
      const professionalName = row.professional_id && catalog.professionals.find((item)=>item.id === row.professional_id)?.name || "profissional";
      return {
        option_index: index + 1,
        appointment_id: row.id,
        service_id: row.service_id,
        service_name: serviceName,
        professional_id: row.professional_id,
        professional_name: professionalName,
        starts_at_iso: row.starts_at
      };
    });
    const lines = options.map((item)=>{
      const timezone = item.professional_id && availability?.scheduleByProfessional.get(item.professional_id)?.timezone || "America/Sao_Paulo";
      return `${item.option_index}) ${item.service_name} em ${formatDateTimePtBrInTimezone(item.starts_at_iso, timezone)} com ${item.professional_name}`;
    });
    return {
      ok: false,
      message: `Encontrei mais de um agendamento para cancelar. Qual opção você quer cancelar?\n` + `${lines.join("\n")}\n` + "Responda com o número da opção.",
      cancellationOptions: options
    };
  }
  const target = effectiveCandidates[0];
  const { error: cancelError } = await admin.from("appointments").update({
    status: "cancelled",
    cancellation_reason: "Cancelado via WhatsApp pelo cliente"
  }).eq("tenant_id", tenantId).eq("id", target.id);
  if (cancelError) {
    return {
      ok: false,
      message: "Não consegui cancelar agora. Pode tentar novamente em instantes?"
    };
  }
  const serviceName = target.service_id && catalog.services.find((item)=>item.id === target.service_id)?.name || "serviço";
  const professionalName = target.professional_id && catalog.professionals.find((item)=>item.id === target.professional_id)?.name || "profissional";
  const timezone = target.professional_id && availability?.scheduleByProfessional.get(target.professional_id)?.timezone || "America/Sao_Paulo";
  return {
    ok: true,
    appointmentId: target.id,
    startsAtIso: target.starts_at,
    serviceName,
    professionalName,
    message: `Cancelamento concluído. Agendamento de ${serviceName} em ${formatDateTimePtBrInTimezone(target.starts_at, timezone)} com ${professionalName} foi cancelado.`
  };
}
async function cancelAppointmentById(admin, tenantId, clientId, catalog, availability, appointmentId) {
  const { data: row } = await admin.from("appointments").select("id, service_id, professional_id, starts_at, status").eq("tenant_id", tenantId).eq("client_id", clientId).eq("id", appointmentId).in("status", ACTIVE_APPOINTMENT_STATUSES).limit(1).maybeSingle();
  if (!row) {
    return {
      ok: false,
      message: "Não encontrei esse agendamento ativo para cancelar."
    };
  }
  const typed = row;
  const { error: cancelError } = await admin.from("appointments").update({
    status: "cancelled",
    cancellation_reason: "Cancelado via WhatsApp pelo cliente"
  }).eq("tenant_id", tenantId).eq("id", typed.id);
  if (cancelError) {
    return {
      ok: false,
      message: "Não consegui cancelar agora. Pode tentar novamente em instantes?"
    };
  }
  const serviceName = typed.service_id && catalog.services.find((item)=>item.id === typed.service_id)?.name || "serviço";
  const professionalName = typed.professional_id && catalog.professionals.find((item)=>item.id === typed.professional_id)?.name || "profissional";
  const timezone = typed.professional_id && availability?.scheduleByProfessional.get(typed.professional_id)?.timezone || "America/Sao_Paulo";
  return {
    ok: true,
    appointmentId: typed.id,
    startsAtIso: typed.starts_at,
    serviceName,
    professionalName,
    message: `Cancelamento concluído. Agendamento de ${serviceName} em ${formatDateTimePtBrInTimezone(typed.starts_at, timezone)} com ${professionalName} foi cancelado.`
  };
}
function buildCatalogPrompt(catalog) {
  return JSON.stringify({
    services: catalog.services.map((item)=>({
        id: item.id,
        name: item.name,
        duration_min: item.duration_min
      })),
    professionals: catalog.professionals.map((item)=>({
        id: item.id,
        name: item.name
      })),
    links: catalog.links
  }, null, 2);
}
async function decideIntentWithAI(conversationText, catalog, aiConfig, latestUserText, shouldGreet) {
  if (!aiConfig.enabled) {
    return {
      intent: "collect_info",
      confidence: 0,
      reply_text: "Recebi sua mensagem. Nosso atendimento vai te responder em instantes.",
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
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) {
    return {
      intent: "collect_info",
      confidence: 0,
      reply_text: buildCollectInfoReply(latestUserText, catalog, shouldGreet),
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
  const model = aiConfig.model ?? Deno.env.get("OPENAI_MODEL") ?? "gpt-4.1-mini";
  const basePrompt = aiConfig.systemPrompt ?? Deno.env.get("OPENAI_WHATSAPP_SYSTEM_PROMPT") ?? "Você é a secretária virtual da Agenda Profissional. Cumprimente o cliente, conduza a conversa com empatia e objetividade, colete preferência de dia/horário e confirme apenas com disponibilidade válida.";
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
- Não invente IDs.
- Atue como secretária do profissional/clínica.
- Cumprimente apenas na primeira mensagem da conversa. Nas demais, responda direto.
- Se faltar preferência de dia/horário, pergunte objetivamente qual período ou horário prefere.
- Se houver opções de horário, apresente em linguagem natural e peça confirmação.
- Se faltar dado para executar agendamento/remarcação, use intent=collect_info e reply_text pedindo só o que falta.
- Use o catálogo abaixo para mapear nomes:
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
        {
          role: "system",
          content: [
            {
              type: "input_text",
              text: systemPrompt
            }
          ]
        },
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: conversationText
            }
          ]
        }
      ],
      max_output_tokens: 500
    })
  });
  if (!response.ok) {
    return {
      intent: "collect_info",
      confidence: 0,
      reply_text: "Consegui registrar sua mensagem. Pode me informar serviço e horário para seguir com o agendamento?",
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
  const data = await response.json();
  const outputText = extractResponseText(data);
  const jsonText = extractJsonObject(outputText);
  if (!jsonText) {
    return {
      intent: "collect_info",
      confidence: 0,
      reply_text: buildCollectInfoReply(latestUserText, catalog, shouldGreet),
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
  const parsed = (()=>{
    try {
      return JSON.parse(jsonText);
    } catch (_) {
      return null;
    }
  })();
  const intent = parseIntentDecision(parsed);
  if (!intent) {
    return {
      intent: "collect_info",
      confidence: 0,
      reply_text: buildCollectInfoReply(latestUserText, catalog, shouldGreet),
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
async function sendWhatsappMessage(to, message, phoneNumberIdFromWebhook, accessTokenOverride = null) {
  const accessToken = accessTokenOverride ?? Deno.env.get("WHATSAPP_ACCESS_TOKEN");
  const defaultPhoneNumberId = Deno.env.get("WHATSAPP_PHONE_NUMBER_ID");
  const apiVersion = Deno.env.get("WHATSAPP_API_VERSION") ?? "v22.0";
  const phoneNumberId = phoneNumberIdFromWebhook ?? defaultPhoneNumberId ?? "";
  if (!accessToken || !phoneNumberId) {
    return {
      messageId: null,
      error: "Missing WHATSAPP_ACCESS_TOKEN or WHATSAPP_PHONE_NUMBER_ID"
    };
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
      text: {
        body: message
      }
    })
  });
  if (!response.ok) {
    const payload = await response.text().catch(()=>"");
    const compact = payload.replace(/\s+/g, " ").trim().slice(0, 600);
    return {
      messageId: null,
      error: `Meta send failed (${response.status}): ${compact || "no response body"}`
    };
  }
  const data = await response.json();
  return {
    messageId: data.messages?.[0]?.id ?? null,
    error: null
  };
}
Deno.serve(async (req)=>{
  if (req.method === "GET") {
    const verifyToken = Deno.env.get("WHATSAPP_VERIFY_TOKEN");
    const url = new URL(req.url);
    const mode = url.searchParams.get("hub.mode");
    const token = url.searchParams.get("hub.verify_token");
    const challenge = url.searchParams.get("hub.challenge");
    if (mode === "subscribe" && verifyToken && token === verifyToken && challenge) {
      return new Response(challenge, {
        status: 200
      });
    }
    return new Response("Forbidden", {
      status: 403
    });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({
      error: "Method not allowed"
    }), {
      status: 405,
      headers: jsonHeaders
    });
  }
  const rawBody = await req.text();
  const signatureOk = await verifyMetaSignature(req, rawBody);
  if (!signatureOk) {
    return new Response(JSON.stringify({
      error: "Invalid signature"
    }), {
      status: 401,
      headers: jsonHeaders
    });
  }
  const payload = (()=>{
    try {
      return JSON.parse(rawBody);
    } catch (_) {
      return null;
    }
  })();
  if (!payload) {
    return new Response(JSON.stringify({
      error: "Invalid JSON payload"
    }), {
      status: 400,
      headers: jsonHeaders
    });
  }
  const incoming = extractIncomingMessages(payload);
  if (incoming.length === 0) {
    return new Response(JSON.stringify({
      ok: true,
      processed: 0
    }), {
      status: 200,
      headers: jsonHeaders
    });
  }
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? Deno.env.get("APP_SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("APP_SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return new Response(JSON.stringify({
      error: "Missing Supabase env"
    }), {
      status: 500,
      headers: jsonHeaders
    });
  }
  const admin = createClient(supabaseUrl, serviceRoleKey);
  let processed = 0;
  for (const item of incoming){
    try {
      const rawPhone = normalizePhone(item.message.from);
      const contactName = resolveClientDisplayName(item.message.contact_name);
      if (!rawPhone) continue;
      const channelConfig = await resolveTenantChannelConfig(admin, item.phoneNumberId);
      if (!channelConfig) continue;
      const tenantId = channelConfig.tenantId;
      const { data: existingClient } = await admin.from("clients").select("id, full_name").eq("tenant_id", tenantId).eq("phone", rawPhone).order("created_at", {
        ascending: true
      }).limit(1).maybeSingle();
      let clientId = existingClient?.id ?? null;
      if (!clientId) {
        const defaultClientName = contactName ?? "Cliente WhatsApp";
        const { data: createdClient } = await admin.from("clients").insert({
          tenant_id: tenantId,
          full_name: defaultClientName,
          phone: rawPhone
        }).select("id").single();
        clientId = createdClient?.id ?? null;
      } else if (contactName) {
        const existingName = (existingClient.full_name ?? "").trim().toLowerCase();
        const shouldUpdateName = !existingName || existingName === "cliente whatsapp" || existingName === "cliente" || existingName === "novo cliente";
        if (shouldUpdateName) {
          await admin.from("clients").update({
            full_name: contactName
          }).eq("tenant_id", tenantId).eq("id", clientId);
        }
      }
      if (!clientId) continue;
      const { data: conversation } = await admin.from("whatsapp_conversations").upsert({
        tenant_id: tenantId,
        client_id: clientId,
        wa_phone: rawPhone,
        status: "open",
        last_message_at: new Date().toISOString()
      }, {
        onConflict: "tenant_id,wa_phone"
      }).select("id").single();
      const conversationId = conversation?.id;
      if (!conversationId) continue;
      const inboundContent = await resolveInboundMessageContent(item.message, channelConfig);
      if (!inboundContent) continue;
      await admin.from("whatsapp_messages").insert({
        tenant_id: tenantId,
        conversation_id: conversationId,
        client_id: clientId,
        direction: "inbound",
        provider_message_id: item.message.id ?? null,
        message_type: inboundContent.messageType,
        media_id: inboundContent.mediaId,
        media_mime_type: inboundContent.mediaMimeType,
        media_sha256: inboundContent.mediaSha256,
        message_text: inboundContent.messageText,
        transcription_text: inboundContent.transcriptionText,
        ai_payload: inboundContent.aiPayload
      });
      if (inboundContent.autoReply) {
        const fallbackDelivery = await sendWhatsappMessage(rawPhone, inboundContent.autoReply, channelConfig.outboundPhoneNumberId ?? item.phoneNumberId, channelConfig.accessToken);
        await admin.from("whatsapp_messages").insert({
          tenant_id: tenantId,
          conversation_id: conversationId,
          client_id: clientId,
          direction: "outbound",
          provider_message_id: fallbackDelivery.messageId,
          message_type: "text",
          message_text: inboundContent.autoReply,
          ai_payload: {
            source: "audio-fallback",
            delivery_error: fallbackDelivery.error
          }
        });
        processed += 1;
        continue;
      }
      const { data: historyRows } = await admin.from("whatsapp_messages").select("direction, message_text").eq("tenant_id", tenantId).eq("conversation_id", conversationId).order("created_at", {
        ascending: false
      }).limit(12);
      const history = (historyRows ?? []).reverse();
      const inboundMessagesCount = history.filter((entry)=>entry.direction === "inbound").length;
      const shouldGreet = inboundMessagesCount <= 1;
      const conversationText = formatConversationForAI(history);
      const catalog = await loadTenantCatalog(admin, tenantId);
      const availability = await loadAvailabilityContext(admin, tenantId, catalog.professionals.map((item)=>item.id));
      let suggestedOptionsPayload = null;
      let cancellationOptionsPayload = null;
      const rawText = inboundContent.messageText;
      const selectedOptionIndex = parseSelectedOptionIndex(rawText);
      let selectedCancellationOption = null;
      let decision;
      let forcedAnchorDayIso = null;
      let forcedMinimumStartsAtIso = null;
      const afterMyAppointmentRequest = looksLikeAfterMyAppointmentRequest(rawText);
      if (selectedOptionIndex !== null) {
        const [latestCancellationOptions, latestSuggestedOptions] = await Promise.all([
          loadLatestCancellationOptions(admin, tenantId, conversationId),
          loadLatestSuggestedOptions(admin, tenantId, conversationId)
        ]);
        const selectedCancellation = latestCancellationOptions.find((item)=>item.option_index === selectedOptionIndex);
        if (selectedCancellation) {
          selectedCancellationOption = selectedCancellation;
          decision = {
            intent: "collect_info",
            confidence: 1,
            reply_text: `Perfeito! Vou cancelar a opção ${selectedOptionIndex} para você.`,
            service_id: selectedCancellation.service_id,
            service_name: selectedCancellation.service_name,
            professional_id: selectedCancellation.professional_id,
            professional_name: selectedCancellation.professional_name,
            starts_at_iso: selectedCancellation.starts_at_iso,
            ends_at_iso: null,
            duration_min: null,
            any_available: false,
            target_appointment_id: selectedCancellation.appointment_id
          };
        } else {
          const selected = latestSuggestedOptions.find((item)=>item.option_index === selectedOptionIndex);
          if (selected) {
            decision = {
              intent: "create_appointment",
              confidence: 1,
              reply_text: `Perfeito! Vou confirmar a opção ${selectedOptionIndex} para você.`,
              service_id: selected.service_id,
              service_name: selected.service_name,
              professional_id: selected.professional_id,
              professional_name: selected.professional_name,
              starts_at_iso: selected.starts_at_iso,
              ends_at_iso: selected.ends_at_iso,
              duration_min: null,
              any_available: false,
              target_appointment_id: null
            };
          } else {
            decision = await decideIntentWithAI(conversationText, catalog, {
              enabled: channelConfig.aiEnabled,
              model: channelConfig.aiModel,
              systemPrompt: channelConfig.aiSystemPrompt
            }, rawText, shouldGreet);
          }
        }
      } else {
        decision = await decideIntentWithAI(conversationText, catalog, {
          enabled: channelConfig.aiEnabled,
          model: channelConfig.aiModel,
          systemPrompt: channelConfig.aiSystemPrompt
        }, rawText, shouldGreet);
      }
      if (looksLikeAffirmativeContinuation(rawText)) {
        const pendingNextOption = await inferPendingNextOptionContext(admin, tenantId, conversationId, catalog);
        if (pendingNextOption) {
          const requestedAnchorMs = pendingNextOption.requestedStartsAtIso ? new Date(pendingNextOption.requestedStartsAtIso).getTime() : Number.NaN;
          const targetAnchorMs = pendingNextOption.targetStartsAtIso ? new Date(pendingNextOption.targetStartsAtIso).getTime() : Number.NaN;
          if (Number.isFinite(requestedAnchorMs) && Number.isFinite(targetAnchorMs)) {
            forcedAnchorDayIso = requestedAnchorMs >= targetAnchorMs ? pendingNextOption.requestedStartsAtIso : pendingNextOption.targetStartsAtIso;
          } else {
            forcedAnchorDayIso = pendingNextOption.requestedStartsAtIso ?? pendingNextOption.targetStartsAtIso;
          }
          decision = {
            ...decision,
            intent: "collect_info",
            confidence: 1,
            reply_text: "Perfeito. Vou buscar as próximas opções para você.",
            service_id: pendingNextOption.service.id,
            service_name: pendingNextOption.service.name,
            professional_id: pendingNextOption.professional?.id ?? null,
            professional_name: pendingNextOption.professional?.name ?? null,
            starts_at_iso: null,
            ends_at_iso: null,
            duration_min: null,
            any_available: pendingNextOption.anyAvailable,
            target_appointment_id: pendingNextOption.targetAppointmentId
          };
        }
      }
      if (afterMyAppointmentRequest) {
        const conversationAnchorStartsAtIso = await inferConversationAnchorStartsAtIso(admin, tenantId, conversationId);
        const inferred = await inferAfterMyAppointmentContext(admin, tenantId, clientId, catalog, rawText, conversationAnchorStartsAtIso);
        if (inferred) {
          forcedAnchorDayIso = inferred.startsAtIso;
          forcedMinimumStartsAtIso = inferred.endsAtIso || inferred.startsAtIso;
          if (!decision.service_id && inferred.service) {
            decision = {
              ...decision,
              intent: "collect_info",
              confidence: Math.max(decision.confidence, 0.8),
              service_id: inferred.service.id,
              service_name: inferred.service.name
            };
          }
          if (!decision.professional_id && inferred.professional) {
            decision = {
              ...decision,
              professional_id: inferred.professional.id,
              professional_name: inferred.professional.name,
              any_available: false
            };
          }
        }
      }
      if ((looksLikeRescheduleRequest(rawText) || decision.intent === "reschedule_appointment") && (!decision.service_id || !decision.professional_id || !decision.target_appointment_id)) {
        const inferred = await inferRescheduleContext(admin, tenantId, clientId, catalog);
        if (inferred) {
          decision = {
            ...decision,
            intent: decision.intent === "create_appointment" ? "create_appointment" : "reschedule_appointment",
            service_id: decision.service_id ?? inferred.service?.id ?? null,
            service_name: decision.service_name ?? inferred.service?.name ?? null,
            professional_id: decision.professional_id ?? inferred.professional?.id ?? null,
            professional_name: decision.professional_name ?? inferred.professional?.name ?? null,
            target_appointment_id: decision.target_appointment_id ?? inferred.appointmentId
          };
        }
      }
      // Fallback for phrases like "dia 17 no mesmo horário":
      // if date was provided but AI did not return starts_at_iso, infer date and keep original appointment time.
      if (looksLikeRescheduleRequest(rawText) && looksLikeSameTimeRequest(rawText) && hasExplicitDateInText(rawText) && !decision.starts_at_iso) {
        const inferred = await inferRescheduleContext(admin, tenantId, clientId, catalog);
        if (inferred) {
          const timezone = availability?.scheduleByProfessional.get(inferred.professional?.id ?? "")?.timezone ?? "America/Sao_Paulo";
          const explicitDateIso = extractExplicitDateIsoInTimezone(rawText, timezone);
          const mergedStartsAtIso = explicitDateIso ? mergeDateWithReferenceTimeInTimezone(explicitDateIso, inferred.startsAtIso, timezone) : null;
          if (mergedStartsAtIso) {
            decision = {
              ...decision,
              intent: "reschedule_appointment",
              confidence: Math.max(decision.confidence, 0.75),
              starts_at_iso: mergedStartsAtIso,
              ends_at_iso: null,
              service_id: decision.service_id ?? inferred.service?.id ?? null,
              service_name: decision.service_name ?? inferred.service?.name ?? null,
              professional_id: decision.professional_id ?? inferred.professional?.id ?? null,
              professional_name: decision.professional_name ?? inferred.professional?.name ?? null,
              target_appointment_id: decision.target_appointment_id ?? inferred.appointmentId
            };
          }
        }
      }
      if (decision.intent === "collect_info" && decision.starts_at_iso && (!decision.service_id || !decision.professional_id)) {
        const [recentContext, inferredReschedule] = await Promise.all([
          inferRecentDecisionContext(admin, tenantId, conversationId, catalog),
          inferRescheduleContext(admin, tenantId, clientId, catalog)
        ]);
        const serviceFromContext = recentContext?.service ?? inferredReschedule?.service ?? null;
        const professionalFromContext = recentContext?.professional ?? inferredReschedule?.professional ?? null;
        if (serviceFromContext) {
          decision = {
            ...decision,
            intent: "reschedule_appointment",
            service_id: decision.service_id ?? serviceFromContext.id,
            service_name: decision.service_name ?? serviceFromContext.name,
            professional_id: decision.professional_id ?? professionalFromContext?.id ?? null,
            professional_name: decision.professional_name ?? professionalFromContext?.name ?? null,
            target_appointment_id: decision.target_appointment_id ?? inferredReschedule?.appointmentId ?? null
          };
        }
      }
      let finalReply = decision.reply_text;
      let actionResult = null;
      const explicitTimeInMessage = extractExplicitTimeInText(rawText);
      if (!actionResult && selectedCancellationOption) {
        actionResult = await cancelAppointmentById(admin, tenantId, clientId, catalog, availability, selectedCancellationOption.appointment_id);
        finalReply = actionResult.message;
      }
      if (!actionResult && looksLikeCancelRequest(rawText)) {
        actionResult = await cancelAppointmentFromRequest(admin, tenantId, clientId, catalog, availability, rawText);
        finalReply = actionResult.message;
        cancellationOptionsPayload = actionResult.cancellationOptions ?? null;
      }
      // Priority path: explicit-time reschedule (e.g. "remarcar para 14hs") must execute directly.
      if (!actionResult && looksLikeRescheduleRequest(rawText) && explicitTimeInMessage) {
        const inferred = await inferRescheduleContext(admin, tenantId, clientId, catalog);
        if (inferred) {
          const timezone = availability?.scheduleByProfessional.get(inferred.professional?.id ?? "")?.timezone ?? "America/Sao_Paulo";
          const explicitDateIso = hasExplicitDateInText(rawText) ? extractExplicitDateIsoInTimezone(rawText, timezone) : null;
          const baseDateIso = decision.starts_at_iso ?? explicitDateIso ?? inferred.startsAtIso;
          const mergedStartsAtIso = mergeDateWithTimeInTimezone(baseDateIso, explicitTimeInMessage.hour, explicitTimeInMessage.minute, timezone);
          if (mergedStartsAtIso) {
            const forcedRescheduleDecision = {
              ...decision,
              intent: "reschedule_appointment",
              confidence: 1,
              starts_at_iso: mergedStartsAtIso,
              ends_at_iso: null,
              service_id: decision.service_id ?? inferred.service?.id ?? null,
              service_name: decision.service_name ?? inferred.service?.name ?? null,
              professional_id: decision.professional_id ?? inferred.professional?.id ?? null,
              professional_name: decision.professional_name ?? inferred.professional?.name ?? null,
              any_available: false,
              target_appointment_id: decision.target_appointment_id ?? inferred.appointmentId
            };
            decision = forcedRescheduleDecision;
            actionResult = await rescheduleAppointmentFromDecision(admin, tenantId, clientId, catalog, forcedRescheduleDecision, availability, rawText);
            finalReply = actionResult.message;
          }
        }
      }
      // Priority path: explicit reschedule request keeping same time must not fall back to generic availability suggestions.
      if (!actionResult && looksLikeRescheduleRequest(rawText) && looksLikeSameTimeRequest(rawText) && hasExplicitDateInText(rawText)) {
        const inferred = await inferRescheduleContext(admin, tenantId, clientId, catalog);
        if (inferred) {
          const timezone = availability?.scheduleByProfessional.get(inferred.professional?.id ?? "")?.timezone ?? "America/Sao_Paulo";
          const explicitDateIso = extractExplicitDateIsoInTimezone(rawText, timezone);
          const mergedStartsAtIso = explicitDateIso ? mergeDateWithReferenceTimeInTimezone(explicitDateIso, inferred.startsAtIso, timezone) : null;
          if (mergedStartsAtIso) {
            const forcedRescheduleDecision = {
              ...decision,
              intent: "reschedule_appointment",
              confidence: 1,
              starts_at_iso: mergedStartsAtIso,
              ends_at_iso: null,
              service_id: decision.service_id ?? inferred.service?.id ?? null,
              service_name: decision.service_name ?? inferred.service?.name ?? null,
              professional_id: decision.professional_id ?? inferred.professional?.id ?? null,
              professional_name: decision.professional_name ?? inferred.professional?.name ?? null,
              any_available: false,
              target_appointment_id: decision.target_appointment_id ?? inferred.appointmentId
            };
            decision = forcedRescheduleDecision;
            actionResult = await rescheduleAppointmentFromDecision(admin, tenantId, clientId, catalog, forcedRescheduleDecision, availability, rawText);
            finalReply = actionResult.message;
          }
        }
      }
      // If user provides an explicit date/time and asks to change schedule, try immediate execution first.
      if (decision.intent === "collect_info" && decision.starts_at_iso) {
        const inferredService = resolveService(catalog, decision);
        if (inferredService) {
          const inferredIntent = {
            ...decision,
            intent: looksLikeRescheduleRequest(rawText) ? "reschedule_appointment" : "create_appointment",
            service_id: decision.service_id ?? inferredService.id,
            service_name: decision.service_name ?? inferredService.name,
            confidence: 1
          };
          actionResult = inferredIntent.intent === "reschedule_appointment" ? await rescheduleAppointmentFromDecision(admin, tenantId, clientId, catalog, inferredIntent, availability, rawText) : await createAppointmentFromDecision(admin, tenantId, clientId, catalog, inferredIntent, availability);
          if (actionResult.ok) {
            finalReply = actionResult.message;
          } else {
            finalReply = actionResult.message;
          }
        }
      }
      if (!actionResult && decision.intent === "collect_info" && decision.confidence >= 0.35) {
        const service = resolveService(catalog, decision);
        const preferredProfessional = resolveProfessional(catalog, decision);
        if (service && !decision.starts_at_iso) {
          const periodPreference = detectPeriodPreference(rawText);
          const dayPreference = detectRelativeDayPreference(rawText);
          const weekdayPreference = detectWeekdayPreference(rawText);
          const optionSearchLimit = forcedAnchorDayIso || forcedMinimumStartsAtIso ? 480 : periodPreference !== null ? 240 : 48;
          const options = await findNextAvailabilityOptions(catalog, availability, service, preferredProfessional?.id ?? null, decision.any_available || !preferredProfessional, optionSearchLimit);
          const keepConversationDay = periodPreference !== null && dayPreference === null && weekdayPreference === null && !hasExplicitDateInText(rawText);
          let anchorDayIso = null;
          if (forcedAnchorDayIso) {
            anchorDayIso = forcedAnchorDayIso;
          } else if (keepConversationDay) {
            const latestSuggestedOptions = await loadLatestSuggestedOptions(admin, tenantId, conversationId);
            anchorDayIso = latestSuggestedOptions[0]?.starts_at_iso ?? null;
          }
          const optionsAfterMinimum = forcedMinimumStartsAtIso ? options.filter((item)=>{
            const slotMs = new Date(item.startsAtIso).getTime();
            const minMs = new Date(forcedMinimumStartsAtIso).getTime();
            return Number.isFinite(slotMs) && Number.isFinite(minMs) && slotMs >= minMs;
          }) : options;
          const baseByDay = optionsAfterMinimum.filter((item)=>{
            const schedule = availability.scheduleByProfessional.get(item.professional.id);
            const timezone = schedule?.timezone || "America/Sao_Paulo";
            if (weekdayPreference !== null) {
              return isWeekdayInTimezone(item.startsAtIso, timezone, weekdayPreference);
            }
            if (dayPreference !== null) {
              return isWithinRelativeDay(item.startsAtIso, timezone, dayPreference);
            }
            if (anchorDayIso) {
              return isSameLocalDayInTimezone(item.startsAtIso, anchorDayIso, timezone);
            }
            return true;
          });
          const filteredByPeriod = baseByDay.filter((item)=>{
            if (periodPreference === null) return true;
            const schedule = availability.scheduleByProfessional.get(item.professional.id);
            const timezone = schedule?.timezone || "America/Sao_Paulo";
            return isWithinPreferredPeriod(item.startsAtIso, timezone, periodPreference);
          });
          const periodOnlyGlobal = optionsAfterMinimum.filter((item)=>{
            if (periodPreference === null) return false;
            const schedule = availability.scheduleByProfessional.get(item.professional.id);
            const timezone = schedule?.timezone || "America/Sao_Paulo";
            return isWithinPreferredPeriod(item.startsAtIso, timezone, periodPreference);
          });
          const optionsByPeriod = filteredByPeriod.slice(0, 3);
          const anchoredOptions = anchorDayIso ? optionsAfterMinimum.filter((item)=>{
            const schedule = availability.scheduleByProfessional.get(item.professional.id);
            const timezone = schedule?.timezone || "America/Sao_Paulo";
            return isOnOrAfterLocalDayInTimezone(item.startsAtIso, anchorDayIso, timezone);
          }) : optionsAfterMinimum;
          const fallbackSource = baseByDay.length > 0 ? baseByDay : anchorDayIso ? anchoredOptions : optionsAfterMinimum;
          const periodAwareFallback = periodPreference === null ? fallbackSource : fallbackSource.filter((item)=>{
            const schedule = availability.scheduleByProfessional.get(item.professional.id);
            const timezone = schedule?.timezone || "America/Sao_Paulo";
            return isPreferredAlternativePeriod(item.startsAtIso, timezone, periodPreference);
          });
          const fallbackOptions = (periodAwareFallback.length > 0 ? periodAwareFallback : fallbackSource).slice(0, 3);
          const sameDayAfterOptions = afterMyAppointmentRequest && anchorDayIso ? optionsAfterMinimum.filter((item)=>{
            const schedule = availability.scheduleByProfessional.get(item.professional.id);
            const timezone = schedule?.timezone || "America/Sao_Paulo";
            return isSameLocalDayInTimezone(item.startsAtIso, anchorDayIso, timezone);
          }) : [];
          const sameDayBeforeOptions = afterMyAppointmentRequest && anchorDayIso && forcedMinimumStartsAtIso ? options.filter((item)=>{
            const schedule = availability.scheduleByProfessional.get(item.professional.id);
            const timezone = schedule?.timezone || "America/Sao_Paulo";
            const sameDay = isSameLocalDayInTimezone(item.startsAtIso, anchorDayIso, timezone);
            if (!sameDay) return false;
            const slotMs = new Date(item.startsAtIso).getTime();
            const minMs = new Date(forcedMinimumStartsAtIso).getTime();
            return Number.isFinite(slotMs) && Number.isFinite(minMs) && slotMs < minMs;
          }) : [];
          if (afterMyAppointmentRequest && anchorDayIso && sameDayAfterOptions.length === 0) {
            const minMs = forcedMinimumStartsAtIso ? new Date(forcedMinimumStartsAtIso).getTime() : Number.NaN;
            const previousDayOptions = sameDayBeforeOptions.slice().sort((a, b)=>{
              const aMs = new Date(a.startsAtIso).getTime();
              const bMs = new Date(b.startsAtIso).getTime();
              if (!Number.isFinite(minMs) || !Number.isFinite(aMs) || !Number.isFinite(bMs)) {
                return bMs - aMs;
              }
              const aDiff = minMs - aMs;
              const bDiff = minMs - bMs;
              return aDiff - bDiff;
            }).slice(0, 3);
            if (previousDayOptions.length > 0) {
              const lines = previousDayOptions.map((item, index)=>{
                const schedule = availability.scheduleByProfessional.get(item.professional.id);
                const timezone = schedule?.timezone || "America/Sao_Paulo";
                const dateLabel = formatDateTimePtBrInTimezone(item.startsAtIso, timezone);
                return `${index + 1}) ${dateLabel} com ${item.professional.name}`;
              });
              suggestedOptionsPayload = previousDayOptions.map((item, index)=>({
                  option_index: index + 1,
                  service_id: service.id,
                  service_name: service.name,
                  professional_id: item.professional.id,
                  professional_name: item.professional.name,
                  starts_at_iso: item.startsAtIso,
                  ends_at_iso: item.endsAtIso
                }));
              finalReply = `Entendi. Não encontrei horário logo após a sua massagem no mesmo dia para ${service.name}. ` + "Posso te oferecer opções anteriores no mesmo dia:\n" + `${lines.join("\n")}`;
            } else {
              const nextDayOptions = anchoredOptions.filter((item)=>{
                const schedule = availability.scheduleByProfessional.get(item.professional.id);
                const timezone = schedule?.timezone || "America/Sao_Paulo";
                return !isSameLocalDayInTimezone(item.startsAtIso, anchorDayIso, timezone);
              }).slice(0, 3);
              if (nextDayOptions.length > 0) {
                const lines = nextDayOptions.map((item, index)=>{
                  const schedule = availability.scheduleByProfessional.get(item.professional.id);
                  const timezone = schedule?.timezone || "America/Sao_Paulo";
                  const dateLabel = formatDateTimePtBrInTimezone(item.startsAtIso, timezone);
                  return `${index + 1}) ${dateLabel} com ${item.professional.name}`;
                });
                suggestedOptionsPayload = nextDayOptions.map((item, index)=>({
                    option_index: index + 1,
                    service_id: service.id,
                    service_name: service.name,
                    professional_id: item.professional.id,
                    professional_name: item.professional.name,
                    starts_at_iso: item.startsAtIso,
                    ends_at_iso: item.endsAtIso
                  }));
                finalReply = `Entendi. Não encontrei horário logo após a sua massagem no mesmo dia para ${service.name}. ` + "Aqui estão as próximas opções:\n" + `${lines.join("\n")}`;
              } else {
                finalReply = `Entendi. Não há horário logo após a sua massagem no mesmo dia para ${service.name}. ` + "Se quiser, me diga outro dia/período e eu busco as melhores opções.";
              }
            }
          } else if (optionsByPeriod.length > 0) {
            const lines = optionsByPeriod.map((item, index)=>{
              const schedule = availability.scheduleByProfessional.get(item.professional.id);
              const timezone = schedule?.timezone || "America/Sao_Paulo";
              const dateLabel = formatDateTimePtBrInTimezone(item.startsAtIso, timezone);
              return `${index + 1}) ${dateLabel} com ${item.professional.name}`;
            });
            suggestedOptionsPayload = optionsByPeriod.map((item, index)=>({
                option_index: index + 1,
                service_id: service.id,
                service_name: service.name,
                professional_id: item.professional.id,
                professional_name: item.professional.name,
                starts_at_iso: item.startsAtIso,
                ends_at_iso: item.endsAtIso
              }));
            const intro = shouldGreet ? "Olá! " : "";
            finalReply = `${intro}Para ${service.name}, encontrei estes horários disponíveis:\n` + `${lines.join("\n")}\n` + "Você prefere alguma dessas opções? Se quiser, me diga outro dia e horário de preferência.";
          } else if (periodPreference !== null && periodOnlyGlobal.length > 0) {
            const intro = shouldGreet ? "Olá! " : "";
            const periodLabel = periodPreference === "morning" ? "pela manhã" : periodPreference === "afternoon" ? "à tarde" : periodPreference === "late_day" ? "no fim do dia" : "à noite";
            const periodLines = periodOnlyGlobal.slice(0, 3).map((item, index)=>{
              const schedule = availability.scheduleByProfessional.get(item.professional.id);
              const timezone = schedule?.timezone || "America/Sao_Paulo";
              const dateLabel = formatDateTimePtBrInTimezone(item.startsAtIso, timezone);
              return `${index + 1}) ${dateLabel} com ${item.professional.name}`;
            });
            suggestedOptionsPayload = periodOnlyGlobal.slice(0, 3).map((item, index)=>({
                option_index: index + 1,
                service_id: service.id,
                service_name: service.name,
                professional_id: item.professional.id,
                professional_name: item.professional.name,
                starts_at_iso: item.startsAtIso,
                ends_at_iso: item.endsAtIso
              }));
            finalReply = `${intro}Para o dia solicitado, não encontrei horários disponíveis ${periodLabel} para ${service.name}. ` + `Aqui estão as próximas opções ${periodLabel}:\n` + `${periodLines.join("\n")}`;
          } else if (periodPreference !== null && fallbackOptions.length > 0) {
            const intro = shouldGreet ? "Olá! " : "";
            const periodLabel = periodPreference === "morning" ? "pela manhã" : periodPreference === "afternoon" ? "à tarde" : periodPreference === "late_day" ? "no fim do dia" : "à noite";
            const alternativeLines = fallbackOptions.map((item, index)=>{
              const schedule = availability.scheduleByProfessional.get(item.professional.id);
              const timezone = schedule?.timezone || "America/Sao_Paulo";
              const dateLabel = formatDateTimePtBrInTimezone(item.startsAtIso, timezone);
              return `${index + 1}) ${dateLabel} com ${item.professional.name}`;
            });
            suggestedOptionsPayload = fallbackOptions.map((item, index)=>({
                option_index: index + 1,
                service_id: service.id,
                service_name: service.name,
                professional_id: item.professional.id,
                professional_name: item.professional.name,
                starts_at_iso: item.startsAtIso,
                ends_at_iso: item.endsAtIso
              }));
            finalReply = `${intro}No momento não encontrei horários disponíveis ${periodLabel} para ${service.name}. ` + "Posso te sugerir as próximas opções em outros períodos:\n" + `${alternativeLines.join("\n")}`;
          } else {
            const intro = shouldGreet ? "Olá! " : "";
            finalReply = `${intro}No momento não encontrei disponibilidade próxima para ${service.name}. ` + "Me diga seu dia/horário de preferência que eu continuo buscando.";
          }
        } else {
          finalReply = shouldPreserveAiCollectReply(decision) ? decision.reply_text : buildCollectInfoReply(rawText, catalog, shouldGreet);
        }
      } else if (!actionResult && decision.intent === "collect_info") {
        finalReply = shouldPreserveAiCollectReply(decision) ? decision.reply_text : buildCollectInfoReply(rawText, catalog, shouldGreet);
      }
      if (!actionResult && decision.confidence >= 0.6 && decision.intent === "create_appointment") {
        actionResult = await createAppointmentFromDecision(admin, tenantId, clientId, catalog, decision, availability);
        if (actionResult.ok) {
          finalReply = actionResult.message;
        } else if (decision.intent !== "collect_info") {
          finalReply = actionResult.message;
        }
      }
      if (!actionResult && decision.confidence >= 0.6 && decision.intent === "reschedule_appointment") {
        actionResult = await rescheduleAppointmentFromDecision(admin, tenantId, clientId, catalog, decision, availability, rawText);
        if (actionResult.ok) {
          finalReply = actionResult.message;
        } else {
          finalReply = actionResult.message;
        }
      }
      finalReply = normalizeOutgoingPortuguese(finalReply);
      const delivery = await sendWhatsappMessage(rawPhone, finalReply, channelConfig.outboundPhoneNumberId ?? item.phoneNumberId, channelConfig.accessToken);
      await admin.from("whatsapp_messages").insert({
        tenant_id: tenantId,
        conversation_id: conversationId,
        client_id: clientId,
        direction: "outbound",
        provider_message_id: delivery.messageId,
        message_type: "text",
        message_text: finalReply,
        ai_payload: {
          model: channelConfig.aiModel ?? Deno.env.get("OPENAI_MODEL") ?? "gpt-4.1-mini",
          source: "openai-responses",
          decision,
          action_result: actionResult,
          suggested_options: suggestedOptionsPayload,
          cancellation_options: cancellationOptionsPayload,
          delivery_error: delivery.error
        }
      });
      processed += 1;
    } catch (_) {
      continue;
    }
  }
  return new Response(JSON.stringify({
    ok: true,
    processed
  }), {
    status: 200,
    headers: jsonHeaders
  });
});
