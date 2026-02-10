import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/appointment.dart';
import 'response_utils.dart';

class AppointmentService {
  AppointmentService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

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
        .select('id, professional_id, starts_at, ends_at, status, professionals(name), services(name), clients(full_name)')
        .gte('starts_at', start.toUtc().toIso8601String())
        .lt('starts_at', end.toUtc().toIso8601String());
    if (professionalId != null && professionalId.isNotEmpty) {
      query = query.eq('professional_id', professionalId);
    }

    final response = await query.order('starts_at');

    return List<Map<String, dynamic>>.from(response).map(AppointmentItem.fromJson).toList();
  }

  Future<Map<String, String>> getProfessionalTimezones(List<String> professionalIds) async {
    if (professionalIds.isEmpty) return {};

    final response = await _client
        .from('professional_schedule_settings')
        .select('professional_id, timezone')
        .inFilter('professional_id', professionalIds);

    final map = <String, String>{};
    for (final row in List<Map<String, dynamic>>.from(response)) {
      final professionalId = row['professional_id'];
      final timezone = row['timezone'];
      if (professionalId is String && timezone is String && timezone.isNotEmpty) {
        map[professionalId] = timezone;
      }
    }

    return map;
  }

  Future<void> createAppointment(CreateAppointmentInput input) async {
    final response = await _client.functions.invoke('create-appointment', body: input.toJson());

    ensureExpectedStatus(
      actualStatus: response.status,
      expectedStatus: 201,
      operation: 'create-appointment',
      responseData: response.data,
    );
  }
}
