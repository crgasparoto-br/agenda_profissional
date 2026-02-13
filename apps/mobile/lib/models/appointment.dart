class AppointmentItem {
  const AppointmentItem({
    required this.id,
    required this.tenantId,
    required this.clientId,
    required this.serviceId,
    required this.specialtyId,
    required this.professionalId,
    required this.source,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    required this.cancellationReason,
    required this.professionalName,
    required this.serviceName,
    required this.serviceDurationMin,
    required this.serviceIntervalMin,
    required this.clientName,
  });

  final String id;
  final String tenantId;
  final String? clientId;
  final String serviceId;
  final String? specialtyId;
  final String professionalId;
  final String source;
  final DateTime startsAt;
  final DateTime endsAt;
  final String status;
  final String? cancellationReason;
  final String professionalName;
  final String serviceName;
  final int serviceDurationMin;
  final int serviceIntervalMin;
  final String clientName;

  factory AppointmentItem.fromJson(Map<String, dynamic> json) {
    final professionals = json['professionals'] as Map<String, dynamic>?;
    final services = json['services'] as Map<String, dynamic>?;
    final clients = json['clients'] as Map<String, dynamic>?;

    return AppointmentItem(
      id: json['id'] as String,
      tenantId: json['tenant_id'] as String,
      clientId: json['client_id'] as String?,
      serviceId: json['service_id'] as String,
      specialtyId: json['specialty_id'] as String?,
      professionalId: json['professional_id'] as String,
      source: (json['source'] as String?) ?? 'professional',
      startsAt: DateTime.parse(json['starts_at'] as String).toUtc(),
      endsAt: DateTime.parse(json['ends_at'] as String).toUtc(),
      status: json['status'] as String,
      cancellationReason: json['cancellation_reason'] as String?,
      professionalName: (professionals?['name'] ?? '-') as String,
      serviceName: (services?['name'] ?? '-') as String,
      serviceDurationMin: (services?['duration_min'] as num?)?.toInt() ?? 0,
      serviceIntervalMin: (services?['interval_min'] as num?)?.toInt() ?? 0,
      clientName: (clients?['full_name'] ?? 'Sem cliente') as String,
    );
  }
}

class CreateAppointmentInput {
  const CreateAppointmentInput({
    required this.clientId,
    required this.clientName,
    required this.clientPhone,
    required this.serviceId,
    required this.startsAt,
    required this.endsAt,
    required this.professionalId,
    required this.anyAvailable,
  });

  final String? clientId;
  final String? clientName;
  final String? clientPhone;
  final String serviceId;
  final DateTime startsAt;
  final DateTime endsAt;
  final String? professionalId;
  final bool anyAvailable;

  Map<String, dynamic> toJson() {
    return {
      'client_id': clientId,
      'client_name': clientName,
      'client_phone': clientPhone,
      'service_id': serviceId,
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt.toUtc().toIso8601String(),
      'professional_id': professionalId,
      'any_available': anyAvailable,
      'source': 'professional',
    };
  }
}
