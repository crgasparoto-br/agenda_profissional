import 'package:flutter/material.dart';

import '../models/app_exception.dart';
import '../models/bootstrap_tenant.dart';
import '../services/auth_service.dart';
import '../services/onboarding_service.dart';
import '../theme/app_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _tenantNameController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _authService = AuthService();
  final _onboardingService = OnboardingService();

  TenantType _tenantType = TenantType.individual;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _tenantNameController.dispose();
    _fullNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _onboardingService.bootstrapTenant(
        BootstrapTenantInput(
          tenantType: _tenantType,
          tenantName: _tenantNameController.text.trim(),
          fullName: _fullNameController.text.trim(),
          phone: _phoneController.text.trim(),
        ),
      );

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/agenda');
    } on AppException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Erro ao executar onboarding');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _skipIfProfileExists() async {
    final user = _authService.currentUser;
    if (user == null) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    final exists = await _onboardingService.profileExists(user.id);

    if (!mounted) return;
    if (exists) {
      Navigator.pushReplacementNamed(context, '/agenda');
    }
  }

  @override
  void initState() {
    super.initState();
    _skipIfProfileExists();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Onboarding'),
        actions: [
          IconButton(
            onPressed: () async {
              await _authService.signOut();
              if (!context.mounted) return;
              Navigator.pushReplacementNamed(context, '/login');
            },
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Configure sua conta', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  const Text('Organize sua agenda e inicie os agendamentos.'),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<TenantType>(
                    initialValue: _tenantType,
                    decoration: const InputDecoration(labelText: 'Tipo de contratacao'),
                    items: const [
                      DropdownMenuItem(value: TenantType.individual, child: Text('Individual')),
                      DropdownMenuItem(value: TenantType.group, child: Text('Grupo (clinica)')),
                    ],
                    onChanged: (value) => setState(() => _tenantType = value ?? TenantType.individual),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tenantNameController,
                    decoration: const InputDecoration(labelText: 'Nome do tenant'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _fullNameController,
                    decoration: const InputDecoration(labelText: 'Nome completo'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phoneController,
                    decoration: const InputDecoration(labelText: 'Telefone'),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    child: Text(_loading ? 'Processando...' : 'Concluir onboarding'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        border: Border.all(color: AppColors.danger.withOpacity(0.35)),
                      ),
                      child: Text(_error!, style: const TextStyle(color: Color(0xFF702621))),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
