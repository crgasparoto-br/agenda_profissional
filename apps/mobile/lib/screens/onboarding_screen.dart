import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
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
  bool _bootstrapping = true;
  bool _isInitialized = false;
  String? _userId;
  String? _tenantId;
  String? _logoUrl;
  Uint8List? _logoBytes;
  String? _logoExt;
  String? _logoMime;
  String? _error;
  String? _status;

  static const _allowedMime = {
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'webp': 'image/webp',
    'svg': 'image/svg+xml',
  };

  @override
  void dispose() {
    _tenantNameController.dispose();
    _fullNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadContext();
  }

  Future<void> _loadContext() async {
    final user = _authService.currentUser;
    if (user == null) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    if (_authService.resolveAccessPath(user) == AccessPath.client) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/client-area');
      return;
    }

    _userId = user.id;

    try {
      final setup = await _onboardingService.loadSetupForUser(user.id);
      if (!mounted) return;

      if (setup != null) {
        _isInitialized = true;
        _tenantId = setup.tenantId;
        _tenantType = setup.tenantType;
        _tenantNameController.text = setup.tenantName;
        _fullNameController.text = setup.fullName;
        _phoneController.text = setup.phone ?? '';
        _logoUrl = setup.logoUrl;
      } else {
        final prefill = (user.userMetadata?['full_name'] ?? '') as String;
        _fullNameController.text = prefill;
      }
    } catch (error) {
      _error = 'Erro ao carregar configuração: $error';
    } finally {
      if (mounted) {
        setState(() => _bootstrapping = false);
      }
    }
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: false,
      withData: true,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'svg'],
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      setState(() => _error = 'Não foi possível ler o arquivo do logotipo.');
      return;
    }

    final ext = (file.extension ?? '').toLowerCase();
    final mime = _allowedMime[ext];
    if (mime == null) {
      setState(() => _error = 'Formato inválido. Use PNG, JPG, WEBP ou SVG.');
      return;
    }

    if (bytes.length > 5 * 1024 * 1024) {
      setState(() => _error = 'Logo muito grande. Limite de 5MB.');
      return;
    }

    setState(() {
      _error = null;
      _logoBytes = bytes;
      _logoExt = ext;
      _logoMime = mime;
    });
  }

  Future<String?> _uploadLogoIfNeeded(String tenantId) async {
    if (_logoBytes == null || _logoExt == null || _logoMime == null) return _logoUrl;
    final nextUrl = await _onboardingService.uploadTenantLogo(
      tenantId: tenantId,
      bytes: _logoBytes!,
      extension: _logoExt!,
      contentType: _logoMime!,
    );
    return nextUrl;
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
      _status = null;
    });

    try {
      final tenantName = _tenantNameController.text.trim();
      final resolvedFullName = _tenantType == TenantType.individual
          ? tenantName
          : _fullNameController.text.trim();

      if (tenantName.length < 2) {
        setState(() => _error = 'Nome profissional ou da empresa inválido.');
        return;
      }
      if (resolvedFullName.length < 2) {
        setState(() => _error = 'Nome completo inválido.');
        return;
      }

      if (_isInitialized && _tenantId != null && _userId != null) {
        final nextLogoUrl = await _uploadLogoIfNeeded(_tenantId!);
        await _onboardingService.updateSetup(
          userId: _userId!,
          tenantId: _tenantId!,
          tenantType: _tenantType,
          tenantName: tenantName,
          fullName: resolvedFullName,
          phone: _phoneController.text.trim(),
          logoUrl: nextLogoUrl,
        );

        setState(() {
          _logoUrl = nextLogoUrl;
          _logoBytes = null;
          _logoExt = null;
          _logoMime = null;
          _status = 'Configuração atualizada com sucesso.';
        });
        return;
      }

      final result = await _onboardingService.bootstrapTenant(
        BootstrapTenantInput(
          tenantType: _tenantType,
          tenantName: tenantName,
          fullName: resolvedFullName,
          phone: _phoneController.text.trim(),
        ),
      );

      var createdLogoUrl = _logoUrl;
      if (_logoBytes != null) {
        createdLogoUrl = await _uploadLogoIfNeeded(result.tenantId);
        if (createdLogoUrl != null) {
          await _onboardingService.updateTenantLogoUrl(
            tenantId: result.tenantId,
            logoUrl: createdLogoUrl,
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _status = 'Configuração inicial concluída.';
        _logoUrl = createdLogoUrl;
      });
      Navigator.pushReplacementNamed(context, '/menu');
    } on AppException catch (error) {
      setState(() => _error = error.message);
    } catch (error) {
      setState(() => _error = 'Erro ao salvar configuração: $error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Widget _buildLogoPreview() {
    if (_logoBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(_logoBytes!, width: 56, height: 56, fit: BoxFit.cover),
      );
    }

    if (_logoUrl != null && _logoUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          _logoUrl!,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Image.asset(
            'assets/brand/agenda-logo.png',
            width: 56,
            height: 56,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        'assets/brand/agenda-logo.png',
        width: 56,
        height: 56,
        fit: BoxFit.cover,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_bootstrapping) {
      return Scaffold(
        appBar: AppBar(title: const Text('Configuração inicial')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuração inicial'),
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
                  Text(
                    _isInitialized ? 'Mantenha os dados da sua organização' : 'Configure sua conta',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isInitialized
                        ? 'Atualize os dados da configuração inicial e identidade visual.'
                        : 'Escolha o tipo de conta e inicie seus agendamentos.',
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<TenantType>(
                    initialValue: _tenantType,
                    decoration: const InputDecoration(labelText: 'Tipo de conta'),
                    items: const [
                      DropdownMenuItem(
                        value: TenantType.individual,
                        child: Text('Individual (PF)'),
                      ),
                      DropdownMenuItem(
                        value: TenantType.group,
                        child: Text('Equipe / Empresa (PJ)'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _tenantType = value ?? TenantType.individual;
                        if (_tenantType == TenantType.individual) {
                          _fullNameController.text = _tenantNameController.text;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tenantNameController,
                    decoration: const InputDecoration(labelText: 'Nome profissional ou da empresa'),
                    onChanged: (value) {
                      if (_tenantType == TenantType.individual) {
                        _fullNameController.text = value;
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  if (_tenantType == TenantType.group)
                    TextField(
                      controller: _fullNameController,
                      decoration: const InputDecoration(labelText: 'Nome completo'),
                    ),
                  if (_tenantType == TenantType.group) const SizedBox(height: 12),
                  TextField(
                    controller: _phoneController,
                    decoration: const InputDecoration(labelText: 'Telefone'),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _pickLogo,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: const Text('Selecionar logotipo'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildLogoPreview(),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _logoBytes != null
                              ? 'Nova logo selecionada. Salve para aplicar.'
                              : _logoUrl != null
                                  ? 'Logo atual da organização.'
                                  : 'Sem logo customizada. Será usada a padrão.',
                        ),
                      ),
                    ],
                  ),
                  if (_status != null) ...[
                    const SizedBox(height: 12),
                    Text(_status!, style: const TextStyle(color: AppColors.secondary)),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
                      ),
                      child: Text(_error!, style: const TextStyle(color: Color(0xFF702621))),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    child: Text(
                      _loading
                          ? 'Processando...'
                          : _isInitialized
                              ? 'Salvar configurações'
                              : 'Concluir configuração',
                    ),
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
