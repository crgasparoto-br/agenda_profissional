"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { getSupabaseBrowserClient } from "@/lib/supabase-browser";
import { Button } from "@/components/ui/button";

type DashboardAppointment = {
  id: string;
  tenant_id: string;
  client_id: string | null;
  service_id: string;
  specialty_id: string | null;
  professional_id: string;
  source: string;
  starts_at: string;
  ends_at: string;
  status: string;
  cancellation_reason: string | null;
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
};
type BreakConfig = { enabled: boolean; start: string; end: string };
type UnavailabilityRow = {
  id: string;
  professional_id: string;
  starts_at: string;
  ends_at: string;
  reason: string | null;
};
type ProfessionalServiceRow = {
  professional_id: string;
  services: { duration_min: number | null } | null;
};

const CALENDAR_SLOT_MINUTES = 30;

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

  if (value === "done") {
    return { label: "Concluído", className: "status-pill status-confirmed" };
  }

  if (value === "rescheduled") {
    return { label: "Remarcado", className: "status-pill status-pending" };
  }

  if (value === "no_show") {
    return { label: "Não compareceu", className: "status-pill status-cancelled" };
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

function dateKeyInTimezone(isoValue: string, timezone: string) {
  const date = new Date(isoValue);
  if (Number.isNaN(date.getTime())) return null;
  try {
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone: timezone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit"
    }).formatToParts(date);
    const year = parts.find((part) => part.type === "year")?.value;
    const month = parts.find((part) => part.type === "month")?.value;
    const day = parts.find((part) => part.type === "day")?.value;
    if (!year || !month || !day) return null;
    return `${year}-${month}-${day}`;
  } catch {
    return null;
  }
}

function unavailableMinutesForDay(
  dayKey: string,
  timezone: string,
  rows: UnavailabilityRow[]
) {
  if (rows.length === 0) return 0;

  let total = 0;
  for (const row of rows) {
    const startKey = dateKeyInTimezone(row.starts_at, timezone);
    const endKey = dateKeyInTimezone(new Date(new Date(row.ends_at).getTime() - 1).toISOString(), timezone);
    if (!startKey || !endKey) continue;
    if (dayKey < startKey || dayKey > endKey) continue;

    const startInfo = getWeekdayAndMinutesInTimezone(row.starts_at, timezone);
    const endInfo = getWeekdayAndMinutesInTimezone(row.ends_at, timezone);
    if (!startInfo || !endInfo) continue;

    let dayStartMin = 0;
    let dayEndMin = 24 * 60;

    if (dayKey === startKey) {
      dayStartMin = Math.max(startInfo.minutes, 0);
    }
    if (dayKey === endKey) {
      dayEndMin = Math.min(endInfo.minutes, 24 * 60);
    }

    if (dayEndMin > dayStartMin) {
      total += dayEndMin - dayStartMin;
    }
  }

  return Math.max(total, 0);
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

function minutesToSlots(minutes: number, strategy: "ceil" | "floor" = "ceil") {
  const safeMinutes = Math.max(minutes, 0);
  const rawSlots = safeMinutes / CALENDAR_SLOT_MINUTES;
  return strategy === "floor" ? Math.floor(rawSlots) : Math.ceil(rawSlots);
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
  const [slotMinutesByProfessional, setSlotMinutesByProfessional] = useState<Record<string, number>>({});
  const [activeProfessionalIds, setActiveProfessionalIds] = useState<string[]>([]);
  const [status, setStatus] = useState<string | null>(null);
  const [selectedStatus, setSelectedStatus] = useState<string>("");
  const [professionals, setProfessionals] = useState<ProfessionalOption[]>([]);
  const [selectedProfessionalId, setSelectedProfessionalId] = useState<string>("");
  const [error, setError] = useState<string | null>(null);
  const [showPjTabs, setShowPjTabs] = useState(false);
  const [unavailabilityByProfessional, setUnavailabilityByProfessional] = useState<Record<string, UnavailabilityRow[]>>({});
  const [viewMode, setViewMode] = useState<ViewMode>("day");
  const [selectedDate, setSelectedDate] = useState(() => {
    const today = new Date();
    return `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, "0")}-${String(today.getDate()).padStart(2, "0")}`;
  });
  const [editingAppointmentId, setEditingAppointmentId] = useState<string | null>(null);
  const [editStartsAt, setEditStartsAt] = useState("");
  const [actionLoading, setActionLoading] = useState(false);
  const [refreshKey, setRefreshKey] = useState(0);

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
    const activeStatuses = new Set(["scheduled", "confirmed"]);
    for (const item of appointments) {
      const normalizedStatus = item.status.toLowerCase();
      if (selectedStatus) {
        if (normalizedStatus !== selectedStatus) continue;
      } else if (!activeStatuses.has(normalizedStatus)) {
        continue;
      }
      const timezone = timezoneByProfessional[item.professional_id] ?? "America/Sao_Paulo";
      const key = dateKeyInTimezone(item.starts_at, timezone);
      if (!key) continue;
      occupiedByDay[key] = (occupiedByDay[key] ?? 0) + 1;
    }

    const statsByDay: Record<string, { occupied: number; free: number }> = {};
    for (const day of calendarDays) {
      const key = toDateKey(day);
      const weekday = day.getDay();
      let totalCapacitySlots = 0;
      for (const professionalId of activeProfessionalIds) {
        const schedule = scheduleByProfessional[professionalId];
        const unavailableRanges = unavailabilityByProfessional[professionalId] ?? [];
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

        const timezone = schedule?.timezone || "America/Sao_Paulo";
        const unavailableMinutes = unavailableMinutesForDay(key, timezone, unavailableRanges);
        const availableMinutes = Math.max(minutes - unavailableMinutes, 0);
        const slotMinutes = Math.max(slotMinutesByProfessional[professionalId] ?? CALENDAR_SLOT_MINUTES, 1);
        totalCapacitySlots += Math.floor(availableMinutes / slotMinutes);
      }

      const occupied = occupiedByDay[key] ?? 0;
      statsByDay[key] = { occupied, free: Math.max(totalCapacitySlots - occupied, 0) };
    }
    return statsByDay;
  }, [
    appointments,
    selectedStatus,
    timezoneByProfessional,
    calendarDays,
    activeProfessionalIds,
    scheduleByProfessional,
    slotMinutesByProfessional,
    unavailabilityByProfessional
  ]);

  const filteredAppointments = useMemo(() => {
    if (!selectedStatus) return appointments;
    return appointments.filter((item) => item.status.toLowerCase() === selectedStatus);
  }, [appointments, selectedStatus]);

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
          "id, tenant_id, client_id, service_id, specialty_id, professional_id, source, starts_at, ends_at, status, cancellation_reason, clients(full_name), services(name, duration_min), professionals(name)"
        )
        .gte("starts_at", todayRange.start)
        .lt("starts_at", todayRange.end)
        .order("starts_at", { ascending: true });

      if (selectedProfessionalId) {
        appointmentQuery = appointmentQuery.eq("professional_id", selectedProfessionalId);
      }
      if (selectedStatus) {
        appointmentQuery = appointmentQuery.eq("status", selectedStatus as "scheduled" | "confirmed" | "cancelled" | "done" | "rescheduled" | "no_show");
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
        setSlotMinutesByProfessional({});
        setUnavailabilityByProfessional({});
        return;
      }

      const { data: scheduleData } = await supabase
        .from("professional_schedule_settings")
        .select("professional_id, timezone, workdays, work_hours")
        .in("professional_id", ids);
      const { data: professionalServicesData } = await supabase
        .from("professional_services")
        .select("professional_id, services(duration_min)")
        .in("professional_id", ids);

      const unavailabilityTable = (supabase as any).from("professional_unavailability");
      const { data: unavailabilityData } = await unavailabilityTable
        .select("id, professional_id, starts_at, ends_at, reason")
        .in("professional_id", ids)
        .order("starts_at", { ascending: true });

      const timezoneMap: Record<string, string> = {};
      const scheduleMap: Record<string, ScheduleSettingsRow> = {};
      const slotMinutesMap: Record<string, number> = {};
      const slotCandidatesByProfessional: Record<string, number[]> = {};
      const unavailabilityMap: Record<string, UnavailabilityRow[]> = {};
      for (const row of (scheduleData ?? []) as ScheduleSettingsRow[]) {
        if (row.professional_id) {
          timezoneMap[row.professional_id] = row.timezone || "America/Sao_Paulo";
          scheduleMap[row.professional_id] = row;
        }
      }
      for (const row of (professionalServicesData ?? []) as ProfessionalServiceRow[]) {
        if (!row.professional_id || !row.services) continue;
        const duration = row.services.duration_min ?? 0;
        const interval = 0;
        const blockMinutes = duration + interval;
        if (blockMinutes <= 0) continue;
        if (!slotCandidatesByProfessional[row.professional_id]) {
          slotCandidatesByProfessional[row.professional_id] = [];
        }
        slotCandidatesByProfessional[row.professional_id].push(blockMinutes);
      }
      for (const professionalId of ids) {
        const candidates = slotCandidatesByProfessional[professionalId] ?? [];
        slotMinutesMap[professionalId] =
          candidates.length > 0 ? Math.max(Math.min(...candidates), 1) : CALENDAR_SLOT_MINUTES;
      }
      for (const row of (unavailabilityData ?? []) as UnavailabilityRow[]) {
        if (!row.professional_id) continue;
        if (!unavailabilityMap[row.professional_id]) {
          unavailabilityMap[row.professional_id] = [];
        }
        unavailabilityMap[row.professional_id].push(row);
      }
      setTimezoneByProfessional(timezoneMap);
      setScheduleByProfessional(scheduleMap);
      setSlotMinutesByProfessional(slotMinutesMap);
      setUnavailabilityByProfessional(unavailabilityMap);
    }

    loadAccountContext();
    load();
  }, [selectedProfessionalId, selectedStatus, todayRange.end, todayRange.start, refreshKey]);

  async function handleCancelAppointment(appointmentId: string) {
    if (!confirm("Deseja realmente cancelar este agendamento?")) return;
    setError(null);
    setStatus(null);
    setActionLoading(true);
    const supabase = getSupabaseBrowserClient();
    const { error: updateError } = await supabase
      .from("appointments")
      .update({
        status: "cancelled",
        cancellation_reason: "Cancelado manualmente na agenda"
      })
      .eq("id", appointmentId);
    setActionLoading(false);
    if (updateError) {
      setError(updateError.message);
      return;
    }
    setAppointments((prev) =>
      prev.map((item) =>
        item.id === appointmentId
          ? { ...item, status: "cancelled", cancellation_reason: "Cancelado manualmente na agenda" }
          : item
      )
    );
    setStatus("Agendamento cancelado com sucesso.");
  }

  async function handleCompleteAppointment(appointmentId: string) {
    if (!confirm("Marcar este agendamento como Concluído?")) return;
    setError(null);
    setStatus(null);
    setActionLoading(true);
    const supabase = getSupabaseBrowserClient();
    const { error: updateError } = await supabase
      .from("appointments")
      .update({ status: "done" })
      .eq("id", appointmentId);
    setActionLoading(false);
    if (updateError) {
      setError(updateError.message);
      return;
    }
    setAppointments((prev) => prev.map((item) => (item.id === appointmentId ? { ...item, status: "done" } : item)));
    setStatus("Agendamento Concluído com sucesso.");
  }

  async function handleNoShowAppointment(appointmentId: string) {
    if (!confirm("Marcar este agendamento como no-show (Não compareceu)?")) return;
    setError(null);
    setStatus(null);
    setActionLoading(true);
    const supabase = getSupabaseBrowserClient();
    const { error: updateError } = await supabase
      .from("appointments")
      .update({ status: "no_show" })
      .eq("id", appointmentId);
    setActionLoading(false);
    if (updateError) {
      setError(updateError.message);
      return;
    }
    setAppointments((prev) => prev.map((item) => (item.id === appointmentId ? { ...item, status: "no_show" } : item)));
    setStatus("Agendamento marcado como no-show.");
  }

  async function handleRescheduleAppointment(appointment: DashboardAppointment) {
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
    const currentBlockedMinutes = Math.max(
      Math.round((new Date(appointment.ends_at).getTime() - new Date(appointment.starts_at).getTime()) / 60000),
      1
    );
    const endsAtDate = new Date(startsAtDate.getTime() + currentBlockedMinutes * 60 * 1000);
    const startsAtIso = startsAtDate.toISOString();
    const endsAtIso = endsAtDate.toISOString();

    const settings = scheduleByProfessional[appointment.professional_id];
    if (!isWithinSchedule(settings, startsAtIso, endsAtIso)) {
      setError("Horário indisponível.");
      return;
    }

    const unavailableRanges = unavailabilityByProfessional[appointment.professional_id] ?? [];
    const isOverlappingUnavailability = unavailableRanges.some((item) => {
      const start = new Date(item.starts_at);
      const end = new Date(item.ends_at);
      if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) return false;
      return startsAtDate < end && start < endsAtDate;
    });

    if (isOverlappingUnavailability) {
      setError("Profissional ausente no periodo selecionado.");
      return;
    }

    const sourceValue =
      appointment.source === "client_link" || appointment.source === "ai" || appointment.source === "professional"
        ? appointment.source
        : "professional";

    setActionLoading(true);
    const supabase = getSupabaseBrowserClient();
    const { data: inserted, error: insertError } = await supabase
      .from("appointments")
      .insert({
        tenant_id: appointment.tenant_id,
        client_id: appointment.client_id,
        service_id: appointment.service_id,
        specialty_id: appointment.specialty_id,
        professional_id: appointment.professional_id,
        starts_at: startsAtIso,
        ends_at: endsAtIso,
        status: "scheduled",
        source: sourceValue,
        assigned_at: new Date().toISOString()
      })
      .select("id")
      .single();

    if (insertError || !inserted) {
      setActionLoading(false);
      if (insertError?.code === "23P01") {
        setError("Já existe um agendamento nesse horário para o profissional.");
        return;
      }
      setError(insertError?.message ?? "Não foi possível remarcar.");
      return;
    }

    const { error: updateError } = await supabase
      .from("appointments")
      .update({
        status: "rescheduled",
        cancellation_reason: `Remarcado manualmente para ${inserted.id}`
      })
      .eq("id", appointment.id);
    setActionLoading(false);

    if (updateError) {
      setError(updateError.message);
      return;
    }

    setAppointments((prev) =>
      [
        ...prev.map((item) =>
          item.id === appointment.id
            ? { ...item, status: "rescheduled", cancellation_reason: `Remarcado manualmente para ${inserted.id}` }
            : item
        ),
        {
          ...appointment,
          id: inserted.id,
          starts_at: startsAtIso,
          ends_at: endsAtIso,
          status: "scheduled",
          cancellation_reason: null
        }
      ].sort((a, b) => new Date(a.starts_at).getTime() - new Date(b.starts_at).getTime())
    );
    setEditingAppointmentId(null);
    setEditStartsAt("");
    setStatus("Remarcacao concluida com sucesso.");
  }

  return (
    <section className="page-stack">
      <div className="card row align-center justify-between page-title-row">
        <h1>Agenda</h1>
        <Link href="/appointments/new">Novo agendamento</Link>
      </div>

      <div className="card">
        <div className="row align-center">
          <Button
            type="button"
            variant={viewMode === "day" ? "default" : "outline"}
            onClick={() => setViewMode("day")}
          >
            Dia
          </Button>
          <Button
            type="button"
            variant={viewMode === "week" ? "default" : "outline"}
            onClick={() => setViewMode("week")}
          >
            Semana
          </Button>
          <Button
            type="button"
            variant={viewMode === "month" ? "default" : "outline"}
            onClick={() => setViewMode("month")}
          >
            Mes
          </Button>
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
          <Button type="button" variant="outline" onClick={() => shiftDate(viewMode === "week" ? -7 : -1)}>
            <span className="date-nav-btn">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" aria-hidden="true">
                <path d="M15 18L9 12L15 6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
              {viewMode === "day" ? "Dia anterior" : viewMode === "week" ? "Semana anterior" : "Mes anterior"}
            </span>
          </Button>
          <input className="date-nav-input" type="date" value={selectedDate} onChange={(e) => setSelectedDate(e.target.value)} />
          <Button type="button" variant="outline" onClick={() => shiftDate(viewMode === "week" ? 7 : 1)}>
            <span className="date-nav-btn">
              {viewMode === "day" ? "Próximo dia" : viewMode === "week" ? "Próxima semana" : "Próximo mês"}
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" aria-hidden="true">
                <path d="M9 18L15 12L9 6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </span>
          </Button>
          <Button type="button" variant="outline" onClick={() => setRefreshKey((value) => value + 1)}>
            <span className="date-nav-btn">
              Atualizar agenda
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" aria-hidden="true">
                <path d="M21 12a9 9 0 1 1-2.64-6.36" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
                <path d="M21 3v6h-6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </span>
          </Button>
          <label className="inline-field date-nav-status-field">
            <span>Status</span>
            <select value={selectedStatus} onChange={(e) => setSelectedStatus(e.target.value)}>
              <option value="">Todos</option>
              <option value="scheduled">Agendado</option>
              <option value="confirmed">Confirmado</option>
              <option value="cancelled">Cancelado</option>
              <option value="done">Concluído</option>
              <option value="no_show">Não compareceu</option>
            </select>
          </label>
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
          <div className="table-wrap">
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
              {filteredAppointments.map((item) => {
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
                          <div className="row actions-row">
                            <Button
                              type="button"
                              onClick={() => handleRescheduleAppointment(item)}
                              disabled={actionLoading || !editStartsAt}
                            >
                              Remarcar
                            </Button>
                            <Button
                              type="button"
                              variant="outline"
                              onClick={() => {
                                setEditingAppointmentId(null);
                                setEditStartsAt("");
                              }}
                              disabled={actionLoading}
                            >
                              Cancelar
                            </Button>
                          </div>
                        </div>
                      ) : (
                        <div className="row actions-row">
                          <Button
                            type="button"
                            variant="outline"
                            onClick={() => {
                              setEditingAppointmentId(item.id);
                              setEditStartsAt(formatInputDateTimeFromIso(item.starts_at));
                            }}
                            disabled={actionLoading}
                          >
                            Remarcar
                          </Button>
                          <Button
                            type="button"
                            variant="destructive"
                            onClick={() => handleCancelAppointment(item.id)}
                            disabled={actionLoading}
                          >
                            Cancelar
                          </Button>
                          <Button
                            type="button"
                            variant="outline"
                            onClick={() => handleCompleteAppointment(item.id)}
                            disabled={actionLoading || ["done", "cancelled", "rescheduled", "no_show"].includes(item.status.toLowerCase())}
                          >
                            Concluir
                          </Button>
                          <Button
                            type="button"
                            variant="outline"
                            onClick={() => handleNoShowAppointment(item.id)}
                            disabled={actionLoading || ["done", "cancelled", "rescheduled", "no_show"].includes(item.status.toLowerCase())}
                          >
                            Não compareceu
                          </Button>
                        </div>
                      )}
                    </td>
                  </tr>
                );
              })}
              {filteredAppointments.length === 0 ? (
                <tr>
                  <td colSpan={6}>Nenhum agendamento para o periodo selecionado.</td>
                </tr>
              ) : null}
            </tbody>
          </table>
          </div>
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


