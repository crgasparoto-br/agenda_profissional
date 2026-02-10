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

  final defaultSupabaseUrl = kIsWeb
      ? 'http://127.0.0.1:54321'
      : Platform.isAndroid
          ? 'http://10.0.2.2:54321'
          : 'http://127.0.0.1:54321';
  final supabaseUrl = const String.fromEnvironment('SUPABASE_URL', defaultValue: '').isNotEmpty
      ? const String.fromEnvironment('SUPABASE_URL')
      : defaultSupabaseUrl;
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'your-anon-key');

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

  runApp(const AgendaProfissionalApp());
}

class AgendaProfissionalApp extends StatelessWidget {
  const AgendaProfissionalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Agenda Profissional',
      theme: AppTheme.light(),
      initialRoute: '/',
      routes: {
        '/': (_) => const SessionGate(),
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

class SessionGate extends StatelessWidget {
  const SessionGate({super.key});

  @override
  Widget build(BuildContext context) {
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

