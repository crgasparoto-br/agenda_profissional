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
    required this.punctualityStatus,
    required this.punctualityEtaMin,
    required this.punctualityPredictedDelayMin,
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
  final String punctualityStatus;
  final int? punctualityEtaMin;
  final int? punctualityPredictedDelayMin;

  static Map<String, dynamic>? _readRelation(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is List && value.isNotEmpty && value.first is Map<String, dynamic>) {
      return value.first as Map<String, dynamic>;
    }
    return null;
  }

  static String _readString(
    Map<String, dynamic> json,
    String key, {
    String fallback = '',
  }) {
    final value = json[key];
    if (value is String && value.isNotEmpty) return value;
    return fallback;
  }

  factory AppointmentItem.fromJson(Map<String, dynamic> json) {
    final professionals = _readRelation(json['professionals']);
    final services = _readRelation(json['services']);
    final clients = _readRelation(json['clients']);

    return AppointmentItem(
      id: _readString(json, 'id'),
      tenantId: _readString(json, 'tenant_id'),
      clientId: json['client_id'] as String?,
      serviceId: _readString(json, 'service_id'),
      specialtyId: json['specialty_id'] as String?,
      professionalId: _readString(json, 'professional_id'),
      source: _readString(json, 'source', fallback: 'professional'),
      startsAt: DateTime.parse(_readString(json, 'starts_at')).toUtc(),
      endsAt: DateTime.parse(_readString(json, 'ends_at')).toUtc(),
      status: _readString(json, 'status'),
      cancellationReason: json['cancellation_reason'] as String?,
      professionalName: (professionals?['name'] as String?) ?? '-',
      serviceName: (services?['name'] as String?) ?? '-',
      serviceDurationMin: (services?['duration_min'] as num?)?.toInt() ?? 0,
      serviceIntervalMin: (services?['interval_min'] as num?)?.toInt() ?? 0,
      clientName: (clients?['full_name'] as String?) ?? 'Sem cliente',
      punctualityStatus:
          (json['punctuality_status'] as String?)?.toLowerCase() ?? 'no_data',
      punctualityEtaMin: (json['punctuality_eta_min'] as num?)?.toInt(),
      punctualityPredictedDelayMin:
          (json['punctuality_predicted_delay_min'] as num?)?.toInt(),
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

class PunctualityAlertItem {
  const PunctualityAlertItem({
    required this.id,
    required this.appointmentId,
    required this.type,
    required this.status,
    required this.createdAt,
    required this.payload,
  });

  final String id;
  final String appointmentId;
  final String type;
  final String status;
  final DateTime createdAt;
  final Map<String, dynamic> payload;
  bool get isRead => status.toLowerCase() == 'read';
  bool get isQueued => status.toLowerCase() == 'queued';
  bool get isDelivered => status.toLowerCase() == 'sent';

  factory PunctualityAlertItem.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    return PunctualityAlertItem(
      id: json['id'] as String,
      appointmentId: json['appointment_id'] as String,
      type: json['type'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      payload:
          rawPayload is Map<String, dynamic> ? rawPayload : <String, dynamic>{},
    );
  }
}

class ClientLocationConsentItem {
  const ClientLocationConsentItem({
    required this.id,
    required this.appointmentId,
    required this.consentStatus,
    required this.consentTextVersion,
    required this.sourceChannel,
    required this.createdAt,
    required this.updatedAt,
    required this.grantedAt,
    required this.expiresAt,
  });

  final String id;
  final String appointmentId;
  final String consentStatus;
  final String consentTextVersion;
  final String sourceChannel;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? grantedAt;
  final DateTime? expiresAt;

  bool get isGrantedActive {
    if (consentStatus.toLowerCase() != 'granted') return false;
    if (expiresAt == null) return true;
    return expiresAt!.isAfter(DateTime.now().toUtc());
  }

  factory ClientLocationConsentItem.fromJson(Map<String, dynamic> json) {
    DateTime? parseOptionalDate(dynamic value) {
      if (value is! String || value.isEmpty) return null;
      return DateTime.parse(value).toUtc();
    }

    return ClientLocationConsentItem(
      id: json['id'] as String,
      appointmentId: json['appointment_id'] as String,
      consentStatus: (json['consent_status'] as String?)?.toLowerCase() ?? '',
      consentTextVersion: (json['consent_text_version'] as String?) ?? 'v1',
      sourceChannel: (json['source_channel'] as String?) ?? 'app_agenda',
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
      grantedAt: parseOptionalDate(json['granted_at']),
      expiresAt: parseOptionalDate(json['expires_at']),
    );
  }
}
