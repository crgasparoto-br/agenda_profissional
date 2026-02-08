"use client";

import { useEffect, useState } from "react";
import type { Json } from "@agenda-profissional/shared/database.types";
import { getSupabaseBrowserClient } from "@/lib/supabase-browser";

type ProfessionalRow = {
  id: string;
  name: string;
  active: boolean;
};

type ScheduleRow = {
  professional_id: string;
  timezone: string;
  workdays: Json;
  work_hours: Json;
  slot_min: number;
  buffer_min: number;
};

type ScheduleDraft = {
  timezone: string;
  workdays: number[];
  start: string;
  end: string;
  slotMin: string;
  bufferMin: string;
};

const WEEK_DAYS = [
  { id: 0, label: "Dom" },
  { id: 1, label: "Seg" },
  { id: 2, label: "Ter" },
  { id: 3, label: "Qua" },
  { id: 4, label: "Qui" },
  { id: 5, label: "Sex" },
  { id: 6, label: "SÃ¡b" }
];

function parseWorkdays(raw: Json): number[] {
  if (!Array.isArray(raw)) return [1, 2, 3, 4, 5];
  const values = raw
    .map((item) => Number(item))
    .filter((item) => Number.isInteger(item) && item >= 0 && item <= 6);
  return values.length > 0 ? values : [1, 2, 3, 4, 5];
}

function parseWorkHours(raw: Json): { start: string; end: string } {
  if (raw && typeof raw === "object" && !Array.isArray(raw)) {
    const start = "start" in raw && typeof raw.start === "string" ? raw.start : "09:00";
    const end = "end" in raw && typeof raw.end === "string" ? raw.end : "18:00";
    return { start, end };
  }

  return { start: "09:00", end: "18:00" };
}

export default function SchedulesPage() {
  const [professionals, setProfessionals] = useState<ProfessionalRow[]>([]);
  const [drafts, setDrafts] = useState<Record<string, ScheduleDraft>>({});
  const [tenantId, setTenantId] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function load() {
    const supabase = getSupabaseBrowserClient();
    const [{ data: professionalsData, error: professionalsError }, { data: schedulesData, error: schedulesError }] =
      await Promise.all([
        supabase.from("professionals").select("id, name, active").order("name"),
        supabase
          .from("professional_schedule_settings")
          .select("professional_id, timezone, workdays, work_hours, slot_min, buffer_min")
      ]);

    if (professionalsError) {
      setError(professionalsError.message);
      return;
    }

    if (schedulesError) {
      setError(schedulesError.message);
      return;
    }

    const professionalsRows = (professionalsData ?? []) as ProfessionalRow[];
    const schedulesRows = (schedulesData ?? []) as ScheduleRow[];
    const scheduleByProfessional = new Map<string, ScheduleRow>(
      schedulesRows.map((item) => [item.professional_id, item])
    );

    const nextDrafts: Record<string, ScheduleDraft> = {};
    for (const professional of professionalsRows) {
      const schedule = scheduleByProfessional.get(professional.id);
      if (!schedule) {
        nextDrafts[professional.id] = {
          timezone: "America/Sao_Paulo",
          workdays: [1, 2, 3, 4, 5],
          start: "09:00",
          end: "18:00",
          slotMin: "30",
          bufferMin: "0"
        };
        continue;
      }

      const parsedHours = parseWorkHours(schedule.work_hours);
      nextDrafts[professional.id] = {
        timezone: schedule.timezone,
        workdays: parseWorkdays(schedule.workdays),
        start: parsedHours.start,
        end: parsedHours.end,
        slotMin: String(schedule.slot_min),
        bufferMin: String(schedule.buffer_min)
      };
    }

    setProfessionals(professionalsRows);
    setDrafts(nextDrafts);
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

  function updateDraft(professionalId: string, patch: Partial<ScheduleDraft>) {
    setDrafts((prev) => ({
      ...prev,
      [professionalId]: {
        ...prev[professionalId],
        ...patch
      }
    }));
  }

  function toggleWorkday(professionalId: string, weekday: number, checked: boolean) {
    const current = drafts[professionalId];
    if (!current) return;

    const nextWorkdays = checked
      ? Array.from(new Set([...current.workdays, weekday])).sort((a, b) => a - b)
      : current.workdays.filter((item) => item !== weekday);

    updateDraft(professionalId, { workdays: nextWorkdays });
  }

  async function saveSchedule(professionalId: string) {
    setError(null);
    setStatus(null);

    const draft = drafts[professionalId];
    if (!draft || !tenantId) return;
    if (draft.workdays.length === 0) {
      setError("Selecione ao menos um dia da semana.");
      return;
    }

    const slotMin = Number.parseInt(draft.slotMin, 10);
    const bufferMin = Number.parseInt(draft.bufferMin, 10);
    if (Number.isNaN(slotMin) || slotMin <= 0 || slotMin > 240) {
      setError("Slot invÃ¡lido. Use valores entre 1 e 240.");
      return;
    }

    if (Number.isNaN(bufferMin) || bufferMin < 0 || bufferMin > 240) {
      setError("Intervalo invÃ¡lido. Use valores entre 0 e 240.");
      return;
    }

    const supabase = getSupabaseBrowserClient();
    const { error: upsertError } = await supabase.from("professional_schedule_settings").upsert(
      {
        tenant_id: tenantId,
        professional_id: professionalId,
        timezone: draft.timezone.trim() || "America/Sao_Paulo",
        workdays: draft.workdays,
        work_hours: {
          start: draft.start,
          end: draft.end
        },
        slot_min: slotMin,
        buffer_min: bufferMin
      },
      { onConflict: "tenant_id,professional_id" }
    );

    if (upsertError) {
      setError(upsertError.message);
      return;
    }

    setStatus("HorÃ¡rio salvo com sucesso.");
    await load();
  }

  return (
    <section className="page-stack">
      <div className="card">
        <h1>HorÃ¡rios e intervalos</h1>
        <p>Configure dias/horÃ¡rios de atendimento, duraÃ§Ã£o do slot e intervalo entre atendimentos.</p>
      </div>

      {status ? <div className="notice">{status}</div> : null}
      {error ? <div className="error">{error}</div> : null}

      {professionals.map((professional) => {
        const draft = drafts[professional.id];
        if (!draft) return null;

        return (
          <div className="card col" key={professional.id}>
            <h2>
              {professional.name}
              {!professional.active ? " (inativo)" : ""}
            </h2>

            <label className="col">
              Timezone
              <input
                value={draft.timezone}
                onChange={(e) => updateDraft(professional.id, { timezone: e.target.value })}
              />
            </label>

            <div className="col">
              <strong>Dias de atendimento</strong>
              <div className="row">
                {WEEK_DAYS.map((weekday) => (
                  <label key={weekday.id} className="row align-center">
                    <input
                      type="checkbox"
                      checked={draft.workdays.includes(weekday.id)}
                      onChange={(e) => toggleWorkday(professional.id, weekday.id, e.target.checked)}
                    />
                    {weekday.label}
                  </label>
                ))}
              </div>
            </div>

            <div className="row">
              <label className="col">
                InÃ­cio
                <input
                  type="time"
                  value={draft.start}
                  onChange={(e) => updateDraft(professional.id, { start: e.target.value })}
                />
              </label>

              <label className="col">
                Fim
                <input
                  type="time"
                  value={draft.end}
                  onChange={(e) => updateDraft(professional.id, { end: e.target.value })}
                />
              </label>

              <label className="col">
                Slot (min)
                <input
                  type="number"
                  min={1}
                  max={240}
                  value={draft.slotMin}
                  onChange={(e) => updateDraft(professional.id, { slotMin: e.target.value })}
                />
              </label>

              <label className="col">
                Intervalo entre atendimentos (min)
                <input
                  type="number"
                  min={0}
                  max={240}
                  value={draft.bufferMin}
                  onChange={(e) => updateDraft(professional.id, { bufferMin: e.target.value })}
                />
              </label>
            </div>

            <div>
              <button type="button" onClick={() => saveSchedule(professional.id)}>
                Salvar horÃ¡rio
              </button>
            </div>
          </div>
        );
      })}

      {professionals.length === 0 ? <div className="card">Nenhum profissional cadastrado.</div> : null}
    </section>
  );
}


