"use client";

import { FormEvent, useEffect, useState } from "react";
import { getSupabaseBrowserClient } from "@/lib/supabase-browser";
import { formatPhone, normalizePhone } from "@/lib/phone";

type ClientRow = {
  id: string;
  full_name: string;
  phone: string | null;
  email: string | null;
  notes: string | null;
  birthday: string | null;
  preferred_contact_channel: string | null;
  location_sharing_enabled: boolean;
  location_sharing_authorized_at: string | null;
};

function todayDateInput() {
  return new Date().toISOString().slice(0, 10);
}

function toAuthorizedAtIso(value: string) {
  if (!value) return null;
  return `${value}T12:00:00.000Z`;
}

function formatBirthday(value: string | null) {
  if (!value) return "-";
  const date = new Date(value + "T12:00:00");
  if (Number.isNaN(date.getTime())) return "-";
  return new Intl.DateTimeFormat("pt-BR", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric"
  }).format(date);
}

function formatAuthorizedAt(value: string | null) {
  if (!value) return "-";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "-";
  return new Intl.DateTimeFormat("pt-BR", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric"
  }).format(date);
}

function mapClientSchemaError(error: unknown, fallback: string) {
  const message = error instanceof Error ? error.message : String(error);
  const normalized = message.toLowerCase();

  if (
    normalized.includes("birthday") ||
    normalized.includes("email") ||
    normalized.includes("preferred_contact_channel") ||
    normalized.includes("location_sharing_enabled") ||
    normalized.includes("location_sharing_authorized_at")
  ) {
    return "O banco de dados ainda nao foi atualizado para a tela de clientes. Aplique as migrations pendentes do Supabase e tente novamente.";
  }

  return `${fallback}${message}`;
}

export default function ClientsPage() {
  const [clients, setClients] = useState<ClientRow[]>([]);
  const [fullName, setFullName] = useState("");
  const [phone, setPhone] = useState("");
  const [email, setEmail] = useState("");
  const [notes, setNotes] = useState("");
  const [birthday, setBirthday] = useState("");
  const [preferredContactChannel, setPreferredContactChannel] = useState("whatsapp");
  const [locationSharingEnabled, setLocationSharingEnabled] = useState(false);
  const [locationSharingAuthorizedAt, setLocationSharingAuthorizedAt] = useState("");
  const [status, setStatus] = useState<string | null>(null);
  const [editingClientId, setEditingClientId] = useState<string | null>(null);
  const [editFullName, setEditFullName] = useState("");
  const [editPhone, setEditPhone] = useState("");
  const [editEmail, setEditEmail] = useState("");
  const [editNotes, setEditNotes] = useState("");
  const [editBirthday, setEditBirthday] = useState("");
  const [editPreferredContactChannel, setEditPreferredContactChannel] = useState("whatsapp");
  const [editLocationSharingEnabled, setEditLocationSharingEnabled] = useState(false);
  const [editLocationSharingAuthorizedAt, setEditLocationSharingAuthorizedAt] = useState("");
  const [error, setError] = useState<string | null>(null);

  async function load() {
    const supabase = getSupabaseBrowserClient();
    const { data, error: queryError } = await supabase
      .from("clients")
      .select("id, full_name, phone, email, notes, birthday, preferred_contact_channel, location_sharing_enabled, location_sharing_authorized_at")
      .order("created_at", { ascending: false });

    if (queryError) {
      setError(mapClientSchemaError(queryError, "Erro ao carregar clientes: "));
      return;
    }

    setClients((data ?? []) as ClientRow[]);
  }

  useEffect(() => {
    load();
  }, []);

  async function handleCreate(event: FormEvent) {
    event.preventDefault();
    setError(null);
    setStatus(null);

    const supabase = getSupabaseBrowserClient();
    const { data: tenantId, error: tenantError } = await supabase.rpc("auth_tenant_id");
    if (tenantError || !tenantId) {
      setError("Não foi possível resolver a organização atual.");
      return;
    }

    const { error: insertError } = await supabase.from("clients").insert({
      tenant_id: tenantId,
      full_name: fullName.trim(),
      phone: normalizePhone(phone) || null,
      email: email.trim() || null,
      notes: notes.trim() || null,
      birthday: birthday || null,
      preferred_contact_channel: preferredContactChannel,
      location_sharing_enabled: locationSharingEnabled,
      location_sharing_authorized_at: locationSharingEnabled
        ? toAuthorizedAtIso(locationSharingAuthorizedAt || todayDateInput())
        : null
    } as any);

    if (insertError) {
      setError(mapClientSchemaError(insertError, "Erro ao cadastrar cliente: "));
      return;
    }

    setFullName("");
    setPhone("");
    setEmail("");
    setNotes("");
    setBirthday("");
    setPreferredContactChannel("whatsapp");
    setLocationSharingEnabled(false);
    setLocationSharingAuthorizedAt("");
    setStatus("Cliente cadastrado.");
    load();
  }

  function startEditing(client: ClientRow) {
    setEditingClientId(client.id);
    setEditFullName(client.full_name);
    setEditPhone(formatPhone(client.phone ?? ""));
    setEditEmail(client.email ?? "");
    setEditNotes(client.notes ?? "");
    setEditBirthday(client.birthday?.slice(0, 10) ?? "");
    setEditPreferredContactChannel(client.preferred_contact_channel ?? "whatsapp");
    setEditLocationSharingEnabled(client.location_sharing_enabled);
    setEditLocationSharingAuthorizedAt(client.location_sharing_authorized_at?.slice(0, 10) ?? "");
    setError(null);
    setStatus(null);
  }

  function cancelEditing() {
    setEditingClientId(null);
    setEditFullName("");
    setEditPhone("");
    setEditEmail("");
    setEditNotes("");
    setEditBirthday("");
    setEditPreferredContactChannel("whatsapp");
    setEditLocationSharingEnabled(false);
    setEditLocationSharingAuthorizedAt("");
  }

  async function saveEditing(clientId: string) {
    setError(null);
    setStatus(null);

    const supabase = getSupabaseBrowserClient();
    const { error: updateError } = await supabase
      .from("clients")
      .update({
        full_name: editFullName.trim(),
        phone: normalizePhone(editPhone) || null,
        email: editEmail.trim() || null,
        notes: editNotes.trim() || null,
        birthday: editBirthday || null,
        preferred_contact_channel: editPreferredContactChannel,
        location_sharing_enabled: editLocationSharingEnabled,
        location_sharing_authorized_at: editLocationSharingEnabled
          ? toAuthorizedAtIso(editLocationSharingAuthorizedAt || todayDateInput())
          : null
      } as any)
      .eq("id", clientId);

    if (updateError) {
      setError(mapClientSchemaError(updateError, "Erro ao atualizar cliente: "));
      return;
    }

    setStatus("Cliente atualizado.");
    cancelEditing();
    await load();
  }

  return (
    <section className="page-stack">
      <div className="card">
        <h1>Clientes</h1>
        <form className="col" onSubmit={handleCreate}>
          <label className="col">
            Nome completo
            <input value={fullName} onChange={(e) => setFullName(e.target.value)} required />
          </label>

          <label className="col">
            Telefone
            <input
              value={phone}
              onChange={(e) => setPhone(formatPhone(e.target.value))}
              inputMode="tel"
              placeholder="(11) 99999-9999"
            />
          </label>

          <label className="col">
            E-mail
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="cliente@exemplo.com"
            />
          </label>

          <label className="col">
            Canal de contato preferido
            <select
              value={preferredContactChannel}
              onChange={(e) => setPreferredContactChannel(e.target.value)}
            >
              <option value="whatsapp">WhatsApp</option>
              <option value="phone">Ligação</option>
              <option value="email">E-mail</option>
            </select>
          </label>

          <label className="col">
            Observações
            <textarea value={notes} onChange={(e) => setNotes(e.target.value)} rows={3} />
          </label>

          <label className="col">
            Aniversário
            <input
              type="date"
              value={birthday}
              onChange={(e) => setBirthday(e.target.value)}
            />
          </label>

          <label className="row">
            <input
              type="checkbox"
              checked={locationSharingEnabled}
              onChange={(e) => {
                const checked = e.target.checked;
                setLocationSharingEnabled(checked);
                setLocationSharingAuthorizedAt((current) =>
                  checked ? current || todayDateInput() : ""
                );
              }}
            />
            Partilha de localização autorizada
          </label>

          {locationSharingEnabled ? (
            <label className="col">
              Data da autorização
              <input
                type="date"
                value={locationSharingAuthorizedAt}
                onChange={(e) => setLocationSharingAuthorizedAt(e.target.value)}
              />
            </label>
          ) : null}

          <button type="submit">Cadastrar cliente</button>
        </form>
      </div>

      {status ? <div className="notice">{status}</div> : null}
      {error ? <div className="error">{error}</div> : null}

      <div className="card">
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Nome</th>
                <th>Telefone</th>
                <th>E-mail</th>
                <th>Aniversário</th>
                <th>Contato preferido</th>
                <th>Localização</th>
                <th>Autorizado em</th>
                <th>Notas</th>
                <th>Ações</th>
              </tr>
            </thead>
            <tbody>
              {clients.map((client) => {
                const isEditing = editingClientId === client.id;
                return (
                  <tr key={client.id}>
                    <td>
                      {isEditing ? (
                        <input
                          value={editFullName}
                          onChange={(e) => setEditFullName(e.target.value)}
                          title="Nome do cliente"
                        />
                      ) : (
                        client.full_name
                      )}
                    </td>
                    <td>
                      {isEditing ? (
                        <input
                          value={editPhone}
                          onChange={(e) => setEditPhone(formatPhone(e.target.value))}
                          inputMode="tel"
                          placeholder="(11) 99999-9999"
                          title="Telefone do cliente"
                        />
                      ) : (
                        formatPhone(client.phone ?? "") || "-"
                      )}
                    </td>
                    <td>
                      {isEditing ? (
                        <input
                          type="email"
                          value={editEmail}
                          onChange={(e) => setEditEmail(e.target.value)}
                          title="E-mail do cliente"
                        />
                      ) : (
                        client.email ?? "-"
                      )}
                    </td>
                    <td>
                      {isEditing ? (
                        <input
                          type="date"
                          value={editBirthday}
                          onChange={(e) => setEditBirthday(e.target.value)}
                          title="Aniversário do cliente"
                        />
                      ) : (
                        formatBirthday(client.birthday)
                      )}
                    </td>
                    <td>
                      {isEditing ? (
                        <select
                          value={editPreferredContactChannel}
                          onChange={(e) => setEditPreferredContactChannel(e.target.value)}
                          title="Canal de contato preferido"
                        >
                          <option value="whatsapp">WhatsApp</option>
                          <option value="phone">Ligação</option>
                          <option value="email">E-mail</option>
                        </select>
                      ) : client.preferred_contact_channel === "email" ? (
                        "E-mail"
                      ) : client.preferred_contact_channel === "phone" ? (
                        "Ligação"
                      ) : (
                        "WhatsApp"
                      )}
                    </td>
                    <td>
                      {isEditing ? (
                        <label className="row">
                          <input
                            type="checkbox"
                            checked={editLocationSharingEnabled}
                            onChange={(e) => {
                              const checked = e.target.checked;
                              setEditLocationSharingEnabled(checked);
                              setEditLocationSharingAuthorizedAt((current) =>
                                checked ? current || todayDateInput() : ""
                              );
                            }}
                          />
                          Autorizada
                        </label>
                      ) : client.location_sharing_enabled ? (
                        "Autorizada"
                      ) : (
                        "Não autorizada"
                      )}
                    </td>
                    <td>
                      {isEditing ? (
                        <input
                          type="date"
                          value={editLocationSharingAuthorizedAt}
                          onChange={(e) => setEditLocationSharingAuthorizedAt(e.target.value)}
                          disabled={!editLocationSharingEnabled}
                          title="Data da autorização da localização"
                        />
                      ) : (
                        formatAuthorizedAt(client.location_sharing_authorized_at)
                      )}
                    </td>
                    <td>
                      {isEditing ? (
                        <input
                          value={editNotes}
                          onChange={(e) => setEditNotes(e.target.value)}
                          title="Observações do cliente"
                        />
                      ) : (
                        client.notes ?? "-"
                      )}
                    </td>
                    <td>
                      <div className="row actions-row">
                        {isEditing ? (
                          <>
                            <button type="button" onClick={() => saveEditing(client.id)}>
                              Salvar
                            </button>
                            <button type="button" className="secondary" onClick={cancelEditing}>
                              Cancelar
                            </button>
                          </>
                        ) : (
                          <button type="button" className="secondary" onClick={() => startEditing(client)}>
                            Editar
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                );
              })}
              {clients.length === 0 ? (
                <tr>
                  <td colSpan={9}>Nenhum cliente cadastrado.</td>
                </tr>
              ) : null}
            </tbody>
          </table>
        </div>
      </div>
    </section>
  );
}




