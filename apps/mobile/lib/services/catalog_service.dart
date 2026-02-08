import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/option_item.dart';

class CatalogService {
  CatalogService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<OptionItem>> listServices() async {
    final response = await _client.from('services').select('id, name').eq('active', true).order('name');
    return List<Map<String, dynamic>>.from(response)
        .map((row) => OptionItem(id: row['id'] as String, label: row['name'] as String))
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
