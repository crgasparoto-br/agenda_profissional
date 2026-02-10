"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { getSupabaseBrowserClient } from "@/lib/supabase-browser";

type DashboardAppointment = {
  id: string;
  professional_id: string;
  starts_at: string;
  ends_at: string;
  status: string;
  clients: { full_name: string | null } | null;
  services: { name: string | null; duration_min: number | null } | null;
  professionals: { name: string | null } | null;
};

type ProfileRow = {
  tenant_id: string;
  role: "owner" | "admin" | "staff" | "receptionist";
} | null;

type TenantRow = {
  type: "individual" | "group";
} | null;
type ViewMode = "day" | "week" | "month";
type ProfessionalOption = { id: string; name: string };
type ScheduleSettingsRow = {
  professional_id: string;
  timezone: string;
  workdays: unknown;
  work_hours: unknown;
  slot_min: number;
  buffer_min: number;
};
type BreakConfig = { enabled: boolean; start: string; end: string };

function statusMeta(status: string) {
  const value = status.toLowerCase();

  if (value === "scheduled") {
    return { label: "Agendado", className: "status-pill status-pending" };
  }

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

function formatTimeLocal(isoValue: string) {
  const date = new Date(isoValue);
  if (Number.isNaN(date.getTime())) return "--:--";
  const hh = String(date.getHours()).padStart(2, "0");
  const mm = String(date.getMinutes()).padStart(2, "0");
  return `${hh}:${mm}`;
}

function formatTimeInTimezone(isoValue: string, timezone: string) {
  const date = new Date(isoValue);
  if (Number.isNaN(date.getTime())) return "--:--";
  try {
    return new Intl.DateTimeFormat("pt-BR", {
      timeZone: timezone,
      hour: "2-digit",
      minute: "2-digit",
      hour12: false
    }).format(date);
  } catch {
    return formatTimeLocal(isoValue);
  }
}

function formatDateLabel(isoValue: string, timezone: string) {
  const date = new Date(isoValue);
  if (Number.isNaN(date.getTime())) return "--/--/----";
  try {
    return new Intl.DateTimeFormat("pt-BR", {
      timeZone: timezone,
      day: "2-digit",
      month: "2-digit",
      year: "numeric"
    }).format(date);
  } catch {
    return "--/--/----";
  }
}

function parseMinutes(value: string): number | null {
  const [hour, minute] = value.split(":").map((item) => Number.parseInt(item, 10));
  if (Number.isNaN(hour) || Number.isNaN(minute)) return null;
  return hour * 60 + minute;
}

function parseWorkdays(raw: unknown): number[] {
  if (!Array.isArray(raw)) return [1, 2, 3, 4, 5];
  const values = raw
    .map((item) => Number(item))
    .filter((item) => Number.isInteger(item) && item >= 0 && item <= 6);
  return values.length > 0 ? values : [1, 2, 3, 4, 5];
}

function parseBreakConfig(raw: unknown, fallbackStart: string, fallbackEnd: string): BreakConfig {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return { enabled: false, start: fallbackStart, end: fallbackEnd };
  }
  const value = raw as Record<string, unknown>;
  const hasLegacyWindow =
    !("enabled" in value) && typeof value.start === "string" && typeof value.end === "string";
  return {
    enabled: value.enabled === true || hasLegacyWindow,
    start: typeof value.start === "string" ? value.start : fallbackStart,
    end: typeof value.end === "string" ? value.end : fallbackEnd
  };
}

function toDateKey(date: Date) {
  const yyyy = date.getFullYear();
  const mm = String(date.getMonth() + 1).padStart(2, "0");
  const dd = String(date.getDate()).padStart(2, "0");
  return `${yyyy}-${mm}-${dd}`;
}

function formatInputDateTimeFromIso(isoValue: string) {
  const date = new Date(isoValue);
  if (Number.isNaN(date.getTime())) return "";
  const yyyy = date.getFullYear();
  const mm = String(date.getMonth() + 1).padStart(2, "0");
  const dd = String(date.getDate()).padStart(2, "0");
  const hh = String(date.getHours()).padStart(2, "0");
  const mi = String(date.getMinutes()).padStart(2, "0");
  return `${yyyy}-${mm}-${dd}T${hh}:${mi}`;
}

function getWeekdayAndMinutesInTimezone(isoValue: string, timezone: string) {
  const date = new Date(isoValue);
  if (Number.isNaN(date.getTime())) return null;
  const weekdayFormat = new Intl.DateTimeFormat("en-US", { timeZone: timezone, weekday: "short" });
  const hourFormat = new Intl.DateTimeFormat("en-US", { timeZone: timezone, hour: "2-digit", hour12: false });
  const minuteFormat = new Intl.DateTimeFormat("en-US", { timeZone: timezone, minute: "2-digit" });
  const weekdayMap: Record<string, number> = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };
  const weekday = weekdayMap[weekdayFormat.format(date)];
  const hour = Number.parseInt(hourFormat.format(date), 10);
  const minute = Number.parseInt(minuteFormat.format(date), 10);
  if (weekday === undefined || Number.isNaN(hour) || Number.isNaN(minute)) return null;
  return { weekday, minutes: hour * 60 + minute };
}

function overlaps(startA: number, endA: number, startB: number, endB: number) {
  return startA < endB && startB < endA;
}

function isWithinSchedule(
  settings: ScheduleSettingsRow | null | undefined,
  startsAtIso: string,
  endsAtIso: string
) {
  if (!settings) return true;
  const timezone = settings.timezone || "America/Sao_Paulo";
  const startInTz = getWeekdayAndMinutesInTimezone(startsAtIso, timezone);
  const endInTz = getWeekdayAndMinutesInTimezone(endsAtIso, timezone);
  if (!startInTz || !endInTz) return false;
  if (startInTz.weekday !== endInTz.weekday) return false;
  if (endInTz.minutes <= startInTz.minutes) return false;

  const workdays = parseWorkdays(settings.workdays);
  if (workdays.length > 0 && !workdays.includes(startInTz.weekday)) return false;

  const workHours =
    settings.work_hours && typeof settings.work_hours === "object" && !Array.isArray(settings.work_hours)
      ? (settings.work_hours as Record<string, unknown>)
      : {};
  const dailyOverrides =
    workHours.daily_overrides && typeof workHours.daily_overrides === "object" && !Array.isArray(workHours.daily_overrides)
      ? (workHours.daily_overrides as Record<string, unknown>)
      : {};
  const overrideForWeekday = dailyOverrides[String(startInTz.weekday)];
  const dayRule =
    overrideForWeekday && typeof overrideForWeekday === "object" && !Array.isArray(overrideForWeekday)
      ? (overrideForWeekday as Record<string, unknown>)
      : workHours;

  const workStart = typeof dayRule.start === "string" ? parseMinutes(dayRule.start) : parseMinutes("09:00");
  const workEnd = typeof dayRule.end === "string" ? parseMinutes(dayRule.end) : parseMinutes("18:00");
  if (workStart === null || workEnd === null || workStart >= workEnd) return false;
  if (startInTz.minutes < workStart || endInTz.minutes > workEnd) return false;

  const lunchBreak = parseBreakConfig(dayRule.lunch_break, "12:00", "13:00");
  if (lunchBreak.enabled) {
    const lunchStart = parseMinutes(lunchBreak.start);
    const lunchEnd = parseMinutes(lunchBreak.end);
    if (lunchStart === null || lunchEnd === null || lunchStart >= lunchEnd) return false;
    if (overlaps(startInTz.minutes, endInTz.minutes, lunchStart, lunchEnd)) return false;
  }

  const snackBreak = parseBreakConfig(dayRule.snack_break, "16:00", "16:15");
  if (snackBreak.enabled) {
    const snackStart = parseMinutes(snackBreak.start);
    const snackEnd = parseMinutes(snackBreak.end);
    if (snackStart === null || snackEnd === null || snackStart >= snackEnd) return false;
    if (overlaps(startInTz.minutes, endInTz.minutes, snackStart, snackEnd)) return false;
  }

  return true;
}

export default function DashboardPage() {
  const [appointments, setAppointments] = useState<DashboardAppointment[]>([]);
  const [timezoneByProfessional, setTimezoneByProfessional] = useState<Record<string, string>>({});
  const [scheduleByProfessional, setScheduleByProfessional] = useState<Record<string, ScheduleSettingsRow>>({});
  const [activeProfessionalIds, setActiveProfessionalIds] = useState<string[]>([]);
  const [status, setStatus] = useState<string | null>(null);
  const [professionals, setProfessionals] = useState<ProfessionalOption[]>([]);
  const [selectedProfessionalId, setSelectedProfessionalId] = useState<string>("");
  const [error, setError] = useState<string | null>(null);
  const [showPjTabs, setShowPjTabs] = useState(false);
  const [viewMode, setViewMode] = useState<ViewMode>("day");
  const [selectedDate, setSelectedDate] = useState(() => {
    const today = new Date();
    return `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, "0")}-${String(today.getDate()).padStart(2, "0")}`;
  });
  const [editingAppointmentId, setEditingAppointmentId] = useState<string | null>(null);
  const [editStartsAt, setEditStartsAt] = useState("");
  const [actionLoading, setActionLoading] = useState(false);

  const todayRange = useMemo(() => {
    const anchor = new Date(`${selectedDate}T00:00:00`);
    const start = new Date(anchor);
    if (viewMode === "week") {
      const weekday = start.getDay();
      const mondayOffset = weekday === 0 ? -6 : 1 - weekday;
      start.setDate(start.getDate() + mondayOffset);
    } else if (viewMode === "month") {
      start.setDate(1);
    }
    const end = new Date(start);
    if (viewMode === "day") {
      end.setDate(end.getDate() + 1);
    } else if (viewMode === "week") {
      end.setDate(end.getDate() + 7);
    } else {
      end.setMonth(end.getMonth() + 1);
    }
    return { start: start.toISOString(), end: end.toISOString() };
  }, [selectedDate, viewMode]);

  const calendarDays = useMemo(() => {
    if (viewMode === "day") return [] as Date[];
    const anchor = new Date(`${selectedDate}T00:00:00`);
    if (viewMode === "week") {
      const weekday = anchor.getDay();
      const mondayOffset = weekday === 0 ? -6 : 1 - weekday;
      const monday = new Date(anchor);
      monday.setDate(monday.getDate() + mondayOffset);
      return Array.from({ length: 7 }, (_, index) => {
        const day = new Date(monday);
        day.setDate(monday.getDate() + index);
        return day;
      });
    }

    const monthStart = new Date(anchor.getFullYear(), anchor.getMonth(), 1);
    const monthEnd = new Date(anchor.getFullYear(), anchor.getMonth() + 1, 0);
    const start = new Date(monthStart);
    const startOffset = start.getDay() === 0 ? -6 : 1 - start.getDay();
    start.setDate(start.getDate() + startOffset);
    const end = new Date(monthEnd);
    const endOffset = end.getDay() === 0 ? 0 : 7 - end.getDay();
    end.setDate(end.getDate() + endOffset);

    const days: Date[] = [];
    const cursor = new Date(start);
    while (cursor <= end) {
      days.push(new Date(cursor));
      cursor.setDate(cursor.getDate() + 1);
    }
    return days;
  }, [selectedDate, viewMode]);

  const dailyStats = useMemo(() => {
    const occupiedByDay: Record<string, number> = {};
    const activeStatuses = new Set(["scheduled", "confirmed", "pending"]);
    for (const item of appointments) {
      if (!activeStatuses.has(item.status.toLowerCase())) continue;
      const timezone = timezoneByProfessional[item.professional_id] ?? "America/Sao_Paulo";
      const key = new Intl.DateTimeFormat("en-CA", { timeZone: timezone }).format(new Date(item.starts_at));
      const schedule = scheduleByProfessional[item.professional_id];
      const slot = schedule?.slot_min ?? 30;
      const buffer = schedule?.buffer_min ?? 0;
      const slotWindow = Math.max(slot + buffer, 1);
      const startsAt = new Date(item.starts_at);
      const endsAt = new Date(item.ends_at);
      const durationMinutes = Math.max(Math.round((endsAt.getTime() - startsAt.getTime()) / 60000), 1);
      const occupiedUnits = Math.max(Math.ceil((durationMinutes + buffer) / slotWindow), 1);
      occupiedByDay[key] = (occupiedByDay[key] ?? 0) + occupiedUnits;
    }

    const statsByDay: Record<string, { occupied: number; free: number }> = {};
    for (const day of calendarDays) {
      const key = toDateKey(day);
      const weekday = day.getDay();
      let totalCapacity = 0;
      for (const professionalId of activeProfessionalIds) {
        const schedule = scheduleByProfessional[professionalId];
        const workdays = parseWorkdays(schedule?.workdays);
        if (!workdays.includes(weekday)) continue;

        const workHours =
          schedule?.work_hours && typeof schedule.work_hours === "object" && !Array.isArray(schedule.work_hours)
            ? (schedule.work_hours as Record<string, unknown>)
            : {};
        const overrides =
          workHours.daily_overrides && typeof workHours.daily_overrides === "object" && !Array.isArray(workHours.daily_overrides)
            ? (workHours.daily_overrides as Record<string, unknown>)
            : {};
        const dayRule =
          overrides[String(weekday)] && typeof overrides[String(weekday)] === "object" && !Array.isArray(overrides[String(weekday)])
            ? (overrides[String(weekday)] as Record<string, unknown>)
            : workHours;

        const start = typeof dayRule.start === "string" ? parseMinutes(dayRule.start) : parseMinutes("09:00");
        const end = typeof dayRule.end === "string" ? parseMinutes(dayRule.end) : parseMinutes("18:00");
        if (start === null || end === null || end <= start) continue;

        let minutes = end - start;
        const lunchBreak = parseBreakConfig(dayRule.lunch_break, "12:00", "13:00");
        if (lunchBreak.enabled) {
          const lunchStart = parseMinutes(lunchBreak.start);
          const lunchEnd = parseMinutes(lunchBreak.end);
          if (lunchStart !== null && lunchEnd !== null && lunchEnd > lunchStart) {
            minutes -= lunchEnd - lunchStart;
          }
        }
        const snackBreak = parseBreakConfig(dayRule.snack_break, "16:00", "16:15");
        if (snackBreak.enabled) {
          const snackStart = parseMinutes(snackBreak.start);
          const snackEnd = parseMinutes(snackBreak.end);
          if (snackStart !== null && snackEnd !== null && snackEnd > snackStart) {
            minutes -= snackEnd - snackStart;
          }
        }

        const slot = schedule?.slot_min ?? 30;
        const buffer = schedule?.buffer_min ?? 0;
        const slotWindow = Math.max(slot + buffer, 1);
        totalCapacity += Math.max(Math.floor(minutes / slotWindow), 0);
      }

      const occupied = occupiedByDay[key] ?? 0;
      statsByDay[key] = { occupied, free: Math.max(totalCapacity - occupied, 0) };
    }
    return statsByDay;
  }, [appointments, timezoneByProfessional, calendarDays, activeProfessionalIds, scheduleByProfessional]);

  function shiftDate(days: number) {
    const base = new Date(`${selectedDate}T00:00:00`);
    if (viewMode === "month") {
      base.setMonth(base.getMonth() + days);
    } else {
      base.setDate(base.getDate() + days);
    }
    const yyyy = base.getFullYear();
    const mm = String(base.getMonth() + 1).padStart(2, "0");
    const dd = String(base.getDate()).padStart(2, "0");
    setSelectedDate(`${yyyy}-${mm}-${dd}`);
  }

  useEffect(() => {
    const supabase = getSupabaseBrowserClient();

    async function loadAccountContext() {
      const {
        data: { user }
      } = await supabase.auth.getUser();

      if (!user) return;

      const { data: profileData } = await supabase
        .from("profiles")
        .select("tenant_id, role")
        .eq("id", user.id)
        .maybeSingle();

      const typedProfile = profileData as ProfileRow;
      if (!typedProfile) return;

      const canManage = ["owner", "admin", "receptionist"].includes(typedProfile.role);
      if (!canManage) return;

      const { data: tenantData } = await supabase
        .from("tenants")
        .select("type")
        .eq("id", typedProfile.tenant_id)
        .maybeSingle();

      const typedTenant = tenantData as TenantRow;
      setShowPjTabs(typedTenant?.type === "group");
    }

    async function load() {
      let appointmentQuery = supabase
        .from("appointments")
        .select(
          "id, professional_id, starts_at, ends_at, status, clients(full_name), services(name, duration_min), professionals(name)"
        )
        .gte("starts_at", todayRange.start)
        .lt("starts_at", todayRange.end)
        .order("starts_at", { ascending: true });

      if (selectedProfessionalId) {
        appointmentQuery = appointmentQuery.eq("professional_id", selectedProfessionalId);
      }

      const { data, error: queryError } = await appointmentQuery;

      if (queryError) {
        setError(queryError.message);
        return;
      }

      const rows = (data ?? []) as DashboardAppointment[];
      setAppointments(rows);

      const { data: professionalsData } = await supabase.from("professionals").select("id, name").eq("active", true).order("name");
      const professionalRows = (professionalsData ?? []) as ProfessionalOption[];
      setProfessionals(professionalRows);
      const ids = professionalRows.map((item) => item.id);
      setActiveProfessionalIds(selectedProfessionalId ? [selectedProfessionalId] : ids);

      if (ids.length === 0) {
        setTimezoneByProfessional({});
        setScheduleByProfessional({});
        return;
      }

      const { data: scheduleData } = await supabase
        .from("professional_schedule_settings")
        .select("professional_id, timezone, workdays, work_hours, slot_min, buffer_min")
        .in("professional_id", ids);

      const timezoneMap: Record<string, string> = {};
      const scheduleMap: Record<string, ScheduleSettingsRow> = {};
      for (const row of (scheduleData ?? []) as ScheduleSettingsRow[]) {
        if (row.professional_id) {
          timezoneMap[row.professional_id] = row.timezone || "America/Sao_Paulo";
          scheduleMap[row.professional_id] = row;
        }
      }
      setTimezoneByProfessional(timezoneMap);
      setScheduleByProfessional(scheduleMap);
    }

    loadAccountContext();
    load();
  }, [selectedProfessionalId, todayRange.end, todayRange.start]);

  async function handleDeleteAppointment(appointmentId: string) {
    if (!confirm("Deseja realmente excluir este agendamento?")) return;
    setError(null);
    setStatus(null);
    setActionLoading(true);
    const supabase = getSupabaseBrowserClient();
    const { error: deleteError } = await supabase.from("appointments").delete().eq("id", appointmentId);
    setActionLoading(false);
    if (deleteError) {
      setError(deleteError.message);
      return;
    }
    setAppointments((prev) => prev.filter((item) => item.id !== appointmentId));
    setStatus("Agendamento excluido com sucesso.");
  }

  async function handleSaveAppointment(appointment: DashboardAppointment) {
    if (!editStartsAt) return;
    setError(null);
    setStatus(null);

    const durationMinutes =
      appointment.services?.duration_min && appointment.services.duration_min > 0
        ? appointment.services.duration_min
        : Math.max(Math.round((new Date(appointment.ends_at).getTime() - new Date(appointment.starts_at).getTime()) / 60000), 1);
    const startsAtDate = new Date(editStartsAt);
    if (Number.isNaN(startsAtDate.getTime())) {
      setError("Data/hora invalida.");
      return;
    }
    const endsAtDate = new Date(startsAtDate.getTime() + durationMinutes * 60 * 1000);
    const startsAtIso = startsAtDate.toISOString();
    const endsAtIso = endsAtDate.toISOString();

    const settings = scheduleByProfessional[appointment.professional_id];
    if (!isWithinSchedule(settings, startsAtIso, endsAtIso)) {
      setError("Horario indisponivel.");
      return;
    }

    setActionLoading(true);
    const supabase = getSupabaseBrowserClient();
    const { error: updateError } = await supabase
      .from("appointments")
      .update({ starts_at: startsAtIso, ends_at: endsAtIso })
      .eq("id", appointment.id);
    setActionLoading(false);

    if (updateError) {
      if (updateError.code === "23P01") {
        setError("Ja existe um agendamento nesse horario para o profissional.");
        return;
      }
      setError(updateError.message);
      return;
    }

    setAppointments((prev) =>
      [...prev.map((item) => (item.id === appointment.id ? { ...item, starts_at: startsAtIso, ends_at: endsAtIso } : item))].sort(
        (a, b) => new Date(a.starts_at).getTime() - new Date(b.starts_at).getTime()
      )
    );
    setEditingAppointmentId(null);
    setEditStartsAt("");
    setStatus("Agendamento atualizado com sucesso.");
  }

  return (
    <section className="page-stack">
      <div className="card row align-center justify-between">
        <h1>Painel - Agenda</h1>
        <Link href="/appointments/new">Novo agendamento</Link>
      </div>

      <div className="card">
        <div className="row align-center">
          <button
            type="button"
            className={viewMode === "day" ? "" : "secondary"}
            onClick={() => setViewMode("day")}
          >
            Dia
          </button>
          <button
            type="button"
            className={viewMode === "week" ? "" : "secondary"}
            onClick={() => setViewMode("week")}
          >
            Semana
          </button>
          <button
            type="button"
            className={viewMode === "month" ? "" : "secondary"}
            onClick={() => setViewMode("month")}
          >
            Mes
          </button>
          <label className="inline-field">
            <span>Profissional</span>
            <select value={selectedProfessionalId} onChange={(e) => setSelectedProfessionalId(e.target.value)}>
              <option value="">Todos</option>
              {professionals.map((item) => (
                <option key={item.id} value={item.id}>
                  {item.name}
                </option>
              ))}
            </select>
          </label>
        </div>
      </div>

      <div className="card">
        <div className="date-nav-row">
          <button type="button" className="secondary" onClick={() => shiftDate(viewMode === "week" ? -7 : -1)}>
            <span className="date-nav-btn">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" aria-hidden="true">
                <path d="M15 18L9 12L15 6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
              {viewMode === "day" ? "Dia anterior" : viewMode === "week" ? "Semana anterior" : "Mes anterior"}
            </span>
          </button>
          <input className="date-nav-input" type="date" value={selectedDate} onChange={(e) => setSelectedDate(e.target.value)} />
          <button type="button" className="secondary" onClick={() => shiftDate(viewMode === "week" ? 7 : 1)}>
            <span className="date-nav-btn">
              {viewMode === "day" ? "Proximo dia" : viewMode === "week" ? "Proxima semana" : "Proximo mes"}
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" aria-hidden="true">
                <path d="M9 18L15 12L9 6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </span>
          </button>
        </div>
      </div>

      {showPjTabs ? (
        <div className="card panel-tabs">
          <span className="panel-tabs-label">Cadastros</span>
          <div className="panel-tabs-list">
            <Link href="/clients">Clientes</Link>
            <Link href="/services">Serviços</Link>
            <Link href="/professionals">Profissionais</Link>
            <Link href="/schedules">Horários</Link>
          </div>
        </div>
      ) : null}

      {error ? <div className="error">{error}</div> : null}
      {status ? <div className="notice">{status}</div> : null}

      {viewMode === "day" ? (
        <div className="card">
          <table>
            <thead>
              <tr>
                <th>Horário</th>
                <th>Cliente</th>
                <th>Serviço</th>
                <th>Profissional</th>
                <th>Status</th>
                <th>Ação</th>
              </tr>
            </thead>
            <tbody>
              {appointments.map((item) => {
                const meta = statusMeta(item.status);
                const timezone = timezoneByProfessional[item.professional_id] ?? "America/Sao_Paulo";

                return (
                  <tr key={item.id}>
                    <td>
                      {formatTimeInTimezone(item.starts_at, timezone)}
                      {" - "}
                      {formatTimeInTimezone(item.ends_at, timezone)}
                    </td>
                    <td>{item.clients?.full_name ?? "Sem cliente"}</td>
                    <td>{item.services?.name ?? "-"}</td>
                    <td>{item.professionals?.name ?? "-"}</td>
                    <td>
                      <span className={meta.className}>{meta.label}</span>
                    </td>
                    <td>
                      {editingAppointmentId === item.id ? (
                        <div className="col">
                          <input
                            type="datetime-local"
                            value={editStartsAt}
                            onChange={(e) => setEditStartsAt(e.target.value)}
                          />
                          <div className="row">
                            <button
                              type="button"
                              onClick={() => handleSaveAppointment(item)}
                              disabled={actionLoading || !editStartsAt}
                            >
                              Salvar
                            </button>
                            <button
                              type="button"
                              className="secondary"
                              onClick={() => {
                                setEditingAppointmentId(null);
                                setEditStartsAt("");
                              }}
                              disabled={actionLoading}
                            >
                              Cancelar
                            </button>
                          </div>
                        </div>
                      ) : (
                        <div className="row">
                          <button
                            type="button"
                            className="secondary"
                            onClick={() => {
                              setEditingAppointmentId(item.id);
                              setEditStartsAt(formatInputDateTimeFromIso(item.starts_at));
                            }}
                            disabled={actionLoading}
                          >
                            Alterar
                          </button>
                          <button
                            type="button"
                            className="danger"
                            onClick={() => handleDeleteAppointment(item.id)}
                            disabled={actionLoading}
                          >
                            Excluir
                          </button>
                        </div>
                      )}
                    </td>
                  </tr>
                );
              })}
              {appointments.length === 0 ? (
                <tr>
                  <td colSpan={6}>Nenhum agendamento para o periodo selecionado.</td>
                </tr>
              ) : null}
            </tbody>
          </table>
        </div>
      ) : (
        <div className="card">
          <div className="calendar-grid">
            {calendarDays.map((day) => {
              const key = toDateKey(day);
              const stats = dailyStats[key] ?? { occupied: 0, free: 0 };
              const isCurrentMonth = day.getMonth() === new Date(`${selectedDate}T00:00:00`).getMonth();
              const isSelected = key === selectedDate;
              const weekdayShort = day.toLocaleDateString("pt-BR", { weekday: "short" });
              const dayHeader = `${weekdayShort.charAt(0).toUpperCase()}${weekdayShort.slice(1)} ${day.getDate()}`;
              const occupancyClass =
                stats.occupied === 0 ? " calendar-day-empty" : stats.free === 0 ? " calendar-day-full" : "";
              return (
                <button
                  key={key}
                  type="button"
                  className={`calendar-day${isCurrentMonth ? "" : " calendar-day-muted"}${isSelected ? " calendar-day-selected" : ""}${occupancyClass}`}
                  onClick={() => {
                    setSelectedDate(key);
                    setViewMode("day");
                  }}
                >
                  <span className="calendar-day-label">{dayHeader}</span>
                  <span className="calendar-day-meta">Ocupados: {stats.occupied}</span>
                  <span className="calendar-day-meta">Livres: {stats.free}</span>
                </button>
              );
            })}
          </div>
        </div>
      )}
    </section>
  );
}

