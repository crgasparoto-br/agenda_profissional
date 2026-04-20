import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
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
  final _dateFormat = DateFormat('dd/MM/yyyy');
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _notesController = TextEditingController();

  bool _loading = false;
  bool _saving = false;
  String? _error;
  String? _status;
  String? _tenantId;
  String? _editingId;
  bool _locationSharingEnabled = false;
  DateTime? _locationSharingAuthorizedAt;
  DateTime? _birthday;
  String? _preferredContactChannel = 'whatsapp';
  List<Map<String, dynamic>> _clients = const [];

  String _mapClientSchemaError(Object error, {required String fallback}) {
    if (error is PostgrestException) {
      final message = error.message.toLowerCase();
      if (message.contains('birthday') ||
          message.contains('email') ||
          message.contains('preferred_contact_channel') ||
          message.contains('location_sharing_enabled') ||
          message.contains('location_sharing_authorized_at')) {
        return 'O banco de dados ainda nao foi atualizado para a tela de clientes. Aplique as migrations pendentes do Supabase e tente novamente.';
      }
    }

    return '$fallback$error';
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

  String _formatPhoneDigits(String digitsInput) {
    final digits = _normalizePhone(digitsInput);
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

  String _formatPhone(String? value) {
    if (value == null || value.trim().isEmpty) return 'Sem WhatsApp';
    return _formatPhoneDigits(value);
  }

  DateTime? _parseOptionalDateTime(dynamic value) {
    if (value is! String || value.trim().isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  String _formatAuthorizedDate(DateTime? value) {
    if (value == null) return 'Nao informada';
    return _dateFormat.format(value);
  }

  String _buildClientSubtitle(Map<String, dynamic> row) {
    final parts = <String>[_formatPhone(row['phone'] as String?)];

    final email = (row['email'] as String?)?.trim();
    if (email != null && email.isNotEmpty) {
      parts.add('E-mail: $email');
    }

    final birthday = _parseBirthday(row['birthday']);
    if (birthday != null) {
      parts.add('Aniversário: ${_dateFormat.format(birthday)}');
    }

    final preferredContactChannel = row['preferred_contact_channel'] as String?;
    if (preferredContactChannel != null && preferredContactChannel.isNotEmpty) {
      parts.add('Contato preferido: ${_formatPreferredContactChannel(preferredContactChannel)}');
    }

    final locationSharingEnabled = row['location_sharing_enabled'] as bool? ?? false;
    final authorizedAt = _parseOptionalDateTime(
      row['location_sharing_authorized_at'],
    );

    if (locationSharingEnabled) {
      parts.add('Localizacao autorizada em ${_formatAuthorizedDate(authorizedAt)}');
    } else {
      parts.add('Localizacao nao autorizada');
    }

    final notes = (row['notes'] as String?)?.trim();
    if (notes != null && notes.isNotEmpty) {
      parts.add(notes);
    }

    return parts.join('\n');
  }

  Future<void> _pickAuthorizedDate() async {
    final initialDate = _locationSharingAuthorizedAt ?? DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selected == null || !mounted) return;

    setState(() {
      _locationSharingEnabled = true;
      _locationSharingAuthorizedAt = DateTime(
        selected.year,
        selected.month,
        selected.day,
        12,
      );
    });
  }

  Future<void> _pickBirthday() async {
    final initialDate = _birthday ?? DateTime(1990);
    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (selected == null || !mounted) return;
    setState(() => _birthday = selected);
  }

  String _formatBirthday(DateTime? value) {
    if (value == null) return 'Não informado';
    return _dateFormat.format(value);
  }

  String _formatPreferredContactChannel(String value) {
    switch (value) {
      case 'email':
        return 'E-mail';
      case 'phone':
        return 'Ligação';
      case 'whatsapp':
      default:
        return 'WhatsApp';
    }
  }

  DateTime? _parseBirthday(dynamic value) {
    if (value is! String || value.trim().isEmpty) return null;
    return DateTime.tryParse(value);
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
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
      setState(() => _error = _mapClientSchemaError(error, fallback: 'Erro ao carregar clientes: '));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadClients() async {
    if (_tenantId == null) return;
    final supabase = Supabase.instance.client;
    final data = await supabase
        .from('clients')
      .select(
        'id, full_name, phone, email, notes, birthday, preferred_contact_channel, location_sharing_enabled, location_sharing_authorized_at')
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
    _emailController.clear();
    _notesController.clear();
    _locationSharingEnabled = false;
    _locationSharingAuthorizedAt = null;
    _birthday = null;
    _preferredContactChannel = 'whatsapp';
  }

  void _startEdit(Map<String, dynamic> row) {
    setState(() {
      _editingId = row['id'] as String;
      _status = null;
      _error = null;
    });
    _nameController.text = (row['full_name'] as String?) ?? '';
    _phoneController.text = _formatPhoneDigits((row['phone'] as String?) ?? '');
    _emailController.text = (row['email'] as String?) ?? '';
    _notesController.text = (row['notes'] as String?) ?? '';
    _locationSharingEnabled = row['location_sharing_enabled'] as bool? ?? false;
    _locationSharingAuthorizedAt =
      _parseOptionalDateTime(row['location_sharing_authorized_at']);
    _birthday = _parseBirthday(row['birthday']);
    _preferredContactChannel =
        (row['preferred_contact_channel'] as String?) ?? 'whatsapp';
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
      final normalizedPhone = _normalizePhone(_phoneController.text);
      final authorizedAt = _locationSharingEnabled
          ? (_locationSharingAuthorizedAt ?? DateTime.now())
          : null;
      final payload = <String, dynamic>{
        'tenant_id': _tenantId,
        'full_name': _nameController.text.trim(),
        'phone': normalizedPhone.isEmpty ? null : normalizedPhone,
        'email': _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        'notes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        'birthday': _birthday == null
            ? null
            : '${_birthday!.year.toString().padLeft(4, '0')}-${_birthday!.month.toString().padLeft(2, '0')}-${_birthday!.day.toString().padLeft(2, '0')}',
        'preferred_contact_channel': _preferredContactChannel,
        'location_sharing_enabled': _locationSharingEnabled,
        'location_sharing_authorized_at': authorizedAt == null
            ? null
            : DateTime(
                authorizedAt.year,
                authorizedAt.month,
                authorizedAt.day,
                12,
              ).toUtc().toIso8601String(),
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
      setState(() => _error = _mapClientSchemaError(error, fallback: 'Erro ao salvar cliente: '));
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
      setState(() => _error = _mapClientSchemaError(error, fallback: 'Erro ao remover cliente: '));
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
                          keyboardType: TextInputType.phone,
                          inputFormatters: const [_BrazilPhoneInputFormatter()],
                          decoration: const InputDecoration(labelText: 'WhatsApp'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(labelText: 'E-mail'),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _preferredContactChannel,
                          decoration: const InputDecoration(
                            labelText: 'Canal de contato preferido',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'whatsapp',
                              child: Text('WhatsApp'),
                            ),
                            DropdownMenuItem(
                              value: 'phone',
                              child: Text('Ligação'),
                            ),
                            DropdownMenuItem(
                              value: 'email',
                              child: Text('E-mail'),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _preferredContactChannel = value ?? 'whatsapp';
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _notesController,
                          minLines: 2,
                          maxLines: 3,
                          decoration: const InputDecoration(labelText: 'Observações'),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Aniversário: ${_formatBirthday(_birthday)}',
                              ),
                            ),
                            OutlinedButton(
                              onPressed: _pickBirthday,
                              child: const Text('Selecionar'),
                            ),
                            if (_birthday != null) ...[  
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: 'Limpar aniversário',
                                onPressed: () => setState(() => _birthday = null),
                                icon: const Icon(Icons.clear),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile.adaptive(
                          value: _locationSharingEnabled,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Partilha de localização autorizada'),
                          subtitle: Text(
                            _locationSharingEnabled
                                ? 'Autorizado em ${_formatAuthorizedDate(_locationSharingAuthorizedAt ?? DateTime.now())}'
                                : 'Use para controle e consulta rápida do consentimento',
                          ),
                          onChanged: (value) {
                            setState(() {
                              _locationSharingEnabled = value;
                              if (value) {
                                _locationSharingAuthorizedAt ??= DateTime(
                                  DateTime.now().year,
                                  DateTime.now().month,
                                  DateTime.now().day,
                                  12,
                                );
                              } else {
                                _locationSharingAuthorizedAt = null;
                              }
                            });
                          },
                        ),
                        if (_locationSharingEnabled) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Data da autorização: ${_formatAuthorizedDate(_locationSharingAuthorizedAt ?? DateTime.now())}',
                                ),
                              ),
                              OutlinedButton(
                                onPressed: _pickAuthorizedDate,
                                child: const Text('Selecionar data'),
                              ),
                            ],
                          ),
                        ],
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
                      final subtitle = _buildClientSubtitle(row);
                      return ListTile(
                        title: Text((row['full_name'] as String?) ?? '-'),
                        subtitle: Text(subtitle),
                        isThreeLine: subtitle.contains('\n'),
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

class _BrazilPhoneInputFormatter extends TextInputFormatter {
  const _BrazilPhoneInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');

    if (digits.startsWith('55') && digits.length >= 12) {
      digits = digits.substring(2);
    }
    while (digits.length > 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    if (digits.length > 11) {
      digits = digits.substring(digits.length - 11);
    }

    final formatted = _formatDigits(digits);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  String _formatDigits(String digits) {
    if (digits.isEmpty) return '';
    if (digits.length <= 2) return digits;
    if (digits.length <= 6) return '(${digits.substring(0, 2)}) ${digits.substring(2)}';
    if (digits.length <= 10) {
      return '(${digits.substring(0, 2)}) ${digits.substring(2, 6)}-${digits.substring(6)}';
    }
    return '(${digits.substring(0, 2)}) ${digits.substring(2, 7)}-${digits.substring(7)}';
  }
}
