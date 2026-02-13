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
            'id, tenant_id, client_id, service_id, specialty_id, professional_id, source, starts_at, ends_at, status, cancellation_reason, professionals(name), services(name, duration_min, interval_min), clients(full_name)')
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
}
