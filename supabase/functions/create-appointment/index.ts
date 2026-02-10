import { createClient } from "npm:@supabase/supabase-js@2.49.1";
import { CreateAppointmentInputSchema } from "../_shared/schemas.ts";

const ACTIVE_STATUSES = ["scheduled", "confirmed"];
const jsonHeaders = { "Content-Type": "application/json" };

type CandidateProfessional = { id: string };
type ScheduleSettingsRow = {
  professional_id: string;
  timezone: string;
  workdays: unknown;
  work_hours: unknown;
};
type BreakConfig = { enabled: boolean; start: string; end: string };

function normalizePhone(phone: string | null | undefined): string {
  if (!phone) return "";
  return phone.replace(/[^\d+]/g, "");
}

function parseMinutes(value: string): number | null {
  const [hour, minute] = value.split(":").map((item) => Number.parseInt(item, 10));
  if (Number.isNaN(hour) || Number.isNaN(minute)) return null;
  return hour * 60 + minute;
}

function parseWorkdays(raw: unknown): number[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .map((item) => Number(item))
    .filter((item) => Number.isInteger(item) && item >= 0 && item <= 6);
}

function parseBreakConfig(raw: unknown, fallbackStart: string, fallbackEnd: string): BreakConfig {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return { enabled: false, start: fallbackStart, end: fallbackEnd };
  }

  const value = raw as Record<string, unknown>;
  const enabled = value.enabled === true;
  const start = typeof value.start === "string" ? value.start : fallbackStart;
  const end = typeof value.end === "string" ? value.end : fallbackEnd;
  return { enabled, start, end };
}

function getWeekdayAndMinutesInTimezone(isoValue: string, timezone: string) {
  const date = new Date(isoValue);
  if (Number.isNaN(date.getTime())) return null;

  const weekdayFormat = new Intl.DateTimeFormat("en-US", { timeZone: timezone, weekday: "short" });
  const hourFormat = new Intl.DateTimeFormat("en-US", { timeZone: timezone, hour: "2-digit", hour12: false });
  const minuteFormat = new Intl.DateTimeFormat("en-US", { timeZone: timezone, minute: "2-digit" });

  const weekdayMap: Record<string, number> = {
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

  return { weekday, minutes: hour * 60 + minute };
}

function overlaps(startA: number, endA: number, startB: number, endB: number) {
  return startA < endB && startB < endA;
}

function isWithinSchedule(
  settings: ScheduleSettingsRow | null | undefined,
  startsAtIso: string,
  endsAtIso: string
) {
  if (!settings) return true;

  const timezone = settings.timezone || "America/Sao_Paulo";
  const startInTz = getWeekdayAndMinutesInTimezone(startsAtIso, timezone);
  const endInTz = getWeekdayAndMinutesInTimezone(endsAtIso, timezone);
  if (!startInTz || !endInTz) return false;
  if (startInTz.weekday !== endInTz.weekday) return false;
  if (endInTz.minutes <= startInTz.minutes) return false;

  const workdays = parseWorkdays(settings.workdays);
  if (workdays.length > 0 && !workdays.includes(startInTz.weekday)) return false;

  const workHours =
    settings.work_hours && typeof settings.work_hours === "object" && !Array.isArray(settings.work_hours)
      ? (settings.work_hours as Record<string, unknown>)
      : {};

  const dailyOverrides =
    workHours.daily_overrides &&
    typeof workHours.daily_overrides === "object" &&
    !Array.isArray(workHours.daily_overrides)
      ? (workHours.daily_overrides as Record<string, unknown>)
      : {};

  const overrideForWeekday = dailyOverrides[String(startInTz.weekday)];
  const dayRule =
    overrideForWeekday && typeof overrideForWeekday === "object" && !Array.isArray(overrideForWeekday)
      ? (overrideForWeekday as Record<string, unknown>)
      : workHours;

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

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 405, headers: jsonHeaders });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? Deno.env.get("APP_SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("APP_SUPABASE_ANON_KEY");

  if (!supabaseUrl || !anonKey) {
    return new Response(JSON.stringify({ error: "Missing Supabase env" }), { status: 500, headers: jsonHeaders });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Missing Authorization header" }), { status: 401, headers: jsonHeaders });
  }

  const supabase = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } }
  });

  const {
    data: { user },
    error: userError
  } = await supabase.auth.getUser();

  if (userError || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: jsonHeaders });
  }

  const body = await req.json().catch(() => null);
  const parsed = CreateAppointmentInputSchema.safeParse(body);
  if (!parsed.success) {
    return new Response(JSON.stringify({ error: "Invalid payload", details: parsed.error.flatten() }), {
      status: 400,
      headers: jsonHeaders
    });
  }

  const payload = parsed.data;
  const normalizedPhone = normalizePhone(payload.client_phone);

  const { data: tenantId, error: tenantError } = await supabase.rpc("auth_tenant_id");
  if (tenantError || !tenantId) {
    return new Response(JSON.stringify({ error: "Unable to resolve tenant" }), { status: 403, headers: jsonHeaders });
  }

  const { data: service, error: serviceError } = await supabase
    .from("services")
    .select("id, specialty_id, duration_min")
    .eq("tenant_id", tenantId)
    .eq("id", payload.service_id)
    .eq("active", true)
    .maybeSingle();

  if (serviceError || !service) {
    return new Response(JSON.stringify({ error: "Service not found" }), { status: 404, headers: jsonHeaders });
  }
  const startsAt = new Date(payload.starts_at);
  if (Number.isNaN(startsAt.getTime())) {
    return new Response(JSON.stringify({ error: "Invalid starts_at" }), { status: 400, headers: jsonHeaders });
  }
  const serviceDuration = Number(service.duration_min);
  if (!Number.isInteger(serviceDuration) || serviceDuration <= 0) {
    return new Response(JSON.stringify({ error: "Service duration is invalid" }), {
      status: 500,
      headers: jsonHeaders
    });
  }
  const resolvedEndsAt = payload.ends_at ?? new Date(startsAt.getTime() + serviceDuration * 60 * 1000).toISOString();
  const endsAt = new Date(resolvedEndsAt);
  if (Number.isNaN(endsAt.getTime()) || endsAt <= startsAt) {
    return new Response(JSON.stringify({ error: "Invalid appointment time range" }), {
      status: 400,
      headers: jsonHeaders
    });
  }

  let selectedProfessionalId = payload.professional_id;

  const { data: scheduleRows, error: scheduleError } = await supabase
    .from("professional_schedule_settings")
    .select("professional_id, timezone, workdays, work_hours");
  if (scheduleError) {
    return new Response(JSON.stringify({ error: "Failed to load schedule settings" }), {
      status: 500,
      headers: jsonHeaders
    });
  }
  const scheduleByProfessional = new Map<string, ScheduleSettingsRow>(
    ((scheduleRows ?? []) as ScheduleSettingsRow[]).map((item) => [item.professional_id, item])
  );

  if (payload.any_available && !selectedProfessionalId) {
    const { data: serviceLinks, error: linksError } = await supabase
      .from("professional_services")
      .select("professional_id")
      .eq("tenant_id", tenantId)
      .eq("service_id", payload.service_id);

    if (linksError) {
      return new Response(JSON.stringify({ error: "Failed to find professionals" }), { status: 500, headers: jsonHeaders });
    }

    const professionalIds = (serviceLinks ?? []).map((link) => link.professional_id);
    if (professionalIds.length === 0) {
      return new Response(JSON.stringify({ error: "No available professional" }), { status: 409, headers: jsonHeaders });
    }

    const { data: professionals, error: professionalsError } = await supabase
      .from("professionals")
      .select("id")
      .eq("tenant_id", tenantId)
      .eq("active", true)
      .in("id", professionalIds);

    if (professionalsError) {
      return new Response(JSON.stringify({ error: "Failed to list professionals" }), { status: 500, headers: jsonHeaders });
    }

    for (const professional of (professionals ?? []) as CandidateProfessional[]) {
      const settings = scheduleByProfessional.get(professional.id);
      if (!isWithinSchedule(settings, payload.starts_at, resolvedEndsAt)) {
        continue;
      }

      const { data: conflict } = await supabase
        .from("appointments")
        .select("id")
        .eq("tenant_id", tenantId)
        .eq("professional_id", professional.id)
        .in("status", ACTIVE_STATUSES)
        .lt("starts_at", resolvedEndsAt)
        .gt("ends_at", payload.starts_at)
        .limit(1);

      if (!conflict || conflict.length === 0) {
        selectedProfessionalId = professional.id;
        break;
      }
    }

    if (!selectedProfessionalId) {
      return new Response(JSON.stringify({ error: "No available professional" }), { status: 409, headers: jsonHeaders });
    }
  }

  if (!selectedProfessionalId) {
    return new Response(JSON.stringify({ error: "professional_id is required" }), { status: 400, headers: jsonHeaders });
  }

  const selectedProfessionalSchedule = scheduleByProfessional.get(selectedProfessionalId);
  if (!isWithinSchedule(selectedProfessionalSchedule, payload.starts_at, resolvedEndsAt)) {
    return new Response(JSON.stringify({ error: "Horario indisponivel." }), {
      status: 409,
      headers: jsonHeaders
    });
  }

  let resolvedClientId = payload.client_id;

  if (!resolvedClientId) {
    if (!normalizedPhone) {
      return new Response(JSON.stringify({ error: "client_phone is required when client_id is null" }), {
        status: 400,
        headers: jsonHeaders
      });
    }

    const { data: existingClient, error: existingClientError } = await supabase
      .from("clients")
      .select("id, full_name")
      .eq("tenant_id", tenantId)
      .eq("phone", normalizedPhone)
      .order("created_at", { ascending: true })
      .limit(1)
      .maybeSingle();

    if (existingClientError) {
      return new Response(JSON.stringify({ error: "Failed to resolve client" }), { status: 500, headers: jsonHeaders });
    }

    if (existingClient?.id) {
      resolvedClientId = existingClient.id;

      if (payload.client_name && payload.client_name !== existingClient.full_name) {
        await supabase
          .from("clients")
          .update({ full_name: payload.client_name })
          .eq("tenant_id", tenantId)
          .eq("id", existingClient.id);
      }
    } else {
      const fallbackName = payload.client_name || "Cliente WhatsApp";
      const { data: insertedClient, error: insertClientError } = await supabase
        .from("clients")
        .insert({
          tenant_id: tenantId,
          full_name: fallbackName,
          phone: normalizedPhone
        })
        .select("id")
        .single();

      if (insertClientError || !insertedClient) {
        return new Response(JSON.stringify({ error: "Could not create client" }), {
          status: 500,
          headers: jsonHeaders
        });
      }

      resolvedClientId = insertedClient.id;
    }
  }

  const { data: insertedAppointment, error: insertError } = await supabase
    .from("appointments")
    .insert({
      tenant_id: tenantId,
      client_id: resolvedClientId,
      service_id: payload.service_id,
      specialty_id: service.specialty_id,
      professional_id: selectedProfessionalId,
      starts_at: payload.starts_at,
      ends_at: resolvedEndsAt,
      status: "scheduled",
      source: payload.source,
      created_by: user.id,
      assigned_at: new Date().toISOString(),
      assigned_by: user.id
    })
    .select("id, tenant_id, professional_id, service_id, status, starts_at, ends_at, assigned_at, assigned_by")
    .single();

  if (insertError) {
    if (insertError.code === "23P01") {
      return new Response(JSON.stringify({ error: "Time conflict for professional" }), { status: 409, headers: jsonHeaders });
    }

    return new Response(JSON.stringify({ error: "Could not create appointment" }), {
      status: 500,
      headers: jsonHeaders
    });
  }

  return new Response(JSON.stringify({ ok: true, appointment: insertedAppointment }), {
    status: 201,
    headers: jsonHeaders
  });
});
