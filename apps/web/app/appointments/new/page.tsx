"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
import { CreateAppointmentInputSchema } from "@agenda-profissional/shared";
import type { Tables } from "@agenda-profissional/shared/database.types";
import { getSupabaseBrowserClient } from "@/lib/supabase-browser";
import { getFunctionErrorMessage } from "@/lib/function-error";
import { formatPhone } from "@/lib/phone";

type Option = { id: string; label: string };
type ClientOption = Pick<Tables<"clients">, "id" | "full_name">;
type ServiceOption = Pick<Tables<"services">, "id" | "name" | "duration_min">;
type ProfessionalOption = Pick<Tables<"professionals">, "id" | "name">;
type ServiceItem = Option & { durationMin: number };

function formatDateTimeLocal(date: Date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  const hours = String(date.getHours()).padStart(2, "0");
  const minutes = String(date.getMinutes()).padStart(2, "0");
  return `${year}-${month}-${day}T${hours}:${minutes}`;
}

export default function NewAppointmentPage() {
  const [clients, setClients] = useState<Option[]>([]);
  const [services, setServices] = useState<ServiceItem[]>([]);
  const [professionals, setProfessionals] = useState<Option[]>([]);

  const [clientId, setClientId] = useState<string>("");
  const [clientName, setClientName] = useState("");
  const [clientPhone, setClientPhone] = useState("");
  const [serviceId, setServiceId] = useState<string>("");
  const [professionalId, setProfessionalId] = useState<string>("");
  const [anyAvailable, setAnyAvailable] = useState(true);
  const [startsAt, setStartsAt] = useState("");
  const [status, setStatus] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const selectedService = useMemo(() => services.find((item) => item.id === serviceId) ?? null, [services, serviceId]);
  const endsAt = useMemo(() => {
    if (!startsAt || !selectedService) return "";
    const startDate = new Date(startsAt);
    if (Number.isNaN(startDate.getTime())) return "";
    const endDate = new Date(startDate.getTime() + selectedService.durationMin * 60 * 1000);
    return formatDateTimeLocal(endDate);
  }, [startsAt, selectedService]);
  const canSubmit = useMemo(() => Boolean(serviceId && startsAt && endsAt), [serviceId, startsAt, endsAt]);

  useEffect(() => {
    const supabase = getSupabaseBrowserClient();

    async function loadOptions() {
      const [{ data: clientsData }, { data: servicesData }, { data: professionalsData }] = await Promise.all([
        supabase.from("clients").select("id, full_name").order("full_name"),
        supabase.from("services").select("id, name, duration_min").eq("active", true).order("name"),
        supabase.from("professionals").select("id, name").eq("active", true).order("name")
      ]);

      setClients((clientsData ?? []).map((c: ClientOption) => ({ id: c.id, label: c.full_name })));
      setServices(
        (servicesData ?? []).map((s: ServiceOption) => ({
          id: s.id,
          label: s.name,
          durationMin: s.duration_min
        }))
      );
      setProfessionals((professionalsData ?? []).map((p: ProfessionalOption) => ({ id: p.id, label: p.name })));
    }

    loadOptions();
  }, []);

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    setError(null);
    setStatus(null);

    const parsed = CreateAppointmentInputSchema.safeParse({
      client_id: clientId || null,
      client_name: clientId ? null : clientName || null,
      client_phone: clientId ? null : clientPhone || null,
      service_id: serviceId,
      starts_at: new Date(startsAt).toISOString(),
      ends_at: new Date(endsAt).toISOString(),
      professional_id: anyAvailable ? null : professionalId || null,
      any_available: anyAvailable,
      source: "professional"
    });

    if (!parsed.success) {
      setError("Dados inválidos para agendamento.");
      return;
    }

    const supabase = getSupabaseBrowserClient();
    const { data, error: invokeError } = await supabase.functions.invoke("create-appointment", {
      body: parsed.data
    });

    if (invokeError) {
      setError(await getFunctionErrorMessage(invokeError, "Nao foi possivel criar o agendamento."));
      return;
    }

    setStatus(`Agendamento criado: ${data.appointment.id}`);
  }

  return (
    <section className="card col">
      <h1>Novo agendamento</h1>
      <form className="col" onSubmit={handleSubmit}>
        <label className="col">
          Cliente (opcional)
          <select value={clientId} onChange={(e) => setClientId(e.target.value)}>
            <option value="">Novo cliente (via WhatsApp)</option>
            {clients.map((item) => (
              <option value={item.id} key={item.id}>
                {item.label}
              </option>
            ))}
          </select>
        </label>

        {!clientId ? (
          <div className="row">
            <label className="col">
              Nome do cliente (opcional)
              <input value={clientName} onChange={(e) => setClientName(e.target.value)} />
            </label>
            <label className="col">
              WhatsApp do cliente
              <input
                value={clientPhone}
                onChange={(e) => setClientPhone(formatPhone(e.target.value))}
                inputMode="tel"
                placeholder="(11) 99999-9999"
                required
              />
            </label>
          </div>
        ) : null}

        <label className="col">
          Serviço
          <select value={serviceId} onChange={(e) => setServiceId(e.target.value)} required>
            <option value="">Selecione...</option>
            {services.map((item) => (
              <option value={item.id} key={item.id}>
                {item.label}
              </option>
            ))}
          </select>
        </label>

        <label className="row align-center">
          <input type="checkbox" checked={anyAvailable} onChange={(e) => setAnyAvailable(e.target.checked)} />
          Qualquer profissional disponível
        </label>

        {!anyAvailable ? (
          <label className="col">
            Profissional
            <select value={professionalId} onChange={(e) => setProfessionalId(e.target.value)} required>
              <option value="">Selecione...</option>
              {professionals.map((item) => (
                <option value={item.id} key={item.id}>
                  {item.label}
                </option>
              ))}
            </select>
          </label>
        ) : null}

        <label className="col">
          Início
          <input type="datetime-local" value={startsAt} onChange={(e) => setStartsAt(e.target.value)} required />
        </label>

        <label className="col">
          Fim (calculado automaticamente)
          <input type="datetime-local" value={endsAt} readOnly disabled />
        </label>

        {status ? <div className="notice">{status}</div> : null}
        {error ? <div className="error">{error}</div> : null}

        <button type="submit" disabled={!canSubmit}>
          Criar agendamento
        </button>
      </form>
    </section>
  );
}




