import 'package:flutter/material.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/appointment.dart';
import '../models/option_item.dart';
import '../services/appointment_service.dart';
import '../services/catalog_service.dart';

enum AgendaViewMode { day, week, month }

class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  final _catalogService = CatalogService();
  final _appointmentService = AppointmentService();

  bool _loading = false;
  bool _actionLoading = false;
  bool _alertsLoading = false;
  bool _alertsExpanded = true;
  String? _error;

  List<AppointmentItem> _appointments = [];
  List<PunctualityAlertItem> _punctualityAlerts = [];
  Map<String, ClientLocationConsentItem> _locationConsents = {};
  List<OptionItem> _professionals = [];
  Map<String, String> _timezoneByProfessional = {};
  Map<String, ProfessionalScheduleSettings> _scheduleByProfessional = {};
  Map<String, int> _slotMinutesByProfessional = {};

  DateTime _selectedDate = DateTime.now();
  AgendaViewMode _viewMode = AgendaViewMode.day;
  String? _selectedProfessionalId;
  String _selectedStatus = 'scheduled';

  String _formatTime(DateTime utcDateTime, String timezone) {
    final location = _resolveLocation(timezone);
    final localDateTime = tz.TZDateTime.from(utcDateTime, location);
    final hh = localDateTime.hour.toString().padLeft(2, '0');
    final mm = localDateTime.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  tz.Location _resolveLocation(String timezone) {
    try {
      return tz.getLocation(timezone);
    } catch (_) {
      return tz.getLocation('America/Sao_Paulo');
    }
  }

  int? _parseMinutes(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hh = int.tryParse(parts[0]);
    final mm = int.tryParse(parts[1]);
    if (hh == null || mm == null) return null;
    return hh * 60 + mm;
  }

  List<int> _parseWorkdays(dynamic raw) {
    if (raw is! List) return [1, 2, 3, 4, 5];
    final values = raw
        .map((item) =>
            item is num ? item.toInt() : int.tryParse(item.toString()) ?? -1)
        .where((item) => item >= 0 && item <= 6)
        .toList();
    return values.isNotEmpty ? values : [1, 2, 3, 4, 5];
  }

  ({bool enabled, String start, String end}) _parseBreakConfig(
    dynamic raw,
    String fallbackStart,
    String fallbackEnd,
  ) {
    if (raw is! Map<String, dynamic>) {
      return (enabled: false, start: fallbackStart, end: fallbackEnd);
    }
    final hasLegacyWindow = !raw.containsKey('enabled') &&
        raw['start'] is String &&
        raw['end'] is String;
    return (
      enabled: raw['enabled'] == true || hasLegacyWindow,
      start: raw['start'] is String ? raw['start'] as String : fallbackStart,
      end: raw['end'] is String ? raw['end'] as String : fallbackEnd,
    );
  }

  ({Color background, Color border, Color text, String label}) _statusVisual(
      String status) {
    switch (status.toLowerCase()) {
      case 'confirmed':
        return (
          background: AppColors.secondary.withValues(alpha: 0.14),
          border: AppColors.secondary.withValues(alpha: 0.4),
          text: const Color(0xFF0F666A),
          label: 'Confirmado',
        );
      case 'cancelled':
        return (
          background: AppColors.danger.withValues(alpha: 0.12),
          border: AppColors.danger.withValues(alpha: 0.35),
          text: const Color(0xFF8A2E2A),
          label: 'Cancelado',
        );
      case 'done':
        return (
          background: AppColors.secondary.withValues(alpha: 0.14),
          border: AppColors.secondary.withValues(alpha: 0.4),
          text: const Color(0xFF0F666A),
          label: 'ConcluÃ­do',
        );
      case 'rescheduled':
        return (
          background: Colors.white,
          border: const Color(0xFFC9D1DA),
          text: const Color(0xFF5C6470),
          label: 'Remarcado',
        );
      case 'no_show':
        return (
          background: AppColors.danger.withValues(alpha: 0.12),
          border: AppColors.danger.withValues(alpha: 0.35),
          text: const Color(0xFF8A2E2A),
          label: 'NÃ£o compareceu',
        );
      case 'scheduled':
        return (
          background: Colors.white,
          border: const Color(0xFFC9D1DA),
          text: const Color(0xFF5C6470),
          label: 'Agendado',
        );
      case 'available':
        return (
          background: const Color(0xFFF0F2F5),
          border: const Color(0xFFD8DEE5),
          text: const Color(0xFF4B5766),
          label: 'DisponÃ­vel',
        );
      default:
        return (
          background: Colors.white,
          border: const Color(0xFFC9D1DA),
          text: const Color(0xFF5C6470),
          label: status,
        );
    }
  }

  ({Color background, Color border, Color text, Color stripe, String label})
      _punctualityVisual(String status) {
    switch (status.toLowerCase()) {
      case 'on_time':
        return (
          background: AppColors.secondary.withValues(alpha: 0.14),
          border: AppColors.secondary.withValues(alpha: 0.4),
          text: const Color(0xFF0F666A),
          stripe: AppColors.secondary,
          label: 'No horÃ¡rio',
        );
      case 'late_ok':
        return (
          background: AppColors.accent.withValues(alpha: 0.17),
          border: AppColors.accent.withValues(alpha: 0.45),
          text: const Color(0xFF8A5427),
          stripe: AppColors.accent,
          label: 'Atraso leve',
        );
      case 'late_critical':
        return (
          background: AppColors.danger.withValues(alpha: 0.12),
          border: AppColors.danger.withValues(alpha: 0.35),
          text: const Color(0xFF8A2E2A),
          stripe: AppColors.danger,
          label: 'Atraso crÃ­tico',
        );
      case 'no_data':
      default:
        return (
          background: const Color(0xFFF0F2F5),
          border: const Color(0xFFD8DEE5),
          text: const Color(0xFF4B5766),
          stripe: AppColors.muted,
          label: 'Sem dados',
        );
    }
  }

  ({Color background, Color border, Color text, String label, String detail})
      _consentVisual(String appointmentId) {
    final consent = _locationConsents[appointmentId];
    if (consent == null) {
      return (
        background: const Color(0xFFF0F2F5),
        border: const Color(0xFFD8DEE5),
        text: const Color(0xFF4B5766),
        label: 'Sem consentimento',
        detail: 'Cliente ainda nÃ£o autorizou localizaÃ§Ã£o',
      );
    }

    final status = consent.consentStatus.toLowerCase();
    final expiry = consent.expiresAt;
    if (status == 'granted' && consent.isGrantedActive) {
      final detail = expiry == null
          ? 'VÃ¡lido sem expiraÃ§Ã£o'
          : 'VÃ¡lido atÃ© ${_formatShortDate(expiry.toLocal())}';
      return (
        background: AppColors.secondary.withValues(alpha: 0.14),
        border: AppColors.secondary.withValues(alpha: 0.4),
        text: const Color(0xFF0F666A),
        label: 'Consentimento ativo',
        detail: detail,
      );
    }

    if (status == 'denied') {
      return (
        background: AppColors.danger.withValues(alpha: 0.12),
        border: AppColors.danger.withValues(alpha: 0.35),
        text: const Color(0xFF8A2E2A),
        label: 'Consentimento negado',
        detail: 'Sem autorizaÃ§Ã£o para monitoramento',
      );
    }

    if (status == 'revoked') {
      return (
        background: AppColors.accent.withValues(alpha: 0.17),
        border: AppColors.accent.withValues(alpha: 0.45),
        text: const Color(0xFF8A5427),
        label: 'Consentimento revogado',
        detail: 'AutorizaÃ§Ã£o removida pelo cliente',
      );
    }

    return (
      background: const Color(0xFFF0F2F5),
      border: const Color(0xFFD8DEE5),
      text: const Color(0xFF4B5766),
      label: 'Consentimento expirado',
      detail: 'Renove a autorizaÃ§Ã£o de localizaÃ§Ã£o',
    );
  }

  String _punctualityDetail(AppointmentItem item) {
    final eta = item.punctualityEtaMin;
    final delay = item.punctualityPredictedDelayMin;
    if (eta == null && delay == null) return 'Sem dados de deslocamento';
    if (eta != null && delay != null) {
      return 'ETA $eta min â€¢ atraso previsto $delay min';
    }
    if (eta != null) return 'ETA $eta min';
    return 'Atraso previsto $delay min';
  }

  String _alertTypeLabel(String type) {
    switch (type) {
      case 'punctuality_on_time':
        return 'Cliente no horÃ¡rio';
      case 'punctuality_late_ok':
        return 'Cliente com atraso leve';
      case 'punctuality_late_critical':
        return 'Atraso crÃ­tico';
      default:
        return 'Alerta de pontualidade';
    }
  }

  String _alertSummary(PunctualityAlertItem alert) {
    final eta = (alert.payload['eta_minutes'] as num?)?.toInt();
    final delay = (alert.payload['predicted_arrival_delay'] as num?)?.toInt();
    if (eta != null && delay != null) {
      return 'ETA $eta min â€¢ atraso previsto $delay min';
    }
    if (eta != null) return 'ETA $eta min';
    if (delay != null) return 'Atraso previsto $delay min';
    return 'Sem dados adicionais';
  }

  String _formatAlertTime(DateTime utcDateTime) {
    final local = utcDateTime.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mi = local.minute.toString().padLeft(2, '0');
    return '$dd/$mm $hh:$mi';
  }

  Future<void> _markAlertAsRead(PunctualityAlertItem alert) async {
    if (alert.isRead) return;
    setState(() => _alertsLoading = true);
    try {
      await _appointmentService.markPunctualityAlertRead(alert.id);
      if (!mounted) return;
      setState(() {
        _punctualityAlerts = _punctualityAlerts
            .map((item) => item.id == alert.id
                ? PunctualityAlertItem(
                    id: item.id,
                    appointmentId: item.appointmentId,
                    type: item.type,
                    status: 'read',
                    createdAt: item.createdAt,
                    payload: item.payload,
                  )
                : item)
            .toList();
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Erro ao marcar alerta como lido');
    } finally {
      if (mounted) setState(() => _alertsLoading = false);
    }
  }

  Future<void> _markAllAlertsAsRead() async {
    final unread = _punctualityAlerts.where((item) => !item.isRead).toList();
    if (unread.isEmpty) return;
    setState(() => _alertsLoading = true);
    try {
      await _appointmentService
          .markPunctualityAlertsRead(unread.map((item) => item.id).toList());
      if (!mounted) return;
      setState(() {
        _punctualityAlerts = _punctualityAlerts
            .map((item) => item.isRead
                ? item
                : PunctualityAlertItem(
                    id: item.id,
                    appointmentId: item.appointmentId,
                    type: item.type,
                    status: 'read',
                    createdAt: item.createdAt,
                    payload: item.payload,
                  ))
            .toList();
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Erro ao marcar alertas como lidos');
      }
    } finally {
      if (mounted) setState(() => _alertsLoading = false);
    }
  }

  ({DateTime start, DateTime end}) _currentRange() {
    final anchor =
        DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    if (_viewMode == AgendaViewMode.day) {
      return (start: anchor, end: anchor.add(const Duration(days: 1)));
    }
    if (_viewMode == AgendaViewMode.week) {
      final monday = anchor.subtract(Duration(days: anchor.weekday - 1));
      return (start: monday, end: monday.add(const Duration(days: 7)));
    }
    final monthStart = DateTime(anchor.year, anchor.month, 1);
    final nextMonth = DateTime(anchor.year, anchor.month + 1, 1);
    return (start: monthStart, end: nextMonth);
  }

  List<DateTime> _calendarDays() {
    if (_viewMode == AgendaViewMode.day) return const [];
    final anchor =
        DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);

    if (_viewMode == AgendaViewMode.week) {
      final monday = anchor.subtract(Duration(days: anchor.weekday - 1));
      return List.generate(7, (index) => monday.add(Duration(days: index)));
    }

    final monthStart = DateTime(anchor.year, anchor.month, 1);
    final monthEnd = DateTime(anchor.year, anchor.month + 1, 0);
    final start = monthStart.subtract(Duration(days: monthStart.weekday - 1));
    final daysToAdd = (7 - monthEnd.weekday) % 7;
    final end = monthEnd.add(Duration(days: daysToAdd));

    final days = <DateTime>[];
    var cursor = start;
    while (!cursor.isAfter(end)) {
      days.add(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }
    return days;
  }

  String _dateKey(DateTime date) {
    final yyyy = date.year.toString().padLeft(4, '0');
    final mm = date.month.toString().padLeft(2, '0');
    final dd = date.day.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd';
  }

  String _dateKeyInTimezone(DateTime utcDate, String timezone) {
    final local =
        tz.TZDateTime.from(utcDate.toUtc(), _resolveLocation(timezone));
    final yyyy = local.year.toString().padLeft(4, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd';
  }

  int _weekdayIndex0to6(DateTime date) {
    return date.weekday % 7;
  }

  List<AppointmentItem> get _filteredAppointments {
    if (_selectedStatus.isEmpty) return _appointments;
    return _appointments
        .where((item) => item.status.toLowerCase() == _selectedStatus)
        .toList();
  }

  Map<String, ({int occupied, int free})> _dailyStats() {
    final days = _calendarDays();
    final occupiedByDay = <String, int>{};
    final activeStatuses = {'scheduled', 'confirmed'};

    for (final item in _appointments) {
      final normalizedStatus = item.status.toLowerCase();
      if (_selectedStatus.isNotEmpty) {
        if (normalizedStatus != _selectedStatus) continue;
      } else if (!activeStatuses.contains(normalizedStatus)) {
        continue;
      }
      final schedule = _scheduleByProfessional[item.professionalId];
      final timezone = schedule?.timezone ??
          _timezoneByProfessional[item.professionalId] ??
          'America/Sao_Paulo';
      final key = _dateKeyInTimezone(item.startsAt, timezone);
      occupiedByDay[key] = (occupiedByDay[key] ?? 0) + 1;
    }

    final activeProfessionalIds = _selectedProfessionalId != null
        ? <String>[_selectedProfessionalId!]
        : _professionals.map((item) => item.id).toList();
    final stats = <String, ({int occupied, int free})>{};

    for (final day in days) {
      final key = _dateKey(day);
      final weekday = _weekdayIndex0to6(day);
      var totalCapacitySlots = 0;

      for (final professionalId in activeProfessionalIds) {
        final schedule = _scheduleByProfessional[professionalId];
        final workdays = _parseWorkdays(schedule?.workdays);
        if (!workdays.contains(weekday)) continue;

        final workHours = schedule?.workHours is Map<String, dynamic>
            ? schedule!.workHours as Map<String, dynamic>
            : <String, dynamic>{};
        final overrides = workHours['daily_overrides'] is Map<String, dynamic>
            ? workHours['daily_overrides'] as Map<String, dynamic>
            : <String, dynamic>{};
        final dayRule = overrides['$weekday'] is Map<String, dynamic>
            ? overrides['$weekday'] as Map<String, dynamic>
            : workHours;

        final start = _parseMinutes(
            dayRule['start'] is String ? dayRule['start'] as String : '09:00');
        final end = _parseMinutes(
            dayRule['end'] is String ? dayRule['end'] as String : '18:00');
        if (start == null || end == null || end <= start) continue;

        var minutes = end - start;
        final lunch =
            _parseBreakConfig(dayRule['lunch_break'], '12:00', '13:00');
        if (lunch.enabled) {
          final lunchStart = _parseMinutes(lunch.start);
          final lunchEnd = _parseMinutes(lunch.end);
          if (lunchStart != null && lunchEnd != null && lunchEnd > lunchStart) {
            minutes -= (lunchEnd - lunchStart);
          }
        }

        final pause =
            _parseBreakConfig(dayRule['snack_break'], '16:00', '16:15');
        if (pause.enabled) {
          final pauseStart = _parseMinutes(pause.start);
          final pauseEnd = _parseMinutes(pause.end);
          if (pauseStart != null && pauseEnd != null && pauseEnd > pauseStart) {
            minutes -= (pauseEnd - pauseStart);
          }
        }

        final slotMinutes =
            (_slotMinutesByProfessional[professionalId] ?? 30).clamp(1, 1440);
        totalCapacitySlots += (minutes.clamp(0, 24 * 60) / slotMinutes).floor();
      }

      final occupied = occupiedByDay[key] ?? 0;
      stats[key] = (
        occupied: occupied,
        free: (totalCapacitySlots - occupied).clamp(0, 10000)
      );
    }

    return stats;
  }

  Future<void> _loadAppointments() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final range = _currentRange();
      final items = await _appointmentService.getAppointmentsRange(
        start: range.start,
        end: range.end,
        professionalId: _selectedProfessionalId,
      );
      final appointmentIds = items.map((item) => item.id).toList();
      final consentByAppointment =
          await _appointmentService.getLocationConsents(appointmentIds);
      final alerts = await _appointmentService.getPunctualityAlerts(
        appointmentIds: appointmentIds,
        limit: 8,
      );
      final queuedAlertIds =
          alerts.where((item) => item.isQueued).map((item) => item.id).toList();
      if (queuedAlertIds.isNotEmpty) {
        await _appointmentService
            .markPunctualityAlertsDelivered(queuedAlertIds);
      }
      final normalizedAlerts = alerts
          .map(
            (item) => item.isQueued
                ? PunctualityAlertItem(
                    id: item.id,
                    appointmentId: item.appointmentId,
                    type: item.type,
                    status: 'sent',
                    createdAt: item.createdAt,
                    payload: item.payload,
                  )
                : item,
          )
          .toList();

      final activeProfessionalIds = _selectedProfessionalId != null
          ? <String>[_selectedProfessionalId!]
          : _professionals.map((item) => item.id).toList();

      final scheduleByProfessional = await _appointmentService
          .getProfessionalScheduleSettings(activeProfessionalIds);
      final slotMinutesByProfessional = await _appointmentService
          .getProfessionalSlotMinutes(activeProfessionalIds);
      final timezoneByProfessional = <String, String>{
        for (final entry in scheduleByProfessional.entries)
          entry.key: entry.value.timezone,
      };

      setState(() {
        _appointments = items;
        _punctualityAlerts = normalizedAlerts;
        _locationConsents = consentByAppointment;
        _timezoneByProfessional = timezoneByProfessional;
        _scheduleByProfessional = scheduleByProfessional;
        _slotMinutesByProfessional = slotMinutesByProfessional;
      });
    } catch (_) {
      setState(() => _error = 'Erro ao carregar agenda');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadProfessionals() async {
    final professionals = await _catalogService.listProfessionals();
    if (!mounted) return;
    setState(() => _professionals = professionals);
    await _loadAppointments();
  }

  @override
  void initState() {
    super.initState();
    _loadProfessionals();
  }

  String _formatShortDate(DateTime value) {
    final dd = value.day.toString().padLeft(2, '0');
    final mm = value.month.toString().padLeft(2, '0');
    final yyyy = value.year.toString();
    return '$dd/$mm/$yyyy';
  }

  String _dayHeader(DateTime day) {
    const names = ['Dom.', 'Seg.', 'Ter.', 'Qua.', 'Qui.', 'Sex.', 'Sab.'];
    return '${names[_weekdayIndex0to6(day)]} ${day.day}';
  }

  Future<void> _pickAgendaDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() => _selectedDate = picked);
    await _loadAppointments();
  }

  Future<void> _shiftAgendaDate(int days) async {
    if (_viewMode == AgendaViewMode.month) {
      setState(() => _selectedDate = DateTime(
          _selectedDate.year, _selectedDate.month + days, _selectedDate.day));
    } else {
      setState(() => _selectedDate = _selectedDate.add(Duration(days: days)));
    }
    await _loadAppointments();
  }

  Future<void> _setViewMode(AgendaViewMode mode) async {
    setState(() => _viewMode = mode);
    await _loadAppointments();
  }

  String _previousLabel() {
    if (_viewMode == AgendaViewMode.day) return 'Dia anterior';
    if (_viewMode == AgendaViewMode.week) return 'Semana anterior';
    return 'MÃªs anterior';
  }

  String _nextLabel() {
    if (_viewMode == AgendaViewMode.day) return 'PrÃ³ximo dia';
    if (_viewMode == AgendaViewMode.week) return 'PrÃ³xima semana';
    return 'PrÃ³ximo mÃªs';
  }

  bool _isFinalStatus(String status) {
    final normalized = status.toLowerCase();
    return normalized == 'done' ||
        normalized == 'cancelled' ||
        normalized == 'rescheduled' ||
        normalized == 'no_show';
  }

  Future<DateTime?> _pickRescheduleDateTime(DateTime initialUtc) async {
    final initialLocal = initialUtc.toLocal();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialLocal,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (pickedDate == null) return null;
    if (!mounted) return null;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialLocal),
    );
    if (pickedTime == null) return null;

    return DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    ).toUtc();
  }

  Future<void> _runStatusUpdate({
    required String appointmentId,
    required String status,
    String? cancellationReason,
    required String errorMessage,
  }) async {
    setState(() {
      _actionLoading = true;
      _error = null;
    });
    try {
      await _appointmentService.updateAppointmentStatus(
        appointmentId: appointmentId,
        status: status,
        cancellationReason: cancellationReason,
      );
      await _loadAppointments();
    } catch (_) {
      if (mounted) setState(() => _error = errorMessage);
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _handleCancel(AppointmentItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar agendamento'),
        content: const Text('Deseja realmente cancelar este agendamento?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancelar')),
        ],
      ),
    );
    if (ok != true) return;
    await _runStatusUpdate(
      appointmentId: item.id,
      status: 'cancelled',
      cancellationReason: 'Cancelado manualmente na agenda',
      errorMessage: 'Erro ao cancelar agendamento',
    );
  }

  Future<void> _handleComplete(AppointmentItem item) async {
    await _runStatusUpdate(
      appointmentId: item.id,
      status: 'done',
      errorMessage: 'Erro ao concluir agendamento',
    );
  }

  Future<void> _handleNoShow(AppointmentItem item) async {
    await _runStatusUpdate(
      appointmentId: item.id,
      status: 'no_show',
      errorMessage: 'Erro ao marcar nÃ£o compareceu',
    );
  }

  Future<void> _handleReschedule(AppointmentItem item) async {
    final newStartUtc = await _pickRescheduleDateTime(item.startsAt);
    if (newStartUtc == null) return;

    final blockMinutes = (item.serviceDurationMin + item.serviceIntervalMin) > 0
        ? (item.serviceDurationMin + item.serviceIntervalMin)
        : item.endsAt.difference(item.startsAt).inMinutes;
    final durationMinutes = blockMinutes > 0 ? blockMinutes : 30;
    final newEndUtc = newStartUtc.add(Duration(minutes: durationMinutes));

    setState(() {
      _actionLoading = true;
      _error = null;
    });
    try {
      await _appointmentService.rescheduleAppointment(
        original: item,
        newStartsAt: newStartUtc,
        newEndsAt: newEndUtc,
      );
      await _loadAppointments();
    } catch (_) {
      if (mounted) setState(() => _error = 'Erro ao remarcar agendamento');
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _handleUpdatePunctuality(AppointmentItem item) async {
    final consent = _locationConsents[item.id];
    if (consent == null || !consent.isGrantedActive) {
      setState(() {
        _error =
            'Sem consentimento ativo de localizaÃ§Ã£o para esta consulta. Registre o consentimento antes de monitorar.';
      });
      return;
    }

    final controller = TextEditingController(
      text: item.punctualityEtaMin?.toString() ?? '',
    );
    final etaMinutes = await showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Atualizar pontualidade'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'ETA em minutos (opcional)',
            hintText: 'Ex.: 20',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty) {
                Navigator.pop(ctx, -1);
                return;
              }
              final parsed = int.tryParse(value);
              Navigator.pop(ctx, parsed);
            },
            child: const Text('Enviar'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (etaMinutes == null) return;

    setState(() {
      _actionLoading = true;
      _error = null;
    });
    try {
      await _appointmentService.sendPunctualitySnapshot(
        appointmentId: item.id,
        etaMinutes: etaMinutes == -1 ? null : etaMinutes,
      );
      await _loadAppointments();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Erro ao atualizar pontualidade');
      }
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _handleLocationConsent(AppointmentItem item) async {
    final current = _locationConsents[item.id];
    String selectedStatus = current?.consentStatus.toLowerCase() == 'granted'
        ? 'granted'
        : current?.consentStatus.toLowerCase() == 'denied'
            ? 'denied'
            : current?.consentStatus.toLowerCase() == 'revoked'
                ? 'revoked'
                : 'granted';
    final versionController =
        TextEditingController(text: current?.consentTextVersion ?? 'v1');
    final expiryHoursController = TextEditingController(text: '24');

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: const Text('Consentimento de localizaÃ§Ã£o'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${item.clientName} â€¢ ${item.serviceName}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedStatus,
                decoration: const InputDecoration(
                  labelText: 'Status do consentimento',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'granted',
                    child: Text('Concedido'),
                  ),
                  DropdownMenuItem(
                    value: 'denied',
                    child: Text('Negado'),
                  ),
                  DropdownMenuItem(
                    value: 'revoked',
                    child: Text('Revogado'),
                  ),
                  DropdownMenuItem(
                    value: 'expired',
                    child: Text('Expirado'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setModalState(() => selectedStatus = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: versionController,
                decoration: const InputDecoration(
                  labelText: 'VersÃ£o do termo',
                  hintText: 'Ex.: v1',
                ),
              ),
              if (selectedStatus == 'granted') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: expiryHoursController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Validade em horas',
                    hintText: 'Ex.: 24',
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );

    if (shouldSave != true) {
      versionController.dispose();
      expiryHoursController.dispose();
      return;
    }

    DateTime? expiresAt;
    if (selectedStatus == 'granted') {
      final hours = int.tryParse(expiryHoursController.text.trim()) ?? 24;
      expiresAt = DateTime.now().toUtc().add(Duration(
            hours: hours.clamp(1, 24 * 30),
          ));
    }

    final consentVersion = versionController.text.trim().isEmpty
        ? 'v1'
        : versionController.text.trim();
    versionController.dispose();
    expiryHoursController.dispose();

    setState(() {
      _actionLoading = true;
      _error = null;
    });
    try {
      await _appointmentService.registerLocationConsent(
        appointment: item,
        consentStatus: selectedStatus,
        consentTextVersion: consentVersion,
        expiresAt: expiresAt,
      );
      await _loadAppointments();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Erro ao registrar consentimento');
      }
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _openDay(DateTime day) async {
    setState(() {
      _selectedDate = DateTime(day.year, day.month, day.day);
      _viewMode = AgendaViewMode.day;
    });
    await _loadAppointments();
  }

  Widget _buildCalendarView() {
    final days = _calendarDays();
    final stats = _dailyStats();
    final currentMonth = _selectedDate.month;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 7 * 120,
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: days.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1.15,
                ),
                itemBuilder: (_, index) {
                  final day = days[index];
                  final key = _dateKey(day);
                  final dayStats = stats[key] ?? (occupied: 0, free: 0);
                  final isCurrentMonth = day.month == currentMonth;
                  final isSelected = _dateKey(_selectedDate) == key;
                  final isEmpty = dayStats.occupied == 0;
                  final isFull = dayStats.occupied > 0 && dayStats.free == 0;

                  Color bg = Colors.white;
                  if (isEmpty) bg = AppColors.danger.withValues(alpha: 0.10);
                  if (isFull) bg = AppColors.secondary.withValues(alpha: 0.10);
                  if (!isCurrentMonth && _viewMode == AgendaViewMode.month) {
                    bg = bg.withValues(alpha: 0.55);
                  }

                  return InkWell(
                    onTap: () => _openDay(day),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    child: Container(
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : const Color(0xFFD7DDE4),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _dayHeader(day),
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: const Color(0xFF66717F),
                                      fontWeight: FontWeight.w500,
                                    ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          const Spacer(),
                          Text('Ocupados: ${dayStats.occupied}',
                              style: Theme.of(context).textTheme.bodySmall),
                          Text('Livres: ${dayStats.free}',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDayList() {
    return Expanded(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        itemBuilder: (_, index) {
          final filteredAppointments = _filteredAppointments;
          final item = filteredAppointments[index];
          final status = _statusVisual(item.status);
          final punctuality = _punctualityVisual(item.punctualityStatus);
          final consent = _consentVisual(item.id);
          final timezone = _timezoneByProfessional[item.professionalId] ??
              'America/Sao_Paulo';

          return Card(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                border: Border(
                  left: BorderSide(color: punctuality.stripe, width: 4),
                ),
              ),
              child: ListTile(
                title: Text('${item.serviceName} - ${item.clientName}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_formatTime(item.startsAt, timezone)} - ${_formatTime(item.endsAt, timezone)} (${item.professionalName})',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _punctualityDetail(item),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF5C6470),
                          ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: consent.background,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: consent.border),
                          ),
                          child: Text(
                            consent.label,
                            style: TextStyle(
                              color: consent.text,
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            consent.detail,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: const Color(0xFF5C6470),
                                    ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: status.background,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: status.border),
                          ),
                          child: Text(
                            status.label,
                            style: TextStyle(
                              color: status.text,
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: punctuality.background,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: punctuality.border),
                          ),
                          child: Text(
                            punctuality.label,
                            style: TextStyle(
                              color: punctuality.text,
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    PopupMenuButton<String>(
                      enabled: !_actionLoading,
                      onSelected: (value) async {
                        if (value == 'reschedule') {
                          await _handleReschedule(item);
                        }
                        if (value == 'cancel') await _handleCancel(item);
                        if (value == 'complete') await _handleComplete(item);
                        if (value == 'no_show') await _handleNoShow(item);
                        if (value == 'update_punctuality') {
                          await _handleUpdatePunctuality(item);
                        }
                        if (value == 'update_consent') {
                          await _handleLocationConsent(item);
                        }
                      },
                      itemBuilder: (_) {
                        final disabled = _isFinalStatus(item.status);
                        final canUpdatePunctuality =
                            (_locationConsents[item.id]?.isGrantedActive ??
                                false);
                        return [
                          PopupMenuItem(
                            value: 'update_punctuality',
                            enabled: canUpdatePunctuality,
                            child: Text(canUpdatePunctuality
                                ? 'Atualizar pontualidade'
                                : 'Pontualidade (sem consentimento)'),
                          ),
                          const PopupMenuItem(
                            value: 'update_consent',
                            child: Text('Registrar consentimento'),
                          ),
                          PopupMenuItem(
                            value: 'reschedule',
                            enabled: !disabled,
                            child: const Text('Remarcar'),
                          ),
                          PopupMenuItem(
                            value: 'cancel',
                            enabled: !disabled,
                            child: const Text('Cancelar'),
                          ),
                          PopupMenuItem(
                            value: 'complete',
                            enabled: !disabled,
                            child: const Text('Concluir'),
                          ),
                          PopupMenuItem(
                            value: 'no_show',
                            enabled: !disabled,
                            child: const Text('NÃ£o compareceu'),
                          ),
                        ];
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemCount: _filteredAppointments.length,
      ),
    );
  }

  Widget _buildPunctualityAlerts() {
    if (_punctualityAlerts.isEmpty) return const SizedBox.shrink();

    final appointmentById = {
      for (final item in _appointments) item.id: item,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                onTap: () => setState(() => _alertsExpanded = !_alertsExpanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Alertas de pontualidade (${_punctualityAlerts.length})',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Icon(_alertsExpanded
                          ? Icons.expand_less
                          : Icons.expand_more),
                    ],
                  ),
                ),
              ),
              if (_alertsExpanded) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _alertsLoading ? null : _markAllAlertsAsRead,
                    child: const Text('Marcar todos como lidos'),
                  ),
                ),
                if (_alertsLoading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                ..._punctualityAlerts.map((alert) {
                  final appointment = appointmentById[alert.appointmentId];
                  final title = appointment != null
                      ? '${appointment.clientName} • ${appointment.serviceName}'
                      : 'Consulta ${alert.appointmentId.substring(0, 8)}';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      border: Border.all(color: const Color(0xFFD7DDE4)),
                      color: Colors.white,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _alertTypeLabel(alert.type),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: alert.isRead
                                    ? const Color(0xFFF0F2F5)
                                    : AppColors.accent.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: alert.isRead
                                      ? const Color(0xFFD8DEE5)
                                      : AppColors.accent
                                          .withValues(alpha: 0.45),
                                ),
                              ),
                              child: Text(
                                alert.isRead ? 'Lido' : 'Nao lido',
                                style: TextStyle(
                                  color: alert.isRead
                                      ? const Color(0xFF5C6470)
                                      : const Color(0xFF8A5427),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(title),
                        const SizedBox(height: 2),
                        Text(
                          _alertSummary(alert),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFF5C6470),
                                  ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatAlertTime(alert.createdAt),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFF7A8492),
                                  ),
                        ),
                        if (!alert.isRead)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _alertsLoading
                                  ? null
                                  : () => _markAlertAsRead(alert),
                              child: const Text('Marcar como lido'),
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agenda'),
        leading: IconButton(
          tooltip: 'Menu principal',
          onPressed: () => Navigator.pushReplacementNamed(context, '/menu'),
          icon: const Icon(Icons.home_outlined),
        ),
        actions: [
          IconButton(
            onPressed: _loadAppointments,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/appointments/new')
                .then((_) => _loadAppointments()),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Filtros da agenda',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 10),
                              DropdownButtonFormField<String?>(
                                initialValue: _selectedProfessionalId,
                                decoration: const InputDecoration(
                                    labelText: 'Profissional'),
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('Todos'),
                                  ),
                                  ..._professionals.map(
                                    (item) => DropdownMenuItem<String?>(
                                      value: item.id,
                                      child: Text(item.label),
                                    ),
                                  ),
                                ],
                                onChanged: (value) async {
                                  setState(
                                      () => _selectedProfessionalId = value);
                                  await _loadAppointments();
                                },
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                initialValue: _selectedStatus,
                                isDense: true,
                                decoration: const InputDecoration(
                                  labelText: 'Status',
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 10),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                      value: '', child: Text('Todos')),
                                  DropdownMenuItem(
                                      value: 'scheduled',
                                      child: Text('Agendado')),
                                  DropdownMenuItem(
                                      value: 'confirmed',
                                      child: Text('Confirmado')),
                                  DropdownMenuItem(
                                      value: 'cancelled',
                                      child: Text('Cancelado')),
                                  DropdownMenuItem(
                                      value: 'done', child: Text('ConcluÃ­do')),
                                  DropdownMenuItem(
                                      value: 'no_show',
                                      child: Text('NÃ£o compareceu')),
                                ],
                                onChanged: (value) async {
                                  setState(() => _selectedStatus = value ?? '');
                                  await _loadAppointments();
                                },
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () =>
                                          _setViewMode(AgendaViewMode.day),
                                      style: OutlinedButton.styleFrom(
                                        backgroundColor:
                                            _viewMode == AgendaViewMode.day
                                                ? AppColors.primary
                                                : null,
                                      ),
                                      child: Text(
                                        'Dia',
                                        style: TextStyle(
                                          color: _viewMode == AgendaViewMode.day
                                              ? Colors.white
                                              : null,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () =>
                                          _setViewMode(AgendaViewMode.week),
                                      style: OutlinedButton.styleFrom(
                                        backgroundColor:
                                            _viewMode == AgendaViewMode.week
                                                ? AppColors.primary
                                                : null,
                                      ),
                                      child: Text(
                                        'Semana',
                                        style: TextStyle(
                                          color:
                                              _viewMode == AgendaViewMode.week
                                                  ? Colors.white
                                                  : null,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () =>
                                          _setViewMode(AgendaViewMode.month),
                                      style: OutlinedButton.styleFrom(
                                        backgroundColor:
                                            _viewMode == AgendaViewMode.month
                                                ? AppColors.primary
                                                : null,
                                      ),
                                      child: Text(
                                        'MÃªs',
                                        style: TextStyle(
                                          color:
                                              _viewMode == AgendaViewMode.month
                                                  ? Colors.white
                                                  : null,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  IconButton(
                                    tooltip: _previousLabel(),
                                    onPressed: () => _shiftAgendaDate(
                                        _viewMode == AgendaViewMode.week
                                            ? -7
                                            : -1),
                                    icon: const Icon(Icons.chevron_left),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: InkWell(
                                      onTap: _pickAgendaDate,
                                      child: Center(
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.calendar_today,
                                                size: 16),
                                            const SizedBox(width: 6),
                                            Text(
                                              _formatShortDate(_selectedDate),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    tooltip: _nextLabel(),
                                    onPressed: () => _shiftAgendaDate(
                                        _viewMode == AgendaViewMode.week
                                            ? 7
                                            : 1),
                                    icon: const Icon(Icons.chevron_right),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(42),
                                ),
                                onPressed:
                                    _actionLoading ? null : _loadAppointments,
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Atualizar agenda'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    _buildPunctualityAlerts(),
                    if (_viewMode == AgendaViewMode.day)
                      _buildDayList()
                    else
                      _buildCalendarView(),
                  ],
                ),
    );
  }
}
