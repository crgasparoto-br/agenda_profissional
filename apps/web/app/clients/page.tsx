"use client";

import { FormEvent, useEffect, useState } from "react";
import { getSupabaseBrowserClient } from "@/lib/supabase-browser";
import { formatPhone } from "@/lib/phone";

type ClientRow = {
  id: string;
  full_name: string;
  phone: string | null;
  notes: string | null;
};

export default function ClientsPage() {
  const [clients, setClients] = useState<ClientRow[]>([]);
  const [fullName, setFullName] = useState("");
  const [phone, setPhone] = useState("");
  const [notes, setNotes] = useState("");
  const [status, setStatus] = useState<string | null>(null);
  const [editingClientId, setEditingClientId] = useState<string | null>(null);
  const [editFullName, setEditFullName] = useState("");
  const [editPhone, setEditPhone] = useState("");
  const [editNotes, setEditNotes] = useState("");
  const [error, setError] = useState<string | null>(null);

  async function load() {
    const supabase = getSupabaseBrowserClient();
    const { data, error: queryError } = await supabase
      .from("clients")
      .select("id, full_name, phone, notes")
      .order("created_at", { ascending: false });

    if (queryError) {
      setError(queryError.message);
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
      setError("Nao foi possivel resolver a organizacao atual.");
      return;
    }

    const { error: insertError } = await supabase.from("clients").insert({
      tenant_id: tenantId,
      full_name: fullName,
      phone: phone || null,
      notes: notes || null
    });

    if (insertError) {
      setError(insertError.message);
      return;
    }

    setFullName("");
    setPhone("");
    setNotes("");
    setStatus("Cliente cadastrado.");
    load();
  }

  function startEditing(client: ClientRow) {
    setEditingClientId(client.id);
    setEditFullName(client.full_name);
    setEditPhone(client.phone ?? "");
    setEditNotes(client.notes ?? "");
    setError(null);
    setStatus(null);
  }

  function cancelEditing() {
    setEditingClientId(null);
    setEditFullName("");
    setEditPhone("");
    setEditNotes("");
  }

  async function saveEditing(clientId: string) {
    setError(null);
    setStatus(null);

    const supabase = getSupabaseBrowserClient();
    const { error: updateError } = await supabase
      .from("clients")
      .update({
        full_name: editFullName.trim(),
        phone: editPhone.trim() || null,
        notes: editNotes.trim() || null
      })
      .eq("id", clientId);

    if (updateError) {
      setError(updateError.message);
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
            Observações
            <textarea value={notes} onChange={(e) => setNotes(e.target.value)} rows={3} />
          </label>

          <button type="submit">Cadastrar cliente</button>
        </form>
      </div>

      {status ? <div className="notice">{status}</div> : null}
      {error ? <div className="error">{error}</div> : null}

      <div className="card">
        <table>
          <thead>
            <tr>
              <th>Nome</th>
              <th>Telefone</th>
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
                      <input value={editFullName} onChange={(e) => setEditFullName(e.target.value)} />
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
                      />
                    ) : (
                      client.phone ?? "-"
                    )}
                  </td>
                  <td>
                    {isEditing ? (
                      <input value={editNotes} onChange={(e) => setEditNotes(e.target.value)} />
                    ) : (
                      client.notes ?? "-"
                    )}
                  </td>
                  <td>
                    <div className="row">
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
                <td colSpan={4}>Nenhum cliente cadastrado.</td>
              </tr>
            ) : null}
          </tbody>
        </table>
      </div>
    </section>
  );
}



