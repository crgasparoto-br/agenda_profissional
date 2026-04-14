import { NextResponse } from "next/server";
import { getSupabaseAdminClient } from "@/lib/supabase-admin";
import { getSupabaseServerClient } from "@/lib/supabase-server";

export async function POST() {
  try {
    const supabase = await getSupabaseServerClient();
    const adminClient = getSupabaseAdminClient();

    const {
      data: { user },
      error: authError
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return NextResponse.json({ error: "Nao autenticado." }, { status: 401 });
    }

    const { data: tenantId, error: tenantError } = await supabase.rpc("auth_tenant_id");
    if (tenantError || !tenantId) {
      return NextResponse.json({ error: "Nao foi possivel resolver a organizacao atual." }, { status: 400 });
    }

    const nowIso = new Date().toISOString();

    const { error: credentialsError } = await (adminClient as any)
      .from("whatsapp_meta_credentials")
      .delete()
      .eq("tenant_id", tenantId);

    if (credentialsError) {
      return NextResponse.json({ error: credentialsError.message }, { status: 400 });
    }

    const { data, error } = await (adminClient as any)
      .from("whatsapp_meta_integrations")
      .update({
        connection_status: "disconnected",
        meta_business_account_id: null,
        meta_phone_number_id: null,
        whatsapp_number: null,
        verified_name: null,
        last_error: null,
        connected_at: null,
        last_synced_at: nowIso,
        updated_at: nowIso,
        metadata: {
          disconnected_by_user_id: user.id,
          disconnected_at: nowIso
        }
      })
      .eq("tenant_id", tenantId)
      .select(
        "id, connection_status, whatsapp_number, meta_phone_number_id, meta_business_account_id, verified_name, display_name, account_label, last_error"
      )
      .maybeSingle();

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }

    return NextResponse.json({ ok: true, integration: data ?? null });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Erro inesperado ao desconectar a conta Meta.";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
