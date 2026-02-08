import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/appointment.dart';
import 'response_utils.dart';

class AppointmentService {
  AppointmentService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<AppointmentItem>> getDailyAppointments(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));

    final response = await _client
        .from('appointments')
        .select('id, starts_at, ends_at, status, professionals(name), services(name), clients(full_name)')
        .gte('starts_at', start.toUtc().toIso8601String())
        .lt('starts_at', end.toUtc().toIso8601String())
        .order('starts_at');

    return List<Map<String, dynamic>>.from(response).map(AppointmentItem.fromJson).toList();
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
