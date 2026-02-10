"use client";

import { FormEvent, useEffect, useState } from "react";
import { getSupabaseBrowserClient } from "@/lib/supabase-browser";

type SpecialtyRow = {
  id: string;
  name: string;
  active: boolean;
};

type ServiceRow = {
  id: string;
  name: string;
  duration_min: number;
  price_cents: number | null;
  active: boolean;
  specialty_id: string | null;
  specialties: { name: string | null } | null;
};

export default function ServicesPage() {
  const [services, setServices] = useState<ServiceRow[]>([]);
  const [specialties, setSpecialties] = useState<SpecialtyRow[]>([]);
  const [tenantId, setTenantId] = useState<string | null>(null);

  const [specialtyName, setSpecialtyName] = useState("");
  const [serviceName, setServiceName] = useState("");
  const [durationMin, setDurationMin] = useState("30");
  const [price, setPrice] = useState("");
  const [serviceSpecialtyId, setServiceSpecialtyId] = useState("");
  const [editingSpecialtyId, setEditingSpecialtyId] = useState<string | null>(null);
  const [editSpecialtyName, setEditSpecialtyName] = useState("");
  const [editingServiceId, setEditingServiceId] = useState<string | null>(null);
  const [editServiceName, setEditServiceName] = useState("");
  const [editDurationMin, setEditDurationMin] = useState("30");
  const [editPrice, setEditPrice] = useState("");
  const [editServiceSpecialtyId, setEditServiceSpecialtyId] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);

  async function load() {
    const supabase = getSupabaseBrowserClient();
    const [{ data: specialtiesData, error: specialtiesError }, { data: servicesData, error: servicesError }] =
      await Promise.all([
        supabase.from("specialties").select("id, name, active").order("name"),
        supabase.from("services").select("id, name, duration_min, price_cents, active, specialty_id, specialties(name)").order("name")
      ]);

    if (specialtiesError) {
      setError(specialtiesError.message);
      return;
    }

    if (servicesError) {
      setError(servicesError.message);
      return;
    }

    setSpecialties((specialtiesData ?? []) as SpecialtyRow[]);
    setServices((servicesData ?? []) as ServiceRow[]);
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

  function parsePriceToCents(raw: string): number | null {
    if (!raw.trim()) return null;
    const normalized = raw.replace(",", ".");
    const parsed = Number.parseFloat(normalized);
    if (Number.isNaN(parsed) || parsed < 0) return null;
    return Math.round(parsed * 100);
  }

  function formatPriceFromCents(value: number | null) {
    if (value === null) return "";
    return (value / 100).toFixed(2);
  }

  async function handleCreateSpecialty(event: FormEvent) {
    event.preventDefault();
    setError(null);
    setStatus(null);

    if (!tenantId) return;

    const supabase = getSupabaseBrowserClient();
    const { error: insertError } = await supabase.from("specialties").insert({
      tenant_id: tenantId,
      name: specialtyName.trim()
    });

    if (insertError) {
      setError(insertError.message);
      return;
    }

    setSpecialtyName("");
    setStatus("Especialidade cadastrada.");
    await load();
  }

  async function handleCreateService(event: FormEvent) {
    event.preventDefault();
    setError(null);
    setStatus(null);

    if (!tenantId) return;

    const parsedDuration = Number.parseInt(durationMin, 10);
    if (Number.isNaN(parsedDuration) || parsedDuration <= 0) {
      setError("Duração inválida.");
      return;
    }

    const parsedPrice = parsePriceToCents(price);
    if (price.trim() && parsedPrice === null) {
      setError("Preço inválido.");
      return;
    }

    const supabase = getSupabaseBrowserClient();
    const { error: insertError } = await supabase.from("services").insert({
      tenant_id: tenantId,
      name: serviceName.trim(),
      duration_min: parsedDuration,
      price_cents: parsedPrice,
      specialty_id: serviceSpecialtyId || null
    });

    if (insertError) {
      setError(insertError.message);
      return;
    }

    setServiceName("");
    setDurationMin("30");
    setPrice("");
    setServiceSpecialtyId("");
    setStatus("Serviço cadastrado.");
    await load();
  }

  async function toggleServiceActive(item: ServiceRow) {
    setError(null);
    setStatus(null);
    const supabase = getSupabaseBrowserClient();
    const { error: updateError } = await supabase
      .from("services")
      .update({ active: !item.active })
      .eq("id", item.id);

    if (updateError) {
      setError(updateError.message);
      return;
    }

    setStatus("Status do serviço atualizado.");
    await load();
  }

  function startEditingSpecialty(item: SpecialtyRow) {
    setEditingSpecialtyId(item.id);
    setEditSpecialtyName(item.name);
    setError(null);
    setStatus(null);
  }

  function cancelEditingSpecialty() {
    setEditingSpecialtyId(null);
    setEditSpecialtyName("");
  }

  async function saveEditingSpecialty(item: SpecialtyRow) {
    setError(null);
    setStatus(null);
    const supabase = getSupabaseBrowserClient();
    const { error: updateError } = await supabase
      .from("specialties")
      .update({ name: editSpecialtyName.trim() })
      .eq("id", item.id);

    if (updateError) {
      setError(updateError.message);
      return;
    }

    setStatus("Especialidade atualizada.");
    cancelEditingSpecialty();
    await load();
  }

  async function toggleSpecialtyActive(item: SpecialtyRow) {
    setError(null);
    setStatus(null);
    const supabase = getSupabaseBrowserClient();
    const { error: updateError } = await supabase
      .from("specialties")
      .update({ active: !item.active })
      .eq("id", item.id);

    if (updateError) {
      setError(updateError.message);
      return;
    }

    setStatus("Status da especialidade atualizado.");
    await load();
  }

  function startEditingService(item: ServiceRow) {
    setEditingServiceId(item.id);
    setEditServiceName(item.name);
    setEditDurationMin(String(item.duration_min));
    setEditPrice(formatPriceFromCents(item.price_cents));
    setEditServiceSpecialtyId(item.specialty_id ?? "");
    setError(null);
    setStatus(null);
  }

  function cancelEditingService() {
    setEditingServiceId(null);
    setEditServiceName("");
    setEditDurationMin("30");
    setEditPrice("");
    setEditServiceSpecialtyId("");
  }

  async function saveEditingService(item: ServiceRow) {
    setError(null);
    setStatus(null);

    const parsedDuration = Number.parseInt(editDurationMin, 10);
    if (Number.isNaN(parsedDuration) || parsedDuration <= 0) {
      setError("Duração inválida.");
      return;
    }

    const parsedPrice = parsePriceToCents(editPrice);
    if (editPrice.trim() && parsedPrice === null) {
      setError("Preço inválido.");
      return;
    }

    const supabase = getSupabaseBrowserClient();
    const { error: updateError } = await supabase
      .from("services")
      .update({
        name: editServiceName.trim(),
        duration_min: parsedDuration,
        price_cents: parsedPrice,
        specialty_id: editServiceSpecialtyId || null
      })
      .eq("id", item.id);

    if (updateError) {
      setError(updateError.message);
      return;
    }

    setStatus("Serviço atualizado.");
    cancelEditingService();
    await load();
  }

  return (
    <section className="page-stack">
      <div className="card">
        <h1>Serviços e especialidades</h1>
        <p>Cadastre os serviços disponíveis e organize por especialidade.</p>
      </div>

      <div className="card col">
        <h2>Nova especialidade</h2>
        <form className="row" onSubmit={handleCreateSpecialty}>
          <input
            placeholder="Ex.: Fisioterapia"
            value={specialtyName}
            onChange={(e) => setSpecialtyName(e.target.value)}
            required
          />
          <button type="submit">Cadastrar especialidade</button>
        </form>
      </div>

      <div className="card col">
        <h2>Novo serviço</h2>
        <form className="col" onSubmit={handleCreateService}>
          <label className="col">
            Nome do serviço
            <input value={serviceName} onChange={(e) => setServiceName(e.target.value)} required />
          </label>

          <div className="row">
            <label className="col">
              Duração (min)
              <input
                type="number"
                min={1}
                max={1440}
                value={durationMin}
                onChange={(e) => setDurationMin(e.target.value)}
                required
              />
            </label>

            <label className="col">
              Preço (R$)
              <input type="number" min={0} step="0.01" value={price} onChange={(e) => setPrice(e.target.value)} />
            </label>

            <label className="col">
              Especialidade (opcional)
              <select value={serviceSpecialtyId} onChange={(e) => setServiceSpecialtyId(e.target.value)}>
                <option value="">Sem especialidade</option>
                {specialties
                  .filter((item) => item.active)
                  .map((item) => (
                    <option key={item.id} value={item.id}>
                      {item.name}
                    </option>
                  ))}
              </select>
            </label>
          </div>

          <button type="submit">Cadastrar serviço</button>
        </form>
      </div>

      {status ? <div className="notice">{status}</div> : null}
      {error ? <div className="error">{error}</div> : null}

      <div className="card">
        <h2>Especialidades</h2>
        <table>
          <thead>
            <tr>
              <th>Nome</th>
              <th>Status</th>
              <th>Ação</th>
            </tr>
          </thead>
          <tbody>
            {specialties.map((item) => (
              <tr key={item.id}>
                <td>
                  {editingSpecialtyId === item.id ? (
                    <input value={editSpecialtyName} onChange={(e) => setEditSpecialtyName(e.target.value)} />
                  ) : (
                    item.name
                  )}
                </td>
                <td>{item.active ? "Ativa" : "Inativa"}</td>
                <td>
                  <div className="row">
                    {editingSpecialtyId === item.id ? (
                      <>
                        <button type="button" onClick={() => saveEditingSpecialty(item)}>
                          Salvar
                        </button>
                        <button type="button" className="secondary" onClick={cancelEditingSpecialty}>
                          Cancelar
                        </button>
                      </>
                    ) : (
                      <button type="button" className="secondary" onClick={() => startEditingSpecialty(item)}>
                        Editar
                      </button>
                    )}
                    <button type="button" className="secondary" onClick={() => toggleSpecialtyActive(item)}>
                      {item.active ? "Desativar" : "Ativar"}
                    </button>
                  </div>
                </td>
              </tr>
            ))}
            {specialties.length === 0 ? (
              <tr>
                <td colSpan={3}>Nenhuma especialidade cadastrada.</td>
              </tr>
            ) : null}
          </tbody>
        </table>
      </div>

      <div className="card">
        <h2>Serviços</h2>
        <table>
          <thead>
            <tr>
              <th>Nome</th>
              <th>Duração</th>
              <th>Preço</th>
              <th>Especialidade</th>
              <th>Status</th>
              <th>Ação</th>
            </tr>
          </thead>
          <tbody>
            {services.map((item) => (
              <tr key={item.id}>
                <td>
                  {editingServiceId === item.id ? (
                    <input value={editServiceName} onChange={(e) => setEditServiceName(e.target.value)} />
                  ) : (
                    item.name
                  )}
                </td>
                <td>
                  {editingServiceId === item.id ? (
                    <input
                      type="number"
                      min={1}
                      max={1440}
                      value={editDurationMin}
                      onChange={(e) => setEditDurationMin(e.target.value)}
                    />
                  ) : (
                    `${item.duration_min} min`
                  )}
                </td>
                <td>
                  {editingServiceId === item.id ? (
                    <input
                      type="number"
                      min={0}
                      step="0.01"
                      value={editPrice}
                      onChange={(e) => setEditPrice(e.target.value)}
                    />
                  ) : item.price_cents === null ? (
                    "-"
                  ) : (
                    `R$ ${(item.price_cents / 100).toFixed(2)}`
                  )}
                </td>
                <td>
                  {editingServiceId === item.id ? (
                    <select value={editServiceSpecialtyId} onChange={(e) => setEditServiceSpecialtyId(e.target.value)}>
                      <option value="">Sem especialidade</option>
                      {specialties.map((specialty) => (
                        <option key={specialty.id} value={specialty.id}>
                          {specialty.name}
                        </option>
                      ))}
                    </select>
                  ) : (
                    item.specialties?.name ?? "-"
                  )}
                </td>
                <td>{item.active ? "Ativo" : "Inativo"}</td>
                <td>
                  <div className="row">
                    {editingServiceId === item.id ? (
                      <>
                        <button type="button" onClick={() => saveEditingService(item)}>
                          Salvar
                        </button>
                        <button type="button" className="secondary" onClick={cancelEditingService}>
                          Cancelar
                        </button>
                      </>
                    ) : (
                      <button type="button" className="secondary" onClick={() => startEditingService(item)}>
                        Editar
                      </button>
                    )}
                    <button type="button" className="secondary" onClick={() => toggleServiceActive(item)}>
                      {item.active ? "Desativar" : "Ativar"}
                    </button>
                  </div>
                </td>
              </tr>
            ))}
            {services.length === 0 ? (
              <tr>
                <td colSpan={6}>Nenhum serviço cadastrado.</td>
              </tr>
            ) : null}
          </tbody>
        </table>
      </div>
    </section>
  );
}


