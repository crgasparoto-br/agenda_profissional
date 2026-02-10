import { createClient } from "npm:@supabase/supabase-js@2.49.1";
import { BootstrapTenantInputSchema } from "../_shared/schemas.ts";

const jsonHeaders = { "Content-Type": "application/json" };

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 405, headers: jsonHeaders });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? Deno.env.get("APP_SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("APP_SUPABASE_ANON_KEY");
  const serviceRoleKey =
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("APP_SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return new Response(JSON.stringify({ error: "Missing Supabase env" }), { status: 500, headers: jsonHeaders });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Missing Authorization header" }), { status: 401, headers: jsonHeaders });
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } }
  });

  const {
    data: { user },
    error: userError
  } = await userClient.auth.getUser();

  if (userError || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: jsonHeaders });
  }

  const body = await req.json().catch(() => null);
  const parsed = BootstrapTenantInputSchema.safeParse(body);
  if (!parsed.success) {
    return new Response(JSON.stringify({ error: "Invalid payload", details: parsed.error.flatten() }), {
      status: 400,
      headers: jsonHeaders
    });
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey);

  const { data: existingProfile, error: profileLookupError } = await adminClient
    .from("profiles")
    .select("tenant_id")
    .eq("id", user.id)
    .maybeSingle();

  if (profileLookupError) {
    return new Response(JSON.stringify({ error: "Failed to inspect profile" }), { status: 500, headers: jsonHeaders });
  }

  if (existingProfile) {
    const { data: existingProfessional } = await adminClient
      .from("professionals")
      .select("id")
      .eq("tenant_id", existingProfile.tenant_id)
      .eq("user_id", user.id)
      .maybeSingle();

    return new Response(
      JSON.stringify({
        ok: true,
        already_initialized: true,
        tenant_id: existingProfile.tenant_id,
        professional_id: existingProfessional?.id ?? null
      }),
      { status: 200, headers: jsonHeaders }
    );
  }

  const { tenant_type, tenant_name, full_name, phone } = parsed.data;

  const { data: tenant, error: tenantError } = await adminClient
    .from("tenants")
    .insert({ type: tenant_type, name: tenant_name })
    .select("id")
    .single();

  if (tenantError || !tenant) {
    return new Response(JSON.stringify({ error: "Failed to create tenant" }), { status: 500, headers: jsonHeaders });
  }

  const { error: profileInsertError } = await adminClient.from("profiles").insert({
    id: user.id,
    tenant_id: tenant.id,
    role: "owner",
    full_name,
    phone
  });

  if (profileInsertError) {
    return new Response(JSON.stringify({ error: "Failed to create profile" }), { status: 500, headers: jsonHeaders });
  }

  const { data: professional, error: professionalError } = await adminClient
    .from("professionals")
    .insert({ tenant_id: tenant.id, user_id: user.id, name: full_name, active: true })
    .select("id")
    .single();

  if (professionalError || !professional) {
    return new Response(JSON.stringify({ error: "Failed to create professional" }), { status: 500, headers: jsonHeaders });
  }

  const { error: scheduleError } = await adminClient.from("professional_schedule_settings").insert({
    tenant_id: tenant.id,
    professional_id: professional.id,
    timezone: "America/Sao_Paulo",
    workdays: [1, 2, 3, 4, 5],
    work_hours: {
      start: "09:00",
      end: "18:00",
      lunch_break: { enabled: false, start: "12:00", end: "13:00" },
      snack_break: { enabled: false, start: "16:00", end: "16:15" }
    },
    slot_min: 30,
    buffer_min: 0
  });

  if (scheduleError) {
    return new Response(JSON.stringify({ error: "Failed to create schedule settings" }), {
      status: 500,
      headers: jsonHeaders
    });
  }

  return new Response(
    JSON.stringify({ ok: true, already_initialized: false, tenant_id: tenant.id, professional_id: professional.id }),
    { status: 200, headers: jsonHeaders }
  );
});
