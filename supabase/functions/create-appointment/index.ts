import { createClient } from "npm:@supabase/supabase-js@2.49.1";
import { CreateAppointmentInputSchema } from "../_shared/schemas.ts";

const ACTIVE_STATUSES = ["scheduled", "confirmed"];
const jsonHeaders = { "Content-Type": "application/json" };

type CandidateProfessional = { id: string };

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

  const { data: tenantId, error: tenantError } = await supabase.rpc("auth_tenant_id");
  if (tenantError || !tenantId) {
    return new Response(JSON.stringify({ error: "Unable to resolve tenant" }), { status: 403, headers: jsonHeaders });
  }

  const { data: service, error: serviceError } = await supabase
    .from("services")
    .select("id, specialty_id")
    .eq("tenant_id", tenantId)
    .eq("id", payload.service_id)
    .eq("active", true)
    .maybeSingle();

  if (serviceError || !service) {
    return new Response(JSON.stringify({ error: "Service not found" }), { status: 404, headers: jsonHeaders });
  }

  let selectedProfessionalId = payload.professional_id;

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
      const { data: conflict } = await supabase
        .from("appointments")
        .select("id")
        .eq("tenant_id", tenantId)
        .eq("professional_id", professional.id)
        .in("status", ACTIVE_STATUSES)
        .lt("starts_at", payload.ends_at)
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

  const { data: insertedAppointment, error: insertError } = await supabase
    .from("appointments")
    .insert({
      tenant_id: tenantId,
      client_id: payload.client_id,
      service_id: payload.service_id,
      specialty_id: service.specialty_id,
      professional_id: selectedProfessionalId,
      starts_at: payload.starts_at,
      ends_at: payload.ends_at,
      status: "scheduled",
      source: "professional",
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
