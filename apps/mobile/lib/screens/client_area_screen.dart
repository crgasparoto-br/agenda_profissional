import 'package:flutter/material.dart';
import 'package:mobile/services/auth_service.dart';

class ClientAreaScreen extends StatefulWidget {
  const ClientAreaScreen({super.key});

  @override
  State<ClientAreaScreen> createState() => _ClientAreaScreenState();
}

class _ClientAreaScreenState extends State<ClientAreaScreen> {
  final _authService = AuthService();

  Future<void> _signOut() async {
    await _authService.signOut();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    final email = _authService.currentUser?.email ?? '-';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Area do cliente'),
        actions: [
          IconButton(
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bem-vindo(a)', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text('Conta: $email'),
                  const SizedBox(height: 10),
                  const Text(
                    'Este caminho e dedicado ao cliente final. '
                    'Proximo passo: listar agendamentos e reagendamentos do cliente.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
