import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile/screens/agenda_screen.dart';
import 'package:mobile/screens/client_area_screen.dart';
import 'package:mobile/screens/create_appointment_screen.dart';
import 'package:mobile/screens/login_screen.dart';
import 'package:mobile/screens/onboarding_screen.dart';
import 'package:mobile/screens/professional_menu_screen.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  runApp(const _BootstrapApp());
}

class AgendaProfissionalApp extends StatelessWidget {
  const AgendaProfissionalApp({super.key, this.bootstrapError});

  final String? bootstrapError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Agenda Profissional',
      theme: AppTheme.light(),
      initialRoute: '/',
      routes: {
        '/': (_) => SessionGate(bootstrapError: bootstrapError),
        '/login': (_) => const LoginScreen(),
        '/onboarding': (_) => const OnboardingScreen(),
        '/menu': (_) => const ProfessionalMenuScreen(),
        '/agenda': (_) => const AgendaScreen(),
        '/client-area': (_) => const ClientAreaScreen(),
        '/appointments/new': (_) => const CreateAppointmentScreen(),
      },
    );
  }
}

class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();

  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  bool _ready = false;
  String? _bootstrapError;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final defaultSupabaseUrl = kIsWeb
        ? 'http://127.0.0.1:54321'
        : Platform.isAndroid
            ? 'http://10.0.2.2:54321'
            : 'http://127.0.0.1:54321';
    final supabaseUrl =
        const String.fromEnvironment('SUPABASE_URL', defaultValue: '')
                .isNotEmpty
            ? const String.fromEnvironment('SUPABASE_URL')
            : defaultSupabaseUrl;
    const defaultLocalAnonKey =
        'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';
    final supabaseAnonKey =
        const String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '')
                .isNotEmpty
            ? const String.fromEnvironment('SUPABASE_ANON_KEY')
            : defaultLocalAnonKey;

    try {
      await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey)
          .timeout(
        const Duration(seconds: 12),
      );
    } catch (error) {
      _bootstrapError =
          'Falha ao iniciar o app. Verifique SUPABASE_URL/SUPABASE_ANON_KEY e conectividade. ($error)';
    }

    if (!mounted) return;
    setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return MaterialApp(
        title: 'Agenda Profissional',
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return AgendaProfissionalApp(bootstrapError: _bootstrapError);
  }
}

class SessionGate extends StatelessWidget {
  const SessionGate({super.key, this.bootstrapError});

  final String? bootstrapError;

  @override
  Widget build(BuildContext context) {
    if (bootstrapError != null) {
      return _BootstrapErrorScreen(message: bootstrapError!);
    }

    final session = Supabase.instance.client.auth.currentSession;
    final authService = AuthService();

    if (session == null) {
      return const LoginScreen();
    }

    final path = authService.resolveAccessPath(authService.currentUser);
    if (path == AccessPath.client) {
      return const ClientAreaScreen();
    }

    return const ProfessionalMenuScreen();
  }
}

class _BootstrapErrorScreen extends StatelessWidget {
  const _BootstrapErrorScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Erro de inicializacao')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Nao foi possivel carregar o aplicativo.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(message),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
