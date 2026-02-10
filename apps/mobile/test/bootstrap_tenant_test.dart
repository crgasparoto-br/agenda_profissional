import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/bootstrap_tenant.dart';

void main() {
  test('BootstrapTenantInput serializes as expected', () {
    const input = BootstrapTenantInput(
      tenantType: TenantType.group,
      tenantName: 'Empresa Central',
      fullName: 'Ana Lima',
      phone: '11999990000',
    );

    final json = input.toJson();

    expect(json['tenant_type'], 'group');
    expect(json['tenant_name'], 'Empresa Central');
    expect(json['full_name'], 'Ana Lima');
    expect(json['phone'], '11999990000');
  });

  test('BootstrapTenantResult parses response map', () {
    final result = BootstrapTenantResult.fromJson({
      'tenant_id': 'tenant-1',
      'professional_id': 'prof-1',
      'already_initialized': true,
    });

    expect(result.tenantId, 'tenant-1');
    expect(result.professionalId, 'prof-1');
    expect(result.alreadyInitialized, true);
  });
}
