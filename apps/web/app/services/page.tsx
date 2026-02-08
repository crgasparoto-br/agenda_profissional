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
        setError("NÃ£o foi possÃ­vel resolver o tenant atual.");
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
      setError("DuraÃ§Ã£o invÃ¡lida.");
      return;
    }

    const parsedPrice = parsePriceToCents(price);
    if (price.trim() && parsedPrice === null) {
      setError("PreÃ§o invÃ¡lido.");
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
    setStatus("ServiÃ§o cadastrado.");
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

    setStatus("Status do serviÃ§o atualizado.");
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

  return (
    <section className="page-stack">
      <div className="card">
        <h1>ServiÃ§os e especialidades</h1>
        <p>Cadastre os serviÃ§os disponÃ­veis e organize por especialidade.</p>
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
        <h2>Novo serviÃ§o</h2>
        <form className="col" onSubmit={handleCreateService}>
          <label className="col">
            Nome do serviÃ§o
            <input value={serviceName} onChange={(e) => setServiceName(e.target.value)} required />
          </label>

          <div className="row">
            <label className="col">
              DuraÃ§Ã£o (min)
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
              PreÃ§o (R$)
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

          <button type="submit">Cadastrar serviÃ§o</button>
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
              <th>AÃ§Ã£o</th>
            </tr>
          </thead>
          <tbody>
            {specialties.map((item) => (
              <tr key={item.id}>
                <td>{item.name}</td>
                <td>{item.active ? "Ativa" : "Inativa"}</td>
                <td>
                  <button type="button" className="secondary" onClick={() => toggleSpecialtyActive(item)}>
                    {item.active ? "Desativar" : "Ativar"}
                  </button>
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
        <h2>ServiÃ§os</h2>
        <table>
          <thead>
            <tr>
              <th>Nome</th>
              <th>DuraÃ§Ã£o</th>
              <th>PreÃ§o</th>
              <th>Especialidade</th>
              <th>Status</th>
              <th>AÃ§Ã£o</th>
            </tr>
          </thead>
          <tbody>
            {services.map((item) => (
              <tr key={item.id}>
                <td>{item.name}</td>
                <td>{item.duration_min} min</td>
                <td>{item.price_cents === null ? "-" : `R$ ${(item.price_cents / 100).toFixed(2)}`}</td>
                <td>{item.specialties?.name ?? "-"}</td>
                <td>{item.active ? "Ativo" : "Inativo"}</td>
                <td>
                  <button type="button" className="secondary" onClick={() => toggleServiceActive(item)}>
                    {item.active ? "Desativar" : "Ativar"}
                  </button>
                </td>
              </tr>
            ))}
            {services.length === 0 ? (
              <tr>
                <td colSpan={6}>Nenhum serviÃ§o cadastrado.</td>
              </tr>
            ) : null}
          </tbody>
        </table>
      </div>
    </section>
  );
}


