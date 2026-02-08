class AppointmentItem {
  const AppointmentItem({
    required this.id,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    required this.professionalName,
    required this.serviceName,
    required this.clientName,
  });

  final String id;
  final DateTime startsAt;
  final DateTime endsAt;
  final String status;
  final String professionalName;
  final String serviceName;
  final String clientName;

  factory AppointmentItem.fromJson(Map<String, dynamic> json) {
    final professionals = json['professionals'] as Map<String, dynamic>?;
    final services = json['services'] as Map<String, dynamic>?;
    final clients = json['clients'] as Map<String, dynamic>?;

    return AppointmentItem(
      id: json['id'] as String,
      startsAt: DateTime.parse(json['starts_at'] as String).toLocal(),
      endsAt: DateTime.parse(json['ends_at'] as String).toLocal(),
      status: json['status'] as String,
      professionalName: (professionals?['name'] ?? '-') as String,
      serviceName: (services?['name'] ?? '-') as String,
      clientName: (clients?['full_name'] ?? 'Sem cliente') as String,
    );
  }
}

class CreateAppointmentInput {
  const CreateAppointmentInput({
    required this.clientId,
    required this.serviceId,
    required this.startsAt,
    required this.endsAt,
    required this.professionalId,
    required this.anyAvailable,
  });

  final String? clientId;
  final String serviceId;
  final DateTime startsAt;
  final DateTime endsAt;
  final String? professionalId;
  final bool anyAvailable;

  Map<String, dynamic> toJson() {
    return {
      'client_id': clientId,
      'service_id': serviceId,
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt.toUtc().toIso8601String(),
      'professional_id': professionalId,
      'any_available': anyAvailable,
    };
  }
}
