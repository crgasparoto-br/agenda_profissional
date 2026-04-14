import { NextResponse } from "next/server";
import { getSupabaseAdminClient } from "@/lib/supabase-admin";
import { getSupabaseServerClient } from "@/lib/supabase-server";

type CompletePayload = {
  event?: string;
  code?: string | null;
  error?: string | null;
  sessionInfo?: {
    phone_number_id?: string | null;
    waba_id?: string | null;
    display_phone_number?: string | null;
    verified_name?: string | null;
    account_label?: string | null;
    display_name?: string | null;
  } | null;
};

type MetaTokenResponse = {
  access_token?: string;
  token_type?: string;
};

type MetaPhoneNumberNode = {
  id?: string;
  display_phone_number?: string;
  verified_name?: string;
};

function stringOrNull(value: unknown) {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : null;
}

async function exchangeCodeForAccessToken(code: string, graphVersion: string) {
  const appId = process.env.NEXT_PUBLIC_META_APP_ID;
  const appSecret = process.env.META_APP_SECRET;

  if (!appId || !appSecret) return null;

  const url = new URL(`https://graph.facebook.com/${graphVersion}/oauth/access_token`);
  url.searchParams.set("client_id", appId);
  url.searchParams.set("client_secret", appSecret);
  url.searchParams.set("code", code);

  const response = await fetch(url.toString(), { method: "GET", cache: "no-store" });
  if (!response.ok) return null;

  const data = (await response.json().catch(() => ({}))) as MetaTokenResponse;
  return {
    accessToken: stringOrNull(data.access_token),
    tokenType: stringOrNull(data.token_type)
  };
}

async function fetchPhoneNumberData(
  accessToken: string,
  wabaId: string,
  phoneNumberId: string,
  graphVersion: string
) {
  const fields = ["id", "display_phone_number", "verified_name"].join(",");
  const url = new URL(`https://graph.facebook.com/${graphVersion}/${wabaId}/phone_numbers`);
  url.searchParams.set("fields", fields);

  const response = await fetch(url.toString(), {
    method: "GET",
    cache: "no-store",
    headers: {
      Authorization: `Bearer ${accessToken}`
    }
  });

  if (!response.ok) return null;

  const data = (await response.json().catch(() => ({}))) as { data?: MetaPhoneNumberNode[] };
  return (data.data ?? []).find((item) => item.id === phoneNumberId) ?? null;
}

export async function POST(req: Request) {
  try {
    const body = (await req.json().catch(() => ({}))) as CompletePayload;
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

    const event = stringOrNull(body.event) ?? "unknown";
    const graphVersion = process.env.NEXT_PUBLIC_META_GRAPH_API_VERSION ?? "v22.0";
    const code = stringOrNull(body.code);
    const explicitError = stringOrNull(body.error);

    const sessionInfo = body.sessionInfo ?? {};
    const wabaId = stringOrNull(sessionInfo.waba_id);
    const phoneNumberId = stringOrNull(sessionInfo.phone_number_id);

    let whatsappNumber = stringOrNull(sessionInfo.display_phone_number);
    let verifiedName = stringOrNull(sessionInfo.verified_name);
    const displayName = stringOrNull(sessionInfo.display_name);
    const accountLabel = stringOrNull(sessionInfo.account_label);
    let codeExchangeCompleted = false;
    let exchangedAccessToken: string | null = null;
    let exchangedTokenType: string | null = null;

    if (code && wabaId && phoneNumberId) {
      const tokenResult = await exchangeCodeForAccessToken(code, graphVersion);
      exchangedAccessToken = tokenResult?.accessToken ?? null;
      exchangedTokenType = tokenResult?.tokenType ?? null;
      if (exchangedAccessToken) {
        codeExchangeCompleted = true;
        const phoneNode = await fetchPhoneNumberData(exchangedAccessToken, wabaId, phoneNumberId, graphVersion);
        whatsappNumber = whatsappNumber ?? stringOrNull(phoneNode?.display_phone_number);
        verifiedName = verifiedName ?? stringOrNull(phoneNode?.verified_name);
      }
    }

    const connectionStatus = explicitError
      ? "error"
      : phoneNumberId && whatsappNumber && exchangedAccessToken
        ? "connected"
      : event === "FINISH" || phoneNumberId || wabaId
          ? "pending"
          : "not_connected";

    const payload = {
      tenant_id: tenantId,
      provider: "meta",
      connection_method: "embedded_signup",
      connection_status: connectionStatus,
      meta_business_account_id: wabaId,
      meta_phone_number_id: phoneNumberId,
      whatsapp_number: whatsappNumber,
      verified_name: verifiedName,
      display_name: displayName,
      account_label: accountLabel,
      last_error: explicitError,
      connected_at: connectionStatus === "connected" ? new Date().toISOString() : null,
      last_synced_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      metadata: {
        onboarding_event: event,
        code_exchange_completed: codeExchangeCompleted,
        completed_by_user_id: user.id
      }
    };

    if (exchangedAccessToken) {
      const { error: credentialError } = await (adminClient as any).from("whatsapp_meta_credentials").upsert(
        {
          tenant_id: tenantId,
          access_token: exchangedAccessToken,
          token_type: exchangedTokenType,
          updated_at: new Date().toISOString()
        },
        { onConflict: "tenant_id" }
      );

      if (credentialError) {
        return NextResponse.json({ error: credentialError.message }, { status: 400 });
      }
    }

    const { data, error } = await (supabase as any)
      .from("whatsapp_meta_integrations")
      .upsert(payload, { onConflict: "tenant_id" })
      .select(
        "id, connection_status, whatsapp_number, meta_phone_number_id, meta_business_account_id, verified_name, display_name, account_label, last_error"
      )
      .maybeSingle();

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }

    return NextResponse.json({ ok: true, integration: data });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Erro inesperado ao concluir a conexao Meta.";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
