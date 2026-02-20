import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_exception.dart';

class DevicePushTokenItem {
  const DevicePushTokenItem({
    required this.id,
    required this.provider,
    required this.platform,
    required this.token,
    required this.active,
    required this.lastSeenAt,
  });

  final String id;
  final String provider;
  final String platform;
  final String token;
  final bool active;
  final DateTime lastSeenAt;

  factory DevicePushTokenItem.fromJson(Map<String, dynamic> json) {
    return DevicePushTokenItem(
      id: json['id'] as String,
      provider: (json['provider'] as String?) ?? 'expo',
      platform: (json['platform'] as String?) ?? 'android',
      token: (json['token'] as String?) ?? '',
      active: json['active'] == true,
      lastSeenAt: DateTime.tryParse(json['last_seen_at'] as String? ?? '')
              ?.toUtc() ??
          DateTime.now().toUtc(),
    );
  }
}

class PushTokenService {
  PushTokenService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String currentPlatformLabel() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      default:
        return 'web';
    }
  }

  Future<String> _tenantId() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AppException(
        message: 'Usuário não autenticado.',
        code: 'unauthenticated',
      );
    }
    final profile = await _client
        .from('profiles')
        .select('tenant_id')
        .eq('id', user.id)
        .maybeSingle();
    final tenantId = profile?['tenant_id'] as String?;
    if (tenantId == null || tenantId.isEmpty) {
      throw const AppException(
        message: 'Não foi possível resolver o tenant do usuário.',
        code: 'tenant_not_found',
      );
    }
    return tenantId;
  }

  Future<List<DevicePushTokenItem>> listOwnTokens() async {
    final response = await _client
        .from('device_push_tokens')
        .select('id, provider, platform, token, active, last_seen_at')
        .order('last_seen_at', ascending: false);
    return List<Map<String, dynamic>>.from(response)
        .map(DevicePushTokenItem.fromJson)
        .toList();
  }

  Future<void> upsertOwnToken({
    required String provider,
    required String token,
    String? platform,
  }) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) {
      throw const AppException(
        message: 'Informe o token de push.',
        code: 'token_required',
      );
    }

    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AppException(
        message: 'Usuário não autenticado.',
        code: 'unauthenticated',
      );
    }

    final tenantId = await _tenantId();
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final effectivePlatform = (platform ?? currentPlatformLabel()).toLowerCase();

    final existing = await _client
        .from('device_push_tokens')
        .select('id')
        .eq('provider', provider)
        .eq('token', cleanToken)
        .eq('user_id', user.id)
        .maybeSingle();

    if (existing != null && existing['id'] is String) {
      await _client
          .from('device_push_tokens')
          .update({
            'active': true,
            'platform': effectivePlatform,
            'last_seen_at': nowIso,
            'updated_at': nowIso,
          })
          .eq('id', existing['id'] as String);
      return;
    }

    await _client.from('device_push_tokens').insert({
      'tenant_id': tenantId,
      'user_id': user.id,
      'provider': provider,
      'platform': effectivePlatform,
      'token': cleanToken,
      'active': true,
      'last_seen_at': nowIso,
      'updated_at': nowIso,
    });
  }

  Future<void> setTokenActive({
    required String tokenId,
    required bool active,
  }) async {
    await _client.from('device_push_tokens').update({
      'active': active,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', tokenId);
  }

  Future<void> copyTokenToClipboard(String token) async {
    await Clipboard.setData(ClipboardData(text: token));
  }
}

