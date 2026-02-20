import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';

class PunctualityAuditScreen extends StatefulWidget {
  const PunctualityAuditScreen({super.key});

  @override
  State<PunctualityAuditScreen> createState() => _PunctualityAuditScreenState();
}

class _PunctualityAuditScreenState extends State<PunctualityAuditScreen> {
  final _appointmentIdController = TextEditingController();

  bool _loadingMetrics = false;
  bool _loadingInvestigation = false;
  bool _savingConsentAction = false;
  String? _error;
  String? _investigationError;

  Map<String, int> _metrics = {
    'push_sent': 0,
    'push_failed': 0,
    'whatsapp_sent': 0,
    'whatsapp_failed': 0,
    'in_app_read': 0,
    'eta_snapshots': 0,
    'eta_with_data': 0,
    'eta_provider_failed': 0,
    'late_ok_events': 0,
    'late_critical_events': 0,
  };

  Map<String, dynamic>? _appointment;
  List<Map<String, dynamic>> _snapshots = [];
  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _notifications = [];
  List<Map<String, dynamic>> _consents = [];

  @override
  void initState() {
    super.initState();
    _loadMetrics();
  }

  @override
  void dispose() {
    _appointmentIdController.dispose();
    super.dispose();
  }

  String _fmtDateTime(String? iso) {
    if (iso == null || iso.isEmpty) return '-';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '-';
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '$dd/$mm $hh:$mi';
  }

  String _statusLabel(String? value) {
    final normalized = (value ?? '').toLowerCase();
    if (normalized == 'scheduled') return 'Agendado';
    if (normalized == 'confirmed') return 'Confirmado';
    if (normalized == 'cancelled') return 'Cancelado';
    if (normalized == 'done') return 'Concluido';
    if (normalized == 'rescheduled') return 'Remarcado';
    if (normalized == 'no_show') return 'Nao compareceu';
    return value ?? '-';
  }

  String _punctualityLabel(String? value) {
    final normalized = (value ?? 'no_data').toLowerCase();
    if (normalized == 'on_time') return 'No horario';
    if (normalized == 'late_ok') return 'Atraso leve';
    if (normalized == 'late_critical') return 'Atraso critico';
    return 'Sem dados';
  }

  String _notificationChannelLabel(String? value) {
    final normalized = (value ?? '').toLowerCase();
    if (normalized == 'in_app') return 'No app';
    if (normalized == 'push') return 'Push';
    if (normalized == 'whatsapp') return 'WhatsApp';
    return 'SMS';
  }

  String _notificationStatusLabel(String? value) {
    final normalized = (value ?? '').toLowerCase();
    if (normalized == 'queued') return 'Na fila';
    if (normalized == 'sent') return 'Enviado';
    if (normalized == 'failed') return 'Falha';
    if (normalized == 'read') return 'Lido';
    return value ?? '-';
  }

  String _notificationTypeLabel(String? value) {
    final normalized = (value ?? '').toLowerCase();
    if (normalized == 'punctuality_on_time') return 'Pontualidade: no horario';
    if (normalized == 'punctuality_late_ok') return 'Pontualidade: atraso leve';
    if (normalized == 'punctuality_late_critical') {
      return 'Pontualidade: atraso critico';
    }
    return value ?? '-';
  }

  String _consentStatusLabel(String? value) {
    final normalized = (value ?? '').toLowerCase();
    if (normalized == 'granted') return 'Concedido';
    if (normalized == 'denied') return 'Negado';
    if (normalized == 'revoked') return 'Revogado';
    if (normalized == 'expired') return 'Expirado';
    return value ?? '-';
  }

  Future<void> _loadMetrics() async {
    setState(() {
      _loadingMetrics = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;
      final metricsStart = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 7))
          .toIso8601String();

      final notifications = await client
          .from('notification_log')
          .select('channel, status, type')
          .inFilter('channel', ['in_app', 'push', 'whatsapp']).inFilter(
              'type', [
        'punctuality_on_time',
        'punctuality_late_ok',
        'punctuality_late_critical',
      ]).gte('created_at', metricsStart);

      final events = await client
          .from('punctuality_events')
          .select('new_status')
          .gte('occurred_at', metricsStart);

      final snapshots = await client
          .from('appointment_eta_snapshots')
          .select('provider, eta_minutes')
          .gte('captured_at', metricsStart);

      final next = <String, int>{
        'push_sent': 0,
        'push_failed': 0,
        'whatsapp_sent': 0,
        'whatsapp_failed': 0,
        'in_app_read': 0,
        'eta_snapshots': 0,
        'eta_with_data': 0,
        'eta_provider_failed': 0,
        'late_ok_events': 0,
        'late_critical_events': 0,
      };

      for (final row in List<Map<String, dynamic>>.from(notifications)) {
        final channel = (row['channel'] as String?)?.toLowerCase() ?? '';
        final status = (row['status'] as String?)?.toLowerCase() ?? '';
        if (channel == 'push' && status == 'sent') {
          next['push_sent'] = next['push_sent']! + 1;
        }
        if (channel == 'push' && status == 'failed') {
          next['push_failed'] = next['push_failed']! + 1;
        }
        if (channel == 'whatsapp' && status == 'sent') {
          next['whatsapp_sent'] = next['whatsapp_sent']! + 1;
        }
        if (channel == 'whatsapp' && status == 'failed') {
          next['whatsapp_failed'] = next['whatsapp_failed']! + 1;
        }
        if (channel == 'in_app' && status == 'read') {
          next['in_app_read'] = next['in_app_read']! + 1;
        }
      }

      for (final row in List<Map<String, dynamic>>.from(events)) {
        final status = (row['new_status'] as String?)?.toLowerCase() ?? '';
        if (status == 'late_ok') {
          next['late_ok_events'] = next['late_ok_events']! + 1;
        }
        if (status == 'late_critical') {
          next['late_critical_events'] = next['late_critical_events']! + 1;
        }
      }

      for (final row in List<Map<String, dynamic>>.from(snapshots)) {
        next['eta_snapshots'] = next['eta_snapshots']! + 1;
        if (row['eta_minutes'] != null) {
          next['eta_with_data'] = next['eta_with_data']! + 1;
        }
        final provider = (row['provider'] as String?)?.toLowerCase() ?? '';
        if (provider.endsWith('_failed')) {
          next['eta_provider_failed'] = next['eta_provider_failed']! + 1;
        }
      }

      if (!mounted) return;
      setState(() => _metrics = next);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Erro ao carregar metricas: $error');
    } finally {
      if (mounted) setState(() => _loadingMetrics = false);
    }
  }

  Future<void> _investigate() async {
    final appointmentId = _appointmentIdController.text.trim();
    if (appointmentId.isEmpty) {
      setState(() => _investigationError = 'Informe o ID do agendamento.');
      return;
    }

    setState(() {
      _loadingInvestigation = true;
      _investigationError = null;
      _appointment = null;
      _snapshots = [];
      _events = [];
      _notifications = [];
      _consents = [];
    });

    try {
      final client = Supabase.instance.client;
      final appointment = await client
          .from('appointments')
          .select(
              'id, starts_at, status, punctuality_status, clients(full_name), professionals(name), services(name)')
          .eq('id', appointmentId)
          .maybeSingle();

      if (appointment == null) {
        if (!mounted) return;
        setState(
            () => _investigationError = 'ID do agendamento nao encontrado.');
        return;
      }

      final snapshots = await client
          .from('appointment_eta_snapshots')
          .select(
              'id, captured_at, status, eta_minutes, predicted_arrival_delay, provider, traffic_level')
          .eq('appointment_id', appointmentId)
          .order('captured_at', ascending: false)
          .limit(15);

      final events = await client
          .from('punctuality_events')
          .select(
              'id, occurred_at, old_status, new_status, predicted_arrival_delay, source')
          .eq('appointment_id', appointmentId)
          .order('occurred_at', ascending: false)
          .limit(15);

      final notifications = await client
          .from('notification_log')
          .select('id, channel, type, status, created_at, provider_message_id')
          .eq('appointment_id', appointmentId)
          .order('created_at', ascending: false)
          .limit(20);

      final consents = await client
          .from('client_location_consents')
          .select(
              'id, consent_status, consent_text_version, source_channel, granted_at, expires_at, updated_at')
          .eq('appointment_id', appointmentId)
          .order('updated_at', ascending: false)
          .limit(20);

      if (!mounted) return;
      setState(() {
        _appointment = Map<String, dynamic>.from(appointment);
        _snapshots = List<Map<String, dynamic>>.from(snapshots);
        _events = List<Map<String, dynamic>>.from(events);
        _notifications = List<Map<String, dynamic>>.from(notifications);
        _consents = List<Map<String, dynamic>>.from(consents);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _investigationError = 'Erro na investigacao: $error');
    } finally {
      if (mounted) setState(() => _loadingInvestigation = false);
    }
  }

  Future<void> _revokeConsent(String consentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revogar consentimento'),
        content:
            const Text('Deseja revogar este consentimento de localizacao?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revogar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _savingConsentAction = true);
    try {
      final nowIso = DateTime.now().toUtc().toIso8601String();
      await Supabase.instance.client.from('client_location_consents').update({
        'consent_status': 'revoked',
        'expires_at': nowIso,
        'source_channel': 'mobile_app',
        'updated_at': nowIso,
      }).eq('id', consentId);

      await _investigate();
    } catch (error) {
      if (!mounted) return;
      setState(
          () => _investigationError = 'Erro ao revogar consentimento: $error');
    } finally {
      if (mounted) setState(() => _savingConsentAction = false);
    }
  }

  Widget _metricTile(String title, int value) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: const Color(0xFFD7DDE4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            '$value',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pushAttempted = _metrics['push_sent']! + _metrics['push_failed']!;
    final pushRate = pushAttempted == 0
        ? 0
        : ((_metrics['push_sent']! * 100) / pushAttempted).round();
    final whatsAttempted =
        _metrics['whatsapp_sent']! + _metrics['whatsapp_failed']!;
    final whatsRate = whatsAttempted == 0
        ? 0
        : ((_metrics['whatsapp_sent']! * 100) / whatsAttempted).round();
    final etaRate = _metrics['eta_snapshots'] == 0
        ? 0
        : ((_metrics['eta_with_data']! * 100) / _metrics['eta_snapshots']!)
            .round();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Auditoria de Pontualidade'),
        actions: [
          IconButton(
            onPressed: _loadingMetrics ? null : _loadMetrics,
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar metricas',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Metricas operacionais (7 dias)',
                      style: Theme.of(context).textTheme.titleMedium),
                  if (_loadingMetrics) ...[
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(minHeight: 2),
                  ],
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1.8,
                    children: [
                      _metricTile(
                          'Notificacoes push enviadas', _metrics['push_sent']!),
                      _metricTile('Falhas em push', _metrics['push_failed']!),
                      _metricTile('Taxa entrega push (%)', pushRate),
                      _metricTile(
                          'WhatsApp enviados', _metrics['whatsapp_sent']!),
                      _metricTile(
                          'WhatsApp com falha', _metrics['whatsapp_failed']!),
                      _metricTile('Taxa entrega WhatsApp (%)', whatsRate),
                      _metricTile('Lidos no app', _metrics['in_app_read']!),
                      _metricTile(
                          'Registros de ETA', _metrics['eta_snapshots']!),
                      _metricTile('Precisao ETA (%)', etaRate),
                      _metricTile('Falhas provedor ETA',
                          _metrics['eta_provider_failed']!),
                      _metricTile(
                          'Eventos atraso leve', _metrics['late_ok_events']!),
                      _metricTile('Eventos atraso critico',
                          _metrics['late_critical_events']!),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Precisao ETA (indicador): percentual de registros com ETA calculado no periodo.',
                    style: TextStyle(color: Color(0xFF66717F)),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'ETA significa Tempo Estimado de Chegada.',
                    style: TextStyle(color: Color(0xFF66717F)),
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
                  Text('Investigacao por ID do agendamento',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _appointmentIdController,
                    decoration: const InputDecoration(
                      labelText: 'ID do agendamento',
                      hintText: 'Informe o UUID do agendamento',
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _loadingInvestigation ? null : _investigate,
                    icon: const Icon(Icons.search),
                    label: Text(_loadingInvestigation
                        ? 'Investigando...'
                        : 'Investigar'),
                  ),
                  if (_investigationError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _investigationError!,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ],
                  if (_appointment != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Cliente: ${(_appointment!['clients'] as Map<String, dynamic>?)?['full_name'] ?? 'Cliente nao identificado'}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                        'Profissional: ${(_appointment!['professionals'] as Map<String, dynamic>?)?['name'] ?? '-'}'),
                    Text(
                        'Servico: ${(_appointment!['services'] as Map<String, dynamic>?)?['name'] ?? '-'}'),
                    Text(
                        'Data/Hora: ${_fmtDateTime(_appointment!['starts_at'] as String?)}'),
                    Text(
                        'Status agenda: ${_statusLabel(_appointment!['status'] as String?)}'),
                    Text(
                        'Pontualidade: ${_punctualityLabel(_appointment!['punctuality_status'] as String?)}'),
                    const SizedBox(height: 10),
                    ExpansionTile(
                      title: Text('Registros de ETA (${_snapshots.length})'),
                      children: _snapshots.isEmpty
                          ? const [
                              ListTile(
                                title: Text(
                                    'Sem registros de ETA para este agendamento.'),
                              )
                            ]
                          : _snapshots
                              .map(
                                (row) => ListTile(
                                  dense: true,
                                  title: Text(_fmtDateTime(
                                      row['captured_at'] as String?)),
                                  subtitle: Text(
                                    '${_punctualityLabel(row['status'] as String?)} • ETA ${row['eta_minutes'] ?? '-'} min • atraso ${row['predicted_arrival_delay'] ?? '-'} min',
                                  ),
                                  trailing:
                                      Text((row['provider'] ?? '-') as String),
                                ),
                              )
                              .toList(),
                    ),
                    ExpansionTile(
                      title: Text('Eventos (${_events.length})'),
                      children: _events.isEmpty
                          ? const [
                              ListTile(
                                title: Text(
                                    'Sem eventos de pontualidade para este agendamento.'),
                              )
                            ]
                          : _events
                              .map(
                                (row) => ListTile(
                                  dense: true,
                                  title: Text(_fmtDateTime(
                                      row['occurred_at'] as String?)),
                                  subtitle: Text(
                                    '${_punctualityLabel(row['old_status'] as String?)} -> ${_punctualityLabel(row['new_status'] as String?)} • atraso ${row['predicted_arrival_delay'] ?? '-'} min',
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                    ExpansionTile(
                      title: Text('Notificacoes (${_notifications.length})'),
                      children: _notifications.isEmpty
                          ? const [
                              ListTile(
                                title: Text(
                                    'Sem notificacoes para este agendamento.'),
                              )
                            ]
                          : _notifications
                              .map(
                                (row) => ListTile(
                                  dense: true,
                                  title: Text(_fmtDateTime(
                                      row['created_at'] as String?)),
                                  subtitle: Text(
                                    '${_notificationChannelLabel(row['channel'] as String?)} • ${_notificationTypeLabel(row['type'] as String?)} • ${_notificationStatusLabel(row['status'] as String?)}',
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                    ExpansionTile(
                      title: Text('Consentimentos (${_consents.length})'),
                      children: _consents.isEmpty
                          ? const [
                              ListTile(
                                title: Text(
                                    'Sem registros de consentimento para este agendamento.'),
                              )
                            ]
                          : _consents
                              .map(
                                (row) => ListTile(
                                  dense: true,
                                  title: Text(_fmtDateTime(
                                      row['updated_at'] as String?)),
                                  subtitle: Text(
                                    '${_consentStatusLabel(row['consent_status'] as String?)} • versao ${row['consent_text_version'] ?? '-'} • canal ${row['source_channel'] ?? '-'}',
                                  ),
                                  trailing: (row['consent_status'] as String?)
                                              ?.toLowerCase() ==
                                          'granted'
                                      ? OutlinedButton(
                                          onPressed: _savingConsentAction
                                              ? null
                                              : () => _revokeConsent(
                                                  row['id'] as String),
                                          child: const Text('Revogar'),
                                        )
                                      : null,
                                ),
                              )
                              .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
          ],
        ],
      ),
    );
  }
}
