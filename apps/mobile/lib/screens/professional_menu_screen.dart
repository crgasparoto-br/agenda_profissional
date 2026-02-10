import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class ProfessionalMenuScreen extends StatefulWidget {
  const ProfessionalMenuScreen({super.key});

  @override
  State<ProfessionalMenuScreen> createState() => _ProfessionalMenuScreenState();
}

class _ProfessionalMenuScreenState extends State<ProfessionalMenuScreen> {
  final _authService = AuthService();

  Future<void> _signOut() async {
    await _authService.signOut();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Menu principal'),
        actions: [
          IconButton(
            tooltip: 'Sair',
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('Agenda'),
              subtitle: const Text('Visualize agendamentos por dia, semana ou mes'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/agenda'),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Novo agendamento'),
              subtitle: const Text('Crie um novo agendamento'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/appointments/new'),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Configuracao inicial'),
              subtitle: const Text('Atualize dados da organizacao'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/onboarding'),
            ),
          ),
        ],
      ),
    );
  }
}
