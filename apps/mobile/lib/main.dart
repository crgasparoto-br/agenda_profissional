import 'package:flutter/material.dart';
import 'package:mobile/screens/agenda_screen.dart';
import 'package:mobile/screens/client_area_screen.dart';
import 'package:mobile/screens/create_appointment_screen.dart';
import 'package:mobile/screens/login_screen.dart';
import 'package:mobile/screens/onboarding_screen.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'http://127.0.0.1:56021');
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

    return const OnboardingScreen();
  }
}

