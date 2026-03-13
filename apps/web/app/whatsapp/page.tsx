"use client";

import { FormEvent, useEffect, useState } from "react";
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

const DEFAULT_PROMPT =
  "Você é a secretária virtual da Agenda Profissional. Cumprimente o cliente, pergunte a preferência de dia e horário, apresente opções disponíveis e confirme o agendamento somente após validação.";

export default function WhatsappSettingsPage() {
  const [tenantId, setTenantId] = useState<string | null>(null);
  const [channels, setChannels] = useState<ChannelRow[]>([]);
  const [professionals, setProfessionals] = useState<ProfessionalRow[]>([]);

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

  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  async function loadAll() {
    const supabase = getSupabaseBrowserClient();
    const table = (supabase as any).from("whatsapp_channel_settings");

    const [{ data: channelRows, error: channelError }, { data: professionalRows, error: professionalError }] =
      await Promise.all([
        table
          .select(
            "id, label, whatsapp_number, phone_number_id, active, ai_enabled, audio_enabled, ai_model, ai_system_prompt, professional_id, professionals(name)"
          )
          .order("created_at", { ascending: true }),
        supabase.from("professionals").select("id, name, active").order("name")
      ]);

    if (channelError) {
      setError(channelError.message);
      return;
    }
    if (professionalError) {
      setError(professionalError.message);
      return;
    }

    setChannels((channelRows ?? []) as ChannelRow[]);
    setProfessionals((professionalRows ?? []) as ProfessionalRow[]);
  }

  useEffect(() => {
    const supabase = getSupabaseBrowserClient();

    async function bootstrap() {
      setLoading(true);
      const { data, error: tenantError } = await supabase.rpc("auth_tenant_id");
      if (tenantError || !data) {
        setError("Não foi possível resolver a organização atual.");
        setLoading(false);
        return;
      }
      setTenantId(data);
      await loadAll();
      setLoading(false);
    }

    bootstrap();
  }, []);

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
    setError(null);
    setStatus(null);
  }

  async function handleSave(event: FormEvent) {
    event.preventDefault();
    setError(null);
    setStatus(null);

    if (!tenantId) return;
    if (!whatsappNumber.trim() || !phoneNumberId.trim()) {
      setError("Informe o número WhatsApp e o ID do número no Meta.");
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
      setError(saveError.message);
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
      setError(deleteError.message);
      return;
    }
    setStatus("Canal removido.");
    if (editingId === id) resetForm();
    await loadAll();
  }

  if (loading) {
    return (
      <section className="page-stack">
        <div className="card">Carregando configurações do WhatsApp...</div>
      </section>
    );
  }

  return (
    <section className="page-stack">
      <div className="card col">
        <h1>WhatsApp + IA</h1>
        <p>Cadastre o número oficial do profissional/clínica e habilite o atendimento automático pelo WhatsApp.</p>
        <p className="text-muted">
          {channels.length === 0
            ? "Primeiro cadastro? Siga as etapas abaixo para conectar o canal sem pular nenhuma configuração importante."
            : "Use este painel para cadastrar novos canais, revisar o status e ajustar IA, áudio e responsável do número."}
        </p>
      </div>

      <div className="card col">
        <h2>{editingId ? "Editar canal" : "Novo canal"}</h2>
        <form className="col" onSubmit={handleSave}>
          <div className="row">
            <label className="col">
              Nome do canal
              <input value={label} onChange={(e) => setLabel(e.target.value)} placeholder="Ex.: Canal principal" />
            </label>
            <label className="col">
              Número WhatsApp
              <input
                value={whatsappNumber}
                onChange={(e) => setWhatsappNumber(e.target.value)}
                placeholder="Ex.: +5511999999999"
                required
              />
            </label>
          </div>

          <div className="row">
            <label className="col">
              ID do número no Meta
              <input
                value={phoneNumberId}
                onChange={(e) => setPhoneNumberId(e.target.value)}
                placeholder="ID do número no Meta WhatsApp Cloud"
                required
              />
            </label>
            <label className="col">
              Profissional (opcional)
              <select value={professionalId} onChange={(e) => setProfessionalId(e.target.value)}>
                <option value="">Canal geral da organização</option>
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
              IA habilitada
            </label>
            <label className="checkbox-row">
              <input type="checkbox" checked={audioEnabled} onChange={(e) => setAudioEnabled(e.target.checked)} />
              Aceitar áudio
            </label>
          </div>

          <div className="row">
            <label className="col">
              Modelo de IA
              <input value={aiModel} onChange={(e) => setAiModel(e.target.value)} placeholder="gpt-4.1-mini" />
            </label>
          </div>

          <label className="col">
            Prompt da IA
            <textarea
              rows={6}
              value={aiPrompt}
              onChange={(e) => setAiPrompt(e.target.value)}
              placeholder="Instruções do atendimento automático para esse número."
            />
          </label>

          <div className="row actions-row">
            <button type="submit">{editingId ? "Salvar canal" : "Cadastrar canal"}</button>
            {editingId ? (
              <button type="button" className="secondary" onClick={resetForm}>
                Cancelar edicao
              </button>
            ) : null}
          </div>
        </form>
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
                <th>Número</th>
                <th>ID no Meta</th>
                <th>Profissional</th>
                <th>Status</th>
                <th>IA</th>
                <th>Áudio</th>
                <th>Ações</th>
              </tr>
            </thead>
            <tbody>
              {channels.map((item) => (
                <tr key={item.id}>
                  <td>{item.label}</td>
                  <td>{formatPhone(item.whatsapp_number) || item.whatsapp_number || "-"}</td>
                  <td>{item.phone_number_id}</td>
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
        <h2>{channels.length === 0 ? "Primeiro cadastro" : "Como ativar um novo canal"}</h2>
        <div className="col">
          <p>
            <strong>1. Separe os dados do canal</strong>
          </p>
          <ul className="whatsapp-checklist">
            <li>Tenha um número aprovado no WhatsApp Business Cloud.</li>
            <li>Copie o `ID do número no Meta` e confirme qual número será usado no atendimento.</li>
          </ul>

          <p>
            <strong>2. Cadastre o canal nesta tela</strong>
          </p>
          <ul className="whatsapp-checklist">
            <li>Preencha nome do canal, número WhatsApp e `ID do número no Meta` exatamente como aparece no Meta.</li>
            <li>Escolha um profissional se o número for exclusivo; deixe em geral se o canal atender a organização inteira.</li>
            <li>Marque `Canal ativo` para habilitar o recebimento.</li>
            <li>Marque `IA habilitada` para respostas automáticas e `Aceitar áudio` se quiser transcrever mensagens de voz.</li>
          </ul>

          <p>
            <strong>3. Conclua a ativacao</strong>
          </p>
          <ul className="whatsapp-checklist">
            <li>Salve o canal aqui no sistema.</li>
            <li>Envie uma mensagem de teste para validar recebimento, resposta da IA e roteamento do canal.</li>
            <li>Se o canal não responder após o cadastro, acione o suporte para revisar a integração técnica do ambiente.</li>
          </ul>
        </div>
      </div>
    </section>
  );
}

