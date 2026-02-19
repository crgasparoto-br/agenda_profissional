import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/app_exception.dart';
import '../models/appointment.dart';
import '../models/option_item.dart';
import '../services/appointment_service.dart';
import '../services/catalog_service.dart';
import '../theme/app_theme.dart';

class CreateAppointmentScreen extends StatefulWidget {
  const CreateAppointmentScreen({super.key});

  @override
  State<CreateAppointmentScreen> createState() =>
      _CreateAppointmentScreenState();
}

class _CreateAppointmentScreenState extends State<CreateAppointmentScreen> {
  final _catalogService = CatalogService();
  final _appointmentService = AppointmentService();

  bool _loading = false;
  String? _error;
  String? _status;

  List<ServiceCatalogItem> _services = [];
  List<OptionItem> _professionals = [];
  List<OptionItem> _clients = [];
  Map<String, String> _timezoneByProfessional = {};

  String? _serviceId;
  String? _professionalId;
  String? _clientId;
  final _clientNameController = TextEditingController();
  final _clientPhoneController = TextEditingController();
  bool _anyAvailable = true;
  DateTime _start = DateTime.now().add(const Duration(hours: 1));

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

  String? _textOrNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  @override
  void dispose() {
    _clientNameController.dispose();
    _clientPhoneController.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    final services = await _catalogService.listServiceCatalog();
    final professionals = await _catalogService.listProfessionals();
    final clients = await _catalogService.listClients();
    final timezoneByProfessional =
        await _appointmentService.getProfessionalTimezones(professionals.map((item) => item.id).toList());

    setState(() {
      _services = services;
      _professionals = professionals;
      _clients = clients;
      _timezoneByProfessional = timezoneByProfessional;
    });
  }

  ServiceCatalogItem? _selectedService() {
    if (_serviceId == null || _serviceId!.isEmpty) return null;
    for (final item in _services) {
      if (item.id == _serviceId) return item;
    }
    return null;
  }

  DateTime _resolvedEndDateTime() {
    final service = _selectedService();
    if (service == null) {
      return _start.add(const Duration(minutes: 30));
    }
    return _start.add(Duration(minutes: service.durationMin + service.intervalMin));
  }

  Future<void> _submit() async {
    if (_serviceId == null) {
      setState(() => _error = 'Selecione um servico');
      return;
    }

    if (!_anyAvailable && _professionalId == null) {
      setState(() => _error = 'Selecione um profissional');
      return;
    }

    if (_clientId == null && _clientPhoneController.text.trim().isEmpty) {
      setState(() => _error = 'Informe o WhatsApp do cliente');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _status = null;
    });

    try {
      await _appointmentService.createAppointment(
        CreateAppointmentInput(
          clientId: _clientId,
          clientName: _clientId == null
              ? _textOrNull(_clientNameController.text)
              : null,
          clientPhone: _clientId == null
              ? _textOrNull(_normalizePhone(_clientPhoneController.text))
              : null,
          serviceId: _serviceId!,
          startsAt: _start,
          endsAt: _resolvedEndDateTime(),
          professionalId: _anyAvailable ? null : _professionalId,
          anyAvailable: _anyAvailable,
        ),
      );

      setState(() => _status = 'Agendamento criado com sucesso');
    } on AppException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Erro ao criar agendamento');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickDateTime() async {
    final initial = _start;
    final timezone = _effectiveTimezone();
    final location = _resolveLocation(timezone);
    final nowInTimezone = tz.TZDateTime.from(DateTime.now().toUtc(), location);
    final initialInTimezone = tz.TZDateTime.from(initial.toUtc(), location);

    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(
        initialInTimezone.year,
        initialInTimezone.month,
        initialInTimezone.day,
      ),
      firstDate: DateTime(
        nowInTimezone.year,
        nowInTimezone.month,
        nowInTimezone.day,
      ).subtract(const Duration(days: 1)),
      lastDate: DateTime(
        nowInTimezone.year,
        nowInTimezone.month,
        nowInTimezone.day,
      ).add(const Duration(days: 365)),
    );

    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: initialInTimezone.hour,
        minute: initialInTimezone.minute,
      ),
    );

    if (time == null) return;

    final selectedInTimezone = tz.TZDateTime(
      location,
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    final dt = selectedInTimezone.toUtc();
    setState(() {
      _start = dt;
    });
  }

  tz.Location _resolveLocation(String timezone) {
    try {
      return tz.getLocation(timezone);
    } catch (_) {
      return tz.getLocation('America/Sao_Paulo');
    }
  }

  String _effectiveTimezone() {
    if (!_anyAvailable && _professionalId != null) {
      return _timezoneByProfessional[_professionalId!] ?? 'America/Sao_Paulo';
    }
    return 'America/Sao_Paulo';
  }

  String _formatDateTime(DateTime value, String timezone) {
    final local = tz.TZDateTime.from(value.toUtc(), _resolveLocation(timezone));
    final yyyy = local.year.toString().padLeft(4, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mi = local.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy $hh:$mi';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Novo agendamento')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Criar agendamento',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  const Text(
                      'Defina servico, horario e profissional com clareza.'),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _serviceId,
                    decoration: const InputDecoration(labelText: 'Servico'),
                    items: _services.map((item) {
                      final label = '${item.name} (${item.durationMin}m + ${item.intervalMin}m intervalo)';
                      return DropdownMenuItem(value: item.id, child: Text(label));
                    }).toList(),
                    onChanged: (value) => setState(() => _serviceId = value),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: _clientId,
                    decoration:
                        const InputDecoration(labelText: 'Cliente (opcional)'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Novo cliente (via WhatsApp)'),
                      ),
                      ..._clients.map(
                        (item) => DropdownMenuItem<String?>(
                            value: item.id, child: Text(item.label)),
                      ),
                    ],
                    onChanged: (value) => setState(() => _clientId = value),
                  ),
                  if (_clientId == null) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _clientNameController,
                      decoration: const InputDecoration(
                          labelText: 'Nome do cliente (opcional)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _clientPhoneController,
                      keyboardType: TextInputType.phone,
                      inputFormatters: const [_BrazilPhoneInputFormatter()],
                      decoration: const InputDecoration(
                          labelText: 'WhatsApp do cliente'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Qualquer profissional disponivel'),
                    contentPadding: EdgeInsets.zero,
                    value: _anyAvailable,
                    onChanged: (value) => setState(() => _anyAvailable = value),
                  ),
                  if (!_anyAvailable) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _professionalId,
                      decoration:
                          const InputDecoration(labelText: 'Profissional'),
                      items: _professionals
                          .map((item) => DropdownMenuItem(
                              value: item.id, child: Text(item.label)))
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _professionalId = value),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Builder(builder: (_) {
                    final timezone = _effectiveTimezone();
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Fuso: $timezone', style: Theme.of(context).textTheme.bodySmall),
                    );
                  }),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Inicio'),
                    subtitle: Text(_formatDateTime(_start, _effectiveTimezone())),
                    trailing: IconButton(
                      onPressed: _pickDateTime,
                      icon: const Icon(Icons.event),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fim de bloqueio'),
                    subtitle: Text(_formatDateTime(_resolvedEndDateTime(), _effectiveTimezone())),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    child: Text(_loading ? 'Salvando...' : 'Criar agendamento'),
                  ),
                  if (_status != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        border: Border.all(
                            color: AppColors.secondary.withValues(alpha: 0.35)),
                      ),
                      child: Text(_status!,
                          style: const TextStyle(color: Color(0xFF0F4D50))),
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
                            color: AppColors.danger.withValues(alpha: 0.35)),
                      ),
                      child: Text(_error!,
                          style: const TextStyle(color: Color(0xFF702621))),
                    ),
                  ],
                ],
              ),
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
