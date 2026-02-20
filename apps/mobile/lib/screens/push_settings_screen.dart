import 'package:flutter/material.dart';

import '../models/app_exception.dart';
import '../services/push_token_service.dart';
import '../theme/app_theme.dart';

class PushSettingsScreen extends StatefulWidget {
  const PushSettingsScreen({super.key});

  @override
  State<PushSettingsScreen> createState() => _PushSettingsScreenState();
}

class _PushSettingsScreenState extends State<PushSettingsScreen> {
  final _pushTokenService = PushTokenService();
  final _tokenController = TextEditingController();

  bool _loading = false;
  String? _error;
  String? _status;
  String _provider = 'expo';
  List<DevicePushTokenItem> _tokens = [];

  @override
  void initState() {
    super.initState();
    _loadTokens();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _loadTokens() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tokens = await _pushTokenService.listOwnTokens();
      if (!mounted) return;
      setState(() => _tokens = tokens);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Erro ao carregar tokens de push');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveToken() async {
    setState(() {
      _loading = true;
      _error = null;
      _status = null;
    });
    try {
      await _pushTokenService.upsertOwnToken(
        provider: _provider,
        token: _tokenController.text,
      );
      await _loadTokens();
      if (!mounted) return;
      _tokenController.clear();
      setState(() => _status = 'Token de push salvo com sucesso');
    } on AppException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Erro ao salvar token de push');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleActive(DevicePushTokenItem item, bool active) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _pushTokenService.setTokenActive(tokenId: item.id, active: active);
      await _loadTokens();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Erro ao atualizar status do token');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDateTime(DateTime utcDate) {
    final local = utcDate.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final yyyy = local.year.toString();
    final hh = local.hour.toString().padLeft(2, '0');
    final mi = local.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy $hh:$mi';
  }

  String _tokenPreview(String token) {
    if (token.length <= 22) return token;
    return '${token.substring(0, 12)}...${token.substring(token.length - 8)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificações push'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loading ? null : _loadTokens,
            icon: const Icon(Icons.refresh),
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
                    'Registrar token de dispositivo',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Cole o token gerado pelo app de push para habilitar alertas no dispositivo.',
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _provider,
                    decoration: const InputDecoration(labelText: 'Provider'),
                    items: const [
                      DropdownMenuItem(value: 'expo', child: Text('Expo')),
                      DropdownMenuItem(value: 'fcm', child: Text('FCM')),
                      DropdownMenuItem(value: 'apns', child: Text('APNS')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _provider = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _tokenController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Token do dispositivo',
                      hintText: 'Ex.: ExponentPushToken[...]',
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _loading ? null : _saveToken,
                    child: Text(_loading ? 'Salvando...' : 'Salvar token'),
                  ),
                  if (_status != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        border: Border.all(
                          color: AppColors.secondary.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        _status!,
                        style: const TextStyle(color: Color(0xFF0F4D50)),
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        border: Border.all(
                          color: AppColors.danger.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Color(0xFF702621)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tokens cadastrados',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (_loading && _tokens.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_tokens.isEmpty)
                    const Text('Nenhum token cadastrado para este usuário.')
                  else
                    ..._tokens.map(
                      (item) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                          border: Border.all(color: const Color(0xFFD7DDE4)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${item.provider.toUpperCase()} • ${item.platform.toUpperCase()}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                                Switch(
                                  value: item.active,
                                  onChanged: _loading
                                      ? null
                                      : (value) => _toggleActive(item, value),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(_tokenPreview(item.token)),
                            const SizedBox(height: 4),
                            Text(
                              'Última atividade: ${_formatDateTime(item.lastSeenAt)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () =>
                                    _pushTokenService.copyTokenToClipboard(
                                  item.token,
                                ),
                                child: const Text('Copiar token'),
                              ),
                            ),
                          ],
                        ),
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

