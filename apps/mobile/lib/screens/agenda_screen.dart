import 'package:flutter/material.dart';
import 'package:mobile/theme/app_theme.dart';

import '../models/appointment.dart';
import '../services/appointment_service.dart';

class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  final _appointmentService = AppointmentService();
  bool _loading = false;
  String? _error;
  List<AppointmentItem> _appointments = [];

  String _formatTime(DateTime dateTime) {
    final hh = dateTime.hour.toString().padLeft(2, '0');
    final mm = dateTime.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  ({Color background, Color border, Color text, String label}) _statusVisual(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed':
        return (
          background: AppColors.secondary.withOpacity(0.14),
          border: AppColors.secondary.withOpacity(0.4),
          text: const Color(0xFF0F666A),
          label: 'Confirmado',
        );
      case 'cancelled':
        return (
          background: AppColors.danger.withOpacity(0.12),
          border: AppColors.danger.withOpacity(0.35),
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
      final items = await _appointmentService.getDailyAppointments(DateTime.now());
      setState(() {
        _appointments = items;
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
    _loadAppointments();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agenda do dia'),
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
                    style: TextStyle(color: AppColors.danger),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemBuilder: (_, index) {
                    final item = _appointments[index];
                    final status = _statusVisual(item.status);

                    return Card(
                      child: ListTile(
                        title: Text('${item.serviceName} - ${item.clientName}'),
                        subtitle: Text(
                          '${_formatTime(item.startsAt)} - ${_formatTime(item.endsAt)} (${item.professionalName})',
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
    );
  }
}
