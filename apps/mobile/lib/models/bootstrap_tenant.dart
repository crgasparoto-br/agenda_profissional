enum TenantType { individual, group }

extension TenantTypeValue on TenantType {
  String get value {
    switch (this) {
      case TenantType.individual:
        return 'individual';
      case TenantType.group:
        return 'group';
    }
  }
}

class BootstrapTenantInput {
  const BootstrapTenantInput({
    required this.tenantType,
    required this.tenantName,
    required this.fullName,
    required this.phone,
  });

  final TenantType tenantType;
  final String tenantName;
  final String fullName;
  final String phone;

  Map<String, dynamic> toJson() {
    return {
      'tenant_type': tenantType.value,
      'tenant_name': tenantName,
      'full_name': fullName,
      'phone': phone,
    };
  }
}

class BootstrapTenantResult {
  const BootstrapTenantResult({
    required this.tenantId,
    required this.professionalId,
    required this.alreadyInitialized,
  });

  final String tenantId;
  final String? professionalId;
  final bool alreadyInitialized;

  factory BootstrapTenantResult.fromJson(Map<String, dynamic> json) {
    return BootstrapTenantResult(
      tenantId: (json['tenant_id'] ?? '') as String,
      professionalId: json['professional_id'] as String?,
      alreadyInitialized: (json['already_initialized'] ?? false) as bool,
    );
  }
}
