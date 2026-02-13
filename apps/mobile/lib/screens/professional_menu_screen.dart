import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';

class ProfessionalMenuScreen extends StatefulWidget {
  const ProfessionalMenuScreen({super.key});

  @override
  State<ProfessionalMenuScreen> createState() => _ProfessionalMenuScreenState();
}

class _ProfessionalMenuScreenState extends State<ProfessionalMenuScreen> {
  final _authService = AuthService();
  bool _cadastrosExpanded = false;
  bool _configExpanded = false;
  String _tenantName = 'Agenda Profissional';
  String? _logoUrl;
  String? _profileName;

  @override
  void initState() {
    super.initState();
    _loadTenantBranding();
  }

  Future<void> _loadTenantBranding() async {
    final user = _authService.currentUser;
    if (user == null) return;

    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('full_name, tenant_id')
          .eq('id', user.id)
          .maybeSingle();
      if (profile == null) return;

      final tenantId = profile['tenant_id'] as String?;
      if (tenantId == null || tenantId.isEmpty) return;

      final tenant = await Supabase.instance.client
          .from('tenants')
          .select('name, logo_url')
          .eq('id', tenantId)
          .maybeSingle();
      if (tenant == null || !mounted) return;

      setState(() {
        _tenantName = (tenant['name'] as String?) ?? 'Agenda Profissional';
        _logoUrl = tenant['logo_url'] as String?;
        _profileName = profile['full_name'] as String?;
      });
    } catch (_) {
      // Mantem fallback visual padrão do app.
    }
  }

  Future<void> _signOut() async {
    await _authService.signOut();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agenda'),
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
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _logoUrl != null && _logoUrl!.isNotEmpty
                    ? Image.network(
                        _logoUrl!,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Image.asset(
                          'assets/brand/agenda-logo.png',
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Image.asset(
                        'assets/brand/agenda-logo.png',
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                      ),
              ),
              title: Text(_tenantName),
              subtitle: Text(_profileName ?? 'Profissional'),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('Agenda'),
              subtitle: const Text('Visualize agendamentos por dia, semana ou mês'),
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
            child: ExpansionTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('Cadastros'),
              trailing: Icon(_cadastrosExpanded ? Icons.expand_less : Icons.chevron_right),
              onExpansionChanged: (value) => setState(() => _cadastrosExpanded = value),
              children: [
                ListTile(
                  leading: const Icon(Icons.group_outlined),
                  title: const Text('Clientes'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pushNamed(context, '/clients'),
                ),
                ListTile(
                  leading: const Icon(Icons.spa_outlined),
                  title: const Text('Serviços'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pushNamed(context, '/services'),
                ),
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('Profissionais'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pushNamed(context, '/professionals'),
                ),
                ListTile(
                  leading: const Icon(Icons.schedule_outlined),
                  title: const Text('Horários'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pushNamed(context, '/schedules'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.tune_outlined),
              title: const Text('Configurações'),
              trailing: Icon(_configExpanded ? Icons.expand_less : Icons.chevron_right),
              onExpansionChanged: (value) => setState(() => _configExpanded = value),
              children: [
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Configuração inicial'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pushNamed(context, '/onboarding'),
                ),
                ListTile(
                  leading: const Icon(Icons.smart_toy_outlined),
                  title: const Text('WhatsApp + IA'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pushNamed(context, '/whatsapp'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
