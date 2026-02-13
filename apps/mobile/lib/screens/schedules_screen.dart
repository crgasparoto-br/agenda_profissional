import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/tenant_service.dart';
import '../theme/app_theme.dart';

class _DayWindow {
  _DayWindow({required this.start, required this.end});

  String start;
  String end;
}

class _ScheduleDraft {
  _ScheduleDraft({
    required this.timezone,
    required this.workdays,
    required this.defaultStart,
    required this.defaultEnd,
    required this.dailyOverrides,
  });

  String timezone;
  Set<int> workdays;
  String defaultStart;
  String defaultEnd;
  Map<int, _DayWindow> dailyOverrides;
}

class _UnavailabilityDraft {
  _UnavailabilityDraft({
    this.id,
    required this.startsAt,
    required this.endsAt,
    required this.reason,
    required this.shareReasonWithClient,
  });

  String? id;
  DateTime startsAt;
  DateTime endsAt;
  String reason;
  bool shareReasonWithClient;
}

class SchedulesScreen extends StatefulWidget {
  const SchedulesScreen({super.key});

  @override
  State<SchedulesScreen> createState() => _SchedulesScreenState();
}

class _SchedulesScreenState extends State<SchedulesScreen> {
  final _tenantService = TenantService();
  final _reasonController = TextEditingController();
  final _timezoneController = TextEditingController(text: 'America/Sao_Paulo');

  bool _loading = true;
  bool _savingSchedule = false;
  bool _savingUnavailability = false;
  String? _tenantId;
  String? _selectedProfessionalId;
  String? _editingUnavailabilityId;
  String? _error;
  String? _status;

  DateTime _unavailabilityStart = _defaultStartDateTime();
  DateTime _unavailabilityEnd = _defaultEndDateTime();
  bool _shareReasonWithClient = false;

  List<Map<String, dynamic>> _professionals = const [];
  Map<String, _ScheduleDraft> _draftByProfessional = {};
  Map<String, List<Map<String, dynamic>>> _unavailabilityByProfessional = {};

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _timezoneController.dispose();
    super.dispose();
  }

  static DateTime _defaultStartDateTime() {
    final base = DateTime.now().add(const Duration(days: 1));
    return DateTime(base.year, base.month, base.day, 9, 0);
  }

  static DateTime _defaultEndDateTime() {
    final base = DateTime.now().add(const Duration(days: 1));
    return DateTime(base.year, base.month, base.day, 10, 0);
  }

  String _weekdayLabel(int day) {
    switch (day) {
      case 0:
        return 'Dom';
      case 1:
        return 'Seg';
      case 2:
        return 'Ter';
      case 3:
        return 'Qua';
      case 4:
        return 'Qui';
      case 5:
        return 'Sex';
      case 6:
        return 'Sáb';
      default:
        return '$day';
    }
  }

  String _formatDateTime(DateTime value) {
    final dd = value.day.toString().padLeft(2, '0');
    final mm = value.month.toString().padLeft(2, '0');
    final yyyy = value.year.toString().padLeft(4, '0');
    final hh = value.hour.toString().padLeft(2, '0');
    final mi = value.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy $hh:$mi';
  }

  _ScheduleDraft _defaultSchedule() {
    return _ScheduleDraft(
      timezone: 'America/Sao_Paulo',
      workdays: {1, 2, 3, 4, 5},
      defaultStart: '09:00',
      defaultEnd: '18:00',
      dailyOverrides: {},
    );
  }

  _UnavailabilityDraft _emptyUnavailabilityDraft() {
    return _UnavailabilityDraft(
      id: null,
      startsAt: _defaultStartDateTime(),
      endsAt: _defaultEndDateTime(),
      reason: '',
      shareReasonWithClient: false,
    );
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _tenantId = await _tenantService.requireTenantId();
      await _load();
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _load() async {
    if (_tenantId == null) return;
    final supabase = Supabase.instance.client;
    final professionals = await supabase
        .from('professionals')
        .select('id, name, active')
        .eq('tenant_id', _tenantId!)
        .order('name');

    final scheduleRows = await supabase
        .from('professional_schedule_settings')
        .select('professional_id, timezone, workdays, work_hours')
        .eq('tenant_id', _tenantId!);

    final unavailabilityRows = await supabase
        .from('professional_unavailability')
        .select('id, professional_id, starts_at, ends_at, reason, share_reason_with_client')
        .eq('tenant_id', _tenantId!)
        .order('starts_at');

    final nextProfessionals = List<Map<String, dynamic>>.from(professionals)
        .where((row) => row['active'] == true)
        .toList();
    final scheduleMap = <String, Map<String, dynamic>>{
      for (final row in List<Map<String, dynamic>>.from(scheduleRows))
        row['professional_id'] as String: row,
    };
    final nextDrafts = <String, _ScheduleDraft>{};
    for (final prof in nextProfessionals) {
      final id = prof['id'] as String;
      final row = scheduleMap[id];
      if (row == null) {
        nextDrafts[id] = _defaultSchedule();
        continue;
      }
      nextDrafts[id] = _parseScheduleRow(row);
    }

    final nextUnavailability = <String, List<Map<String, dynamic>>>{};
    for (final row in List<Map<String, dynamic>>.from(unavailabilityRows)) {
      final professionalId = row['professional_id'] as String;
      final bucket = nextUnavailability.putIfAbsent(professionalId, () => []);
      bucket.add(row);
    }

    if (!mounted) return;
    setState(() {
      _professionals = nextProfessionals;
      _draftByProfessional = nextDrafts;
      _unavailabilityByProfessional = nextUnavailability;
      _selectedProfessionalId = _selectedProfessionalId ??
          (nextProfessionals.isNotEmpty ? nextProfessionals.first['id'] as String : null);
      _applyScheduleToForm();
    });
  }

  _ScheduleDraft _parseScheduleRow(Map<String, dynamic> row) {
    final timezone = (row['timezone'] as String?)?.trim().isNotEmpty == true
        ? row['timezone'] as String
        : 'America/Sao_Paulo';

    final workdaysRaw = row['workdays'];
    final workdays = <int>{};
    if (workdaysRaw is List) {
      for (final item in workdaysRaw) {
        final value = item is int ? item : int.tryParse('$item');
        if (value != null && value >= 0 && value <= 6) {
          workdays.add(value);
        }
      }
    }
    if (workdays.isEmpty) {
      workdays.addAll({1, 2, 3, 4, 5});
    }

    final workHoursRaw = row['work_hours'];
    String defaultStart = '09:00';
    String defaultEnd = '18:00';
    final overrides = <int, _DayWindow>{};

    if (workHoursRaw is Map<String, dynamic>) {
      defaultStart = (workHoursRaw['start'] as String?) ?? defaultStart;
      defaultEnd = (workHoursRaw['end'] as String?) ?? defaultEnd;

      final overrideRaw = workHoursRaw['daily_overrides'];
      if (overrideRaw is Map<String, dynamic>) {
        for (final entry in overrideRaw.entries) {
          final day = int.tryParse(entry.key);
          final item = entry.value;
          if (day == null || day < 0 || day > 6 || item is! Map<String, dynamic>) continue;
          final start = (item['start'] as String?) ?? defaultStart;
          final end = (item['end'] as String?) ?? defaultEnd;
          overrides[day] = _DayWindow(start: start, end: end);
        }
      }
    }

    return _ScheduleDraft(
      timezone: timezone,
      workdays: workdays,
      defaultStart: defaultStart,
      defaultEnd: defaultEnd,
      dailyOverrides: overrides,
    );
  }

  void _applyScheduleToForm() {
    final draft = _currentDraft;
    if (draft == null) return;
    _timezoneController.text = draft.timezone;
  }

  _ScheduleDraft? get _currentDraft {
    if (_selectedProfessionalId == null) return null;
    return _draftByProfessional[_selectedProfessionalId!];
  }

  List<Map<String, dynamic>> get _currentUnavailability {
    if (_selectedProfessionalId == null) return const [];
    return _unavailabilityByProfessional[_selectedProfessionalId!] ?? const [];
  }

  Future<void> _pickTime({
    required String current,
    required void Function(String) onPicked,
  }) async {
    final parts = current.split(':');
    final hour = parts.length >= 2 ? int.tryParse(parts[0]) ?? 9 : 9;
    final minute = parts.length >= 2 ? int.tryParse(parts[1]) ?? 0 : 0;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: minute),
    );
    if (picked == null || !mounted) return;
    onPicked(
      '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
    );
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
    );
    if (time == null || !mounted) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _saveSchedule() async {
    if (_tenantId == null || _selectedProfessionalId == null) return;
    final draft = _currentDraft;
    if (draft == null) return;

    setState(() {
      _savingSchedule = true;
      _error = null;
      _status = null;
    });

    try {
      final payload = {
        'tenant_id': _tenantId,
        'professional_id': _selectedProfessionalId,
        'timezone': _timezoneController.text.trim().isEmpty
            ? 'America/Sao_Paulo'
            : _timezoneController.text.trim(),
        'workdays': draft.workdays.toList()..sort(),
        'work_hours': {
          'start': draft.defaultStart,
          'end': draft.defaultEnd,
          'daily_overrides': {
            for (final entry in draft.dailyOverrides.entries)
              '${entry.key}': {
                'start': entry.value.start,
                'end': entry.value.end,
              }
          }
        },
      };

      await Supabase.instance.client.from('professional_schedule_settings').upsert(
            payload,
            onConflict: 'professional_id',
          );

      setState(() => _status = 'Horário salvo com sucesso.');
      await _load();
    } catch (error) {
      setState(() => _error = 'Erro ao salvar horário: $error');
    } finally {
      if (mounted) setState(() => _savingSchedule = false);
    }
  }

  void _setDefaultTime({String? start, String? end}) {
    final draft = _currentDraft;
    if (draft == null) return;
    setState(() {
      if (start != null) draft.defaultStart = start;
      if (end != null) draft.defaultEnd = end;
    });
  }

  void _toggleWorkday(int weekday, bool selected) {
    final draft = _currentDraft;
    if (draft == null) return;
    setState(() {
      if (selected) {
        draft.workdays.add(weekday);
      } else {
        draft.workdays.remove(weekday);
        draft.dailyOverrides.remove(weekday);
      }
    });
  }

  void _toggleOverride(int weekday, bool selected) {
    final draft = _currentDraft;
    if (draft == null) return;
    setState(() {
      if (selected) {
        draft.dailyOverrides[weekday] =
            _DayWindow(start: draft.defaultStart, end: draft.defaultEnd);
      } else {
        draft.dailyOverrides.remove(weekday);
      }
    });
  }

  void _setOverrideTime(int weekday, {String? start, String? end}) {
    final draft = _currentDraft;
    final override = draft?.dailyOverrides[weekday];
    if (override == null) return;
    setState(() {
      if (start != null) override.start = start;
      if (end != null) override.end = end;
    });
  }

  void _resetUnavailabilityForm() {
    final draft = _emptyUnavailabilityDraft();
    setState(() {
      _editingUnavailabilityId = null;
      _unavailabilityStart = draft.startsAt;
      _unavailabilityEnd = draft.endsAt;
      _shareReasonWithClient = draft.shareReasonWithClient;
      _reasonController.text = draft.reason;
    });
  }

  void _startEditUnavailability(Map<String, dynamic> row) {
    final startsAt = DateTime.tryParse(row['starts_at'] as String? ?? '');
    final endsAt = DateTime.tryParse(row['ends_at'] as String? ?? '');
    if (startsAt == null || endsAt == null) return;
    setState(() {
      _editingUnavailabilityId = row['id'] as String;
      _unavailabilityStart = startsAt.toLocal();
      _unavailabilityEnd = endsAt.toLocal();
      _shareReasonWithClient = row['share_reason_with_client'] == true;
      _reasonController.text = (row['reason'] as String?) ?? '';
    });
  }

  Future<void> _saveUnavailability() async {
    if (_tenantId == null || _selectedProfessionalId == null) return;
    if (!_unavailabilityEnd.isAfter(_unavailabilityStart)) {
      setState(() => _error = 'Período de ausência inválido.');
      return;
    }

    setState(() {
      _savingUnavailability = true;
      _error = null;
      _status = null;
    });

    try {
      final payload = {
        'tenant_id': _tenantId,
        'professional_id': _selectedProfessionalId,
        'starts_at': _unavailabilityStart.toUtc().toIso8601String(),
        'ends_at': _unavailabilityEnd.toUtc().toIso8601String(),
        'reason': _reasonController.text.trim().isEmpty ? null : _reasonController.text.trim(),
        'share_reason_with_client': _shareReasonWithClient,
      };

      if (_editingUnavailabilityId == null) {
        await Supabase.instance.client.from('professional_unavailability').insert(payload);
        setState(() => _status = 'Ausência cadastrada com sucesso.');
      } else {
        await Supabase.instance.client
            .from('professional_unavailability')
            .update(payload)
            .eq('id', _editingUnavailabilityId!);
        setState(() => _status = 'Ausência atualizada com sucesso.');
      }

      _resetUnavailabilityForm();
      await _load();
    } catch (error) {
      setState(() => _error = 'Erro ao salvar ausência: $error');
    } finally {
      if (mounted) setState(() => _savingUnavailability = false);
    }
  }

  Future<void> _deleteUnavailability(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir ausência'),
        content: const Text('Deseja remover este período de ausência?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await Supabase.instance.client.from('professional_unavailability').delete().eq('id', id);
      setState(() => _status = 'Ausência removida com sucesso.');
      if (_editingUnavailabilityId == id) {
        _resetUnavailabilityForm();
      }
      await _load();
    } catch (error) {
      setState(() => _error = 'Erro ao remover ausência: $error');
    }
  }

  Future<void> _setShareReason(String id, bool value) async {
    try {
      await Supabase.instance.client
          .from('professional_unavailability')
          .update({'share_reason_with_client': value}).eq('id', id);
      await _load();
    } catch (error) {
      setState(() => _error = 'Erro ao atualizar flag da ausência: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = _currentDraft;
    return Scaffold(
      appBar: AppBar(title: const Text('Horários')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _professionals.isEmpty
              ? const Center(child: Text('Nenhum profissional ativo cadastrado.'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedProfessionalId,
                          decoration: const InputDecoration(labelText: 'Profissional'),
                          items: _professionals
                              .map(
                                (row) => DropdownMenuItem<String>(
                                  value: row['id'] as String,
                                  child: Text((row['name'] as String?) ?? '-'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedProfessionalId = value;
                              _applyScheduleToForm();
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (draft != null)
                      Card(
                        child: ExpansionTile(
                          initiallyExpanded: true,
                          title: const Text('Configuração de horários'),
                          childrenPadding: const EdgeInsets.all(12),
                          children: [
                            TextField(
                              controller: _timezoneController,
                              decoration: const InputDecoration(labelText: 'Timezone'),
                            ),
                            const SizedBox(height: 12),
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text('Dias de atendimento'),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: List.generate(
                                7,
                                (day) => FilterChip(
                                  label: Text(_weekdayLabel(day)),
                                  selected: draft.workdays.contains(day),
                                  onSelected: (selected) => _toggleWorkday(day, selected),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => _pickTime(
                                      current: draft.defaultStart,
                                      onPicked: (value) => _setDefaultTime(start: value),
                                    ),
                                    child: Text('Início: ${draft.defaultStart}'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => _pickTime(
                                      current: draft.defaultEnd,
                                      onPicked: (value) => _setDefaultTime(end: value),
                                    ),
                                    child: Text('Fim: ${draft.defaultEnd}'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: ElevatedButton(
                                onPressed: _savingSchedule ? null : _saveSchedule,
                                child: Text(
                                  _savingSchedule ? 'Salvando...' : 'Salvar horários',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (draft != null)
                      Card(
                        child: ExpansionTile(
                          title: const Text('Exceções por dia'),
                          childrenPadding: const EdgeInsets.all(12),
                          children: (draft.workdays.toList()..sort()).map((weekday) {
                            final override = draft.dailyOverrides[weekday];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text('Usar exceção em ${_weekdayLabel(weekday)}'),
                                      value: override != null,
                                      onChanged: (value) => _toggleOverride(weekday, value),
                                    ),
                                    if (override != null)
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () => _pickTime(
                                                current: override.start,
                                                onPicked: (value) => _setOverrideTime(weekday, start: value),
                                              ),
                                              child: Text('Início: ${override.start}'),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () => _pickTime(
                                                current: override.end,
                                                onPicked: (value) => _setOverrideTime(weekday, end: value),
                                              ),
                                              child: Text('Fim: ${override.end}'),
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Card(
                      child: ExpansionTile(
                        title: const Text('Ausências programadas'),
                        initiallyExpanded: true,
                        childrenPadding: const EdgeInsets.all(12),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Bloqueia disponibilidade em dias futuros.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () async {
                                    final picked = await _pickDateTime(_unavailabilityStart);
                                    if (picked == null) return;
                                    setState(() => _unavailabilityStart = picked);
                                  },
                                  child: Text('Início: ${_formatDateTime(_unavailabilityStart)}'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () async {
                                    final picked = await _pickDateTime(_unavailabilityEnd);
                                    if (picked == null) return;
                                    setState(() => _unavailabilityEnd = picked);
                                  },
                                  child: Text('Fim: ${_formatDateTime(_unavailabilityEnd)}'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _reasonController,
                            decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _shareReasonWithClient,
                            onChanged: (value) => setState(() => _shareReasonWithClient = value),
                            title: const Text(
                              'Permitir que o bot informe o motivo da ausência ao cliente',
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _savingUnavailability ? null : _saveUnavailability,
                                  child: Text(
                                    _savingUnavailability
                                        ? 'Salvando...'
                                        : _editingUnavailabilityId == null
                                            ? 'Adicionar ausência'
                                            : 'Atualizar ausência',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: _savingUnavailability ? null : _resetUnavailabilityForm,
                                child: const Text('Limpar formulário'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_currentUnavailability.isEmpty)
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text('Nenhuma ausência cadastrada.'),
                            ),
                          ..._currentUnavailability.map(
                            (row) {
                              final startsAt = DateTime.tryParse(row['starts_at'] as String? ?? '');
                              final endsAt = DateTime.tryParse(row['ends_at'] as String? ?? '');
                              final reason = (row['reason'] as String?) ?? '-';
                              final shareReason = row['share_reason_with_client'] == true;
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  startsAt == null || endsAt == null
                                      ? 'Período inválido'
                                      : '${_formatDateTime(startsAt.toLocal())} até ${_formatDateTime(endsAt.toLocal())}',
                                ),
                                subtitle: Text('Motivo: $reason'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Tooltip(
                                      message: 'Bot pode informar motivo',
                                      child: Checkbox(
                                        value: shareReason,
                                        onChanged: (value) {
                                          if (value == null) return;
                                          _setShareReason(row['id'] as String, value);
                                        },
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () => _startEditUnavailability(row),
                                      icon: const Icon(Icons.edit_outlined),
                                      tooltip: 'Editar',
                                    ),
                                    IconButton(
                                      onPressed: () => _deleteUnavailability(row['id'] as String),
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
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: const TextStyle(color: AppColors.danger)),
                    ],
                    if (_status != null) ...[
                      const SizedBox(height: 8),
                      Text(_status!, style: const TextStyle(color: AppColors.secondary)),
                    ],
                  ],
                ),
    );
  }
}
