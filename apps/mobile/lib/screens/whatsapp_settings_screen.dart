import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_exception.dart';
import '../services/tenant_service.dart';
import '../theme/app_theme.dart';

class WhatsappSettingsScreen extends StatefulWidget {
  const WhatsappSettingsScreen({super.key});

  @override
  State<WhatsappSettingsScreen> createState() => _WhatsappSettingsScreenState();
}

class _WhatsappIntegrationStatus {
  const _WhatsappIntegrationStatus({
    required this.id,
    required this.connectionStatus,
    required this.whatsappNumber,
    required this.metaPhoneNumberId,
    required this.metaBusinessAccountId,
    required this.verifiedName,
    required this.displayName,
    required this.accountLabel,
    required this.lastError,
  });

  final String id;
  final String connectionStatus;
  final String? whatsappNumber;
  final String? metaPhoneNumberId;
  final String? metaBusinessAccountId;
  final String? verifiedName;
  final String? displayName;
  final String? accountLabel;
  final String? lastError;

  factory _WhatsappIntegrationStatus.fromJson(Map<String, dynamic> json) {
    return _WhatsappIntegrationStatus(
      id: (json['id'] as String?) ?? '',
      connectionStatus: (json['connection_status'] as String?) ?? 'not_connected',
      whatsappNumber: json['whatsapp_number'] as String?,
      metaPhoneNumberId: json['meta_phone_number_id'] as String?,
      metaBusinessAccountId: json['meta_business_account_id'] as String?,
      verifiedName: json['verified_name'] as String?,
      displayName: json['display_name'] as String?,
      accountLabel: json['account_label'] as String?,
      lastError: json['last_error'] as String?,
    );
  }
}

class _WhatsappSettingsScreenState extends State<WhatsappSettingsScreen> {
  static const _defaultPrompt =
      'Voce e a secretaria virtual da Agenda Profissional. Cumprimente o cliente, peca dia e horario e confirme agendamento somente apos validacao da disponibilidade.';

  final _tenantService = TenantService();
  final _labelController = TextEditingController(text: 'Canal principal');
  final _numberController = TextEditingController();
  final _phoneNumberIdController = TextEditingController();
  final _aiModelController = TextEditingController(text: 'gpt-4.1-mini');
  final _aiPromptController = TextEditingController(text: _defaultPrompt);

  bool _loading = true;
  bool _saving = false;
  bool _active = true;
  bool _aiEnabled = true;
  bool _audioEnabled = true;
  bool _showAdvancedSettings = false;
  String? _tenantId;
  String? _editingId;
  String _selectedProfessionalId = '';
  String? _error;
  String? _status;
  _WhatsappIntegrationStatus? _integration;

  List<Map<String, dynamic>> _channels = const [];
  List<Map<String, dynamic>> _professionals = const [];

  String _integrationStatusLabel(String? status) {
    switch (status) {
      case 'connected':
        return 'Conectada';
      case 'pending':
        return 'Pendente';
      case 'error':
        return 'Com erro';
      case 'disconnected':
        return 'Desconectada';
      default:
        return 'Nao conectada';
    }
  }

  String _integrationStatusDescription(String? status) {
    switch (status) {
      case 'connected':
        return 'A conta Meta esta pronta e o numero ja pode ser usado pelo app.';
      case 'pending':
        return 'A conexao foi iniciada, mas ainda faltam dados para liberar o canal.';
      case 'error':
        return 'A Meta retornou um problema na conexao. Revise a integracao e tente novamente.';
      case 'disconnected':
        return 'A conta foi desconectada. Conecte novamente para voltar a usar o WhatsApp.';
      default:
        return 'Ainda nao existe uma conta Meta conectada para esta organizacao.';
    }
  }

  String _normalizePhone(String value) {
    var digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('55') && digits.length >= 12) {
      digits = digits.substring(2);
    }
    while (digits.length > 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    if (digits.length > 11) {
      digits = digits.substring(digits.length - 11);
    }
    return digits;
  }

  String _formatPhoneDigits(String value) {
    final digits = _normalizePhone(value);
    if (digits.isEmpty) return '';
    if (digits.length <= 2) return digits;
    if (digits.length <= 6) {
      return '(${digits.substring(0, 2)}) ${digits.substring(2)}';
    }
    if (digits.length <= 10) {
      return '(${digits.substring(0, 2)}) ${digits.substring(2, 6)}-${digits.substring(6)}';
    }
    return '(${digits.substring(0, 2)}) ${digits.substring(2, 7)}-${digits.substring(7)}';
  }

  String _friendlyPostgrestMessage(PostgrestException error) {
    final message = error.message.toLowerCase();
    final details = (error.details is String ? error.details as String : '').toLowerCase();
    final code = error.code;

    if (code == '23505' || message.contains('duplicate key') || details.contains('already exists')) {
      if (message.contains('phone_number_id')) {
        return 'Esse numero da Meta ja esta conectado em outro canal.';
      }
      if (message.contains('professional_id')) {
        return 'Ja existe um canal vinculado a esse profissional.';
      }
      return 'Ja existe um cadastro igual a esse. Revise os dados e tente novamente.';
    }

    if (message.contains('row-level security') || message.contains('permission denied')) {
      return 'Voce nao tem permissao para alterar essa configuracao. Entre com um perfil administrador.';
    }

    if (message.contains('invalid input syntax')) {
      return 'Algum dado informado esta em formato invalido. Revise os campos e tente novamente.';
    }

    return 'Nao foi possivel salvar a configuracao agora. Tente novamente em instantes.';
  }

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
    } on AppException catch (error) {
      setState(() => _error = error.message);
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAll() async {
    if (_tenantId == null) return;
    final supabase = Supabase.instance.client;
    try {
      final results = await Future.wait([
        supabase
            .from('whatsapp_channel_settings')
            .select(
                'id, label, whatsapp_number, phone_number_id, active, ai_enabled, audio_enabled, ai_model, ai_system_prompt, professional_id, professionals(name)')
            .eq('tenant_id', _tenantId!)
            .order('created_at'),
        supabase
            .from('professionals')
            .select('id, name, active')
            .eq('tenant_id', _tenantId!)
            .eq('active', true)
            .order('name'),
        supabase
            .from('whatsapp_meta_integrations')
            .select(
                'id, connection_status, whatsapp_number, meta_phone_number_id, meta_business_account_id, verified_name, display_name, account_label, last_error')
            .maybeSingle(),
      ]);

      final channels = results[0] as List;
      final professionals = results[1] as List;
      final integration = results[2];

      if (!mounted) return;
      setState(() {
        _channels = List<Map<String, dynamic>>.from(channels);
        _professionals = List<Map<String, dynamic>>.from(professionals);
        _integration = integration is Map<String, dynamic>
            ? _WhatsappIntegrationStatus.fromJson(integration)
            : null;
      });
    } on PostgrestException catch (error) {
      throw AppException(
        message: _friendlyPostgrestMessage(error),
        code: error.code ?? 'postgrest_error',
      );
    }
  }

  void _resetForm() {
    setState(() {
      _editingId = null;
      _labelController.text = 'Canal principal';
      _numberController.clear();
      _phoneNumberIdController.clear();
      _active = true;
      _aiEnabled = true;
      _audioEnabled = true;
      _aiModelController.text = 'gpt-4.1-mini';
      _aiPromptController.text = _defaultPrompt;
      _numberController.text =
          _formatPhoneDigits(_integration?.whatsappNumber ?? '');
      _phoneNumberIdController.text = _integration?.metaPhoneNumberId ?? '';
      _selectedProfessionalId = '';
      _showAdvancedSettings = false;
    });
  }

  void _startEdit(Map<String, dynamic> row) {
    final phoneNumberId = (row['phone_number_id'] as String?) ?? '';
    setState(() {
      _editingId = row['id'] as String;
      _labelController.text = (row['label'] as String?) ?? 'Canal principal';
      _numberController.text =
          _formatPhoneDigits((row['whatsapp_number'] as String?) ?? '');
      _phoneNumberIdController.text = phoneNumberId;
      _active = row['active'] == true;
      _aiEnabled = row['ai_enabled'] == true;
      _audioEnabled = row['audio_enabled'] == true;
      _aiModelController.text =
          (row['ai_model'] as String?)?.trim().isNotEmpty == true
              ? row['ai_model'] as String
              : 'gpt-4.1-mini';
      _aiPromptController.text =
          (row['ai_system_prompt'] as String?)?.trim().isNotEmpty == true
              ? row['ai_system_prompt'] as String
              : _defaultPrompt;
      _selectedProfessionalId = (row['professional_id'] as String?) ?? '';
      _showAdvancedSettings = false;
    });
  }

  Future<void> _saveChannel() async {
    if (_tenantId == null) return;
    final normalizedPhone = _normalizePhone(_numberController.text);
    if (normalizedPhone.isEmpty ||
        _phoneNumberIdController.text.trim().isEmpty) {
      setState(
        () => _error =
            'Conecte primeiro a conta Meta da organizacao para liberar a configuracao do canal.',
      );
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
        'label': _labelController.text.trim().isEmpty
            ? 'Canal principal'
            : _labelController.text.trim(),
        'whatsapp_number': normalizedPhone,
        'phone_number_id': _phoneNumberIdController.text.trim(),
        'professional_id':
            _selectedProfessionalId.isEmpty ? null : _selectedProfessionalId,
        'active': _active,
        'ai_enabled': _aiEnabled,
        'audio_enabled': _audioEnabled,
        'ai_model': _aiModelController.text.trim().isEmpty
            ? 'gpt-4.1-mini'
            : _aiModelController.text.trim(),
        'ai_system_prompt': _aiPromptController.text.trim().isEmpty
            ? null
            : _aiPromptController.text.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      if (_editingId == null) {
        await Supabase.instance.client
            .from('whatsapp_channel_settings')
            .insert(payload);
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
    } on PostgrestException catch (error) {
      setState(() => _error = _friendlyPostgrestMessage(error));
    } catch (_) {
      setState(() => _error = 'Erro ao salvar canal. Tente novamente.');
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await Supabase.instance.client
          .from('whatsapp_channel_settings')
          .delete()
          .eq('id', id);
      setState(() => _status = 'Canal removido com sucesso.');
      if (_editingId == id) {
        _resetForm();
      }
      await _loadAll();
    } on PostgrestException catch (error) {
      setState(() => _error = _friendlyPostgrestMessage(error));
    } catch (_) {
      setState(() => _error = 'Erro ao remover canal. Tente novamente.');
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
                          'WhatsApp + IA',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _channels.isEmpty
                              ? 'Vamos preparar a conexao do WhatsApp de cada organizacao com a propria conta Meta.'
                              : 'Revise aqui o status da conta Meta e as configuracoes do canal conectado.',
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.secondary.withValues(alpha: 0.18),
                            ),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Antes de ativar',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'A estrategia agora e cada tenant conectar a propria conta Meta. Esta tela separa o estado da conexao Meta da configuracao do canal dentro do app.',
                              ),
                            ],
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
                        Text(
                          'Conta Meta',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Status atual: ${_integrationStatusLabel(_integration?.connectionStatus)}',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _integrationStatusDescription(
                            _integration?.connectionStatus,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_integration == null) ...[
                          const Text(
                            'Nenhuma conta Meta conectada para esta organizacao.',
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Na proxima fase vamos abrir aqui o fluxo oficial de conexao via Embedded Signup da Meta.',
                          ),
                        ] else ...[
                          Text(
                            'Numero conectado: ${_integration?.whatsappNumber?.isNotEmpty == true ? _formatPhoneDigits(_integration!.whatsappNumber!) : 'Nao informado'}',
                          ),
                          Text(
                            'Nome verificado: ${_integration?.verifiedName?.isNotEmpty == true ? _integration!.verifiedName! : 'Nao informado'}',
                          ),
                          Text(
                            'Conta: ${_integration?.accountLabel?.isNotEmpty == true ? _integration!.accountLabel! : (_integration?.displayName?.isNotEmpty == true ? _integration!.displayName! : 'Nao informado')}',
                          ),
                          if (_integration?.lastError?.isNotEmpty == true) ...[
                            const SizedBox(height: 8),
                            Text(
                              _integration!.lastError!,
                              style: const TextStyle(color: AppColors.danger),
                            ),
                          ],
                        ],
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
                        Text(
                          _editingId == null ? 'Novo canal' : 'Editar canal',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        if (_integration == null ||
                            _integration?.connectionStatus != 'connected') ...[
                          const Text(
                            'Conecte primeiro a conta Meta da organizacao para liberar a configuracao do canal.',
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Quando a conexao estiver pronta, o numero e o identificador tecnico serao preenchidos a partir dessa integracao.',
                          ),
                        ] else ...[
                          const Text(
                            'Com a conta Meta conectada, aqui voce ajusta como esse canal sera usado dentro do app.',
                          ),
                          const SizedBox(height: 12),
                        TextField(
                          controller: _labelController,
                          decoration: const InputDecoration(
                            labelText: 'Nome do canal',
                            hintText: 'Ex.: Recepcao principal',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _numberController,
                          keyboardType: TextInputType.phone,
                          onChanged: (value) {
                            final formatted = _formatPhoneDigits(value);
                            if (formatted == value) return;
                            _numberController.value = TextEditingValue(
                              text: formatted,
                              selection: TextSelection.collapsed(
                                offset: formatted.length,
                              ),
                            );
                          },
                          decoration: const InputDecoration(
                            labelText: 'Numero de WhatsApp',
                            hintText: '(11) 99999-9999',
                            helperText:
                                'Esse numero vem da conta Meta conectada.',
                          ),
                          enabled: false,
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedProfessionalId,
                          decoration: const InputDecoration(
                            labelText: 'Profissional (opcional)',
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: '',
                              child: Text('Canal geral da organizacao'),
                            ),
                            ..._professionals.map(
                              (row) => DropdownMenuItem<String>(
                                value: row['id'] as String,
                                child: Text((row['name'] as String?) ?? '-'),
                              ),
                            ),
                          ],
                          onChanged: (value) => setState(
                            () => _selectedProfessionalId = value ?? '',
                          ),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _active,
                          onChanged: (value) => setState(() => _active = value),
                          title: const Text('Canal ativo'),
                          subtitle: const Text(
                            'Quando ligado, o sistema pode responder e enviar mensagens por este numero.',
                          ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _aiEnabled,
                          onChanged: (value) => setState(() => _aiEnabled = value),
                          title: const Text('Responder com IA'),
                          subtitle: const Text(
                            'Ative para a assistente ajudar no atendimento e no agendamento.',
                          ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _audioEnabled,
                          onChanged: (value) => setState(() => _audioEnabled = value),
                          title: const Text('Aceitar audio'),
                          subtitle: const Text(
                            'Permite transcrever mensagens de voz recebidas no WhatsApp.',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Card(
                          margin: EdgeInsets.zero,
                          color: AppColors.background,
                          elevation: 0,
                          child: ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            initiallyExpanded: _showAdvancedSettings,
                            onExpansionChanged: (value) =>
                                setState(() => _showAdvancedSettings = value),
                            title: const Text('Configuracoes avancadas'),
                            subtitle: const Text(
                              'Codigo manual da Meta, modelo e instrucoes da IA.',
                            ),
                            children: [
                              TextField(
                                controller: _phoneNumberIdController,
                                decoration: const InputDecoration(
                                  labelText: 'Codigo de conexao do numero (Meta)',
                                  hintText: 'Ex.: 123456789012345',
                                  helperText:
                                      'Esse identificador tecnico vem da conexao Meta do tenant.',
                                ),
                                enabled: false,
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _aiModelController,
                                decoration: const InputDecoration(
                                  labelText: 'Modelo de IA',
                                  helperText:
                                      'Recomendado manter o padrao para evitar configuracoes desnecessarias.',
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _aiPromptController,
                                minLines: 4,
                                maxLines: 6,
                                decoration: const InputDecoration(
                                  labelText: 'Instrucoes da IA',
                                  helperText:
                                      'Use apenas se quiser personalizar o jeito de responder.',
                                ),
                              ),
                            ],
                          ),
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
                                child: const Text('Cancelar edicao'),
                              ),
                            ]
                          ],
                        ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_status != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _status!,
                    style: const TextStyle(color: AppColors.secondary),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      border: Border.all(
                        color: AppColors.danger.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFF702621)),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Canais cadastrados',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        if (_channels.isEmpty)
                          const Text('Nenhum canal cadastrado.'),
                        ..._channels.map(
                          (row) {
                            final professional =
                                row['professionals'] as Map<String, dynamic>?;
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text((row['label'] as String?) ?? '-'),
                              subtitle: Text(
                                '${_formatPhoneDigits((row['whatsapp_number'] as String?) ?? '')}\n'
                                'Profissional: ${professional?['name'] ?? 'Geral'} | ${row['active'] == true ? 'Ativo' : 'Inativo'} | IA ${row['ai_enabled'] == true ? 'ligada' : 'desligada'} | Audio ${row['audio_enabled'] == true ? 'ligado' : 'desligado'}',
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
                                    onPressed: () =>
                                        _deleteChannel(row['id'] as String),
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
                        Text(
                          'Como ativar sem complicacao',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: 10),
                        Text('1. Cada organizacao vai conectar a propria conta Meta ao app.'),
                        SizedBox(height: 4),
                        Text(
                          '2. Depois da conexao, o numero e o identificador tecnico vao aparecer nesta tela.',
                        ),
                        SizedBox(height: 4),
                        Text(
                          '3. A configuracao do canal fica separada da conexao da conta Meta.',
                        ),
                        SizedBox(height: 4),
                        Text(
                          '4. Na proxima fase vamos habilitar aqui o fluxo oficial de conexao Embedded Signup.',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
