"use client";

import { FormEvent, useEffect, useState } from "react";
import { getSupabaseBrowserClient } from "@/lib/supabase-browser";

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

    const supabase = getSupabaseBrowserClient();
    const { data: tenantId, error: tenantError } = await supabase.rpc("auth_tenant_id");
    if (tenantError || !tenantId) {
      setError("Não foi possível resolver o tenant atual.");
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
    load();
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
            <input value={phone} onChange={(e) => setPhone(e.target.value)} />
          </label>

          <label className="col">
            Observações
            <textarea value={notes} onChange={(e) => setNotes(e.target.value)} rows={3} />
          </label>

          <button type="submit">Cadastrar cliente</button>
        </form>
      </div>

      {error ? <div className="error">{error}</div> : null}

      <div className="card">
        <table>
          <thead>
            <tr>
              <th>Nome</th>
              <th>Telefone</th>
              <th>Notas</th>
            </tr>
          </thead>
          <tbody>
            {clients.map((client) => (
              <tr key={client.id}>
                <td>{client.full_name}</td>
                <td>{client.phone ?? "-"}</td>
                <td>{client.notes ?? "-"}</td>
              </tr>
            ))}
            {clients.length === 0 ? (
              <tr>
                <td colSpan={3}>Nenhum cliente cadastrado.</td>
              </tr>
            ) : null}
          </tbody>
        </table>
      </div>
    </section>
  );
}



