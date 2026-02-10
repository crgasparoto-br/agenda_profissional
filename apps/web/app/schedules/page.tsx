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

type BreakDraft = {
  enabled: boolean;
  start: string;
  end: string;
};

type DayRuleDraft = {
  start: string;
  end: string;
  lunchBreak: BreakDraft;
  pauseBreak: BreakDraft;
};

type ScheduleDraft = {
  timezone: string;
  workdays: number[];
  defaultRule: DayRuleDraft;
  dailyOverrides: Record<number, DayRuleDraft>;
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
  { id: 6, label: "Sab" }
];

function createDefaultRule(): DayRuleDraft {
  return {
    start: "09:00",
    end: "18:00",
    lunchBreak: { enabled: false, start: "12:00", end: "13:00" },
    pauseBreak: { enabled: false, start: "16:00", end: "16:15" }
  };
}

function parseWorkdays(raw: Json): number[] {
  if (!Array.isArray(raw)) return [1, 2, 3, 4, 5];
  const values = raw
    .map((item) => Number(item))
    .filter((item) => Number.isInteger(item) && item >= 0 && item <= 6);
  return values.length > 0 ? values : [1, 2, 3, 4, 5];
}

function toMinutes(timeValue: string) {
  const [hour, minute] = timeValue.split(":").map((value) => Number.parseInt(value, 10));
  if (Number.isNaN(hour) || Number.isNaN(minute)) return null;
  return hour * 60 + minute;
}

function parseBreak(raw: unknown, fallbackStart: string, fallbackEnd: string): BreakDraft {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return { enabled: false, start: fallbackStart, end: fallbackEnd };
  }
  const value = raw as Record<string, unknown>;
  return {
    enabled: value.enabled === true,
    start: typeof value.start === "string" ? value.start : fallbackStart,
    end: typeof value.end === "string" ? value.end : fallbackEnd
  };
}

function parseDayRule(raw: unknown, fallback: DayRuleDraft): DayRuleDraft {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return fallback;

  const value = raw as Record<string, unknown>;
  return {
    start: typeof value.start === "string" ? value.start : fallback.start,
    end: typeof value.end === "string" ? value.end : fallback.end,
    lunchBreak: parseBreak(value.lunch_break, fallback.lunchBreak.start, fallback.lunchBreak.end),
    pauseBreak: parseBreak(value.snack_break, fallback.pauseBreak.start, fallback.pauseBreak.end)
  };
}

function parseWorkHours(raw: Json): { defaultRule: DayRuleDraft; dailyOverrides: Record<number, DayRuleDraft> } {
  const fallback = createDefaultRule();
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return { defaultRule: fallback, dailyOverrides: {} };
  }

  const value = raw as Record<string, unknown>;
  const defaultRule = parseDayRule(value, fallback);
  const dailyOverrides: Record<number, DayRuleDraft> = {};

  if (
    "daily_overrides" in value &&
    value.daily_overrides &&
    typeof value.daily_overrides === "object" &&
    !Array.isArray(value.daily_overrides)
  ) {
    const overrides = value.daily_overrides as Record<string, unknown>;
    for (const [weekdayKey, overrideRaw] of Object.entries(overrides)) {
      const weekday = Number.parseInt(weekdayKey, 10);
      if (!Number.isInteger(weekday) || weekday < 0 || weekday > 6) continue;
      dailyOverrides[weekday] = parseDayRule(overrideRaw, defaultRule);
    }
  }

  return { defaultRule, dailyOverrides };
}

function validateDayRule(rule: DayRuleDraft, label: string): string | null {
  const startMinutes = toMinutes(rule.start);
  const endMinutes = toMinutes(rule.end);
  if (startMinutes === null || endMinutes === null || startMinutes >= endMinutes) {
    return `Janela de atendimento invalida (${label}).`;
  }

  if (rule.lunchBreak.enabled) {
    const breakStart = toMinutes(rule.lunchBreak.start);
    const breakEnd = toMinutes(rule.lunchBreak.end);
    if (
      breakStart === null ||
      breakEnd === null ||
      breakStart >= breakEnd ||
      breakStart < startMinutes ||
      breakEnd > endMinutes
    ) {
      return `Almoco invalido (${label}).`;
    }
  }

  if (rule.pauseBreak.enabled) {
    const breakStart = toMinutes(rule.pauseBreak.start);
    const breakEnd = toMinutes(rule.pauseBreak.end);
    if (
      breakStart === null ||
      breakEnd === null ||
      breakStart >= breakEnd ||
      breakStart < startMinutes ||
      breakEnd > endMinutes
    ) {
      return `Pausa invalida (${label}).`;
    }
  }

  if (rule.lunchBreak.enabled && rule.pauseBreak.enabled) {
    const lunchStart = toMinutes(rule.lunchBreak.start);
    const lunchEnd = toMinutes(rule.lunchBreak.end);
    const pauseStart = toMinutes(rule.pauseBreak.start);
    const pauseEnd = toMinutes(rule.pauseBreak.end);
    if (
      lunchStart !== null &&
      lunchEnd !== null &&
      pauseStart !== null &&
      pauseEnd !== null &&
      lunchStart < pauseEnd &&
      pauseStart < lunchEnd
    ) {
      return `Almoco e pausa nao podem se sobrepor (${label}).`;
    }
  }

  return null;
}

export default function SchedulesPage() {
  const [professionals, setProfessionals] = useState<ProfessionalRow[]>([]);
  const [drafts, setDrafts] = useState<Record<string, ScheduleDraft>>({});
  const [tenantId, setTenantId] = useState<string | null>(null);
  const [editingProfessionalId, setEditingProfessionalId] = useState<string | null>(null);
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
          defaultRule: createDefaultRule(),
          dailyOverrides: {},
          slotMin: "30",
          bufferMin: "0"
        };
        continue;
      }

      const parsed = parseWorkHours(schedule.work_hours);
      nextDrafts[professional.id] = {
        timezone: schedule.timezone,
        workdays: parseWorkdays(schedule.workdays),
        defaultRule: parsed.defaultRule,
        dailyOverrides: parsed.dailyOverrides,
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
        setError("Nao foi possivel resolver a organizacao atual.");
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

  function updateDefaultRule(professionalId: string, patch: Partial<DayRuleDraft>) {
    const current = drafts[professionalId];
    if (!current) return;
    updateDraft(professionalId, {
      defaultRule: {
        ...current.defaultRule,
        ...patch
      }
    });
  }

  function updateDefaultBreak(
    professionalId: string,
    breakKey: "lunchBreak" | "pauseBreak",
    patch: Partial<BreakDraft>
  ) {
    const current = drafts[professionalId];
    if (!current) return;
    updateDefaultRule(professionalId, {
      [breakKey]: {
        ...current.defaultRule[breakKey],
        ...patch
      }
    } as Partial<DayRuleDraft>);
  }

  function toggleWorkday(professionalId: string, weekday: number, checked: boolean) {
    const current = drafts[professionalId];
    if (!current) return;

    const nextWorkdays = checked
      ? Array.from(new Set([...current.workdays, weekday])).sort((a, b) => a - b)
      : current.workdays.filter((item) => item !== weekday);

    const nextOverrides = { ...current.dailyOverrides };
    if (!checked) {
      delete nextOverrides[weekday];
    }

    updateDraft(professionalId, { workdays: nextWorkdays, dailyOverrides: nextOverrides });
  }

  function toggleDayOverride(professionalId: string, weekday: number, enabled: boolean) {
    const current = drafts[professionalId];
    if (!current) return;

    const nextOverrides = { ...current.dailyOverrides };
    if (enabled) {
      nextOverrides[weekday] = { ...current.defaultRule };
    } else {
      delete nextOverrides[weekday];
    }

    updateDraft(professionalId, { dailyOverrides: nextOverrides });
  }

  function updateDayOverride(professionalId: string, weekday: number, patch: Partial<DayRuleDraft>) {
    const current = drafts[professionalId];
    const currentOverride = current?.dailyOverrides[weekday];
    if (!current || !currentOverride) return;

    updateDraft(professionalId, {
      dailyOverrides: {
        ...current.dailyOverrides,
        [weekday]: {
          ...currentOverride,
          ...patch
        }
      }
    });
  }

  function updateDayOverrideBreak(
    professionalId: string,
    weekday: number,
    breakKey: "lunchBreak" | "pauseBreak",
    patch: Partial<BreakDraft>
  ) {
    const current = drafts[professionalId];
    const currentOverride = current?.dailyOverrides[weekday];
    if (!current || !currentOverride) return;

    updateDayOverride(professionalId, weekday, {
      [breakKey]: {
        ...currentOverride[breakKey],
        ...patch
      }
    } as Partial<DayRuleDraft>);
  }

  async function saveSchedule(professionalId: string): Promise<boolean> {
    setError(null);
    setStatus(null);

    const draft = drafts[professionalId];
    if (!draft || !tenantId) return false;
    if (draft.workdays.length === 0) {
      setError("Selecione ao menos um dia da semana.");
      return false;
    }

    const slotMin = Number.parseInt(draft.slotMin, 10);
    const bufferMin = Number.parseInt(draft.bufferMin, 10);
    if (Number.isNaN(slotMin) || slotMin <= 0 || slotMin > 240) {
      setError("Duração do atendimento inválida. Use valores entre 1 e 240.");
      return false;
    }
    if (Number.isNaN(bufferMin) || bufferMin < 0 || bufferMin > 240) {
      setError("Intervalo invalido. Use valores entre 0 e 240.");
      return false;
    }

    const defaultError = validateDayRule(draft.defaultRule, "regra geral");
    if (defaultError) {
      setError(defaultError);
      return false;
    }

    for (const weekday of draft.workdays) {
      const override = draft.dailyOverrides[weekday];
      if (!override) continue;
      const label = `excecao de ${WEEK_DAYS.find((item) => item.id === weekday)?.label ?? weekday}`;
      const overrideError = validateDayRule(override, label);
      if (overrideError) {
        setError(overrideError);
        return false;
      }
    }

    const serializedOverrides = Object.entries(draft.dailyOverrides).reduce<Record<string, Json>>((acc, [key, value]) => {
      acc[key] = {
        start: value.start,
        end: value.end,
        lunch_break: {
          enabled: value.lunchBreak.enabled,
          start: value.lunchBreak.start,
          end: value.lunchBreak.end
        },
        snack_break: {
          enabled: value.pauseBreak.enabled,
          start: value.pauseBreak.start,
          end: value.pauseBreak.end
        }
      };
      return acc;
    }, {});

    const workHoursPayload: Json = {
      start: draft.defaultRule.start,
      end: draft.defaultRule.end,
      lunch_break: {
        enabled: draft.defaultRule.lunchBreak.enabled,
        start: draft.defaultRule.lunchBreak.start,
        end: draft.defaultRule.lunchBreak.end
      },
      snack_break: {
        enabled: draft.defaultRule.pauseBreak.enabled,
        start: draft.defaultRule.pauseBreak.start,
        end: draft.defaultRule.pauseBreak.end
      },
      daily_overrides: serializedOverrides
    };

    const supabase = getSupabaseBrowserClient();
    const { error: upsertError } = await supabase.from("professional_schedule_settings").upsert(
      {
        tenant_id: tenantId,
        professional_id: professionalId,
        timezone: draft.timezone.trim() || "America/Sao_Paulo",
        workdays: draft.workdays,
        work_hours: workHoursPayload,
        slot_min: slotMin,
        buffer_min: bufferMin
      },
      { onConflict: "tenant_id,professional_id" }
    );

    if (upsertError) {
      setError(upsertError.message);
      return false;
    }

    setStatus("Horario salvo com sucesso.");
    await load();
    return true;
  }

  async function startEditingSchedule(professionalId: string) {
    setError(null);
    setStatus(null);
    await load();
    setEditingProfessionalId(professionalId);
  }

  async function cancelEditingSchedule() {
    setError(null);
    setStatus(null);
    await load();
    setEditingProfessionalId(null);
  }

  return (
    <section className="page-stack">
      <div className="card">
        <h1>Horarios e intervalos</h1>
        <p>Configure a regra geral de atendimento e, se precisar, adicione excecoes para dias especificos.</p>
      </div>

      {status ? <div className="notice">{status}</div> : null}
      {error ? <div className="error">{error}</div> : null}

      {professionals.map((professional) => {
        const draft = drafts[professional.id];
        if (!draft) return null;
        const isEditing = editingProfessionalId === professional.id;

        return (
          <div className="card col" key={professional.id}>
            <div className="row align-center justify-between">
              <h2>
                {professional.name}
                {!professional.active ? " (inativo)" : ""}
              </h2>

              <label className="inline-field">
                <span>Fuso horario</span>
                <input
                  value={draft.timezone}
                  onChange={(e) => updateDraft(professional.id, { timezone: e.target.value })}
                  disabled={!isEditing}
                />
              </label>
            </div>

            <div className="col">
              <strong>Dias de atendimento</strong>
              <div className="row">
                {WEEK_DAYS.map((weekday) => (
                  <label key={weekday.id} className="row align-center">
                    <input
                      type="checkbox"
                      checked={draft.workdays.includes(weekday.id)}
                      onChange={(e) => toggleWorkday(professional.id, weekday.id, e.target.checked)}
                      disabled={!isEditing}
                    />
                    {weekday.label}
                  </label>
                ))}
              </div>
            </div>

            <div className="row">
              <label className="inline-field">
                <span>Duração do atendimento (min)</span>
                <input
                  type="number"
                  min={1}
                  max={240}
                  value={draft.slotMin}
                  onChange={(e) => updateDraft(professional.id, { slotMin: e.target.value })}
                  disabled={!isEditing}
                />
              </label>

              <label className="inline-field">
                <span>Intervalo entre atendimentos (min)</span>
                <input
                  type="number"
                  min={0}
                  max={240}
                  value={draft.bufferMin}
                  onChange={(e) => updateDraft(professional.id, { bufferMin: e.target.value })}
                  disabled={!isEditing}
                />
              </label>
            </div>

            <div className="col">
              <div className="row align-center">
                <strong>Regra geral:</strong>
                <label className="inline-field">
                  <span>Inicio</span>
                  <input
                    type="time"
                    value={draft.defaultRule.start}
                    onChange={(e) => updateDefaultRule(professional.id, { start: e.target.value })}
                    disabled={!isEditing}
                  />
                </label>
                <label className="inline-field">
                  <span>Fim</span>
                  <input
                    type="time"
                    value={draft.defaultRule.end}
                    onChange={(e) => updateDefaultRule(professional.id, { end: e.target.value })}
                    disabled={!isEditing}
                  />
                </label>
              </div>

              <div className="row align-center">
                <label className="row align-center">
                  <input
                    type="checkbox"
                    checked={draft.defaultRule.lunchBreak.enabled}
                    onChange={(e) => updateDefaultBreak(professional.id, "lunchBreak", { enabled: e.target.checked })}
                    disabled={!isEditing}
                  />
                  Almoco:
                </label>
                <label className="inline-field">
                  <span>Inicio</span>
                  <input
                    type="time"
                    value={draft.defaultRule.lunchBreak.start}
                    onChange={(e) => updateDefaultBreak(professional.id, "lunchBreak", { start: e.target.value })}
                    disabled={!isEditing || !draft.defaultRule.lunchBreak.enabled}
                  />
                </label>
                <label className="inline-field">
                  <span>Fim</span>
                  <input
                    type="time"
                    value={draft.defaultRule.lunchBreak.end}
                    onChange={(e) => updateDefaultBreak(professional.id, "lunchBreak", { end: e.target.value })}
                    disabled={!isEditing || !draft.defaultRule.lunchBreak.enabled}
                  />
                </label>
              </div>

              <div className="row align-center">
                <label className="row align-center">
                  <input
                    type="checkbox"
                    checked={draft.defaultRule.pauseBreak.enabled}
                    onChange={(e) => updateDefaultBreak(professional.id, "pauseBreak", { enabled: e.target.checked })}
                    disabled={!isEditing}
                  />
                  Pausa:
                </label>
                <label className="inline-field">
                  <span>Inicio</span>
                  <input
                    type="time"
                    value={draft.defaultRule.pauseBreak.start}
                    onChange={(e) => updateDefaultBreak(professional.id, "pauseBreak", { start: e.target.value })}
                    disabled={!isEditing || !draft.defaultRule.pauseBreak.enabled}
                  />
                </label>
                <label className="inline-field">
                  <span>Fim</span>
                  <input
                    type="time"
                    value={draft.defaultRule.pauseBreak.end}
                    onChange={(e) => updateDefaultBreak(professional.id, "pauseBreak", { end: e.target.value })}
                    disabled={!isEditing || !draft.defaultRule.pauseBreak.enabled}
                  />
                </label>
              </div>
            </div>

            <div className="col">
              <strong>Excecoes por dia (opcional)</strong>
              {draft.workdays.map((weekday) => {
                const override = draft.dailyOverrides[weekday];
                const weekdayLabel = WEEK_DAYS.find((item) => item.id === weekday)?.label ?? String(weekday);
                return (
                  <div className="card col" key={weekday}>
                    <label className="row align-center">
                      <input
                        type="checkbox"
                        checked={Boolean(override)}
                        onChange={(e) => toggleDayOverride(professional.id, weekday, e.target.checked)}
                        disabled={!isEditing}
                      />
                      Usar excecao em {weekdayLabel}
                    </label>

                    {override ? (
                      <>
                        <div className="row align-center">
                          <strong>Regra do dia:</strong>
                          <label className="inline-field">
                            <span>Inicio</span>
                            <input
                              type="time"
                              value={override.start}
                              onChange={(e) => updateDayOverride(professional.id, weekday, { start: e.target.value })}
                              disabled={!isEditing}
                            />
                          </label>
                          <label className="inline-field">
                            <span>Fim</span>
                            <input
                              type="time"
                              value={override.end}
                              onChange={(e) => updateDayOverride(professional.id, weekday, { end: e.target.value })}
                              disabled={!isEditing}
                            />
                          </label>
                        </div>

                        <div className="row align-center">
                          <label className="row align-center">
                            <input
                              type="checkbox"
                              checked={override.lunchBreak.enabled}
                              onChange={(e) =>
                                updateDayOverrideBreak(professional.id, weekday, "lunchBreak", {
                                  enabled: e.target.checked
                                })}
                              disabled={!isEditing}
                            />
                            Almoco:
                          </label>
                          <label className="inline-field">
                            <span>Inicio</span>
                            <input
                              type="time"
                              value={override.lunchBreak.start}
                              onChange={(e) =>
                                updateDayOverrideBreak(professional.id, weekday, "lunchBreak", {
                                  start: e.target.value
                                })}
                              disabled={!isEditing || !override.lunchBreak.enabled}
                            />
                          </label>
                          <label className="inline-field">
                            <span>Fim</span>
                            <input
                              type="time"
                              value={override.lunchBreak.end}
                              onChange={(e) =>
                                updateDayOverrideBreak(professional.id, weekday, "lunchBreak", {
                                  end: e.target.value
                                })}
                              disabled={!isEditing || !override.lunchBreak.enabled}
                            />
                          </label>
                        </div>

                        <div className="row align-center">
                          <label className="row align-center">
                            <input
                              type="checkbox"
                              checked={override.pauseBreak.enabled}
                              onChange={(e) =>
                                updateDayOverrideBreak(professional.id, weekday, "pauseBreak", {
                                  enabled: e.target.checked
                                })}
                              disabled={!isEditing}
                            />
                            Pausa:
                          </label>
                          <label className="inline-field">
                            <span>Inicio</span>
                            <input
                              type="time"
                              value={override.pauseBreak.start}
                              onChange={(e) =>
                                updateDayOverrideBreak(professional.id, weekday, "pauseBreak", {
                                  start: e.target.value
                                })}
                              disabled={!isEditing || !override.pauseBreak.enabled}
                            />
                          </label>
                          <label className="inline-field">
                            <span>Fim</span>
                            <input
                              type="time"
                              value={override.pauseBreak.end}
                              onChange={(e) =>
                                updateDayOverrideBreak(professional.id, weekday, "pauseBreak", {
                                  end: e.target.value
                                })}
                              disabled={!isEditing || !override.pauseBreak.enabled}
                            />
                          </label>
                        </div>
                      </>
                    ) : null}
                  </div>
                );
              })}
            </div>

            <div>
              {isEditing ? (
                <div className="row">
                  <button
                    type="button"
                    onClick={async () => {
                      const ok = await saveSchedule(professional.id);
                      if (ok) {
                        setEditingProfessionalId(null);
                      }
                    }}
                  >
                    Salvar horario
                  </button>
                  <button type="button" className="secondary" onClick={cancelEditingSchedule}>
                    Cancelar
                  </button>
                </div>
              ) : (
                <button type="button" className="secondary" onClick={() => startEditingSchedule(professional.id)}>
                  Editar horario
                </button>
              )}
            </div>
          </div>
        );
      })}

      {professionals.length === 0 ? <div className="card">Nenhum profissional cadastrado.</div> : null}
    </section>
  );
}
