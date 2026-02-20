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

type ServiceLocationRow = {
  id: string;
  professional_id: string | null;
  name: string;
  address_line: string;
  city: string;
  state: string;
  postal_code: string | null;
  country: string;
  latitude: number | null;
  longitude: number | null;
  is_active: boolean;
};

type ServiceLocationDraft = {
  id: string | null;
  name: string;
  addressLine: string;
  city: string;
  state: string;
  postalCode: string;
  country: string;
  latitude: string;
  longitude: string;
  isActive: boolean;
};

function createDefaultServiceLocationDraft(): ServiceLocationDraft {
  return {
    id: null,
    name: "Endereço principal",
    addressLine: "",
    city: "",
    state: "",
    postalCode: "",
    country: "BR",
    latitude: "",
    longitude: "",
    isActive: true
  };
}

export default function ProfessionalsPage() {
  const [professionals, setProfessionals] = useState<ProfessionalRow[]>([]);
  const [services, setServices] = useState<ServiceRow[]>([]);
  const [links, setLinks] = useState<ProfessionalServiceRow[]>([]);
  const [serviceLocationDrafts, setServiceLocationDrafts] = useState<Record<string, ServiceLocationDraft>>({});
  const [tenantId, setTenantId] = useState<string | null>(null);

  const [name, setName] = useState("");
  const [editingProfessionalId, setEditingProfessionalId] = useState<string | null>(null);
  const [editingAddressProfessionalId, setEditingAddressProfessionalId] = useState<string | null>(null);
  const [editProfessionalName, setEditProfessionalName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);

  async function load() {
    const supabase = getSupabaseBrowserClient();
    const [
      { data: professionalsData, error: professionalsError },
      { data: servicesData, error: servicesError },
      { data: linksData, error: linksError },
      { data: serviceLocationsData, error: serviceLocationsError }
    ] = await Promise.all([
      supabase.from("professionals").select("id, name, active").order("name"),
      supabase.from("services").select("id, name, active").order("name"),
      supabase.from("professional_services").select("professional_id, service_id"),
      (supabase as any)
        .from("service_locations")
        .select(
          "id, professional_id, name, address_line, city, state, postal_code, country, latitude, longitude, is_active"
        )
        .not("professional_id", "is", null)
        .order("updated_at", { ascending: false })
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
    if (serviceLocationsError) {
      setError(serviceLocationsError.message);
      return;
    }

    const professionalRows = (professionalsData ?? []) as ProfessionalRow[];
    const locationByProfessional = new Map<string, ServiceLocationRow>();
    for (const row of (serviceLocationsData ?? []) as ServiceLocationRow[]) {
      if (!row.professional_id) continue;
      if (!locationByProfessional.has(row.professional_id)) {
        locationByProfessional.set(row.professional_id, row);
      }
    }
    const nextDrafts: Record<string, ServiceLocationDraft> = {};
    for (const professional of professionalRows) {
      const location = locationByProfessional.get(professional.id);
      nextDrafts[professional.id] = location
        ? {
            id: location.id,
            name: location.name,
            addressLine: location.address_line,
            city: location.city,
            state: location.state,
            postalCode: location.postal_code ?? "",
            country: location.country,
            latitude: location.latitude?.toString() ?? "",
            longitude: location.longitude?.toString() ?? "",
            isActive: location.is_active
          }
        : createDefaultServiceLocationDraft();
    }

    setProfessionals(professionalRows);
    setServices((servicesData ?? []) as ServiceRow[]);
    setLinks((linksData ?? []) as ProfessionalServiceRow[]);
    setServiceLocationDrafts(nextDrafts);
  }

  useEffect(() => {
    const supabase = getSupabaseBrowserClient();

    async function bootstrap() {
      const { data, error: tenantError } = await supabase.rpc("auth_tenant_id");
      if (tenantError || !data) {
        setError("Não foi possível resolver a organização atual.");
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

  function startEditingAddress(professionalId: string) {
    setEditingAddressProfessionalId(professionalId);
    setError(null);
    setStatus(null);
  }

  function cancelEditingAddress() {
    setEditingAddressProfessionalId(null);
    setError(null);
    setStatus(null);
  }

  function updateServiceLocationDraft(professionalId: string, patch: Partial<ServiceLocationDraft>) {
    setServiceLocationDrafts((prev) => ({
      ...prev,
      [professionalId]: {
        ...(prev[professionalId] ?? createDefaultServiceLocationDraft()),
        ...patch
      }
    }));
  }

  function parseLocationDraft(
    draft: ServiceLocationDraft,
    labelPrefix: string
  ): {
    payload: Record<string, unknown>;
    error: string | null;
  } {
    if (!draft.name.trim()) return { payload: {}, error: `${labelPrefix}: informe o nome do endereço.` };
    if (!draft.addressLine.trim()) return { payload: {}, error: `${labelPrefix}: informe o endereço.` };
    if (!draft.city.trim()) return { payload: {}, error: `${labelPrefix}: informe a cidade.` };
    if (!draft.state.trim()) return { payload: {}, error: `${labelPrefix}: informe o estado.` };
    if (!draft.country.trim()) return { payload: {}, error: `${labelPrefix}: informe o país.` };

    let lat: number | null = null;
    let lng: number | null = null;
    if (draft.latitude.trim() || draft.longitude.trim()) {
      lat = Number(draft.latitude);
      lng = Number(draft.longitude);
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
        return { payload: {}, error: `${labelPrefix}: latitude/longitude inválidas.` };
      }
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
        return { payload: {}, error: `${labelPrefix}: latitude/longitude fora de faixa.` };
      }
    }

    return {
      payload: {
        name: draft.name.trim(),
        address_line: draft.addressLine.trim(),
        city: draft.city.trim(),
        state: draft.state.trim(),
        postal_code: draft.postalCode.trim() || null,
        country: draft.country.trim().toUpperCase(),
        latitude: lat,
        longitude: lng,
        is_active: draft.isActive
      },
      error: null
    };
  }

  async function saveServiceLocation(professionalId: string): Promise<boolean> {
    if (!tenantId) return false;
    setError(null);
    setStatus(null);
    const draft = serviceLocationDrafts[professionalId] ?? createDefaultServiceLocationDraft();
    const parsed = parseLocationDraft(draft, "Endereço do profissional");
    if (parsed.error) {
      setError(parsed.error);
      return false;
    }

    const supabase = getSupabaseBrowserClient();
    const table = (supabase as any).from("service_locations");
    const payload = {
      tenant_id: tenantId,
      professional_id: professionalId,
      ...parsed.payload
    };
    const mutation = draft.id
      ? table.update(payload).eq("id", draft.id).eq("professional_id", professionalId)
      : table.insert(payload);
    const { error: mutationError } = await mutation;
    if (mutationError) {
      setError(mutationError.message);
      return false;
    }

    setStatus("Endereço de atendimento salvo.");
    await load();
    return true;
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
        <div className="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Profissional</th>
              <th>Status</th>
              <th>Serviços habilitados</th>
              <th>Endereço</th>
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
                  <div className="col checklist-grid">
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
                  {(() => {
                    const draft = serviceLocationDrafts[professional.id] ?? createDefaultServiceLocationDraft();
                    const summary = draft.addressLine.trim()
                      ? `${draft.city || "-"} / ${draft.state || "-"}`
                      : "Não cadastrado";
                    return (
                      <div className="col">
                        <span>{summary}</span>
                        <small className="text-muted">{draft.isActive ? "Ativo" : "Inativo"}</small>
                      </div>
                    );
                  })()}
                </td>
                <td>
                  <div className="row actions-row">
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
                    <button type="button" className="secondary" onClick={() => startEditingAddress(professional.id)}>
                      Endereço
                    </button>
                  </div>
                </td>
              </tr>
            ))}
            {professionals.length === 0 ? (
              <tr>
                <td colSpan={5}>Nenhum profissional cadastrado.</td>
              </tr>
            ) : null}
          </tbody>
        </table>
        </div>
      </div>

      {editingAddressProfessionalId ? (
        <div className="card col">
          <div className="row align-center justify-between">
            <h2>
              Endereço de atendimento
              {" - "}
              {professionals.find((item) => item.id === editingAddressProfessionalId)?.name ?? "Profissional"}
            </h2>
            <div className="row actions-row">
              <button type="button" onClick={() => saveServiceLocation(editingAddressProfessionalId)}>
                Salvar endereço
              </button>
              <button type="button" className="secondary" onClick={cancelEditingAddress}>
                Fechar
              </button>
            </div>
          </div>
          {(() => {
            const draft = serviceLocationDrafts[editingAddressProfessionalId] ?? createDefaultServiceLocationDraft();
            return (
              <>
                <div className="absence-grid">
                  <label className="col">
                    Nome do local
                    <input
                      value={draft.name}
                      onChange={(e) =>
                        updateServiceLocationDraft(editingAddressProfessionalId, { name: e.target.value })
                      }
                      placeholder="Ex.: Sala 02"
                    />
                  </label>
                  <label className="col absence-reason">
                    Endereço
                    <input
                      value={draft.addressLine}
                      onChange={(e) =>
                        updateServiceLocationDraft(editingAddressProfessionalId, { addressLine: e.target.value })
                      }
                      placeholder="Rua, número e complemento"
                    />
                  </label>
                  <label className="col">
                    Cidade
                    <input
                      value={draft.city}
                      onChange={(e) =>
                        updateServiceLocationDraft(editingAddressProfessionalId, { city: e.target.value })
                      }
                    />
                  </label>
                  <label className="col">
                    Estado
                    <input
                      value={draft.state}
                      onChange={(e) =>
                        updateServiceLocationDraft(editingAddressProfessionalId, { state: e.target.value })
                      }
                    />
                  </label>
                  <label className="col">
                    CEP
                    <input
                      value={draft.postalCode}
                      onChange={(e) =>
                        updateServiceLocationDraft(editingAddressProfessionalId, { postalCode: e.target.value })
                      }
                    />
                  </label>
                  <label className="col">
                    País
                    <input
                      value={draft.country}
                      onChange={(e) =>
                        updateServiceLocationDraft(editingAddressProfessionalId, { country: e.target.value })
                      }
                    />
                  </label>
                  <label className="col">
                    Latitude (opcional)
                    <input
                      value={draft.latitude}
                      onChange={(e) =>
                        updateServiceLocationDraft(editingAddressProfessionalId, { latitude: e.target.value })
                      }
                      placeholder="-23.56321"
                    />
                  </label>
                  <label className="col">
                    Longitude (opcional)
                    <input
                      value={draft.longitude}
                      onChange={(e) =>
                        updateServiceLocationDraft(editingAddressProfessionalId, { longitude: e.target.value })
                      }
                      placeholder="-46.65425"
                    />
                  </label>
                </div>
                <label className="checkbox-row">
                  <input
                    type="checkbox"
                    checked={draft.isActive}
                    onChange={(e) =>
                      updateServiceLocationDraft(editingAddressProfessionalId, { isActive: e.target.checked })
                    }
                  />
                  Endereço ativo
                </label>
                <small className="text-muted">
                  Se não houver endereço ativo do profissional, o sistema usa o endereço padrão da empresa.
                </small>
              </>
            );
          })()}
        </div>
      ) : null}
    </section>
  );
}



