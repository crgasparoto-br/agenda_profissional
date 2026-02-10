import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
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

  bool _loading = false;
  bool _isSignUp = false;
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  String? _status;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _nameController.dispose();
    super.dispose();
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
          setState(() => _error = 'As senhas nao conferem');
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

      if (!mounted) return;
      final path = _authService.resolveAccessPath(response.user);
      Navigator.pushReplacementNamed(
        context,
        path == AccessPath.client ? '/client-area' : '/onboarding',
      );
    } on AuthException catch (error) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isSignUp ? 'Criar conta' : 'Login')),
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
                          child: const Text('Criar usuario'),
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
                    decoration: const InputDecoration(labelText: 'Email'),
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
