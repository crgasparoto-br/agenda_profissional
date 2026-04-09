import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/tenant_service.dart';
import '../theme/app_theme.dart';

class _ServiceLocationDraft {
  _ServiceLocationDraft({
    this.id,
    required this.name,
    required this.addressLine,
    required this.city,
    required this.state,
    required this.postalCode,
    required this.country,
    required this.latitude,
    required this.longitude,
    required this.isActive,
  });

  String? id;
  String name;
  String addressLine;
  String city;
  String state;
  String postalCode;
  String country;
  String latitude;
  String longitude;
  bool isActive;

  factory _ServiceLocationDraft.empty() {
    return _ServiceLocationDraft(
      id: null,
      name: 'Endereço principal',
      addressLine: '',
      city: '',
      state: '',
      postalCode: '',
      country: 'BR',
      latitude: '',
      longitude: '',
      isActive: true,
    );
  }

  _ServiceLocationDraft copyWith({
    String? id,
    String? name,
    String? addressLine,
    String? city,
    String? state,
    String? postalCode,
    String? country,
    String? latitude,
    String? longitude,
    bool? isActive,
  }) {
    return _ServiceLocationDraft(
      id: id ?? this.id,
      name: name ?? this.name,
      addressLine: addressLine ?? this.addressLine,
      city: city ?? this.city,
      state: state ?? this.state,
      postalCode: postalCode ?? this.postalCode,
      country: country ?? this.country,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isActive: isActive ?? this.isActive,
    );
  }
}

class ProfessionalsScreen extends StatefulWidget {
  const ProfessionalsScreen({super.key});

  @override
  State<ProfessionalsScreen> createState() => _ProfessionalsScreenState();
}

class _ProfessionalsScreenState extends State<ProfessionalsScreen> {
  final _tenantService = TenantService();
  final _nameController = TextEditingController();

  bool _active = true;
  bool _loading = false;
  bool _saving = false;
  bool _savingLocation = false;
  String? _tenantId;
  String? _editingId;
  String? _expandedProfessionalId;
  String? _error;
  String? _status;

  List<Map<String, dynamic>> _professionals = const [];
  List<Map<String, dynamic>> _services = const [];
  List<Map<String, dynamic>> _links = const [];
  Map<String, _ServiceLocationDraft> _locationByProfessional = {};

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      _tenantId = await _tenantService.requireTenantId();
      await _loadAll();
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAll() async {
    if (_tenantId == null) return;
    final supabase = Supabase.instance.client;

    final results = await Future.wait([
      supabase
          .from('professionals')
          .select('id, name, active')
          .eq('tenant_id', _tenantId!)
          .order('name'),
      supabase
          .from('services')
          .select('id, name, active')
          .eq('tenant_id', _tenantId!)
          .order('name'),
      supabase
          .from('professional_services')
          .select('professional_id, service_id')
          .eq('tenant_id', _tenantId!),
      supabase
          .from('service_locations')
          .select(
              'id, professional_id, name, address_line, city, state, postal_code, country, latitude, longitude, is_active, updated_at')
          .eq('tenant_id', _tenantId!)
          .order('updated_at', ascending: false),
    ]);

    final professionals = List<Map<String, dynamic>>.from(results[0] as List);
    final services = List<Map<String, dynamic>>.from(results[1] as List);
    final links = List<Map<String, dynamic>>.from(results[2] as List);
    final locations = List<Map<String, dynamic>>.from(results[3] as List);

    final nextLocations = <String, _ServiceLocationDraft>{};
    for (final professional in professionals) {
      final professionalId = professional['id'] as String;
      final row = locations.cast<Map<String, dynamic>>().firstWhere(
            (item) => item['professional_id'] == professionalId,
            orElse: () => <String, dynamic>{},
          );

      if (row.isEmpty) {
        nextLocations[professionalId] = _ServiceLocationDraft.empty();
        continue;
      }

      nextLocations[professionalId] = _ServiceLocationDraft(
        id: row['id'] as String?,
        name: (row['name'] as String?) ?? 'Endereço principal',
        addressLine: (row['address_line'] as String?) ?? '',
        city: (row['city'] as String?) ?? '',
        state: (row['state'] as String?) ?? '',
        postalCode: (row['postal_code'] as String?) ?? '',
        country: ((row['country'] as String?) ?? 'BR').toUpperCase(),
        latitude: row['latitude']?.toString() ?? '',
        longitude: row['longitude']?.toString() ?? '',
        isActive: row['is_active'] == true,
      );
    }

    if (!mounted) return;
    setState(() {
      _professionals = professionals;
      _services = services;
      _links = links;
      _locationByProfessional = nextLocations;
      _expandedProfessionalId ??=
          professionals.isNotEmpty ? professionals.first['id'] as String : null;
    });
  }

  void _startCreate() {
    setState(() {
      _editingId = null;
      _active = true;
      _error = null;
      _status = null;
    });
    _nameController.clear();
  }

  void _startEdit(Map<String, dynamic> row) {
    setState(() {
      _editingId = row['id'] as String;
      _active = row['active'] == true;
      _error = null;
      _status = null;
    });
    _nameController.text = (row['name'] as String?) ?? '';
  }

  Future<void> _save() async {
    if (_tenantId == null) return;
    if (_nameController.text.trim().isEmpty) {
      setState(() => _error = 'Informe o nome do profissional.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _status = null;
    });
    try {
      final payload = {
        'tenant_id': _tenantId,
        'name': _nameController.text.trim(),
        'active': _active,
      };
      if (_editingId == null) {
        await Supabase.instance.client.from('professionals').insert(payload);
        setState(() => _status = 'Profissional cadastrado com sucesso.');
      } else {
        await Supabase.instance.client
            .from('professionals')
            .update(payload)
            .eq('id', _editingId!);
        setState(() => _status = 'Profissional atualizado com sucesso.');
      }
      _startCreate();
      await _loadAll();
    } catch (error) {
      setState(() => _error = 'Erro ao salvar profissional: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleProfessionalActive(Map<String, dynamic> row) async {
    try {
      await Supabase.instance.client.from('professionals').update(
          {'active': row['active'] != true}).eq('id', row['id'] as String);
      setState(() => _status = 'Status do profissional atualizado.');
      await _loadAll();
    } catch (error) {
      setState(() => _error = 'Erro ao atualizar profissional: $error');
    }
  }

  bool _hasServiceLink(String professionalId, String serviceId) {
    return _links.any((item) =>
        item['professional_id'] == professionalId &&
        item['service_id'] == serviceId);
  }

  Future<void> _toggleServiceLink(
      String professionalId, String serviceId, bool enabled) async {
    if (_tenantId == null) return;
    setState(() {
      _error = null;
      _status = null;
    });

    try {
      final table = Supabase.instance.client.from('professional_services');
      if (enabled) {
        await table.upsert(
          {
            'tenant_id': _tenantId,
            'professional_id': professionalId,
            'service_id': serviceId,
          },
          onConflict: 'tenant_id,professional_id,service_id',
        );
      } else {
        await table
            .delete()
            .eq('professional_id', professionalId)
            .eq('service_id', serviceId);
      }
      await _loadAll();
    } catch (error) {
      setState(() => _error = 'Erro ao atualizar vínculo de serviço: $error');
    }
  }

  void _updateLocationDraft(
      String professionalId, _ServiceLocationDraft draft) {
    setState(() {
      _locationByProfessional = {
        ..._locationByProfessional,
        professionalId: draft,
      };
    });
  }

  String? _validateLocationDraft(_ServiceLocationDraft draft) {
    if (draft.name.trim().isEmpty) return 'Informe o nome do endereço.';
    if (draft.addressLine.trim().isEmpty) return 'Informe o endereço.';
    if (draft.city.trim().isEmpty) return 'Informe a cidade.';
    if (draft.state.trim().isEmpty) return 'Informe o estado.';
    if (draft.country.trim().isEmpty) return 'Informe o país.';

    if (draft.latitude.trim().isNotEmpty || draft.longitude.trim().isNotEmpty) {
      final latitude = double.tryParse(draft.latitude.replaceAll(',', '.'));
      final longitude = double.tryParse(draft.longitude.replaceAll(',', '.'));
      if (latitude == null || longitude == null) {
        return 'Latitude e longitude precisam ser numéricas.';
      }
      if (latitude < -90 ||
          latitude > 90 ||
          longitude < -180 ||
          longitude > 180) {
        return 'Latitude ou longitude fora da faixa válida.';
      }
    }
    return null;
  }

  Future<void> _saveLocation(String professionalId) async {
    if (_tenantId == null) return;
    final draft = _locationByProfessional[professionalId] ??
        _ServiceLocationDraft.empty();
    final validationError = _validateLocationDraft(draft);
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    setState(() {
      _savingLocation = true;
      _error = null;
      _status = null;
    });

    try {
      final latitude = draft.latitude.trim().isEmpty
          ? null
          : double.parse(draft.latitude.replaceAll(',', '.'));
      final longitude = draft.longitude.trim().isEmpty
          ? null
          : double.parse(draft.longitude.replaceAll(',', '.'));

      final payload = {
        'tenant_id': _tenantId,
        'professional_id': professionalId,
        'name': draft.name.trim(),
        'address_line': draft.addressLine.trim(),
        'city': draft.city.trim(),
        'state': draft.state.trim(),
        'postal_code':
            draft.postalCode.trim().isEmpty ? null : draft.postalCode.trim(),
        'country': draft.country.trim().toUpperCase(),
        'latitude': latitude,
        'longitude': longitude,
        'is_active': draft.isActive,
      };

      final table = Supabase.instance.client.from('service_locations');
      if (draft.id == null) {
        await table.insert(payload);
      } else {
        await table
            .update(payload)
            .eq('id', draft.id!)
            .eq('professional_id', professionalId);
      }

      setState(() => _status = 'Endereço de atendimento salvo com sucesso.');
      await _loadAll();
    } catch (error) {
      setState(() => _error = 'Erro ao salvar endereço: $error');
    } finally {
      if (mounted) setState(() => _savingLocation = false);
    }
  }

  String _serviceLocationSummary(String professionalId) {
    final draft = _locationByProfessional[professionalId];
    if (draft == null || draft.addressLine.trim().isEmpty) {
      return 'Não cadastrado';
    }
    return '${draft.city} / ${draft.state}';
  }

  Widget _buildControlledTextField({
    required String value,
    required ValueChanged<String> onChanged,
    required String label,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: TextEditingController(text: value)
        ..selection = TextSelection.collapsed(offset: value.length),
      keyboardType: keyboardType,
      onChanged: onChanged,
      decoration: InputDecoration(labelText: label),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profissionais')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(labelText: 'Nome'),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _active,
                          onChanged: (value) => setState(() => _active = value),
                          title: const Text('Ativo'),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _saving ? null : _save,
                                child: Text(
                                  _saving
                                      ? 'Salvando...'
                                      : _editingId == null
                                          ? 'Adicionar'
                                          : 'Salvar',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: _saving ? null : _startCreate,
                              child: const Text('Limpar'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: const TextStyle(color: AppColors.danger)),
                ],
                if (_status != null) ...[
                  const SizedBox(height: 8),
                  Text(_status!,
                      style: const TextStyle(color: AppColors.secondary)),
                ],
                const SizedBox(height: 8),
                ..._professionals.map((row) {
                  final professionalId = row['id'] as String;
                  final active = row['active'] == true;
                  final expanded = _expandedProfessionalId == professionalId;
                  final locationDraft =
                      _locationByProfessional[professionalId] ??
                          _ServiceLocationDraft.empty();

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ExpansionTile(
                        key: ValueKey(professionalId),
                        initiallyExpanded: expanded,
                        onExpansionChanged: (value) {
                          setState(() {
                            _expandedProfessionalId =
                                value ? professionalId : null;
                          });
                        },
                        title: Text((row['name'] as String?) ?? '-'),
                        subtitle: Text(
                          '${active ? 'Ativo' : 'Inativo'} • ${_serviceLocationSummary(professionalId)}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: () => _startEdit(row),
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: 'Editar profissional',
                            ),
                            IconButton(
                              onPressed: () => _toggleProfessionalActive(row),
                              icon: Icon(
                                  active ? Icons.toggle_on : Icons.toggle_off),
                              tooltip: active ? 'Desativar' : 'Ativar',
                            ),
                          ],
                        ),
                        childrenPadding:
                            const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        children: [
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Serviços habilitados',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _services.map((service) {
                              final serviceId = service['id'] as String;
                              final checked =
                                  _hasServiceLink(professionalId, serviceId);
                              final serviceName =
                                  (service['name'] as String?) ?? '-';
                              final inactive = service['active'] != true;
                              return FilterChip(
                                label: Text(
                                  inactive
                                      ? '$serviceName (inativo)'
                                      : serviceName,
                                ),
                                selected: checked,
                                onSelected: (value) => _toggleServiceLink(
                                    professionalId, serviceId, value),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Endereço de atendimento',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildControlledTextField(
                            value: locationDraft.name,
                            onChanged: (value) => _updateLocationDraft(
                              professionalId,
                              locationDraft.copyWith(name: value),
                            ),
                            label: 'Nome do local',
                          ),
                          const SizedBox(height: 8),
                          _buildControlledTextField(
                            value: locationDraft.addressLine,
                            onChanged: (value) => _updateLocationDraft(
                              professionalId,
                              locationDraft.copyWith(addressLine: value),
                            ),
                            label: 'Endereço',
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _buildControlledTextField(
                                  value: locationDraft.city,
                                  onChanged: (value) => _updateLocationDraft(
                                    professionalId,
                                    locationDraft.copyWith(city: value),
                                  ),
                                  label: 'Cidade',
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildControlledTextField(
                                  value: locationDraft.state,
                                  onChanged: (value) => _updateLocationDraft(
                                    professionalId,
                                    locationDraft.copyWith(state: value),
                                  ),
                                  label: 'Estado',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _buildControlledTextField(
                                  value: locationDraft.postalCode,
                                  onChanged: (value) => _updateLocationDraft(
                                    professionalId,
                                    locationDraft.copyWith(postalCode: value),
                                  ),
                                  label: 'CEP',
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildControlledTextField(
                                  value: locationDraft.country,
                                  onChanged: (value) => _updateLocationDraft(
                                    professionalId,
                                    locationDraft.copyWith(country: value),
                                  ),
                                  label: 'País',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _buildControlledTextField(
                                  value: locationDraft.latitude,
                                  onChanged: (value) => _updateLocationDraft(
                                    professionalId,
                                    locationDraft.copyWith(latitude: value),
                                  ),
                                  label: 'Latitude (opcional)',
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildControlledTextField(
                                  value: locationDraft.longitude,
                                  onChanged: (value) => _updateLocationDraft(
                                    professionalId,
                                    locationDraft.copyWith(longitude: value),
                                  ),
                                  label: 'Longitude (opcional)',
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: locationDraft.isActive,
                            onChanged: (value) => _updateLocationDraft(
                              professionalId,
                              locationDraft.copyWith(isActive: value),
                            ),
                            title: const Text('Endereço ativo'),
                            subtitle: const Text(
                              'Se não houver endereço ativo do profissional, será usado o endereço padrão da organização.',
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton.icon(
                              onPressed: _savingLocation
                                  ? null
                                  : () => _saveLocation(professionalId),
                              icon: const Icon(Icons.save_outlined),
                              label: Text(
                                _savingLocation
                                    ? 'Salvando...'
                                    : 'Salvar endereço',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
