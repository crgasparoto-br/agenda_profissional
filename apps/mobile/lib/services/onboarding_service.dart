import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/bootstrap_tenant.dart';
import 'response_utils.dart';

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
}
