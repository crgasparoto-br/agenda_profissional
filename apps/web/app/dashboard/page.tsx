"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { getSupabaseBrowserClient } from "@/lib/supabase-browser";

type DashboardAppointment = {
  id: string;
  starts_at: string;
  ends_at: string;
  status: string;
  clients: { full_name: string | null } | null;
  services: { name: string | null } | null;
  professionals: { name: string | null } | null;
};

function statusMeta(status: string) {
  const value = status.toLowerCase();

  if (value === "confirmed") {
    return { label: "Confirmado", className: "status-pill status-confirmed" };
  }

  if (value === "cancelled") {
    return { label: "Cancelado", className: "status-pill status-cancelled" };
  }

  if (value === "pending") {
    return { label: "Pendente", className: "status-pill status-pending" };
  }

  if (value === "available") {
    return { label: "Disponível", className: "status-pill status-available" };
  }

  return { label: status, className: "status-pill status-pending" };
}

export default function DashboardPage() {
  const [appointments, setAppointments] = useState<DashboardAppointment[]>([]);
  const [error, setError] = useState<string | null>(null);

  const todayRange = useMemo(() => {
    const start = new Date();
    start.setHours(0, 0, 0, 0);
    const end = new Date(start);
    end.setDate(end.getDate() + 1);
    return { start: start.toISOString(), end: end.toISOString() };
  }, []);

  useEffect(() => {
    const supabase = getSupabaseBrowserClient();

    async function load() {
      const { data, error: queryError } = await supabase
        .from("appointments")
        .select(
          "id, starts_at, ends_at, status, clients(full_name), services(name), professionals(name)"
        )
        .gte("starts_at", todayRange.start)
        .lt("starts_at", todayRange.end)
        .order("starts_at", { ascending: true });

      if (queryError) {
        setError(queryError.message);
        return;
      }

      setAppointments((data ?? []) as DashboardAppointment[]);
    }

    load();
  }, [todayRange.end, todayRange.start]);

  return (
    <section className="page-stack">
      <div className="card row align-center justify-between">
        <h1>Dashboard - Agenda de hoje</h1>
        <Link href="/appointments/new">Novo agendamento</Link>
      </div>

      {error ? <div className="error">{error}</div> : null}

      <div className="card">
        <table>
          <thead>
            <tr>
              <th>Horário</th>
              <th>Cliente</th>
              <th>Serviço</th>
              <th>Profissional</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            {appointments.map((item) => {
              const meta = statusMeta(item.status);

              return (
                <tr key={item.id}>
                  <td>
                    {new Date(item.starts_at).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}
                    {" - "}
                    {new Date(item.ends_at).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}
                  </td>
                  <td>{item.clients?.full_name ?? "Sem cliente"}</td>
                  <td>{item.services?.name ?? "-"}</td>
                  <td>{item.professionals?.name ?? "-"}</td>
                  <td>
                    <span className={meta.className}>{meta.label}</span>
                  </td>
                </tr>
              );
            })}
            {appointments.length === 0 ? (
              <tr>
                <td colSpan={5}>Nenhum agendamento para hoje.</td>
              </tr>
            ) : null}
          </tbody>
        </table>
      </div>
    </section>
  );
}

