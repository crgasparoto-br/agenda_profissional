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
  String? _error;
  List<AppointmentItem> _appointments = [];
  List<OptionItem> _professionals = [];
  Map<String, String> _timezoneByProfessional = {};
  DateTime _selectedDate = DateTime.now();
  AgendaViewMode _viewMode = AgendaViewMode.day;
  String? _selectedProfessionalId;

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

  ({Color background, Color border, Color text, String label}) _statusVisual(String status) {
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
      case 'pending':
        return (
          background: Colors.white,
          border: const Color(0xFFC9D1DA),
          text: const Color(0xFF5C6470),
          label: 'Pendente',
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
      final professionalIds = items.map((item) => item.professionalId).toSet().toList();
      final timezoneByProfessional = await _appointmentService.getProfessionalTimezones(professionalIds);
      setState(() {
        _appointments = items;
        _timezoneByProfessional = timezoneByProfessional;
      });
    } catch (_) {
      setState(() => _error = 'Erro ao carregar agenda');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadProfessionals();
    _loadAppointments();
  }

  Future<void> _loadProfessionals() async {
    final professionals = await _catalogService.listProfessionals();
    if (!mounted) return;
    setState(() => _professionals = professionals);
  }

  String _formatShortDate(DateTime value) {
    final dd = value.day.toString().padLeft(2, '0');
    final mm = value.month.toString().padLeft(2, '0');
    final yyyy = value.year.toString();
    return '$dd/$mm/$yyyy';
  }

  ({DateTime start, DateTime end}) _currentRange() {
    final anchor = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    if (_viewMode == AgendaViewMode.day) {
      return (start: anchor, end: anchor.add(const Duration(days: 1)));
    }
    if (_viewMode == AgendaViewMode.week) {
      final weekday = anchor.weekday; // 1..7
      final monday = anchor.subtract(Duration(days: weekday - 1));
      return (start: monday, end: monday.add(const Duration(days: 7)));
    }
    final monthStart = DateTime(anchor.year, anchor.month, 1);
    final nextMonth = DateTime(anchor.year, anchor.month + 1, 1);
    return (start: monthStart, end: nextMonth);
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
      setState(() => _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + days, _selectedDate.day));
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
    return 'Mes anterior';
  }

  String _nextLabel() {
    if (_viewMode == AgendaViewMode.day) return 'Proximo dia';
    if (_viewMode == AgendaViewMode.week) return 'Proxima semana';
    return 'Proximo mes';
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
            onPressed: () => Navigator.pushNamed(context, '/appointments/new').then((_) => _loadAppointments()),
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
                                decoration: const InputDecoration(labelText: 'Profissional'),
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
                                  setState(() => _selectedProfessionalId = value);
                                  await _loadAppointments();
                                },
                              ),
                              const SizedBox(width: 8),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => _setViewMode(AgendaViewMode.day),
                                      style: OutlinedButton.styleFrom(
                                        backgroundColor: _viewMode == AgendaViewMode.day ? AppColors.primary : null,
                                      ),
                                      child: Text(
                                        'Dia',
                                        style: TextStyle(
                                          color: _viewMode == AgendaViewMode.day ? Colors.white : null,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => _setViewMode(AgendaViewMode.week),
                                      style: OutlinedButton.styleFrom(
                                        backgroundColor: _viewMode == AgendaViewMode.week ? AppColors.primary : null,
                                      ),
                                      child: Text(
                                        'Semana',
                                        style: TextStyle(
                                          color: _viewMode == AgendaViewMode.week ? Colors.white : null,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => _setViewMode(AgendaViewMode.month),
                                      style: OutlinedButton.styleFrom(
                                        backgroundColor: _viewMode == AgendaViewMode.month ? AppColors.primary : null,
                                      ),
                                      child: Text(
                                        'Mes',
                                        style: TextStyle(
                                          color: _viewMode == AgendaViewMode.month ? Colors.white : null,
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
                                onPressed: () => _shiftAgendaDate(_viewMode == AgendaViewMode.week ? -7 : -1),
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
                                        const Icon(Icons.calendar_today, size: 16),
                                        const SizedBox(width: 6),
                                        Text(
                                          _formatShortDate(_selectedDate),
                                          style: Theme.of(context).textTheme.titleMedium,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: _nextLabel(),
                                onPressed: () => _shiftAgendaDate(_viewMode == AgendaViewMode.week ? 7 : 1),
                                icon: const Icon(Icons.chevron_right),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemBuilder: (_, index) {
                          final item = _appointments[index];
                          final status = _statusVisual(item.status);
                          final timezone = _timezoneByProfessional[item.professionalId] ?? 'America/Sao_Paulo';

                          return Card(
                            child: ListTile(
                              title: Text('${item.serviceName} - ${item.clientName}'),
                              subtitle: Text(
                                '${_formatTime(item.startsAt, timezone)} - ${_formatTime(item.endsAt, timezone)} (${item.professionalName})',
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                            ),
                          );
                        },
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemCount: _appointments.length,
                      ),
                    ),
                  ],
                ),
    );
  }
}

