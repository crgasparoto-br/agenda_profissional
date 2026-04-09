import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/tenant_service.dart';
import '../theme/app_theme.dart';

class _BreakDraft {
  _BreakDraft({required this.enabled, required this.start, required this.end});

  bool enabled;
  String start;
  String end;

  _BreakDraft copyWith({bool? enabled, String? start, String? end}) {
    return _BreakDraft(
      enabled: enabled ?? this.enabled,
      start: start ?? this.start,
      end: end ?? this.end,
    );
  }
}

class _DayRuleDraft {
  _DayRuleDraft({
    required this.start,
    required this.end,
    required this.lunchBreak,
    required this.pauseBreak,
  });

  String start;
  String end;
  _BreakDraft lunchBreak;
  _BreakDraft pauseBreak;

  _DayRuleDraft copyWith({
    String? start,
    String? end,
    _BreakDraft? lunchBreak,
    _BreakDraft? pauseBreak,
  }) {
    return _DayRuleDraft(
      start: start ?? this.start,
      end: end ?? this.end,
      lunchBreak: lunchBreak ?? this.lunchBreak,
      pauseBreak: pauseBreak ?? this.pauseBreak,
    );
  }
}

class _ScheduleDraft {
  _ScheduleDraft({
    required this.timezone,
    required this.workdays,
    required this.defaultRule,
    required this.dailyOverrides,
  });

  String timezone;
  Set<int> workdays;
  _DayRuleDraft defaultRule;
  Map<int, _DayRuleDraft> dailyOverrides;
}

class _DelayPolicyDraft {
  _DelayPolicyDraft({
    required this.tempoMaximoAtrasoMin,
    required this.janelaAvisoAntesConsultaMin,
    required this.monitorIntervalMin,
    required this.fallbackWhatsappForProfessional,
  });

  int tempoMaximoAtrasoMin;
  int janelaAvisoAntesConsultaMin;
  int monitorIntervalMin;
  bool fallbackWhatsappForProfessional;
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
  bool _savingDelayPolicy = false;
  bool _savingUnavailability = false;
  bool _showOnlyShareable = false;
  String? _tenantId;
  String? _selectedProfessionalId;
  String? _error;
  String? _status;

  DateTime _unavailabilityStart = _defaultStartDateTime();
  DateTime _unavailabilityEnd = _defaultEndDateTime();
  bool _shareReasonWithClient = false;

  List<Map<String, dynamic>> _professionals = const [];
  Map<String, _ScheduleDraft> _draftByProfessional = {};
  Map<String, _DelayPolicyDraft> _delayPolicyByProfessional = {};
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

  _BreakDraft _defaultLunchBreak() =>
      _BreakDraft(enabled: false, start: '12:00', end: '13:00');

  _BreakDraft _defaultPauseBreak() =>
      _BreakDraft(enabled: false, start: '16:00', end: '16:15');

  _DayRuleDraft _defaultRule() {
    return _DayRuleDraft(
      start: '09:00',
      end: '18:00',
      lunchBreak: _defaultLunchBreak(),
      pauseBreak: _defaultPauseBreak(),
    );
  }

  _ScheduleDraft _defaultSchedule() {
    return _ScheduleDraft(
      timezone: 'America/Sao_Paulo',
      workdays: {1, 2, 3, 4, 5},
      defaultRule: _defaultRule(),
      dailyOverrides: {},
    );
  }

  _DelayPolicyDraft _defaultDelayPolicy() {
    return _DelayPolicyDraft(
      tempoMaximoAtrasoMin: 10,
      janelaAvisoAntesConsultaMin: 90,
      monitorIntervalMin: 5,
      fallbackWhatsappForProfessional: false,
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
    final results = await Future.wait([
      supabase
          .from('professionals')
          .select('id, name, active')
          .eq('tenant_id', _tenantId!)
          .order('name'),
      supabase
          .from('professional_schedule_settings')
          .select('professional_id, timezone, workdays, work_hours')
          .eq('tenant_id', _tenantId!),
      supabase
          .from('delay_policies')
          .select(
              'professional_id, tempo_maximo_atraso_min, janela_aviso_antes_consulta_min, monitor_interval_min, fallback_whatsapp_for_professional')
          .eq('tenant_id', _tenantId!),
      supabase
          .from('professional_unavailability')
          .select(
              'id, professional_id, starts_at, ends_at, reason, share_reason_with_client')
          .eq('tenant_id', _tenantId!)
          .order('starts_at'),
    ]);

    final professionals = List<Map<String, dynamic>>.from(results[0] as List);
    final scheduleRows = List<Map<String, dynamic>>.from(results[1] as List);
    final delayRows = List<Map<String, dynamic>>.from(results[2] as List);
    final unavailabilityRows =
        List<Map<String, dynamic>>.from(results[3] as List);

    final scheduleMap = <String, Map<String, dynamic>>{
      for (final row in scheduleRows) row['professional_id'] as String: row,
    };

    Map<String, dynamic>? tenantDelayPolicy;
    final delayPolicyMap = <String, Map<String, dynamic>>{};
    for (final row in delayRows) {
      final professionalId = row['professional_id'] as String?;
      if (professionalId == null) {
        tenantDelayPolicy = row;
      } else {
        delayPolicyMap[professionalId] = row;
      }
    }

    final nextDrafts = <String, _ScheduleDraft>{};
    final nextDelayPolicies = <String, _DelayPolicyDraft>{};
    for (final professional in professionals) {
      final professionalId = professional['id'] as String;
      final schedule = scheduleMap[professionalId];
      nextDrafts[professionalId] =
          schedule == null ? _defaultSchedule() : _parseScheduleRow(schedule);

      final policy = delayPolicyMap[professionalId] ?? tenantDelayPolicy;
      final fallback = _defaultDelayPolicy();
      nextDelayPolicies[professionalId] = _DelayPolicyDraft(
        tempoMaximoAtrasoMin:
            (policy?['tempo_maximo_atraso_min'] as num?)?.toInt() ??
                fallback.tempoMaximoAtrasoMin,
        janelaAvisoAntesConsultaMin:
            (policy?['janela_aviso_antes_consulta_min'] as num?)?.toInt() ??
                fallback.janelaAvisoAntesConsultaMin,
        monitorIntervalMin:
            (policy?['monitor_interval_min'] as num?)?.toInt() ??
                fallback.monitorIntervalMin,
        fallbackWhatsappForProfessional:
            policy?['fallback_whatsapp_for_professional'] == true,
      );
    }

    final nextUnavailability = <String, List<Map<String, dynamic>>>{};
    for (final row in unavailabilityRows) {
      final professionalId = row['professional_id'] as String;
      final bucket = nextUnavailability.putIfAbsent(professionalId, () => []);
      bucket.add(row);
    }

    if (!mounted) return;
    setState(() {
      _professionals = professionals;
      _draftByProfessional = nextDrafts;
      _delayPolicyByProfessional = nextDelayPolicies;
      _unavailabilityByProfessional = nextUnavailability;
      _selectedProfessionalId = _selectedProfessionalId ??
          (professionals.isNotEmpty
              ? professionals.first['id'] as String
              : null);
      _applyCurrentDraftToForm();
    });
  }

  _ScheduleDraft _parseScheduleRow(Map<String, dynamic> row) {
    final timezone = (row['timezone'] as String?)?.trim().isNotEmpty == true
        ? row['timezone'] as String
        : 'America/Sao_Paulo';

    final workdays = <int>{};
    final rawWorkdays = row['workdays'];
    if (rawWorkdays is List) {
      for (final item in rawWorkdays) {
        final value = item is int ? item : int.tryParse('$item');
        if (value != null && value >= 0 && value <= 6) {
          workdays.add(value);
        }
      }
    }
    if (workdays.isEmpty) {
      workdays.addAll({1, 2, 3, 4, 5});
    }

    final workHours = row['work_hours'];
    final defaultRule = _parseDayRule(workHours, _defaultRule());
    final overrides = <int, _DayRuleDraft>{};

    if (workHours is Map<String, dynamic>) {
      final rawOverrides = workHours['daily_overrides'];
      if (rawOverrides is Map<String, dynamic>) {
        for (final entry in rawOverrides.entries) {
          final weekday = int.tryParse(entry.key);
          if (weekday == null || weekday < 0 || weekday > 6) continue;
          overrides[weekday] = _parseDayRule(entry.value, defaultRule);
        }
      }
    }

    return _ScheduleDraft(
      timezone: timezone,
      workdays: workdays,
      defaultRule: defaultRule,
      dailyOverrides: overrides,
    );
  }

  _DayRuleDraft _parseDayRule(dynamic raw, _DayRuleDraft fallback) {
    if (raw is! Map<String, dynamic>) return fallback;
    return _DayRuleDraft(
      start: (raw['start'] as String?) ?? fallback.start,
      end: (raw['end'] as String?) ?? fallback.end,
      lunchBreak: _parseBreak(raw['lunch_break'], fallback.lunchBreak),
      pauseBreak: _parseBreak(raw['snack_break'], fallback.pauseBreak),
    );
  }

  _BreakDraft _parseBreak(dynamic raw, _BreakDraft fallback) {
    if (raw is! Map<String, dynamic>) return fallback;
    return _BreakDraft(
      enabled: raw['enabled'] == true,
      start: (raw['start'] as String?) ?? fallback.start,
      end: (raw['end'] as String?) ?? fallback.end,
    );
  }

  void _applyCurrentDraftToForm() {
    final draft = _currentDraft;
    if (draft == null) return;
    _timezoneController.text = draft.timezone;
    _resetUnavailabilityForm();
  }

  _ScheduleDraft? get _currentDraft {
    if (_selectedProfessionalId == null) return null;
    return _draftByProfessional[_selectedProfessionalId!];
  }

  _DelayPolicyDraft? get _currentDelayPolicy {
    if (_selectedProfessionalId == null) return null;
    return _delayPolicyByProfessional[_selectedProfessionalId!];
  }

  List<Map<String, dynamic>> get _currentUnavailability {
    if (_selectedProfessionalId == null) return const [];
    final items =
        _unavailabilityByProfessional[_selectedProfessionalId!] ?? const [];
    if (!_showOnlyShareable) return items;
    return items
        .where((item) => item['share_reason_with_client'] == true)
        .toList();
  }

  int? _toMinutes(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return hour * 60 + minute;
  }

  String? _validateDayRule(_DayRuleDraft rule, String label) {
    final start = _toMinutes(rule.start);
    final end = _toMinutes(rule.end);
    if (start == null || end == null || start >= end) {
      return 'Janela de atendimento inválida em $label.';
    }

    String? validateBreak(_BreakDraft draft, String breakLabel) {
      if (!draft.enabled) return null;
      final breakStart = _toMinutes(draft.start);
      final breakEnd = _toMinutes(draft.end);
      if (breakStart == null || breakEnd == null || breakStart >= breakEnd) {
        return '$breakLabel inválido em $label.';
      }
      if (breakStart < start || breakEnd > end) {
        return '$breakLabel precisa ficar dentro do horário de atendimento em $label.';
      }
      return null;
    }

    final lunchError = validateBreak(rule.lunchBreak, 'Intervalo de almoço');
    if (lunchError != null) return lunchError;
    final pauseError = validateBreak(rule.pauseBreak, 'Pausa');
    if (pauseError != null) return pauseError;

    if (rule.lunchBreak.enabled && rule.pauseBreak.enabled) {
      final lunchStart = _toMinutes(rule.lunchBreak.start)!;
      final lunchEnd = _toMinutes(rule.lunchBreak.end)!;
      final pauseStart = _toMinutes(rule.pauseBreak.start)!;
      final pauseEnd = _toMinutes(rule.pauseBreak.end)!;
      if (lunchStart < pauseEnd && pauseStart < lunchEnd) {
        return 'Almoço e pausa não podem se sobrepor em $label.';
      }
    }
    return null;
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

  void _setTimezone(String value) {
    final draft = _currentDraft;
    if (draft == null) return;
    setState(() => draft.timezone = value);
  }

  void _setRuleTime(_DayRuleDraft rule, {String? start, String? end}) {
    setState(() {
      if (start != null) rule.start = start;
      if (end != null) rule.end = end;
    });
  }

  void _setBreakValue(_BreakDraft draft,
      {bool? enabled, String? start, String? end}) {
    setState(() {
      if (enabled != null) draft.enabled = enabled;
      if (start != null) draft.start = start;
      if (end != null) draft.end = end;
    });
  }

  void _toggleOverride(int weekday, bool selected) {
    final draft = _currentDraft;
    if (draft == null) return;
    setState(() {
      if (selected) {
        final source = draft.defaultRule;
        draft.dailyOverrides[weekday] = _DayRuleDraft(
          start: source.start,
          end: source.end,
          lunchBreak: source.lunchBreak.copyWith(),
          pauseBreak: source.pauseBreak.copyWith(),
        );
      } else {
        draft.dailyOverrides.remove(weekday);
      }
    });
  }

  void _setDelayPolicyField({
    int? tempoMaximoAtrasoMin,
    int? janelaAvisoAntesConsultaMin,
    int? monitorIntervalMin,
    bool? fallbackWhatsappForProfessional,
  }) {
    final policy = _currentDelayPolicy;
    if (policy == null) return;
    setState(() {
      if (tempoMaximoAtrasoMin != null) {
        policy.tempoMaximoAtrasoMin = tempoMaximoAtrasoMin;
      }
      if (janelaAvisoAntesConsultaMin != null) {
        policy.janelaAvisoAntesConsultaMin = janelaAvisoAntesConsultaMin;
      }
      if (monitorIntervalMin != null) {
        policy.monitorIntervalMin = monitorIntervalMin;
      }
      if (fallbackWhatsappForProfessional != null) {
        policy.fallbackWhatsappForProfessional =
            fallbackWhatsappForProfessional;
      }
    });
  }

  Future<void> _saveSchedule() async {
    if (_tenantId == null || _selectedProfessionalId == null) return;
    final draft = _currentDraft;
    if (draft == null) return;

    final timezone = _timezoneController.text.trim().isEmpty
        ? 'America/Sao_Paulo'
        : _timezoneController.text.trim();
    draft.timezone = timezone;

    final defaultError = _validateDayRule(draft.defaultRule, 'horário padrão');
    if (defaultError != null) {
      setState(() => _error = defaultError);
      return;
    }

    for (final entry in draft.dailyOverrides.entries) {
      final error = _validateDayRule(entry.value, _weekdayLabel(entry.key));
      if (error != null) {
        setState(() => _error = error);
        return;
      }
    }

    setState(() {
      _savingSchedule = true;
      _error = null;
      _status = null;
    });

    try {
      final payload = {
        'tenant_id': _tenantId,
        'professional_id': _selectedProfessionalId,
        'timezone': timezone,
        'workdays': draft.workdays.toList()..sort(),
        'work_hours': {
          'start': draft.defaultRule.start,
          'end': draft.defaultRule.end,
          'lunch_break': {
            'enabled': draft.defaultRule.lunchBreak.enabled,
            'start': draft.defaultRule.lunchBreak.start,
            'end': draft.defaultRule.lunchBreak.end,
          },
          'snack_break': {
            'enabled': draft.defaultRule.pauseBreak.enabled,
            'start': draft.defaultRule.pauseBreak.start,
            'end': draft.defaultRule.pauseBreak.end,
          },
          'daily_overrides': {
            for (final entry in draft.dailyOverrides.entries)
              '${entry.key}': {
                'start': entry.value.start,
                'end': entry.value.end,
                'lunch_break': {
                  'enabled': entry.value.lunchBreak.enabled,
                  'start': entry.value.lunchBreak.start,
                  'end': entry.value.lunchBreak.end,
                },
                'snack_break': {
                  'enabled': entry.value.pauseBreak.enabled,
                  'start': entry.value.pauseBreak.start,
                  'end': entry.value.pauseBreak.end,
                },
              }
          },
        },
      };

      await Supabase.instance.client
          .from('professional_schedule_settings')
          .upsert(
            payload,
            onConflict: 'tenant_id,professional_id',
          );

      setState(() => _status = 'Horários salvos com sucesso.');
      await _load();
    } catch (error) {
      setState(() => _error = 'Erro ao salvar horários: $error');
    } finally {
      if (mounted) setState(() => _savingSchedule = false);
    }
  }

  Future<void> _saveDelayPolicy() async {
    if (_tenantId == null || _selectedProfessionalId == null) return;
    final policy = _currentDelayPolicy;
    if (policy == null) return;

    if (policy.tempoMaximoAtrasoMin < 0 || policy.tempoMaximoAtrasoMin > 180) {
      setState(() =>
          _error = 'Tempo máximo de atraso deve ficar entre 0 e 180 minutos.');
      return;
    }
    if (policy.janelaAvisoAntesConsultaMin < 5 ||
        policy.janelaAvisoAntesConsultaMin > 1440) {
      setState(
          () => _error = 'Janela de aviso deve ficar entre 5 e 1440 minutos.');
      return;
    }
    if (policy.monitorIntervalMin < 1 || policy.monitorIntervalMin > 60) {
      setState(() =>
          _error = 'Intervalo do monitor deve ficar entre 1 e 60 minutos.');
      return;
    }

    setState(() {
      _savingDelayPolicy = true;
      _error = null;
      _status = null;
    });

    try {
      await Supabase.instance.client.from('delay_policies').upsert(
        {
          'tenant_id': _tenantId,
          'professional_id': _selectedProfessionalId,
          'tempo_maximo_atraso_min': policy.tempoMaximoAtrasoMin,
          'janela_aviso_antes_consulta_min': policy.janelaAvisoAntesConsultaMin,
          'monitor_interval_min': policy.monitorIntervalMin,
          'fallback_whatsapp_for_professional':
              policy.fallbackWhatsappForProfessional,
        },
        onConflict: 'tenant_id,professional_id',
      );
      setState(() => _status = 'Política de atraso salva com sucesso.');
      await _load();
    } catch (error) {
      setState(() => _error = 'Erro ao salvar política de atraso: $error');
    } finally {
      if (mounted) setState(() => _savingDelayPolicy = false);
    }
  }

  void _resetUnavailabilityForm() {
    final draft = _emptyUnavailabilityDraft();
    setState(() {
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
      _unavailabilityStart = startsAt.toLocal();
      _unavailabilityEnd = endsAt.toLocal();
      _shareReasonWithClient = row['share_reason_with_client'] == true;
      _reasonController.text = (row['reason'] as String?) ?? '';
      _currentUnavailabilityDraftId = row['id'] as String?;
    });
  }

  String? _currentUnavailabilityDraftId;

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
        'reason': _reasonController.text.trim().isEmpty
            ? null
            : _reasonController.text.trim(),
        'share_reason_with_client': _shareReasonWithClient,
      };

      if (_currentUnavailabilityDraftId == null) {
        await Supabase.instance.client
            .from('professional_unavailability')
            .insert(payload);
        setState(() => _status = 'Ausência cadastrada com sucesso.');
      } else {
        await Supabase.instance.client
            .from('professional_unavailability')
            .update(payload)
            .eq('id', _currentUnavailabilityDraftId!);
        setState(() => _status = 'Ausência atualizada com sucesso.');
      }

      _currentUnavailabilityDraftId = null;
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
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await Supabase.instance.client
          .from('professional_unavailability')
          .delete()
          .eq('id', id);
      if (_currentUnavailabilityDraftId == id) {
        _currentUnavailabilityDraftId = null;
        _resetUnavailabilityForm();
      }
      setState(() => _status = 'Ausência removida com sucesso.');
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
      setState(
          () => _error = 'Erro ao atualizar visibilidade da ausência: $error');
    }
  }

  Widget _buildBreakEditor(String title, _BreakDraft draft) {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(title),
              value: draft.enabled,
              onChanged: (value) => _setBreakValue(draft, enabled: value),
            ),
            if (draft.enabled)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickTime(
                        current: draft.start,
                        onPicked: (value) =>
                            _setBreakValue(draft, start: value),
                      ),
                      child: Text('Início: ${draft.start}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickTime(
                        current: draft.end,
                        onPicked: (value) => _setBreakValue(draft, end: value),
                      ),
                      child: Text('Fim: ${draft.end}'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayRuleEditor(
      {required String title, required _DayRuleDraft rule}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(
                      current: rule.start,
                      onPicked: (value) => _setRuleTime(rule, start: value),
                    ),
                    child: Text('Início: ${rule.start}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(
                      current: rule.end,
                      onPicked: (value) => _setRuleTime(rule, end: value),
                    ),
                    child: Text('Fim: ${rule.end}'),
                  ),
                ),
              ],
            ),
            _buildBreakEditor('Intervalo de almoço', rule.lunchBreak),
            _buildBreakEditor('Pausa rápida', rule.pauseBreak),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = _currentDraft;
    final delayPolicy = _currentDelayPolicy;

    return Scaffold(
      appBar: AppBar(title: const Text('Horários')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _professionals.isEmpty
              ? const Center(child: Text('Nenhum profissional cadastrado.'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedProfessionalId,
                          decoration:
                              const InputDecoration(labelText: 'Profissional'),
                          items: _professionals
                              .map(
                                (row) => DropdownMenuItem<String>(
                                  value: row['id'] as String,
                                  child: Text(
                                    row['active'] == true
                                        ? (row['name'] as String? ?? '-')
                                        : '${(row['name'] as String? ?? '-')} (inativo)',
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedProfessionalId = value;
                              _applyCurrentDraftToForm();
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
                              onChanged: _setTimezone,
                              decoration: const InputDecoration(
                                labelText: 'Timezone',
                                helperText: 'Exemplo: America/Sao_Paulo',
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text('Dias de atendimento'),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: List.generate(
                                7,
                                (day) => FilterChip(
                                  label: Text(_weekdayLabel(day)),
                                  selected: draft.workdays.contains(day),
                                  onSelected: (selected) =>
                                      _toggleWorkday(day, selected),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildDayRuleEditor(
                              title: 'Horário padrão',
                              rule: draft.defaultRule,
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: ElevatedButton(
                                onPressed:
                                    _savingSchedule ? null : _saveSchedule,
                                child: Text(
                                  _savingSchedule
                                      ? 'Salvando...'
                                      : 'Salvar horários',
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
                          children:
                              (draft.workdays.toList()..sort()).map((weekday) {
                            final override = draft.dailyOverrides[weekday];
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                      'Usar regra específica em ${_weekdayLabel(weekday)}'),
                                  value: override != null,
                                  onChanged: (value) =>
                                      _toggleOverride(weekday, value),
                                ),
                                if (override != null)
                                  _buildDayRuleEditor(
                                    title:
                                        'Configuração de ${_weekdayLabel(weekday)}',
                                    rule: override,
                                  ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (delayPolicy != null)
                      Card(
                        child: ExpansionTile(
                          title: const Text('Política de atraso'),
                          childrenPadding: const EdgeInsets.all(12),
                          children: [
                            TextFormField(
                              initialValue:
                                  delayPolicy.tempoMaximoAtrasoMin.toString(),
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Tempo máximo de atraso (minutos)',
                              ),
                              onChanged: (value) => _setDelayPolicyField(
                                tempoMaximoAtrasoMin: int.tryParse(value) ??
                                    delayPolicy.tempoMaximoAtrasoMin,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              initialValue: delayPolicy
                                  .janelaAvisoAntesConsultaMin
                                  .toString(),
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText:
                                    'Janela de aviso antes da consulta (minutos)',
                              ),
                              onChanged: (value) => _setDelayPolicyField(
                                janelaAvisoAntesConsultaMin:
                                    int.tryParse(value) ??
                                        delayPolicy.janelaAvisoAntesConsultaMin,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              initialValue:
                                  delayPolicy.monitorIntervalMin.toString(),
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Intervalo do monitor (minutos)',
                              ),
                              onChanged: (value) => _setDelayPolicyField(
                                monitorIntervalMin: int.tryParse(value) ??
                                    delayPolicy.monitorIntervalMin,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value:
                                  delayPolicy.fallbackWhatsappForProfessional,
                              onChanged: (value) => _setDelayPolicyField(
                                fallbackWhatsappForProfessional: value,
                              ),
                              title: const Text(
                                  'Usar WhatsApp como fallback do profissional'),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: ElevatedButton(
                                onPressed: _savingDelayPolicy
                                    ? null
                                    : _saveDelayPolicy,
                                child: Text(
                                  _savingDelayPolicy
                                      ? 'Salvando...'
                                      : 'Salvar política de atraso',
                                ),
                              ),
                            ),
                          ],
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
                              'Bloqueia a disponibilidade do profissional em períodos específicos.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: () async {
                              final picked =
                                  await _pickDateTime(_unavailabilityStart);
                              if (picked == null) return;
                              setState(() => _unavailabilityStart = picked);
                            },
                            child: Text(
                                'Início: ${_formatDateTime(_unavailabilityStart)}'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: () async {
                              final picked =
                                  await _pickDateTime(_unavailabilityEnd);
                              if (picked == null) return;
                              setState(() => _unavailabilityEnd = picked);
                            },
                            child: Text(
                                'Fim: ${_formatDateTime(_unavailabilityEnd)}'),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _reasonController,
                            decoration: const InputDecoration(
                                labelText: 'Motivo (opcional)'),
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _shareReasonWithClient,
                            onChanged: (value) =>
                                setState(() => _shareReasonWithClient = value),
                            title: const Text(
                                'Permitir que o cliente veja o motivo'),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _savingUnavailability
                                      ? null
                                      : _saveUnavailability,
                                  child: Text(
                                    _savingUnavailability
                                        ? 'Salvando...'
                                        : _currentUnavailabilityDraftId == null
                                            ? 'Adicionar ausência'
                                            : 'Atualizar ausência',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: _savingUnavailability
                                    ? null
                                    : () {
                                        setState(() =>
                                            _currentUnavailabilityDraftId =
                                                null);
                                        _resetUnavailabilityForm();
                                      },
                                child: const Text('Limpar'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _showOnlyShareable,
                            onChanged: (value) =>
                                setState(() => _showOnlyShareable = value),
                            title: const Text(
                                'Mostrar apenas ausências visíveis ao cliente'),
                          ),
                          const SizedBox(height: 8),
                          if (_currentUnavailability.isEmpty)
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text('Nenhuma ausência cadastrada.'),
                            ),
                          ..._currentUnavailability.map((row) {
                            final startsAt = DateTime.tryParse(
                                row['starts_at'] as String? ?? '');
                            final endsAt = DateTime.tryParse(
                                row['ends_at'] as String? ?? '');
                            final shareReason =
                                row['share_reason_with_client'] == true;
                            final reason = (row['reason'] as String?)?.trim();
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      startsAt == null || endsAt == null
                                          ? 'Período inválido'
                                          : '${_formatDateTime(startsAt.toLocal())} até ${_formatDateTime(endsAt.toLocal())}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                        'Motivo: ${reason == null || reason.isEmpty ? '-' : reason}'),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        FilterChip(
                                          label: Text(
                                            shareReason
                                                ? 'Visível ao cliente'
                                                : 'Oculto ao cliente',
                                          ),
                                          selected: shareReason,
                                          onSelected: (value) =>
                                              _setShareReason(
                                                  row['id'] as String, value),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: () =>
                                              _startEditUnavailability(row),
                                          icon: const Icon(Icons.edit_outlined),
                                          label: const Text('Editar'),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: () =>
                                              _deleteUnavailability(
                                                  row['id'] as String),
                                          icon:
                                              const Icon(Icons.delete_outline),
                                          label: const Text('Excluir'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
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
                  ],
                ),
    );
  }
}
