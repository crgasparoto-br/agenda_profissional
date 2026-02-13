import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_exception.dart';

class TenantService {
  TenantService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<String> requireTenantId() async {
    final data = await _client.rpc('auth_tenant_id');
    if (data is String && data.isNotEmpty) return data;
    throw const AppException(
      message: 'Não foi possível resolver a organização atual.',
      code: 'tenant_not_found',
    );
  }
}

