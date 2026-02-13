import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data';

import '../models/bootstrap_tenant.dart';
import 'response_utils.dart';

class OnboardingSetup {
  const OnboardingSetup({
    required this.userId,
    required this.tenantId,
    required this.tenantType,
    required this.tenantName,
    required this.fullName,
    required this.phone,
    required this.logoUrl,
  });

  final String userId;
  final String tenantId;
  final TenantType tenantType;
  final String tenantName;
  final String fullName;
  final String? phone;
  final String? logoUrl;
}

class OnboardingService {
  OnboardingService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<bool> profileExists(String userId) async {
    final profile = await _client.from('profiles').select('id').eq('id', userId).maybeSingle();
    return profile != null;
  }

  Future<BootstrapTenantResult> bootstrapTenant(BootstrapTenantInput input) async {
    final response = await _client.functions.invoke('bootstrap-tenant', body: input.toJson());

    ensureExpectedStatus(
      actualStatus: response.status,
      expectedStatus: 200,
      operation: 'bootstrap-tenant',
      responseData: response.data,
    );

    final data = requireJsonMap(data: response.data, operation: 'bootstrap-tenant');
    return BootstrapTenantResult.fromJson(data);
  }

  Future<OnboardingSetup?> loadSetupForUser(String userId) async {
    final profile = await _client
        .from('profiles')
        .select('id, tenant_id, full_name, phone')
        .eq('id', userId)
        .maybeSingle();
    if (profile == null) return null;

    final tenantId = (profile['tenant_id'] ?? '') as String;
    if (tenantId.isEmpty) return null;

    final tenant = await _client
        .from('tenants')
        .select('id, type, name, logo_url')
        .eq('id', tenantId)
        .maybeSingle();
    if (tenant == null) return null;

    final typeRaw = tenant['type'] as String? ?? 'individual';
    final tenantType = typeRaw == 'group' ? TenantType.group : TenantType.individual;

    return OnboardingSetup(
      userId: profile['id'] as String,
      tenantId: tenant['id'] as String,
      tenantType: tenantType,
      tenantName: (tenant['name'] as String?) ?? '',
      fullName: (profile['full_name'] as String?) ?? '',
      phone: profile['phone'] as String?,
      logoUrl: tenant['logo_url'] as String?,
    );
  }

  Future<void> updateSetup({
    required String userId,
    required String tenantId,
    required TenantType tenantType,
    required String tenantName,
    required String fullName,
    String? phone,
    String? logoUrl,
  }) async {
    await _client.from('tenants').update({
      'type': tenantType.value,
      'name': tenantName,
      'logo_url': logoUrl,
    }).eq('id', tenantId);

    await _client.from('profiles').update({
      'full_name': fullName,
      'phone': (phone ?? '').trim().isEmpty ? null : phone!.trim(),
    }).eq('id', userId);
  }

  Future<String> uploadTenantLogo({
    required String tenantId,
    required Uint8List bytes,
    required String extension,
    required String contentType,
  }) async {
    final safeExt = extension.replaceAll('.', '').toLowerCase();
    final objectPath = '$tenantId/logo.$safeExt';

    await _client.storage.from('tenant-assets').uploadBinary(
          objectPath,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: contentType,
            cacheControl: '3600',
          ),
        );

    final publicUrl = _client.storage.from('tenant-assets').getPublicUrl(objectPath);
    return '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> updateTenantLogoUrl({
    required String tenantId,
    required String logoUrl,
  }) async {
    await _client.from('tenants').update({'logo_url': logoUrl}).eq('id', tenantId);
  }
}
