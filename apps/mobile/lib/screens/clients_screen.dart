import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/tenant_service.dart';
import '../theme/app_theme.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final _tenantService = TenantService();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();

  bool _loading = false;
  bool _saving = false;
  String? _error;
  String? _status;
  String? _tenantId;
  String? _editingId;
  List<Map<String, dynamic>> _clients = const [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tenantId = await _tenantService.requireTenantId();
      _tenantId = tenantId;
      await _loadClients();
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadClients() async {
    if (_tenantId == null) return;
    final supabase = Supabase.instance.client;
    final data = await supabase
        .from('clients')
        .select('id, full_name, phone, notes')
        .eq('tenant_id', _tenantId!)
        .order('full_name');
    if (!mounted) return;
    setState(() => _clients = List<Map<String, dynamic>>.from(data));
  }

  void _startCreate() {
    setState(() {
      _editingId = null;
      _status = null;
      _error = null;
    });
    _nameController.clear();
    _phoneController.clear();
    _notesController.clear();
  }

  void _startEdit(Map<String, dynamic> row) {
    setState(() {
      _editingId = row['id'] as String;
      _status = null;
      _error = null;
    });
    _nameController.text = (row['full_name'] as String?) ?? '';
    _phoneController.text = (row['phone'] as String?) ?? '';
    _notesController.text = (row['notes'] as String?) ?? '';
  }

  Future<void> _saveClient() async {
    if (_tenantId == null) return;
    if (_nameController.text.trim().isEmpty) {
      setState(() => _error = 'Informe o nome do cliente.');
      return;
    }
    final supabase = Supabase.instance.client;
    setState(() {
      _saving = true;
      _error = null;
      _status = null;
    });
    try {
      final payload = <String, dynamic>{
        'tenant_id': _tenantId,
        'full_name': _nameController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        'notes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      };
      if (_editingId == null) {
        await supabase.from('clients').insert(payload);
        setState(() => _status = 'Cliente cadastrado com sucesso.');
      } else {
        await supabase.from('clients').update(payload).eq('id', _editingId!);
        setState(() => _status = 'Cliente atualizado com sucesso.');
      }
      _startCreate();
      await _loadClients();
    } catch (error) {
      setState(() => _error = 'Erro ao salvar cliente: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteClient(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover cliente'),
        content: const Text('Deseja remover este cliente?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remover')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await Supabase.instance.client.from('clients').delete().eq('id', id);
      setState(() => _status = 'Cliente removido com sucesso.');
      await _loadClients();
    } catch (error) {
      setState(() => _error = 'Erro ao remover cliente: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clientes')),
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
                        TextField(
                          controller: _phoneController,
                          decoration: const InputDecoration(labelText: 'WhatsApp'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _notesController,
                          minLines: 2,
                          maxLines: 3,
                          decoration: const InputDecoration(labelText: 'Observações'),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _saving ? null : _saveClient,
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
                    itemCount: _clients.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final row = _clients[index];
                      return ListTile(
                        title: Text((row['full_name'] as String?) ?? '-'),
                        subtitle: Text((row['phone'] as String?) ?? 'Sem WhatsApp'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Editar',
                              onPressed: () => _startEdit(row),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Remover',
                              onPressed: () => _deleteClient(row['id'] as String),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
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

