import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/tenant_service.dart';
import '../theme/app_theme.dart';

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
  String? _tenantId;
  String? _editingId;
  String? _error;
  String? _status;
  List<Map<String, dynamic>> _professionals = const [];

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
      await _loadProfessionals();
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadProfessionals() async {
    if (_tenantId == null) return;
    final data = await Supabase.instance.client
        .from('professionals')
        .select('id, name, active')
        .eq('tenant_id', _tenantId!)
        .order('name');
    if (!mounted) return;
    setState(() => _professionals = List<Map<String, dynamic>>.from(data));
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
        await Supabase.instance.client.from('professionals').update(payload).eq('id', _editingId!);
        setState(() => _status = 'Profissional atualizado com sucesso.');
      }
      _startCreate();
      await _loadProfessionals();
    } catch (error) {
      setState(() => _error = 'Erro ao salvar profissional: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
                                child: Text(_saving
                                    ? 'Salvando...'
                                    : _editingId == null
                                        ? 'Adicionar'
                                        : 'Salvar'),
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
                  Text(_error!, style: const TextStyle(color: AppColors.danger)),
                ],
                if (_status != null) ...[
                  const SizedBox(height: 8),
                  Text(_status!, style: const TextStyle(color: AppColors.secondary)),
                ],
                const SizedBox(height: 8),
                Card(
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _professionals.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final row = _professionals[index];
                      final active = row['active'] == true;
                      return ListTile(
                        title: Text((row['name'] as String?) ?? '-'),
                        subtitle: Text(active ? 'Ativo' : 'Inativo'),
                        trailing: IconButton(
                          onPressed: () => _startEdit(row),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

