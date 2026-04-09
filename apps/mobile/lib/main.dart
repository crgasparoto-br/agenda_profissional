import 'dart:io' show Platform;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile/screens/agenda_screen.dart';
import 'package:mobile/screens/client_area_screen.dart';
import 'package:mobile/screens/clients_screen.dart';
import 'package:mobile/screens/create_appointment_screen.dart';
import 'package:mobile/screens/login_screen.dart';
import 'package:mobile/screens/onboarding_screen.dart';
import 'package:mobile/screens/punctuality_audit_screen.dart';
import 'package:mobile/screens/professional_menu_screen.dart';
import 'package:mobile/screens/professionals_screen.dart';
import 'package:mobile/screens/push_settings_screen.dart';
import 'package:mobile/screens/schedules_screen.dart';
import 'package:mobile/screens/services_screen.dart';
import 'package:mobile/screens/whatsapp_settings_screen.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/services/biometric_auth_service.dart';
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
      builder: (context, child) => AppLockGate(child: child ?? const SizedBox.shrink()),
      initialRoute: '/',
      routes: {
        '/': (_) => SessionGate(bootstrapError: bootstrapError),
        '/login': (_) => const LoginScreen(),
        '/onboarding': (_) => const OnboardingScreen(),
        '/menu': (_) => const ProfessionalMenuScreen(),
        '/agenda': (_) => const AgendaScreen(),
        '/auditoria-pontualidade': (_) => const PunctualityAuditScreen(),
        '/client-area': (_) => const ClientAreaScreen(),
        '/appointments/new': (_) => const CreateAppointmentScreen(),
        '/clients': (_) => const ClientsScreen(),
        '/services': (_) => const ServicesScreen(),
        '/professionals': (_) => const ProfessionalsScreen(),
        '/schedules': (_) => const SchedulesScreen(),
        '/whatsapp': (_) => const WhatsappSettingsScreen(),
        '/push': (_) => const PushSettingsScreen(),
      },
    );
  }
}

class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  final _authService = AuthService();
  final _biometricAuthService = BiometricAuthService();

  StreamSubscription<AuthState>? _authSubscription;
  bool _biometricEnabled = false;
  bool _locked = false;
  bool _checkingAvailability = true;
  bool _unlockInProgress = false;
  bool _resumeRequiresUnlock = false;
  String? _unlockError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen(_onAuthStateChanged);
    _initializeLockState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      if (_hasActiveSession() && _biometricEnabled) {
        _resumeRequiresUnlock = true;
      }
    }

    if (state == AppLifecycleState.resumed && _resumeRequiresUnlock) {
      _resumeRequiresUnlock = false;
      _lockAndPrompt();
    }
  }

  Future<void> _initializeLockState() async {
    final biometricEnabled = await _biometricAuthService.isEnabled();
    if (!mounted) return;

    setState(() {
      _biometricEnabled = biometricEnabled;
      _checkingAvailability = false;
      _locked = _hasActiveSession() && biometricEnabled;
    });

    if (_locked) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _unlockSession());
    }
  }

  void _onAuthStateChanged(AuthState authState) {
    final event = authState.event;
    final hasSession = authState.session != null;

    if (!mounted) return;

    if (!hasSession) {
      setState(() {
        _locked = false;
        _unlockInProgress = false;
        _unlockError = null;
      });
      return;
    }

    if (event == AuthChangeEvent.signedIn) {
      setState(() {
        _locked = false;
        _unlockError = null;
      });
    }
  }

  bool _hasActiveSession() {
    return Supabase.instance.client.auth.currentSession != null;
  }

  Future<void> _lockAndPrompt() async {
    if (!_hasActiveSession() || !_biometricEnabled || _unlockInProgress) return;

    setState(() {
      _locked = true;
      _unlockError = null;
    });

    await _unlockSession();
  }

  Future<void> _unlockSession() async {
    if (!_locked || _unlockInProgress || !_hasActiveSession()) return;

    setState(() {
      _unlockInProgress = true;
      _unlockError = null;
    });

    try {
      final authenticated = await _biometricAuthService.authenticate();
      if (!mounted) return;

      if (authenticated) {
        setState(() {
          _locked = false;
          _unlockError = null;
        });
      } else {
        setState(() {
          _unlockError = 'Confirme sua biometria para voltar ao app.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _unlockError =
            'Nao foi possivel validar a biometria agora. Tente novamente.';
      });
    } finally {
      if (mounted) {
        setState(() => _unlockInProgress = false);
      }
    }
  }

  Future<void> _signOutFromLock() async {
    await _authService.signOut();
    if (!mounted) return;
    setState(() {
      _locked = false;
      _unlockError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAvailability || !_locked || !_hasActiveSession()) {
      return widget.child;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        ColoredBox(
          color: AppColors.background.withValues(alpha: 0.96),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: AppColors.secondary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                            ),
                            child: const Icon(
                              Icons.fingerprint_rounded,
                              color: AppColors.secondary,
                              size: 32,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Desbloqueie sua agenda',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Use a biometria para continuar com seguranca no Agenda Profissional.',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: const Color(0xFF66717F),
                                ),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: _unlockInProgress ? null : _unlockSession,
                            icon: const Icon(Icons.lock_open_rounded),
                            label: Text(
                              _unlockInProgress
                                  ? 'Validando biometria...'
                                  : 'Desbloquear com biometria',
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _unlockInProgress ? null : _signOutFromLock,
                            child: const Text('Sair desta conta'),
                          ),
                          if (_unlockError != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.danger.withValues(alpha: 0.12),
                                borderRadius:
                                    BorderRadius.circular(AppTheme.radiusMd),
                                border: Border.all(
                                  color:
                                      AppColors.danger.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Text(
                                _unlockError!,
                                style: const TextStyle(color: Color(0xFF702621)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
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

    return const AgendaScreen();
  }
}

class _BootstrapErrorScreen extends StatelessWidget {
  const _BootstrapErrorScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Erro de inicialização')),
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
                  'Não foi possível carregar o aplicativo.',
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
