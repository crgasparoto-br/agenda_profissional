"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { getSupabaseBrowserClient } from "@/lib/supabase-browser";
import { Button } from "@/components/ui/button";

type PunctualityStatus = "no_data" | "on_time" | "late_ok" | "late_critical";

type NotificationMetricRow = {
  channel: "in_app" | "push" | "sms" | "whatsapp";
  status: "queued" | "sent" | "failed" | "read";
  type: string;
};

type PunctualityEventMetricRow = {
  new_status: PunctualityStatus;
};

type EtaSnapshotMetricRow = {
  provider: string | null;
  eta_minutes: number | null;
};

type InvestigationAppointmentRow = {
  id: string;
  starts_at: string;
  status: string;
  punctuality_status: PunctualityStatus | null;
  clients: { full_name: string | null } | null;
  professionals: { name: string | null } | null;
  services: { name: string | null } | null;
};

type InvestigationSnapshotRow = {
  id: string;
  captured_at: string;
  status: PunctualityStatus;
  eta_minutes: number | null;
  predicted_arrival_delay: number | null;
  provider: string | null;
  traffic_level: string | null;
};

type InvestigationEventRow = {
  id: string;
  occurred_at: string;
  old_status: PunctualityStatus;
  new_status: PunctualityStatus;
  predicted_arrival_delay: number | null;
  source: string | null;
};

type InvestigationNotificationRow = {
  id: string;
  channel: "in_app" | "push" | "sms" | "whatsapp";
  type: string;
  status: "queued" | "sent" | "failed" | "read";
  created_at: string;
  provider_message_id: string | null;
};

type InvestigationConsentRow = {
  id: string;
  consent_status: "granted" | "denied" | "revoked" | "expired";
  consent_text_version: string;
  source_channel: string;
  granted_at: string | null;
  expires_at: string | null;
  updated_at: string;
};

type AppointmentInvestigation = {
  appointment: InvestigationAppointmentRow | null;
  snapshots: InvestigationSnapshotRow[];
  events: InvestigationEventRow[];
  notifications: InvestigationNotificationRow[];
  consents: InvestigationConsentRow[];
};

type DashboardMetrics = {
  pushQueued: number;
  pushSent: number;
  pushFailed: number;
  whatsappQueued: number;
  whatsappSent: number;
  whatsappFailed: number;
  inAppQueued: number;
  inAppSent: number;
  inAppRead: number;
  onTimeEvents: number;
  lateOkEvents: number;
  lateCriticalEvents: number;
  etaSnapshots: number;
  etaWithData: number;
  etaNoData: number;
  etaProviderFailed: number;
};

const EMPTY_METRICS: DashboardMetrics = {
  pushQueued: 0,
  pushSent: 0,
  pushFailed: 0,
  whatsappQueued: 0,
  whatsappSent: 0,
  whatsappFailed: 0,
  inAppQueued: 0,
  inAppSent: 0,
  inAppRead: 0,
  onTimeEvents: 0,
  lateOkEvents: 0,
  lateCriticalEvents: 0,
  etaSnapshots: 0,
  etaWithData: 0,
  etaNoData: 0,
  etaProviderFailed: 0
};

function statusMeta(status: string) {
  const value = status.toLowerCase();
  if (value === "scheduled") return { label: "Agendado", className: "status-pill status-pending" };
  if (value === "confirmed") return { label: "Confirmado", className: "status-pill status-confirmed" };
  if (value === "cancelled") return { label: "Cancelado", className: "status-pill status-cancelled" };
  if (value === "pending") return { label: "Pendente", className: "status-pill status-pending" };
  if (value === "done") return { label: "Concluído", className: "status-pill status-confirmed" };
  if (value === "rescheduled") return { label: "Remarcado", className: "status-pill status-pending" };
  if (value === "no_show") return { label: "Não compareceu", className: "status-pill status-cancelled" };
  return { label: status, className: "status-pill status-pending" };
}

function punctualityMeta(status: PunctualityStatus | null) {
  const value = (status ?? "no_data").toLowerCase();
  if (value === "on_time") return { label: "No horário", className: "status-pill punctuality-on-time" };
  if (value === "late_ok") return { label: "Atraso leve", className: "status-pill punctuality-late-ok" };
  if (value === "late_critical") return { label: "Atraso crítico", className: "status-pill punctuality-late-critical" };
  return { label: "Sem dados", className: "status-pill punctuality-no-data" };
}

function formatAlertDateTime(isoValue: string) {
  const dt = new Date(isoValue);
  if (Number.isNaN(dt.getTime())) return "--/-- --:--";
  return new Intl.DateTimeFormat("pt-BR", {
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false
  }).format(dt);
}

function consentStatusLabel(status: InvestigationConsentRow["consent_status"]) {
  if (status === "granted") return "Concedido";
  if (status === "denied") return "Negado";
  if (status === "revoked") return "Revogado";
  return "Expirado";
}

function notificationChannelLabel(channel: InvestigationNotificationRow["channel"]) {
  if (channel === "in_app") return "No app";
  if (channel === "push") return "Push";
  if (channel === "whatsapp") return "WhatsApp";
  return "SMS";
}

function notificationStatusLabel(status: InvestigationNotificationRow["status"]) {
  if (status === "queued") return "Na fila";
  if (status === "sent") return "Enviado";
  if (status === "failed") return "Falha";
  return "Lido";
}

function notificationTypeLabel(type: string) {
  if (type === "punctuality_on_time") return "Pontualidade: no horario";
  if (type === "punctuality_late_ok") return "Pontualidade: atraso leve";
  if (type === "punctuality_late_critical") return "Pontualidade: atraso critico";
  return type;
}

function sourceLabel(source: string | null) {
  if (!source) return "-";
  if (source === "web_dashboard") return "Painel web";
  if (source === "mobile_app") return "App mobile";
  if (source === "monitor") return "Monitor";
  return source;
}

function csvCell(value: string) {
  return `"${value.replace(/"/g, "\"\"")}"`;
}

export default function PunctualityAuditPage() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [metrics, setMetrics] = useState<DashboardMetrics>(EMPTY_METRICS);
  const [investigationAppointmentId, setInvestigationAppointmentId] = useState("");
  const [investigationLoading, setInvestigationLoading] = useState(false);
  const [investigationActionLoading, setInvestigationActionLoading] = useState(false);
  const [investigationError, setInvestigationError] = useState<string | null>(null);
  const [investigationData, setInvestigationData] = useState<AppointmentInvestigation | null>(null);

  const pushDeliveryRate = useMemo(() => {
    const attempted = metrics.pushSent + metrics.pushFailed;
    if (attempted === 0) return 0;
    return Math.round((metrics.pushSent / attempted) * 100);
  }, [metrics.pushSent, metrics.pushFailed]);

  const whatsappDeliveryRate = useMemo(() => {
    const attempted = metrics.whatsappSent + metrics.whatsappFailed;
    if (attempted === 0) return 0;
    return Math.round((metrics.whatsappSent / attempted) * 100);
  }, [metrics.whatsappSent, metrics.whatsappFailed]);

  const etaQualityRate = useMemo(() => {
    if (metrics.etaSnapshots === 0) return 0;
    return Math.round((metrics.etaWithData / metrics.etaSnapshots) * 100);
  }, [metrics.etaSnapshots, metrics.etaWithData]);

  async function loadMetrics() {
    setLoading(true);
    setError(null);
    const supabase = getSupabaseBrowserClient();
    const metricsStart = new Date();
    metricsStart.setDate(metricsStart.getDate() - 7);
    const metricsStartIso = metricsStart.toISOString();

    const { data: notificationMetricsData, error: notificationError } = await supabase
      .from("notification_log")
      .select("channel, status, type")
      .in("channel", ["in_app", "push", "whatsapp"])
      .in("type", ["punctuality_on_time", "punctuality_late_ok", "punctuality_late_critical"])
      .gte("created_at", metricsStartIso);

    if (notificationError) {
      setLoading(false);
      setError(notificationError.message);
      return;
    }

    const { data: punctualityEventsData, error: eventsError } = await supabase
      .from("punctuality_events")
      .select("new_status")
      .gte("occurred_at", metricsStartIso);

    if (eventsError) {
      setLoading(false);
      setError(eventsError.message);
      return;
    }

    const { data: etaSnapshotsData, error: snapshotsError } = await supabase
      .from("appointment_eta_snapshots")
      .select("provider, eta_minutes")
      .gte("captured_at", metricsStartIso);

    if (snapshotsError) {
      setLoading(false);
      setError(snapshotsError.message);
      return;
    }

    const nextMetrics: DashboardMetrics = { ...EMPTY_METRICS };

    for (const row of (notificationMetricsData ?? []) as NotificationMetricRow[]) {
      if (row.channel === "push") {
        if (row.status === "queued") nextMetrics.pushQueued += 1;
        if (row.status === "sent") nextMetrics.pushSent += 1;
        if (row.status === "failed") nextMetrics.pushFailed += 1;
      }
      if (row.channel === "in_app") {
        if (row.status === "queued") nextMetrics.inAppQueued += 1;
        if (row.status === "sent") nextMetrics.inAppSent += 1;
        if (row.status === "read") nextMetrics.inAppRead += 1;
      }
      if (row.channel === "whatsapp") {
        if (row.status === "queued") nextMetrics.whatsappQueued += 1;
        if (row.status === "sent") nextMetrics.whatsappSent += 1;
        if (row.status === "failed") nextMetrics.whatsappFailed += 1;
      }
    }

    for (const event of (punctualityEventsData ?? []) as PunctualityEventMetricRow[]) {
      if (event.new_status === "on_time") nextMetrics.onTimeEvents += 1;
      if (event.new_status === "late_ok") nextMetrics.lateOkEvents += 1;
      if (event.new_status === "late_critical") nextMetrics.lateCriticalEvents += 1;
    }

    for (const snapshot of (etaSnapshotsData ?? []) as EtaSnapshotMetricRow[]) {
      nextMetrics.etaSnapshots += 1;
      if (typeof snapshot.eta_minutes === "number") nextMetrics.etaWithData += 1;
      else nextMetrics.etaNoData += 1;
      if (typeof snapshot.provider === "string" && snapshot.provider.endsWith("_failed")) {
        nextMetrics.etaProviderFailed += 1;
      }
    }

    setMetrics(nextMetrics);
    setLoading(false);
  }

  async function loadInvestigationByAppointmentId(appointmentId: string) {
    const normalizedId = appointmentId.trim();
    if (!normalizedId) {
      setInvestigationError("Informe o ID do agendamento para investigar.");
      setInvestigationData(null);
      return;
    }

    setInvestigationLoading(true);
    setInvestigationError(null);
    const supabase = getSupabaseBrowserClient();

    const { data: appointmentData, error: appointmentError } = await supabase
      .from("appointments")
      .select(
        "id, starts_at, status, punctuality_status, clients(full_name), professionals(name), services(name)"
      )
      .eq("id", normalizedId)
      .maybeSingle();

    if (appointmentError) {
      setInvestigationLoading(false);
      setInvestigationError(appointmentError.message);
      setInvestigationData(null);
      return;
    }

    if (!appointmentData) {
      setInvestigationLoading(false);
      setInvestigationError("ID do agendamento não encontrado no tenant atual.");
      setInvestigationData(null);
      return;
    }

    const { data: snapshotsData } = await supabase
      .from("appointment_eta_snapshots")
      .select("id, captured_at, status, eta_minutes, predicted_arrival_delay, provider, traffic_level")
      .eq("appointment_id", normalizedId)
      .order("captured_at", { ascending: false })
      .limit(15);

    const { data: eventsData } = await supabase
      .from("punctuality_events")
      .select("id, occurred_at, old_status, new_status, predicted_arrival_delay, source")
      .eq("appointment_id", normalizedId)
      .order("occurred_at", { ascending: false })
      .limit(15);

    const { data: notificationsData } = await supabase
      .from("notification_log")
      .select("id, channel, type, status, created_at, provider_message_id")
      .eq("appointment_id", normalizedId)
      .order("created_at", { ascending: false })
      .limit(20);

    const { data: consentsData } = await supabase
      .from("client_location_consents")
      .select("id, consent_status, consent_text_version, source_channel, granted_at, expires_at, updated_at")
      .eq("appointment_id", normalizedId)
      .order("updated_at", { ascending: false })
      .limit(20);

    setInvestigationData({
      appointment: appointmentData as InvestigationAppointmentRow,
      snapshots: (snapshotsData ?? []) as InvestigationSnapshotRow[],
      events: (eventsData ?? []) as InvestigationEventRow[],
      notifications: (notificationsData ?? []) as InvestigationNotificationRow[],
      consents: (consentsData ?? []) as InvestigationConsentRow[]
    });
    setInvestigationLoading(false);
  }

  async function investigateByAppointmentId() {
    await loadInvestigationByAppointmentId(investigationAppointmentId);
  }

  async function revokeConsent(consentId: string) {
    if (!investigationData?.appointment) return;
    if (!confirm("Deseja revogar este consentimento de localização?")) return;

    setInvestigationActionLoading(true);
    setInvestigationError(null);
    const supabase = getSupabaseBrowserClient();
    const now = new Date().toISOString();
    const { error: revokeError } = await supabase
      .from("client_location_consents")
      .update({
        consent_status: "revoked",
        expires_at: now,
        source_channel: "web_dashboard",
        updated_at: now
      })
      .eq("id", consentId);

    setInvestigationActionLoading(false);
    if (revokeError) {
      setInvestigationError(revokeError.message);
      return;
    }

    await loadInvestigationByAppointmentId(investigationData.appointment.id);
  }

  function exportConsentTrailCsv() {
    if (!investigationData?.appointment || investigationData.consents.length === 0) {
      setInvestigationError("Não há consentimentos para exportar no agendamento investigado.");
      return;
    }

    const appointmentId = investigationData.appointment.id;
    const clientName = investigationData.appointment.clients?.full_name ?? "Cliente não identificado";
    const header = [
      "appointment_id",
      "cliente",
      "status_consentimento",
      "versao_termo",
      "canal_origem",
      "concedido_em",
      "expira_em",
      "atualizado_em",
      "consentimento_id"
    ];

    const lines = investigationData.consents.map((consent) =>
      [
        appointmentId,
        clientName,
        consentStatusLabel(consent.consent_status),
        consent.consent_text_version || "",
        consent.source_channel || "",
        consent.granted_at ? formatAlertDateTime(consent.granted_at) : "",
        consent.expires_at ? formatAlertDateTime(consent.expires_at) : "",
        formatAlertDateTime(consent.updated_at),
        consent.id
      ]
        .map((item) => csvCell(item))
        .join(";")
    );

    const csv = [header.join(";"), ...lines].join("\n");
    const blob = new Blob(["\uFEFF" + csv], { type: "text/csv;charset=utf-8;" });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = `consentimentos_${appointmentId}.csv`;
    document.body.appendChild(anchor);
    anchor.click();
    document.body.removeChild(anchor);
    URL.revokeObjectURL(url);
  }

  useEffect(() => {
    loadMetrics();
  }, []);

  return (
    <section className="page-stack">
      <div className="card row align-center justify-between page-title-row">
        <div>
          <h1>Auditoria de Pontualidade</h1>
          <small className="text-muted">Métricas operacionais e investigação detalhada por agendamento.</small>
        </div>
        <div className="row align-center">
          <Button type="button" variant="outline" onClick={loadMetrics} disabled={loading}>
            {loading ? "Atualizando..." : "Atualizar métricas"}
          </Button>
          <Link href="/dashboard">Voltar para Agenda</Link>
        </div>
      </div>

      {error ? <p className="error">{error}</p> : null}

      <div className="card">
        <div className="row align-center justify-between">
          <h2>Métricas operacionais (7 dias)</h2>
          {loading ? <small className="text-muted">Atualizando...</small> : null}
        </div>
        <div className="metrics-grid">
          <div className="metric-item">
            <strong>Notificações push enviadas</strong>
            <span>{metrics.pushSent}</span>
          </div>
          <div className="metric-item">
            <strong>Falhas em push</strong>
            <span>{metrics.pushFailed}</span>
          </div>
          <div className="metric-item">
            <strong>Taxa entrega push</strong>
            <span>{pushDeliveryRate}%</span>
          </div>
          <div className="metric-item">
            <strong>WhatsApp enviados</strong>
            <span>{metrics.whatsappSent}</span>
          </div>
          <div className="metric-item">
            <strong>WhatsApp com falha</strong>
            <span>{metrics.whatsappFailed}</span>
          </div>
          <div className="metric-item">
            <strong>Taxa entrega WhatsApp</strong>
            <span>{whatsappDeliveryRate}%</span>
          </div>
          <div className="metric-item">
            <strong>Lidos no app</strong>
            <span>{metrics.inAppRead}</span>
          </div>
          <div className="metric-item">
            <strong>Registros de ETA</strong>
            <span>{metrics.etaSnapshots}</span>
          </div>
          <div className="metric-item">
            <strong>Precisão ETA (indicador)</strong>
            <span>{etaQualityRate}%</span>
          </div>
          <div className="metric-item">
            <strong>Falhas do provedor de ETA</strong>
            <span>{metrics.etaProviderFailed}</span>
          </div>
          <div className="metric-item">
            <strong>Eventos atraso leve</strong>
            <span>{metrics.lateOkEvents}</span>
          </div>
          <div className="metric-item">
            <strong>Eventos atraso crítico</strong>
            <span>{metrics.lateCriticalEvents}</span>
          </div>
        </div>
        <small className="text-muted">
          Precisão ETA (indicador): percentual de registros com ETA calculado no período.
        </small>
        <br />
        <small className="text-muted">ETA significa Tempo Estimado de Chegada.</small>
      </div>

      <div className="card">
        <div className="row align-center justify-between">
          <h2>Investigação por ID do agendamento</h2>
          {investigationLoading ? <small className="text-muted">Investigando...</small> : null}
        </div>
        <div className="row align-center investigation-controls">
          <label className="inline-field">
            <span>ID do agendamento</span>
            <input
              type="text"
              value={investigationAppointmentId}
              onChange={(e) => setInvestigationAppointmentId(e.target.value)}
              placeholder="UUID do agendamento"
            />
          </label>
          <Button type="button" variant="outline" onClick={investigateByAppointmentId} disabled={investigationLoading}>
            Investigar
          </Button>
          <Button
            type="button"
            variant="outline"
            onClick={exportConsentTrailCsv}
            disabled={investigationLoading || !investigationData?.appointment || investigationData.consents.length === 0}
          >
            Exportar consentimentos em CSV
          </Button>
        </div>
        {investigationError ? <p className="error">{investigationError}</p> : null}
        {investigationData?.appointment ? (
          <div className="investigation-stack">
            <div className="investigation-summary">
              <strong>
                Cliente: {investigationData.appointment.clients?.full_name ?? "Cliente não identificado"}
              </strong>
              <span>Profissional: {investigationData.appointment.professionals?.name ?? "-"}</span>
              <span>Serviço: {investigationData.appointment.services?.name ?? "-"}</span>
              <span>Data/Hora: {formatAlertDateTime(investigationData.appointment.starts_at)}</span>
              <span>Status agenda: {statusMeta(investigationData.appointment.status).label}</span>
              <span>Pontualidade: {punctualityMeta(investigationData.appointment.punctuality_status).label}</span>
            </div>

            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Registros de ETA</th>
                    <th>Pontualidade</th>
                    <th>Detalhe</th>
                    <th>Provedor</th>
                    <th>Trânsito</th>
                  </tr>
                </thead>
                <tbody>
                  {investigationData.snapshots.length === 0 ? (
                    <tr>
                      <td colSpan={5}>Sem registros de ETA para este agendamento.</td>
                    </tr>
                  ) : (
                    investigationData.snapshots.map((item) => {
                      const meta = punctualityMeta(item.status);
                      const detail =
                        typeof item.eta_minutes === "number" && typeof item.predicted_arrival_delay === "number"
                          ? `ETA ${item.eta_minutes} min • atraso ${item.predicted_arrival_delay} min`
                          : typeof item.eta_minutes === "number"
                            ? `ETA ${item.eta_minutes} min`
                            : "Sem tempo estimado";

                      return (
                        <tr key={item.id}>
                          <td>{formatAlertDateTime(item.captured_at)}</td>
                          <td>
                            <span className={meta.className}>{meta.label}</span>
                          </td>
                          <td>{detail}</td>
                          <td>{item.provider ?? "-"}</td>
                          <td>{item.traffic_level ?? "-"}</td>
                        </tr>
                      );
                    })
                  )}
                </tbody>
              </table>
            </div>

            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Eventos</th>
                    <th>Transição</th>
                    <th>Fonte</th>
                    <th>Atraso previsto</th>
                  </tr>
                </thead>
                <tbody>
                  {investigationData.events.length === 0 ? (
                    <tr>
                      <td colSpan={4}>Sem eventos de pontualidade para este agendamento.</td>
                    </tr>
                  ) : (
                    investigationData.events.map((event) => (
                      <tr key={event.id}>
                        <td>{formatAlertDateTime(event.occurred_at)}</td>
                        <td>
                          {punctualityMeta(event.old_status).label} → {punctualityMeta(event.new_status).label}
                        </td>
                        <td>{sourceLabel(event.source)}</td>
                        <td>{typeof event.predicted_arrival_delay === "number" ? `${event.predicted_arrival_delay} min` : "-"}</td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>

            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Notificações</th>
                    <th>Canal</th>
                    <th>Tipo</th>
                    <th>Status</th>
                    <th>ID do provedor</th>
                  </tr>
                </thead>
                <tbody>
                  {investigationData.notifications.length === 0 ? (
                    <tr>
                      <td colSpan={5}>Sem notificações para este agendamento.</td>
                    </tr>
                  ) : (
                    investigationData.notifications.map((notification) => (
                      <tr key={notification.id}>
                        <td>{formatAlertDateTime(notification.created_at)}</td>
                        <td>{notificationChannelLabel(notification.channel)}</td>
                        <td>{notificationTypeLabel(notification.type)}</td>
                        <td>{notificationStatusLabel(notification.status)}</td>
                        <td>{notification.provider_message_id ?? "-"}</td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>

            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Consentimentos</th>
                    <th>Status</th>
                    <th>Versão termo</th>
                    <th>Canal</th>
                    <th>Concedido em</th>
                    <th>Expira em</th>
                    <th>Ação</th>
                  </tr>
                </thead>
                <tbody>
                  {investigationData.consents.length === 0 ? (
                    <tr>
                      <td colSpan={7}>Sem registros de consentimento para este agendamento.</td>
                    </tr>
                  ) : (
                    investigationData.consents.map((consent) => {
                      const consentClass =
                        consent.consent_status === "granted"
                          ? "status-pill punctuality-on-time"
                          : consent.consent_status === "denied"
                            ? "status-pill punctuality-late-critical"
                            : "status-pill punctuality-late-ok";
                      const consentLabel = consentStatusLabel(consent.consent_status);
                      return (
                        <tr key={consent.id}>
                          <td>{formatAlertDateTime(consent.updated_at)}</td>
                          <td>
                            <span className={consentClass}>{consentLabel}</span>
                          </td>
                          <td>{consent.consent_text_version || "-"}</td>
                          <td>{consent.source_channel || "-"}</td>
                          <td>{consent.granted_at ? formatAlertDateTime(consent.granted_at) : "-"}</td>
                          <td>{consent.expires_at ? formatAlertDateTime(consent.expires_at) : "-"}</td>
                          <td>
                            {consent.consent_status === "granted" ? (
                              <Button
                                type="button"
                                variant="outline"
                                onClick={() => revokeConsent(consent.id)}
                                disabled={investigationActionLoading}
                              >
                                Revogar
                              </Button>
                            ) : (
                              "-"
                            )}
                          </td>
                        </tr>
                      );
                    })
                  )}
                </tbody>
              </table>
            </div>
          </div>
        ) : null}
      </div>
    </section>
  );
}
