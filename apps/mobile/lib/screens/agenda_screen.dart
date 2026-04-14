import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/appointment.dart';
import '../models/option_item.dart';
import '../services/appointment_service.dart';
import '../services/catalog_service.dart';

enum AgendaViewMode { day, week, month }

class _RescheduleSlotOption {
  const _RescheduleSlotOption({
    required this.startsAtUtc,
    required this.endsAtUtc,
    required this.label,
  });

  final DateTime startsAtUtc;
  final DateTime endsAtUtc;
  final String label;
}

class _RescheduleDaySuggestion {
  const _RescheduleDaySuggestion({
    required this.date,
    required this.freeSlots,
  });

  final DateTime date;
  final int freeSlots;
}

class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  final _catalogService = CatalogService();
  final _appointmentService = AppointmentService();
  static const _ptBrLocale = 'pt_BR';

  bool _loading = false;
  bool _rangeLoading = false;
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
          label: 'Concluído',
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
          label: 'Não compareceu',
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
          label: 'Disponível',
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
          label: 'No horário',
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
          label: 'Atraso crítico',
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
        detail: 'Cliente ainda não autorizou a localização',
      );
    }

    final status = consent.consentStatus.toLowerCase();
    final expiry = consent.expiresAt;
    if (status == 'granted' && consent.isGrantedActive) {
      final detail = expiry == null
          ? 'Válido sem expiração'
          : 'Válido até ${_formatShortDate(expiry.toLocal())}';
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
        detail: 'Sem autorização para monitoramento',
      );
    }

    if (status == 'revoked') {
      return (
        background: AppColors.accent.withValues(alpha: 0.17),
        border: AppColors.accent.withValues(alpha: 0.45),
        text: const Color(0xFF8A5427),
        label: 'Consentimento revogado',
        detail: 'Autorização removida pelo cliente',
      );
    }

    return (
      background: const Color(0xFFF0F2F5),
      border: const Color(0xFFD8DEE5),
      text: const Color(0xFF4B5766),
      label: 'Consentimento expirado',
      detail: 'Renove a autorização de localização',
    );
  }

  String _punctualityDetail(AppointmentItem item) {
    final eta = item.punctualityEtaMin;
    final delay = item.punctualityPredictedDelayMin;
    if (eta == null && delay == null) return 'Sem dados de deslocamento';
    if (eta != null && delay != null) {
      return 'Chegada em $eta min • atraso previsto de $delay min';
    }
    if (eta != null) return 'Chegada em $eta min';
    return 'Atraso previsto de $delay min';
  }

  String _alertTypeLabel(String type) {
    switch (type) {
      case 'punctuality_on_time':
        return 'Cliente no horário';
      case 'punctuality_late_ok':
        return 'Cliente com atraso leve';
      case 'punctuality_late_critical':
        return 'Atraso crítico';
      default:
        return 'Alerta de pontualidade';
    }
  }

  String _alertSummary(PunctualityAlertItem alert) {
    final eta = (alert.payload['eta_minutes'] as num?)?.toInt();
    final delay = (alert.payload['predicted_arrival_delay'] as num?)?.toInt();
    if (eta != null && delay != null) {
      return 'Chegada em $eta min • atraso previsto de $delay min';
    }
    if (eta != null) return 'Chegada em $eta min';
    if (delay != null) return 'Atraso previsto de $delay min';
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

  Map<String, List<AppointmentItem>> _appointmentsByDay() {
    final grouped = <String, List<AppointmentItem>>{};

    for (final item in _filteredAppointments) {
      final timezone =
          _timezoneByProfessional[item.professionalId] ?? 'America/Sao_Paulo';
      final key = _dateKeyInTimezone(item.startsAt, timezone);
      grouped.putIfAbsent(key, () => <AppointmentItem>[]).add(item);
    }

    for (final items in grouped.values) {
      items.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    }

    return grouped;
  }

  Future<void> _loadAppointments({bool partial = false}) async {
    setState(() {
      if (partial) {
        _rangeLoading = true;
      } else {
        _loading = true;
      }
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
      if (mounted) {
        setState(() {
          _loading = false;
          _rangeLoading = false;
        });
      }
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
    return DateFormat('dd/MM/yyyy', _ptBrLocale).format(value);
  }

  String _formatShortDayMonth(DateTime value) {
    return DateFormat('dd/MM', _ptBrLocale).format(value);
  }

  String _formatMonthLabel(DateTime value) {
    final label = DateFormat('MMMM yyyy', _ptBrLocale).format(value);
    return toBeginningOfSentenceCase(label) ?? label;
  }

  String _agendaDateLabel() {
    if (_viewMode == AgendaViewMode.day) {
      return _formatShortDate(_selectedDate);
    }

    if (_viewMode == AgendaViewMode.week) {
      final range = _currentRange();
      final endInclusive = range.end.subtract(const Duration(days: 1));

      if (range.start.year != endInclusive.year) {
        return '${_formatShortDate(range.start)} - ${_formatShortDate(endInclusive)}';
      }

      return '${_formatShortDayMonth(range.start)} - ${_formatShortDate(endInclusive)}';
    }

    return _formatMonthLabel(_selectedDate);
  }

  String _dayHeader(DateTime day) {
    final label =
        DateFormat('EEE d', _ptBrLocale).format(day).replaceAll('.', '');
    return toBeginningOfSentenceCase(label) ?? label;
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
    await _loadAppointments(partial: _viewMode != AgendaViewMode.day);
  }

  Future<void> _shiftAgendaDate(int days) async {
    if (_viewMode == AgendaViewMode.month) {
      setState(() => _selectedDate = DateTime(
          _selectedDate.year, _selectedDate.month + days, _selectedDate.day));
    } else {
      setState(() => _selectedDate = _selectedDate.add(Duration(days: days)));
    }
    await _loadAppointments(partial: _viewMode != AgendaViewMode.day);
  }

  Future<void> _setViewMode(AgendaViewMode mode) async {
    setState(() => _viewMode = mode);
    await _loadAppointments(partial: mode != AgendaViewMode.day);
  }

  int _currentNavigationStep() {
    if (_viewMode == AgendaViewMode.week) return 7;
    return 1;
  }

  Future<void> _handleHorizontalSwipe(DragEndDetails details) async {
    if (_viewMode == AgendaViewMode.day || _rangeLoading || _actionLoading) {
      return;
    }

    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 200) return;

    if (velocity < 0) {
      await _shiftAgendaDate(_currentNavigationStep());
    } else {
      await _shiftAgendaDate(-_currentNavigationStep());
    }
  }

  Widget _buildAgendaRangeViewport() {
    final child = _viewMode == AgendaViewMode.day
        ? _buildDayList()
        : _viewMode == AgendaViewMode.week
            ? _buildWeekView()
            : _buildCalendarView();

    final content = AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: _rangeLoading ? 0.6 : 1,
      child: child,
    );

    if (_viewMode == AgendaViewMode.day) {
      return content;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: _handleHorizontalSwipe,
      child: Column(
        children: [
          if (_rangeLoading)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          content,
        ],
      ),
    );
  }

  String _previousLabel() {
    if (_viewMode == AgendaViewMode.day) return 'Dia anterior';
    if (_viewMode == AgendaViewMode.week) return 'Semana anterior';
    return 'Mês anterior';
  }

  String _nextLabel() {
    if (_viewMode == AgendaViewMode.day) return 'Próximo dia';
    if (_viewMode == AgendaViewMode.week) return 'Próxima semana';
    return 'Próximo mês';
  }

  bool _isFinalStatus(String status) {
    final normalized = status.toLowerCase();
    return normalized == 'done' ||
        normalized == 'cancelled' ||
        normalized == 'rescheduled' ||
        normalized == 'no_show';
  }

  DateTime _normalizeDate(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  DateTime _combineDateAndMinutes(DateTime date, int minutes) {
    final hour = minutes ~/ 60;
    final minute = minutes % 60;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  bool _overlapsRange({
    required DateTime startA,
    required DateTime endA,
    required DateTime startB,
    required DateTime endB,
  }) {
    return startA.isBefore(endB) && endA.isAfter(startB);
  }

  Future<List<_RescheduleSlotOption>> _loadRescheduleSlots({
    required AppointmentItem original,
    required DateTime selectedDate,
  }) async {
    final schedule = _scheduleByProfessional[original.professionalId];
    final timezone = schedule?.timezone ??
        _timezoneByProfessional[original.professionalId] ??
        'America/Sao_Paulo';
    final location = _resolveLocation(timezone);
    final day = _normalizeDate(selectedDate);
    final weekday = _weekdayIndex0to6(day);
    final workdays = _parseWorkdays(schedule?.workdays);
    if (!workdays.contains(weekday)) {
      return const [];
    }

    final workHours = schedule?.workHours is Map<String, dynamic>
        ? schedule!.workHours as Map<String, dynamic>
        : <String, dynamic>{};
    final overrides = workHours['daily_overrides'] is Map<String, dynamic>
        ? workHours['daily_overrides'] as Map<String, dynamic>
        : <String, dynamic>{};
    final dayRule = overrides['$weekday'] is Map<String, dynamic>
        ? overrides['$weekday'] as Map<String, dynamic>
        : workHours;

    final startMinutes = _parseMinutes(
      dayRule['start'] is String ? dayRule['start'] as String : '09:00',
    );
    final endMinutes = _parseMinutes(
      dayRule['end'] is String ? dayRule['end'] as String : '18:00',
    );
    if (startMinutes == null ||
        endMinutes == null ||
        endMinutes <= startMinutes) {
      return const [];
    }

    final lunch = _parseBreakConfig(dayRule['lunch_break'], '12:00', '13:00');
    final lunchStart = lunch.enabled ? _parseMinutes(lunch.start) : null;
    final lunchEnd = lunch.enabled ? _parseMinutes(lunch.end) : null;

    final pause = _parseBreakConfig(dayRule['snack_break'], '16:00', '16:15');
    final pauseStart = pause.enabled ? _parseMinutes(pause.start) : null;
    final pauseEnd = pause.enabled ? _parseMinutes(pause.end) : null;

    final blockMinutes =
        (original.serviceDurationMin + original.serviceIntervalMin) > 0
            ? (original.serviceDurationMin + original.serviceIntervalMin)
            : original.endsAt.difference(original.startsAt).inMinutes;
    final durationMinutes = blockMinutes > 0 ? blockMinutes : 30;
    final slotStep =
        (_slotMinutesByProfessional[original.professionalId] ?? durationMinutes)
            .clamp(5, 1440);

    final localDayStart = tz.TZDateTime(location, day.year, day.month, day.day);
    final localDayEnd = localDayStart.add(const Duration(days: 1));

    final appointments = await _appointmentService.getAppointmentsRange(
      start: localDayStart,
      end: localDayEnd,
      professionalId: original.professionalId,
    );
    final isSameCurrentDay = _normalizeDate(
          tz.TZDateTime.from(original.startsAt, location),
        ) ==
        day;

    final nowInTimezone = tz.TZDateTime.now(location);
    final slots = <_RescheduleSlotOption>[];

    for (var minute = startMinutes;
        minute + durationMinutes <= endMinutes;
        minute += slotStep) {
      final localStart = _combineDateAndMinutes(day, minute);
      final localEnd = localStart.add(Duration(minutes: durationMinutes));
      final label =
          '${DateFormat('HH:mm', _ptBrLocale).format(localStart)} - ${DateFormat('HH:mm', _ptBrLocale).format(localEnd)}';

      final overlapsLunch = lunch.enabled &&
          lunchStart != null &&
          lunchEnd != null &&
          _overlapsRange(
            startA: localStart,
            endA: localEnd,
            startB: _combineDateAndMinutes(day, lunchStart),
            endB: _combineDateAndMinutes(day, lunchEnd),
          );
      if (overlapsLunch) continue;

      final overlapsPause = pause.enabled &&
          pauseStart != null &&
          pauseEnd != null &&
          _overlapsRange(
            startA: localStart,
            endA: localEnd,
            startB: _combineDateAndMinutes(day, pauseStart),
            endB: _combineDateAndMinutes(day, pauseEnd),
          );
      if (overlapsPause) continue;

      final slotStartUtc = tz.TZDateTime(
        location,
        localStart.year,
        localStart.month,
        localStart.day,
        localStart.hour,
        localStart.minute,
      ).toUtc();
      final slotEndUtc = tz.TZDateTime(
        location,
        localEnd.year,
        localEnd.month,
        localEnd.day,
        localEnd.hour,
        localEnd.minute,
      ).toUtc();

      if (!slotStartUtc.isAfter(nowInTimezone.toUtc())) continue;
      if (isSameCurrentDay &&
          _overlapsRange(
            startA: slotStartUtc,
            endA: slotEndUtc,
            startB: original.startsAt,
            endB: original.endsAt,
          )) {
        continue;
      }

      final hasConflict = appointments.any((appointment) {
        if (appointment.id == original.id) return false;
        final normalizedStatus = appointment.status.toLowerCase();
        if (normalizedStatus == 'cancelled' ||
            normalizedStatus == 'rescheduled' ||
            normalizedStatus == 'no_show') {
          return false;
        }
        return _overlapsRange(
          startA: slotStartUtc,
          endA: slotEndUtc,
          startB: appointment.startsAt,
          endB: appointment.endsAt,
        );
      });

      if (hasConflict) continue;

      slots.add(
        _RescheduleSlotOption(
          startsAtUtc: slotStartUtc,
          endsAtUtc: slotEndUtc,
          label: label,
        ),
      );
    }

    return slots;
  }

  String? _rescheduleDayHint({
    required AppointmentItem original,
    required DateTime selectedDate,
  }) {
    final schedule = _scheduleByProfessional[original.professionalId];
    final day = _normalizeDate(selectedDate);
    final weekday = _weekdayIndex0to6(day);
    final workdays = _parseWorkdays(schedule?.workdays);

    if (!workdays.contains(weekday)) {
      return 'O profissional nao atende neste dia.';
    }

    final workHours = schedule?.workHours is Map<String, dynamic>
        ? schedule!.workHours as Map<String, dynamic>
        : <String, dynamic>{};
    final overrides = workHours['daily_overrides'] is Map<String, dynamic>
        ? workHours['daily_overrides'] as Map<String, dynamic>
        : <String, dynamic>{};
    final dayRule = overrides['$weekday'] is Map<String, dynamic>
        ? overrides['$weekday'] as Map<String, dynamic>
        : workHours;

    final startMinutes = _parseMinutes(
      dayRule['start'] is String ? dayRule['start'] as String : '09:00',
    );
    final endMinutes = _parseMinutes(
      dayRule['end'] is String ? dayRule['end'] as String : '18:00',
    );

    if (startMinutes == null ||
        endMinutes == null ||
        endMinutes <= startMinutes) {
      return 'Nao existe uma janela de atendimento configurada para este dia.';
    }

    final timezone = schedule?.timezone ??
        _timezoneByProfessional[original.professionalId] ??
        'America/Sao_Paulo';
    final currentDay = _normalizeDate(
      tz.TZDateTime.from(original.startsAt, _resolveLocation(timezone)),
    );
    if (day == currentDay) {
      return 'O horario atual desta consulta nao pode ser selecionado novamente.';
    }

    return null;
  }

  Future<List<_RescheduleDaySuggestion>> _findNextAvailableRescheduleDays({
    required AppointmentItem original,
    required DateTime fromDate,
    int lookAheadDays = 21,
    int maxSuggestions = 4,
  }) async {
    final suggestions = <_RescheduleDaySuggestion>[];

    for (var offset = 1; offset <= lookAheadDays; offset++) {
      final candidateDate = _normalizeDate(
        fromDate.add(Duration(days: offset)),
      );
      final slots = await _loadRescheduleSlots(
        original: original,
        selectedDate: candidateDate,
      );
      if (slots.isEmpty) continue;

      suggestions.add(
        _RescheduleDaySuggestion(
          date: candidateDate,
          freeSlots: slots.length,
        ),
      );
      if (suggestions.length >= maxSuggestions) {
        break;
      }
    }

    return suggestions;
  }

  Future<_RescheduleSlotOption?> _pickRescheduleSlot(
    AppointmentItem original,
  ) async {
    final schedule = _scheduleByProfessional[original.professionalId];
    final timezone = schedule?.timezone ??
        _timezoneByProfessional[original.professionalId] ??
        'America/Sao_Paulo';
    final location = _resolveLocation(timezone);
    var selectedDate = _normalizeDate(
      tz.TZDateTime.from(original.startsAt, location),
    );

    List<_RescheduleSlotOption> slots = const [];
    List<_RescheduleDaySuggestion> suggestions = const [];
    _RescheduleSlotOption? selectedSlot;
    var loading = true;
    var suggestionsLoading = false;
    String? modalError;
    var initialized = false;

    return showDialog<_RescheduleSlotOption>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          Future<void> loadSlots() async {
            setModalState(() {
              loading = true;
              suggestionsLoading = false;
              modalError = null;
              selectedSlot = null;
              suggestions = const [];
            });

            try {
              final nextSlots = await _loadRescheduleSlots(
                original: original,
                selectedDate: selectedDate,
              );
              if (!ctx.mounted) return;
              setModalState(() {
                slots = nextSlots;
              });
              if (nextSlots.isEmpty) {
                setModalState(() => suggestionsLoading = true);
                final nextSuggestions = await _findNextAvailableRescheduleDays(
                  original: original,
                  fromDate: selectedDate,
                );
                if (!ctx.mounted) return;
                setModalState(() {
                  suggestions = nextSuggestions;
                });
              }
            } catch (_) {
              if (!ctx.mounted) return;
              setModalState(() {
                slots = const [];
                suggestions = const [];
                modalError = 'Nao foi possivel carregar os horarios livres.';
              });
            } finally {
              if (ctx.mounted) {
                setModalState(() {
                  loading = false;
                  suggestionsLoading = false;
                });
              }
            }
          }

          if (!initialized) {
            initialized = true;
            Future.microtask(loadSlots);
          }

          final currentLocal = tz.TZDateTime.from(original.startsAt, location);
          final currentSlotLabel =
              '${DateFormat('dd/MM/yyyy', _ptBrLocale).format(currentLocal)} • ${DateFormat('HH:mm', _ptBrLocale).format(currentLocal)}';

          final dayHint = _rescheduleDayHint(
            original: original,
            selectedDate: selectedDate,
          );

          return AlertDialog(
            title: const Text('Remarcar consulta'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${original.clientName} • ${original.serviceName}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Horario atual: $currentSlotLabel',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF66717F),
                        ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: loading
                        ? null
                        : () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: selectedDate,
                              firstDate: DateTime.now()
                                  .subtract(const Duration(days: 365)),
                              lastDate:
                                  DateTime.now().add(const Duration(days: 365)),
                            );
                            if (picked == null || !ctx.mounted) return;
                            setModalState(() {
                              selectedDate = _normalizeDate(picked);
                            });
                            await loadSlots();
                          },
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    label: Text(
                      DateFormat("EEEE, dd 'de' MMMM", _ptBrLocale)
                          .format(selectedDate),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFB),
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        border: Border.all(color: const Color(0xFFD7DDE4)),
                      ),
                      child: Text(
                        slots.isEmpty
                            ? (dayHint ??
                                'Nenhum horario livre encontrado para este dia.')
                            : '${slots.length} horarios livres encontrados. Toque em um horario para selecionar.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF5C6470),
                            ),
                      ),
                    ),
                    if (modalError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        modalError!,
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ],
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: slots.isEmpty
                          ? SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (suggestionsLoading)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 12),
                                      child:
                                          LinearProgressIndicator(minHeight: 2),
                                    ),
                                  if (!suggestionsLoading &&
                                      suggestions.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      'Proximos dias com disponibilidade',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                              fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        for (final suggestion in suggestions)
                                          ActionChip(
                                            label: Text(
                                              '${DateFormat('dd/MM', _ptBrLocale).format(suggestion.date)} • ${suggestion.freeSlots} livres',
                                            ),
                                            onPressed: () async {
                                              setModalState(() {
                                                selectedDate = _normalizeDate(
                                                    suggestion.date);
                                              });
                                              await loadSlots();
                                            },
                                            avatar: const Icon(
                                              Icons.arrow_forward_rounded,
                                              size: 18,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                  if (!suggestionsLoading &&
                                      suggestions.isEmpty &&
                                      modalError == null) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      'Nao encontramos disponibilidade nos proximos dias pesquisados.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: const Color(0xFF66717F),
                                          ),
                                    ),
                                  ],
                                ],
                              ),
                            )
                          : SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final slot in slots)
                                        ChoiceChip(
                                          label: Text(slot.label),
                                          selected: selectedSlot == slot,
                                          onSelected: (_) {
                                            setModalState(
                                                () => selectedSlot = slot);
                                          },
                                          selectedColor: AppColors.primary
                                              .withValues(alpha: 0.16),
                                          labelStyle: TextStyle(
                                            color: selectedSlot == slot
                                                ? AppColors.primary
                                                : AppColors.text,
                                            fontWeight: selectedSlot == slot
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                          ),
                                          side: BorderSide(
                                            color: selectedSlot == slot
                                                ? AppColors.primary
                                                : const Color(0xFFD7DDE4),
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              AppTheme.radiusMd,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: loading || selectedSlot == null
                    ? null
                    : () => Navigator.pop(ctx, selectedSlot),
                child: const Text('Confirmar remarcacao'),
              ),
            ],
          );
        },
      ),
    );
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
      errorMessage: 'Erro ao marcar ausência do cliente',
    );
  }

  Future<void> _handleReschedule(AppointmentItem item) async {
    final selectedSlot = await _pickRescheduleSlot(item);
    if (selectedSlot == null) return;

    setState(() {
      _actionLoading = true;
      _error = null;
    });
    try {
      await _appointmentService.rescheduleAppointment(
        original: item,
        newStartsAt: selectedSlot.startsAtUtc,
        newEndsAt: selectedSlot.endsAtUtc,
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
            'Sem consentimento ativo de localização para esta consulta. Registre o consentimento antes de monitorar.';
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
            labelText: 'Tempo estimado de chegada em minutos',
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
          title: const Text('Consentimento de localização'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${item.clientName} • ${item.serviceName}',
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
                  labelText: 'Versão do termo',
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

  Future<void> _handleMonthDayTap(DateTime day) async {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    if (normalizedDay.month == _selectedDate.month &&
        normalizedDay.year == _selectedDate.year) {
      setState(() => _selectedDate = normalizedDay);
      return;
    }

    setState(() => _selectedDate = normalizedDay);
    await _loadAppointments();
  }

  Widget _buildCalendarView() {
    final days = _calendarDays();
    final stats = _dailyStats();
    final appointmentsByDay = _appointmentsByDay();
    final currentMonth = _selectedDate.month;
    final selectedKey = _dateKey(_selectedDate);
    final selectedStats = stats[selectedKey] ?? (occupied: 0, free: 0);
    final selectedAppointments = appointmentsByDay[selectedKey] ?? const [];
    const weekdayLabels = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sab', 'Dom'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cellWidth = (constraints.maxWidth - (6 * 6)) / 7;
                  final cellHeight = cellWidth.clamp(54.0, 78.0).toDouble();

                  return Column(
                    children: [
                      Row(
                        children: [
                          for (final label in weekdayLabels)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  label,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(
                                        color: const Color(0xFF66717F),
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: days.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
                          childAspectRatio: cellWidth / cellHeight,
                        ),
                        itemBuilder: (_, index) {
                          final day = days[index];
                          final key = _dateKey(day);
                          final dayStats = stats[key] ?? (occupied: 0, free: 0);
                          final isCurrentMonth = day.month == currentMonth;
                          final isSelected = selectedKey == key;
                          final isToday = _dateKey(DateTime.now()) == key;
                          final hasAppointments = dayStats.occupied > 0;
                          final isFull =
                              dayStats.occupied > 0 && dayStats.free == 0;

                          Color background = Colors.white;
                          Color border = const Color(0xFFD7DDE4);
                          Color dayColor = AppColors.text;

                          if (!isCurrentMonth) {
                            background = const Color(0xFFF7F8FA);
                            dayColor = const Color(0xFF9AA3AE);
                          } else if (isFull) {
                            background =
                                AppColors.secondary.withValues(alpha: 0.12);
                          } else if (hasAppointments) {
                            background =
                                AppColors.primary.withValues(alpha: 0.06);
                          }

                          if (isToday) {
                            border = AppColors.secondary;
                          }

                          if (isSelected) {
                            background = AppColors.primary;
                            border = AppColors.primary;
                            dayColor = Colors.white;
                          }

                          return InkWell(
                            onTap: () => _handleMonthDayTap(day),
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusMd),
                            child: Container(
                              decoration: BoxDecoration(
                                color: background,
                                borderRadius:
                                    BorderRadius.circular(AppTheme.radiusMd),
                                border: Border.all(
                                  color: border,
                                  width: isSelected || isToday ? 1.5 : 1,
                                ),
                              ),
                              padding: const EdgeInsets.all(6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          day.day.toString(),
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelLarge
                                              ?.copyWith(
                                                color: dayColor,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                      if (hasAppointments)
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? Colors.white
                                                : isFull
                                                    ? AppColors.secondary
                                                    : AppColors.accent,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _dayHeader(_selectedDate),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatShortDate(_selectedDate),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: const Color(0xFF66717F)),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _openDay(_selectedDate),
                        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                        label: const Text('Ver dia'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildAgendaBadge(
                        label: '${selectedStats.occupied} atendimentos',
                        background: AppColors.secondary.withValues(alpha: 0.12),
                        border: AppColors.secondary.withValues(alpha: 0.35),
                        text: const Color(0xFF0F666A),
                      ),
                      _buildAgendaBadge(
                        label: '${selectedStats.free} horários livres',
                        background: const Color(0xFFF0F2F5),
                        border: const Color(0xFFD8DEE5),
                        text: const Color(0xFF4B5766),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (selectedAppointments.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFB),
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        border: Border.all(color: const Color(0xFFD7DDE4)),
                      ),
                      child: Text(
                        'Nenhum atendimento listado para este dia.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF66717F),
                            ),
                      ),
                    )
                  else
                    Column(
                      children: [
                        for (final item in selectedAppointments.take(3)) ...[
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusMd),
                              border:
                                  Border.all(color: const Color(0xFFD7DDE4)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(
                                      AppTheme.radiusMd,
                                    ),
                                  ),
                                  child: Text(
                                    _formatTime(
                                      item.startsAt,
                                      _timezoneByProfessional[
                                              item.professionalId] ??
                                          'America/Sao_Paulo',
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.clientName,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${item.serviceName} • ${item.professionalName}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: const Color(0xFF66717F),
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (selectedAppointments.length > 3)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '+${selectedAppointments.length - 3} atendimentos neste dia',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: const Color(0xFF66717F),
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekView() {
    final days = _calendarDays();
    final stats = _dailyStats();
    final appointmentsByDay = _appointmentsByDay();
    final selectedKey = _dateKey(_selectedDate);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: days.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, index) {
          final day = days[index];
          final key = _dateKey(day);
          final dayStats = stats[key] ?? (occupied: 0, free: 0);
          final dayAppointments = appointmentsByDay[key] ?? const [];
          final isSelected = selectedKey == key;
          final isToday = _dateKey(DateTime.now()) == key;

          return InkWell(
            onTap: () => _openDay(day),
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            child: Card(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary
                        : const Color(0xFFD7DDE4),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 54,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isToday
                                  ? AppColors.primary
                                  : AppColors.surface,
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusMd),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  [
                                    'DOM',
                                    'SEG',
                                    'TER',
                                    'QUA',
                                    'QUI',
                                    'SEX',
                                    'SAB'
                                  ][_weekdayIndex0to6(day)],
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: isToday
                                            ? Colors.white
                                            : const Color(0xFF66717F),
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  day.day.toString().padLeft(2, '0'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        color: isToday
                                            ? Colors.white
                                            : AppColors.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _formatShortDate(day),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _buildAgendaBadge(
                                      label:
                                          '${dayStats.occupied} atendimentos',
                                      background: AppColors.secondary
                                          .withValues(alpha: 0.12),
                                      border: AppColors.secondary
                                          .withValues(alpha: 0.35),
                                      text: const Color(0xFF0F666A),
                                    ),
                                    _buildAgendaBadge(
                                      label: '${dayStats.free} horários livres',
                                      background: const Color(0xFFF0F2F5),
                                      border: const Color(0xFFD8DEE5),
                                      text: const Color(0xFF4B5766),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _openDay(day),
                            icon: const Icon(
                              Icons.arrow_forward_rounded,
                              size: 18,
                            ),
                            label: const Text('Ver dia'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (dayAppointments.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFB),
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusMd),
                            border: Border.all(color: const Color(0xFFD7DDE4)),
                          ),
                          child: Text(
                            'Sem atendimentos listados para este dia.',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: const Color(0xFF66717F),
                                    ),
                          ),
                        )
                      else
                        Column(
                          children: [
                            for (final item in dayAppointments.take(4)) ...[
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius:
                                      BorderRadius.circular(AppTheme.radiusMd),
                                  border: Border.all(
                                    color: const Color(0xFFD7DDE4),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(
                                          AppTheme.radiusMd,
                                        ),
                                      ),
                                      child: Text(
                                        _formatTime(
                                          item.startsAt,
                                          _timezoneByProfessional[
                                                  item.professionalId] ??
                                              'America/Sao_Paulo',
                                        ),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(
                                              color: AppColors.primary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.clientName,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${item.serviceName} • ${item.professionalName}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color:
                                                      const Color(0xFF66717F),
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (dayAppointments.length > 4)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '+${dayAppointments.length - 4} atendimentos neste dia',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: const Color(0xFF66717F),
                                        fontWeight: FontWeight.w500,
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
          );
        },
      ),
    );
  }

  Widget _buildDayList() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
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
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${item.serviceName} - ${item.clientName}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_formatTime(item.startsAt, timezone)} - ${_formatTime(item.endsAt, timezone)} (${item.professionalName})',
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _punctualityDetail(item),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: const Color(0xFF5C6470),
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  _buildAgendaBadge(
                                    label: consent.label,
                                    background: consent.background,
                                    border: consent.border,
                                    text: consent.text,
                                  ),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                        minWidth: 120, maxWidth: 220),
                                    child: Text(
                                      consent.detail,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: const Color(0xFF5C6470),
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          enabled: !_actionLoading,
                          onSelected: (value) async {
                            if (value == 'reschedule') {
                              await _handleReschedule(item);
                            }
                            if (value == 'cancel') {
                              await _handleCancel(item);
                            }
                            if (value == 'complete') {
                              await _handleComplete(item);
                            }
                            if (value == 'no_show') {
                              await _handleNoShow(item);
                            }
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
                                child: const Text('Não compareceu'),
                              ),
                            ];
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildAgendaBadge(
                          label: status.label,
                          background: status.background,
                          border: status.border,
                          text: status.text,
                        ),
                        _buildAgendaBadge(
                          label: punctuality.label,
                          background: punctuality.background,
                          border: punctuality.border,
                          text: punctuality.text,
                        ),
                      ],
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

  Widget _buildAgendaBadge({
    required String label,
    required Color background,
    required Color border,
    required Color text,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: text,
          fontWeight: FontWeight.w500,
          fontSize: 12,
        ),
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
                  final payloadClientName =
                      (alert.payload['client_name'] as String?)?.trim();
                  final payloadServiceName =
                      (alert.payload['service_name'] as String?)?.trim();
                  final title = appointment != null
                      ? '${appointment.clientName} • ${appointment.serviceName}'
                      : payloadClientName != null &&
                              payloadClientName.isNotEmpty
                          ? payloadServiceName != null &&
                                  payloadServiceName.isNotEmpty
                              ? '$payloadClientName • $payloadServiceName'
                              : payloadClientName
                          : 'Cliente da consulta';

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
                                alert.isRead ? 'Lido' : 'Não lido',
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
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppTheme.radiusMd),
                                ),
                              ),
                              onPressed: _alertsLoading
                                  ? null
                                  : () => _markAlertAsRead(alert),
                              icon: const Icon(Icons.done_rounded, size: 18),
                              label: const Text('Marcar como lido'),
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

  Future<void> _refreshAgenda() async {
    if (_actionLoading) return;
    await _loadAppointments(partial: _viewMode != AgendaViewMode.day);
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
            onPressed: _refreshAgenda,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/appointments/new')
                .then((_) => _refreshAgenda()),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAgenda,
        child: _loading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 220),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _error != null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 220),
                      Center(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: AppColors.danger),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
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
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
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
                                        value: 'done',
                                        child: Text('Concluído')),
                                    DropdownMenuItem(
                                        value: 'no_show',
                                        child: Text('Não compareceu')),
                                  ],
                                  onChanged: (value) async {
                                    setState(
                                        () => _selectedStatus = value ?? '');
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
                                            color:
                                                _viewMode == AgendaViewMode.day
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
                                          'Mês',
                                          style: TextStyle(
                                            color: _viewMode ==
                                                    AgendaViewMode.month
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
                                                _agendaDateLabel(),
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
                              ],
                            ),
                          ),
                        ),
                      ),
                      _buildPunctualityAlerts(),
                      _buildAgendaRangeViewport(),
                    ],
                  ),
      ),
    );
  }
}
