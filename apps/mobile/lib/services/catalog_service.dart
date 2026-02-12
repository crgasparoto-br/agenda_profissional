import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/option_item.dart';

class ServiceCatalogItem {
  const ServiceCatalogItem({
    required this.id,
    required this.name,
    required this.durationMin,
    required this.intervalMin,
  });

  final String id;
  final String name;
  final int durationMin;
  final int intervalMin;
}

class CatalogService {
  CatalogService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<OptionItem>> listServices() async {
    final response = await _client.from('services').select('id, name').eq('active', true).order('name');
    return List<Map<String, dynamic>>.from(response)
        .map((row) => OptionItem(id: row['id'] as String, label: row['name'] as String))
        .toList();
  }

  Future<List<ServiceCatalogItem>> listServiceCatalog() async {
    final response = await _client
        .from('services')
        .select('id, name, duration_min, interval_min')
        .eq('active', true)
        .order('name');

    return List<Map<String, dynamic>>.from(response)
        .map((row) => ServiceCatalogItem(
              id: row['id'] as String,
              name: row['name'] as String,
              durationMin: (row['duration_min'] as num?)?.toInt() ?? 30,
              intervalMin: (row['interval_min'] as num?)?.toInt() ?? 0,
            ))
        .toList();
  }

  Future<List<OptionItem>> listProfessionals() async {
    final response = await _client.from('professionals').select('id, name').eq('active', true).order('name');
    return List<Map<String, dynamic>>.from(response)
        .map((row) => OptionItem(id: row['id'] as String, label: row['name'] as String))
        .toList();
  }

  Future<List<OptionItem>> listClients() async {
    final response = await _client.from('clients').select('id, full_name').order('full_name');
    return List<Map<String, dynamic>>.from(response)
        .map((row) => OptionItem(id: row['id'] as String, label: row['full_name'] as String))
        .toList();
  }
}
