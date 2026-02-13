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
  String? _error;

  List<AppointmentItem> _appointments = [];
  List<OptionItem> _professionals = [];
  Map<String, String> _timezoneByProfessional = {};
  Map<String, ProfessionalScheduleSettings> _scheduleByProfessional = {};
  Map<String, int> _slotMinutesByProfessional = {};

  DateTime _selectedDate = DateTime.now();
  AgendaViewMode _viewMode = AgendaViewMode.day;
  String? _selectedProfessionalId;
  String _selectedStatus = '';

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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancelar')),
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
      errorMessage: 'Erro ao marcar não compareceu',
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
          final timezone = _timezoneByProfessional[item.professionalId] ??
              'America/Sao_Paulo';

          return Card(
            child: ListTile(
              title: Text('${item.serviceName} - ${item.clientName}'),
              subtitle: Text(
                '${_formatTime(item.startsAt, timezone)} - ${_formatTime(item.endsAt, timezone)} (${item.professionalName})',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    enabled: !_actionLoading,
                    onSelected: (value) async {
                      if (value == 'reschedule') await _handleReschedule(item);
                      if (value == 'cancel') await _handleCancel(item);
                      if (value == 'complete') await _handleComplete(item);
                      if (value == 'no_show') await _handleNoShow(item);
                    },
                    itemBuilder: (_) {
                      final disabled = _isFinalStatus(item.status);
                      return [
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
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemCount: _filteredAppointments.length,
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
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            children: [
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
                                        'Mês',
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
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: _previousLabel(),
                                onPressed: () => _shiftAgendaDate(
                                    _viewMode == AgendaViewMode.week ? -7 : -1),
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
                                    _viewMode == AgendaViewMode.week ? 7 : 1),
                                icon: const Icon(Icons.chevron_right),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: _actionLoading ? null : _loadAppointments,
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Atualizar agenda'),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 190,
                                child: DropdownButtonFormField<String>(
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
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_viewMode == AgendaViewMode.day)
                      _buildDayList()
                    else
                      _buildCalendarView(),
                  ],
                ),
    );
  }
}
