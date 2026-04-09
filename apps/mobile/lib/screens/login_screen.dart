import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../services/biometric_auth_service.dart';
import '../services/onboarding_service.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _nameController = TextEditingController();
  final _authService = AuthService();
  final _onboardingService = OnboardingService();
  final _biometricAuthService = BiometricAuthService();

  bool _loading = false;
  bool _isSignUp = false;
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _useBiometricOnThisDevice = false;
  String? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBiometricState();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadBiometricState() async {
    final available = await _biometricAuthService.isAvailable();
    final enabled = available && await _biometricAuthService.isEnabled();
    if (!mounted) return;

    setState(() {
      _biometricAvailable = available;
      _biometricEnabled = enabled;
      _useBiometricOnThisDevice = enabled;
    });
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
      _status = null;
    });

    try {
      if (_isSignUp) {
        if (_passwordController.text.length < 6) {
          setState(() => _error = 'A senha deve ter pelo menos 6 caracteres');
          return;
        }

        if (_passwordController.text != _confirmController.text) {
          setState(() => _error = 'As senhas não conferem');
          return;
        }

        final response = await _authService.signUpWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          fullName: _nameController.text.trim(),
        );

        if (response.session == null) {
          setState(() => _status =
              'Conta criada. Verifique seu email para confirmar o acesso.');
          return;
        }

        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/onboarding');
        return;
      }

      final response = await _authService.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      await _syncBiometricPreference();

      final route = await _resolveRouteAfterSignIn(response.user);
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, route);
    } on AuthException catch (error) {
      final message = error.message.toLowerCase();
      if (message.contains('invalid login credentials')) {
        setState(() => _error =
            'E-mail ou senha inválidos. Se os dados estiverem corretos, confira se o app mobile está conectado ao mesmo Supabase da web.');
        return;
      }
      if (message.contains('invalid api key') || message.contains('apikey')) {
        setState(() => _error =
            'Configuração do Supabase inválida no app mobile (SUPABASE_ANON_KEY).');
        return;
      }
      setState(() => _error = error.message);
    } catch (_) {
      setState(() =>
          _error = _isSignUp ? 'Falha ao criar conta' : 'Falha ao autenticar');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<String> _resolveRouteAfterSignIn(User? user) async {
    final path = _authService.resolveAccessPath(user);
    if (path == AccessPath.client) return '/client-area';

    final userId = user?.id;
    if (userId == null || userId.isEmpty) return '/onboarding';

    final setup = await _onboardingService.loadSetupForUser(userId);
    if (setup != null) {
      return '/agenda';
    }
    return '/onboarding';
  }

  Future<void> _syncBiometricPreference() async {
    if (!_biometricAvailable) return;

    if (_useBiometricOnThisDevice) {
      await _biometricAuthService.enable(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      setState(() => _biometricEnabled = true);
      return;
    }

    if (_biometricEnabled) {
      await _biometricAuthService.disable();
      if (!mounted) return;
      setState(() => _biometricEnabled = false);
    }
  }

  Future<void> _signInWithBiometrics() async {
    setState(() {
      _loading = true;
      _error = null;
      _status = null;
    });

    try {
      final credentials =
          await _biometricAuthService.authenticateAndLoadCredentials();
      if (credentials == null) {
        setState(() {
          _error =
              'Nao foi possivel validar sua biometria neste dispositivo. Entre com email e senha.';
          _useBiometricOnThisDevice = false;
        });
        return;
      }

      _emailController.text = credentials.email;
      _passwordController.text = credentials.password;

      final response = await _authService.signInWithPassword(
        email: credentials.email,
        password: credentials.password,
      );

      final route = await _resolveRouteAfterSignIn(response.user);
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, route);
    } on AuthException catch (error) {
      await _biometricAuthService.disable();
      if (!mounted) return;
      setState(() {
        _biometricEnabled = false;
        _useBiometricOnThisDevice = false;
        _error =
            'A biometria foi desativada porque as credenciais salvas nao sao mais validas. Entre novamente com email e senha. (${error.message})';
      });
    } catch (_) {
      setState(() {
        _error =
            'Falha ao entrar com biometria. Tente novamente ou use email e senha.';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isSignUp ? 'Criar conta' : 'Entrar')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(
                        'assets/brand/agenda-logo.png',
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isSignUp
                        ? 'Crie sua conta para organizar agenda, clientes e confirmacoes em um so lugar.'
                        : 'Entre para acessar sua agenda com seguranca e rapidez.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF66717F),
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => setState(() => _isSignUp = false),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isSignUp
                                ? Colors.transparent
                                : AppColors.primary,
                            foregroundColor:
                                _isSignUp ? AppColors.primary : Colors.white,
                            side: _isSignUp
                                ? const BorderSide(color: AppColors.primary)
                                : null,
                          ),
                          child: const Text('Entrar'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => setState(() => _isSignUp = true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isSignUp
                                ? AppColors.primary
                                : Colors.transparent,
                            foregroundColor:
                                _isSignUp ? Colors.white : AppColors.primary,
                            side: _isSignUp
                                ? null
                                : const BorderSide(color: AppColors.primary),
                          ),
                          child: const Text('Criar usuário'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_isSignUp) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameController,
                      decoration:
                          const InputDecoration(labelText: 'Nome completo'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'E-mail'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: !_showPassword,
                    decoration: InputDecoration(
                      labelText: 'Senha',
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setState(() => _showPassword = !_showPassword),
                        icon: Icon(
                          _showPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        tooltip:
                            _showPassword ? 'Ocultar senha' : 'Mostrar senha',
                      ),
                    ),
                  ),
                  if (_isSignUp) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirmController,
                      obscureText: !_showConfirmPassword,
                      decoration: InputDecoration(
                        labelText: 'Confirmar senha',
                        suffixIcon: IconButton(
                          onPressed: () => setState(() =>
                              _showConfirmPassword = !_showConfirmPassword),
                          icon: Icon(
                            _showConfirmPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          tooltip: _showConfirmPassword
                              ? 'Ocultar senha'
                              : 'Mostrar senha',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text(
                    'Acesso exclusivo para profissionais e equipes de empresas.',
                    style: TextStyle(color: Color(0xFF66717F)),
                  ),
                  if (!_isSignUp && _biometricAvailable) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusMd),
                        border: Border.all(color: const Color(0xFFD7DDE4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.secondary
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.fingerprint_rounded,
                                  color: AppColors.secondary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Biometria no dispositivo',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _biometricEnabled
                                          ? 'Use sua biometria para entrar sem digitar a senha.'
                                          : 'Ative para reutilizar com seguranca suas credenciais neste aparelho.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: const Color(0xFF66717F),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _useBiometricOnThisDevice,
                                onChanged: _loading
                                    ? null
                                    : (value) {
                                        setState(() =>
                                            _useBiometricOnThisDevice = value);
                                      },
                              ),
                            ],
                          ),
                          if (_biometricEnabled) ...[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _loading ? null : _signInWithBiometrics,
                              icon: const Icon(Icons.fingerprint_rounded),
                              label: const Text('Entrar com biometria'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    child: Text(
                      _loading
                          ? (_isSignUp ? 'Criando...' : 'Entrando...')
                          : (_isSignUp ? 'Criar conta' : 'Entrar'),
                    ),
                  ),
                  if (_status != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        border: Border.all(
                            color: AppColors.secondary.withValues(alpha: 0.35)),
                      ),
                      child: Text(_status!,
                          style: const TextStyle(color: Color(0xFF0F4D50))),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        border: Border.all(
                            color: AppColors.danger.withValues(alpha: 0.35)),
                      ),
                      child: Text(_error!,
                          style: const TextStyle(color: Color(0xFF702621))),
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
