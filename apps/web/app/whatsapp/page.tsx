"use client";

import { FormEvent, useCallback, useEffect, useRef, useState } from "react";
import { getSupabaseBrowserClient } from "@/lib/supabase-browser";
import { formatPhone } from "@/lib/phone";

type ChannelRow = {
  id: string;
  label: string;
  whatsapp_number: string;
  phone_number_id: string;
  active: boolean;
  ai_enabled: boolean;
  audio_enabled: boolean;
  ai_model: string;
  ai_system_prompt: string | null;
  professional_id: string | null;
  professionals: { name: string | null } | null;
};

type ProfessionalRow = {
  id: string;
  name: string;
  active: boolean;
};

type IntegrationRow = {
  id: string;
  connection_status: "not_connected" | "pending" | "connected" | "error" | "disconnected";
  whatsapp_number: string | null;
  meta_phone_number_id: string | null;
  meta_business_account_id: string | null;
  verified_name: string | null;
  display_name: string | null;
  account_label: string | null;
  last_error: string | null;
};

const DEFAULT_PROMPT =
  "Voce e a secretaria virtual da Agenda Profissional. Cumprimente o cliente, pergunte a preferencia de dia e horario, apresente opcoes disponiveis e confirme o agendamento somente apos validacao.";

const META_APP_ID = process.env.NEXT_PUBLIC_META_APP_ID ?? "";
const META_EMBEDDED_SIGNUP_CONFIG_ID =
  process.env.NEXT_PUBLIC_META_WHATSAPP_EMBEDDED_SIGNUP_CONFIG_ID ?? "";
const META_GRAPH_API_VERSION = process.env.NEXT_PUBLIC_META_GRAPH_API_VERSION ?? "v22.0";

type MetaEmbeddedSignupEventPayload = {
  type?: string;
  event?: "FINISH" | "CANCEL" | "ERROR";
  data?: {
    phone_number_id?: string;
    waba_id?: string;
    display_phone_number?: string;
    verified_name?: string;
    account_label?: string;
    display_name?: string;
  };
  error_message?: string;
};

type MetaLoginResponse = {
  authResponse?: {
    code?: string;
  };
  status?: string;
};

declare global {
  interface Window {
    FB?: {
      init: (options: Record<string, unknown>) => void;
      login: (
        callback: (response: MetaLoginResponse) => void,
        options: Record<string, unknown>
      ) => void;
    };
    fbAsyncInit?: () => void;
  }
}

export default function WhatsappSettingsPage() {
  const [tenantId, setTenantId] = useState<string | null>(null);
  const [channels, setChannels] = useState<ChannelRow[]>([]);
  const [professionals, setProfessionals] = useState<ProfessionalRow[]>([]);
  const [integration, setIntegration] = useState<IntegrationRow | null>(null);

  const [editingId, setEditingId] = useState<string | null>(null);
  const [label, setLabel] = useState("Canal principal");
  const [whatsappNumber, setWhatsappNumber] = useState("");
  const [phoneNumberId, setPhoneNumberId] = useState("");
  const [professionalId, setProfessionalId] = useState("");
  const [active, setActive] = useState(true);
  const [aiEnabled, setAiEnabled] = useState(true);
  const [audioEnabled, setAudioEnabled] = useState(true);
  const [aiModel, setAiModel] = useState("gpt-4.1-mini");
  const [aiPrompt, setAiPrompt] = useState(DEFAULT_PROMPT);
  const [showAdvancedSettings, setShowAdvancedSettings] = useState(false);

  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [connectingMeta, setConnectingMeta] = useState(false);
  const [disconnectingMeta, setDisconnectingMeta] = useState(false);
  const [metaSdkReady, setMetaSdkReady] = useState(false);

  const latestMetaCodeRef = useRef<string | null>(null);

  function friendlyPostgrestMessage(error: { message?: string | null; details?: string | null; code?: string | null }) {
    const message = (error.message ?? "").toLowerCase();
    const details = (error.details ?? "").toLowerCase();

    if (error.code === "23505" || message.includes("duplicate key") || details.includes("already exists")) {
      if (message.includes("phone_number_id")) {
        return "Esse numero da Meta ja esta conectado em outro canal.";
      }
      if (message.includes("professional_id")) {
        return "Ja existe um canal vinculado a esse profissional.";
      }
      return "Ja existe um cadastro igual a esse. Revise os dados e tente novamente.";
    }

    if (message.includes("row-level security") || message.includes("permission denied")) {
      return "Voce nao tem permissao para alterar essa configuracao. Entre com um perfil administrador.";
    }

    return "Nao foi possivel salvar a configuracao agora. Tente novamente em instantes.";
  }

  function integrationStatusLabel(status: IntegrationRow["connection_status"] | null | undefined) {
    switch (status) {
      case "connected":
        return "Conectada";
      case "pending":
        return "Pendente";
      case "error":
        return "Com erro";
      case "disconnected":
        return "Desconectada";
      default:
        return "Nao conectada";
    }
  }

  function integrationStatusDescription(status: IntegrationRow["connection_status"] | null | undefined) {
    switch (status) {
      case "connected":
        return "A conta Meta esta pronta e o numero ja pode ser usado pelo app.";
      case "pending":
        return "A conexao foi iniciada, mas ainda faltam dados ou credenciais para liberar o canal.";
      case "error":
        return "A Meta retornou um problema na conexao. Revise a integracao e tente novamente.";
      case "disconnected":
        return "A conta foi desconectada. Conecte novamente para voltar a usar o WhatsApp.";
      default:
        return "Ainda nao existe uma conta Meta conectada para esta organizacao.";
    }
  }

  async function loadAll() {
    const supabase = getSupabaseBrowserClient();
    const table = (supabase as any).from("whatsapp_channel_settings");

    const [
      { data: channelRows, error: channelError },
      { data: professionalRows, error: professionalError },
      { data: integrationRow, error: integrationError }
    ] =
      await Promise.all([
        table
          .select(
            "id, label, whatsapp_number, phone_number_id, active, ai_enabled, audio_enabled, ai_model, ai_system_prompt, professional_id, professionals(name)"
          )
          .order("created_at", { ascending: true }),
        supabase.from("professionals").select("id, name, active").order("name"),
        (supabase as any)
          .from("whatsapp_meta_integrations")
          .select(
            "id, connection_status, whatsapp_number, meta_phone_number_id, meta_business_account_id, verified_name, display_name, account_label, last_error"
          )
          .maybeSingle()
      ]);

    if (channelError) {
      setError(channelError.message);
      return;
    }
    if (professionalError) {
      setError(professionalError.message);
      return;
    }
    if (integrationError) {
      setError(integrationError.message);
      return;
    }

    setChannels((channelRows ?? []) as ChannelRow[]);
    setProfessionals((professionalRows ?? []) as ProfessionalRow[]);
    setIntegration((integrationRow ?? null) as IntegrationRow | null);
  }

  const persistMetaCompletion = useCallback(async (payload: {
    event: string;
    code?: string | null;
    error?: string | null;
    sessionInfo?: MetaEmbeddedSignupEventPayload["data"];
  }) => {
    const response = await fetch("/api/whatsapp/meta/complete", {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify(payload)
    });

    const responseBody = (await response.json().catch(() => ({}))) as {
      error?: string;
      integration?: IntegrationRow | null;
    };

    if (!response.ok) {
      throw new Error(responseBody.error || "Nao foi possivel concluir a conexao com a Meta.");
    }

    setIntegration(responseBody.integration ?? null);
    setWhatsappNumber(responseBody.integration?.whatsapp_number ?? "");
    setPhoneNumberId(responseBody.integration?.meta_phone_number_id ?? "");
    await loadAll();
  }, []);

  /* eslint-disable react-hooks/exhaustive-deps */
  useEffect(() => {
    const supabase = getSupabaseBrowserClient();

    async function bootstrap() {
      setLoading(true);
      const { data, error: tenantError } = await supabase.rpc("auth_tenant_id");
      if (tenantError || !data) {
        setError("Nao foi possivel resolver a organizacao atual.");
        setLoading(false);
        return;
      }
      setTenantId(data);
      await loadAll();
      setLoading(false);
    }

    bootstrap();
  }, [persistMetaCompletion]);
  /* eslint-enable react-hooks/exhaustive-deps */

  useEffect(() => {
    if (!META_APP_ID || !META_EMBEDDED_SIGNUP_CONFIG_ID) return;
    if (typeof window === "undefined") return;

    let active = true;

    function markSdkReady() {
      if (!active) return;
      setMetaSdkReady(true);
    }

    if (window.FB) {
      markSdkReady();
      return () => {
        active = false;
      };
    }

    window.fbAsyncInit = () => {
      window.FB?.init({
        appId: META_APP_ID,
        autoLogAppEvents: true,
        xfbml: false,
        version: META_GRAPH_API_VERSION
      });
      markSdkReady();
    };

    const script = document.createElement("script");
    script.src = "https://connect.facebook.net/en_US/sdk.js";
    script.async = true;
    script.defer = true;
    script.crossOrigin = "anonymous";
    script.onerror = () => {
      if (!active) return;
      setError("Nao foi possivel carregar a conexao com a Meta. Tente novamente.");
    };
    document.body.appendChild(script);

    return () => {
      active = false;
    };
  }, []);

  useEffect(() => {
    if (typeof window === "undefined") return;

    async function handleMetaMessage(event: MessageEvent) {
      if (!String(event.origin).includes("facebook.com")) return;

      let payload: unknown = event.data;
      if (typeof payload === "string") {
        try {
          payload = JSON.parse(payload);
        } catch {
          return;
        }
      }

      if (!payload || typeof payload !== "object") return;
      const parsed = payload as MetaEmbeddedSignupEventPayload;
      if (parsed.type !== "WA_EMBEDDED_SIGNUP") return;

      if (parsed.event === "FINISH") {
        setConnectingMeta(true);
        setError(null);
        setStatus("Conta Meta recebida. Estamos concluindo a vinculacao...");
        try {
          await persistMetaCompletion({
            event: "FINISH",
            code: latestMetaCodeRef.current,
            sessionInfo: parsed.data
          });
          setStatus("Conta Meta conectada com sucesso.");
        } catch (error) {
          setError(error instanceof Error ? error.message : "Nao foi possivel concluir a conexao Meta.");
        } finally {
          setConnectingMeta(false);
          latestMetaCodeRef.current = null;
        }
        return;
      }

      if (parsed.event === "ERROR") {
        const message = parsed.error_message || "A Meta retornou um erro ao concluir a conexao.";
        setError(message);
        setConnectingMeta(false);
        latestMetaCodeRef.current = null;
        void persistMetaCompletion({ event: "ERROR", error: message, sessionInfo: parsed.data }).catch(() => null);
        return;
      }

      if (parsed.event === "CANCEL") {
        setStatus("Conexao com a Meta cancelada.");
        setConnectingMeta(false);
        latestMetaCodeRef.current = null;
      }
    }

    window.addEventListener("message", handleMetaMessage);
    return () => window.removeEventListener("message", handleMetaMessage);
  }, [persistMetaCompletion]);
  /* eslint-enable react-hooks/exhaustive-deps */

  function resetForm() {
    setEditingId(null);
    setLabel("Canal principal");
    setWhatsappNumber("");
    setPhoneNumberId("");
    setProfessionalId("");
    setActive(true);
    setAiEnabled(true);
    setAudioEnabled(true);
    setAiModel("gpt-4.1-mini");
    setAiPrompt(DEFAULT_PROMPT);
    setShowAdvancedSettings(false);
    setWhatsappNumber(integration?.whatsapp_number ?? "");
    setPhoneNumberId(integration?.meta_phone_number_id ?? "");
  }

  function startEdit(item: ChannelRow) {
    setEditingId(item.id);
    setLabel(item.label);
    setWhatsappNumber(item.whatsapp_number);
    setPhoneNumberId(item.phone_number_id);
    setProfessionalId(item.professional_id ?? "");
    setActive(item.active);
    setAiEnabled(item.ai_enabled);
    setAudioEnabled(item.audio_enabled);
    setAiModel(item.ai_model || "gpt-4.1-mini");
    setAiPrompt(item.ai_system_prompt || DEFAULT_PROMPT);
    setShowAdvancedSettings(false);
    setError(null);
    setStatus(null);
  }

  function handleConnectMeta() {
    setError(null);
    setStatus(null);

    if (!META_APP_ID || !META_EMBEDDED_SIGNUP_CONFIG_ID) {
      setError(
        "Falta configurar NEXT_PUBLIC_META_APP_ID e NEXT_PUBLIC_META_WHATSAPP_EMBEDDED_SIGNUP_CONFIG_ID no web."
      );
      return;
    }

    if (!window.FB || !metaSdkReady) {
      setError("A integracao com a Meta ainda esta carregando. Tente novamente em alguns segundos.");
      return;
    }

    setConnectingMeta(true);
    setStatus("Abrindo a conexao oficial da Meta...");
    latestMetaCodeRef.current = null;

    window.FB.login(
      (response) => {
        const authCode = response.authResponse?.code ?? null;
        latestMetaCodeRef.current = authCode;

        if (!authCode) {
          setConnectingMeta(false);
          setStatus("Janela da Meta aberta. Aguarde a conclusao do processo para vincular a conta.");
        }
      },
      {
        config_id: META_EMBEDDED_SIGNUP_CONFIG_ID,
        response_type: "code",
        override_default_response_type: true,
        extras: {
          feature: "whatsapp_embedded_signup",
          sessionInfoVersion: 3
        }
      }
    );
  }

  async function handleDisconnectMeta() {
    setError(null);
    setStatus(null);
    setDisconnectingMeta(true);

    try {
      const response = await fetch("/api/whatsapp/meta/disconnect", {
        method: "POST"
      });

      const responseBody = (await response.json().catch(() => ({}))) as {
        error?: string;
        integration?: IntegrationRow | null;
      };

      if (!response.ok) {
        throw new Error(responseBody.error || "Nao foi possivel desconectar a conta Meta.");
      }

      setIntegration(responseBody.integration ?? null);
      setWhatsappNumber("");
      setPhoneNumberId("");
      setStatus("Conta Meta desconectada com sucesso.");
      await loadAll();
    } catch (disconnectError) {
      setError(
        disconnectError instanceof Error
          ? disconnectError.message
          : "Nao foi possivel desconectar a conta Meta."
      );
    } finally {
      setDisconnectingMeta(false);
    }
  }

  async function handleSave(event: FormEvent) {
    event.preventDefault();
    setError(null);
    setStatus(null);

    if (!tenantId) return;
    if (!whatsappNumber.trim() || !phoneNumberId.trim()) {
      setError("Conclua primeiro a conexao da conta Meta para liberar o numero e o identificador tecnico.");
      return;
    }

    const supabase = getSupabaseBrowserClient();
    const table = (supabase as any).from("whatsapp_channel_settings");

    const payload = {
      tenant_id: tenantId,
      label: label.trim() || "Canal principal",
      whatsapp_number: whatsappNumber.trim(),
      phone_number_id: phoneNumberId.trim(),
      active,
      ai_enabled: aiEnabled,
      audio_enabled: audioEnabled,
      ai_model: aiModel.trim() || "gpt-4.1-mini",
      ai_system_prompt: aiPrompt.trim() || null,
      professional_id: professionalId || null,
      updated_at: new Date().toISOString()
    };

    const query = editingId ? table.update(payload).eq("id", editingId) : table.insert(payload);
    const { error: saveError } = await query;
    if (saveError) {
      setError(friendlyPostgrestMessage(saveError));
      return;
    }

    setStatus(editingId ? "Canal atualizado com sucesso." : "Canal cadastrado com sucesso.");
    resetForm();
    await loadAll();
  }

  async function handleDelete(id: string) {
    setError(null);
    setStatus(null);
    const supabase = getSupabaseBrowserClient();
    const table = (supabase as any).from("whatsapp_channel_settings");
    const { error: deleteError } = await table.delete().eq("id", id);
    if (deleteError) {
      setError(friendlyPostgrestMessage(deleteError));
      return;
    }
    setStatus("Canal removido.");
    if (editingId === id) resetForm();
    await loadAll();
  }

  if (loading) {
    return (
      <section className="page-stack">
        <div className="card">Carregando configuracoes do WhatsApp...</div>
      </section>
    );
  }

  return (
    <section className="page-stack">
      <div className="card col">
        <h1>WhatsApp + IA</h1>
        <p>Conecte a conta Meta do proprio cliente e use o WhatsApp dentro do Agenda Profissional.</p>
        <p className="text-muted">
          {channels.length === 0
            ? "Nesta fase deixamos a estrutura pronta para a conexao individual por tenant."
            : "Revise aqui o status da conexao Meta e as configuracoes do canal ativo."}
        </p>
        <div
          style={{
            padding: 12,
            borderRadius: 12,
            border: "1px solid rgba(31, 164, 169, 0.22)",
            background: "#FFFFFF"
          }}
        >
          <strong>Antes de ativar</strong>
          <p style={{ margin: "6px 0 0" }}>
            O caminho escalavel sera cada cliente conectar a propria conta Meta. Esta tela agora separa o estado da
            conexao Meta da configuracao do canal de atendimento.
          </p>
        </div>
      </div>

      <div className="card col">
        <h2>Conta Meta</h2>
        <p className="text-muted">
          Status atual: <strong>{integrationStatusLabel(integration?.connection_status)}</strong>
        </p>
        <p className="text-muted">{integrationStatusDescription(integration?.connection_status)}</p>
        <div className="row actions-row">
          <button
            type="button"
            onClick={handleConnectMeta}
            disabled={connectingMeta || disconnectingMeta || !META_APP_ID || !META_EMBEDDED_SIGNUP_CONFIG_ID}
          >
            {connectingMeta ? "Conectando..." : "Conectar conta Meta"}
          </button>
          {integration ? (
            <button
              type="button"
              className="secondary"
              onClick={handleDisconnectMeta}
              disabled={connectingMeta || disconnectingMeta}
            >
              {disconnectingMeta ? "Desconectando..." : "Desconectar"}
            </button>
          ) : null}
        </div>
        {!META_APP_ID || !META_EMBEDDED_SIGNUP_CONFIG_ID ? (
          <p className="text-muted">
            Para habilitar o fluxo oficial, configure `NEXT_PUBLIC_META_APP_ID` e
            `NEXT_PUBLIC_META_WHATSAPP_EMBEDDED_SIGNUP_CONFIG_ID` no web.
          </p>
        ) : null}
        {integration ? (
          <div className="col">
            <p>Número conectado: {integration.whatsapp_number || "Nao informado"}</p>
            <p>Nome verificado: {integration.verified_name || "Nao informado"}</p>
            <p>Conta: {integration.account_label || integration.display_name || "Nao informado"}</p>
            {integration.last_error ? <div className="error">{integration.last_error}</div> : null}
          </div>
        ) : (
          <div className="col">
            <p>Nenhuma conta Meta conectada para esta organizacao.</p>
            <p className="text-muted">
              Na proxima fase vamos abrir aqui o fluxo oficial de conexao via Embedded Signup da Meta.
            </p>
          </div>
        )}
      </div>

      <div className="card col">
        <h2>{editingId ? "Editar canal" : "Novo canal"}</h2>
        {!integration || integration.connection_status !== "connected" ? (
          <div className="col">
            <p>Conecte primeiro a conta Meta da organizacao para liberar a configuracao do canal.</p>
            <p className="text-muted">
              Quando a conexao estiver pronta, o numero e o identificador tecnico serao preenchidos a partir dessa
              integracao.
            </p>
          </div>
        ) : (
        <form className="col" onSubmit={handleSave}>
          <p className="text-muted">Com a conta Meta conectada, aqui voce ajusta o uso do canal dentro do app.</p>
          <div className="row">
            <label className="col">
              Nome do canal
              <input value={label} onChange={(e) => setLabel(e.target.value)} placeholder="Ex.: Recepcao principal" />
            </label>
            <label className="col">
              Numero de WhatsApp
              <input
                value={whatsappNumber}
                onChange={(e) => setWhatsappNumber(e.target.value)}
                placeholder="Ex.: +5511999999999"
                required
                disabled
              />
              <small className="text-muted">Esse numero vem da conta Meta conectada.</small>
            </label>
          </div>

          <div className="row">
            <label className="col">
              Profissional (opcional)
              <select value={professionalId} onChange={(e) => setProfessionalId(e.target.value)}>
                <option value="">Canal geral da organizacao</option>
                {professionals
                  .filter((item) => item.active)
                  .map((item) => (
                    <option key={item.id} value={item.id}>
                      {item.name}
                    </option>
                  ))}
              </select>
            </label>
          </div>

          <div className="row whatsapp-toggle-row">
            <label className="checkbox-row">
              <input type="checkbox" checked={active} onChange={(e) => setActive(e.target.checked)} />
              Canal ativo
            </label>
            <label className="checkbox-row">
              <input type="checkbox" checked={aiEnabled} onChange={(e) => setAiEnabled(e.target.checked)} />
              Responder com IA
            </label>
            <label className="checkbox-row">
              <input type="checkbox" checked={audioEnabled} onChange={(e) => setAudioEnabled(e.target.checked)} />
              Aceitar audio
            </label>
          </div>

          <details open={showAdvancedSettings} onToggle={(e) => setShowAdvancedSettings(e.currentTarget.open)}>
            <summary style={{ cursor: "pointer", fontWeight: 500 }}>Configuracoes avancadas</summary>
            <div className="col" style={{ marginTop: 12 }}>
              <label className="col">
                Codigo de conexao do numero (Meta)
                <input
                  value={phoneNumberId}
                  onChange={(e) => setPhoneNumberId(e.target.value)}
                  placeholder="Ex.: 123456789012345"
                  disabled
                />
                <small className="text-muted">
                  Esse identificador tecnico vem da conexao Meta do tenant.
                </small>
              </label>

              <label className="col">
                Modelo de IA
                <input value={aiModel} onChange={(e) => setAiModel(e.target.value)} placeholder="gpt-4.1-mini" />
                <small className="text-muted">Recomendado manter o padrao.</small>
              </label>

              <label className="col">
                Instrucoes da IA
                <textarea
                  rows={6}
                  value={aiPrompt}
                  onChange={(e) => setAiPrompt(e.target.value)}
                  placeholder="Instrucoes do atendimento automatico para esse numero."
                />
                <small className="text-muted">Altere apenas se quiser personalizar a forma de atendimento.</small>
              </label>
            </div>
          </details>

          <div className="row actions-row">
            <button type="submit">{editingId ? "Salvar canal" : "Cadastrar canal"}</button>
            {editingId ? (
              <button type="button" className="secondary" onClick={resetForm}>
                Cancelar edicao
              </button>
            ) : null}
          </div>
        </form>
        )}
      </div>

      {status ? <div className="notice">{status}</div> : null}
      {error ? <div className="error">{error}</div> : null}

      <div className="card col">
        <h2>Canais cadastrados</h2>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Canal</th>
                <th>Numero</th>
                <th>Conexao Meta</th>
                <th>Profissional</th>
                <th>Status</th>
                <th>IA</th>
                <th>Audio</th>
                <th>Acoes</th>
              </tr>
            </thead>
            <tbody>
              {channels.map((item) => (
                <tr key={item.id}>
                  <td>{item.label}</td>
                  <td>{formatPhone(item.whatsapp_number) || item.whatsapp_number || "-"}</td>
                  <td>{item.phone_number_id ? "Configurado" : "-"}</td>
                  <td>{item.professionals?.name ?? "Geral"}</td>
                  <td>{item.active ? "Ativo" : "Inativo"}</td>
                  <td>{item.ai_enabled ? "Ligada" : "Desligada"}</td>
                  <td>{item.audio_enabled ? "Ligado" : "Desligado"}</td>
                  <td>
                    <div className="row actions-row">
                      <button type="button" className="secondary" onClick={() => startEdit(item)}>
                        Editar
                      </button>
                      <button type="button" className="danger" onClick={() => handleDelete(item.id)}>
                        Excluir
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
              {channels.length === 0 ? (
                <tr>
                  <td colSpan={8}>Nenhum canal cadastrado.</td>
                </tr>
              ) : null}
            </tbody>
          </table>
        </div>
      </div>

      <div className="card col">
        <h2>{channels.length === 0 ? "Primeira ativacao" : "Como ativar um novo canal"}</h2>
        <div className="col">
          <p>
            <strong>1. Conecte a conta Meta da organizacao</strong>
          </p>
          <ul className="whatsapp-checklist">
            <li>Cada organizacao vai conectar a propria conta Meta ao app.</li>
            <li>Na proxima fase, essa conexao sera feita pelo fluxo oficial Embedded Signup da Meta.</li>
          </ul>

          <p>
            <strong>2. Revise os dados do numero conectado</strong>
          </p>
          <ul className="whatsapp-checklist">
            <li>Depois da conexao, o numero e o identificador tecnico vao aparecer automaticamente nesta tela.</li>
            <li>O usuario nao deve preencher o ID tecnico da Meta manualmente.</li>
          </ul>

          <p>
            <strong>3. Configure o canal dentro do app</strong>
          </p>
          <ul className="whatsapp-checklist">
            <li>Defina nome do canal, profissional responsavel e se o atendimento vai usar IA e audio.</li>
            <li>Depois disso, vale fazer um teste de mensagem para validar o atendimento e o roteamento.</li>
          </ul>
        </div>
      </div>
    </section>
  );
}
