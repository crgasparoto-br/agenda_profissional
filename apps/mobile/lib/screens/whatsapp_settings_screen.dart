import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/tenant_service.dart';
import '../theme/app_theme.dart';

class WhatsappSettingsScreen extends StatefulWidget {
  const WhatsappSettingsScreen({super.key});

  @override
  State<WhatsappSettingsScreen> createState() => _WhatsappSettingsScreenState();
}

class _WhatsappSettingsScreenState extends State<WhatsappSettingsScreen> {
  final _tenantService = TenantService();
  final _labelController = TextEditingController(text: 'Canal principal');
  final _numberController = TextEditingController();
  final _phoneNumberIdController = TextEditingController();
  final _aiModelController = TextEditingController(text: 'gpt-4.1-mini');
  final _aiPromptController = TextEditingController(
    text:
        'Você é a secretária virtual da Agenda Profissional. Cumprimente o cliente, peça dia e horário e confirme agendamento somente após validação da disponibilidade.',
  );

  bool _loading = true;
  bool _saving = false;
  bool _active = true;
  bool _aiEnabled = true;
  String? _tenantId;
  String? _editingId;
  String _selectedProfessionalId = '';
  String? _error;
  String? _status;

  List<Map<String, dynamic>> _channels = const [];
  List<Map<String, dynamic>> _professionals = const [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _labelController.dispose();
    _numberController.dispose();
    _phoneNumberIdController.dispose();
    _aiModelController.dispose();
    _aiPromptController.dispose();
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
    final channels = await supabase
        .from('whatsapp_channel_settings')
        .select(
            'id, label, whatsapp_number, phone_number_id, active, ai_enabled, ai_model, ai_system_prompt, professional_id, professionals(name)')
        .eq('tenant_id', _tenantId!)
        .order('created_at');
    final professionals = await supabase
        .from('professionals')
        .select('id, name, active')
        .eq('tenant_id', _tenantId!)
        .eq('active', true)
        .order('name');

    if (!mounted) return;
    setState(() {
      _channels = List<Map<String, dynamic>>.from(channels);
      _professionals = List<Map<String, dynamic>>.from(professionals);
    });
  }

  void _resetForm() {
    setState(() {
      _editingId = null;
      _labelController.text = 'Canal principal';
      _numberController.clear();
      _phoneNumberIdController.clear();
      _active = true;
      _aiEnabled = true;
      _aiModelController.text = 'gpt-4.1-mini';
      _aiPromptController.text =
          'Você é a secretária virtual da Agenda Profissional. Cumprimente o cliente, peça dia e horário e confirme agendamento somente após validação da disponibilidade.';
      _selectedProfessionalId = '';
    });
  }

  void _startEdit(Map<String, dynamic> row) {
    setState(() {
      _editingId = row['id'] as String;
      _labelController.text = (row['label'] as String?) ?? 'Canal principal';
      _numberController.text = (row['whatsapp_number'] as String?) ?? '';
      _phoneNumberIdController.text = (row['phone_number_id'] as String?) ?? '';
      _active = row['active'] == true;
      _aiEnabled = row['ai_enabled'] == true;
      _aiModelController.text = (row['ai_model'] as String?)?.trim().isNotEmpty == true
          ? row['ai_model'] as String
          : 'gpt-4.1-mini';
      _aiPromptController.text = (row['ai_system_prompt'] as String?)?.trim().isNotEmpty == true
          ? row['ai_system_prompt'] as String
          : _aiPromptController.text;
      _selectedProfessionalId = (row['professional_id'] as String?) ?? '';
    });
  }

  Future<void> _saveChannel() async {
    if (_tenantId == null) return;
    if (_numberController.text.trim().isEmpty || _phoneNumberIdController.text.trim().isEmpty) {
      setState(() => _error = 'Informe o número de WhatsApp e o Phone Number ID.');
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
        'label': _labelController.text.trim().isEmpty ? 'Canal principal' : _labelController.text.trim(),
        'whatsapp_number': _numberController.text.trim(),
        'phone_number_id': _phoneNumberIdController.text.trim(),
        'professional_id': _selectedProfessionalId.isEmpty ? null : _selectedProfessionalId,
        'active': _active,
        'ai_enabled': _aiEnabled,
        'ai_model': _aiModelController.text.trim().isEmpty ? 'gpt-4.1-mini' : _aiModelController.text.trim(),
        'ai_system_prompt': _aiPromptController.text.trim().isEmpty ? null : _aiPromptController.text.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      if (_editingId == null) {
        await Supabase.instance.client.from('whatsapp_channel_settings').insert(payload);
        setState(() => _status = 'Canal cadastrado com sucesso.');
      } else {
        await Supabase.instance.client
            .from('whatsapp_channel_settings')
            .update(payload)
            .eq('id', _editingId!);
        setState(() => _status = 'Canal atualizado com sucesso.');
      }

      _resetForm();
      await _loadAll();
    } catch (error) {
      setState(() => _error = 'Erro ao salvar canal: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteChannel(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir canal'),
        content: const Text('Deseja remover este canal do WhatsApp?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await Supabase.instance.client.from('whatsapp_channel_settings').delete().eq('id', id);
      setState(() => _status = 'Canal removido com sucesso.');
      if (_editingId == id) {
        _resetForm();
      }
      await _loadAll();
    } catch (error) {
      setState(() => _error = 'Erro ao remover canal: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WhatsApp + IA')),
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
                        Text(
                          _editingId == null ? 'Novo canal' : 'Editar canal',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _labelController,
                          decoration: const InputDecoration(labelText: 'Nome do canal'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _numberController,
                          decoration: const InputDecoration(labelText: 'Número WhatsApp'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _phoneNumberIdController,
                          decoration: const InputDecoration(labelText: 'Phone Number ID (Meta)'),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedProfessionalId,
                          decoration: const InputDecoration(labelText: 'Profissional (opcional)'),
                          items: [
                            const DropdownMenuItem<String>(
                              value: '',
                              child: Text('Canal geral da organização'),
                            ),
                            ..._professionals.map(
                              (row) => DropdownMenuItem<String>(
                                value: row['id'] as String,
                                child: Text((row['name'] as String?) ?? '-'),
                              ),
                            ),
                          ],
                          onChanged: (value) => setState(() => _selectedProfessionalId = value ?? ''),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _active,
                          onChanged: (value) => setState(() => _active = value),
                          title: const Text('Canal ativo'),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _aiEnabled,
                          onChanged: (value) => setState(() => _aiEnabled = value),
                          title: const Text('IA habilitada'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _aiModelController,
                          decoration: const InputDecoration(labelText: 'Modelo de IA'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _aiPromptController,
                          minLines: 4,
                          maxLines: 6,
                          decoration: const InputDecoration(labelText: 'Prompt da IA'),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _saving ? null : _saveChannel,
                                child: Text(
                                  _saving
                                      ? 'Salvando...'
                                      : _editingId == null
                                          ? 'Cadastrar canal'
                                          : 'Salvar canal',
                                ),
                              ),
                            ),
                            if (_editingId != null) ...[
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: _saving ? null : _resetForm,
                                child: const Text('Cancelar edição'),
                              ),
                            ]
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (_status != null) ...[
                  const SizedBox(height: 8),
                  Text(_status!, style: const TextStyle(color: AppColors.secondary)),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: AppColors.danger)),
                ],
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Canais cadastrados', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        if (_channels.isEmpty) const Text('Nenhum canal cadastrado.'),
                        ..._channels.map(
                          (row) {
                            final professional = row['professionals'] as Map<String, dynamic>?;
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text((row['label'] as String?) ?? '-'),
                              subtitle: Text(
                                '${row['whatsapp_number'] ?? '-'} • ${row['phone_number_id'] ?? '-'}\n'
                                'Profissional: ${professional?['name'] ?? 'Geral'} • ${row['active'] == true ? 'Ativo' : 'Inativo'} • IA ${row['ai_enabled'] == true ? 'ligada' : 'desligada'}',
                              ),
                              isThreeLine: true,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    onPressed: () => _startEdit(row),
                                    icon: const Icon(Icons.edit_outlined),
                                    tooltip: 'Editar',
                                  ),
                                  IconButton(
                                    onPressed: () => _deleteChannel(row['id'] as String),
                                    icon: const Icon(Icons.delete_outline),
                                    tooltip: 'Excluir',
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Checklist de ativação'),
                        SizedBox(height: 6),
                        Text('1. Configure o token de acesso em WHATSAPP_ACCESS_TOKEN.'),
                        Text('2. Cadastre número e Phone Number ID do Meta.'),
                        Text('3. Aponte o webhook para /functions/v1/whatsapp-webhook.'),
                        Text('4. Ative a IA no canal para respostas automáticas.'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
