import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/tenant_service.dart';
import '../theme/app_theme.dart';

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  final _tenantService = TenantService();

  final _specialtyController = TextEditingController();
  final _serviceController = TextEditingController();
  final _durationController = TextEditingController(text: '30');
  final _intervalController = TextEditingController(text: '0');
  final _priceController = TextEditingController();

  final _editSpecialtyController = TextEditingController();
  final _editServiceController = TextEditingController();
  final _editDurationController = TextEditingController(text: '30');
  final _editIntervalController = TextEditingController(text: '0');
  final _editPriceController = TextEditingController();

  String? _tenantId;
  String? _selectedSpecialtyId;
  String? _editingSpecialtyId;
  String? _editingServiceId;
  String? _editingServiceSpecialtyId;
  bool _loading = false;
  bool _saving = false;
  String? _error;
  String? _status;
  List<Map<String, dynamic>> _specialties = const [];
  List<Map<String, dynamic>> _services = const [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _specialtyController.dispose();
    _serviceController.dispose();
    _durationController.dispose();
    _intervalController.dispose();
    _priceController.dispose();
    _editSpecialtyController.dispose();
    _editServiceController.dispose();
    _editDurationController.dispose();
    _editIntervalController.dispose();
    _editPriceController.dispose();
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
    final specialties = await supabase
        .from('specialties')
        .select('id, name, active')
        .eq('tenant_id', _tenantId!)
        .order('name');
    final services = await supabase
        .from('services')
        .select(
            'id, name, duration_min, interval_min, price_cents, active, specialty_id, specialties(name)')
        .eq('tenant_id', _tenantId!)
        .order('name');
    if (!mounted) return;
    setState(() {
      _specialties = List<Map<String, dynamic>>.from(specialties);
      _services = List<Map<String, dynamic>>.from(services);
    });
  }

  int? _parsePriceToCents(String raw) {
    if (raw.trim().isEmpty) return null;
    final normalized = raw.replaceAll(',', '.');
    final parsed = double.tryParse(normalized);
    if (parsed == null || parsed < 0) return null;
    return (parsed * 100).round();
  }

  String _formatPriceFromCents(dynamic value) {
    final cents = value is num ? value.toInt() : int.tryParse('$value');
    if (cents == null) return '';
    return (cents / 100).toStringAsFixed(2);
  }

  String _formatPriceLabel(dynamic value) {
    final cents = value is num ? value.toInt() : int.tryParse('$value');
    if (cents == null) return '-';
    final reais = (cents / 100).toStringAsFixed(2).replaceAll('.', ',');
    return 'R\$ $reais';
  }

  Future<void> _addSpecialty() async {
    if (_tenantId == null) return;
    if (_specialtyController.text.trim().isEmpty) {
      setState(() => _error = 'Informe o nome da especialidade.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _status = null;
    });
    try {
      await Supabase.instance.client.from('specialties').insert({
        'tenant_id': _tenantId,
        'name': _specialtyController.text.trim(),
        'active': true,
      });
      _specialtyController.clear();
      setState(() => _status = 'Especialidade cadastrada com sucesso.');
      await _loadAll();
    } catch (error) {
      setState(() => _error = 'Erro ao cadastrar especialidade: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addService() async {
    if (_tenantId == null) return;
    if (_serviceController.text.trim().isEmpty) {
      setState(() => _error = 'Informe o nome do serviço.');
      return;
    }
    final duration = int.tryParse(_durationController.text.trim()) ?? 0;
    final interval = int.tryParse(_intervalController.text.trim()) ?? 0;
    final price = _parsePriceToCents(_priceController.text.trim());
    if (duration <= 0) {
      setState(() => _error = 'Duração deve ser maior que zero.');
      return;
    }
    if (interval < 0 || interval > 240) {
      setState(() => _error = 'Intervalo deve ficar entre 0 e 240 minutos.');
      return;
    }
    if (_priceController.text.trim().isNotEmpty && price == null) {
      setState(() => _error = 'Preço inválido.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _status = null;
    });
    try {
      await Supabase.instance.client.from('services').insert({
        'tenant_id': _tenantId,
        'name': _serviceController.text.trim(),
        'specialty_id': _selectedSpecialtyId,
        'duration_min': duration,
        'interval_min': interval,
        'price_cents': price,
        'active': true,
      });
      _serviceController.clear();
      _durationController.text = '30';
      _intervalController.text = '0';
      _priceController.clear();
      setState(() => _status = 'Serviço cadastrado com sucesso.');
      await _loadAll();
    } catch (error) {
      setState(() => _error = 'Erro ao cadastrar serviço: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _startEditingSpecialty(Map<String, dynamic> row) {
    setState(() {
      _editingSpecialtyId = row['id'] as String;
      _error = null;
      _status = null;
    });
    _editSpecialtyController.text = (row['name'] as String?) ?? '';
  }

  void _cancelEditingSpecialty() {
    setState(() => _editingSpecialtyId = null);
    _editSpecialtyController.clear();
  }

  Future<void> _saveEditingSpecialty(Map<String, dynamic> row) async {
    final name = _editSpecialtyController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Informe o nome da especialidade.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _status = null;
    });
    try {
      await Supabase.instance.client
          .from('specialties')
          .update({'name': name}).eq('id', row['id'] as String);
      _cancelEditingSpecialty();
      setState(() => _status = 'Especialidade atualizada com sucesso.');
      await _loadAll();
    } catch (error) {
      setState(() => _error = 'Erro ao atualizar especialidade: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleSpecialtyActive(Map<String, dynamic> row) async {
    try {
      await Supabase.instance.client.from('specialties').update(
          {'active': row['active'] != true}).eq('id', row['id'] as String);
      setState(() => _status = 'Status da especialidade atualizado.');
      await _loadAll();
    } catch (error) {
      setState(() => _error = 'Erro ao atualizar especialidade: $error');
    }
  }

  void _startEditingService(Map<String, dynamic> row) {
    setState(() {
      _editingServiceId = row['id'] as String;
      _editingServiceSpecialtyId = row['specialty_id'] as String?;
      _error = null;
      _status = null;
    });
    _editServiceController.text = (row['name'] as String?) ?? '';
    _editDurationController.text = '${row['duration_min'] ?? 30}';
    _editIntervalController.text = '${row['interval_min'] ?? 0}';
    _editPriceController.text = _formatPriceFromCents(row['price_cents']);
  }

  void _cancelEditingService() {
    setState(() {
      _editingServiceId = null;
      _editingServiceSpecialtyId = null;
    });
    _editServiceController.clear();
    _editDurationController.text = '30';
    _editIntervalController.text = '0';
    _editPriceController.clear();
  }

  Future<void> _saveEditingService(Map<String, dynamic> row) async {
    final name = _editServiceController.text.trim();
    final duration = int.tryParse(_editDurationController.text.trim()) ?? 0;
    final interval = int.tryParse(_editIntervalController.text.trim()) ?? -1;
    final price = _parsePriceToCents(_editPriceController.text.trim());
    if (name.isEmpty) {
      setState(() => _error = 'Informe o nome do serviço.');
      return;
    }
    if (duration <= 0) {
      setState(() => _error = 'Duração deve ser maior que zero.');
      return;
    }
    if (interval < 0 || interval > 240) {
      setState(() => _error = 'Intervalo deve ficar entre 0 e 240 minutos.');
      return;
    }
    if (_editPriceController.text.trim().isNotEmpty && price == null) {
      setState(() => _error = 'Preço inválido.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _status = null;
    });
    try {
      await Supabase.instance.client.from('services').update({
        'name': name,
        'duration_min': duration,
        'interval_min': interval,
        'price_cents': price,
        'specialty_id': _editingServiceSpecialtyId,
      }).eq('id', row['id'] as String);
      _cancelEditingService();
      setState(() => _status = 'Serviço atualizado com sucesso.');
      await _loadAll();
    } catch (error) {
      setState(() => _error = 'Erro ao atualizar serviço: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleServiceActive(Map<String, dynamic> row) async {
    try {
      await Supabase.instance.client.from('services').update(
          {'active': row['active'] != true}).eq('id', row['id'] as String);
      setState(() => _status = 'Status do serviço atualizado.');
      await _loadAll();
    } catch (error) {
      setState(() => _error = 'Erro ao atualizar serviço: $error');
    }
  }

  String _specialtyName(String? id) {
    if (id == null) return '-';
    for (final row in _specialties) {
      if (row['id'] == id) return (row['name'] as String?) ?? '-';
    }
    return '-';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Serviços e especialidades')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Nova especialidade'),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _specialtyController,
                          decoration: const InputDecoration(
                              labelText: 'Nome da especialidade'),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton(
                            onPressed: _saving ? null : _addSpecialty,
                            child: const Text('Adicionar especialidade'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Novo serviço'),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _serviceController,
                          decoration: const InputDecoration(
                              labelText: 'Nome do serviço'),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedSpecialtyId,
                          decoration:
                              const InputDecoration(labelText: 'Especialidade'),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('Sem especialidade'),
                            ),
                            ..._specialties.map(
                              (item) => DropdownMenuItem<String>(
                                value: item['id'] as String,
                                child: Text((item['name'] as String?) ?? '-'),
                              ),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _selectedSpecialtyId = value),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _durationController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    labelText: 'Duração (min)'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _intervalController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    labelText: 'Intervalo (min)'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _priceController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                              labelText: 'Preço (R\$) opcional'),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton(
                            onPressed: _saving ? null : _addService,
                            child: const Text('Adicionar serviço'),
                          ),
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
                Card(
                  child: ExpansionTile(
                    title: const Text('Especialidades'),
                    children: _specialties
                        .map(
                          (row) => ListTile(
                            title: _editingSpecialtyId == row['id']
                                ? TextField(
                                    controller: _editSpecialtyController,
                                    decoration: const InputDecoration(
                                      labelText: 'Nome da especialidade',
                                    ),
                                  )
                                : Text((row['name'] as String?) ?? '-'),
                            subtitle: Text(
                                row['active'] == true ? 'Ativa' : 'Inativa'),
                            trailing: Wrap(
                              spacing: 4,
                              children: [
                                if (_editingSpecialtyId == row['id'])
                                  IconButton(
                                    onPressed: _saving
                                        ? null
                                        : () => _saveEditingSpecialty(row),
                                    icon: const Icon(Icons.check_outlined),
                                    tooltip: 'Salvar',
                                  )
                                else
                                  IconButton(
                                    onPressed: () =>
                                        _startEditingSpecialty(row),
                                    icon: const Icon(Icons.edit_outlined),
                                    tooltip: 'Editar',
                                  ),
                                if (_editingSpecialtyId == row['id'])
                                  IconButton(
                                    onPressed: _saving
                                        ? null
                                        : _cancelEditingSpecialty,
                                    icon: const Icon(Icons.close_outlined),
                                    tooltip: 'Cancelar',
                                  ),
                                IconButton(
                                  onPressed: () => _toggleSpecialtyActive(row),
                                  icon: Icon(row['active'] == true
                                      ? Icons.toggle_on
                                      : Icons.toggle_off),
                                  tooltip: row['active'] == true
                                      ? 'Desativar'
                                      : 'Ativar',
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: ExpansionTile(
                    title: const Text('Serviços'),
                    children: _services
                        .map(
                          (row) => ListTile(
                            title: _editingServiceId == row['id']
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      TextField(
                                        controller: _editServiceController,
                                        decoration: const InputDecoration(
                                          labelText: 'Nome do serviço',
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller:
                                                  _editDurationController,
                                              keyboardType:
                                                  TextInputType.number,
                                              decoration: const InputDecoration(
                                                labelText: 'Duração (min)',
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: TextField(
                                              controller:
                                                  _editIntervalController,
                                              keyboardType:
                                                  TextInputType.number,
                                              decoration: const InputDecoration(
                                                labelText: 'Intervalo (min)',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      TextField(
                                        controller: _editPriceController,
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(
                                          labelText: 'Preço (R\$) opcional',
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      DropdownButtonFormField<String>(
                                        initialValue:
                                            _editingServiceSpecialtyId,
                                        decoration: const InputDecoration(
                                          labelText: 'Especialidade',
                                        ),
                                        items: [
                                          const DropdownMenuItem<String>(
                                            value: null,
                                            child: Text('Sem especialidade'),
                                          ),
                                          ..._specialties.map(
                                            (item) => DropdownMenuItem<String>(
                                              value: item['id'] as String,
                                              child: Text(
                                                (item['name'] as String?) ??
                                                    '-',
                                              ),
                                            ),
                                          ),
                                        ],
                                        onChanged: (value) => setState(
                                          () => _editingServiceSpecialtyId =
                                              value,
                                        ),
                                      ),
                                    ],
                                  )
                                : Text((row['name'] as String?) ?? '-'),
                            subtitle: _editingServiceId == row['id']
                                ? null
                                : Text(
                                    '${row['duration_min'] ?? 0} min (+${row['interval_min'] ?? 0} min) • ${_formatPriceLabel(row['price_cents'])} • ${_specialtyName(row['specialty_id'] as String?)}',
                                  ),
                            trailing: Wrap(
                              spacing: 4,
                              children: [
                                if (_editingServiceId == row['id'])
                                  IconButton(
                                    onPressed: _saving
                                        ? null
                                        : () => _saveEditingService(row),
                                    icon: const Icon(Icons.check_outlined),
                                    tooltip: 'Salvar',
                                  )
                                else
                                  IconButton(
                                    onPressed: () => _startEditingService(row),
                                    icon: const Icon(Icons.edit_outlined),
                                    tooltip: 'Editar',
                                  ),
                                if (_editingServiceId == row['id'])
                                  IconButton(
                                    onPressed:
                                        _saving ? null : _cancelEditingService,
                                    icon: const Icon(Icons.close_outlined),
                                    tooltip: 'Cancelar',
                                  ),
                                IconButton(
                                  onPressed: () => _toggleServiceActive(row),
                                  icon: Icon(row['active'] == true
                                      ? Icons.toggle_on
                                      : Icons.toggle_off),
                                  tooltip: row['active'] == true
                                      ? 'Desativar'
                                      : 'Ativar',
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
    );
  }
}
