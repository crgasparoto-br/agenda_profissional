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
  final _durationController = TextEditingController(text: '60');
  final _intervalController = TextEditingController(text: '0');

  String? _tenantId;
  String? _selectedSpecialtyId;
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
        .select('id, name, duration_min, interval_min, active, specialty_id')
        .eq('tenant_id', _tenantId!)
        .order('name');
    if (!mounted) return;
    setState(() {
      _specialties = List<Map<String, dynamic>>.from(specialties);
      _services = List<Map<String, dynamic>>.from(services);
    });
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
    if (duration <= 0) {
      setState(() => _error = 'Duração deve ser maior que zero.');
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
        'active': true,
      });
      _serviceController.clear();
      _durationController.text = '60';
      _intervalController.text = '0';
      setState(() => _status = 'Serviço cadastrado com sucesso.');
      await _loadAll();
    } catch (error) {
      setState(() => _error = 'Erro ao cadastrar serviço: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
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
                          decoration: const InputDecoration(labelText: 'Nome da especialidade'),
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
                          decoration: const InputDecoration(labelText: 'Nome do serviço'),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedSpecialtyId,
                          decoration: const InputDecoration(labelText: 'Especialidade'),
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
                          onChanged: (value) => setState(() => _selectedSpecialtyId = value),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _durationController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Duração (min)'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _intervalController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Intervalo (min)'),
                              ),
                            ),
                          ],
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
                  Text(_error!, style: const TextStyle(color: AppColors.danger)),
                ],
                if (_status != null) ...[
                  const SizedBox(height: 8),
                  Text(_status!, style: const TextStyle(color: AppColors.secondary)),
                ],
                const SizedBox(height: 8),
                Card(
                  child: ExpansionTile(
                    title: const Text('Especialidades'),
                    children: _specialties
                        .map(
                          (row) => ListTile(
                            title: Text((row['name'] as String?) ?? '-'),
                            subtitle: Text(row['active'] == true ? 'Ativa' : 'Inativa'),
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
                            title: Text((row['name'] as String?) ?? '-'),
                            subtitle: Text(
                              '${row['duration_min'] ?? 0} min (+${row['interval_min'] ?? 0} min) • ${_specialtyName(row['specialty_id'] as String?)}',
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
