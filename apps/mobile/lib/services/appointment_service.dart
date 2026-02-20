import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/appointment.dart';
import '../models/app_exception.dart';
import 'response_utils.dart';

class ProfessionalScheduleSettings {
  const ProfessionalScheduleSettings({
    required this.professionalId,
    required this.timezone,
    required this.workdays,
    required this.workHours,
  });

  final String professionalId;
  final String timezone;
  final dynamic workdays;
  final dynamic workHours;
}

class AppointmentService {
  AppointmentService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<AppointmentItem>> getDailyAppointments(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return getAppointmentsRange(start: start, end: end);
  }

  Future<List<AppointmentItem>> getAppointmentsRange({
    required DateTime start,
    required DateTime end,
    String? professionalId,
  }) async {
    var query = _client
        .from('appointments')
        .select(
            'id, tenant_id, client_id, service_id, specialty_id, professional_id, source, starts_at, ends_at, status, cancellation_reason, punctuality_status, punctuality_eta_min, punctuality_predicted_delay_min, professionals(name), services(name, duration_min, interval_min), clients(full_name)')
        .gte('starts_at', start.toUtc().toIso8601String())
        .lt('starts_at', end.toUtc().toIso8601String());
    if (professionalId != null && professionalId.isNotEmpty) {
      query = query.eq('professional_id', professionalId);
    }

    final response = await query.order('starts_at');

    return List<Map<String, dynamic>>.from(response)
        .map(AppointmentItem.fromJson)
        .toList();
  }

  Future<Map<String, String>> getProfessionalTimezones(
      List<String> professionalIds) async {
    if (professionalIds.isEmpty) return {};

    final response = await _client
        .from('professional_schedule_settings')
        .select('professional_id, timezone')
        .inFilter('professional_id', professionalIds);

    final map = <String, String>{};
    for (final row in List<Map<String, dynamic>>.from(response)) {
      final professionalId = row['professional_id'];
      final timezone = row['timezone'];
      if (professionalId is String &&
          timezone is String &&
          timezone.isNotEmpty) {
        map[professionalId] = timezone;
      }
    }

    return map;
  }

  Future<Map<String, ProfessionalScheduleSettings>>
      getProfessionalScheduleSettings(List<String> professionalIds) async {
    if (professionalIds.isEmpty) return {};

    final response = await _client
        .from('professional_schedule_settings')
        .select('professional_id, timezone, workdays, work_hours')
        .inFilter('professional_id', professionalIds);

    final map = <String, ProfessionalScheduleSettings>{};
    for (final row in List<Map<String, dynamic>>.from(response)) {
      final professionalId = row['professional_id'];
      if (professionalId is! String || professionalId.isEmpty) continue;

      map[professionalId] = ProfessionalScheduleSettings(
        professionalId: professionalId,
        timezone: (row['timezone'] as String?)?.isNotEmpty == true
            ? row['timezone'] as String
            : 'America/Sao_Paulo',
        workdays: row['workdays'],
        workHours: row['work_hours'],
      );
    }

    return map;
  }

  Future<Map<String, int>> getProfessionalSlotMinutes(
      List<String> professionalIds) async {
    if (professionalIds.isEmpty) return {};

    final response = await _client
        .from('professional_services')
        .select('professional_id, services(duration_min, interval_min)')
        .inFilter('professional_id', professionalIds);

    final slotCandidates = <String, List<int>>{};
    for (final row in List<Map<String, dynamic>>.from(response)) {
      final professionalId = row['professional_id'];
      if (professionalId is! String || professionalId.isEmpty) continue;

      final serviceRaw = row['services'];
      final service = serviceRaw is Map<String, dynamic>
          ? serviceRaw
          : serviceRaw is List &&
                  serviceRaw.isNotEmpty &&
                  serviceRaw.first is Map<String, dynamic>
              ? serviceRaw.first as Map<String, dynamic>
              : null;
      if (service == null) continue;

      final duration = (service['duration_min'] as num?)?.toInt() ?? 0;
      final interval = (service['interval_min'] as num?)?.toInt() ?? 0;
      final blockMinutes = duration + interval;
      if (blockMinutes <= 0) continue;

      slotCandidates
          .putIfAbsent(professionalId, () => <int>[])
          .add(blockMinutes);
    }

    final slotMinutesByProfessional = <String, int>{};
    for (final professionalId in professionalIds) {
      final candidates = slotCandidates[professionalId];
      if (candidates == null || candidates.isEmpty) {
        slotMinutesByProfessional[professionalId] = 30;
        continue;
      }
      candidates.sort();
      slotMinutesByProfessional[professionalId] = candidates.first;
    }

    return slotMinutesByProfessional;
  }

  Future<void> createAppointment(CreateAppointmentInput input) async {
    final response = await _client.functions
        .invoke('create-appointment', body: input.toJson());

    ensureExpectedStatus(
      actualStatus: response.status,
      expectedStatus: 201,
      operation: 'create-appointment',
      responseData: response.data,
    );
  }

  Future<void> updateAppointmentStatus({
    required String appointmentId,
    required String status,
    String? cancellationReason,
  }) async {
    final payload = <String, dynamic>{'status': status};
    if (cancellationReason != null) {
      payload['cancellation_reason'] = cancellationReason;
    }

    final response = await _client
        .from('appointments')
        .update(payload)
        .eq('id', appointmentId)
        .select('id')
        .maybeSingle();

    if (response == null) {
      throw const AppException(
        message: 'Agendamento não encontrado para atualização.',
        code: 'appointment_not_found',
      );
    }
  }

  Future<void> rescheduleAppointment({
    required AppointmentItem original,
    required DateTime newStartsAt,
    required DateTime newEndsAt,
  }) async {
    final source = (original.source == 'professional' ||
            original.source == 'client_link' ||
            original.source == 'ai')
        ? original.source
        : 'professional';

    final inserted = await _client
        .from('appointments')
        .insert({
          'tenant_id': original.tenantId,
          'client_id': original.clientId,
          'service_id': original.serviceId,
          'specialty_id': original.specialtyId,
          'professional_id': original.professionalId,
          'starts_at': newStartsAt.toUtc().toIso8601String(),
          'ends_at': newEndsAt.toUtc().toIso8601String(),
          'status': 'scheduled',
          'source': source,
          'assigned_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select('id')
        .maybeSingle();

    if (inserted == null || inserted['id'] is! String) {
      throw const AppException(
        message: 'Não foi possível criar o novo agendamento na remarcação.',
        code: 'reschedule_insert_failed',
      );
    }

    final newId = inserted['id'] as String;
    await updateAppointmentStatus(
      appointmentId: original.id,
      status: 'rescheduled',
      cancellationReason: 'Remarcado manualmente para $newId',
    );
  }

  Future<void> sendPunctualitySnapshot({
    required String appointmentId,
    int? etaMinutes,
    double? clientLat,
    double? clientLng,
    String source = 'mobile_app',
  }) async {
    final response = await _client.functions.invoke(
      'punctuality-monitor',
      body: {
        'appointment_id': appointmentId,
        'source': source,
        'snapshots': [
          {
            'appointment_id': appointmentId,
            'eta_minutes': etaMinutes,
            'captured_at': DateTime.now().toUtc().toIso8601String(),
            'client_lat': clientLat,
            'client_lng': clientLng,
            'provider': 'mobile_manual',
          }
        ],
      },
    );

    ensureExpectedStatus(
      actualStatus: response.status,
      expectedStatus: 200,
      operation: 'punctuality-monitor',
      responseData: response.data,
    );
  }

  Future<List<PunctualityAlertItem>> getPunctualityAlerts({
    List<String>? appointmentIds,
    int limit = 15,
    bool includeRead = true,
  }) async {
    var query = _client
        .from('notification_log')
        .select('id, appointment_id, type, status, payload, created_at')
        .eq('channel', 'in_app')
        .inFilter('type', const [
      'punctuality_on_time',
      'punctuality_late_ok',
      'punctuality_late_critical',
    ]);

    if (appointmentIds != null && appointmentIds.isNotEmpty) {
      query = query.inFilter('appointment_id', appointmentIds);
    }
    if (!includeRead) {
      query = query.inFilter('status', const ['queued', 'sent']);
    }

    final response =
        await query.order('created_at', ascending: false).limit(limit);

    return List<Map<String, dynamic>>.from(response)
        .map(PunctualityAlertItem.fromJson)
        .toList();
  }

  Future<void> markPunctualityAlertsDelivered(List<String> alertIds) async {
    if (alertIds.isEmpty) return;
    await _client
        .from('notification_log')
        .update({'status': 'sent'})
        .inFilter('id', alertIds)
        .eq('status', 'queued');
  }

  Future<void> markPunctualityAlertRead(String alertId) async {
    await _client
        .from('notification_log')
        .update({'status': 'read'}).eq('id', alertId);
  }

  Future<void> markPunctualityAlertsRead(List<String> alertIds) async {
    if (alertIds.isEmpty) return;
    await _client
        .from('notification_log')
        .update({'status': 'read'}).inFilter('id', alertIds);
  }

  Future<Map<String, ClientLocationConsentItem>> getLocationConsents(
      List<String> appointmentIds) async {
    if (appointmentIds.isEmpty) return {};

    final response = await _client
        .from('client_location_consents')
        .select(
            'id, appointment_id, consent_status, consent_text_version, source_channel, granted_at, expires_at, created_at, updated_at')
        .inFilter('appointment_id', appointmentIds)
        .order('updated_at', ascending: false);

    final map = <String, ClientLocationConsentItem>{};
    for (final row in List<Map<String, dynamic>>.from(response)) {
      final item = ClientLocationConsentItem.fromJson(row);
      map.putIfAbsent(item.appointmentId, () => item);
    }
    return map;
  }

  Future<void> registerLocationConsent({
    required AppointmentItem appointment,
    required String consentStatus,
    required String consentTextVersion,
    DateTime? expiresAt,
    String sourceChannel = 'app_agenda_profissional',
  }) async {
    if (appointment.clientId == null || appointment.clientId!.isEmpty) {
      throw const AppException(
        message:
            'Agendamento sem cliente vinculado para registrar consentimento.',
        code: 'appointment_without_client',
      );
    }

    final status = consentStatus.trim().toLowerCase();
    if (!{'granted', 'denied', 'revoked', 'expired'}.contains(status)) {
      throw const AppException(
        message: 'Status de consentimento inválido.',
        code: 'invalid_consent_status',
      );
    }

    final nowIso = DateTime.now().toUtc().toIso8601String();
    final payload = <String, dynamic>{
      'tenant_id': appointment.tenantId,
      'client_id': appointment.clientId,
      'appointment_id': appointment.id,
      'consent_status': status,
      'consent_text_version':
          consentTextVersion.trim().isEmpty ? 'v1' : consentTextVersion.trim(),
      'source_channel': sourceChannel,
      'granted_at': status == 'granted' ? nowIso : null,
      'expires_at': status == 'granted'
          ? expiresAt?.toUtc().toIso8601String()
          : status == 'revoked'
              ? nowIso
              : null,
    };

    final existing = await _client
        .from('client_location_consents')
        .select('id')
        .eq('appointment_id', appointment.id)
        .order('updated_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (existing != null && existing['id'] is String) {
      await _client
          .from('client_location_consents')
          .update(payload)
          .eq('id', existing['id'] as String);
      return;
    }

    await _client.from('client_location_consents').insert(payload);
  }
}
