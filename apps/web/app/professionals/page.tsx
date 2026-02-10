"use client";

import { FormEvent, useEffect, useState } from "react";
import { getSupabaseBrowserClient } from "@/lib/supabase-browser";

type ProfessionalRow = {
  id: string;
  name: string;
  active: boolean;
};

type ServiceRow = {
  id: string;
  name: string;
  active: boolean;
};

type ProfessionalServiceRow = {
  professional_id: string;
  service_id: string;
};

export default function ProfessionalsPage() {
  const [professionals, setProfessionals] = useState<ProfessionalRow[]>([]);
  const [services, setServices] = useState<ServiceRow[]>([]);
  const [links, setLinks] = useState<ProfessionalServiceRow[]>([]);
  const [tenantId, setTenantId] = useState<string | null>(null);

  const [name, setName] = useState("");
  const [editingProfessionalId, setEditingProfessionalId] = useState<string | null>(null);
  const [editProfessionalName, setEditProfessionalName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);

  async function load() {
    const supabase = getSupabaseBrowserClient();
    const [
      { data: professionalsData, error: professionalsError },
      { data: servicesData, error: servicesError },
      { data: linksData, error: linksError }
    ] = await Promise.all([
      supabase.from("professionals").select("id, name, active").order("name"),
      supabase.from("services").select("id, name, active").order("name"),
      supabase.from("professional_services").select("professional_id, service_id")
    ]);

    if (professionalsError) {
      setError(professionalsError.message);
      return;
    }

    if (servicesError) {
      setError(servicesError.message);
      return;
    }

    if (linksError) {
      setError(linksError.message);
      return;
    }

    setProfessionals((professionalsData ?? []) as ProfessionalRow[]);
    setServices((servicesData ?? []) as ServiceRow[]);
    setLinks((linksData ?? []) as ProfessionalServiceRow[]);
  }

  useEffect(() => {
    const supabase = getSupabaseBrowserClient();

    async function bootstrap() {
      const { data, error: tenantError } = await supabase.rpc("auth_tenant_id");
      if (tenantError || !data) {
        setError("Nao foi possivel resolver a organizacao atual.");
        return;
      }

      setTenantId(data);
      await load();
    }

    bootstrap();
  }, []);

  async function handleCreate(event: FormEvent) {
    event.preventDefault();
    setError(null);
    setStatus(null);

    if (!tenantId) return;

    const supabase = getSupabaseBrowserClient();
    const { error: insertError } = await supabase.from("professionals").insert({
      tenant_id: tenantId,
      name: name.trim()
    });

    if (insertError) {
      setError(insertError.message);
      return;
    }

    setName("");
    setStatus("Profissional cadastrado.");
    await load();
  }

  async function toggleProfessionalActive(item: ProfessionalRow) {
    setError(null);
    setStatus(null);
    const supabase = getSupabaseBrowserClient();
    const { error: updateError } = await supabase
      .from("professionals")
      .update({ active: !item.active })
      .eq("id", item.id);

    if (updateError) {
      setError(updateError.message);
      return;
    }

    setStatus("Status do profissional atualizado.");
    await load();
  }

  function startEditingProfessional(item: ProfessionalRow) {
    setEditingProfessionalId(item.id);
    setEditProfessionalName(item.name);
    setError(null);
    setStatus(null);
  }

  function cancelEditingProfessional() {
    setEditingProfessionalId(null);
    setEditProfessionalName("");
  }

  async function saveEditingProfessional(item: ProfessionalRow) {
    setError(null);
    setStatus(null);

    const supabase = getSupabaseBrowserClient();
    const { error: updateError } = await supabase
      .from("professionals")
      .update({ name: editProfessionalName.trim() })
      .eq("id", item.id);

    if (updateError) {
      setError(updateError.message);
      return;
    }

    setStatus("Profissional atualizado.");
    cancelEditingProfessional();
    await load();
  }

  function hasService(professionalId: string, serviceId: string) {
    return links.some((item) => item.professional_id === professionalId && item.service_id === serviceId);
  }

  async function toggleServiceLink(professionalId: string, serviceId: string, enabled: boolean) {
    setError(null);
    setStatus(null);

    const supabase = getSupabaseBrowserClient();
    if (enabled) {
      if (!tenantId) return;
      const { error: upsertError } = await supabase.from("professional_services").upsert(
        {
          tenant_id: tenantId,
          professional_id: professionalId,
          service_id: serviceId
        },
        { onConflict: "tenant_id,professional_id,service_id" }
      );

      if (upsertError) {
        setError(upsertError.message);
        return;
      }
    } else {
      const { error: deleteError } = await supabase
        .from("professional_services")
        .delete()
        .eq("professional_id", professionalId)
        .eq("service_id", serviceId);

      if (deleteError) {
        setError(deleteError.message);
        return;
      }
    }

    await load();
  }

  return (
    <section className="page-stack">
      <div className="card">
        <h1>Profissionais</h1>
        <p>Cadastre profissionais e vincule quais serviços cada um executa.</p>
      </div>

      <div className="card">
        <h2>Novo profissional</h2>
        <form className="row" onSubmit={handleCreate}>
          <input placeholder="Nome do profissional" value={name} onChange={(e) => setName(e.target.value)} required />
          <button type="submit">Cadastrar profissional</button>
        </form>
      </div>

      {status ? <div className="notice">{status}</div> : null}
      {error ? <div className="error">{error}</div> : null}

      <div className="card">
        <h2>Lista de profissionais</h2>
        <table>
          <thead>
            <tr>
              <th>Profissional</th>
              <th>Status</th>
              <th>Serviços habilitados</th>
              <th>Ações</th>
            </tr>
          </thead>
          <tbody>
            {professionals.map((professional) => (
              <tr key={professional.id}>
                <td>
                  {editingProfessionalId === professional.id ? (
                    <input value={editProfessionalName} onChange={(e) => setEditProfessionalName(e.target.value)} />
                  ) : (
                    professional.name
                  )}
                </td>
                <td>{professional.active ? "Ativo" : "Inativo"}</td>
                <td>
                  <div className="col">
                    {services.map((service) => {
                      const checked = hasService(professional.id, service.id);
                      return (
                        <label key={service.id} className="row align-center">
                          <input
                            type="checkbox"
                            checked={checked}
                            onChange={(event) => toggleServiceLink(professional.id, service.id, event.target.checked)}
                          />
                          {service.name}
                          {!service.active ? " (inativo)" : ""}
                        </label>
                      );
                    })}
                  </div>
                </td>
                <td>
                  <div className="row">
                    {editingProfessionalId === professional.id ? (
                      <>
                        <button type="button" onClick={() => saveEditingProfessional(professional)}>
                          Salvar
                        </button>
                        <button type="button" className="secondary" onClick={cancelEditingProfessional}>
                          Cancelar
                        </button>
                      </>
                    ) : (
                      <button type="button" className="secondary" onClick={() => startEditingProfessional(professional)}>
                        Editar
                      </button>
                    )}
                    <button type="button" className="secondary" onClick={() => toggleProfessionalActive(professional)}>
                      {professional.active ? "Desativar" : "Ativar"}
                    </button>
                  </div>
                </td>
              </tr>
            ))}
            {professionals.length === 0 ? (
              <tr>
                <td colSpan={4}>Nenhum profissional cadastrado.</td>
              </tr>
            ) : null}
          </tbody>
        </table>
      </div>
    </section>
  );
}


